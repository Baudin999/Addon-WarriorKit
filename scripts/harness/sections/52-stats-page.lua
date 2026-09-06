-- What you miss with, on the sheet
--
-- The numbers on the stats column, against the three figures the game publishes:
-- five percent on a same level target, six on two levels up, nine on a boss, and
-- six tenths of a percent for every point of weapon skill you are short of the
-- cap. Nobody can check those by looking at the page. They are the one thing on
-- the sheet that is arithmetic rather than a call to the client, they are what
-- the badge at the head of the column is built from, and a formula that stopped
-- at the first ten points read nine percent against a boss on a character who
-- misses fifteen.
--
-- A file of its own rather than a block in 52-character.lua, which is the same
-- move that gave that file 52-gear-page.lua, 52-screen-dark.lua and
-- 52-trinket-sweep.lua. The window is one subject and this is another: the sheet
-- can be dragged, opened in a fight and closed by three routes without a single
-- one of these numbers moving, and every helper below is read here and nowhere
-- else. It ran over that file's own line ceiling, which is what noticed.
--
-- What this cannot prove: that the client agrees about any of it. The stub
-- answers what client/13-character.lua says it answers, and the two clients this
-- addon runs on disagree about three of the calls, which is why the ratings are
-- taken away below rather than assumed.

local H = ...
local ns, check = H.ns, H.check
local sheet = H.sheet

local Stats = ns.CharStats

-- The heading the three miss rows sit under. It carries the three levels so the
-- rows underneath do not have to, and it is named here because six checks below
-- read it.
local MISSING = "Missing a boss, three levels up"

-- Both halves of the stats as one list.
--
-- The sheet draws them on two tabs now, standard and extended, and every claim
-- in this file is about a number rather than about which tab it lands on. The
-- tabs are 52-gear-page.lua's subject; this is what the four constants add up
-- to, and it wants all of them.
local function Every()
	local groups = Stats.Standard()
	local extra = Stats.Extended()
	for index = 1, #extra do
		groups[#groups + 1] = extra[index]
	end
	return groups
end

local function Find(groups, title, label)
	for _, group in ipairs(groups) do
		if group.title == title then
			for _, row in ipairs(group.rows) do
				if row.label == label then
					return row
				end
			end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Missing, against the three published figures
----------------------------------------------------------------------

do
	local short = sheet.short
	sheet.short = 0

	check(math.abs(Stats.MeleeMiss(0) - 5.0) < 1e-6,
		("at the cap, a same level target reads %.2f%% and should read 5.00%%")
			:format(Stats.MeleeMiss(0)))
	check(math.abs(Stats.MeleeMiss(1) - 5.5) < 1e-6,
		("at the cap, one level up reads %.2f%% and should read 5.50%%")
			:format(Stats.MeleeMiss(1)))
	check(math.abs(Stats.MeleeMiss(2) - 6.0) < 1e-6,
		("at the cap, two levels up reads %.2f%% and should read 6.00%%")
			:format(Stats.MeleeMiss(2)))
	check(math.abs(Stats.MeleeMiss(3) - 9.0) < 1e-6,
		("at the cap, a boss reads %.2f%% and should read 9.00%%")
			:format(Stats.MeleeMiss(3)))

	-- And the shortfall, which is the branch a formula that stopped at the
	-- first ten points would get wrong. Ten points under the cap is six tenths
	-- of a percent each on top of the nine.
	sheet.short = 10
	check(math.abs(Stats.MeleeMiss(3) - 15.0) < 1e-6,
		("ten points of weapon skill short of the cap reads %.2f%% against a boss and should read 15.00%%")
			:format(Stats.MeleeMiss(3)))

	sheet.short = short
end

do
	local groups = Every()
	local special = Find(groups, MISSING, "a special")
	check(special ~= nil, "the stats page has no row for missing a special")
	check(special.value == ("%.2f%%"):format(Stats.MeleeMiss(3) - sheet.hitMelee),
		("the special row reads %s and the hit off the gear was not taken off it")
			:format(tostring(special and special.value)))

	-- The second weapon costs nineteen points on a white swing and nothing on a
	-- special, which is the one thing on this page that is a fact about you
	-- rather than about the target.
	local was = H.swing.off
	H.swing.off = 1.8
	local swing = Find(Every(), MISSING, "a white swing")
	check(swing.value == ("%.2f%%"):format(Stats.MeleeMiss(3) + 19 - sheet.hitMelee),
		("dual wielding, a white swing reads %s"):format(tostring(swing.value)))
	H.swing.off = was

	local skill = Find(Every(), MISSING, "weapon skill")
	check(skill ~= nil and skill.note:find("Under the cap", 1, true) ~= nil,
		"a weapon skill under the cap does not say so on the stats page")

	-- A spell never goes below one percent however much hit is on the gear, so
	-- the row is floored rather than reaching nothing.
	local spell = Find(groups, MISSING, "a spell")
	check(spell ~= nil and tonumber(spell.value:match("^([%d.]+)")) >= 1,
		"the spell row went under the floor a spell always has")
end

-- The older client, which has no combat ratings at all. Taking the index away
-- is what makes it that client for a moment: the page has to say it cannot
-- subtract rather than subtracting zero and reporting a clean sheet.
do
	local melee, spell = _G.CR_HIT_MELEE, _G.CR_HIT_SPELL
	_G.CR_HIT_MELEE, _G.CR_HIT_SPELL = nil, nil

	local row = Find(Every(), MISSING, "hit off your gear")
	check(row ~= nil and row.value:find("does not rate hit", 1, true) ~= nil,
		("with no ratings the hit row reads %s"):format(tostring(row and row.value)))
	local special = Find(Every(), MISSING, "a special")
	check(special.value == ("%.2f%%"):format(Stats.MeleeMiss(3)),
		"with no ratings something was still taken off the miss chance")
	check(Stats.Describe():find("no ratings", 1, true) ~= nil,
		("the status line does not say the client has no ratings: %s"):format(Stats.Describe()))

	_G.CR_HIT_MELEE, _G.CR_HIT_SPELL = melee, spell
end

-- A group with nothing to say is not drawn at all. The client answers a spell
-- crit chance and a mana regen for a warrior in plate, both off intellect
-- nobody chose to have, so the spell group hangs on spell power rather than on
-- whether its calls answered: rows of nought are how a page teaches you to stop
-- reading it.
do
	local groups = Every()
	local spell
	for _, group in ipairs(groups) do
		if group.title == "Spell" then
			spell = group
		end
	end
	check(spell == nil, "the spell group was drawn on a character with no spell power")
	sheet.spellPower = 640
	check(Find(Every(), "Spell", "spell power") ~= nil,
		"spell power on the gear and the spell group is still not drawn")
	sheet.spellPower = 0
	check(Find(groups, "Attributes", "strength") ~= nil, "the attributes group is missing")
	check(Find(groups, "Defence", "dodge") ~= nil, "the defence group is missing")
end

print("miss   5% on a same level target, 6% two up and 9% on a boss at the cap, 15% ten points short of it; the hit off your gear taken off a special, 19 points added for the off hand, and a client with no ratings says so instead of subtracting nothing")
