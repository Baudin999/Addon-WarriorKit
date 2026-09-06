-- Who nearby has a quest you have never taken
--
-- One claim: ns.QuestNear answers a list of npcs and a yardage for each, built
-- a slice at a time off one ticker, and it does no work at all in the three
-- states where the work would be thrown away.
--
-- **The budget is asserted by counting ticks, not by timing them.** The
-- fixture offers fifty one npcs and the walk takes twenty five per tick, so a
-- pass that finished on the tick it started is a pass that blocked. Three of
-- the four checks below the pass are therefore assertions that the answer is
-- still empty, which is the only shape "it did not do it all at once" has from
-- outside.
--
-- **The colon on GetNPC is proved by the answer having any names in it.** The
-- stub takes a self it ignores, exactly as Questie's own does, so a caller
-- reaching it with a dot passes the npc id in as that self and gets nil back
-- for every npc in the game. That failure raises nothing and reads as Questie
-- not being installed, which is why it is worth a fixture rather than a
-- comment.
--
-- **The two fields are broken one at a time.** ns.Questie asks whether the
-- calls you named are functions and cannot cover a data table, so
-- __availableQuestsByNpc absent, __availableQuestsByNpc set to a number, and
-- an npc row with no spawns are three separate readings and every one of them
-- has to end quietly rather than in an error.
--
-- **Three states do no work.** Nobody has asked; Questie has nothing to say;
-- you are standing in an instance. The third is the interesting one: Questie
-- adds half a million yards to every spawn outside the instance you are in, so
-- a pass run in a dungeon measures a thousand npcs and throws all of them away
-- at the cut.

local H = ...
local ns, check, advance = H.ns, H.check, H.advance
local near, dungeons, fire = H.near, H.dungeons, H.fire

local Near = ns.QuestNear

-- Fifty one of the fifty two npcs Questie is offering something on. 1241 is
-- the one it is not: his quests were all taken and Questie left the empty
-- table behind rather than taking him off the list.
local WALKED = 8 + near.FILLERS
local FOUND = 5

-- Past the wait between one pass and the next, and short of the half minute
-- with no reader that stops the walk.
local BETWEEN = 5

----------------------------------------------------------------------

local tick = ns.UI.Ticking("near")
check(tick ~= nil, "the walk armed no ticker on ns.UI.Forever")

-- One tick of the client, driven through the tick itself rather than through
-- the frame's OnUpdate: every permanent tick in the addon hangs off one frame,
-- so driving the frame would run twenty other parts on every line below.
local function beat(times)
	for _ = 1, times or 1 do
		tick:Beat(tick.interval)
	end
end

----------------------------------------------------------------------
-- Nothing until something asks
----------------------------------------------------------------------

Near.Forget()
beat(10)
check(#Near.List() == 0,
	"the walk built a list before anything had ever asked for one")

----------------------------------------------------------------------
-- A pass, over several ticks
----------------------------------------------------------------------

-- The call above is the first ask, so the pass starts on the next tick. One
-- tick to snapshot the npc ids and then one per slice of twenty five.
beat(1)
check(#Near.List() == 0, "a pass answered on the tick that started it")
beat(1)
check(#Near.List() == 0,
	("the first slice of a %d npc pass answered the whole of it"):format(WALKED))
beat(1)
check(#Near.List() == 0,
	("a %d npc pass finished inside two slices of twenty five"):format(WALKED))

beat(1)
local found = Near.List()
check(#found == FOUND,
	("the pass answered %d npcs and the fixture offers %d worth having")
		:format(#found, FOUND))

check(rawequal(Near.List(), found), "the answer is copied on the way out")

local by = {}
for _, entry in ipairs(found) do
	by[entry.npc] = entry
end

-- A name at all is the colon. See the header.
check(by[1234] and by[1234].name == "Farmer Furlbrow",
	"the npc rows came back nameless, which is what a dot call on GetNPC answers")
check(by[1234] and by[1234].distance == 60,
	("the nearest npc came back at %s yards")
		:format(by[1234] and tostring(by[1234].distance)))
check(by[1234] and by[1234].area == 40 and by[1234].x == 42.5 and by[1234].y == 61.0,
	"the spawn the yardage was measured to did not come back with it")
check(by[1234] and by[1234].quest == 26 and by[1234].quests == 1,
	"the one quest on an npc did not come back as one quest")

-- Two quest ids on one npc, and the lower is the one named. The order pairs
-- answers a table in is not the order it was written in, so naming the first
-- would name a different quest on different runs.
check(by[1235] and by[1235].quests == 2 and by[1235].quest == 19,
	"an npc holding two quests named the wrong one of them, or lost the count")

-- Two spawn tables and the near one wins, which is the whole of what
-- GetNearestSpawn is for.
check(by[1237] and by[1237].distance == 220 and by[1237].area == 12,
	"an npc standing in two places was measured to the far one")

-- A row with no name is still somebody standing near you.
check(by[1242] and by[1242].name == nil and by[1242].distance == 220,
	"an npc row with no name lost its entry rather than its name")

----------------------------------------------------------------------
-- Two npcs at one distance
----------------------------------------------------------------------

check(by[1234] and by[1235] and by[1234].distance == by[1235].distance,
	"two npcs standing the same distance away did not both come back")
check(by[1234] ~= by[1235],
	"two npcs at one distance came back sharing a single entry")

----------------------------------------------------------------------
-- What the pass leaves out
----------------------------------------------------------------------

check(by[1240] == nil,
	"an npc on the other continent was listed, and Questie adds half a million yards to say so")
check(by[1239] == nil, "an npc row with no spawns table was listed anyway")
check(by[1238] == nil,
	"a quest offered on an npc the database has no row for was listed anyway")
check(by[1241] == nil,
	"an npc whose quests have all been taken was listed off the empty table Questie leaves behind")
check(by[2001] == nil, "the forty three npcs on the other continent reached the answer")

check(Near.Describe() == ("%d near you have a quest you have never taken"):format(FOUND),
	("the reading says %q"):format(Near.Describe()))

----------------------------------------------------------------------
-- The two fields and the two calls, broken one at a time
----------------------------------------------------------------------

-- Ask, drive a whole pass's worth of ticks, and say what came out. Every one
-- of these has to end in an empty list rather than in an error.
local function quiet(what)
	Near.Forget()
	Near.List()
	beat(8)
	check(#Near.List() == 0, ("the walk built a list with %s"):format(what))
	near.Restore()
end

near.available.__availableQuestsByNpc = nil
quiet("no __availableQuestsByNpc on the module")

near.available.__availableQuestsByNpc = 7
quiet("a number where __availableQuestsByNpc should be")

near.available.__availableQuestsByNpc = {}
quiet("nobody on the whole of __availableQuestsByNpc")

near.db.GetNPC = nil
quiet("no GetNPC on the database")

near.db.GetNPC = 7
quiet("a number where GetNPC should be")

near.distances.GetNearestSpawn = nil
quiet("no GetNearestSpawn on DistanceUtils")

-- And the pair put back answers again, so the six above proved the break and
-- not the restore.
Near.Forget()
Near.List()
beat(4)
check(#Near.List() == FOUND, "the walk did not answer again once Questie did")

----------------------------------------------------------------------
-- Questie absent
----------------------------------------------------------------------

local loader = _G.QuestieLoader
_G.QuestieLoader = nil

Near.Forget()
Near.List()
beat(8)
check(#Near.List() == 0, "a client with no Questie built a list of who has a quest for you")
check(Near.Describe() == "Questie is not saying who has a quest for you",
	("the reading says %q"):format(Near.Describe()))

_G.QuestieLoader = loader

----------------------------------------------------------------------
-- Nobody reading
----------------------------------------------------------------------

Near.Forget()
Near.List()
advance(31)
beat(10)
check(#Near.List() == 0,
	"a pass ran for a reader that had not asked in half a minute")

-- The call in the check above is the ask, so this one runs.
beat(4)
check(#Near.List() == FOUND, "the walk did not start again when something asked")

----------------------------------------------------------------------
-- Indoors
----------------------------------------------------------------------

-- A finished answer first, so what walking into an instance does is drop one
-- rather than fail to build one. ns.QuestHere memoises on the map id and the
-- map is not changing here, so the held answer is dropped by hand.
dungeons.Inside("party")
ns.QuestHere.Forget()
fire("PLAYER_ENTERING_WORLD")

check(#Near.List() == 0,
	"walking into an instance left the list built outside it standing")
check(Near.Describe()
	== "indoors, where everything is thirty yards away and nothing is worth saying",
	("the reading says %q"):format(Near.Describe()))

advance(BETWEEN)
beat(10)
check(#Near.List() == 0, "the walk ran a pass while you were standing in a dungeon")

dungeons.Inside(nil)
ns.QuestHere.Forget()
fire("PLAYER_ENTERING_WORLD")

advance(BETWEEN)
Near.List()
beat(4)
check(#Near.List() == FOUND, "walking back out of the instance did not start the walk again")

----------------------------------------------------------------------

-- Everything this section moved, back the way it was found: the three Questie
-- names, the instance the client says you are in, and the walk's own state.
near.Restore()
dungeons.Inside(nil)
ns.QuestHere.Forget()
Near.Forget()

print(("near %s"):format(Near.Describe()))
