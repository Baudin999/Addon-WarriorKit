-- The line at the foot of the tracker
--
-- ns.QuestFriend is a page of restraint holding up one sentence, and every rule
-- on that page is the kind that erodes in a refactor nobody meant anything by.
-- So the rules are driven rather than read: the fixture puts people near you,
-- turns you round and moves the clock, and what is asserted is the sentence
-- that comes out.
--
-- **One line, and only one.** Two npcs stand at the same yardage on purpose.
-- A second name in the sentence is a list, a list is a route, and a route is
-- the module this was explicitly not going to be, so the count of friend lines
-- on the column is an assertion of its own rather than a string comparison
-- that happens to pass.
--
-- **The direction is arithmetic and is proved as arithmetic.** The same person
-- is read twice from the same spot with the player turned half a circle
-- between, and the two words have to be opposites. That is the half of the
-- reading this harness can honestly answer for. Which way is north it cannot:
-- the world position fixture folds a map id into one of its two numbers and
-- keeps the map's own axes rather than the compass's, so the absolute word is
-- a fact about the fixture. The signs against the live client are argued out
-- on UI/Chart.lua, off HereBeDragons on disk.
--
-- **Silence is three separate things.** Nobody worth naming, standing indoors,
-- and fighting are three code paths and the last two both leave a tracker on
-- the screen with the sentence gone off the bottom of it, which is why they are
-- read off the frames and not off the module.
--
-- Everything this moves is put back at the foot of the file: where you are
-- standing, the tracker switch, the lock, whether you are in an instance,
-- whether you are fighting, which way you are facing, Questie's offer table and
-- the walk's own state.

local H = ...
local ns, check, advance = H.ns, H.check, H.advance
local near, dungeons, worldmap = H.near, H.dungeons, H.worldmap
local quests, combat = H.quests, H.inCombat

local Column, Friend, Near = ns.QuestColumn, ns.QuestFriend, ns.QuestNear

local standing = quests.standing
local WAS_MAP = standing.map
local WAS_OFF = ns.db.questsTrackerOff
local WAS_LOCK = ns.db.locked

-- Westfall, where the log has one quest and the fixture has two npcs sixty
-- yards away and three at two hundred and twenty.
local WESTFALL = 52

-- Past the module's own quiet period, which is twenty seconds.
local PAST = 21

-- What the line says about the nearer of the two at sixty yards, from where the
-- quest fixture stands you and facing north. Farmer Furlbrow rather than Salma
-- Saldean because the tie goes to the lower npc id, which is the whole of what
-- makes two people at one distance one sentence.
local FURLBROW = "Farmer Furlbrow, ahead and to your right, "
	.. "has a quest you have never taken."
local TURNED = "Farmer Furlbrow, behind and to your left, "
	.. "has a quest you have never taken."

----------------------------------------------------------------------

ns.db.locked = true
ns.db.questsTrackerOff = true
standing.map = WESTFALL
dungeons.Inside(nil)
combat.player = nil
worldmap.Face(0)
ns.QuestHere.Forget()
Column.Apply()

local frame = _G.WarriorKitQuestColumn
local tick = ns.UI.Ticking("near")

-- The stack's own frame, found the way 85-quest-column finds it: the one child
-- of the tracker with rows under it.
local function canvas()
	for _, child in ipairs(frame.children) do
		if #child.children > 0 then
			return child
		end
	end
	return nil
end

-- Every string the column is drawing, top down.
local function drawn()
	local out = {}
	for _, row in ipairs(canvas().children) do
		if row.shown then
			for _, text in ipairs(row.regions) do
				if text.kind == "fontstring" and text.text ~= "" then
					out[#out + 1] = text.text
				end
			end
		end
	end
	return out
end

-- The friend's lines on the column, as opposed to the quest names and the
-- objectives. A list rather than the first one found, because how many there
-- are is the assertion.
local function asides()
	local out = {}
	for _, line in ipairs(drawn()) do
		if line:find("never taken", 1, true) then
			out[#out + 1] = line
		end
	end
	return out
end

-- One whole pass of ns.QuestNear, from nothing. One tick to snapshot the ids
-- and one per slice of twenty five, and six is room for all of them.
local function walk()
	Near.Forget()
	Near.List()
	for _ = 1, 6 do
		tick:Beat(tick.interval)
	end
	return #Near.List()
end

-- A fresh reading with no memory of the last one, for the cases that are about
-- what the sentence says rather than about when it is allowed to say it.
local function fresh()
	Friend.Forget()
	return Friend.Line()
end

local seen = {}

----------------------------------------------------------------------
-- Two npcs at one distance, one line
----------------------------------------------------------------------

check(walk() == 5, ("the walk found %d npcs and the fixture offers five worth having")
	:format(#Near.List()))

check(fresh() == FURLBROW, ("the line says %q"):format(tostring(Friend.Line())))

-- Off the frames, because a module that answered one sentence and a column that
-- drew two would pass every assertion above.
Column.Refresh()
check(#asides() == 1,
	("the column drew %d lines naming somebody nearby, and one is the rule")
		:format(#asides()))
check(asides()[1] == FURLBROW,
	("the column drew %q at its foot"):format(tostring(asides()[1])))
check(#drawn() == 4,
	("the column drew %d rows, where one quest, two objectives and one line is four")
		:format(#drawn()))
seen[#seen + 1] = asides()[1]

----------------------------------------------------------------------
-- Which way, and it is arithmetic
----------------------------------------------------------------------

-- The same person from the same spot, with the player turned half a circle.
-- Ahead and to the right has to become behind and to the left, and nothing else
-- about the sentence may move.
worldmap.Face(math.pi)
check(fresh() == TURNED,
	("turned round, the line says %q"):format(tostring(Friend.Line())))
seen[#seen + 1] = "turned round it says " .. TURNED

worldmap.Face(0)
check(fresh() == FURLBROW, "turning back did not give the first word back")

-- No yardage anywhere in it. The distance is Euclidean over world coordinates
-- and a cliff between you and the murloc makes sixty of those yards a three
-- minute walk, so the number is what picks the person and never what is said.
check(not Friend.Line():find("%d"),
	("the line has a number in it: %q"):format(Friend.Line()))

----------------------------------------------------------------------
-- Not twice inside the quiet period
----------------------------------------------------------------------

-- Farmer Furlbrow has just been named. Take him off Questie's offer table, so
-- the nearest person with something to say is somebody else, and ask again
-- inside the twenty seconds. It has to say nothing at all rather than swap.
local offers = near.available.__availableQuestsByNpc
near.available.__availableQuestsByNpc = { [1235] = { [22] = true, [19] = true } }
check(walk() == 1, "the offer table was cut to one npc and the walk found others")
check(Friend.Line() == nil,
	("a second ask inside the quiet period said %q")
		:format(tostring(Friend.Line())))

-- And past it, the person who is actually nearest gets the line.
advance(PAST)
Near.List()
check(Friend.Line() ~= nil, "the line stayed quiet after its own period had run out")
check(Friend.Line():find("Salma Saldean", 1, true) ~= nil,
	("past the quiet period the line says %q"):format(Friend.Line()))
seen[#seen + 1] = "then " .. Friend.Line()

----------------------------------------------------------------------
-- Not again for the thing it just named
----------------------------------------------------------------------

-- Nobody has moved and nothing has changed. Salma Saldean is still the only
-- person offering anything, and once her twenty seconds are out she is not
-- news any more: walking past the same person all evening is not a friend.
advance(PAST)
Near.List()
check(Friend.Line() == nil,
	("the line named the same person again: %q"):format(tostring(Friend.Line())))

Column.Refresh()
check(#asides() == 0, "the column is still drawing a line the module has stopped saying")

near.available.__availableQuestsByNpc = offers
walk()

----------------------------------------------------------------------
-- Nothing past the other continent's cut
----------------------------------------------------------------------

-- Thrall, standing in Stormwind, which the yardage fixture uses as anywhere you
-- are not: Questie adds half a million yards to a spawn outside the instance
-- you are in so that local things sort first. He is the only person offering
-- anything here, and the answer is still nobody.
near.available.__availableQuestsByNpc = { [1240] = { [3] = true } }
check(walk() == 0, "an npc on the other continent reached the list the line reads")
check(fresh() == nil,
	("the line named somebody on the other continent: %q"):format(tostring(Friend.Line())))

near.available.__availableQuestsByNpc = offers
walk()

----------------------------------------------------------------------
-- A row with no name, and a client that will not place one
----------------------------------------------------------------------

-- Questie's database carries rows with no name on them. The sentence has to
-- lose the name rather than the sentence.
near.available.__availableQuestsByNpc = { [1242] = { [62] = true } }
walk()
local nameless = fresh()
check(nameless ~= nil and nameless:find("^Somebody ") ~= nil,
	("an npc row with no name drew %q"):format(tostring(nameless)))
seen[#seen + 1] = nameless

-- And the same the other way: a client that will not turn a map coordinate into
-- yards leaves the direction off rather than guessing one.
near.available.__availableQuestsByNpc = offers
walk()
local worldPos = _G.C_Map.GetWorldPosFromMapPos
_G.C_Map.GetWorldPosFromMapPos = nil
check(fresh() == "Farmer Furlbrow has a quest you have never taken.",
	("with no world position the line says %q"):format(tostring(Friend.Line())))
_G.C_Map.GetWorldPosFromMapPos = worldPos

----------------------------------------------------------------------
-- Nothing in combat
----------------------------------------------------------------------

-- The tracker stays up and the sentence goes. Driven through the client's own
-- event, because the swords coming out is not otherwise a thing this column
-- hears and a line that sat over the fight until the next QUEST_LOG_UPDATE
-- happened along would pass a check made against the module alone.
check(fresh() ~= nil, "the line was already quiet before the fight started")
combat.player = true
H.fire("PLAYER_REGEN_DISABLED")
check(Friend.Line() == nil, "the line spoke while you were fighting")
check(frame:IsShown(), "the tracker went away with the fight rather than the line")
check(#asides() == 0,
	("the column drew %d lines naming somebody nearby during a fight")
		:format(#asides()))

combat.player = nil
H.fire("PLAYER_REGEN_ENABLED")
check(#asides() == 1, "the line did not come back when the fight ended")

----------------------------------------------------------------------
-- Nothing indoors
----------------------------------------------------------------------

-- IsInInstance rather than the dungeon book, so raids and battlegrounds are
-- covered by the same rule. You are still standing on Westfall's map, so the
-- log's Westfall quest is still on the tracker and what goes away is the line
-- and nothing else.
dungeons.Inside("party")
ns.QuestHere.Forget()
H.fire("PLAYER_ENTERING_WORLD")

check(Friend.Line() == nil, "the line spoke while you were standing in an instance")
check(Column.Describe() == "one quest, in Westfall",
	("indoors the tracker says %q"):format(Column.Describe()))
check(frame:IsShown(), "the tracker went away indoors rather than the line")
check(#asides() == 0,
	("the column drew %d lines naming somebody nearby indoors"):format(#asides()))
check(Friend.Describe() == "quiet, because you are fighting or standing indoors",
	("the reading says %q"):format(Friend.Describe()))

dungeons.Inside(nil)
ns.QuestHere.Forget()
H.fire("PLAYER_ENTERING_WORLD")

----------------------------------------------------------------------
-- Nobody to name
----------------------------------------------------------------------

near.available.__availableQuestsByNpc = {}
walk()
check(fresh() == nil, "the line named somebody off an empty offer table")
Column.Refresh()
check(#asides() == 0, "the column drew a line off an empty offer table")
check(Friend.Describe() == "nobody near you has a quest you have never taken",
	("the reading says %q"):format(Friend.Describe()))

----------------------------------------------------------------------

-- Everything this section moved, back the way it was found.
near.available.__availableQuestsByNpc = offers
near.Restore()
dungeons.Inside(nil)
combat.player = nil
worldmap.Face(0)
ns.QuestHere.Forget()
Near.Forget()
Friend.Forget()
ns.db.questsTrackerOff = WAS_OFF
ns.db.locked = WAS_LOCK
standing.map = WAS_MAP
Column.Apply()

print(("the friend says %s"):format(table.concat(seen, "; ")))
