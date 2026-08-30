-- The party and raid blocks
--
-- Three questions, and only the first of them is about pixels.
--
-- Who ends up in which slot. That is the whole item: the order is a role band
-- and then a name, decided out of four sources that disagree, and it is
-- recomputed out of combat and nowhere else. Every roster below is the same six
-- people with one thing changed, so what is being read is the change and not
-- the scene.
--
-- What one block draws. Class colour on the health fill, the power colour for
-- the power type, no rail at all for a member the client answers no maximum
-- for, and Blizzard's own role art at the quadrant that is that role. All four
-- were invisible in review, because each one is a value that reaches a widget
-- through three files.
--
-- What it costs. A tick over four blocks that allocates nothing, which is what
-- the HOT list holds Member.lua to and what this measures.
--
-- What this cannot prove is the header. SecureGroupHeaderTemplate is
-- FrameXML's, harness/client/09-group.lua is a model of it written from the
-- contract, and a model that is wrong is a test that passes and a client that
-- does not. What is asserted about it is the half the addon owns: the
-- attributes it wrote, and the order it put in the name list.

local H = ...
local ns, check, fire = H.ns, H.check, H.fire
local group, advance, CHURN = H.group, H.advance, H.CHURN
local Color, Role = ns.Unit.Color, ns.Unit.Role
local header = ns.Group.Header()

local function near(a, b)
	return a ~= nil and b ~= nil and math.abs(a - b) < 1e-6
end

-- What a gauge was painted, off the status bar rather than off a texture: the
-- fill of one of our own gauges is a status bar colour and the spent track
-- behind it is a colour texture.
local function fills(bar, color)
	return near(bar.barR, color[1]) and near(bar.barG, color[2])
		and near(bar.barB, color[3])
end

local function tracks(bar, color)
	local track = bar.track
	return track and near(track.r, color[1] * Color.track)
		and near(track.g, color[2] * Color.track) and near(track.a, 0.9)
end

-- The list as it stands, read back off the buttons rather than off
-- Group.Order, so what is checked is where the header put somebody and not what
-- the addon meant to ask for.
local function slots()
	local out = {}
	for _, button in ipairs(ns.Group.Members()) do
		if button:IsShown() then
			out[#out + 1] = _G.UnitName(button:GetAttribute("unit")) or "?"
		end
	end
	return out
end

local function reads(what, want)
	local got = table.concat(slots(), ", ")
	check(got == want, ("%s: the list reads %q and belongs %q"):format(what, got, want))
end

local function blockOf(name)
	for _, button in ipairs(ns.Group.Members()) do
		if button:IsShown() and _G.UnitName(button:GetAttribute("unit")) == name then
			return button.wk, button
		end
	end
	return nil
end

----------------------------------------------------------------------
-- The scene
--
-- Six people who turn up in every roster below, so a slot that moved moved
-- because of the one thing that changed. Bramblefoot carries no power maximum
-- at all, which is a member the client has not filled in yet and is the case
-- that has to draw no rail rather than an empty one.
--
-- Every one of them carries a GUID of their own, spelled the same in the party
-- and in the raid. That is not decoration: a role resolved out of talents is
-- cached against the GUID, so a fixture that handed the same person a new one
-- when they moved from party2 to raid5 would be asserting that an inspect is
-- forgotten every time the group changes shape, which is the opposite of what
-- the file claims.
----------------------------------------------------------------------

local PARTY = {
	{ token = "player", you = true, guid = "Player-Tusksfirst",
		name = "Tusksfirst", class = "WARRIOR",
		health = 6000, healthMax = 9000, power = 40, powerMax = 100, powerType = 1 },
	{ token = "party1", guid = "Player-Sneaky", name = "Sneaky", class = "ROGUE",
		health = 3000, healthMax = 4000, power = 60, powerMax = 100, powerType = 3 },
	{ token = "party2", guid = "Player-Bramblefoot", name = "Bramblefoot", class = "DRUID",
		health = 4500, healthMax = 5000, powerMax = 0 },
	{ token = "party3", guid = "Player-Lightwell", name = "Lightwell", class = "PRIEST",
		health = 2000, healthMax = 4000, power = 800, powerMax = 4000, powerType = 0 },
	{ token = "party4", guid = "Player-Ironhide", name = "Ironhide", class = "WARRIOR",
		maintank = true,
		health = 8000, healthMax = 8000, power = 20, powerMax = 100, powerType = 1 },
}

local function stand(list, raid)
	group.Set(list, raid)
	fire("GROUP_ROSTER_UPDATE")
end

check(header ~= nil, "no secure group header was built")
check(_G.WarriorKitGroup ~= nil and _G.WarriorKitGroupHeader ~= nil,
	"the list you drag and the header on it are not both named")
check(_G.WarriorKitGroup.ignoreScale == true,
	"the frame you drag the list by is not on the grid")

stand(PARTY, false)

----------------------------------------------------------------------
-- The attributes
----------------------------------------------------------------------

do
	check(header:GetAttribute("template") == "SecureUnitButtonTemplate",
		"the header was not told what to make each member out of")
	check(header:GetAttribute("showSolo") == false,
		"the header shows a group of one, which is the player block said twice")
	check(header:GetAttribute("showParty") == true and header:GetAttribute("showRaid") == true,
		"the header was not told to show a party and a raid")
	check(header:GetAttribute("showPlayer") == false,
		"your own block is in the list and the default says it is not")
	check(header:GetAttribute("sortMethod") == "NAMELIST",
		"the order is a role band and a name, which is a name list and nothing else")
	check(header:GetAttribute("point") == "TOP"
		and header:GetAttribute("yOffset") == -ns.db.partyGap,
		"the list does not grow down by the gap it was given")

	-- The snippet, read off a button rather than out of the string, because the
	-- string is what was asked for and the button is what the header did with it.
	local _, button = blockOf("Ironhide")
	check(button ~= nil, "nobody in the party got a block at all")
	if button then
		check(button:GetWidth() == ns.db.partyHeight + ns.db.partyWidth
			and button:GetHeight() == ns.db.partyHeight,
			("a block is %dx%d and the settings say %dx%d"):format(button:GetWidth(),
				button:GetHeight(), ns.db.partyHeight + ns.db.partyWidth, ns.db.partyHeight))
		check(button:GetAttribute("*type1") == "target"
			and button:GetAttribute("*type2") == "togglemenu",
			"a block does not target on the left button and open the menu on the right")
		check(button.scripts.OnMouseDown ~= nil,
			"nothing hooked a block's mouse, so ctrl-click marking went off the screen"
				.. " with Blizzard's party frames")
	end
end

----------------------------------------------------------------------
-- Where the block sits
--
-- The list fills outward from the middle. The header is centred on the frame
-- you drag and takes its own size from the buttons it has just arranged, so a
-- fifth person moves every slot half a block away from the anchor rather than
-- pushing one end of the list along and leaving the other where it was.
--
-- Measured off the buttons rather than off the header, because the header's own
-- size is the model's arithmetic and the buttons are where that arithmetic
-- actually put somebody.
----------------------------------------------------------------------

-- The rectangle the shown blocks fill: its top left corner, then its middle.
local function block()
	local left, right = math.huge, -math.huge
	local top, bottom = -math.huge, math.huge
	for _, button in ipairs(ns.Group.Members()) do
		if button:IsShown() then
			left, right = math.min(left, button:GetLeft()), math.max(right, button:GetRight())
			top, bottom = math.max(top, button:GetTop()), math.min(bottom, button:GetBottom())
		end
	end
	return left, top, (left + right) / 2, (top + bottom) / 2
end

-- On the grid, to a millionth. Not an exact integer: the list is anchored by its
-- growth point now rather than by a corner, so every edge read back out of the
-- model is the anchor's middle plus half a header minus half a block, and three
-- fractional scales cancelling in floating point land seven parts in a
-- quadrillion off. What this is guarding against is a half unit.
local function whole(value)
	return math.abs(value - math.floor(value + 0.5)) < 1e-6
end

do
	local ax, ay = _G.WarriorKitGroup:GetCenter()
	local _, top, x, y = block()
	check(near(x, ax) and near(y, ay),
		("four blocks sit round %.1f, %.1f and the frame you drag is at %.1f, %.1f")
			:format(x, y, ax, ay))

	-- The same anchor with one more person in the list. Both halves matter: the
	-- middle did not move, and the top did, or the first assertion would pass on
	-- a list that never grew at all.
	ns.db.partySelf = true
	ns.Group.Apply()
	check(ns.Group.Count() == 5, "the fifth block never turned up")
	local _, grownTop, grownX, grownY = block()
	check(near(grownX, ax) and near(grownY, ay),
		("a fifth block moved the middle of the list to %.1f, %.1f from %.1f, %.1f")
			:format(grownX, grownY, ax, ay))
	check(grownTop > top,
		"a fifth block did not lift the top of the list, so nothing filled outward")
	ns.db.partySelf = false
	ns.Group.Apply()
end

-- Half of the block is not always a whole unit. Four blocks with a three unit
-- gap between them is a hundred and forty five, and a list centred on half of
-- that puts every edge inside it across two rows of pixels. So the offset that
-- centres the header is rounded: what is given up is half a unit of centring and
-- what is kept is the grid.
do
	local was = ns.db.partyGap
	ns.db.partyGap = 3
	ns.Group.Apply()

	local left, top, x, y = block()
	check(whole(left) and whole(top),
		("an odd block puts the corner of the list at %.1f, %.1f, which is off the grid")
			:format(left, top))
	local ax, ay = _G.WarriorKitGroup:GetCenter()
	check(math.abs(x - ax) <= 0.5 + 1e-6 and math.abs(y - ay) <= 0.5 + 1e-6,
		("an odd block sits %.1f, %.1f off the frame you drag, and rounding costs half a unit at most")
			:format(x - ax, y - ay))

	ns.db.partyGap = was
	ns.Group.Apply()
end

-- The same four people run sideways, which is one to a column and a column
-- each. This is the arrangement the centring was wrong for, and it is wrong in
-- the one direction a vertical list can never show: the header sizes itself to
-- every column it drew and then anchors the first column across its own middle,
-- so the blocks sit half a list to the right of the box. Centring the box put
-- the whole party right of the frame you drag, which is the list flowing off one
-- end again with the arithmetic that was supposed to have stopped it.
do
	local was = ns.db.partyRaidPerColumn
	ns.db.partyRaidPerColumn = 1
	ns.Group.Apply()

	check(ns.Group.Count() == 4, "a party one to a column lost somebody")
	local left, top, x, y = block()
	local ax, ay = _G.WarriorKitGroup:GetCenter()
	check(near(x, ax) and near(y, ay),
		("four blocks in a row sit round %.1f, %.1f and the frame you drag is at %.1f, %.1f")
			:format(x, y, ax, ay))

	-- And it is a row, not a column, or the assertion above would pass on a list
	-- that ignored the setting entirely.
	local block4 = ns.db.partyHeight + ns.db.partyWidth
	local wide = 4 * block4 + 3 * ns.db.partyGap
	check(near(x - left, wide / 2),
		("four blocks one to a column are %.1f across and belong %d"):format(
			(x - left) * 2, wide))
	check(near(top, y + ns.db.partyHeight / 2),
		"four blocks one to a column are not on one row")

	ns.db.partyRaidPerColumn = was
	ns.Group.Apply()
end

----------------------------------------------------------------------
-- The order, under three rosters
----------------------------------------------------------------------

-- One. Nobody has been inspected and nobody has an assignment, so the only two
-- sources answering are the raid's main tank flag and the class floor:
-- Ironhide is flagged, a priest is a healer before anyone reads their talents,
-- and the other two are damage by name.
reads("a party with one flagged tank", "Ironhide, Lightwell, Bramblefoot, Sneaky")

-- Two. The group finder assigns Sneaky to heal, which beats the class floor
-- that had a rogue down as damage, and the healer band sorts by name.
do
	group.members.party1.assigned = "HEALER"
	Role.Forget()
	ns.Group.Rebuild()
	reads("a rogue the group finder calls a healer",
		"Ironhide, Lightwell, Sneaky, Bramblefoot")
	group.members.party1.assigned = nil
	Role.Forget()
	ns.Group.Rebuild()
end

-- Three. Talents, which is the only source on these clients that is about the
-- character rather than about what somebody typed. Bramblefoot comes back as
-- forty-one points in tree two, which is Feral Combat, which is a tank, and a
-- tank sorts above Ironhide because B is before I.
do
	ns.Unit.Spec.Forget()
	advance(70)
	H.talentTrees.inspect = {
		{ name = "Balance", icon = "Interface\\Icons\\Spell_Nature_StarFall", points = 8 },
		{ name = "Feral Combat", icon = "Interface\\Icons\\Ability_Racial_BearForm", points = 41 },
		{ name = "Restoration", icon = "Interface\\Icons\\Spell_Nature_HealingTouch", points = 12 },
	}
	local guid = "Player-Bramblefoot"
	check(ns.Unit.Spec.Request(guid), "no inspect went out for a party member in range")
	fire("INSPECT_READY", guid)
	local tree, points = ns.Unit.Spec.Tree(guid)
	check(tree == 2 and points == 41,
		("the winning tree came back as %s with %s points"):format(tostring(tree), tostring(points)))
	check(Role.Of("party2") == Role.TANK,
		"forty-one points in a druid's second tree is a tank and the role says otherwise")

	ns.Group.Rebuild()
	reads("a druid whose talents came back feral",
		"Bramblefoot, Ironhide, Lightwell, Sneaky")
end

-- And an answer typed by hand, which beats all three of them. Sneaky is a
-- rogue with no assignment and no talents read, and saying so puts them at the
-- top of the tank band.
do
	Role.Set("Sneaky", Role.TANK)
	check(Role.Of("party1") == Role.TANK, "an override did not beat the class floor")
	ns.Group.Rebuild()
	reads("a rogue you called a tank", "Bramblefoot, Ironhide, Sneaky, Lightwell")
	Role.Set("Sneaky", nil)
	ns.Group.Rebuild()
end

----------------------------------------------------------------------
-- What one block draws
----------------------------------------------------------------------

do
	local rogue = blockOf("Sneaky")
	local priest = blockOf("Lightwell")
	local warrior = blockOf("Ironhide")
	local druid = blockOf("Bramblefoot")
	check(rogue and priest and warrior and druid, "four members, and not four blocks")

	-- The class colour off the palette rather than typed again here. The
	-- palette caps every fill under a luminance ceiling, so a copy of the
	-- client's own numbers would be one more place the arithmetic has to be
	-- redone by hand.
	check(fills(rogue.health, Color.Class("ROGUE")),
		"the rogue's health fill is not the rogue class colour")
	check(fills(priest.health, Color.Class("PRIEST")),
		"the priest's health fill is not the priest class colour")
	check(tracks(rogue.health, Color.Class("ROGUE")),
		"the spent part of the rogue's gauge is not their colour at ns.Unit.Color.track")

	-- Power by the number UnitPowerType answers, which is the half of that API
	-- that has never been renamed between these two clients.
	check(fills(rogue.rail, Color.power[3]), "energy is not drawn in the energy colour")
	check(fills(priest.rail, Color.power[0]), "mana is not drawn in the mana colour")
	check(fills(warrior.rail, Color.power[1]), "rage is not drawn in the rage colour")

	-- A member with no power draws no rail rather than an empty one, and the
	-- health gauge takes the room back rather than leaving a gap where it was.
	check(druid.rail.shown == false,
		"a member the client answers no power maximum for still drew a rail")
	check(druid.health:GetHeight() > rogue.health:GetHeight(),
		("the gauge on a block with no rail is %d tall and one with a rail is %d")
			:format(druid.health:GetHeight(), rogue.health:GetHeight()))
	-- And the room it took back is exactly the rail plus the hairline that was
	-- between them, so a block with no power is the same height as one with it
	-- rather than one pixel of backdrop short along its bottom edge.
	check(druid.health:GetHeight()
		== rogue.health:GetHeight() + rogue.rail:GetHeight() + 1,
		("the gauge with no rail is %d and the two with one come to %d")
			:format(druid.health:GetHeight(),
				rogue.health:GetHeight() + rogue.rail:GetHeight() + 1))

	-- The percent, floored to the integer that gets drawn, which is what the
	-- tick guards on: 2000 of 4000 is 50 and 4500 of 5000 is 90.
	check(priest.healthText.text == "50%" and druid.healthText.text == "90%",
		("the readings came out %q and %q"):format(tostring(priest.healthText.text),
			tostring(druid.healthText.text)))
	check(rogue.nameText.text == "Sneaky",
		("a block's name reads %q"):format(tostring(rogue.nameText.text)))
end

----------------------------------------------------------------------
-- The role icon
--
-- Blizzard's own art, cut as a grid of 75 pixel cells out of a 256 square
-- sheet. The four numbers are restated here rather than read out of
-- Unit/Role.lua, because a gate that imported the value it is checking would
-- pass on the day somebody changed it by accident.
----------------------------------------------------------------------

do
	local CELL, SHEET = 75 / 256, "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
	local QUADRANT = {
		tank = { 0, CELL, CELL, CELL * 2 },
		healer = { CELL, CELL * 2, 0, CELL },
		dps = { CELL, CELL * 2, CELL, CELL * 2 },
	}
	local WHO = { Bramblefoot = "tank", Lightwell = "healer", Sneaky = "dps" }

	for name, role in pairs(WHO) do
		local block = blockOf(name)
		local want = QUADRANT[role]
		local crop = block and block.roleIcon.texcoord
		check(block and block.roleIcon.texture == SHEET,
			name .. ": the role icon is not cut from Blizzard's own role sheet")
		check(crop and near(crop[1], want[1]) and near(crop[2], want[2])
			and near(crop[3], want[3]) and near(crop[4], want[4]),
			("%s: the %s icon crops to %s and belongs at %.4f %.4f %.4f %.4f"):format(
				name, role, crop and table.concat(crop, " ") or "nothing",
				want[1], want[2], want[3], want[4]))
	end
end

----------------------------------------------------------------------
-- What a member you cannot read draws
--
-- Four states, one picture: the fill goes to the track colour and the name says
-- which. Out of range is in the list with the other three on purpose, because
-- the slot is what says who it is.
----------------------------------------------------------------------

do
	local STATES = {
		{ field = "range", value = false, word = "out of range" },
		{ field = "dead", value = true, word = "dead" },
		{ field = "ghost", value = true, word = "ghost" },
		{ field = "connected", value = false, word = "offline" },
	}
	local faded = Color.Class("ROGUE")
	for _, state in ipairs(STATES) do
		group.members.party1[state.field] = state.value
		ns.Group.Update()
		local block = blockOf("Sneaky")
		check(block.nameText.text == state.word,
			("%s: the name reads %q"):format(state.word, tostring(block.nameText.text)))
		check(near(block.health.barR, faded[1] * Color.track),
			state.word .. ": the fill did not go to the track colour")
		group.members.party1[state.field] = nil
	end
	ns.Group.Update()
	check(blockOf("Sneaky").nameText.text == "Sneaky",
		"a member who came back into range kept the word that said they were gone")
	check(fills(blockOf("Sneaky").health, faded),
		"a member who came back into range kept the drained fill")
end

----------------------------------------------------------------------
-- The order does not move in combat
--
-- This is what makes fixed placing true rather than aspirational. An inspect
-- that resolves mid pull is recorded and changes nothing on the screen until
-- the fight ends.
----------------------------------------------------------------------

do
	local realLockdown, realProtected = _G.InCombatLockdown, H.Region.IsProtected
	local before = table.concat(slots(), ", ")

	_G.InCombatLockdown = function() return true end
	H.Region.IsProtected = function() return true end

	-- Somebody the raid leader flags mid fight, which is a real change to a
	-- real source and must not move a single block until combat drops.
	group.members.party1.maintank = true
	Role.Forget()
	ns.Group.Rebuild()
	check(table.concat(slots(), ", ") == before,
		("the list moved in combat: %q was %q"):format(table.concat(slots(), ", "), before))
	check(ns.Group.Deferred(), "a rebuild combat refused did not say it had been deferred")
	check(ns.Group.Describe():find("when combat drops") ~= nil,
		"the status line does not say the rest is waiting for combat to drop")

	_G.InCombatLockdown, H.Region.IsProtected = realLockdown, realProtected
	fire("PLAYER_REGEN_ENABLED")
	reads("combat dropped and the flag landed", "Bramblefoot, Ironhide, Sneaky, Lightwell")
	check(not ns.Group.Deferred(), "the deferred rebuild never ran")

	group.members.party1.maintank = nil
	Role.Forget()
	ns.Group.Rebuild()
end

----------------------------------------------------------------------
-- A raid
----------------------------------------------------------------------

local RAID = {
	{ you = true, guid = "Player-Tusksfirst", name = "Tusksfirst", class = "WARRIOR",
		subgroup = 1,
		health = 6000, healthMax = 9000, power = 40, powerMax = 100, powerType = 1 },
	{ guid = "Player-Ironhide", name = "Ironhide", class = "WARRIOR", subgroup = 1,
		maintank = true,
		health = 8000, healthMax = 8000, power = 20, powerMax = 100, powerType = 1 },
	{ guid = "Player-Lightwell", name = "Lightwell", class = "PRIEST", subgroup = 2,
		health = 2000, healthMax = 4000, power = 800, powerMax = 4000, powerType = 0 },
	{ guid = "Player-Sneaky", name = "Sneaky", class = "ROGUE", subgroup = 2,
		health = 3000, healthMax = 4000, power = 60, powerMax = 100, powerType = 3 },
	{ guid = "Player-Bramblefoot", name = "Bramblefoot", class = "DRUID", subgroup = 1,
		health = 4500, healthMax = 5000, powerMax = 0 },
	{ guid = "Player-Emberdusk", name = "Emberdusk", class = "MAGE", subgroup = 2,
		health = 3300, healthMax = 5000, power = 2000, powerMax = 6000, powerType = 0 },
}

do
	-- The druid's inspect is still on record, so the same person walks into the
	-- raid as a tank. That is the point of the cache: an answer settled once is
	-- settled for the session, and only a guess is asked again.
	stand(RAID, true)
	check(_G.IsInRaid(), "the raid did not stand up")
	reads("a raid of six by role",
		"Bramblefoot, Ironhide, Lightwell, Emberdusk, Sneaky")

	-- And the other ordering, which is the one somebody running twenty five
	-- with assignments per group actually wants. Group 1 is Ironhide and
	-- Bramblefoot in the order the client hands them over, then group 2.
	ns.db.partyOrder = "group"
	ns.Group.Apply()
	check(header:GetAttribute("sortMethod") == "INDEX"
		and header:GetAttribute("groupBy") == "GROUP",
		"party order group did not put the header on the raid's own groups")
	check(header:GetAttribute("nameList") == nil,
		"the name list survived a switch to group order, so two orderings are live")
	check(#ns.Group.Order() == 0,
		"a role order is still being handed out while the header runs group numbers")
	reads("a raid of six by group number",
		"Ironhide, Bramblefoot, Lightwell, Sneaky, Emberdusk")

	-- Party is always by role, whatever this setting says, because every group
	-- number in a party is 1 and grouping by it is the order the client handed
	-- the units over.
	stand(PARTY, false)
	check(header:GetAttribute("sortMethod") == "NAMELIST",
		"a party in group order is a party in the order it was invited")
	ns.db.partyOrder = "role"
	ns.Group.Apply()
end

----------------------------------------------------------------------
-- Your own block, and the switch
----------------------------------------------------------------------

do
	ns.db.partySelf = true
	ns.Group.Apply()
	check(header:GetAttribute("showPlayer") == true,
		"party self on did not tell the header to show you")
	reads("your own block, at your own role's slot",
		"Bramblefoot, Ironhide, Lightwell, Sneaky, Tusksfirst")
	ns.db.partySelf = false
	ns.Group.Apply()

	ns.db.party = false
	ns.Group.Apply()
	check(#slots() == 0 and ns.Group.Count() == 0,
		"party off left blocks on the screen")
	check(ns.Group.Describe():find("^off") ~= nil,
		"party off does not say so: " .. ns.Group.Describe())
	ns.db.party = true
	ns.Group.Apply()
	check(ns.Group.Count() == 4, "party back on did not put the four blocks back")

	-- The two switches that reach one block rather than the header. Both travel
	-- to UnitFrames/Member.lua at layout time, because that file reads no
	-- setting of its own, so both are a relayout and neither is a branch on the
	-- tick.
	ns.db.partyRoleIcon = false
	ns.Group.Apply()
	check(blockOf("Ironhide").roleIcon.shown == false,
		"the role icon switch went off and the icon is still drawn")
	ns.db.partyRoleIcon = true
	ns.Group.Apply()

	group.members.party1.range = false
	ns.db.partyRange = false
	ns.Group.Apply()
	check(blockOf("Sneaky").nameText.text == "Sneaky"
		and fills(blockOf("Sneaky").health, Color.Class("ROGUE")),
		"range checking went off and a member out of range still drained")
	ns.db.partyRange = true
	ns.Group.Apply()
	check(blockOf("Sneaky").nameText.text == "out of range",
		"range checking came back on and nothing said so")
	group.members.party1.range = nil
	ns.Group.Update()
end

----------------------------------------------------------------------
-- The sizes, and the grid
----------------------------------------------------------------------

do
	ns.db.partyHeight, ns.db.partyWidth, ns.db.partyGap = 22, 120, 2
	ns.Group.Apply()
	local _, button = blockOf("Ironhide")
	check(button:GetWidth() == 142 and button:GetHeight() == 22,
		("a resized block is %dx%d and belongs 142x22"):format(button:GetWidth(),
			button:GetHeight()))
	check(header:GetAttribute("yOffset") == -2,
		"the gap between two blocks did not follow the setting")

	local block = button.wk
	check(block.box:GetWidth() == 142 and block.box:GetHeight() == 22,
		"the block inside the button did not follow it")
	check(block.slot:GetWidth() == 22 and block.slot:GetHeight() == 22,
		"the role icon's square is not the block's height squared")
	for _, part in ipairs({ block.health, block.rail }) do
		local tall = part:GetHeight()
		check(tall >= 1 and math.abs(tall - math.floor(tall + 0.5)) < 1e-9,
			("a gauge is %.4f pixels tall, not a whole one"):format(tall))
	end

	ns.db.partyHeight, ns.db.partyWidth, ns.db.partyGap = 34, 168, 4
	ns.Group.Apply()
end

----------------------------------------------------------------------
-- Blizzard's own, off the screen
----------------------------------------------------------------------

do
	check(ns.db.hideBlizzParty and ns.db.hideBlizzRaid,
		"the two new hide switches do not ship on, and two copies on screen is a bug")
	for index = 1, 4 do
		check(_G["PartyMemberFrame" .. index]:IsShown() == false,
			"PartyMemberFrame" .. index .. " is still on the screen")
	end
	check(_G.CompactRaidFrameContainer:IsShown() == false,
		"the raid container is still on the screen")

	-- The manager's own layout pass, which is what puts the container back. It
	-- does it with SetShown, which is resolved in C and never reads the Lua Show
	-- that ns.Strip replaced, so the flag on the frame really does come back on
	-- and nothing the addon can install stops it.
	--
	-- What stops it is the parent. The container lives in the attic, the attic is
	-- hidden and cannot be shown, so the frame's own flag is the only thing that
	-- moved and the container is still not drawn. This used to be a hook on that
	-- one function, which is a patch for the one frame somebody noticed rather
	-- than an answer for the call.
	_G.CompactRaidFrameManager_UpdateShown()
	check(_G.CompactRaidFrameContainer:IsShown(),
		"the fixture cannot put the container back, so this proves nothing")
	check(_G.CompactRaidFrameContainer:IsVisible() == false,
		"the manager's layout pass put the raid container back on the screen")

	ns.db.hideBlizzParty = false
	ns.BlizzHide.Apply()
	check(_G.PartyMemberFrame1:IsShown(),
		"turning the party switch off did not give Blizzard's frames back")
	ns.db.hideBlizzParty = true
	ns.BlizzHide.Apply()
end

----------------------------------------------------------------------
-- Allocation
--
-- Four blocks at five ticks a second, with nothing moving, which is what a
-- party looks like for most of a session. Every write in Member.lua is guarded
-- on the value already on the frame, so the steady state is a walk and a
-- handful of comparisons and it should measure nothing at all.
----------------------------------------------------------------------

local function churn(ticks)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, ticks do
		advance(0.2)
		ns.Group.Update()
	end
	local after = collectgarbage("count")
	collectgarbage("restart")
	return (after - before) / (ticks / 50)
end

-- Cold first, for the reason every other measurement here takes a cold pass:
-- the first run interns every string the four blocks will ever draw.
churn(200)
local burn = churn(200)
check(burn <= CHURN.party,
	("the party tick allocates %.2f KB per 50 ticks, the gate is %.2f")
		:format(burn, CHURN.party))

print(("party  %d blocks of %d x %d px, %s; %.2f KB per 50 ticks, gate is %.2f")
	:format(ns.Group.Count(), ns.db.partyHeight + ns.db.partyWidth, ns.db.partyHeight,
		table.concat(ns.Group.Order(), ", "), burn, CHURN.party))
print("party  " .. ns.Group.Describe())
print("roles  " .. Role.Describe())

----------------------------------------------------------------------
-- Put the client back the way a section after this one would expect it.
----------------------------------------------------------------------

group.Forget()
fire("GROUP_ROSTER_UPDATE")
ns.Unit.Spec.Forget()
Role.Forget()
