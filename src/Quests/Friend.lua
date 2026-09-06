local ADDON, ns = ...

local Friend = {}
ns.QuestFriend = Friend

local Near = ns.QuestNear
local Where = ns.QuestWhere

--------------------------------------------------------------------------
-- The line that says why not finish this one
--
-- One sentence at the foot of the tracker naming one person standing near you
-- with a quest that has never been in your log. Quests/Near.lua does the
-- walking; this decides which of its answers is worth a sentence, what the
-- sentence says, and when to keep quiet.
--
-- **It is a friend and not a route planner, and every rule below is that one
-- sentence.**
--
-- No number reaches the player. Questie's yardage is QuestieLib.Euclid over
-- world coordinates, which is a straight line through whatever is between you
-- and the murloc, and a cliff or a lake makes sixty of those yards a three
-- minute walk. Printing the figure would be a promise the data cannot keep.
-- The yardage is still what picks the person, because ranking is all it is
-- honest for.
--
-- What is printed instead is a direction, in eight words, and it is the one
-- thing here the game confirms as you walk: turn, and the words were right or
-- they were not. The arithmetic is this addon's own. UI/Chart.lua puts you and
-- the spawn into the same world yards, the bearing between them is an atan2,
-- the facing comes off the client, and the difference falls into one of eight
-- slices. A compass would be the other choice and it is worse: north is a fact
-- about the map, and a friend beside you says "behind you".
--
-- One person and one quest. Near.lua hands over the lowest quest id an npc is
-- offering rather than the first, so the same person names the same quest on
-- every pass and the line does not shuffle while you stand still. A second
-- name in the sentence would be a list, a list is a route, and a route is the
-- thing this was explicitly not going to be.
--
-- Nothing past ELSEWHERE, which is already Near.lua's cut: Questie adds half a
-- million yards to a spawn outside the instance you are standing in, and every
-- entry that reaches here is under it.
--
-- **It speaks when the answer changes, and then it stops.** QUIET seconds is
-- the whole clock. The line stands for that long, it will not be replaced
-- inside it by somebody nearer, and once it has run out the person it named is
-- not named again. A tracker redraws on QUEST_LOG_UPDATE, which the client
-- says several times a second while you are killing things, so a line worked
-- out fresh on every paint and drawn every time would be a sentence flickering
-- over the world all evening.
--
-- **The quiet period holds which quest is named, not how it is described.**
-- The pair is what stands for the twenty seconds; the direction is worked out
-- again on every reading. Caching the finished string instead is the one bug
-- the sentence above will not tolerate: turn round with a line standing and it
-- says "ahead of you" about somebody now behind you, for the rest of its
-- period, which is exactly the promise the direction was chosen over a yardage
-- to keep.
--
-- Silent in combat, and silent indoors. Near.lua already idles in an instance
-- because every spawn outside it is half a million yards away; this is the
-- second layer over the same fact, and it is the one that covers a walk into a
-- dungeon while a line is already standing.
--
-- **The list is read out again on every call and never kept.** Near.List hands
-- back the array it is holding, and the pass after next writes into the
-- entries in it.
--------------------------------------------------------------------------

-- The eight words, anticlockwise from straight ahead, because that is the
-- direction GetPlayerFacing counts in and turning them round in the table is
-- cheaper than turning the arithmetic round underneath it.
local WORDS = {
	"ahead of you",
	"ahead and to your left",
	"to your left",
	"behind and to your left",
	"behind you",
	"behind and to your right",
	"to your right",
	"ahead and to your right",
}

local TURN = math.pi * 2
local SLICE = TURN / #WORDS

-- How long the line stands, and how long it is quiet for afterwards.
--
-- One number rather than two, because they are one rule seen from both ends: a
-- sentence you have read is a sentence that has done its job, and the moment it
-- stops being worth reading is the moment somebody else is worth naming.
--
-- Twenty seconds is a reading and a look round. Longer and it is furniture;
-- shorter and it is gone before you have looked away from the fight.
local QUIET = 20.0

-- Who the line last named and when it named him. The pair is held rather than
-- the entry it came off, for the reason in the header: the entry belongs to
-- Near.lua's walk and is written into again. The sentence is not held at all,
-- for the other reason in the header.
local saidNpc, saidQuest, saidAt

--------------------------------------------------------------------------
-- Which way
--------------------------------------------------------------------------

-- The word for where a spawn is, from where you are standing and which way you
-- are pointing. Nothing at all where the client will not place one of the two,
-- which draws the sentence without its direction rather than with a wrong one.
--
-- Both ends go through the same call so that both are in the same frame of
-- yards, and the instances are compared because two places in different ones
-- have coordinates that mean nothing to each other.
local function Word(area, x, y)
	local map = Where.Map(area)
	if not map then
		return nil
	end
	local here, atX, atY = ns.UI.Chart.Here()
	if not here or not atX or not atY then
		return nil
	end
	local youNorth, youWest, yours = ns.UI.Chart.World(here, atX, atY)
	local hisNorth, hisWest, his = ns.UI.Chart.World(map, x, y)
	if not youNorth or not hisNorth or yours ~= his then
		return nil
	end
	local north, west = hisNorth - youNorth, hisWest - youWest
	-- Standing on him. atan2 answers nought for it, which would read as ahead,
	-- and there is no direction to give.
	if north == 0 and west == 0 then
		return nil
	end
	local turned = (math.atan2(west, north) - ns.UI.Chart.Facing()) % TURN
	return WORDS[math.floor(turned / SLICE + 0.5) % #WORDS + 1]
end

--------------------------------------------------------------------------
-- Who
--------------------------------------------------------------------------

-- The nearest person on the list with a quest on him, and one of them where
-- two are standing the same distance away.
--
-- The tie goes to the lower npc id, which is arbitrary and is the point: it is
-- the same answer on every pass, so two people at one distance is one line
-- rather than a sentence swapping between them.
--
-- An entry with no quest id is skipped rather than named. Near.lua leaves that
-- field empty where Questie's offer table lost the npc between the snapshot
-- and the measurement, and a line that cannot say which quest it means is a
-- line about nothing.
local function Nearest()
	local best
	for _, entry in ipairs(Near.List()) do
		if entry.quest and (not best or entry.distance < best.distance
			or (entry.distance == best.distance and entry.npc < best.npc)) then
			best = entry
		end
	end
	return best
end

-- The sentence itself. Four of them, because Questie's row carries no name for
-- some npcs and the client will not always place a spawn, and a sentence with
-- a hole in it reads as a bug rather than as a friend.
local function Phrase(name, word)
	if name and word then
		return ("%s, %s, has a quest you have never taken."):format(name, word)
	end
	if name then
		return ("%s has a quest you have never taken."):format(name)
	end
	if word then
		return ("Somebody %s has a quest you have never taken."):format(word)
	end
	return "Somebody near you has a quest you have never taken."
end

-- The sentence for one entry, worked out again on every reading rather than
-- kept. The name is a fact about the person and stands for the quiet period;
-- the word is a fact about where you are standing and which way you are
-- pointing, and both change under a line that is still standing.
local function Say(at)
	return Phrase(at.name, Word(at.area, at.x, at.y))
end

--------------------------------------------------------------------------
-- The line
--------------------------------------------------------------------------

-- Whether this is a moment for saying anything at all.
--
-- ns.QuestHere memoises on the map id, so the flag is a table lookup on a
-- paint. It is IsInInstance rather than the dungeon book, which is why raids
-- and battlegrounds are covered by the same line.
local function Hushed()
	local here = ns.QuestHere.Now()
	if here and here.dungeon then
		return true
	end
	return UnitAffectingCombat("player") and true or false
end

-- What the tracker puts at its foot right now, or nothing.
--
-- Called on every paint and answers the same string for as long as the same
-- person is the nearest, so the row does not flicker while the client repeats
-- QUEST_LOG_UPDATE at you.
function Friend.Line()
	if Hushed() then
		return nil
	end
	local at = Nearest()
	if not at then
		return nil
	end
	local now = GetTime()
	local quiet = saidAt and (now - saidAt) < QUIET
	if at.npc == saidNpc and at.quest == saidQuest then
		-- The one it is already saying. It stands out its twenty seconds and
		-- then it is done: walking past the same person for the rest of the
		-- evening is not news. Said again rather than repeated, so the
		-- direction is the one you are facing now.
		return quiet and Say(at) or nil
	end
	if quiet then
		return nil
	end
	saidNpc, saidQuest, saidAt = at.npc, at.quest, now
	return Say(at)
end

-- The clock and the name dropped, for the harness and for anything that has to
-- watch the line decide again. Nothing in the addon calls it: the quiet period
-- runs out on its own.
function Friend.Forget()
	saidNpc, saidQuest, saidAt = nil, nil, nil
end

-- Short enough for a reading on the options page, which never wraps, and with
-- no yardage in it for the reason the line itself has none.
function Friend.Describe()
	if Hushed() then
		return "quiet, because you are fighting or standing indoors"
	end
	local at = Nearest()
	if not at then
		return "nobody near you has a quest you have never taken"
	end
	-- The standing sentence, said the way the line would say it right now.
	-- Anything else inside the period is the line refusing to speak, and the
	-- reading says so rather than repeating what it said last.
	if saidAt and (GetTime() - saidAt) < QUIET
		and at.npc == saidNpc and at.quest == saidQuest then
		return Say(at)
	end
	if saidNpc then
		return "quiet, having named the last one already"
	end
	return "somebody near you has one, and the line is about to say so"
end
