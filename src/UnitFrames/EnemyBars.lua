local ADDON, ns = ...

local EnemyBars = {}
ns.EnemyBars = EnemyBars

-- Rank 1 IDs. Matching happens on the localised name, so every rank counts and
-- another warrior's Sunder shows up too. Add Hamstring (1715), Piercing Howl
-- (12323) or Mocking Blow (694) here if you want them on the bars.
local TRACKED_SPELLS = { 7386, 1160, 6343, 772 } -- Sunder Armor, Demoralizing Shout, Thunder Clap, Rend

local REFRESH = 0.2
local ICON_SIZE = 18
local ICON_GAP = 3
local PLATE_BAR_HEIGHT = 17
local LIST_BAR_HEIGHT = 23
local TOP_TEXT = 12
local LEVEL_WIDTH = 26 -- until the first update measures the tag's own text
local LEVEL_PAD = 8
local STRIPE_WIDTH = 4
local NAME_MAX = 8
local RAID_ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- The look: flat fills, one pixel edges, no gloss and no gradient. The bar is
-- drawn from coloured rectangles rather than from UI-StatusBar, which is the
-- 2007 glass texture and reads like it. Nothing here is a file path, so there
-- is no art asset that has to still exist on this client.
local BACKDROP = { 0.04, 0.04, 0.05, 0.85 }
local EDGE = { 0, 0, 0, 0.90 } -- debuff icons only, the gauge edge follows threat
local TRACK = 0.20 -- the spent part of a bar is its own colour, this dark
local NAME_TEXT = { 0.97, 0.97, 1.00 }
local TARGET_TEXT = { 1.00, 0.90, 0.55 }
local HEALTH_TEXT = { 0.74, 0.76, 0.82 }
local COUNT_TEXT = { 1.00, 0.86, 0.45 }

-- Tanking colours key off how close the nearest challenger is. Not tanking is
-- always red, because the mob is on the wrong person.
local SAFE = { 0.20, 0.72, 0.38 }
local CLOSE = { 0.95, 0.77, 0.25 }
local LOSING = { 0.98, 0.55, 0.20 }
local OFF_YOU = { 0.88, 0.25, 0.28 }
local IDLE = { 0.42, 0.45, 0.52 }

-- What the mob is worth, on the client's own XP scale. These never touch the
-- gauge: the XP scale and the threat scale are the same five colours saying
-- two different things, and a bar carrying both would say neither. Difficulty
-- gets the level tag, threat keeps the fill, the edge and the line above.
local NO_XP = { 0.55, 0.56, 0.60 }
local EASY = { 0.35, 0.85, 0.35 }
local EVEN = { 1.00, 0.92, 0.25 }
local HARD = { 1.00, 0.62, 0.25 }
local DEADLY = { 1.00, 0.35, 0.32 }
local LEVEL_BACK = { 0.03, 0.03, 0.04, 0.95 }

-- Whether it comes for you on its own. Hostile is what nearly everything on
-- the screen is, so it stays deep and quiet; a third bright red on a bar that
-- already carries threat red and five-levels-up red would be one red too many.
-- Neutral is the exception and the one worth seeing from across a room, so it
-- gets the bright colour.
local AGGRO = { 0.55, 0.12, 0.12 }
local PASSIVE = { 0.95, 0.75, 0.15 }

-- The suffix is the whole classification vocabulary, and it is the half of the
-- answer the number cannot give: an elite at your level is not a mob at your
-- level, in XP or in what it does back.
--
--     42   normal        42+   elite        42r   rare        42r+  rare elite
--     ??   a boss, or a level this client will not name
local CLASSIFICATION = {
	elite = "+",
	worldboss = "+",
	rareelite = "r+",
	rare = "r",
}

local anchor, header
local pool, attached, listWidgets = {}, {}, {}
local trackedNames, trackedIcons = {}, {}
local targeters, groupUnits = {}, {}
local firstSeen, seenCounter = {}, 0
local scratch = {}
local stripped, pending = {}, {}
-- Bumped by anything that changes the shape of a widget, which is how a pooled
-- widget knows its layout is stale. See Attach.
local layoutEpoch = 0
local warnedNameplates = false
local warnedThreat = false

-- Cut on a character, not on a byte. Names arrive as UTF-8 and sub() counts
-- bytes, so a plain slice through a two or three byte sequence on a non-English
-- realm draws a replacement glyph on the end of every long name.
local function ShortName(name)
	if not name then
		return "?"
	end
	if #name <= NAME_MAX then
		return name -- every name this short is at most NAME_MAX characters too
	end
	local byte, count = 0, 0
	while byte < #name do
		if count >= NAME_MAX then
			return name:sub(1, byte)
		end
		local lead = name:byte(byte + 1)
		byte = byte + (lead < 0xC0 and 1 or (lead < 0xE0 and 2 or (lead < 0xF0 and 3 or 4)))
		count = count + 1
	end
	return name
end

-- Cached per class rather than formatted per call. There are nine of these on
-- this client and the answer for a class never moves, but this is reached once
-- per group member five times a second and the format call allocated a string
-- every time.
local classColors = {}

local function ClassColor(unit)
	local _, class = UnitClass(unit)
	if not class then
		return "ffffffff"
	end
	local cached = classColors[class]
	if cached then
		return cached
	end
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if not color then
		return "ffffffff"
	end
	cached = ("ff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255)
	classColors[class] = cached
	return cached
end

--------------------------------------------------------------------------
-- Data gathering
--------------------------------------------------------------------------

-- "raid17" .. "target" is a fresh string every time it is asked for, and it is
-- asked for once per group member five times a second. The token set is fixed
-- and under a hundred entries, so it is memoised rather than rebuilt.
local targetTokens = {}

local function TargetToken(unit)
	local token = targetTokens[unit]
	if not token then
		token = unit .. "target"
		targetTokens[unit] = token
	end
	return token
end

-- The coloured label for one group member, cached against the name it was
-- built from. Group composition changes when someone joins or leaves, not five
-- times a second, so the format call and the ShortName slice now run on a
-- change rather than on a tick.
local labels = {}

local function Label(unit, owner)
	local subject = owner or unit
	local name = UnitName(subject)
	local entry = labels[unit]
	if entry and entry.name == name then
		return entry.label
	end
	local label = ("|c%s%s%s|r"):format(ClassColor(subject), owner and "*" or "", ShortName(name))
	if entry then
		entry.name, entry.label = name, label
	else
		labels[unit] = { name = name, label = label }
	end
	return label
end

-- Hoisted out of BuildTargeters rather than declared inside it, because two
-- closures per call is two closures five times a second for the life of the
-- session. They read the same two module tables either way.
local function Record(unit, owner)
	local targetUnit = TargetToken(unit)
	if not UnitExists(targetUnit) then
		return
	end
	local guid = UnitGUID(targetUnit)
	if not guid then
		return
	end
	local label = Label(unit, owner)
	targeters[guid] = targeters[guid] and (targeters[guid] .. " " .. label) or label
end

local function Member(unit, petUnit)
	Record(unit)
	if UnitExists(petUnit) then
		Record(petUnit, unit)
	end
	if not UnitIsUnit(unit, "player") then
		groupUnits[#groupUnits + 1] = unit
	end
end

-- guid -> "Name *Pet Name", and a fresh roster for threat comparisons.
local function BuildTargeters()
	wipe(targeters)
	wipe(groupUnits)

	Member("player", "pet")
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local unit = "raid" .. i
			if UnitExists(unit) and not UnitIsUnit(unit, "player") then
				Member(unit, "raidpet" .. i)
			end
		end
	else
		for i = 1, 4 do
			if UnitExists("party" .. i) then
				Member("party" .. i, "partypet" .. i)
			end
		end
	end
end

-- Vanilla has no threat API, so on Classic Era the colour comes from who the
-- mob is swinging at instead: you, someone else, or nobody yet. That is not
-- threat. It cannot warn you before a mob turns, only tell you after it has.
-- It is the honest half of the question that client can answer, and it beats a
-- screen of identical grey bars.
local function TargetState(unit)
	local victim = unit .. "target"
	if not UnitExists(victim) then
		return IDLE, ""
	end
	if UnitIsUnit(victim, "player") then
		return SAFE, "on you"
	end
	return OFF_YOU, "on " .. ShortName(UnitName(victim))
end

-- While you hold the mob the number that matters is the nearest challenger,
-- not your own permanent 100%. Returns a colour and a line of text, and the
-- colour is the one thing on the widget that is not about health: it paints
-- the gauge, the edge around it and the line above it.
local function ThreatState(unit)
	if not ns.HasThreat() then
		return TargetState(unit)
	end

	local isTanking, status = ns.Threat("player", unit)
	if status == nil then
		return IDLE, ""
	end

	if isTanking then
		local worst, worstUnit = 0, nil
		for _, member in ipairs(groupUnits) do
			local _, _, percent = ns.Threat(member, unit)
			if percent and percent > worst then
				worst, worstUnit = percent, member
			end
		end
		if not worstUnit then
			return SAFE, ""
		end
		local color = worst >= 90 and LOSING or (worst >= 70 and CLOSE or SAFE)
		return color, ("%d%% %s"):format(worst, ShortName(UnitName(worstUnit)))
	end

	local _, _, percent = ns.Threat("player", unit)
	percent = percent or 0
	return OFF_YOU, ("%d%%"):format(percent)
end

-- Hostile mobs come for you inside their aggro radius. Neutral ones stand
-- there until you hit them. That is the whole question and UnitReaction is the
-- whole answer: 4 is neutral, under it is hostile, over it does not fight you
-- at all and cannot normally reach a bar, since a bar needs UnitCanAttack.
--
-- What the reaction cannot tell you is aggro radius, which shrinks as the mob
-- falls behind your level until a hostile mob well under you walks past
-- without noticing. Read the stripe with the level: deep red on a grey number
-- is a mob that could come and probably will not bother.
local function Reaction(unit)
	local reaction = UnitReaction(unit, "player")
	if not reaction or reaction >= 5 then
		return IDLE
	end
	return reaction == 4 and PASSIVE or AGGRO
end

-- The level tag and the colour that says what killing it is worth. The scale
-- is the client's own quest scale, which is also its XP scale: more than
-- GetQuestGreenRange below you and the mob pays nothing, two either side of
-- you is even, five above is the top of the range.
--
-- A client with no GetQuestGreenRange gets green rather than grey for the mobs
-- below that line. Grey is a claim that the kill is worth zero, and that claim
-- needs the number the shim could not get.
local function Difficulty(unit)
	local level = UnitLevel(unit) or 0
	local tag = level > 0 and tostring(level) or "??"
	local suffix = CLASSIFICATION[ns.Classification(unit) or "normal"]
	if suffix then
		tag = tag .. suffix
	end

	-- A level the client will not name is above yours by definition.
	if level <= 0 then
		return tag, DEADLY
	end

	local diff = level - (UnitLevel("player") or level)
	if diff >= 5 then
		return tag, DEADLY
	elseif diff >= 3 then
		return tag, HARD
	elseif diff >= -2 then
		return tag, EVEN
	end

	local green = ns.GreenRange()
	if green and -diff > green then
		return tag, NO_XP
	end
	return tag, EASY
end

-- The per-slot tables are reused rather than rebuilt, so `found` carries one
-- table per tracked spell for the life of the session and `active` says
-- whether this mob has it. A fresh table per matched debuff per mob per tick
-- is the kind of garbage that shows up as a stutter on a pull rather than as a
-- number on a frame counter.
local function ScanDebuffs(unit, found)
	for i = 1, #TRACKED_SPELLS do
		local slotData = found[i]
		if not slotData then
			slotData = {}
			found[i] = slotData
		end
		slotData.active = false
	end

	local index = 1
	while index <= 40 do
		local name, count, expires, source
		if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
			local aura = C_UnitAuras.GetDebuffDataByIndex(unit, index)
			if not aura then
				break
			end
			name, count, expires, source = aura.name, aura.applications, aura.expirationTime, aura.sourceUnit
		else
			local auraName, _, auraCount, _, _, expirationTime, unitCaster = UnitAura(unit, index, "HARMFUL")
			if not auraName then
				break
			end
			name, count, expires, source = auraName, auraCount, expirationTime, unitCaster
		end

		for slot, trackedName in ipairs(trackedNames) do
			if name == trackedName then
				local slotData = found[slot]
				slotData.active = true
				slotData.count = count or 0
				slotData.expires = expires or 0
				slotData.mine = (source == "player")
			end
		end
		index = index + 1
	end
end

--------------------------------------------------------------------------
-- Widget
--------------------------------------------------------------------------

-- A status bar with a flat fill and a track behind it, both plain colour, so
-- one call recolours the whole gauge.
local function FlatBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	local fill = bar:CreateTexture(nil, "ARTWORK")
	fill:SetColorTexture(1, 1, 1, 1)
	bar:SetStatusBarTexture(fill)
	bar:SetMinMaxValues(0, 1)
	bar.track = bar:CreateTexture(nil, "BACKGROUND")
	bar.track:SetAllPoints()
	return bar
end

-- Outlined rather than shadowed, because these sit over the world and a drop
-- shadow disappears against a dark floor.
local function Text(parent, size, color, justify)
	local text = parent:CreateFontString(nil, "OVERLAY")
	text:SetFont((GameFontNormal:GetFont()), size, "OUTLINE")
	text:SetTextColor(color[1], color[2], color[3])
	text:SetJustifyH(justify or "LEFT")
	-- Guarded the same way the panel guards it. Nothing installed here proves
	-- SetWordWrap exists on 2.5.6, and this runs once per nameplate, so an
	-- absent method would raise per widget rather than once.
	if text.SetWordWrap then
		text:SetWordWrap(false)
	end
	return text
end

local function CreateWidget()
	local widget = CreateFrame("Frame", nil, UIParent)
	widget:EnableMouse(false) -- never steal a click from the nameplate underneath

	-- One framed box, one gauge inside it, and the gauge fills the box. There
	-- used to be a second three pixel bar for threat stacked above the health
	-- bar, which sat empty whenever nothing was pulling and left a dark stripe
	-- along the top that read as an unfinished fill. Threat is a colour now,
	-- on the gauge and on the edge, and a number on the line above.
	local box = CreateFrame("Frame", nil, widget)
	local bg = ns.Fill(box, "BACKGROUND", BACKDROP[1], BACKDROP[2], BACKDROP[3], BACKDROP[4])
	bg:SetAllPoints()
	box.edges = ns.Outline(box, IDLE[1], IDLE[2], IDLE[3], 1)
	widget.box = box

	widget.health = FlatBar(box)

	-- The tag sits outside the box, off the gauge's left end, because inside
	-- the gauge it covered the left end of the fill and that is the end a mob
	-- still has at ten percent. It is a frame of its own rather than a texture
	-- so it can carry its own plate and grow with its text. Dark plate,
	-- coloured number: a filled chip would sit against the gauge in a colour
	-- off the same five and the two would read as one smear.
	local level = CreateFrame("Frame", nil, widget)
	local levelBack = ns.Fill(level, "BACKGROUND",
		LEVEL_BACK[1], LEVEL_BACK[2], LEVEL_BACK[3], LEVEL_BACK[4])
	levelBack:SetAllPoints()
	-- The reaction stripe closes the tag on the left. Same frame, because the
	-- two answer one question between them, what this mob is and what it does
	-- about you, and one setting turns the pair on and off.
	level.stripe = ns.Fill(level, "ARTWORK", AGGRO[1], AGGRO[2], AGGRO[3], 1)
	level.text = Text(level, 10, NO_XP, "CENTER")
	level.text:SetPoint("CENTER", level, "CENTER", STRIPE_WIDTH / 2, 0)
	widget.level = level

	widget.name = Text(widget.health, 10, NAME_TEXT, "LEFT")
	widget.healthText = Text(widget.health, 10, HEALTH_TEXT, "RIGHT")
	widget.threatText = Text(widget, 10, HEALTH_TEXT, "LEFT")

	widget.marker = widget:CreateTexture(nil, "OVERLAY")
	widget.marker:SetTexture(RAID_ICON_TEXTURE)
	widget.marker:Hide()

	widget.icons = {}
	for i = 1, #TRACKED_SPELLS do
		local holder = CreateFrame("Frame", nil, widget)
		holder:SetSize(ICON_SIZE, ICON_SIZE)
		holder.edges = ns.Outline(holder, EDGE[1], EDGE[2], EDGE[3], EDGE[4])
		holder.texture = holder:CreateTexture(nil, "ARTWORK")
		holder.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		holder.texture:SetTexture(trackedIcons[i])
		-- Timer along the bottom edge and stacks in the corner, which leaves
		-- the middle of the art readable. A number across the icon does not.
		holder.timer = Text(holder, 10, NAME_TEXT, "CENTER")
		holder.timer:SetPoint("BOTTOM", holder, "BOTTOM", 0, 0)
		holder.count = Text(holder, 9, COUNT_TEXT, "RIGHT")
		holder.count:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -1, -1)
		widget.icons[i] = holder
	end

	widget.targetedBy = Text(widget, 10, HEALTH_TEXT, "CENTER")

	-- The outline of what actually takes the mouse, drawn only while the frames
	-- are unlocked.
	--
	-- The hit box is Blizzard's UnitFrame and the addon cannot resize it, so
	-- the honest thing is to show where it is. Without this the boundary is
	-- invisible, and a drag that turns the camera over one part of a bar and
	-- refuses over another reads as the addon being flaky rather than as two
	-- rectangles that do not line up.
	local hitbox = CreateFrame("Frame", nil, widget)
	hitbox.edges = ns.Outline(hitbox, 0.95, 0.35, 0.35, 0.9)
	hitbox:Hide()
	widget.hitbox = hitbox

	return widget
end

-- Shown while unlocked, and only when there is a hit box to draw. With
-- clickthrough on there is none: the plate has no mouse and nothing is being
-- taken, so an outline would be claiming something that is not true.
local function ShowHitbox(widget)
	widget.hitbox:SetShown(widget.hitbox.hosted and not ns.db.locked and not ns.db.barsClickThrough)
end

-- Everything stacks upwards from the gauge, which sits on the widget's bottom
-- edge. That way one anchor point places the whole thing. The row above the
-- gauge is shared: threat on the left, debuff icons packed to the right, so
-- neither has to be centred into the other's way.
local function LayoutWidget(widget, width, onPlate)
	-- Measured here rather than baked into a constant, because the same widget
	-- is laid out on a nameplate and in the list and those two do not share a
	-- scale. Everything an edge touches is in these units.
	local px = ns.Pixel(widget)
	local barHeight = onPlate and PLATE_BAR_HEIGHT or LIST_BAR_HEIGHT
	local boxHeight = barHeight + px * 2 -- the gauge, plus the hairline around it
	local iconRow = #TRACKED_SPELLS * ICON_SIZE + (#TRACKED_SPELLS - 1) * ICON_GAP
	local textSize = onPlate and 10 or 12
	local font = (GameFontNormal:GetFont())

	widget:SetWidth(width)
	widget:SetHeight(boxHeight + ICON_GAP + ICON_SIZE + TOP_TEXT)
	widget.onPlate = onPlate -- PlaceOnPlate centres on a plate and not in the list

	widget.box:ClearAllPoints()
	widget.box:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", 0, 0)
	widget.box:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 0, 0)
	widget.box:SetHeight(boxHeight)
	ns.EdgeSize(widget.box.edges, px)

	-- Pinned to all four corners rather than given a height, so the gauge is
	-- exactly the inside of the box however the numbers round.
	widget.health:ClearAllPoints()
	widget.health:SetPoint("TOPLEFT", widget.box, "TOPLEFT", px, -px)
	widget.health:SetPoint("BOTTOMRIGHT", widget.box, "BOTTOMRIGHT", -px, px)

	widget.healthText:SetFont(font, textSize, "OUTLINE")
	widget.healthText:ClearAllPoints()
	widget.healthText:SetPoint("RIGHT", widget.health, "RIGHT", -4, 0)

	-- Levelled here rather than at creation, because Attach sets the widget's
	-- frame level after the widget exists and this runs after that.
	local showLevel = ns.db.barsLevel
	widget.level:SetShown(showLevel)
	widget.level:SetFrameLevel(widget.health:GetFrameLevel() + 1)
	widget.level.text:SetFont(font, textSize, "OUTLINE")
	widget.level:ClearAllPoints()
	-- Flush against the box and the same height as it, so the tag and the bar
	-- read as one strip with the box's own hairline between them. Pinned by
	-- its right edge, so a wider tag grows leftwards into empty screen and the
	-- gauge never moves under it.
	widget.level:SetPoint("TOPRIGHT", widget.box, "TOPLEFT", 0, 0)
	widget.level:SetPoint("BOTTOMRIGHT", widget.box, "BOTTOMLEFT", 0, 0)
	widget.level:SetWidth(LEVEL_WIDTH)
	widget.level.stripe:ClearAllPoints()
	widget.level.stripe:SetPoint("TOPLEFT", widget.level, "TOPLEFT", 0, 0)
	widget.level.stripe:SetPoint("BOTTOMLEFT", widget.level, "BOTTOMLEFT", 0, 0)
	widget.level.stripe:SetWidth(STRIPE_WIDTH)
	widget.levelTag = nil -- the next update sizes the tag to its own text

	-- The whole inside of the gauge belongs to the name now, left edge to
	-- health number, because the tag no longer takes a bite out of it.
	widget.name:SetFont(font, textSize, "OUTLINE")
	widget.name:ClearAllPoints()
	widget.name:SetPoint("LEFT", widget.health, "LEFT", 4, 0)
	widget.name:SetPoint("RIGHT", widget.healthText, "LEFT", -4, 0)

	widget.threatText:ClearAllPoints()
	widget.threatText:SetPoint("LEFT", widget, "BOTTOMLEFT", px, boxHeight + ICON_GAP + ICON_SIZE / 2)
	widget.threatText:SetWidth(math.max(24, width - iconRow - 8))

	for i, holder in ipairs(widget.icons) do
		ns.EdgeSize(holder.edges, px)
		holder.texture:ClearAllPoints()
		holder.texture:SetPoint("TOPLEFT", px, -px)
		holder.texture:SetPoint("BOTTOMRIGHT", -px, px)
		holder:ClearAllPoints()
		if i == 1 then
			holder:SetPoint("BOTTOMLEFT", widget.box, "TOPRIGHT", -iconRow, ICON_GAP)
		else
			holder:SetPoint("LEFT", widget.icons[i - 1], "RIGHT", ICON_GAP, 0)
		end
	end

	-- Outside the tag when there is a tag, so the two do not want the same
	-- strip of screen. Anchored to the box when there is not, rather than to a
	-- hidden frame, which would leave the icon floating a tag's width out.
	widget.marker:ClearAllPoints()
	widget.marker:SetSize(barHeight + 4, barHeight + 4)
	if showLevel then
		widget.marker:SetPoint("RIGHT", widget.level, "LEFT", -3, 0)
	else
		widget.marker:SetPoint("RIGHT", widget.box, "LEFT", -3, 0)
	end

	widget.targetedBy:ClearAllPoints()
	widget.targetedBy:SetPoint("TOP", widget, "TOP", 0, 0)
	widget.targetedBy:SetWidth(width + 60)
end

-- The tag hangs off the left of the box, so the box on its own is no longer
-- what sits over the mob. Shifting the whole widget right by half the tag puts
-- the middle of tag-plus-box on the plate's centre, and moves the threat line
-- and the debuff row with it rather than leaving them behind. This runs again
-- every time the tag is remeasured, because "9" and "42r+" are not the same
-- width and neither is the offset that centres them.
--
-- The list gets no offset. There the widgets stack against the anchor's left
-- edge, and boxes that line up under a ragged tag column is the correct look.
local function PlaceOnPlate(widget)
	local plate = widget.plate
	if not plate then
		return
	end
	local shift = 0
	if widget.onPlate and ns.db.barsLevel then
		shift = widget.level:GetWidth() / 2
	end

	-- Anchored to the frame that takes the mouse, not to the plate around it.
	--
	-- That frame is the hit box. Our bar is standing in for it, so the two
	-- should occupy the same strip of screen by construction rather than by a
	-- constant that happened to line up, and where they do not line up the
	-- result is a bar that eats a drag along part of its length and passes it
	-- along the rest, with nothing on screen saying where the boundary is.
	--
	-- Where the UnitFrame is coincident with the plate, which is the usual
	-- shape, this places identically to the old anchor. Where it is not, the
	-- bar moves onto the hit box, which is the point. barsOffset still nudges.
	local host = plate.UnitFrame or plate

	widget:ClearAllPoints()
	if ns.db.barsStyle == "replace" then
		-- Sit where the Blizzard bar was, so the bar still reads as the mob's.
		-- The gauge sits one pixel inside the box, so the gauge and not the
		-- frame around it is what lands on the centre.
		widget:SetPoint("BOTTOM", host, "CENTER", shift, -(PLATE_BAR_HEIGHT / 2 + 1) + ns.db.barsOffset)
	else
		widget:SetPoint("BOTTOM", host, "TOP", shift, ns.db.barsOffset)
	end
end

-- Every write in here is guarded against the value already on the widget.
--
-- The version this replaced guarded the cheap comparisons, the colour tables
-- and the level string, and left the expensive writes open: the name, the
-- health number, the targeted-by line, the track colour, the raid marker and
-- sixteen calls across the four debuff holders. That is about thirty widget
-- writes per mob per tick, and at fifteen plates and five ticks a second it is
-- roughly two thousand font string and texture updates every second, nearly
-- all of them writing the value that was already there.
--
-- A guard costs one comparison. A SetText costs a string measure and a
-- relayout whether or not the text changed. That ratio is why the rule here is
-- that nothing writes without asking first.
--
-- The caches live on the widget rather than in a module table because widgets
-- are pooled and their drawn state survives pooling, so the cache stays true
-- across a release and a reattach. LayoutWidget clears the ones it invalidates.
local function UpdateWidget(widget, unit, guid)
	local now = GetTime()

	local health, healthMax = UnitHealth(unit), UnitHealthMax(unit)
	local scale = healthMax > 0 and healthMax or 1
	if widget.shownMax ~= scale then
		widget.shownMax = scale
		widget.health:SetMinMaxValues(0, scale)
	end
	if widget.shownHealth ~= health then
		widget.shownHealth = health
		widget.health:SetValue(health)
	end

	-- The gauge, the track behind it, the threat line and the edge all take the
	-- one colour, so a single identity guard covers the four of them. These are
	-- the five module constants, so identity is the right comparison.
	--
	-- The spent part of the bar keeps the hue at a fifth of the brightness, so
	-- a mob at ten percent still reads as yours instead of as an empty box.
	-- The edge takes it too, so the frame and the fill say the same thing and
	-- the aggro state is legible at a glance from a bar that is nearly empty.
	local color, label = ThreatState(unit)
	if widget.edgeColor ~= color then
		widget.edgeColor = color
		widget.health:SetStatusBarColor(color[1], color[2], color[3])
		widget.health.track:SetColorTexture(color[1] * TRACK, color[2] * TRACK, color[3] * TRACK, 0.9)
		widget.threatText:SetTextColor(color[1], color[2], color[3])
		ns.Recolor(widget.box.edges, color)
	end
	if widget.shownThreat ~= label then
		widget.shownThreat = label
		widget.threatText:SetText(label)
	end

	-- Guarded on the string and on the colour table's identity, the way the
	-- edge is: this runs five times a second per mob and a level changes when
	-- the mob does.
	if ns.db.barsLevel then
		local tag, xp = Difficulty(unit)
		if widget.levelTag ~= tag then
			widget.levelTag = tag
			widget.level.text:SetText(tag)
			widget.level:SetWidth(widget.level.text:GetStringWidth() + LEVEL_PAD + STRIPE_WIDTH)
			PlaceOnPlate(widget) -- the tag changed width, so the centre moved
		end
		if widget.levelColor ~= xp then
			widget.levelColor = xp
			widget.level.text:SetTextColor(xp[1], xp[2], xp[3])
		end

		local reaction = Reaction(unit)
		if widget.reactionColor ~= reaction then
			widget.reactionColor = reaction
			widget.level.stripe:SetColorTexture(reaction[1], reaction[2], reaction[3], 1)
		end
	end

	local name = UnitName(unit) or ""
	if widget.shownName ~= name then
		widget.shownName = name
		widget.name:SetText(name)
	end

	-- Compared as the integer that gets drawn, not as the ratio behind it. A
	-- mob losing one point of health out of four thousand does not redraw a
	-- number that still says 99%.
	local percent = healthMax > 0 and math.floor(health / healthMax * 100) or -1
	if widget.shownPercent ~= percent then
		widget.shownPercent = percent
		widget.healthText:SetText(percent >= 0 and (percent .. "%") or "")
	end

	local raidIcon = ns.db.barsMarker and GetRaidTargetIndex(unit) or nil
	if widget.shownMarker ~= raidIcon then
		widget.shownMarker = raidIcon
		if raidIcon then
			SetRaidTargetIconTexture(widget.marker, raidIcon)
			widget.marker:Show()
		else
			widget.marker:Hide()
		end
	end

	-- Your current target is marked on the name, because the edge now belongs
	-- to threat. Guarded for the same reason as the edge.
	local isTarget = UnitIsUnit(unit, "target")
	if widget.targeted ~= isTarget then
		widget.targeted = isTarget
		local text = isTarget and TARGET_TEXT or NAME_TEXT
		widget.name:SetTextColor(text[1], text[2], text[3])
	end

	local by = targeters[guid] or ""
	if widget.shownTargeters ~= by then
		widget.shownTargeters = by
		widget.targetedBy:SetText(by)
	end

	-- Three states per holder and not eight: nobody has it, someone else has
	-- it, you have it. The art and the alpha answer only that, so they are
	-- guarded on it and not on the aura. The timer and the stack count move on
	-- their own and carry their own guards, both on the integer that is drawn.
	ScanDebuffs(unit, scratch)
	for slot, holder in ipairs(widget.icons) do
		local aura = scratch[slot]
		local active = aura and aura.active
		local state = active and (aura.mine and "mine" or "theirs") or "none"
		if holder.shownState ~= state then
			holder.shownState = state
			holder.texture:SetDesaturated(state ~= "mine")
			holder:SetAlpha(state == "mine" and 1 or (state == "theirs" and 0.65 or 0.22))
		end

		local seconds = 0
		if active and aura.expires > 0 then
			seconds = math.floor(aura.expires - now)
			if seconds < 0 then
				seconds = 0
			end
		end
		if holder.shownSeconds ~= seconds then
			holder.shownSeconds = seconds
			holder.timer:SetText(seconds > 0 and tostring(seconds) or "")
		end

		local count = active and aura.count or 0
		if holder.shownCount ~= count then
			holder.shownCount = count
			holder.count:SetText(count > 1 and tostring(count) or "")
		end
	end
end

--------------------------------------------------------------------------
-- Blizzard nameplate visuals
--
-- The UnitFrame stays shown, because that is the frame the game hit-tests for
-- clicks. Killing it would kill ctrl-click marking and targeting. Only its
-- visible pieces get switched off, and the cast bar is deliberately left
-- alone so interrupts stay visible.
--------------------------------------------------------------------------

-- ns.Strip and ns.Unstrip in Core do the work, because the artwork part strips
-- Blizzard bar art through the same two calls.

local function PlateRegions(plate)
	local unitFrame = plate.UnitFrame
	if not unitFrame then
		return nil
	end
	local regions = {
		unitFrame.healthBar or unitFrame.HealthBarsContainer,
		unitFrame.name,
		unitFrame.LevelFrame,
		unitFrame.ClassificationFrame,
		unitFrame.selectionHighlight,
		unitFrame.aggroHighlight,
	}
	if ns.db.barsMarker then
		regions[#regions + 1] = unitFrame.RaidTargetFrame or unitFrame.raidIcon or unitFrame.RaidTargetIcon
	end
	return regions
end

-- A plate is a hole in the camera, and the hole is not ours. Our widget calls
-- EnableMouse(false) on itself and none of its children ever take the mouse,
-- so what swallows a button over a bar is the UnitFrame underneath: a mouse
-- enabled secure button, which is exactly how a click on a plate targets and
-- where ctrl-click marking gets its unit.
--
-- A mouse enabled frame takes every button that lands on it, so the only lever
-- here used to be the whole plate or none of it, and the camera drag was the
-- price of click targeting. SetPassThroughButtons is the lever the client
-- actually offers: the frame keeps the mouse, and the buttons named in the
-- call fall through to whatever is underneath, which for a nameplate is the
-- world and the camera.
--
-- Details calls it unguarded in `functions/slash.lua`, which its 20506 TOC
-- loads, for exactly this, its own click-through options. That is what proves
-- it is here. Questie replaces it with a no-op on its world map pin with the
-- comment "hack to avoid in-combat error", which is what proves it is
-- protected, so it goes through the same pending queue as everything else
-- combat refuses.
--
-- Left cannot be the one handed back. The click that targets a plate is a left
-- click on the frame, and a button that passes through never reaches the frame
-- at all, so handing left back is click-through by another name. Right is the
-- one worth giving away: it costs Blizzard's right-click-to-interact and
-- ctrl-right-click cross marking on a plate, and it buys the camera.
local CAMERA_BUTTONS = {
	right = { "RightButton" },
	left = { "LeftButton" },
	both = { "LeftButton", "RightButton" },
}

-- nil until the call has been tried, false on a client without the method,
-- true once one has gone through. Reported by Describe, never inferred.
local passThrough

-- Buttons is one of the CAMERA_BUTTONS tables or nil for "hand nothing back".
-- unpack is avoided because there are at most two and a spread would need a
-- guard of its own on a client that renamed it.
local function PlatePassThrough(unitFrame, buttons)
	if type(unitFrame.SetPassThroughButtons) ~= "function" then
		passThrough = false
		return true -- nothing to apply and nothing to undo
	end
	if ns.Blocked(unitFrame) then
		return false
	end
	local ok
	if not buttons then
		ok = pcall(unitFrame.SetPassThroughButtons, unitFrame)
	elseif buttons[2] then
		ok = pcall(unitFrame.SetPassThroughButtons, unitFrame, buttons[1], buttons[2])
	else
		ok = pcall(unitFrame.SetPassThroughButtons, unitFrame, buttons[1])
	end
	if ok then
		passThrough = true
	end
	return ok
end

-- Whether the pass-through path is doing anything on this client, for the
-- status line. "off" is a setting, "unavailable" is a client.
function EnemyBars.CameraState()
	if ns.db.barsClickThrough then
		return "moot" -- the plate has no mouse at all, so every button is through
	end
	if not CAMERA_BUTTONS[ns.db.barsCamera] then
		return "off"
	end
	if passThrough == false then
		return "unavailable"
	end
	if passThrough == nil then
		return "unproven"
	end
	return ns.db.barsCamera
end

-- Both halves are idempotent and neither touches a plate that is already where
-- it should be. EnableMouse on a secure frame taints it, and a taint on the
-- button that targets is worth carrying only when a setting has asked for it.
--
-- The pass-through state is tracked separately from the mouse state, because a
-- plate arrives mouse enabled and therefore never needs the EnableMouse call,
-- and the old single guard would have skipped the pass-through with it.
local function PlateMouse(plate, enabled, buttons)
	local unitFrame = plate.UnitFrame
	if not unitFrame or not unitFrame.EnableMouse then
		return true
	end
	local complete = true

	if (not unitFrame.wkMouseOff) ~= enabled then
		if ns.Blocked(unitFrame) then
			complete = false
		else
			unitFrame:EnableMouse(enabled)
			unitFrame.wkMouseOff = (not enabled) or nil
		end
	end

	-- Only meaningful while the plate still has the mouse. A plate with no
	-- mouse passes every button already.
	local wanted = enabled and buttons or nil
	if unitFrame.wkPassThrough ~= wanted then
		if PlatePassThrough(unitFrame, wanted) then
			unitFrame.wkPassThrough = wanted
		else
			complete = false
		end
	end

	return complete
end

local function StripPlate(plate)
	local complete = PlateMouse(plate, not ns.db.barsClickThrough, CAMERA_BUTTONS[ns.db.barsCamera])
	local regions = ns.db.barsStyle == "replace" and PlateRegions(plate) or nil
	for _, region in ipairs(regions or {}) do
		if not ns.Strip(region) then
			complete = false
		end
	end
	stripped[plate] = true
	if not complete then
		pending[plate] = "strip" -- finish once combat drops
	else
		pending[plate] = nil
	end
end

-- Unconditional, because the setting that put a plate in this state may have
-- changed since. Both halves no-op on a plate that was never touched.
local function RestorePlate(plate)
	local complete = PlateMouse(plate, true, nil)
	for _, region in ipairs(PlateRegions(plate) or {}) do
		if not ns.Unstrip(region) then
			complete = false
		end
	end
	if complete then
		stripped[plate] = nil
		pending[plate] = nil
	else
		pending[plate] = "restore"
	end
end

local function FlushPending()
	for plate, action in pairs(pending) do
		if action == "strip" then
			StripPlate(plate)
		else
			RestorePlate(plate)
		end
	end
end

--------------------------------------------------------------------------
-- Modes
--------------------------------------------------------------------------

local function NameplatesEnabled()
	if not C_NamePlate then
		return false
	end
	if GetCVarBool then
		return GetCVarBool("nameplateShowEnemies") and true or false
	end
	return true
end

-- "auto" follows the nameplate cvar: plates when they are on, the stacked
-- panel when they are off.
function EnemyBars.Mode()
	local mode = ns.db.barsMode
	if mode == "auto" then
		return NameplatesEnabled() and "plates" or "list"
	end
	return mode
end

local function Attach(unit)
	if not ns.db.bars or EnemyBars.Mode() ~= "plates" then
		return
	end
	if attached[unit] or not UnitCanAttack("player", unit) then
		return
	end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then
		return
	end

	StripPlate(plate)

	local widget = table.remove(pool) or CreateWidget()
	widget:SetParent(plate)
	widget:SetFrameStrata(plate:GetFrameStrata())
	widget:SetFrameLevel(math.min(plate:GetFrameLevel() + 5, 100))
	if widget.SetIgnoreParentAlpha then
		widget:SetIgnoreParentAlpha(true)
	end

	-- LayoutWidget is around sixty anchor, font and size calls, and this runs
	-- for every nameplate the game puts up, which in a busy zone is several a
	-- second. Plates on one client are all the same width, so a widget coming
	-- back out of the pool is nearly always being laid out to the shape it
	-- already has. The epoch is what makes that safe: anything that changes
	-- the shape bumps it, so the cache cannot outlive a setting.
	local width = ns.Measure(plate, "GetWidth")
	width = (width and width > 20) and width or 130
	if widget.laidWidth ~= width or widget.laidEpoch ~= layoutEpoch then
		widget.laidWidth, widget.laidEpoch = width, layoutEpoch
		LayoutWidget(widget, width, true)
	end

	widget.plate = plate
	PlaceOnPlate(widget)

	widget.hitbox:ClearAllPoints()
	widget.hitbox.hosted = plate.UnitFrame ~= nil
	if widget.hitbox.hosted then
		widget.hitbox:SetAllPoints(plate.UnitFrame)
	end
	ShowHitbox(widget)

	widget:Show()
	attached[unit] = widget
end

local function Release(unit)
	local widget = attached[unit]
	if not widget then
		return
	end
	attached[unit] = nil
	widget.plate = nil
	widget:Hide()
	-- Cleared before the reparent below, so no anchor survives pointing at a
	-- plate this widget is about to stop being a child of.
	widget.hitbox:Hide()
	widget.hitbox:ClearAllPoints()
	widget.hitbox.hosted = nil
	widget:ClearAllPoints()
	widget:SetParent(UIParent)
	pool[#pool + 1] = widget
end

local function ReleaseAll()
	for unit in pairs(attached) do
		Release(unit)
	end
	for plate in pairs(stripped) do
		RestorePlate(plate)
	end
end

local function AttachAll()
	if not C_NamePlate then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then
			Attach(unit)
		end
	end
end

local function CollectUnits()
	local list, seenNow = {}, {}

	local function add(unit)
		if not UnitExists(unit) or UnitIsDead(unit) or not UnitCanAttack("player", unit) then
			return
		end
		local guid = UnitGUID(unit)
		if not guid or seenNow[guid] then
			return
		end
		seenNow[guid] = true
		if not firstSeen[guid] then
			seenCounter = seenCounter + 1
			firstSeen[guid] = seenCounter
		end
		list[#list + 1] = { unit = unit, guid = guid, order = firstSeen[guid] }
	end

	add("target")
	add("focus")
	if C_NamePlate then
		for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
			local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
			if unit then
				add(unit)
			end
		end
	end

	table.sort(list, function(a, b)
		return a.order < b.order
	end)

	if #list == 0 and seenCounter > 500 then
		wipe(firstSeen)
		seenCounter = 0
	end
	return list
end

local function UpdateList()
	local list = CollectUnits()
	local shown = math.min(#list, ns.db.barsMax)

	for index = 1, shown do
		local widget = listWidgets[index]
		if not widget then
			widget = CreateWidget()
			listWidgets[index] = widget
			widget:SetParent(anchor)
			LayoutWidget(widget, ns.db.barsWidth, false)
			widget:ClearAllPoints()
			if index == 1 then
				widget:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
			else
				widget:SetPoint("BOTTOMLEFT", listWidgets[index - 1], "TOPLEFT", 0, 4)
			end
		end
		UpdateWidget(widget, list[index].unit, list[index].guid)
		widget:Show()
	end
	for index = shown + 1, #listWidgets do
		listWidgets[index]:Hide()
	end
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

-- The charge marker anchors above our bar when there is one on the plate.
function EnemyBars.WidgetFor(unit)
	return attached[unit]
end

function EnemyBars.ApplyLayout()
	if not anchor then
		return
	end
	layoutEpoch = layoutEpoch + 1
	local point = ns.db.barsPoint
	anchor:ClearAllPoints()
	anchor:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	anchor:SetSize(ns.db.barsWidth, 20)
	for _, widget in ipairs(listWidgets) do
		LayoutWidget(widget, ns.db.barsWidth, false)
	end
end

function EnemyBars.ApplyLock()
	if not anchor then
		return
	end
	local unlocked = not ns.db.locked
	anchor:EnableMouse(unlocked)
	header:SetShown(unlocked and EnemyBars.Mode() == "list")
	for _, widget in pairs(attached) do
		ShowHitbox(widget)
	end
end

-- Called whenever a setting changes the shape of things.
function EnemyBars.Rebuild()
	if not anchor then
		return
	end
	layoutEpoch = layoutEpoch + 1
	ReleaseAll()
	for _, widget in ipairs(listWidgets) do
		widget:Hide()
	end
	if ns.db.bars and EnemyBars.Mode() == "plates" then
		AttachAll()
	end
	EnemyBars.ApplyLock()
end

function EnemyBars.Update()
	if not anchor or not ns.db.bars then
		return
	end

	if EnemyBars.Mode() == "plates" then
		-- The roster walk is the whole party or raid, and in a forty man it is
		-- eighty unit queries. It only feeds the targeted-by line on a bar, so
		-- with no bars up there is nothing to feed and no reason to walk. This
		-- used to run before the mode check, five times a second, in every
		-- zone with the nameplate key switched off.
		if not next(attached) then
			return
		end
		BuildTargeters()
		for unit, widget in pairs(attached) do
			if UnitExists(unit) and UnitCanAttack("player", unit) then
				UpdateWidget(widget, unit, UnitGUID(unit))
			else
				Release(unit)
			end
		end
	else
		BuildTargeters()
		UpdateList()
	end
end

--------------------------------------------------------------------------

local elapsed = 0
local lastMode
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("CVAR_UPDATE")
if C_NamePlate then
	events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
end

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "NAME_PLATE_UNIT_ADDED" then
		Attach(arg1)
		return
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		Release(arg1)
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		FlushPending()
		return
	elseif event == "CVAR_UPDATE" then
		if EnemyBars.Mode() ~= lastMode then
			lastMode = EnemyBars.Mode()
			EnemyBars.Rebuild()
		end
		return
	elseif event == "PLAYER_ENTERING_WORLD" then
		lastMode = EnemyBars.Mode()
		EnemyBars.Rebuild()
		if not warnedNameplates and ns.db.barsMode == "auto" and not NameplatesEnabled() then
			warnedNameplates = true
			ns.Print("enemy nameplates are off, so the bars are running as a panel. Press V for the attached version.")
		end
		if not warnedThreat and ns.db.bars and not ns.HasThreat() then
			warnedThreat = true
			ns.Print("this client has no threat API, so the bars colour by who each mob is hitting instead.")
		end
		return
	end

	-- PLAYER_LOGIN
	for slot, spellID in ipairs(TRACKED_SPELLS) do
		trackedNames[slot] = ns.SpellName(spellID)
		trackedIcons[slot] = ns.SpellTexture(spellID)
	end

	anchor = CreateFrame("Frame", "WarriorKitEnemyBarsAnchor", UIParent)
	anchor:SetMovable(true)
	anchor:RegisterForDrag("LeftButton")
	anchor:SetClampedToScreen(true)
	anchor:SetScript("OnDragStart", function(self)
		if not ns.db.locked then
			self:StartMoving()
		end
	end)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint()
		ns.db.barsPoint = { point, "UIParent", relativePoint, x, y }
	end)

	header = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	header:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
	header:SetText("WarriorKit enemies")
	header:Hide()

	EnemyBars.ApplyLayout()
	EnemyBars.Rebuild()

	events:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed >= REFRESH then
			elapsed = 0
			EnemyBars.Update()
		end
	end)
end)
