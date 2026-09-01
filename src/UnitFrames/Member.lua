local ADDON, ns = ...

local Member = {}
ns.GroupMember = Member

--------------------------------------------------------------------------
-- One party or raid member's block
--
-- The same block UnitFrames/Skin.lua draws over the player and target frames,
-- at the same default size, because they are the same instrument and a party
-- frame that does not match the player frame reads as a second addon.
--
-- Nothing in here knows there is a header, an order or a raid, and nothing in
-- here reads a setting. What one block is drawn from arrives as one table at
-- layout time, which is the same seam UnitFrames/Cast.lua sits on and is what
-- lets UnitFrames/Group.lua be about attributes and slots and nothing else.
--
-- The one real difference from the skin is what is underneath. The skin borrows
-- Blizzard's own status bars because they belong to a frame it must hand back;
-- here the button is empty when the header makes it, so the gauges are
-- ns.UI.Gauge's own and the whole block is on the grid with nothing to convert.
--
-- Every widget write on the tick is guarded on the value already on the frame.
-- Forty of these on a raid at five ticks a second is where that stops being a
-- style rule and starts being the difference you can feel.
--------------------------------------------------------------------------

local Unit = ns.Unit
local Color = Unit.Color
local Role = Unit.Role
local Gauge = ns.UI.Gauge
local Flow = ns.UI.Flow

-- How much of the block the health bar takes, less the three hairlines that
-- cross it. The skin's number, because it is the skin's block.
local HEALTH_SHARE = 0.70
local HAIRLINES = 3
local TEXT_PAD = 4

-- The glyph's share of the bar it is written in, and the range it may land in.
-- Taken off the bar rather than fixed, because the same code draws a 34 pixel
-- party block and a 22 pixel raid one.
local TEXT_SHARE = 0.72
local TEXT_FLOOR, TEXT_CEILING = 7, 14

local BACKDROP = Color.backdrop
local NAME_TEXT = Color.text.name
local VALUE_TEXT = Color.text.value
local IDLE = Color.reaction.idle

-- The four states that all draw the same way: the fill goes to the track colour
-- and the name says which. Out of range is in the list on purpose. A member you
-- cannot reach and a member who is not there are the same fact as far as the
-- next thing you were going to press is concerned, and the slot is what says
-- who it is, which is the whole point of a fixed order.
local OFFLINE, GHOST, DEAD, AWAY = "offline", "ghost", "dead", "out of range"

local UnitExists = UnitExists
local UnitName = UnitName
local UnitInRange = _G.UnitInRange
local UnitIsConnected = _G.UnitIsConnected
local UnitIsGhost = _G.UnitIsGhost
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost

--------------------------------------------------------------------------
-- Building one
--------------------------------------------------------------------------

-- Three frame levels, and they are the whole z-order: the box carries the
-- backdrop and the outline, the two gauges sit one above it, and every string
-- sits one above them. Font strings under a status bar is exactly what the
-- first version of the skin shipped.
local BOX, GAUGE, TOP = 0, 1, 2

-- Everything this file draws hangs off the button as `wk`, and it is handed out
-- rather than kept in a table here for the reason PlayerCast.Bar is: what was
-- drawn has to be readable from a macro and from the harness, and a block that
-- landed in the wrong place is one field lookup rather than another round of
-- inference.
function Member.Build(button)
	if button.wk then
		return button.wk
	end

	local block = {}
	button.wk = block

	block.box = CreateFrame("Frame", nil, button)
	block.box:EnableMouse(false)
	local backdrop = ns.Fill(block.box, "BACKGROUND",
		BACKDROP[1], BACKDROP[2], BACKDROP[3], BACKDROP[4])
	backdrop:SetAllPoints()
	block.box.edges = ns.Outline(block.box, IDLE[1], IDLE[2], IDLE[3], 1)

	-- The square the role icon sits in, and the hairline down its inner edge.
	-- The divider is the square's own column rather than a cell of its own, so
	-- the square and the gauge read as one strip with a line down it rather than
	-- as two boxes that happen to touch.
	block.slot = CreateFrame("Frame", nil, block.box)
	block.slot:EnableMouse(false)
	block.divider = ns.Fill(block.box, "BORDER", IDLE[1], IDLE[2], IDLE[3], 1)

	-- Blizzard's own role art, so nothing here is cropped the way a spell icon
	-- is: this sheet is a grid of whole cells and Unit/Role.lua hands over the
	-- one this member wants.
	block.roleIcon = block.slot:CreateTexture(nil, "ARTWORK")
	ns.UI.Crisp(block.roleIcon)

	block.health = Gauge.New(block.box)
	block.rail = Gauge.New(block.box)

	block.top = CreateFrame("Frame", nil, block.box)
	block.top:EnableMouse(false)
	block.nameText = ns.UI.Label(block.top, TEXT_CEILING, NAME_TEXT, "LEFT", ns.UI.FLAT)
	block.healthText = ns.UI.Label(block.top, TEXT_CEILING, VALUE_TEXT, "RIGHT", ns.UI.FLAT)

	return block
end

--------------------------------------------------------------------------
-- Laying one out
--------------------------------------------------------------------------

-- The whole inside of the block, in one row of three: the role icon's square,
-- the gauge, and one pixel of nothing on the far edge for the box's own outline
-- to draw into.
--
-- A member with no power draws no rail rather than an empty one, and the health
-- bar takes the room back. `skip` is how ns.UI.Flow says that, and the rail is
-- hidden alongside, because a skipped node keeps whatever anchors it last had.
local function Frames(block, px, wide, tall, rails)
	local side = tall
	-- Whole pixels, because the two gauges have to add up to the square
	-- exactly: health plus power plus the three hairlines is the side, and a
	-- fractional share leaves a seam along one of them that reads as a
	-- rendering fault.
	local gauges = side - HAIRLINES
	local health, power = math.floor(gauges * HEALTH_SHARE), 0
	if rails then
		power = gauges - health
	else
		-- The hairline between the two gauges goes back to the health bar along
		-- with the rail, or a block with no power carries a pixel of backdrop
		-- along its bottom edge that no other block has.
		health = gauges + 1
	end

	block.rail:SetShown(rails)
	Flow.Arrange(block.box, {
		direction = "row", align = "stretch",
		width = (side + wide) * px, height = side * px,
		{ frame = block.slot, width = side * px, align = "stretch",
			direction = "row", pad = { 0, px, 0, px },
			{ grow = 1 }, { frame = block.divider, width = px } },
		{ direction = "column", grow = 1, gap = px, align = "stretch",
			pad = { 0, px, 0, px },
			{ frame = block.health, height = health * px },
			{ frame = block.rail, height = power * px, skip = not rails } },
		{ width = px },
	})
	return health
end

-- The name on the left of the gauge and the percent on its right, both on the
-- health bar's middle line.
--
-- The name is pinned to the number rather than given a width, so a long name
-- yields to the reading. Floored to a whole pixel: half of an odd bar is half a
-- pixel, and a glyph asked for at half a pixel is rasterised across two.
local function Strings(block, px, health)
	local size = math.min(math.max(math.floor(health * TEXT_SHARE), TEXT_FLOOR),
		TEXT_CEILING)
	local font = ns.UI.Font(size * px, ns.UI.FLAT)
	block.nameText:SetFontObject(font)
	block.healthText:SetFontObject(font)

	local pad = TEXT_PAD * px
	local mid = -(1 + math.floor(health / 2)) * px

	block.healthText:ClearAllPoints()
	block.healthText:SetPoint("RIGHT", block.box, "TOPRIGHT", -pad, mid)
	block.nameText:ClearAllPoints()
	block.nameText:SetPoint("LEFT", block.slot, "TOPRIGHT", pad, mid)
	block.nameText:SetPoint("RIGHT", block.healthText, "LEFT", -pad, 0)
end

-- Everything a setting can move, for one member. Never called from the tick:
-- this runs at login, whenever a number in the panel changes, whenever the
-- roster moves and whenever the grid moves under the frame.
--
-- The unit is read here rather than trusted from last time, because the header
-- re-points a button at somebody else when the group changes and this is the
-- pass that follows it.
--
-- `look` is what one block is drawn from, and it is the whole of what this file
-- knows about the settings:
--
--   width   the gauge, in pixels
--   height  the block, and the role icon's square is the same again
--   role    what Unit/Role.lua says this member is playing
--   icons   whether the role icon is drawn at all
--   range   whether a member you cannot reach drains
--   preview there is nobody behind this block, so ask the client nothing
--   rails   whether a preview block carries a power rail
--
-- One table rather than five arguments, and one table reused by the caller
-- rather than one per member: this runs over forty blocks on a raid relayout
-- and every field but the role is the same for all of them.
function Member.Place(button, look)
	local block = button.wk
	if not block then
		return
	end
	local px = ns.Pixel(button)
	local wide, tall = look.width, look.height
	-- The size is written on the button as well as by the header's own snippet,
	-- because the snippet only ever runs on a button the header has just made
	-- and these two numbers are settings. A button that existed before the
	-- slider moved is still the size it was born.
	button:SetSize((tall + wide) * px, tall * px)

	-- A preview block has nobody behind it, so it says for itself whether it
	-- carries a rail and never asks the client about a unit it does not have.
	block.unit = not look.preview and button:GetAttribute("unit") or nil
	local rails = look.preview and look.rails ~= false or false
	if block.unit and UnitExists(block.unit) then
		rails = select(2, Unit.Power(block.unit)) > 0
	end
	block.rails = rails

	-- Pinned to the button's own corner and given the size, rather than stretched
	-- across it with SetAllPoints. That is what Skin.lua does with its block and
	-- the reason is the same: a frame sized by two opposing anchors has a
	-- rectangle only the client knows, and every size in this addon is one the
	-- addon can measure.
	block.box:ClearAllPoints()
	block.box:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	block.box:SetSize((tall + wide) * px, tall * px)
	block.box:SetFrameLevel(button:GetFrameLevel() + BOX)
	block.health:SetFrameLevel(button:GetFrameLevel() + GAUGE)
	block.rail:SetFrameLevel(button:GetFrameLevel() + GAUGE)
	block.top:ClearAllPoints()
	block.top:SetAllPoints(block.box)
	block.top:SetFrameLevel(button:GetFrameLevel() + TOP)
	ns.EdgeSize(block.box.edges, px)

	local health = Frames(block, px, wide, tall, rails)
	Strings(block, px, health)

	local sheet, left, right, top, bottom = Role.Art(look.role)
	block.roleIcon:ClearAllPoints()
	block.roleIcon:SetPoint("TOPLEFT", block.slot, "TOPLEFT", px, -px)
	block.roleIcon:SetPoint("BOTTOMRIGHT", block.slot, "BOTTOMRIGHT", -px, px)
	block.roleIcon:SetTexture(sheet)
	block.roleIcon:SetTexCoord(left, right, top, bottom)
	block.roleIcon:SetShown(look.icons ~= false)

	-- Carried on the block rather than read on the tick, so the tick asks
	-- nothing about the settings. Turning it off is a relayout, which is what
	-- every other switch on this page already is.
	block.range = look.range ~= false
	Member.Clear(button)
end

--------------------------------------------------------------------------
-- The tick
--
-- Five times a second, the same rate the skin runs at and for the same reason
-- it does not use events: the names that carry health and power have been
-- renamed twice between these two clients and a missed one is a bar that lies.
--------------------------------------------------------------------------

-- Everything this block last drew, forgotten. Every field, rather than the ones
-- that look like they matter: a field left behind is a write that will not
-- happen the next time the same value comes round, and the symptom is a block
-- carrying the last member's name for as long as the new one stands in it.
function Member.Clear(button)
	local block = button.wk
	if not block then
		return
	end
	block.tint, block.shade, block.hue = nil, nil, nil
	block.percent, block.power, block.label = nil, nil, nil
	block.dr, block.dg, block.db = nil, nil, nil
end

-- Which of the four states this member is in, or nothing at all.
--
-- Every call is probed by name. Nothing installed on this machine calls
-- UnitInRange, UnitIsGhost or UnitIsDeadOrGhost, and a client missing one has
-- to lose that state rather than raise once per member five times a second.
function Member.Shade(unit, range)
	if type(UnitIsConnected) == "function" and not UnitIsConnected(unit) then
		return OFFLINE
	end
	if type(UnitIsGhost) == "function" and UnitIsGhost(unit) then
		return GHOST
	end
	if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost(unit) then
		return DEAD
	end
	if range and type(UnitInRange) == "function" then
		local within, checked = UnitInRange(unit)
		if checked and not within then
			return AWAY
		end
	end
	return nil
end

-- The hairline down the square's inner edge, guarded on the three channels
-- rather than on the table they came out of.
--
-- Colour identity is what every other guard in the addon compares, and it
-- cannot be used here: the edge is ns.Unit.Color.Dim's shared scratch table, so
-- its identity is the same on every call and every colour it ever holds.
function Member.Divider(block, r, g, b)
	if block.dr ~= r or block.dg ~= g or block.db ~= b then
		block.dr, block.dg, block.db = r, g, b
		block.divider:SetColorTexture(r, g, b, 1)
	end
end

-- The fill, the spent track behind it and the five hairlines, in one colour.
--
-- Dim writes into one shared scratch table and the next call overwrites it, so
-- the fill is painted before the edge colour is asked for. That is the contract
-- Unit/Color.lua states and this is the one place in the addon that leans on
-- both halves of it in one function.
function Member.Paint(block, tint, shade)
	if shade then
		Gauge.Paint(block.health, block.health.track, Color.Dim(tint, Color.track))
	else
		Gauge.Paint(block.health, block.health.track, tint)
	end
	local edge = Color.Dim(tint, Color.edgeDim)
	ns.Recolor(block.box.edges, edge)
	Member.Divider(block, edge[1], edge[2], edge[3])
end

-- Health and power, compared as the integers that get drawn.
--
-- The bar is written as a whole percent rather than as the raw fraction, which
-- is a guard as well as a quantiser: a member losing one point out of four
-- thousand must not move a fill that is still 99 percent, and at 168 pixels
-- wide one percent is under two of them. Nothing on this block animates, so
-- there is no motion to lose.
function Member.Numbers(block, unit)
	local _, _, percent = Unit.Health(unit)
	if block.percent ~= percent then
		block.percent = percent
		block.health:SetValue(percent >= 0 and percent / 100 or 0)
		block.healthText:SetText(percent >= 0 and (percent .. "%") or "")
	end

	if not block.rails then
		return
	end
	local power, maxPower, powerType = Unit.Power(unit)
	local drawn = maxPower > 0 and math.floor(power / maxPower * 100) or -1
	if block.power ~= drawn then
		block.power = drawn
		block.rail:SetValue(drawn >= 0 and drawn / 100 or 0)
	end
	local hue = (maxPower > 0 and Color.power[powerType]) or IDLE
	if block.hue ~= hue then
		block.hue = hue
		Gauge.Paint(block.rail, block.rail.track, hue)
	end
end

-- The name, or the word that says why there is no reading to take.
function Member.Label(block, unit, shade)
	local text = shade or UnitName(unit) or ""
	if block.label ~= text then
		block.label = text
		block.nameText:SetText(text)
	end
end

-- One member, redrawn.
--
-- The unit is read off the button every pass rather than trusted from the last
-- layout. The header only re-points a button out of combat, so this should
-- never move between two ticks, and one attribute read per member is cheaper
-- than being wrong about which person's health is on the screen.
function Member.Update(button)
	local block = button.wk
	if not block then
		return
	end
	local unit = button:GetAttribute("unit")
	if block.unit ~= unit then
		block.unit = unit
		Member.Clear(button)
	end
	if not unit or not UnitExists(unit) then
		return
	end

	local shade = Member.Shade(unit, block.range)
	local tint = Color.OfUnit(unit)
	if block.tint ~= tint or block.shade ~= shade then
		block.tint, block.shade = tint, shade
		Member.Paint(block, tint, shade)
	end

	Member.Numbers(block, unit)
	Member.Label(block, unit, shade)
end

--------------------------------------------------------------------------

-- One block filled in for somebody who is not there, which is what
-- UnitFrames/Group.lua stands in the slots while the frames are unlocked and
-- you are not in a group.
--
-- Every write the tick would have made, made once from a table instead of from
-- a unit. It goes through the same Paint and the same widgets, so what you are
-- placing is the block you will get and not a drawing of one, and it writes the
-- guards as well as the values so a block that later takes a real member repaints
-- rather than keeping a made up name.
--
-- Not on the HOT list and not on a tick: this runs when you unlock the frames
-- and when a setting moves under them.
function Member.Preview(button, member)
	local block = button.wk
	if not block then
		return
	end

	local tint = Color.Class(member.class)
	block.tint, block.shade = tint, nil
	Member.Paint(block, tint, nil)

	block.label = member.name
	block.nameText:SetText(member.name)
	block.percent = member.health
	block.health:SetValue(member.health / 100)
	block.healthText:SetText(member.health .. "%")

	if not block.rails then
		return
	end
	block.power = member.power
	block.rail:SetValue(member.power / 100)
	block.hue = Color.power[member.powerType] or IDLE
	Gauge.Paint(block.rail, block.rail.track, block.hue)
end

-- Whether this member's block still wants the rails it was laid out with. A
-- druid leaving cat form gains a mana bar, and growing one is a relayout rather
-- than a write, so the answer goes back to UnitFrames/Group.lua and is acted on
-- out of combat like every other layout there.
function Member.Rails(button)
	local block = button.wk
	if not block or not block.unit or not UnitExists(block.unit) then
		return true
	end
	return block.rails == (select(2, Unit.Power(block.unit)) > 0)
end
