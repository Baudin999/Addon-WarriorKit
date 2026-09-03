-- The shared combat log reader
--
-- Four questions, and none of them is about what a line means. The three
-- sections under this one already ask that of the meters, the swing timer and
-- the breakdown record; this one asks about the thing in front of all of them.
--
-- Is the client asked once per line. Six parts read this log and each of them
-- used to call CombatLogGetCurrentEventInfo itself, which at sixty lines a
-- second in a pull is seven thousand value copies before any filter runs. The
-- stub counts its own calls, so this is the one assertion that can tell one
-- read handed to six readers from six reads.
--
-- Do two subscribers get the same line. The values go out as arguments rather
-- than in a table, which is what keeps the path free of allocation, and the
-- failure that shape allows is a second reader seeing a shifted list or a
-- half-consumed one.
--
-- Is your own GUID the twenty second value. Five of the six reject a line on
-- it, and one of them was calling UnitGUID on every line to ask. A reader that
-- got nil there would answer "not yours" to everything you did, which looks
-- exactly like a quiet fight.
--
-- And does the addon come off the event when nobody is reading. That is the
-- whole reason the file exists: a night with the meters, the breakdown and the
-- swing bars off should cost nothing at all rather than three unpacks a line.
-- The registration is read off the client stub rather than off the addon,
-- because a count the addon keeps and a registration the client holds are two
-- different facts and only the second one is the cost.

local H = ...
local ns, fire, check = H.ns, H.fire, H.check
local events, logArgs, logReads = H.events, H.logArgs, H.logReads
local guids, WARRIOR = H.guids, H.WARRIOR

local ME = "Player-0-00000d01"
local MOB = "Creature-0-0-0-0-4321-00000d02"

-- How many frames the client is holding for the combat log. One while anything
-- is reading and none while nothing is, whatever the number of readers.
local function registered()
	local list = events["COMBAT_LOG_EVENT_UNFILTERED"]
	return list and #list or 0
end

local function line(subevent, source, dest)
	for index = 1, 21 do
		logArgs[index] = nil
	end
	logArgs[1] = _G.GetTime()
	logArgs[2] = subevent
	logArgs[4] = source
	logArgs[8] = dest
	logArgs[12] = 4321
	logArgs[13] = "Mortal Strike"
	logArgs[15] = 700
	logArgs[21] = true
	fire("COMBAT_LOG_EVENT_UNFILTERED")
end

guids.player = ME
fire("PLAYER_ENTERING_WORLD")

check(ns.CombatLog.Ready(), "the shared reader says this client has no combat log")
check(ns.CombatLog.PlayerGUID() == ME,
	("the reader read the player as %s, expected %s")
		:format(tostring(ns.CombatLog.PlayerGUID()), ME))

----------------------------------------------------------------------
-- One line, one read, two readers
----------------------------------------------------------------------

-- What each probe saw, written in place. A table per line here would be this
-- section allocating on the path it is asserting does not.
local first, second = {}, {}

local function Probe(into)
	return function(...)
		local held = select("#", ...)
		for index = 1, held do
			into[index] = (select(index, ...))
		end
		into.n = held
		return true
	end
end

local readFirst = Probe(first)
local readSecond = Probe(second)

local base = ns.CombatLog.Count()
check(base > 0, "nothing in the addon is reading the combat log at all")
check(registered() == 1,
	("%d frames are registered for the combat log, and six readers want one")
		:format(registered()))

check(ns.CombatLog.Subscribe(readFirst), "the reader refused a subscriber")
check(ns.CombatLog.Subscribe(readSecond), "the reader refused a second subscriber")
check(ns.CombatLog.Count() == base + 2,
	("two subscribers took the list to %d, expected %d")
		:format(ns.CombatLog.Count(), base + 2))

-- Twice, because subscribing is idempotent the way the client's own
-- RegisterEvent is: a part that applies its settings twice reads a line once.
ns.CombatLog.Subscribe(readFirst)
check(ns.CombatLog.Count() == base + 2,
	"subscribing twice put the same reader on the list twice")

local reads = logReads()
line("SPELL_DAMAGE", ME, MOB)
check(logReads() == reads + 1,
	("one combat log line cost %d reads of the client, expected 1")
		:format(logReads() - reads))

check(first.n == 22 and second.n == 22,
	("the two readers were handed %s and %s values, expected 22 each")
		:format(tostring(first.n), tostring(second.n)))
check(first[2] == "SPELL_DAMAGE" and second[2] == "SPELL_DAMAGE",
	"a subscriber did not get the subevent in slot two")
check(first[4] == ME and first[8] == MOB,
	"a subscriber did not get the two ends of the event where the client puts them")
check(first[13] == "Mortal Strike" and first[21] == true,
	"a subscriber lost the far end of the list, which is where the off hand flag sits")
check(first[22] == ME and second[22] == ME,
	("the player GUID reached the readers as %s and %s, expected %s")
		:format(tostring(first[22]), tostring(second[22]), ME))

for index = 1, 22 do
	check(first[index] == second[index],
		("the two readers disagree about value %d: %s against %s")
			:format(index, tostring(first[index]), tostring(second[index])))
end

----------------------------------------------------------------------
-- And off the event when nobody is reading
----------------------------------------------------------------------

ns.CombatLog.Unsubscribe(readFirst)
ns.CombatLog.Unsubscribe(readSecond)
check(ns.CombatLog.Count() == base,
	("two subscribers left and the list holds %d, expected %d")
		:format(ns.CombatLog.Count(), base))

-- Every switch that can turn a reader off, turned off. What is left after this
-- is the reaction windows, which have no switch of their own: they are armed by
-- the class owning an ability that opens on a dodge or a block, and a class
-- that owns none never subscribed. So the empty case is real on three of the
-- four runs and the warrior run asserts the one reader that is left.
local held = {
	meter = ns.db.meter,
	breakdown = ns.db.breakdown,
	swing = ns.db.swing,
	combatFeed = ns.db.combatFeed,
	thankStrangers = ns.db.thankStrangers,
}

ns.db.meter, ns.db.breakdown, ns.db.swing = false, false, false
ns.db.combatFeed, ns.db.thankStrangers = false, false
ns.Meter.Apply()
ns.Breakdown.Apply()
ns.Swing.Apply()
ns.CombatFeed.Apply()
ns.Thanks.Apply()

local left = WARRIOR and 1 or 0
check(ns.CombatLog.Count() == left,
	("every switch is off and %d readers are left, expected %d")
		:format(ns.CombatLog.Count(), left))
check(registered() == left,
	("every switch is off and the client holds %d combat log registrations, expected %d")
		:format(registered(), left))

if not WARRIOR then
	-- Nothing is reading, so nothing is read. The count above is the addon's
	-- claim and this is the client's.
	reads = logReads()
	line("SPELL_DAMAGE", ME, MOB)
	check(logReads() == reads,
		"the client was asked for a line with nobody subscribed to hear it")

	-- And one subscriber puts the addon back on the event. The registration has
	-- to come back on its own, because a part switched on mid-session is the
	-- normal case and a reader that only registered at load would be silent for
	-- the rest of the evening. Asked here rather than above, because the list is
	-- empty on these runs and only an empty list can be seen to fill.
	ns.CombatLog.Subscribe(readFirst)
	check(registered() == 1,
		"a subscriber arriving at an empty list did not put the addon back on the event")
	ns.CombatLog.Unsubscribe(readFirst)
	check(registered() == 0, "the last subscriber left and the addon is still on the event")
end

----------------------------------------------------------------------

ns.db.meter, ns.db.breakdown, ns.db.swing = held.meter, held.breakdown, held.swing
ns.db.combatFeed, ns.db.thankStrangers = held.combatFeed, held.thankStrangers
ns.Meter.Apply()
ns.Breakdown.Apply()
ns.Swing.Apply()
ns.CombatFeed.Apply()
ns.Thanks.Apply()

check(ns.CombatLog.Count() == base,
	("the switches went back and %d readers are on the log, expected %d")
		:format(ns.CombatLog.Count(), base))

print(("log    %d readers on one client registration, one read a line, %d values"
	.. " with the player last, %d left on it with every switch off")
	:format(base, first.n, left))

guids.player = nil
