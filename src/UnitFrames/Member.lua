local ADDON, ns = ...

local Member = {}
ns.GroupMember = Member

--------------------------------------------------------------------------
-- One party or raid member's tile
--
-- A block of the person's class colour with their name across the top of it,
-- and what they have lost bleached and hatched at the right hand end. Nothing
-- else: no number, no second bar through the middle, no square bolted on the
-- side. You read a tile by how much of it is still the colour, which is a
-- shape rather than a reading and is what makes a wall of forty of them
-- scannable at a glance.
--
-- This replaced a row that was the player block repeated, and the reason is
-- worth writing down. A party block that matched the skin was one gauge among
-- the six already on the screen, and in a raid it was forty gauges: the same
-- instrument the player frame is, at a size nobody can take a reading off,
-- forty times over. The tile is a different instrument on purpose. It is read
-- as an area and not as a length, and the two things it says are who and how
-- much, which are the only two questions a group frame is ever asked.
--
-- The missing end is washed toward white rather than dimmed toward the
-- backdrop, and that is the one decision the whole look hangs off. A dimmed
-- end is a second fill in a duller colour and the eye has to find the join; a
-- bleached and hatched one is plainly an absence, and the join is where the
-- texture starts. ns.Unit.Color.Wash is that direction and ns.Unit.Color.Dim
-- is the other, which is what the four dead states still use.
--
-- Nothing in here knows there is a header, an order or a raid, and nothing in
-- here reads a setting. What one tile is drawn from arrives as one table at
-- layout time, which is the same seam UnitFrames/Cast.lua sits on and is what
-- lets UnitFrames/Group.lua be about attributes and slots and nothing else.
--
-- Every widget write on the tick is guarded on the value already on the frame.
-- Forty of these on a raid at five ticks a second is where that stops being a
-- style rule and starts being the difference you can feel.
--------------------------------------------------------------------------

local Unit = ns.Unit
local Color = Unit.Color
local Role = Unit.Role
local Gauge = ns.UI.Gauge

-- The weave the bleached end is drawn through. One 32 pixel tile repeated at
-- its own size across whatever the bar came out as, rather than stretched to
-- fit it: a stretched hatch is a hatch whose stripe width says how hurt
-- somebody is, and the mark has to read the same on a raid cell and a party
-- tile or it is saying two things at once.
local WEAVE = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Hatch.tga"
local WEAVE_SIDE = 32

-- The tile's own outline, which every rectangle inside it is held off by.
local PAD = 1

-- The power rail along the bottom, as a share of the tile and with a floor
-- under it. Two pixels is the thinnest rail anybody can take a reading off,
-- and at raid size the share alone lands under it.
local RAIL_SHARE = 0.11
local RAIL_FLOOR = 2

-- The role square in the top corner, and where it may land. Taken off the
-- tile's height rather than fixed, because the same code draws a party tile
-- and a raid cell half its size.
--
-- A fifth of the height and not a third. The square is a mark in a corner, not
-- a column of its own, and it shares the top of the tile with the name: any
-- bigger and it is either eating the name's room or sitting under it.
local ROLE_SHARE = 0.22
local ROLE_FLOOR, ROLE_CEILING = 8, 18

-- The name's share of the tile, and the tallest it may get. Its floor is
-- ns.UI.OutlineFloor and is not a number of this file's own: the name sits
-- over the fill at one end of the tile and over the bleached weave at the
-- other, so there is no one colour behind it to read against and the rim is
-- the only thing that works. A rim under the floor closes the hole in a 6, so
-- the floor is where a name can be outlined at all rather than a preference.
local TEXT_SHARE = 0.34
local TEXT_CEILING = 20

-- How far the missing end is washed toward white, and how much of the weave
-- over it is drawn.
local GROUND_WASH = 0.55
local WEAVE_ALPHA = 0.22

-- And what the whole tile keeps when there is nobody in it to read. Under
-- Color.track, so a member who is gone is darker across the tile than a member
-- at one percent is at their spent end, and the two states cannot be confused
-- for each other.
local GROUND_DIM = 0.15

local BACKDROP = Color.backdrop
local NAME_TEXT = Color.text.name
local IDLE = Color.reaction.idle

-- The four states that all draw the same way: the tile goes to the track
-- colour and the name says which. Out of range is in the list on purpose. A
-- member you cannot reach and a member who is not there are the same fact as
-- far as the next thing you were going to press is concerned, and the slot is
-- what says who it is, which is the whole point of a fixed order.
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
-- backdrop and the outline, the two gauges sit one above it, and the name and
-- the role square sit one above them.
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

	block.health = Gauge.New(block.box)

	-- The weave over the ground and under the fill. Both of those are
	-- BACKGROUND inside the bar, so what orders them is a sublevel and not a
	-- frame level, which is the one ordering nothing a caller writes can get
	-- wrong. The fill is on ARTWORK and covers both, so the weave shows exactly
	-- where the health is not and nowhere else.
	block.weave = Gauge.Underlay(block.health, 1)
	block.weave:SetTexture(WEAVE, "REPEAT", "REPEAT")
	block.weave:SetVertexColor(1, 1, 1, WEAVE_ALPHA)

	block.rail = Gauge.New(block.box)

	block.top = CreateFrame("Frame", nil, block.box)
	block.top:EnableMouse(false)

	-- Blizzard's own role art, so nothing here is cropped the way a spell icon
	-- is: this sheet is a grid of whole cells and Unit/Role.lua hands over the
	-- one this member wants.
	block.roleIcon = block.top:CreateTexture(nil, "ARTWORK")
	ns.UI.Crisp(block.roleIcon)

	block.nameText = ns.UI.Label(block.top, ns.UI.OutlineFloor(), NAME_TEXT,
		"CENTER", ns.UI.OUTLINE)
	block.nameText:SetWordWrap(false)

	return block
end

--------------------------------------------------------------------------
-- Laying one out
--------------------------------------------------------------------------

-- The two bars, in whole pixels off the tile's own two numbers.
--
-- A member with no power draws no rail rather than an empty one, and the
-- health bar takes the room back: the seam between them is the backdrop
-- showing through, so a tile with no power is the health bar plus the rail
-- plus the seam and not one pixel of dark along its bottom edge that no other
-- tile has.
--
-- Returns how tall the health bar came out, which is what the weave is
-- repeated across.
local function Bars(block, px, wide, tall, rails)
	local inner = tall - 2 * PAD
	local rail = rails
		and math.max(math.floor(tall * RAIL_SHARE), RAIL_FLOOR) or 0
	local health = rails and (inner - rail - PAD) or inner
	local across = wide - 2 * PAD

	block.health:ClearAllPoints()
	block.health:SetPoint("TOPLEFT", block.box, "TOPLEFT", PAD * px, -PAD * px)
	block.health:SetSize(across * px, health * px)

	block.rail:SetShown(rails)
	block.rail:ClearAllPoints()
	block.rail:SetPoint("BOTTOMLEFT", block.box, "BOTTOMLEFT", PAD * px, PAD * px)
	block.rail:SetSize(across * px, math.max(rail, RAIL_FLOOR) * px)

	-- In design pixels, so the stripe is the same width at every zoom and on
	-- every tile size, which is the whole reason the weave is a tile rather
	-- than a stretched texture.
	block.weave:SetTexCoord(0, across / WEAVE_SIDE, 0, health / WEAVE_SIDE)
	return health
end

-- The role square in the top corner and the name across the top.
--
-- The name is centred on the whole tile and not on the room left beside the
-- square. The tiles are read as a stack, and a title that wanders left and
-- right down the list is a list you have to read rather than scan. What that
-- costs is that a long name reaches the corner the square is in, which is why
-- the square is a fifth of the height rather than a third and why the name
-- carries a rim: the two can overlap for a letter without either being lost.
local function Marks(block, px, tall)
	local mark = math.min(math.max(math.floor(tall * ROLE_SHARE), ROLE_FLOOR),
		ROLE_CEILING)
	block.roleIcon:ClearAllPoints()
	block.roleIcon:SetPoint("TOPLEFT", block.box, "TOPLEFT", PAD * px, -PAD * px)
	block.roleIcon:SetSize(mark * px, mark * px)

	-- Floored to a whole pixel: half of an odd tile is half a pixel, and a
	-- glyph asked for at half a pixel is rasterised across two. The floor is
	-- written into the call as well as into the clamp so the gate can read it,
	-- because a size the gate cannot follow is a rim nobody can say is above
	-- the floor.
	local size = math.min(math.max(math.floor(tall * TEXT_SHARE),
		ns.UI.OutlineFloor()), TEXT_CEILING)
	block.nameText:SetFontObject(
		ns.UI.Font(math.max(size, ns.UI.OutlineFloor()) * px, ns.UI.OUTLINE))

	block.nameText:ClearAllPoints()
	block.nameText:SetPoint("TOPLEFT", block.box, "TOPLEFT", PAD * px, -PAD * px)
	block.nameText:SetPoint("TOPRIGHT", block.box, "TOPRIGHT", -PAD * px, -PAD * px)
end

-- Everything a setting can move, for one member. Never called from the tick:
-- this runs at login, whenever a number in the panel changes, whenever the
-- roster moves and whenever the grid moves under the frame.
--
-- The unit is read here rather than trusted from last time, because the header
-- re-points a button at somebody else when the group changes and this is the
-- pass that follows it.
--
-- `look` is what one tile is drawn from, and it is the whole of what this file
-- knows about the settings:
--
--   width   the tile, in pixels
--   height  the tile, in pixels
--   role    what Unit/Role.lua says this member is playing
--   icons   whether the role square is drawn at all
--   range   whether a member you cannot reach drains
--   preview there is nobody behind this tile, so ask the client nothing
--   rails   whether a preview tile carries a power rail
--
-- One table rather than five arguments, and one table reused by the caller
-- rather than one per member: this runs over forty tiles on a raid relayout
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
	button:SetSize(wide * px, tall * px)

	-- A preview tile has nobody behind it, so it says for itself whether it
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
	block.box:SetSize(wide * px, tall * px)
	block.box:SetFrameLevel(button:GetFrameLevel() + BOX)
	block.health:SetFrameLevel(button:GetFrameLevel() + GAUGE)
	block.rail:SetFrameLevel(button:GetFrameLevel() + GAUGE)
	block.top:ClearAllPoints()
	block.top:SetAllPoints(block.box)
	block.top:SetFrameLevel(button:GetFrameLevel() + TOP)
	ns.EdgeSize(block.box.edges, px)

	Bars(block, px, wide, tall, rails)
	Marks(block, px, tall)

	local sheet, left, right, top, bottom = Role.Art(look.role)
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

-- Everything this tile last drew, forgotten. Every field, rather than the ones
-- that look like they matter: a field left behind is a write that will not
-- happen the next time the same value comes round, and the symptom is a tile
-- carrying the last member's name for as long as the new one stands in it.
function Member.Clear(button)
	local block = button.wk
	if not block then
		return
	end
	block.tint, block.shade, block.hue = nil, nil, nil
	block.percent, block.power, block.label = nil, nil, nil
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

-- The fill, the ground behind it and the outline, in one colour.
--
-- Three answers off one tint, and they are asked for in the order the scratch
-- tables allow. Color.Dim and Color.Wash each write into one table of their
-- own and the next call overwrites it, so every result here is handed straight
-- to a setter before the next one is asked for. That is the contract
-- Unit/Color.lua states and this is the one place in the addon that leans on
-- all of it.
--
-- The weave is not repainted. It is white at a fixed alpha over whatever the
-- ground is, so it takes the class colour from underneath and there is nothing
-- per-unit for the tick to write.
function Member.Paint(block, tint, shade)
	Gauge.Paint(block.health, nil, shade and Color.Dim(tint, Color.track) or tint)
	Gauge.Ground(block.health.track, shade and Color.Dim(tint, GROUND_DIM)
		or Color.Wash(tint, GROUND_WASH))
	ns.Recolor(block.box.edges, Color.Dim(tint, Color.edgeDim))
end

-- Health and power, compared as the integers that get drawn.
--
-- The bar is written as a whole percent rather than as the raw fraction, which
-- is a guard as well as a quantiser: a member losing one point out of four
-- thousand must not move a fill that is still 99 percent, and at a hundred and
-- twenty pixels wide one percent is over one of them. Nothing on this tile
-- animates, so there is no motion to lose.
function Member.Numbers(block, unit)
	local _, _, percent = Unit.Health(unit)
	if block.percent ~= percent then
		block.percent = percent
		block.health:SetValue(percent >= 0 and percent / 100 or 0)
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

-- One tile filled in for somebody who is not there, which is what
-- UnitFrames/Group.lua stands in the slots while the frames are unlocked and
-- you are not in a group.
--
-- Every write the tick would have made, made once from a table instead of from
-- a unit. It goes through the same Paint and the same widgets, so what you are
-- placing is the tile you will get and not a drawing of one, and it writes the
-- guards as well as the values so a tile that later takes a real member
-- repaints rather than keeping a made up name.
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

	if not block.rails then
		return
	end
	block.power = member.power
	block.rail:SetValue(member.power / 100)
	block.hue = Color.power[member.powerType] or IDLE
	Gauge.Paint(block.rail, block.rail.track, block.hue)
end

-- Whether this member's tile still wants the rail it was laid out with. A
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
