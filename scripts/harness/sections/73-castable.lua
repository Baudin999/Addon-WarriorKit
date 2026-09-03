-- What a square answers past its own cooldown
--
-- The cooldown row used to ask one question of a spell, whether its own
-- cooldown was running, and drew ready on every other answer. Bloodthirst read
-- ready at five rage, Overpower read ready with nothing having dodged you, and
-- a troll shaman's Berserking read ready for the whole of its three minutes
-- because the id the row held was the rogue's. The action bars had every one
-- of those rungs and the row had none.
--
-- Buttons/Castable.lua is the one ladder both climb now, and this section
-- drives it from the row's side. The row's own reads come first, moved here
-- from 42-cooldown-row.lua because every answer is held for the frame it was
-- given in and this section moves the clock between reads. Then each rung the
-- row never had, then the racial, which reads the same ladder and finds its id
-- in the book rather than in a table keyed by race.

local H = ...
local own, guids, logArgs, inCombat = H.own, H.guids, H.logArgs, H.inCombat
local advance, ns, fire, check = H.advance, H.ns, H.fire, H.check
local WARRIOR = H.WARRIOR

local Cooldowns, Row, Racials, Castable = ns.Cooldowns, ns.CooldownRow, ns.Racials, ns.Castable
local unusable, harmful = _G.WarriorKitUnusableSpells, _G.WarriorKitHarmfulSpells
local health = _G.WarriorKitHealth

local function tick()
	local running = ns.UI.Ticking("cooldowns")
	if running then
		running:Beat(0.2)
	end
end

-- The clock moves before the scene does. Castable.State holds its answer for
-- the frame GetTime names, the way Charge.State does, and this clock only
-- moves when a section moves it, so a scene changed in the same instant it
-- was last read would read the old answer back. That is a fact about a
-- stopped clock, and the memo is asserted on its own terms further down.
local function later()
	advance(0.1)
end

check(Castable ~= nil, "ns.Castable is not exported")

ns.db.cooldowns = true
ns.db.cooldownIdle = false
inCombat.player = false
local hadTarget = guids.target
guids.target = nil
fire("SPELLS_CHANGED")
later()
tick()

----------------------------------------------------------------------
-- What one square is doing
----------------------------------------------------------------------

if Cooldowns.Count() > 0 and Cooldowns.Entry(1).id then
	local entry = Cooldowns.Entry(1)

	local status = Cooldowns.State(1)
	check(status == "ready", ("a spell off cooldown reads as %s"):format(status))

	-- A global sweep is not a cooldown. Every square in the addon follows this
	-- rule and it is worth asserting on the one row where the whole point is the
	-- number: a row that counted the global would put 1.5 on every square every
	-- time you pressed anything.
	later()
	own.cooldowns[entry.id] = { _G.GetTime(), 1.5 }
	tick()
	status = Cooldowns.State(1)
	check(status == "ready", ("a global sweep read as %s"):format(status))

	later()
	own.cooldowns[entry.id] = { _G.GetTime(), 180 }
	tick()
	local start, duration
	status, start, duration = Cooldowns.State(1)
	check(status == "cooldown", ("a three minute wait reads as %s"):format(status))
	check(duration == 180, ("the swipe was handed %s seconds"):format(tostring(duration)))
	check(start == _G.GetTime(), "the swipe was handed the wrong start")

	-- Minutes, because a thirty minute cooldown on a 27 pixel square used to
	-- draw four digits of false precision. The whole ladder is walked here,
	-- because what a countdown has to get right is the seams: it rounds down, so
	-- 1m means a minute or more, and there is a label at every step from three
	-- minutes to the last tenth of a second.
	check(Row.Icon(1).timer:GetText() == "3m",
		("a three minute wait reads %q on the square"):format(Row.Icon(1).timer:GetText()))

	advance(61)
	tick()
	check(Row.Icon(1).timer:GetText() == "1m",
		("just under two minutes reads %q"):format(Row.Icon(1).timer:GetText()))

	advance(60)
	tick()
	check(Row.Icon(1).timer:GetText() == "59",
		("just under a minute reads %q"):format(Row.Icon(1).timer:GetText()))

	advance(55)
	tick()
	check(Row.Icon(1).timer:GetText() == "4.0",
		("four seconds left reads %q"):format(Row.Icon(1).timer:GetText()))

	-- The memo, on its own terms: read twice in one frame, the second read is
	-- the first one's answer whatever the client says in between, and the next
	-- frame reads the client again. That is the whole of what "per frame"
	-- means and it is what lets a bar and the row share one walk.
	own.cooldowns[entry.id] = nil
	check(Cooldowns.State(1) == "cooldown",
		"a second read in the same frame went back to the client")
	later()
	tick()
	check(Cooldowns.State(1) == "ready", "the next frame did not read the client again")

	-- The window it opened, which the client will not answer for: a cooldown
	-- starts the moment you press the ability and says nothing about whether
	-- the fifteen seconds you pressed it for are still running. The aura is the
	-- only source, and it is read on an event rather than on the tick.
	own.auras[1] = { name = entry.name, icon = "Interface\\Icons\\A" }
	fire("UNIT_AURA", "player")
	later()
	tick()
	local _, _, _, active = Cooldowns.State(1)
	check(active == true, ("%s is running and the square does not say so"):format(entry.name))

	own.auras[1] = nil
	fire("UNIT_AURA", "player")
	later()
	tick()
	_, _, _, active = Cooldowns.State(1)
	check(active == false, "the window stayed open after the aura came off")

	------------------------------------------------------------------
	-- The rungs the row never had
	--
	-- Each one driven through the same square, because a square that goes
	-- grey for every reason at once proves none of them. Cost and stance are
	-- the client's own two refusals, read by name so the rank on your bar is
	-- the rank that answers. Nothing to aim at is read off the target, and a
	-- real cooldown still outranks all three, because the swipe counts that
	-- one down and nothing counts the others.
	------------------------------------------------------------------

	later()
	unusable[entry.name] = "power"
	tick()
	status = Cooldowns.State(1)
	check(status == "cost", ("%s at no rage reads as %s"):format(entry.name, status))

	later()
	unusable[entry.name] = "stance"
	tick()
	status = Cooldowns.State(1)
	check(status == "stance", ("%s in the wrong stance reads as %s"):format(entry.name, status))

	later()
	unusable[entry.name] = nil
	harmful[entry.name] = true
	tick()
	status = Cooldowns.State(1)
	check(status == "notarget",
		("%s aimed at nothing reads as %s"):format(entry.name, status))

	later()
	own.cooldowns[entry.id] = { _G.GetTime(), 30 }
	unusable[entry.name] = "power"
	tick()
	status = Cooldowns.State(1)
	check(status == "cooldown",
		("a real wait under every other refusal reads as %s"):format(status))

	later()
	own.cooldowns[entry.id] = nil
	unusable[entry.name] = nil
	harmful[entry.name] = nil
	tick()
	status = Cooldowns.State(1)
	check(status == "ready", ("with everything cleared the square reads as %s"):format(status))

	-- The tooltip has a sentence for each, because a grey square with a
	-- picture on it and no number is the one square on the row that needs one.
	-- In a fight, because that is when the row paints.
	inCombat.player = true
	later()
	unusable[entry.name] = "power"
	tick()
	local w = Row.Icon(1)
	check(w.status == "cost", "the square did not keep the status for its tooltip")
	inCombat.player = false
	unusable[entry.name] = nil
	later()
	tick()
end

----------------------------------------------------------------------
-- The two rungs the client cannot answer at all
--
-- Overpower on the arms line and Revenge on the protection line are on the
-- row as well as on the bar, and the row said ready for the whole fight on
-- both. Execute is on no row, so its threshold is asked of the ladder
-- directly, which is the same call the row would make.
----------------------------------------------------------------------

local ME = "Player-0-0000000r"
local MOB = "Creature-0-0000000r"

-- Sixteen values matter here and each subevent puts the one this reads in a
-- different slot, so the slot is a parameter. The same helper 04-ability-square
-- carries, for the same line.
local function logLine(subevent, source, dest, at, value)
	for index = 1, 21 do
		logArgs[index] = nil
	end
	logArgs[1] = _G.GetTime()
	logArgs[2] = subevent
	logArgs[4] = source
	logArgs[8] = dest
	logArgs[12] = 300
	logArgs[at] = value
	fire("COMBAT_LOG_EVENT_UNFILTERED")
end

if WARRIOR then
	local hadPlayer = guids.player
	guids.player = ME
	guids.target = MOB

	local reactive
	for index = 1, Cooldowns.Count() do
		local key = Cooldowns.Entry(index).key
		if key == "overpower" or key == "revenge" then
			reactive = index
		end
	end
	if reactive then
		local entry = Cooldowns.Entry(reactive)
		later()
		tick()
		local status = Cooldowns.State(reactive)
		check(status == "reaction",
			("%s on the row reads %s with nothing having opened it"):format(entry.name, status))

		if entry.key == "overpower" then
			logLine("SWING_MISSED", ME, MOB, 12, "DODGE")
		else
			logLine("SWING_MISSED", MOB, ME, 12, "PARRY")
		end
		later()
		tick()
		status = Cooldowns.State(reactive)
		check(status == "ready", ("the window opened and the row reads %s"):format(status))

		advance(5.1)
		tick()
		status = Cooldowns.State(reactive)
		check(status == "reaction", ("the window lapsed and the row reads %s"):format(status))
	end

	-- Execute, asked of the ladder by the id the class file carries. At the
	-- default 4200 of 9000 the target is above a fifth; at 1700 it is under.
	local execute = ns.Class.Of("requires")
	execute = execute and execute[1] and execute[1].spell
	check(execute ~= nil, "the warrior file names no condition to drive")
	if execute then
		later()
		local status = Castable.State(execute)
		check(status == "condition",
			("Execute at half health reads %s off the ladder"):format(status))
		health.target = 1700
		later()
		status = Castable.State(execute)
		check(status == "ready", ("Execute under a fifth reads %s off the ladder"):format(status))
		health.target = nil
	end

	guids.player = hadPlayer
end

----------------------------------------------------------------------
-- Which racial is yours
--
-- Three ids per racial, one per power type, and the book says which one
-- this character knows. A troll shaman knows the mana Berserking and no
-- other, and asking the client about the rogue's is how the racial read
-- ready through the whole of its cooldown.
----------------------------------------------------------------------

own.race, own.raceName = "Troll", "Troll"
Racials.Forget()
check(Racials.Spell() == 26296, "a troll who knows every Berserking did not get the first")

own.unknown[26296], own.unknown[26297] = true, true
Racials.Forget()
check(Racials.Spell() == 20554,
	("a troll shaman, who knows only the mana Berserking, was handed %s"):format(tostring(Racials.Spell())))
check(Racials.Name() == "Berserking", "the shaman's Berserking is not named Berserking")

-- Held once found. A character does not change class, and the walk is three
-- client calls a tick until it is held.
own.unknown[20554] = true
check(Racials.Spell() == 20554, "the id found in the book was not held")

-- Nothing known at all answers the first the client names, and holds
-- nothing, so a book that has not loaded yet is read again next time.
Racials.Forget()
check(Racials.Spell() == 26296, "with nothing in the book the racial vanished rather than falling back")
check(Racials.Describe():find("not known", 1, true) ~= nil,
	"the status line does not say the id is a fallback: " .. Racials.Describe())
own.unknown[20554] = nil
check(Racials.Spell() == 20554, "a book that loaded late was never read again")
own.unknown[26296], own.unknown[26297] = nil, nil

own.race, own.raceName = "Orc", "Orc"
own.unknown[20572], own.unknown[33702] = true, true
Racials.Forget()
check(Racials.Spell() == 33697,
	("an orc shaman was handed %s for Blood Fury"):format(tostring(Racials.Spell())))
own.unknown[20572], own.unknown[33702] = nil, nil
Racials.Forget()
check(Racials.Spell() == 20572, "an orc warrior did not get Blood Fury back")

----------------------------------------------------------------------
-- And whether it is a press
--
-- The same ladder as the row. A racial you cannot afford is not idle, and
-- neither is one on cooldown, and the nag reads both off this one answer.
----------------------------------------------------------------------

later()
check(Racials.Ready(), "Blood Fury off cooldown and affordable reads as not ready")
check(Racials.Idle(), "an orc's ready Blood Fury is not idle")

later()
unusable["Blood Fury"] = "power"
check(not Racials.Ready(), "a racial you cannot afford reads as ready")
check(not Racials.Idle(), "a racial you cannot afford nags anyway")
unusable["Blood Fury"] = nil

later()
own.cooldowns[20572] = { _G.GetTime(), 120 }
check(not Racials.Ready(), "a racial on cooldown reads as ready")
check(Racials.Describe():find("cooldown", 1, true) ~= nil,
	"the status line does not say the racial is on cooldown: " .. Racials.Describe())
own.cooldowns[20572] = nil

later()
check(Racials.Ready(), "the racial did not come back when its cooldown ran out")

guids.target = hadTarget
later()
tick()

do
	local onRow = "no reactive square on this row"
	for index = 1, Cooldowns.Count() do
		local key = Cooldowns.Entry(index).key
		if key == "overpower" or key == "revenge" then
			onRow = key .. " on the row, shut until the fight opens it"
		end
	end
	print(("ladder %d squares read through Castable, %s; racial %s")
		:format(Cooldowns.Count(), onRow, Racials.Describe()))
end
