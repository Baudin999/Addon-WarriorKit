local ADDON, ns = ...

local Member = {}
ns.GroupMember = Member

--------------------------------------------------------------------------
-- One party or raid member's tile
--
-- A block of the person's class colour with their role at the left end and
-- their name beside it, and what they have lost dimmed at the right hand end
-- the way the player frame's own bar dims it. Nothing else: no number, no
-- second bar through the middle, no square bolted on the side. You read a tile
-- by how much of it is still the colour, which is a shape rather than a reading
-- and is what makes a wall of forty of them scannable at a glance.
--
-- This replaced a row that was the player block repeated, and the reason is
-- worth writing down. A party block that matched the skin was one gauge among
-- the six already on the screen, and in a raid it was forty gauges: the same
-- instrument the player frame is, at a size nobody can take a reading off,
-- forty times over. The tile is a different instrument on purpose. It is read
-- as an area and not as a length, and the two things it says are who and how
-- much, which are the only two questions a group frame is ever asked.
--
-- The missing end is the fill dimmed, which is what every other gauge in the
-- addon keeps behind its fill. It was bleached toward white and hatched for a
-- while, on the argument that a dimmed end reads as a second fill; on the
-- screen the hatch read as a stripe through the tile and the player frame next
-- to it dimmed, and two instruments saying "lost" two ways is one too many.
--
-- Nothing in here knows there is a header, an order or a raid, and nothing in
-- here reads a setting. What one tile is drawn from arrives as one table at
-- layout time, which is the same seam UnitFrames/Cast.lua sits on and is what
-- lets UnitFrames/Group.lua be about attributes and slots and nothing else.
--
-- Every widget write on the tick is guarded on the value already on the frame.
-- Forty of these on a raid at five ticks a second is where that stops being a
-- style rule and starts being the difference you can feel.
--
-- When a tile is drawn is the other half of that, and it is this file's too. A
-- tile registers three unit events against whichever token the header has its
-- button pointed at and marks itself when one arrives, so the pass over forty
-- of them draws the ones something happened to. What is left on the pass for
-- every tile is one UnitInRange, which is the one reading on here the client
-- has no event for.
--------------------------------------------------------------------------

local Unit = ns.Unit
local Color = Unit.Color
local Role = Unit.Role
local Gauge = ns.UI.Gauge

-- The tile's own outline, which every rectangle inside it is held off by.
local PAD = 1

-- The power rail along the bottom, as a share of the tile and with a floor
-- under it. Two pixels is the thinnest rail anybody can take a reading off,
-- and at raid size the share alone lands under it.
local RAIL_SHARE = 0.11
local RAIL_FLOOR = 2

-- The role square at the left end of the tile, as a share of the health bar it
-- stands in, and the name starts this far to the right of it. Taken off the bar
-- rather than fixed, because the same code draws a party tile and a raid cell
-- half its size, and the art is a cell that scales down without going soft.
--
-- Not the whole bar's height, which is what it was. A square the height of the
-- bar is a third of a party tile's width, and the name that has to share the
-- row with it came out as "Rando..." on a five letter name. Seven tenths keeps
-- the art readable from across the screen and hands the rest of the row back to
-- the name, which is the other thing the tile is for. The floor is under the
-- raid cell, where the share alone lands at a size nobody can tell a shield
-- from a sword at.
local ROLE_SHARE = 0.7
local ROLE_FLOOR = 8
local ROLE_GAP = 3

-- The name's share of the tile, and the tallest it may get. Its floor is
-- ns.UI.OutlineFloor and is not a number of this file's own: the name sits
-- over the fill at one end of the tile and over the dimmed end at the other,
-- so there is no one colour behind it to read against and the rim is the only
-- thing that works. A rim under the floor closes the hole in a 6, so the floor
-- is where a name can be outlined at all rather than a preference.
local TEXT_SHARE = 0.34
local TEXT_CEILING = 20

local BACKDROP = Color.backdrop
local NAME_TEXT = Color.text.name
local IDLE = Color.reaction.idle

-- The four states that all drain the tile to the track colour. Three of them
-- put a word where the name was, because a member who is dead or gone is not
-- somebody you are about to press anything on and the word is the reading.
-- Out of range keeps the name: the colour already says you cannot reach them,
-- and who they are is what you need to know to walk the right way.
local OFFLINE, GHOST, DEAD, AWAY = "offline", "ghost", "dead", "out of range"

local UnitExists = UnitExists
local UnitName = UnitName
local UnitInRange = _G.UnitInRange
local UnitIsConnected = _G.UnitIsConnected
local UnitIsGhost = _G.UnitIsGhost
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost

--------------------------------------------------------------------------
-- What the client says has moved on one member
--
-- Three events, and every one is something a tile draws: the fill, the power
-- rail, and the word for somebody who has gone offline. They are what
-- Blizzard's own frames take on this client, PartyMemberFrame.lua for the
-- connection and UnitFrame.lua for the other two, and the compact raid frame
-- keeps the same pair of dirty bits behind them that this does.
--
-- No UNIT_AURA, because a tile draws no auras. Being dead or a ghost is not on
-- the list either and does not need to be: a member who dies loses their health
-- to zero on the way, which is UNIT_HEALTH, and the reading behind the events
-- catches a release.
--
-- The events land on the tile's own box rather than on the button, because the
-- button is a secure unit button the header owns and its scripts are the
-- header's business.
--------------------------------------------------------------------------

local WATCHED = { "UNIT_HEALTH", "UNIT_POWER_UPDATE", "UNIT_CONNECTION" }

local function Touched(box, _, unit)
	if unit == box.unit then
		box.block.dirty = true
	end
end

-- The token this tile answers for, and the three events about it. Both move
-- together: Touched compares the token, so a box carrying events and no token
-- would ignore every one of them.
--
-- Called whenever the unit under a button changes, which the header only does
-- out of combat.
local function Listen(block, unit)
	local box = block.box
	box.unit = unit
	for index = 1, #WATCHED do
		if unit then
			ns.RegisterUnitEvent(box, WATCHED[index], unit)
		else
			box:UnregisterEvent(WATCHED[index])
		end
	end
	block.dirty = true
end

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
	block.box.block = block
	block.box:SetScript("OnEvent", Touched)
	local backdrop = ns.Fill(block.box, "BACKGROUND",
		BACKDROP[1], BACKDROP[2], BACKDROP[3], BACKDROP[4])
	backdrop:SetAllPoints()
	block.box.edges = ns.Outline(block.box, IDLE[1], IDLE[2], IDLE[3], 1)

	block.health = Gauge.New(block.box)
	block.rail = Gauge.New(block.box)

	block.top = CreateFrame("Frame", nil, block.box)
	block.top:EnableMouse(false)

	-- Blizzard's own role art, so nothing here is cropped the way a spell icon
	-- is: this sheet is a grid of whole cells and Unit/Role.lua hands over the
	-- one this member wants.
	block.roleIcon = block.top:CreateTexture(nil, "ARTWORK")
	ns.UI.Crisp(block.roleIcon)

	block.nameText = ns.UI.Label(block.top, ns.UI.OutlineFloor(), NAME_TEXT,
		"LEFT", ns.UI.OUTLINE)
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
-- Returns how tall the health bar came out, which is what the role square is
-- sized off.
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
	return health
end

-- The role square at the left end and the name beside it.
--
-- The square sits on the health bar's midline at its left end, so the bar reads
-- as a mark of role and a run of colour, the way the player frame is a portrait
-- and a bar. The name starts to the right of it and runs to the far edge, left
-- aligned like the player's own, so every name down a stack starts on the same
-- line and the list is scanned rather than read. With the icons switched off
-- the name takes the square's room back.
--
-- Floored to a whole pixel for the same reason the name's size is: art asked
-- for at half a pixel is rasterised across two and the ring round the icon goes
-- soft.
local function Marks(block, px, tall, health, icons)
	local square = math.max(math.floor(health * ROLE_SHARE), ROLE_FLOOR)
	block.roleIcon:ClearAllPoints()
	block.roleIcon:SetPoint("LEFT", block.health, "LEFT", 0, 0)
	block.roleIcon:SetSize(square * px, square * px)

	-- Floored to a whole pixel: half of an odd tile is half a pixel, and a
	-- glyph asked for at half a pixel is rasterised across two. The floor is
	-- written into the call as well as into the clamp so the gate can read it,
	-- because a size the gate cannot follow is a rim nobody can say is above
	-- the floor.
	local size = math.min(math.max(math.floor(tall * TEXT_SHARE),
		ns.UI.OutlineFloor()), TEXT_CEILING)
	block.nameText:SetFontObject(
		ns.UI.Font(math.max(size, ns.UI.OutlineFloor()) * px, ns.UI.OUTLINE))

	-- Anchored by its two ends rather than by a corner, so the string sits on
	-- the health bar's midline whatever height the bar came out. Both anchors
	-- are on regions the bar's own height, so the two agree on where that is.
	block.nameText:ClearAllPoints()
	if icons then
		block.nameText:SetPoint("LEFT", block.roleIcon, "RIGHT", ROLE_GAP * px, 0)
	else
		block.nameText:SetPoint("LEFT", block.health, "LEFT", ROLE_GAP * px, 0)
	end
	block.nameText:SetPoint("RIGHT", block.health, "RIGHT", -ROLE_GAP * px, 0)
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
	-- And the events follow the token. This is the pass that runs when the
	-- header re-points a button at somebody else, so it is where a tile stops
	-- being told about the person who used to stand in it.
	Listen(block, block.unit)
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

	local health = Bars(block, px, wide, tall, rails)
	Marks(block, px, tall, health, look.icons ~= false)

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
-- Five times a second for the range, and on the three events above for
-- everything else, with a reading of every tile behind them once a second.
-- It used to be sixteen client calls per tile five times a second whatever had
-- happened, which in a raid is 3,200 a second to redraw forty tiles that were
-- already right.
--------------------------------------------------------------------------

-- Everything this tile last drew, forgotten. Every field, rather than the ones
-- that look like they matter: a field left behind is a write that will not
-- happen the next time the same value comes round, and the symptom is a tile
-- carrying the last member's name for as long as the new one stands in it.
--
-- The range answer goes with them, and it is a reading rather than a drawing.
-- Nobody is out of range until the next pass has asked, which is the right
-- default: the alternative is a tile that says "out of range" about somebody
-- standing next to you because the person who used to be in that slot was.
function Member.Clear(button)
	local block = button.wk
	if not block then
		return
	end
	block.tint, block.shade, block.hue = nil, nil, nil
	block.percent, block.power, block.label = nil, nil, nil
	block.away = nil
end

-- Whether this member is close enough to be worth pressing anything on, which
-- is the one reading on the tile that no event carries. UnitInRange is a
-- distance and the client fires nothing when it changes, so the pass asks it
-- and marks the tile only when the answer moves. Blizzard's own compact frame
-- keeps calling the same function for the same reason.
--
-- Probed by name, like the three below. Nothing installed on this machine calls
-- UnitInRange, and a client missing it has to lose the state rather than raise
-- once per member five times a second.
function Member.Ranged(button)
	local block = button.wk
	if not block or not block.range or not block.unit
		or type(UnitInRange) ~= "function" then
		return
	end
	local within, checked = UnitInRange(block.unit)
	local away = (checked and not within) and true or false
	if block.away ~= away then
		block.away = away
		block.dirty = true
	end
end

-- Which of the four states this member is in, or nothing at all.
--
-- Every call is probed by name. Nothing installed on this machine calls
-- UnitIsGhost or UnitIsDeadOrGhost, and a client missing one has to lose that
-- state rather than raise once per member five times a second.
--
-- The range answer is read off the tile rather than asked for again. It is
-- Member.Ranged's, taken on the pass rather than here, so a redraw the events
-- ask for does not cost a second distance check.
function Member.Shade(block, unit)
	if type(UnitIsConnected) == "function" and not UnitIsConnected(unit) then
		return OFFLINE
	end
	if type(UnitIsGhost) == "function" and UnitIsGhost(unit) then
		return GHOST
	end
	if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost(unit) then
		return DEAD
	end
	if block.range and block.away then
		return AWAY
	end
	return nil
end

-- The fill, the ground behind it and the outline, in one colour.
--
-- Gauge.Paint draws the ground as the fill dimmed, which is the same bar the
-- player frame is, so a tile's missing end and the player's are one mark. A
-- drained tile hands the dimmed fill over and gets a ground dimmed twice, which
-- is darker than any healthy tile's spent end and is what keeps the two
-- states apart.
--
-- Color.Dim writes into one scratch table and the next call overwrites it, so
-- each answer is handed straight to a setter before the next is asked for.
function Member.Paint(block, tint, shade)
	Gauge.Paint(block.health, block.health.track,
		shade and Color.Dim(tint, Color.track) or tint)
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

-- The name, or the word that says why there is no reading to take. Out of
-- range is not a word: the drained fill says it, and the name stays.
function Member.Label(block, unit, shade)
	local text = (shade and shade ~= AWAY) and shade or UnitName(unit) or ""
	if block.label ~= text then
		block.label = text
		block.nameText:SetText(text)
	end
end

-- One member, redrawn.
--
-- The unit is read off the button here rather than trusted from the last
-- layout. The header only re-points a button out of combat, so this should
-- never move between two readings, and one attribute read per member is cheaper
-- than being wrong about which person's health is on the screen. It is on this
-- side of the dirty bit rather than on the pass, which is what takes it off the
-- fifth of a second and leaves it on the reading.
function Member.Update(button)
	local block = button.wk
	if not block then
		return
	end
	local unit = button:GetAttribute("unit")
	if block.unit ~= unit then
		Listen(block, unit)
		block.unit = unit
		Member.Clear(button)
	end
	block.dirty = false
	if not unit or not UnitExists(unit) then
		return
	end

	local shade = Member.Shade(block, unit)
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
