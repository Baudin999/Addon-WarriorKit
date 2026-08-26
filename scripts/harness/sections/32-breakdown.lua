-- The breakdown
--
-- Six questions no amount of reading Breakdown/ will answer.
--
-- Do the numbers land in the right slot. The whole file is positional reads of
-- the combat log, and a swing puts its amount where a spell puts its id. A
-- parser that read the wrong slot would file a spell id as a damage number and
-- the table would look populated and be nonsense.
--
-- Is a crit counted as a hit as well as a crit. Crits are a subset of landed
-- hits and not a separate outcome, and getting that wrong gives a crit rate
-- over the wrong denominator, which is the single number this feature exists to
-- report.
--
-- Are the two averages actually separable. Keeping crit damage apart from total
-- damage is the whole reason four counters are stored rather than two, and the
-- claim is that the average normal hit and the average crit both come back out.
-- A blended average would satisfy any test that only checked the total.
--
-- Does a miss keep its type. A dodge and a parry mean different things to a
-- warrior and the store keeps them apart on purpose; a pooled counter would
-- pass every test about miss chance and lose the thing worth knowing.
--
-- Does the level band actually band. The combat log carries no level, so this
-- rests on a cache fed from targets and nameplates, and the failure mode is
-- silent: everything lands in one bucket and every rate is an average of
-- unrelated fights.
--
-- And does the roll up by name join ranks without joining anything else.

local H = ...
local guids, logArgs, ns = H.guids, H.logArgs, H.ns
local fire, check = H.fire, H.check

local Breakdown, Pane = ns.Breakdown, ns.BreakdownWindow

-- The sections above leave the player with no GUID, which is what the client
-- looks like across a loading screen. PLAYER_ENTERING_WORLD is what this
-- part reads its own GUID and level on, so it is fired rather than the
-- module local being reached into.
guids.player = "Player-0-0000000f"
fire("PLAYER_ENTERING_WORLD")
Breakdown.Reset()

local ME = guids.player
local MOB = "Creature-0-0-0-0-4321-00000001"
local UNSEEN = "Creature-0-0-0-0-4321-00000002"

local function log(subevent, source, dest, slots)
	for index = 1, 21 do
		logArgs[index] = nil
	end
	logArgs[1] = GetTime()
	logArgs[2] = subevent
	logArgs[4] = source
	logArgs[8] = dest
	for at, value in pairs(slots) do
		logArgs[at] = value
	end
	fire("COMBAT_LOG_EVENT_UNFILTERED")
end

-- One row out of the ranked list, by name, so an assertion names the
-- ability it is about rather than an index that moves as the sort does.
local function row(name, band)
	local ranked = Breakdown.Rank(band)
	for index = 1, #ranked do
		if ranked[index].name == name then
			return ranked[index]
		end
	end
	return nil
end

check(Breakdown.Ready(), "the breakdown says this client has no combat log")
check(Breakdown.Count() == 0, "the store did not start empty")
check(Breakdown.Since() > 0, "a reset did not stamp when the count started")

----------------------------------------------------------------------
-- Which slot the number is in
----------------------------------------------------------------------

-- A white swing carries its amount at twelve and has no spell in front of
-- it. A parser that read slot fifteen would find nothing and count nothing.
log("SWING_DAMAGE", ME, UNSEEN, { [12] = 137 })
local melee = row(ns.SpellName(6603) or "Melee")
check(melee ~= nil, "a white swing did not reach the table")
check(melee and melee.damage == 137, "a swing's amount was not read from slot twelve")
check(melee and melee.name == "Attack",
	("a swing is filed under %s, expected the client's own word for it")
		:format(tostring(melee and melee.name)))

-- A spell carries its id, name and school first and its amount at fifteen.
log("SPELL_DAMAGE", ME, UNSEEN, { [12] = 12294, [13] = "Mortal Strike", [15] = 500 })
log("SPELL_DAMAGE", ME, UNSEEN, { [12] = 12294, [13] = "Mortal Strike", [15] = 900, [21] = true })

local ms = row("Mortal Strike")
check(ms ~= nil, "a spell did not reach the table")
check(ms and ms.damage == 1400, ("Mortal Strike totals %s, expected 1400")
	:format(tostring(ms and ms.damage)))

----------------------------------------------------------------------
-- Crits are a subset of hits, and the two averages come apart
----------------------------------------------------------------------

check(ms and ms.landed == 2, ("%s landed hits, expected the crit to count as one too")
	:format(tostring(ms and ms.landed)))
check(ms and ms.crits == 1, "the critical was not counted as one")
check(Breakdown.CritRate(ms) == 0.5,
	("crit rate came back %s, expected one crit in two landed hits")
		:format(tostring(Breakdown.CritRate(ms))))

-- The claim that keeping crit damage apart is worth a counter. A blended
-- average of a 500 and a 900 is 700, which is a number describing no hit
-- this character has ever landed.
check(Breakdown.AverageHit(ms) == 500,
	("the average normal hit came back %s, expected 500 and not a blend with the crit")
		:format(tostring(Breakdown.AverageHit(ms))))
check(Breakdown.AverageCrit(ms) == 900,
	("the average crit came back %s, expected 900"):format(tostring(Breakdown.AverageCrit(ms))))

----------------------------------------------------------------------
-- Overkill
--
-- The client sends the wasted part in the slot after the amount and sends
-- minus one on every hit that killed nothing. Meter/Meter.lua subtracts it
-- and this has to agree, or the two readouts cannot be compared.
----------------------------------------------------------------------

log("SPELL_DAMAGE", ME, UNSEEN, { [12] = 772, [13] = "Rend", [15] = 300, [16] = 100 })
local rend = row("Rend")
check(rend and rend.damage == 200,
	("Rend counted %s of a 300 hit that wasted 100"):format(tostring(rend and rend.damage)))
check(rend and rend.wasted == 100, "the wasted part was not kept")
check(rend and rend.max == 200, "the best hit recorded the raw number rather than the effective one")

log("SPELL_DAMAGE", ME, UNSEEN, { [12] = 772, [13] = "Rend", [15] = 50, [16] = -1 })
rend = row("Rend")
check(rend and rend.damage == 250,
	("a minus one overkill changed the total to %s"):format(tostring(rend and rend.damage)))

----------------------------------------------------------------------
-- A miss keeps its type
----------------------------------------------------------------------

log("SPELL_MISSED", ME, UNSEEN, { [12] = 12294, [13] = "Mortal Strike", [15] = "DODGE" })
log("SPELL_MISSED", ME, UNSEEN, { [12] = 12294, [13] = "Mortal Strike", [15] = "PARRY" })
ms = row("Mortal Strike")

check(ms and ms.misses == 2, "two stopped attempts did not both count")
check(Breakdown.Attempts(ms) == 4, ("%s attempts, expected two landed and two stopped")
	:format(tostring(Breakdown.Attempts(ms))))
check(Breakdown.MissRate(ms) == 0.5, "the miss rate is not stopped attempts over every attempt")
check(Breakdown.MissRateOf(ms, "DODGE") == 0.25, "a dodge did not keep its own rate")
check(Breakdown.MissRateOf(ms, "PARRY") == 0.25, "a parry did not keep its own rate")
check(Breakdown.MissRateOf(ms, "MISS") == nil,
	"an outcome that never happened is being reported as a zero rate")

-- A stopped attempt is not a landed hit, so it must not move the crit rate.
check(Breakdown.CritRate(ms) == 0.5, "a dodge changed the crit rate")

----------------------------------------------------------------------
-- What is in the ranking, and what is only in the store
--
-- The table is ranked by damage, so a row has to have attempted damage to
-- be in it. An ability that has only ever been pressed is counted and kept
-- and not listed, or the top of a damage table is a run of zeroes: Battle
-- Shout, Charge and every stance, above the abilities you opened it to
-- read. The failure mode of getting this wrong is exactly what shipped
-- before it, so it is asserted from both ends.
----------------------------------------------------------------------

local held = Breakdown.Count()
log("SPELL_CAST_SUCCESS", ME, UNSEEN, { [12] = 6673, [13] = "Battle Shout" })
check(Breakdown.Count() == held + 1, "a cast that does no damage was not counted at all")
check(row("Battle Shout") == nil,
	"an ability that has never attempted damage is in a table ranked by damage")

-- A cast is still worth counting for an ability that does damage, because
-- how often you pressed it is half of whether it paid for itself. The casts
-- from before the first landed hit have to survive to that hit.
log("SPELL_CAST_SUCCESS", ME, UNSEEN, { [12] = 1464, [13] = "Slam" })
log("SPELL_CAST_SUCCESS", ME, UNSEEN, { [12] = 1464, [13] = "Slam" })
check(row("Slam") == nil, "a cast alone put a row in the ranking")

log("SPELL_DAMAGE", ME, UNSEEN, { [12] = 1464, [13] = "Slam", [15] = 400 })
local slam = row("Slam")
check(slam and slam.casts == 2, "the casts before the first landed hit were lost")
check(slam and Breakdown.Attempts(slam) == 1, "a cast was counted as an attempt")

-- An ability that has only ever been stopped. No damage across two dodges
-- is not the same fact as no damage because the thing does none, and it is
-- the more useful of the two, so it keeps its row.
log("SPELL_MISSED", ME, UNSEEN, { [12] = 845, [13] = "Cleave", [15] = "DODGE" })
local cleave = row("Cleave")
check(cleave ~= nil, "an ability that has only ever been dodged lost its row")
check(cleave and cleave.damage == 0, "a dodge added damage")
check(Breakdown.CritRate(cleave) == nil, "a spell with no landed hits reported a crit rate")

----------------------------------------------------------------------
-- Somebody else's fight
--
-- The one filter that keeps the table bounded. Without it the store grows
-- by every stranger you have ever been in a party with.
----------------------------------------------------------------------

held = Breakdown.Count()
log("SPELL_DAMAGE", "Player-9", UNSEEN, { [12] = 9999, [13] = "Someone Else", [15] = 4000 })
check(Breakdown.Count() == held, "another player's damage was counted as yours")

----------------------------------------------------------------------
-- The level bands
--
-- The combat log carries no level, so this rests entirely on the cache fed
-- from your target and from nameplates. The failure is silent: everything
-- lands in one band and every rate becomes an average of unrelated fights.
----------------------------------------------------------------------

_G.WarriorKitLevels.target = 65
guids.target = MOB
fire("PLAYER_TARGET_CHANGED")

log("SPELL_DAMAGE", ME, MOB, { [12] = 845, [13] = "Cleave", [15] = 220 })
check(row("Cleave", 3) ~= nil, "a mob three levels over you did not land in the third band")
check(row("Cleave", 1) == nil, "a mob three levels over you was counted as at or under you")

-- A mob you never targeted and never saw a plate for. It has to land in the
-- band that says so rather than being quietly counted as your own level,
-- which is the answer that would flatter every rate in the table.
log("SPELL_DAMAGE", ME, UNSEEN, { [12] = 845, [13] = "Cleave", [15] = 180 })
check(row("Cleave", 4) ~= nil, "a mob whose level was never seen did not land in the unknown band")
check(row("Cleave").damage == 400, "the bands do not add back up to the total")

----------------------------------------------------------------------
-- Ranks roll up, and nothing else does
----------------------------------------------------------------------

log("SPELL_DAMAGE", ME, UNSEEN, { [12] = 11574, [13] = "Rend", [15] = 90 })
check(Breakdown.Count() >= 2, "two ranks of Rend were stored under one key")
rend = row("Rend")
check(rend and rend.damage == 340,
	("two ranks of Rend read back as %s, expected them added up under one name")
		:format(tostring(rend and rend.damage)))
check(row("Mortal Strike").damage == 1400, "the roll up joined two different abilities")

----------------------------------------------------------------------
-- The table in its window
----------------------------------------------------------------------

Pane.Open()
check(Pane.IsShown(), "the breakdown window did not open")
check(Pane.Shown() > 0, "the breakdown drew no rows with a table full of abilities")
check(Pane.Row(1).name:GetText() == "Mortal Strike",
	("the top row by damage is %s, expected the biggest total")
		:format(tostring(Pane.Row(1).name:GetText())))
check(Pane.Row(1).bar:GetWidth() > Pane.Row(2).bar:GetWidth(),
	"the share bars do not rank the rows")
check(Pane.Row(1).icon.texture ~= nil, "a row drew no icon")

-- Escape has to close it, and Escape is a list of frame names rather than a
-- key anything here can press. A window that never joined the list is one
-- you can only close with the mouse, and nothing else would say so.
local escapes = false
for _, name in ipairs(_G.UISpecialFrames) do
	if name == "WarriorKitBreakdown" then
		escapes = true
	end
end
check(escapes, "the breakdown window is not in UISpecialFrames, so Escape leaves it open")

-- The utility spell in the store is not one of the rows on screen, which is
-- the same claim as the ranking check above made through the window rather
-- than through Rank.
for index = 1, Pane.Shown() do
	check(Pane.Row(index).name:GetText() ~= "Battle Shout",
		"the window drew a row for an ability that has never done damage")
end

----------------------------------------------------------------------
-- Starting again
----------------------------------------------------------------------

local since = Breakdown.Since()
Breakdown.Reset()
check(Breakdown.Count() == 0, "a reset left abilities in the store")
check(Breakdown.Since() >= since, "a reset did not restamp when the count started")
Pane.Paint()
check(Pane.Shown() == 0, "the window still drew rows after a reset")
Pane.Close()
check(not Pane.IsShown(), "the breakdown window would not close")

print(("break  %s; %d bands, melee as %q")
	:format(Breakdown.Describe(), #Breakdown.Bands(), ns.SpellName(6603) or "Melee"))
