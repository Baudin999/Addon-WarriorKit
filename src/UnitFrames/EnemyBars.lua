local ADDON, ns = ...

local EnemyBars = {}
ns.EnemyBars = EnemyBars

-- The debuff row, as it ships. Rank 1 IDs, because matching happens on the
-- localised name: every rank counts, another warrior's Sunder shows up, and
-- one entry covers a spell you will re-rank six times.
--
-- This is the starting list and not the list. What a bar tracks is
-- ns.db.barsSpells, which the panel and `bars debuff` edit, because which
-- debuffs matter is a spec question and a fight question. An arms warrior
-- watches Deep Wounds and Mortal Strike; a protection one watches neither and
-- wants the room back.
local DEFAULT_SPELLS = { 7386, 1160, 6343, 772 } -- Sunder Armor, Demoralizing Shout, Thunder Clap, Rend

-- The most a bar will track. The aura scan is forty slots against every name on
-- the list, per mob, five times a second, and the row still has to fit above a
-- bar that is 120 pixels wide at its narrowest. Ten is past anything a warrior
-- applies and cheap enough not to be worth arguing about.
local MAX_SPELLS = 10

-- What the panel's picker offers: every debuff a warrior puts on a mob on these
-- two clients. It is a shortlist and not a limit, because the panel also takes
-- a bare spell ID and so does `bars debuff add`. An ID this client cannot name
-- is dropped from the offer rather than shown as a blank row.
--
-- Every ID here is the ID of the aura that lands on the mob, never the ID of
-- the spell or talent that applies it. For a ranked spell those are the same
-- thing and rank 1 covers every rank. For a proc and for a stun bolted onto a
-- charge they are two different spells with two different names, and the one
-- you find first is the wrong one. Deep Wounds is the case that got shipped
-- broken: 12162 is the talent, the picker offered it, and the square never
-- lit up once. See REPLACED below.
local SUGGESTED = {
	7386,  -- Sunder Armor
	1160,  -- Demoralizing Shout
	6343,  -- Thunder Clap
	772,   -- Rend
	12721, -- Deep Wound, the bleed the Deep Wounds talent applies
	12294, -- Mortal Strike
	1715,  -- Hamstring
	12323, -- Piercing Howl
	355,   -- Taunt
	694,   -- Mocking Blow
	1161,  -- Challenging Shout
	676,   -- Disarm
	12809, -- Concussion Blow
	5246,  -- Intimidating Shout
	7922,  -- Charge Stun, not Charge
	20253, -- Intercept Stun, not Intercept
}

-- An ID this addon offered that no aura will ever carry, and the ID that works
-- in its place.
--
-- 12162 is the Deep Wounds talent. The client names it "Deep Wounds" and
-- ns.SpellName answers happily, so nothing looked wrong: the picker showed the
-- entry, the square drew, and it stayed dark through every fight. The aura that
-- actually lands is 12721, and the client calls that one "Deep Wound",
-- singular. Since the scan matches on the name, one letter was the whole bug.
--
-- Two doors have to be shut, not one. A saved list keeps whatever was already
-- in it, because DEFAULT_SPELLS is read once on a fresh account and never
-- again, so anyone who picked Deep Wounds before this fix still carries the
-- dead ID. And a bare number goes on through the panel's text field and
-- `bars debuff add`, where Wowhead's search for "deep wounds" still lands on
-- the talent first. So the swap happens at login and again inside AddSpell.
local REPLACED = {
	[12162] = 12721, -- the Deep Wounds talent, for the Deep Wound bleed
}

local REFRESH = 0.2

-- Pixels, not units.
--
-- Every widget here sits on the pixel grid in UI/Pixel.lua, where one unit is
-- one physical pixel, so these are the sizes the bar actually occupies on the
-- monitor and they are the same on every monitor. That is the point of the
-- grid and it is also the one thing it costs: a 21 pixel bar is a fifth of the
-- screen height on a laptop and a tenth of it on a 4K panel. `bars zoom` is the
-- answer to that, and it is a whole number because a fractional one would put
-- everything back on half pixels.
--
-- The icon's edge is ns.db.barsIconSize and only the gap between icons is
-- fixed, because the row is as long as the list now and the list is yours.
--
-- This used to say 16 and 32 were the two sizes with a right answer. They are
-- not, and the square has never been drawn at either of them, for two reasons
-- that both live in this part of the addon.
--
-- The square carries a one pixel border and the art is inset inside it, so a
-- 20 pixel setting draws 18 pixels of icon. And ns.UI.Icon crops five texels
-- off each edge to lose the border the client bakes into the art, so 54 texels
-- are sampled and not 64. The client keeps half sized copies and picks the pair
-- nearest what was asked for, so the exact sizes are the ones 54 halves down
-- to, which is 54 and 27 rather than 32 and 16.
--
-- Add the border back and the only setting in the 16 to 32 range that draws one
-- texel per pixel is 29. 20 draws 18 pixels from 54 texels, which is 58 percent
-- of the way between two stored copies and about as blended as it gets.
-- EnemyBars.IconAdvice is where that arithmetic lives, the panel and the slash
-- word both read it, and the harness checks the number it names is really
-- exact rather than trusting a comment.
local ICON_GAP = 4

-- What the square's edge may be set to. Named here rather than written into the
-- panel and the slash word separately, because EnemyBars.IconAdvice has to
-- search the same range those two offer or it will name a size neither reaches.
--
-- The ceiling is 56 rather than a round number. 54 texels survive the crop, the
-- border takes two pixels, so 56 is the largest square where a stored texel
-- still lands on a screen pixel. Above it the client is stretching a 54 texel
-- picture over more pixels than it has and the art goes soft again, so a higher
-- ceiling would only offer sizes that look worse than the one below them.
--
-- It was 32, which was chosen when the row was four fixed icons on a 180 pixel
-- bar. That put the whole top half of the useful range out of reach: `bars zoom`
-- did not work, so the only way to get a big icon was this number, and this
-- number stopped well short of one.
local ICON_MIN, ICON_MAX = 16, 56
local PLATE_BAR_HEIGHT = 21
local LIST_BAR_HEIGHT = 28
local TOP_TEXT = 15
local LEVEL_WIDTH = 32 -- until the first update measures the tag's own text
local LEVEL_PAD = 10
local STRIPE_WIDTH = 5
local PLATE_TEXT = 12
local LIST_TEXT = 14
local COUNT_TEXT_SIZE = 11
local NAME_MAX = 8
local RAID_ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- The look: flat fills, one pixel edges, no gloss and no gradient. The bar is
-- drawn from coloured rectangles rather than from UI-StatusBar, which is the
-- 2007 glass texture and reads like it. Nothing here is a file path, so there
-- is no art asset that has to still exist on this client.
--
-- Every colour on that list now comes out of ns.Unit.Color rather than out of
-- this file. It used to be declared here and declared again in Skin.lua, four
-- of the nine with the same literals typed twice, which held right up until
-- somebody warmed the green on one of them.
local Color = ns.Unit.Color
local Level = ns.Unit.Level
local Roster = ns.Unit.Roster
local Threat = ns.Unit.Threat
local Flow = ns.UI.Flow
-- The gauge itself is UI/Gauge.lua's, and the spent part behind it with it.
-- Both used to be here and the same pair of writes was in Skin.lua as well,
-- down to the fifth and the nine tenths.
local Gauge = ns.UI.Gauge
-- The cast row under the gauge, which is a widget of its own rather than
-- forty more lines in here. It knows nothing about a plate, a list or a pool:
-- this file hands it a widget and it draws on it.
local Cast = ns.Cast

local BACKDROP = Color.backdrop
local EDGE = Color.iconEdge -- debuff icons only, the gauge edge follows threat
local NAME_TEXT = Color.text.name
local TARGET_TEXT = Color.text.target
local HEALTH_TEXT = Color.text.value
local COUNT_TEXT = Color.text.count
local LEVEL_BACK = Color.plate

-- Which bar is yours, said with the one channel nothing else on the bar is
-- using. The fill, the edge and the line above all belong to threat, the tag
-- belongs to what the kill is worth, and the stripe belongs to reaction, so a
-- fourth colour would be a fourth thing to read on a bar that already has
-- three. Alpha is free.
--
-- Attach calls SetIgnoreParentAlpha, which throws away the client's own
-- nameplateNotSelectedAlpha, and that is deliberate rather than an oversight to
-- undo: the plate's alpha also fades with distance and through the plate's own
-- fade in, and in list mode there is no plate and no alpha to inherit. The bars
-- answer this themselves so the answer is the same in both modes and means one
-- thing only.
--
-- With nothing targeted every bar is bright. Dimming the whole screen to say
-- "none of these" is noise, and it is the moment you most want to read threat
-- off a mob that is not yours yet.
local TARGET_ALPHA = 1.00
local OTHER_ALPHA = 0.55

local anchor, header
-- Assigned in the events section at the foot of the file, because it is the
-- event frame's business and that frame is made down there. Declared up here
-- because EnemyBars.Rebuild is what turns the cast events on and off and sits
-- above it. Nothing can reach Rebuild before the file has finished loading.
local CastEvents
local pool, attached, listWidgets = {}, {}, {}
-- Every enemy plate the client currently has up, kept by the add and remove
-- events. GetNamePlates builds a fresh table on every call, and both the list
-- collector and the attach walk wanted one five times a second.
local plateUnits = {}
-- ns.db.barsSpells, resolved. Names because the aura scan matches on the
-- localised name, textures because the row draws them, and both indexed by slot
-- so the tick reads two arrays rather than calling into the spell API. Rebuilt
-- by Retrack whenever the list changes, which is the only time it can.
local trackedNames, trackedIcons = {}, {}
-- IDs on the list this client will not name. Kept rather than deleted, because
-- an account plays both flavours and a spell Era has never heard of should come
-- back when you log into the TBC character it was added on.
local unresolved = {}
local targeters = {}
-- unit token -> that member's pet token. Built once against the fixed token set
-- rather than concatenated per member per tick, for the reason
-- ns.Unit.TargetToken exists.
local PET_FOR = { player = "pet" }
for index = 1, 40 do
	PET_FOR["raid" .. index] = "raidpet" .. index
end
for index = 1, 4 do
	PET_FOR["party" .. index] = "partypet" .. index
end
local haveTarget = false -- gathered once a tick, read by every widget
local firstSeen, seenCounter = {}, 0
local scratch = {}
local stripped, pending = {}, {}
-- Bumped by anything that changes the shape of a widget, which is how a pooled
-- widget knows its layout is stale. See Attach.
local layoutEpoch = 0
local warnedNameplates = false
local warnedThreat = false

--------------------------------------------------------------------------
-- The tracked list
--
-- Which debuffs the row above a bar shows, as an array of spell IDs in the
-- order they are drawn. It lives in ns.db, so it is one setting the panel edits
-- and `bars debuff` edits and neither owns; everything below is the only code
-- allowed to write it, because every write has to be followed by a re-resolve
-- and a relayout and a caller that forgot one would leave a row of blank
-- squares.
--
-- Matching is by localised name, which is what makes rank 1 enough. That is
-- also why two IDs that resolve to the same name are refused: they would be two
-- identical icons lighting up and going out together.
--------------------------------------------------------------------------

-- A fresh table every time. The saved list is mutated in place by Add and
-- Remove, so a caller handed the module's own copy would be editing the
-- default, and the next reset would restore whatever it had been edited into.
-- The border the square draws round its art, one pixel on each of four sides,
-- so the art is two pixels smaller than the number in the panel.
local ICON_BORDER = 2

-- What a debuff square really draws on screen at a given setting, and whether
-- the client has to blend two stored copies to do it.
--
-- Three numbers decide it and two of them are not the setting. The square is
-- barsIconSize design pixels, so the zoom multiplies it. The border is one
-- screen pixel a side and does not scale, so it takes two off whatever that
-- comes to. And ns.UI.Icon crops the art to 54 texels, so the sizes where one
-- stored texel lands on one pixel are 54 and 27 rather than the powers of two
-- everybody expects.
--
-- Returns the drawn size in screen pixels, whether it is exact, and the nearest
-- setting in the range that would be. That last one moves with the zoom: at 1x
-- it is 29, which draws 27 off the half size copy, and at 2x it is 28, which
-- draws 54 off the full size copy and is the sharpest a spell icon gets.
--
-- Read out of ns.UI.IconSizes rather than typed, so changing the crop in
-- UI/Draw.lua moves the advice instead of leaving a stale number in a note.
function EnemyBars.IconAdvice(size, zoom, low, high)
	size = size or ns.db.barsIconSize
	zoom = zoom or ns.db.barsZoom or 1
	low, high = low or ICON_MIN, high or ICON_MAX

	local function drawnAt(setting)
		return setting * zoom - ICON_BORDER
	end

	local wanted = {}
	for _, drawn in ipairs(ns.UI.IconSizes()) do
		wanted[drawn] = true
	end

	local nearest = nil
	for setting = low, high do
		if wanted[drawnAt(setting)] then
			if not nearest or math.abs(setting - size) < math.abs(nearest - size) then
				nearest = setting
			end
		end
	end

	return drawnAt(size), wanted[drawnAt(size)] or false, nearest
end

-- The range the panel and the slash word both offer, so neither writes it out.
function EnemyBars.IconRange()
	return ICON_MIN, ICON_MAX
end

-- The same answer as a sentence, because three callers want to say it and none
-- of them should be re-deriving it.
function EnemyBars.DescribeIcon(size, zoom)
	local drawn, exact, nearest = EnemyBars.IconAdvice(size, zoom)
	if exact then
		return ("%d screen pixels of art inside the border, one stored texel per pixel")
			:format(drawn)
	end
	if not nearest then
		return ("%d screen pixels of art inside the border, blended from two stored copies, and nothing in this range is exact at this zoom")
			:format(drawn)
	end
	return ("%d screen pixels of art inside the border, blended from two stored copies. %d is the size that is not")
		:format(drawn, nearest)
end

function EnemyBars.DefaultSpells()
	local list = {}
	for index, spellID in ipairs(DEFAULT_SPELLS) do
		list[index] = spellID
	end
	return list
end

function EnemyBars.Spells()
	return ns.db.barsSpells
end

function EnemyBars.Suggestions()
	return SUGGESTED
end

function EnemyBars.MaxSpells()
	return MAX_SPELLS
end

-- Which slot a spell is in, or nil. The panel asks so it can leave a debuff you
-- already track out of the picker.
function EnemyBars.Slot(spellID)
	for index, id in ipairs(ns.db.barsSpells) do
		if id == spellID then
			return index
		end
	end
	return nil
end

-- The IDs the list carries that this client cannot name, so the panel and
-- /wk status can say so rather than leaving a row silently short.
function EnemyBars.Unresolved()
	return unresolved
end

-- Swap every dead ID on the saved list for the one that works, once, at login.
-- It runs before the first Resolve, so no name has been taken off a dead ID yet
-- and nothing downstream has to know this happened. It edits the list and
-- nothing else, because at login the anchor does not exist and a relayout from
-- here would raise. Resolve is the next line in that handler.
--
-- A list that already carries the replacement drops the dead entry rather than
-- keeping both. Two IDs that resolve to one name are two squares lighting up
-- and going out together, which is exactly what AddSpell refuses to create.
function EnemyBars.Repair()
	local list = ns.db.barsSpells
	for index = #list, 1, -1 do
		local live = REPLACED[list[index]]
		if live then
			if EnemyBars.Slot(live) then
				table.remove(list, index)
			else
				list[index] = live
			end
		end
	end
end

local function Resolve()
	local count = 0
	wipe(unresolved)
	for _, spellID in ipairs(ns.db.barsSpells) do
		local name = ns.SpellName(spellID)
		if name then
			count = count + 1
			trackedNames[count] = name
			trackedIcons[count] = ns.SpellTexture(spellID)
		else
			unresolved[#unresolved + 1] = spellID
		end
	end
	-- Trimmed rather than left long, because #trackedNames is what the row
	-- length, the aura scan and the tick all count in.
	for index = #trackedNames, count + 1, -1 do
		trackedNames[index] = nil
		trackedIcons[index] = nil
	end
end

-- The list moved, so every widget's row is the wrong length and every widget is
-- the wrong height. ApplyLayout bumps the epoch and re-lays the bars that are
-- up; the ones in the pool take theirs when they next attach, which is what the
-- epoch is for.
function EnemyBars.Retrack()
	Resolve()
	EnemyBars.ApplyLayout()
	EnemyBars.Rebuild()
end

-- Returns true and the spell's name, or false and the sentence to print.
function EnemyBars.AddSpell(spellID)
	spellID = tonumber(spellID)
	if not spellID or spellID <= 0 or spellID ~= math.floor(spellID) then
		return false, "a spell id is a whole number. It is the last part of the spell's Wowhead address."
	end
	-- Typed the talent, got the bleed. The caller prints the name that comes
	-- back, so the substitution says itself: you asked for Deep Wounds and the
	-- addon tells you Deep Wound is on the bar.
	spellID = REPLACED[spellID] or spellID

	local name = ns.SpellName(spellID)
	if not name then
		return false, ("this client does not know spell %d."):format(spellID)
	end

	local list = ns.db.barsSpells
	for _, id in ipairs(list) do
		if id == spellID or ns.SpellName(id) == name then
			return false, name .. " is already on the bar."
		end
	end
	if #list >= MAX_SPELLS then
		return false, ("the bar tracks %d debuffs at most. Take one off first."):format(MAX_SPELLS)
	end

	list[#list + 1] = spellID
	EnemyBars.Retrack()
	return true, name
end

-- Returns true and the name it took off, or false when the list never had it.
function EnemyBars.RemoveSpell(spellID)
	spellID = tonumber(spellID)
	local list = ns.db.barsSpells
	for index, id in ipairs(list) do
		if id == spellID then
			table.remove(list, index)
			EnemyBars.Retrack()
			return true, ns.SpellName(id) or ("spell " .. id)
		end
	end
	return false
end

function EnemyBars.ResetSpells()
	ns.db.barsSpells = EnemyBars.DefaultSpells()
	EnemyBars.Retrack()
end

-- One line for the panel note and for /wk status: the names, in order, or what
-- is wrong with the list.
function EnemyBars.DescribeSpells()
	if #trackedNames == 0 then
		return "nothing tracked, so the row above each bar is empty"
	end
	local line = table.concat(trackedNames, ", ")
	if #unresolved > 0 then
		line = line .. (", and %d this client cannot name"):format(#unresolved)
	end
	return line
end

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

--------------------------------------------------------------------------
-- Data gathering
--------------------------------------------------------------------------

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
	local _, class = UnitClass(subject)
	local label = ("|c%s%s%s|r"):format(Color.ClassHex(class), owner and "*" or "", ShortName(name))
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
	local targetUnit = ns.Unit.TargetToken(unit)
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
end

-- guid -> "Name *Pet Name", for the line above each bar that says who else is
-- already on this mob.
--
-- Who is in the group no longer comes from here. It used to: this function
-- rebuilt the whole party or raid on every tick, eighty unit queries in a forty
-- man five times a second, and then the threat comparison walked what came out.
-- ns.Unit.Roster already had that list, built on GROUP_ROSTER_UPDATE, because
-- the meters needed the same thing and got it right. What is left here is the
-- half that genuinely does move between two ticks, which is what each member is
-- currently targeting.
local function BuildTargeters()
	wipe(targeters)
	-- Asked once here rather than once per mob in UpdateWidget. It is the same
	-- answer for every bar on the screen and this already runs exactly once a
	-- tick in both modes.
	haveTarget = UnitExists("target")

	local group = Roster.Units()
	for index = 1, #group do
		local unit = group[index]
		Member(unit, PET_FOR[unit])
	end
end

-- The colour and the line of text above the gauge. The colour is the one thing
-- on the widget that is not about health: it paints the gauge, the edge around
-- it and the line above it.
--
-- Both halves of the question live in ns.Unit.Threat now, which is also where
-- the meter reads them. What stays here is the wording, because how a bar
-- phrases a number is the bar's business and shortening a name is presentation.
--
-- While you hold the mob the number that matters is the nearest challenger, not
-- your own permanent 100%.
local function ThreatState(unit)
	local color, percent, challenger = Threat.State(unit)

	-- Vanilla has no threat API. The colour comes from who the mob is swinging
	-- at instead: you, someone else, or nobody yet. That is not threat. It
	-- cannot warn you before a mob turns, only tell you after it has. It is the
	-- honest half of the question that client can answer, and it beats a screen
	-- of identical grey bars.
	if not color then
		local shade, victim, mine = Threat.Swinging(unit)
		if not victim then
			return shade, ""
		end
		return shade, mine and "on you" or ("on " .. ShortName(UnitName(victim)))
	end

	if not percent then
		return color, ""
	end
	if challenger then
		return color, ("%d%% %s"):format(percent, ShortName(UnitName(challenger)))
	end
	return color, ("%d%%"):format(percent)
end

-- The per-slot tables are reused rather than rebuilt, so `found` carries one
-- table per tracked spell for the life of the session and `active` says
-- whether this mob has it. A fresh table per matched debuff per mob per tick
-- is the kind of garbage that shows up as a stutter on a pull rather than as a
-- number on a frame counter.
--
-- A shorter list leaves the tail of `found` behind rather than trimming it. The
-- entries past #trackedNames are never read and never cleared, which costs one
-- table each and saves the tick from caring that the list can move.
local function ScanDebuffs(unit, found)
	for i = 1, #trackedNames do
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

local Text = ns.UI.Label

-- One debuff square. Sized, positioned and given its fonts by LayoutWidget,
-- because all three follow settings that move while the addon is up.
local function IconHolder(widget)
	local holder = CreateFrame("Frame", nil, widget)
	holder.edges = ns.Outline(holder, EDGE[1], EDGE[2], EDGE[3], EDGE[4])
	holder.texture = ns.UI.Icon(holder)
	-- Timer along the bottom edge and stacks in the corner, which leaves the
	-- middle of the art readable. A number across the icon does not.
	holder.timer = Text(holder, PLATE_TEXT, NAME_TEXT, "CENTER")
	holder.timer:SetPoint("BOTTOM", holder, "BOTTOM", 0, 0)
	holder.count = Text(holder, COUNT_TEXT_SIZE, COUNT_TEXT, "RIGHT")
	holder.count:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -1, -1)
	return holder
end

-- The row, fitted to the list. A frame cannot be destroyed on this client, so a
-- shorter list hides its tail rather than freeing it and a longer one grows into
-- squares that are already there: a widget that has carried eight and now
-- carries three keeps five hidden holders for the next time you add one.
--
-- Widgets are pooled and their drawn state survives pooling, so a slot whose art
-- changed has to forget what the tick last put on it. Otherwise slot 2 keeps
-- Rend's stack count after Rend moved to slot 3.
local function FitIcons(widget)
	for index = 1, #trackedNames do
		local holder = widget.icons[index]
		if not holder then
			holder = IconHolder(widget)
			widget.icons[index] = holder
		end
		if holder.shownIcon ~= trackedIcons[index] then
			holder.shownIcon = trackedIcons[index]
			holder.texture:SetTexture(trackedIcons[index])
			holder.shownState, holder.shownSeconds, holder.shownCount = nil, nil, nil
		end
		holder:Show()
	end
	for index = #trackedNames + 1, #widget.icons do
		widget.icons[index]:Hide()
	end
end

local function CreateWidget()
	local widget = CreateFrame("Frame", nil, UIParent)
	widget:EnableMouse(false) -- never steal a click from the nameplate underneath

	-- On the grid, and off whatever scale the plate it ends up parented to
	-- carries. A nameplate is scaled by three client settings at once and the
	-- product is never a whole number, so a bar that inherited it would have
	-- every edge, every icon and every glyph resampled by a fraction. This is
	-- the single call that makes the rest of the file able to say 21 and mean
	-- twenty one pixels.
	ns.UI.Adopt(widget, ns.db.barsZoom)

	-- One framed box, one gauge inside it, and the gauge fills the box. There
	-- used to be a second three pixel bar for threat stacked above the health
	-- bar, which sat empty whenever nothing was pulling and left a dark stripe
	-- along the top that read as an unfinished fill. Threat is a colour now,
	-- on the gauge and on the edge, and a number on the line above.
	local box = CreateFrame("Frame", nil, widget)
	local bg = ns.Fill(box, "BACKGROUND", BACKDROP[1], BACKDROP[2], BACKDROP[3], BACKDROP[4])
	bg:SetAllPoints()
	local idle = Color.threat.idle
	box.edges = ns.Outline(box, idle[1], idle[2], idle[3], 1)
	widget.box = box

	widget.health = Gauge.New(box)

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
	local aggro = Color.aggro.comes
	level.stripe = ns.Fill(level, "ARTWORK", aggro[1], aggro[2], aggro[3], 1)
	level.text = Text(level, PLATE_TEXT, Color.xp.none, "CENTER")
	widget.level = level

	-- Under the gauge, and reserved whether or not this mob ever casts. See the
	-- head of Cast.lua for why it is reserved and why it draws nothing while it
	-- is empty.
	Cast.Build(widget)

	widget.name = Text(widget.health, PLATE_TEXT, NAME_TEXT, "LEFT")
	widget.healthText = Text(widget.health, PLATE_TEXT, HEALTH_TEXT, "RIGHT")
	widget.threatText = Text(widget, PLATE_TEXT, HEALTH_TEXT, "LEFT")

	-- SetRaidTargetIconTexture picks one of eight out of a single sheet, so this
	-- takes the sampling fix without the crop that comes with a spell icon.
	widget.marker = ns.UI.Crisp(widget:CreateTexture(nil, "OVERLAY"))
	widget.marker:SetTexture(RAID_ICON_TEXTURE)
	widget.marker:Hide()

	-- Empty. The row is as long as the list and the list is a setting, so
	-- FitIcons builds it and LayoutWidget calls FitIcons.
	widget.icons = {}

	widget.targetedBy = Text(widget, PLATE_TEXT, HEALTH_TEXT, "CENTER")

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
--
-- This used to be a hundred and eighty lines of SetPoint. It is a tree handed
-- to ns.UI.Flow now, and the widget's own height falls out of the measurement
-- rather than being derived by hand from four other numbers. What that bought,
-- beyond the length: the icon row wraps because the row node says wrap, not
-- because this function works out how many fit and anchors each square to the
-- gauge's corner with the row width subtracted.
--
-- Three things are still anchored by hand below the tree, and the reason is the
-- same for all three: their size is whatever the mob happens to be called or
-- what level it is, so it is not known when the layout runs. A layout that had
-- to re-run on a name change would be a layout running on the tick. See the
-- note at the top of UI/Flow.lua.
--
-- Two conversions, and telling them apart is the whole of why `bars zoom` works
-- now and did not before.
--
-- `unit` turns a number from the constants above into the units this widget is
-- drawn in. On the grid it is 1: a design pixel is a unit, and the zoom on the
-- frame's scale is what makes that unit a 1x1, 2x2 or 3x3 block of screen
-- pixels. Off the grid, on a client with no SetIgnoreParentScale, it is the
-- fraction that keeps the bar the same physical size, which is as close as that
-- client gets.
--
-- `px` is one screen pixel, and it is for hairlines, insets and nothing else.
-- An edge is one pixel at every zoom, the same as every rule in the options
-- window. A design that grows does not want a border that grows with it.
--
-- Every size here used to go through `px`, including the ones that are sizes in
-- the design. On the grid that is a divide by the zoom, the frame's scale
-- multiplies it straight back, and the bar measured 180 by 62 screen pixels at
-- zoom 1, 2 and 3 alike. The setting had never done anything.
local function LayoutWidget(widget, width, onPlate)
	-- Measured here rather than baked into a constant, because the same widget
	-- is laid out on a nameplate and in the list and a reparent can move the
	-- scale under it. Everything below is in these units.
	local px = ns.Pixel(widget)
	local unit = ns.UI.Unit(widget)
	local barHeight = (onPlate and PLATE_BAR_HEIGHT or LIST_BAR_HEIGHT) * unit
	local boxHeight = barHeight + px * 2 -- the gauge, plus the hairline around it
	local iconSize = ns.db.barsIconSize * unit
	local iconGap = ICON_GAP * unit
	local pad = 4 * unit
	local fontSize = math.floor((onPlate and PLATE_TEXT or LIST_TEXT) * unit + 0.5)
	local font = ns.UI.Font(fontSize)

	-- Two strings on this widget have nothing behind them.
	--
	-- The name, the health number and the level tag all sit on an opaque fill, so
	-- an outline is a choice there and contrast is the argument for keeping it.
	-- The threat line and the targeted-by line sit in the gap above the gauge,
	-- over whatever the player happens to be standing on, so the outline is not a
	-- choice: without it a pale number over pale ground is gone.
	--
	-- That makes the outline floor a hard minimum for these two rather than the
	-- switch point ns.UI.NumberFont applies over art. There is no graceful
	-- degradation available, so the size has to come up instead.
	local openFont = ns.UI.Font(math.max(fontSize, ns.UI.OutlineFloor()))

	-- Both numbers on an icon are sized off the icon rather than off the bar,
	-- because the icon is a setting now: a fourteen pixel timer on a sixteen
	-- pixel square covers the art it is annotating.
	-- Both sit on the icon's own art, which is opaque, so they go through
	-- ns.UI.NumberFont: it keeps the outline while the glyph is big enough to
	-- carry one and drops it when it is not.
	local timerFont = ns.UI.NumberFont(math.max(8,
		math.min(fontSize, math.floor(iconSize * 0.6))))
	local countFont = ns.UI.NumberFont(math.max(7,
		math.min(math.floor(COUNT_TEXT_SIZE * unit + 0.5), math.floor(iconSize * 0.5))))

	-- The row, packed right and wrapped.
	--
	-- Right against the gauge's right edge is where it has always been and where
	-- it stays: the icons are what you glance at, the gauge's right end is where
	-- the health number already is, and a row that grew rightwards would walk
	-- off the bar. What is new is that the length is yours, and ten icons at
	-- thirty two pixels is 356 and wider than any bar this addon will draw. So
	-- the row wraps upwards instead of overflowing, every row right aligned
	-- under the one above it, and the bottom row is the one nearest the gauge
	-- and the one that fills first. That is `lineOrder = "up"`.
	FitIcons(widget)
	local count = #trackedNames
	local icons = {
		direction = "row", wrap = true, justify = "end", lineOrder = "up",
		gap = iconGap, width = width, alignX = "start", alignY = "end",
	}
	for index = 1, count do
		local holder = widget.icons[index]
		ns.EdgeSize(holder.edges, px)
		holder.timer:SetFontObject(timerFont)
		holder.count:SetFontObject(countFont)
		holder.texture:ClearAllPoints()
		holder.texture:SetPoint("TOPLEFT", px, -px)
		holder.texture:SetPoint("BOTTOMRIGHT", -px, px)
		icons[index] = { frame = holder, width = iconSize, height = iconSize }
	end

	-- The cast row, under the gauge. What comes back is a node for the tree
	-- below and how tall it is, and the second one is what PlaceOnPlate has to
	-- take back out of its offset: the widget is anchored by its bottom edge,
	-- the gauge used to sit on that edge, and anything reserved below it moves
	-- the health bar up off the mob.
	local castNode, castHeight = Cast.Fit(widget, unit, px, onPlate)
	widget.underGauge = castHeight > 0
		and ns.UI.Round(widget, castHeight + iconGap) or 0

	-- The strip between the gauge and whatever is above it. The threat number
	-- shares it with the bottom row of icons, so it is an icon tall; with
	-- nothing tracked there are no icons to share it with and it is as tall as
	-- its own text, which is the whole of what an empty list costs in height.
	local lineHeight = count > 0 and iconSize
		or math.max(fontSize, ns.UI.OutlineFloor())

	-- Only the bottom line is beside the threat number, so only the bottom line
	-- takes width away from it. Asked of Flow rather than worked out again here,
	-- so there is one rule for where a line breaks.
	local lines = Flow.Lines(icons)
	local bottomWidth = (count > 0 and lines[1]) and lines[1].main or 0

	widget:SetWidth(width)
	widget.onPlate = onPlate -- PlaceOnPlate centres on a plate and not in the list

	Flow.Arrange(widget, {
		direction = "column", width = width, align = "stretch",

		-- Wider than the bar and centred on it, so a long list of names
		-- overhangs both sides evenly rather than clipping on one.
		{ frame = widget.targetedBy, width = width + 60 * unit,
			height = TOP_TEXT * unit, align = "center" },

		{ direction = "column", gap = iconGap, align = "stretch",

			-- Two things in one strip. The icons take the full width to wrap
			-- against and the threat line takes what the bottom line of them
			-- leaves, which is why this is a stack and not a row: in a row each
			-- would reserve space from the other and the icons would wrap early.
			{ direction = "stack",
				{ frame = widget.threatText, alignX = "start", alignY = "end",
					width = math.max(24 * unit, width - bottomWidth - 8 * unit),
					height = lineHeight },
				icons,
			},

			-- The gauge is the inside of the box, less the hairline around it.
			-- It grows rather than carrying a height, so the two hairlines come
			-- off the box's own measurement and the gauge is exactly what is
			-- left however the numbers round.
			{ frame = widget.box, height = boxHeight, pad = px, align = "stretch",
				direction = "column",
				{ frame = widget.health, grow = 1 },
			},

			castNode,
		},
	})

	ns.EdgeSize(widget.box.edges, px)
	widget.threatText:SetFontObject(openFont)
	widget.targetedBy:SetFontObject(openFont)

	--------------------------------------------------------------------------
	-- Sized by their own content, so they are anchored rather than arranged
	--------------------------------------------------------------------------

	widget.healthText:SetFontObject(font)
	widget.healthText:ClearAllPoints()
	widget.healthText:SetPoint("RIGHT", widget.health, "RIGHT", -pad, 0)

	-- The whole inside of the gauge belongs to the name, left edge to health
	-- number, because the tag no longer takes a bite out of it. Pinned to the
	-- number rather than given a width, so a long name yields to it.
	widget.name:SetFontObject(font)
	widget.name:ClearAllPoints()
	widget.name:SetPoint("LEFT", widget.health, "LEFT", pad, 0)
	widget.name:SetPoint("RIGHT", widget.healthText, "LEFT", -pad, 0)

	-- Levelled here rather than at creation, because Attach sets the widget's
	-- frame level after the widget exists and this runs after that.
	local showLevel = ns.db.barsLevel
	widget.level:SetShown(showLevel)
	widget.level:SetFrameLevel(widget.health:GetFrameLevel() + 1)
	widget.level.text:SetFontObject(font)
	widget.level.text:ClearAllPoints()
	-- Shifted right by half the stripe, so the number centres in the space the
	-- stripe leaves rather than in the whole tag. Rounded, because the stripe is
	-- five pixels wide and half of five is half a pixel: the number was landing
	-- across two columns on every bar the addon has ever drawn. Half a pixel off
	-- centre and sharp beats dead centre and smeared.
	widget.level.text:SetPoint("CENTER", widget.level, "CENTER",
		ns.UI.Round(widget, STRIPE_WIDTH * unit / 2), 0)
	widget.level:ClearAllPoints()
	-- Flush against the box and the same height as it, so the tag and the bar
	-- read as one strip with the box's own hairline between them. Pinned by
	-- its right edge, so a wider tag grows leftwards into empty screen and the
	-- gauge never moves under it.
	widget.level:SetPoint("TOPRIGHT", widget.box, "TOPLEFT", 0, 0)
	widget.level:SetPoint("BOTTOMRIGHT", widget.box, "BOTTOMLEFT", 0, 0)
	widget.level:SetWidth(LEVEL_WIDTH * unit)
	widget.level.stripe:ClearAllPoints()
	widget.level.stripe:SetPoint("TOPLEFT", widget.level, "TOPLEFT", 0, 0)
	widget.level.stripe:SetPoint("BOTTOMLEFT", widget.level, "BOTTOMLEFT", 0, 0)
	widget.level.stripe:SetWidth(STRIPE_WIDTH * unit)
	widget.levelTag = nil -- the next update sizes the tag to its own text

	-- Outside the tag when there is a tag, so the two do not want the same
	-- strip of screen. Anchored to the box when there is not, rather than to a
	-- hidden frame, which would leave the icon floating a tag's width out.
	widget.marker:ClearAllPoints()
	widget.marker:SetSize(barHeight + pad, barHeight + pad)
	if showLevel then
		widget.marker:SetPoint("RIGHT", widget.level, "LEFT", -3 * unit, 0)
	else
		widget.marker:SetPoint("RIGHT", widget.box, "LEFT", -3 * unit, 0)
	end

	-- What the client needs to know to stop two of these landing on each other.
	-- Sent in UIParent's units because that is what the nameplate driver counts
	-- in, and only from the plate layout: the list is anchored to the screen and
	-- spaces itself.
	if onPlate then
		local wide = width + (showLevel and widget.level:GetWidth() or 0)
		ns.Plates.SetFootprint(
			ns.UI.Convert(wide, widget, UIParent),
			ns.UI.Convert(widget:GetHeight(), widget, UIParent))
	end
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
	-- Rounded, because half of an odd tag is half a pixel and a widget offset
	-- by half a pixel has every edge, glyph and icon inside it resampled across
	-- two. This is the one offset in the file that is not already a whole
	-- number: it is derived from text the client measured.
	local shift = 0
	if widget.onPlate and ns.db.barsLevel then
		shift = ns.UI.Round(widget, widget.level:GetWidth() / 2)
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
		--
		-- Rounded, and this is the one that mattered. PLATE_BAR_HEIGHT is 21, so
		-- half of it plus one is 11.5, and replace is the default style: every
		-- bar the addon has ever drawn had its own origin half a pixel below a
		-- pixel boundary, and a widget offset by half a pixel has every edge,
		-- every glyph and every icon inside it drawn across two rows. That is
		-- the whole of "the bar does not look crisp". The comment three lines up
		-- from here has said so since the tag shift was rounded; the number
		-- underneath it was never put through the same treatment.
		--
		-- An odd bar cannot be centred on a point and land on a boundary, so
		-- half a pixel of centring is what is given up. It is not visible. The
		-- smear was.
		--
		-- The cast row is subtracted rather than ignored. It is reserved under
		-- the gauge whether or not the mob casts, so without this every bar
		-- would sit a cast row higher than it used to and the health bar, which
		-- is the thing being centred, would no longer be over the mob.
		local unit = ns.UI.Unit(widget)
		widget:SetPoint("BOTTOM", host, "CENTER", shift,
			-ns.UI.Round(widget, (PLATE_BAR_HEIGHT / 2 + 1) * unit)
				- (widget.underGauge or 0)
				+ ns.db.barsOffset * unit)
	else
		widget:SetPoint("BOTTOM", host, "TOP", shift, ns.db.barsOffset * ns.UI.Unit(widget))
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
	-- That fifth is UI/Gauge.lua's now, because the skinned unit frames want
	-- the same one and the two files each had their own copy of it. The edge
	-- takes the colour too, so the frame and the fill say the same thing and
	-- the aggro state is legible at a glance from a bar that is nearly empty.
	local color, label = ThreatState(unit)
	if widget.edgeColor ~= color then
		widget.edgeColor = color
		Gauge.Paint(widget.health, widget.health.track, color)
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
		local tag, xp = Level.Of(unit)
		if widget.levelTag ~= tag then
			widget.levelTag = tag
			widget.level.text:SetText(tag)
			-- ns.UI.Unit inline rather than in a local, because `unit` in this
			-- function is the unit token the tick is about and two meanings of
			-- one word inside one function is how the wrong one gets used.
			widget.level:SetWidth(ns.UI.Round(widget,
				widget.level.text:GetStringWidth()
					+ (LEVEL_PAD + STRIPE_WIDTH) * ns.UI.Unit(widget)))
			PlaceOnPlate(widget) -- the tag changed width, so the centre moved
		end
		if widget.levelColor ~= xp then
			widget.levelColor = xp
			widget.level.text:SetTextColor(xp[1], xp[2], xp[3])
		end

		local reaction = Color.Aggro(unit)
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

	-- Your current target, said twice: brighter than everything else on the
	-- screen, and warm rather than white on the name. The alpha is what you see
	-- from across a pull and the name colour is what confirms it once you are
	-- looking. Both guarded for the same reason as the edge.
	--
	-- The alpha guard compares the number and not isTarget, because it moves on
	-- two things: which mob is yours, and whether you have one at all. Guarding
	-- on isTarget alone would leave every bar dim after you dropped target.
	local isTarget = UnitIsUnit(unit, "target")
	if widget.targeted ~= isTarget then
		widget.targeted = isTarget
		local text = isTarget and TARGET_TEXT or NAME_TEXT
		widget.name:SetTextColor(text[1], text[2], text[3])
	end

	local alpha = (isTarget or not haveTarget) and TARGET_ALPHA or OTHER_ALPHA
	if widget.shownAlpha ~= alpha then
		widget.shownAlpha = alpha
		widget:SetAlpha(alpha)
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
	-- Bounded by the widget as well as by the list. FitIcons makes the row as
	-- long as the list and LayoutWidget calls it, but this runs five times a
	-- second whether or not a layout has happened since the list last moved, and
	-- a nil index on a ticker is a thousand errors a minute rather than one.
	for slot = 1, math.min(#trackedNames, #widget.icons) do
		local holder = widget.icons[slot]
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

	-- What the client says this mob is casting. Last, because it is the one
	-- thing on the widget that is not read out of the unit's own state, and
	-- because the cast events call it again on their own for the unit they
	-- name. Everything it does is guarded in there.
	Cast.Update(widget, unit)
end

--------------------------------------------------------------------------
-- Blizzard nameplate visuals
--
-- The UnitFrame stays shown, because that is the frame the game hit-tests for
-- clicks. Killing it would kill ctrl-click marking and targeting. Only its
-- visible pieces get switched off.
--
-- This used to say the cast bar was deliberately left alone so interrupts
-- stayed visible, and it was right for as long as nothing here drew one. The
-- bars draw their own now, so leaving Blizzard's up is two cast bars for one
-- cast, in two places, disagreeing about where the mob is. It goes with the
-- rest, and only while `bars cast` is on: switch ours off and Blizzard's is
-- what says when to Pummel again.
--------------------------------------------------------------------------

-- ns.Strip and ns.Unstrip in Core do the work, because the artwork part strips
-- Blizzard bar art through the same two calls.

-- `every` is what Restore passes and Strip does not.
--
-- Two of these regions are hidden only while a setting says so, and the list
-- has to be longer on the way back than it was on the way in. Built from the
-- settings in both directions, a plate stripped while `bars marker` was on and
-- restored after it was switched off would keep Blizzard's raid icon hidden for
-- the rest of the session: the walk that was supposed to give it back no longer
-- had it on the list. Nothing said anything and the only symptom was a marker
-- that had gone for good. Restore gives back everything this file has ever
-- taken; ns.Unstrip is a no-op on a region that was never taken, so asking for
-- all of them costs a table lookup.
local function PlateRegions(plate, every)
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
	if every or ns.db.barsMarker then
		regions[#regions + 1] = unitFrame.RaidTargetFrame or unitFrame.raidIcon or unitFrame.RaidTargetIcon
	end
	if every or ns.db.barsCast then
		-- One name and no fallback list. `castBar` is what the nameplate driver
		-- calls it on every flavour of this client, and a second guess at a
		-- PascalCase spelling is how a strip walk ends up handed a method rather
		-- than a frame: the harness models a plate faithfully enough that it
		-- answered one the first time this line asked for `CastBar`.
		regions[#regions + 1] = unitFrame.castBar
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
	for _, region in ipairs(PlateRegions(plate, true) or {}) do
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

	-- Before StripPlate and before the driver has been told anything, because
	-- this is the one moment a plate is still the size the client shipped and
	-- the spacing arithmetic needs that figure.
	ns.Plates.Measure(plate)

	StripPlate(plate)

	local widget = table.remove(pool) or CreateWidget()
	ns.UI.Rezoom(widget, ns.db.barsZoom)
	widget:SetParent(plate)
	widget:SetFrameStrata(plate:GetFrameStrata())
	widget:SetFrameLevel(math.min(plate:GetFrameLevel() + 5, 100))
	if widget.SetIgnoreParentAlpha then
		widget:SetIgnoreParentAlpha(true)
	end

	-- `bars width` pixels, the same figure the list uses, and the same number of
	-- screen pixels on every monitor because the widget is on the grid.
	--
	-- It used to be the width of the plate under it, and that was a loop with no
	-- fixed point. LayoutWidget hands the driver a footprint a tag wider than
	-- the bar, so that the level tag hanging off the left edge still counts as
	-- room; the driver sizes every plate to it; and the next bar measured off a
	-- plate came back changed. Which way it ran depended on the scale the client
	-- puts on a nameplate against the scale it puts on UIParent. Wider every
	-- round on one, narrower every round on another, and a setting change ran it
	-- again. There was never a width the bars settled on, and no setting that
	-- chose one.
	--
	-- LayoutWidget is around sixty anchor, font and size calls, and this runs
	-- for every nameplate the game puts up, which in a busy zone is several a
	-- second. The epoch is what keeps it off that path: anything that changes
	-- the shape bumps it, so a widget coming back out of the pool is laid out
	-- again only when the shape it already has is out of date.
	local width = ns.db.barsWidth * ns.UI.Unit(widget)
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
	-- A pooled widget keeps everything the tick drew on it, which is what the
	-- caches on it are for. A half finished cast is the one piece of that which
	-- is about the mob rather than about the widget, so it does not travel.
	Cast.Clear(widget)
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

-- Walks GetNamePlates, which allocates, so it runs on a rebuild and never on a
-- tick. Everything after this point reads plateUnits, which the add and remove
-- events keep current for free.
local function SyncPlates()
	wipe(plateUnits)
	if not C_NamePlate then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then
			plateUnits[unit] = true
			ns.Plates.Measure(plate)
		end
	end
end

local function AttachAll()
	for unit in pairs(plateUnits) do
		Attach(unit)
	end
end

-- Every tick in list mode used to build a table for the list, a table for the
-- seen set, a table for each mob in it, a closure to add one and a closure to
-- sort them, and hand all of it to the collector a fifth of a second later. At
-- five ticks a second and eight mobs that is around seventy tables and ten
-- closures a second, allocated and dropped, for a list whose contents rarely
-- change. Nothing here allocates now: the entries are reused in place, the two
-- helpers are file scope rather than closures, and the plate list is the one
-- this module already keeps from the add and remove events rather than a fresh
-- table from GetNamePlates.
local collected, collectSeen = {}, {}
local collectCount = 0

local function ByFirstSeen(a, b)
	return a.order < b.order
end

local function Collect(unit)
	if not UnitExists(unit) or UnitIsDead(unit) or not UnitCanAttack("player", unit) then
		return
	end
	local guid = UnitGUID(unit)
	if not guid or collectSeen[guid] then
		return
	end
	collectSeen[guid] = true
	if not firstSeen[guid] then
		seenCounter = seenCounter + 1
		firstSeen[guid] = seenCounter
	end

	collectCount = collectCount + 1
	local entry = collected[collectCount]
	if not entry then
		entry = {}
		collected[collectCount] = entry
	end
	entry.unit, entry.guid, entry.order = unit, guid, firstSeen[guid]
end

-- Returns how many of `collected` are live, not a list. A caller that kept the
-- table past the next tick would be reading the tick after it.
local function CollectUnits()
	wipe(collectSeen)
	collectCount = 0

	Collect("target")
	Collect("focus")
	for unit in pairs(plateUnits) do
		Collect(unit)
	end

	-- Sorting the live prefix of a table that is longer than the prefix would
	-- sort the stale entries in with it, so the tail is trimmed first. table.sort
	-- has no length argument.
	for index = #collected, collectCount + 1, -1 do
		collected[index] = nil
	end
	table.sort(collected, ByFirstSeen)

	if collectCount == 0 and seenCounter > 500 then
		wipe(firstSeen)
		seenCounter = 0
	end
	return collectCount
end

local function UpdateList()
	local shown = math.min(CollectUnits(), ns.db.barsMax)
	local width = ns.db.barsWidth * ns.UI.Unit(anchor)

	for index = 1, shown do
		local widget = listWidgets[index]
		if not widget then
			widget = CreateWidget()
			listWidgets[index] = widget
			widget:SetParent(anchor)
			LayoutWidget(widget, width, false)
			widget:ClearAllPoints()
			if index == 1 then
				widget:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
			else
				widget:SetPoint("BOTTOMLEFT", listWidgets[index - 1], "TOPLEFT", 0, 4)
			end
		end
		UpdateWidget(widget, collected[index].unit, collected[index].guid)
		widget:Show()
	end
	for index = shown + 1, #listWidgets do
		Cast.Clear(listWidgets[index])
		listWidgets[index]:Hide()
	end
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

-- How many bars are actually drawn right now, in whichever mode is running.
-- Read by the performance tab, which cannot say whether 0.31 ms is cheap
-- without it.
function EnemyBars.Count()
	if EnemyBars.Mode() ~= "plates" then
		local shown = 0
		for _, widget in ipairs(listWidgets) do
			if widget:IsShown() then
				shown = shown + 1
			end
		end
		return shown
	end
	local count = 0
	for _ in pairs(attached) do
		count = count + 1
	end
	return count
end

-- The charge marker anchors above our bar when there is one on the plate.
function EnemyBars.WidgetFor(unit)
	return attached[unit]
end

-- One line for /wk status, covering the two things about the bars that are the
-- client's answer rather than a setting: what the grid resolved to, and whether
-- the driver agreed to space plates the way the bars need.
function EnemyBars.Describe()
	return ns.UI.Describe() .. "; " .. ns.Plates.Describe()
end

function EnemyBars.ApplyLayout()
	if not anchor then
		return
	end
	layoutEpoch = layoutEpoch + 1
	local point = ns.db.barsPoint
	anchor:ClearAllPoints()
	anchor:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	ns.UI.Rezoom(anchor, ns.db.barsZoom)
	-- Rezoomed first, because the unit a design pixel occupies is read off the
	-- frame and the zoom is what decides it. Sizing before the rezoom lays the
	-- list out for the zoom it is leaving.
	local unit = ns.UI.Unit(anchor)
	anchor:SetSize(ns.db.barsWidth * unit, 20 * unit)
	for _, widget in ipairs(listWidgets) do
		ns.UI.Rezoom(widget, ns.db.barsZoom)
		LayoutWidget(widget, ns.db.barsWidth * ns.UI.Unit(widget), false)
	end
	-- The bars already sitting on plates take the same width, and nothing else
	-- would reach them: a widget on a plate is laid out when it attaches, and
	-- these are attached. Sized off their own pixel rather than the anchor's,
	-- because a plate widget can be on a zoom of its own until Rebuild runs.
	for _, widget in pairs(attached) do
		ns.UI.Rezoom(widget, ns.db.barsZoom)
		widget.laidWidth = ns.db.barsWidth * ns.UI.Unit(widget)
		widget.laidEpoch = layoutEpoch
		LayoutWidget(widget, widget.laidWidth, true)
		PlaceOnPlate(widget)
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
	SyncPlates()
	for _, widget in ipairs(listWidgets) do
		ns.UI.Rezoom(widget, ns.db.barsZoom)
		widget:Hide()
	end
	if ns.db.bars and EnemyBars.Mode() == "plates" then
		AttachAll()
	end
	-- Only while there is a row for them to reach, and only on a client that
	-- answers for a unit that is not you. See CAST_EVENTS.
	CastEvents(ns.db.bars and ns.db.barsCast and ns.HasCastInfo()
		and EnemyBars.Mode() == "plates")
	ns.Plates.Apply()
	EnemyBars.ApplyLock()
end

-- The cast fills, and nothing else, on every frame.
--
-- Split off EnemyBars.Update rather than folded into it, because the two are
-- different kinds of thing running at different rates. Everything Update draws
-- is a readout, and a readout a fifth of a second stale is one nobody can
-- fault. A cast fill is a moving edge, and a moving edge is an animation: it is
-- drawn on the frame the screen is drawn on or it is drawn in steps. That
-- argument is Swing/Gauges.lua's and the note at the head of it is the long
-- version.
--
-- What this costs when nothing is casting is the walk and one IsShown per bar,
-- because Cast.Sweep's first line is the hidden row returning. GetTime is asked
-- once here rather than once per bar.
function EnemyBars.Sweep()
	if not anchor or not ns.db.bars or not ns.db.barsCast then
		return
	end

	-- Both lists, and no mode check. EnemyBars.Mode reads a CVar, which is a
	-- reasonable thing to do five times a second and not sixty, and it is not
	-- needed: `attached` is empty in list mode and every list widget is hidden
	-- in plate mode, so the walk the mode would have skipped is the walk that
	-- finds nothing anyway.
	local now = GetTime()
	for _, widget in pairs(attached) do
		Cast.Sweep(widget, now)
	end
	for _, widget in ipairs(listWidgets) do
		if widget:IsShown() then
			Cast.Sweep(widget, now)
		end
	end
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

-- The cast events, and what they are and are not for.
--
-- They are not what the feature is built on. ns.CastingInfo is read again for
-- every bar on every tick, so a client that never fires one of these for a
-- nameplate unit draws exactly the same bar a fifth of a second later. That is
-- deliberate after the Deep Wounds bug: a feature whose only source is an event
-- nobody has proved fires is a feature that draws nothing and says nothing.
--
-- What they buy is the fifth of a second. A cast that starts just after a tick
-- is 200 ms old before any bar admits it, and on a one and a half second window
-- that is an eighth of the reason to look.
--
-- Registered only while there is something to draw with them, because
-- registered they wake this frame on every cast every unit the client tracks
-- starts, which in a raid is a great many for the eight of them that land on a
-- mob with a bar. Rebuild is what turns them on and off, so a setting change
-- reaches them for free.
local CAST_EVENTS = {
	"UNIT_SPELLCAST_START",
	"UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_CHANNEL_STOP",
}

local isCastEvent = {}
for _, event in ipairs(CAST_EVENTS) do
	isCastEvent[event] = true
end

local castRegistered = false

CastEvents = function(wanted)
	wanted = wanted and true or false
	if castRegistered == wanted then
		return
	end
	castRegistered = wanted
	for _, event in ipairs(CAST_EVENTS) do
		if wanted then
			events:RegisterEvent(event)
		else
			events:UnregisterEvent(event)
		end
	end
end

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("CVAR_UPDATE")
if C_NamePlate then
	events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
end

events:SetScript("OnEvent", function(_, event, arg1)
	if isCastEvent[event] then
		-- Plate mode only, and the list is not an oversight. A widget in the
		-- list is found by position rather than by unit, so the lookup would be
		-- a walk of every bar for every cast in the zone, to save a fifth of a
		-- second on the mode that runs when nameplates are switched off.
		local casting = attached[arg1]
		if casting then
			Cast.Update(casting, arg1, true)
		end
		return
	end

	if event == "NAME_PLATE_UNIT_ADDED" then
		plateUnits[arg1] = true
		Attach(arg1)
		return
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		plateUnits[arg1] = nil
		Release(arg1)
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		FlushPending()
		ns.Plates.Flush()
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
		ns.Plates.Warn()
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
	EnemyBars.Repair()
	Resolve()
	if #unresolved > 0 then
		ns.Print("these ids on the debuff list are not spells this client knows, so they draw"
			.. " nothing and keep their place: " .. table.concat(unresolved, ", ") .. ".")
	end

	anchor = CreateFrame("Frame", "WarriorKitEnemyBarsAnchor", UIParent)
	-- On the grid too, so a list bar is snapped in both axes rather than only
	-- sized in whole pixels. A bar on a nameplate cannot have this: its origin
	-- is wherever the mob is standing, which is a moving fraction of a pixel no
	-- addon can read or round.
	ns.UI.Adopt(anchor, ns.db.barsZoom)
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
		-- The cast fills first and unthrottled. See EnemyBars.Sweep.
		ns.Perf.Start("cast")
		EnemyBars.Sweep()
		ns.Perf.Stop("cast")

		elapsed = elapsed + delta
		if elapsed >= REFRESH then
			-- The remainder, not zero. Zeroing an accumulator throws away
			-- however far past the interval the frame landed, which turns a
			-- 5 Hz tick into one that fires every fourth 60 Hz frame and every
			-- twelfth 144 Hz one, at rates of 4.6 and 4.8. That is the first
			-- half of what made the swing bar step, and this is the same line.
			elapsed = elapsed % REFRESH
			ns.Perf.Start("bars")
			EnemyBars.Update()
			ns.Perf.Stop("bars")
		end
	end)
end)

-- A resolution change moves every size in this file at once, and a UI scale
-- change moves the nameplates the bars are anchored to. Both come through here
-- rather than through a ticker noticing.
ns.UI.OnRescale(function()
	EnemyBars.ApplyLayout()
	EnemyBars.Rebuild()
end)
