-- When a party tile is redrawn
--
-- 39-party-raid.lua is what a tile draws. This is when: the client says a
-- member's health, power or connection moved, that tile is marked, and the pass
-- a fifth of a second later draws the ones something happened to. What is left
-- on the pass for every tile is one UnitInRange, which is the one reading here
-- the client has no event for and the reason the pass exists at all.
--
-- A separate section rather than another block in 39-party-raid.lua, which is
-- at its own line ceiling, and it is a separate subject: that file is about the
-- order, the tile and the grid, and this one is about the clock behind them.
--
-- The two clocks have to be put in a known phase before any of it means
-- anything. Both tickers hang off one frame, so one long frame fires them both
-- and leaves both accumulators at zero, after which four short frames drive the
-- fast pass alone. Without that the once a second reading could land on any of
-- these lines and the section would be measuring the phase it started in.

local H = ...
local ns, check, fire = H.ns, H.check, H.fire
local group = H.group

local PARTY = {
	{ token = "player", you = true, guid = "Player-Tusksfirst",
		name = "Tusksfirst", class = "WARRIOR",
		health = 6000, healthMax = 9000, power = 40, powerMax = 100, powerType = 1 },
	{ token = "party1", guid = "Player-Sneaky", name = "Sneaky", class = "ROGUE",
		health = 3000, healthMax = 4000, power = 60, powerMax = 100, powerType = 3 },
	{ token = "party2", guid = "Player-Lightwell", name = "Lightwell", class = "PRIEST",
		health = 2000, healthMax = 4000, power = 800, powerMax = 4000, powerType = 0 },
}

group.Set(PARTY, false)
fire("GROUP_ROSTER_UPDATE")

-- Both halves, the fast pass and the reading behind it, beaten together the
-- way driving the party's own frame ran both before every permanent tick moved
-- to one frame.
local partyPass, partyRead = H.tick("party"), H.tick("partyread")

local function settle()
	partyPass:Beat(5)
	partyRead:Beat(5)
end
local function pass()
	partyPass:Beat(0.2)
	partyRead:Beat(0.2)
end

local function tileOf(name)
	for _, button in ipairs(ns.Group.Members("party")) do
		if button:IsShown() and _G.UnitName(button:GetAttribute("unit")) == name then
			return button.wk
		end
	end
	return nil
end

local sneaky = tileOf("Sneaky")
check(sneaky ~= nil, "Sneaky has no tile, so nothing below is being measured")

----------------------------------------------------------------------
-- Health, told and not told
----------------------------------------------------------------------

do
	settle()
	local drawn = sneaky.health:GetValue()
	check(math.abs(drawn - 0.75) < 1e-9,
		("Sneaky is at 3000 of 4000 and the fill reads %.4f"):format(drawn))

	-- A hit nobody mentions. The tile is not redrawn, which is the whole of the
	-- change: the pass no longer reads health off the client.
	group.members.party1.health = 1000
	pass()
	check(math.abs(sneaky.health:GetValue() - 0.75) < 1e-9,
		"a tile redrew on a pass nothing had marked, so it is still polling")

	-- Somebody else's news is not this member's.
	fire("UNIT_HEALTH", "party2")
	pass()
	check(math.abs(sneaky.health:GetValue() - 0.75) < 1e-9,
		"a tile redrew on an event that named another member")

	-- And the event that is about them.
	fire("UNIT_HEALTH", "party1")
	pass()
	check(math.abs(sneaky.health:GetValue() - 0.25) < 1e-9,
		("a member taking a hit did not reach their tile on the next pass: %.4f")
			:format(sneaky.health:GetValue()))

	-- The reading behind the events, for a client that fires none of them.
	group.members.party1.health = 4000
	settle()
	check(math.abs(sneaky.health:GetValue() - 1) < 1e-9,
		"the once a second reading never caught up with the client")
end

----------------------------------------------------------------------
-- The range, which has no event and is what is left on the pass
----------------------------------------------------------------------

do
	check(ns.db.partyRange, "range checking is off, so the one poll left is not"
		.. " being driven at all")
	group.members.party1.range = false
	pass()
	check(sneaky.nameText.text == "out of range",
		("a member walked out of range and the tile reads %q on the next pass")
			:format(tostring(sneaky.nameText.text)))

	group.members.party1.range = nil
	pass()
	check(sneaky.nameText.text == "Sneaky",
		"a member who came back into range kept the word that said they were gone")
end

----------------------------------------------------------------------
-- The events follow the person, not the slot
--
-- The header re-points a button when the roster changes, and a tile still
-- registered against the token the last person stood under is a tile marked by
-- somebody else's health.
----------------------------------------------------------------------

do
	local SWAPPED = {
		{ token = "player", you = true, guid = "Player-Tusksfirst",
			name = "Tusksfirst", class = "WARRIOR",
			health = 6000, healthMax = 9000, power = 40, powerMax = 100, powerType = 1 },
		{ token = "party1", guid = "Player-Ironhide", name = "Ironhide", class = "WARRIOR",
			health = 8000, healthMax = 8000, power = 20, powerMax = 100, powerType = 1 },
	}
	group.Set(SWAPPED, false)
	fire("GROUP_ROSTER_UPDATE")
	settle()

	local ironhide = tileOf("Ironhide")
	check(ironhide ~= nil, "the new member has no tile")
	group.members.party1.health = 2000
	fire("UNIT_HEALTH", "party1")
	pass()
	check(math.abs(ironhide.health:GetValue() - 0.25) < 1e-9,
		("the tile was not listening for the person now standing in it: %.4f")
			:format(ironhide.health:GetValue()))

	print("party  a health event draws on the next pass, a pass with nothing"
		.. " marked draws nothing, and the range is the one poll left")
end

----------------------------------------------------------------------
-- Put the client back the way a section after this one would expect it.
----------------------------------------------------------------------

group.Forget()
fire("GROUP_ROSTER_UPDATE")
