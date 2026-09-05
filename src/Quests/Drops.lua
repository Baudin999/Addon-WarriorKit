local ADDON, ns = ...

local Drops = {}
ns.QuestDrops = Drops

local C = ns.UI.Color

--------------------------------------------------------------------------
-- What a creature is carrying that a quest of yours wants
--
-- Point at a boar and the client tells you it is a boar. What it does not tell
-- you is that eight of its hides are the difference between you and the end of
-- the quest in your log, that you already have three, and that the last four
-- boars had nothing on them. All three of those are things you know while you
-- are killing the boars and forget by the time you come back to the zone, and
-- the second one is the reason people open the quest log between pulls.
--
-- So this hangs three lines off the world hover, and each of them answers a
-- different question:
--
--   which quest   the name of the thing in your log this creature feeds
--   what for      the objective's own words, and the client's counter under
--                 them as collected of needed
--   how often     what fraction of the kills drop it
--
-- **All of it is Questie's and the client's, and none of it is guessed.**
--
-- Questie is the only thing on either client that knows a creature feeds a
-- quest at all. There is no API for it: the client will tell you what a quest
-- wants and never what carries it or where it walks. Questie carries a database
-- row per creature and registers, per objective, the key `m_<npc id>` against
-- every spawn that would tick it. That table is what this file reads, and reads
-- only: nothing here calls Update on one of Questie's objectives or writes a
-- field on it. A part that mutates another addon's state is a part that breaks
-- when the other addon changes and cannot be blamed for it.
--
-- **Every kind of objective, not only the ones that drop something.** Questie
-- files five kinds under that key and this file read one of them for a long
-- time, `item`, which is why the hover people actually wanted was the hover
-- that said nothing. A creature you have to kill eight of is a `monster`
-- objective, it is the commonest quest in the game, and it fell out one line
-- above the box being built. WANTED below is the list, and the reason it is a
-- list rather than a comparison is that the next kind Questie adds should show
-- up as a missing entry rather than as silence.
--
-- **The drop chance has two sources and they are not equal.** Questie v11 ships
-- a drop table -- three databases deep, keyed item then npc, reachable through
-- QuestieDB.GetItemDroprate -- and that is the number printed wherever it
-- answers, because it is there on the first hover. The note that used to stand
-- here said no database on either client carried one, and that was true of the
-- v6 this file was written against and is false of the v11 in the game.
--
-- Under it is the ledger, which is this addon's own and is counted rather than
-- looked up: every corpse of that creature you open the loot window on is one
-- sample and every one that had the item on it is a hit. It is what the box
-- says where Questie's table has no row, and it is printed beside Questie's
-- where both have an answer, because a rate scraped off a database and a rate
-- off four hundred of your own kills disagreeing is the single most useful
-- thing either of them can tell you.
--
-- It says nothing until it has enough corpses to be worth saying. A creature
-- you have looted twice with one drop is not a fifty percent drop rate, it is
-- two corpses, and a tooltip that rounds that to a number is a tooltip lying
-- with arithmetic. FLOOR is where it starts talking.
--
-- **Nothing here is a fallback.** With Questie absent, no line is drawn and the
-- box is the name and the client's own words, which is what it was before this
-- file existed. That is the shape every part of this addon that leans on
-- another one has: degrade to the box you would have had, never to a guess.
--------------------------------------------------------------------------

-- The fewest corpses before a fraction is worth printing. Ten is where a single
-- unlucky run stops being the whole of the answer: at ten, one drop reads as
-- ten percent and is somewhere between three and thirty, which is wide and is
-- at least the right order of magnitude. Below it the number would be noise
-- wearing a percent sign.
local FLOOR = 10

-- How many creatures the ledger keeps. It only ever writes a creature Questie
-- has said carries a quest item, which is hundreds over a whole character
-- rather than the tens of thousands of things you loot, but a saved variable
-- with no ceiling is a saved variable that is one day megabytes. Past this the
-- least useful row goes, which is the one with the fewest corpses on it: a
-- creature seen twice is worth less than the one you have killed four hundred
-- of, and it is also the one you are least likely to be standing in front of.
local ROOM = 400

--------------------------------------------------------------------------
-- Reading Questie
--------------------------------------------------------------------------

-- The npc behind a unit token, as the number Questie's database is keyed by.
--
-- A GUID is `Creature-0-3007-0-11-1234-000136DF16` and the sixth field is the
-- npc id. The parse is ns.CreatureId in Core, beside the thirty other questions
-- the two clients answer differently, because the dungeon log reads the same
-- number off the same loot window and two copies of one format would drift.
-- What is left here is the name this file's callers already use.
function Drops.NpcId(guid)
	return ns.CreatureId(guid)
end

-- Questie keys its tooltip table by the creature id with an "m_" in front of
-- it, and this is asked on every hover and every plate pass. The key is built
-- once per creature and kept, because the id is the same number every time and
-- joining it to a prefix is a fresh string every time.
local keys = {}

-- Every objective Questie has registered against that creature, or nil.
--
-- The table is Questie's own and is handed back rather than copied, so nothing
-- downstream may write to it. Everything below only reads.
local function Registered(npcId)
	if not npcId then
		return nil
	end
	local tips = ns.Questie("QuestieTooltips")
	if not tips or type(tips.lookupByKey) ~= "table" then
		return nil
	end
	local key = keys[npcId]
	if not key then
		key = "m_" .. npcId
		keys[npcId] = key
	end
	return tips.lookupByKey[key]
end

-- One quest's name, as Questie's database has it. The client cannot be asked:
-- its own log is indexed by position and the whole point of holding an id is
-- not to have to walk it.
local function QuestName(questId)
	if type(questId) ~= "number" then
		return nil
	end
	local db = ns.Questie("QuestieDB", "QueryQuestSingle")
	if not db then
		return nil
	end
	local ok, name = pcall(db.QueryQuestSingle, questId, "name")
	if not ok or type(name) ~= "string" or name == "" then
		return nil
	end
	return name
end

-- Whether a quest is still one of yours. Questie leaves a key registered after
-- a hand-in until something walks it, so a creature you finished the quest on
-- would otherwise still be answering for it a zone later.
local function Carrying(questId)
	local player = ns.Questie("QuestiePlayer")
	if not player or type(player.currentQuestlog) ~= "table" then
		return false
	end
	return player.currentQuestlog[questId] ~= nil
end

-- Every kind of objective a creature can be registered against, and what each
-- one means to somebody standing in front of it.
--
-- Questie keys `m_<npc id>` off the spawn list of the objective rather than off
-- its type, so all five arrive here together and the type is only ever a label
-- on what you are being told. A table rather than a comparison because the
-- comparison is what shipped: `Type == "item"` read one of the five, and the
-- four it dropped included the one every quest in the game has.
local WANTED = {
	monster = true, -- something you have to kill, and the commonest of the five
	item    = true, -- something it is carrying
	object  = true, -- a thing on the ground it stands over
	event   = true, -- a creature that ticks the objective by being reached
	spell   = true, -- something you have to cast on it
}

-- The objective behind one of Questie's registry entries, and the quest it
-- belongs to, where it is one this hover should say anything about.
--
-- Four things disqualify one, and each is a line that would otherwise be wrong
-- rather than merely uninteresting:
--
--   no objective   the entry is a quest this creature *starts*, which Questie
--                  files under the same key with a name instead. Questie draws
--                  its own mark for those and the client draws one too.
--   a kind we do   a type absent from WANTED, so that the day Questie adds a
--   not know       sixth the symptom is a missing line rather than a raise.
--   finished       an objective already at its count, which over a mob is a
--                  line telling you to stop doing what you are doing.
--   handed in      a quest no longer in your log. Questie leaves the key
--                  registered until something walks it, so the log has to be
--                  asked as well as the registry.
local function Live(entry)
	local objective = type(entry) == "table" and entry.objective or nil
	if type(objective) ~= "table" or not WANTED[objective.Type] then
		return nil
	end
	if objective.Completed or not Carrying(entry.questId) then
		return nil
	end
	return objective, entry.questId
end

-- What the objective is asking for, in Questie's own words.
--
-- FullDescription first and Description under it, which is the order Questie's
-- own tooltip reads them in: a kill objective's Description is the creature's
-- name and its FullDescription is the sentence the quest gave you, and over a
-- mob whose name is already at the top of the box the sentence is the half
-- worth printing.
local function Wording(objective)
	local said = objective.FullDescription or objective.Description
	if type(said) ~= "string" or said == "" then
		return "the objective"
	end
	return (said:gsub("%.$", ""))
end

--------------------------------------------------------------------------
-- The ledger
--
-- One row per creature: how many of its corpses you have opened, and how many
-- of those had each quest item on them. Account-wide, because a boar drops what
-- a boar drops whichever of your characters is standing over it, and kept out
-- of the reset for the reason the purse is: it is a record of what happened
-- rather than a number anybody chose.
--------------------------------------------------------------------------

local function Row(npcId, make)
	local ledger = ns.db.questDrops
	if type(ledger) ~= "table" then
		return nil
	end
	local row = ledger[npcId]
	if not row and make then
		row = { n = 0 }
		ledger[npcId] = row
	end
	return row
end

-- The thinnest row, dropped, once there are more of them than ROOM.
--
-- Only on the loot that added a creature the ledger had never seen, because
-- that is the only loot that can push the count over. Every other loot is a row
-- that already existed getting one more corpse on it, and walking four hundred
-- entries to find that out would be a table scan on every kill.
--
-- The thinnest row is the one with the fewest corpses behind it, which is both
-- the least useful number in the table and the one you are least likely to be
-- standing in front of.
local function Prune()
	local ledger = ns.db.questDrops
	local held, thinnest, fewest = 0, nil, nil
	for npcId, row in pairs(ledger) do
		held = held + 1
		if not fewest or (row.n or 0) < fewest then
			thinnest, fewest = npcId, row.n or 0
		end
	end
	if held > ROOM and thinnest then
		ledger[thinnest] = nil
	end
end

-- Whether that creature is one the ledger has any use for: does an item
-- objective of a quest you are on hang off it.
--
-- The registry alone used to be the test, and it stopped being enough the
-- moment WANTED above grew past `item`. Every creature in a kill objective is
-- registered under the same key, there are far more of those than there are
-- things that drop something, and a row against each would be four hundred
-- entries of `n` counting corpses nobody will ever ask a fraction about --
-- which is also four hundred entries pushing the creatures that do drop
-- something out of ROOM.
local function Carries(npcId)
	local registered = Registered(npcId)
	if not registered then
		return false
	end
	for _, entry in pairs(registered) do
		local objective = Live(entry)
		if objective and objective.Type == "item" and objective.Id then
			return true
		end
	end
	return false
end

-- One corpse of one creature, and what was on it.
--
-- `items` is a set of item ids rather than a list, because a corpse carrying
-- two stacks of the same thing is still one corpse that had it and counting it
-- twice would put the fraction over one.
function Drops.Record(npcId, items)
	if type(npcId) ~= "number" or not Carries(npcId) then
		return false
	end
	local fresh = Row(npcId) == nil
	local row = Row(npcId, true)
	if not row then
		return false
	end
	row.n = (row.n or 0) + 1
	for itemId in pairs(items or {}) do
		row[itemId] = (row[itemId] or 0) + 1
	end
	if fresh then
		Prune()
	end
	return true
end

-- How often that creature had that item, as a fraction and the count it came
-- from. Nil below FLOOR corpses, which is the whole of the honesty in this
-- file: a number nobody should act on is worse than no number.
function Drops.Chance(npcId, itemId)
	local row = Row(npcId)
	if not row or (row.n or 0) < FLOOR then
		return nil
	end
	return (row[itemId] or 0) / row.n, row.n
end

--------------------------------------------------------------------------
-- Watching the loot window
--
-- LOOT_OPENED rather than CHAT_MSG_LOOT, and the difference is the whole
-- reason: the chat message says what you took and the loot window says what was
-- there. A corpse you walked away from because your bags were full still had
-- the hide on it, and a fraction built out of what you managed to pick up would
-- read low on exactly the creatures whose drops you care about.
--
-- GetLootSourceInfo is what ties a slot to the corpse it came out of, and it is
-- probed rather than trusted. Without it there is no honest way to tell a
-- two-corpse loot window apart, and the ledger records nothing at all rather
-- than filing both corpses under whichever one the client listed first.
--
-- It answers guid, quantity, guid, quantity for a slot that several corpses
-- contributed to, and only the first pair is read. That is the whole of the
-- inaccuracy in this file and it is worth naming: a stack of hides pooled out
-- of two boars is counted against one of them. It happens on the slot rather
-- than on the corpse, so both boars are still counted as corpses opened, and
-- the fraction it moves is one kill's worth.
--------------------------------------------------------------------------

local function SourcesOf(slot)
	local read = _G.GetLootSourceInfo
	if type(read) ~= "function" then
		return nil
	end
	local ok, guid = pcall(read, slot)
	if not ok or type(guid) ~= "string" then
		return nil
	end
	return guid
end

-- Every corpse in the window, each with the set of items that were on it.
local function Corpses()
	local size = _G.GetNumLootItems
	local count = (type(size) == "function" and size()) or 0
	local corpses = nil
	for slot = 1, count do
		local guid = SourcesOf(slot)
		local npcId = Drops.NpcId(guid)
		if npcId then
			corpses = corpses or {}
			corpses[npcId] = corpses[npcId] or {}
			local itemId = ns.ItemKind(ns.LootSlotLink(slot))
			if itemId then
				corpses[npcId][itemId] = true
			end
		end
	end
	return corpses
end

function Drops.OnLoot()
	local corpses = Corpses()
	if not corpses then
		return false
	end
	local recorded = 0
	for npcId, items in pairs(corpses) do
		if Drops.Record(npcId, items) then
			recorded = recorded + 1
		end
	end
	return recorded > 0
end

local events = CreateFrame("Frame")
events:RegisterEvent("LOOT_OPENED")
events:SetScript("OnEvent", function()
	Drops.OnLoot()
end)

--------------------------------------------------------------------------
-- What a drop is worth saying
--------------------------------------------------------------------------

-- What Questie's own drop table says that item drops at on that creature, as a
-- percentage, or nil where it has no row for the pair.
--
-- **This is new since v6 and it is why the note at the head of the file
-- changed.** v6 carried item rows with a name, a list of npcs and a list of
-- quests and no percentage anywhere, which is what made the ledger below the
-- only answer this addon could give. v11 ships Database/DropTables: a manual
-- correction layer over a private-server table over a Wowhead table, keyed item
-- then npc, and QuestieDB.GetItemDroprate walks the three in that order. It
-- answers a pair, the number and which of the three it came from, and the
-- number is already a percentage rather than a fraction.
--
-- Probed for by name rather than assumed, the way every other call into Questie
-- in this tree is: a v6 install answers a QuestieDB with no such function on it
-- and the box falls back to the ledger, which is exactly the behaviour it had
-- before this existed.
local function Listed(npcId, itemId)
	if type(npcId) ~= "number" or type(itemId) ~= "number" then
		return nil
	end
	local db = ns.Questie("QuestieDB", "GetItemDroprate")
	if not db then
		return nil
	end
	local ok, found = pcall(db.GetItemDroprate, itemId, npcId)
	if not ok or type(found) ~= "table" or type(found[1]) ~= "number" then
		return nil
	end
	return found[1]
end

-- A percentage with as many figures as it is worth reading and no more.
--
-- Questie's own rule, and it is the right one: a third of the time is `33%` and
-- a decimal on it would be arithmetic nobody asked for, while a drop somewhere
-- under one in a hundred is the difference between a long evening and the wrong
-- plan, and rounding that to `0%` says the item does not drop at all.
local function Percent(rate)
	if rate >= 10 then
		return ("%d%%"):format(math.floor(rate + 0.5))
	end
	if rate >= 1 then
		return ("%.1f%%"):format(rate)
	end
	return ("%.2f%%"):format(rate)
end

-- The drop lines for one objective: what the database says, what your own kills
-- say, or both.
--
-- Both, where both have an answer, and the second line is labelled as yours
-- rather than merged into the first. A scraped rate and four hundred of your
-- own corpses are two different claims about the same creature and the
-- interesting case is the one where they disagree; averaging them would throw
-- away the only thing the pair can tell you that neither can alone.
--
-- Only the database line where the ledger is under FLOOR, and only the ledger
-- line where the database has no row, which is every creature on a v6 install
-- and a good few on v11.
local function Rates(into, npcId, itemId)
	local listed = Listed(npcId, itemId)
	local rate, corpses = Drops.Chance(npcId, itemId)
	if listed then
		into[#into + 1] = { "dropped by", Percent(listed) }
	elseif rate then
		into[#into + 1] = { "dropped by",
			("%d%% of %d looted"):format(math.floor(rate * 100 + 0.5), corpses) }
	end
	if listed and rate then
		into[#into + 1] = { "your kills",
			("%d%% of %d"):format(math.floor(rate * 100 + 0.5), corpses) }
	end
	return into
end

--------------------------------------------------------------------------
-- What the hover says
--------------------------------------------------------------------------

-- The lines for one quest, given the objectives of that quest this creature
-- feeds. One name line, then one line per objective, then the drop rates under
-- the ones that are about an item.
--
-- The name line carries what kind of quest it is at its right edge, which is
-- the same half-line the map's marker hover draws and is drawn here in the same
-- two colours. It is the one fact on this box that is not about the creature
-- under the cursor: three of these hides is a fact about the boar, and "Elite"
-- is a fact about the four things you have not found yet. A player who has read
-- it on the map should not have to wonder whether the box out in the world is
-- quiet because the quest is ordinary or because this box never says.
local function Quest(into, npcId, questId, objectives)
	local name = QuestName(questId)
	if not name then
		return into
	end
	local tag = ns.QuestWhere.Tag(questId)
	into[#into + 1] = tag and { name, tag, color = C.heading, tone = C.quiet }
		or { name, color = C.heading }

	for _, objective in ipairs(objectives) do
		local held = tonumber(objective.Collected) or 0
		local want = tonumber(objective.Needed) or 0
		if want > 0 then
			into[#into + 1] = { Wording(objective), ("%d/%d"):format(held, want) }
		else
			into[#into + 1] = { Wording(objective) }
		end
		-- Only an item has a drop rate. A creature you have to kill eight of
		-- drops itself every time, and a line saying so would be furniture.
		if objective.Type == "item" then
			Rates(into, npcId, objective.Id)
		end
	end
	return into
end

-- Everything this creature is wanted for, grouped by the quest that wants it.
--
-- Grouped rather than listed flat because two objectives of one quest on one
-- creature is ordinary, and repeating the quest's name over each of them is how
-- a four line box becomes an eight line one saying the same thing twice.
function Drops.Lines(unit)
	local npcId = Drops.NpcId(UnitGUID and UnitGUID(unit))
	local registered = Registered(npcId)
	if not registered then
		return nil
	end

	local order, byQuest = {}, {}
	for _, entry in pairs(registered) do
		local objective, questId = Live(entry)
		if objective then
			if not byQuest[questId] then
				byQuest[questId] = {}
				order[#order + 1] = questId
			end
			local at = byQuest[questId]
			at[#at + 1] = objective
		end
	end

	if #order < 1 then
		return nil
	end

	-- Sorted, because pairs over Questie's table hands them back in whatever
	-- order its hashing happened to land on and a tooltip whose lines swap
	-- places between two hovers of the same mob is a tooltip you cannot read.
	table.sort(order)

	local lines = {}
	for _, questId in ipairs(order) do
		local objectives = byQuest[questId]
		table.sort(objectives, function(a, b)
			return (a.Index or 0) < (b.Index or 0)
		end)
		Quest(lines, npcId, questId, objectives)
	end
	return lines
end

ns.Tip.Source({
	name = "quest drops",
	kind = "unit",
	band = "extra",
	order = 40,
	fill = function(subject)
		return Drops.Lines(subject.unit)
	end,
})

--------------------------------------------------------------------------
-- What a nameplate says
--
-- The hover has room for the quest's name, the objective's own sentence and two
-- drop rates. A bar over a mob's head has room for four characters, and the
-- four worth having are the count: `3/8` is both why you are pulling this one
-- and whether you still have to. Where the client has no count for the
-- objective -- an event, a thing you cast on it -- the mark on its own is the
-- whole answer, and the mark is what UnitFrames/EnemyBars.lua draws in quest
-- gold beside the bar.
--
-- **Cached, and the cache is the reason this is a separate function rather than
-- Lines with a shorter formatter.** It is asked once per plate five times a
-- second, and the walk behind it is over another addon's hash table with a
-- currentQuestlog lookup per entry. One table index per plate per tick is what
-- the answer costs once the walk has happened, and the walk happens once per
-- creature per change to your log.
--
-- Thrown away whole on QUEST_LOG_UPDATE, which is the one event that covers
-- every way the answer can move: accepting, abandoning, handing in, and killing
-- the seventh of eight. It fires often enough that a creature answered before
-- Questie had compiled its database is re-asked a moment later, which is the
-- other half of what the wipe is for.
--------------------------------------------------------------------------

-- False rather than nil for a creature no quest wants, so that "asked and the
-- answer was no" is a hit and not a miss. A creature with nothing on it is the
-- overwhelming majority of what a plate is put up for.
local badges = {}

-- Whether the second of two objectives is the one the plate should carry.
--
-- The most left to do wins, because that is the one still deciding whether you
-- pull. Ties go to the lower quest id and then the lower objective index, which
-- is arbitrary and is the point: pairs over Questie's table answers in whatever
-- order its hashing landed on, and a plate whose number swapped between two
-- ticks of the same mob would read as the count going backwards.
local function Beats(left, questId, index, bestLeft, bestQuest, bestIndex)
	if bestLeft == nil or left ~= bestLeft then
		return bestLeft == nil or left > bestLeft
	end
	if questId ~= bestQuest then
		return questId < bestQuest
	end
	return index < bestIndex
end

-- The mark a plate carries when the objective has no count to show.
local MARK = "!"

local function Build(npcId)
	local registered = Registered(npcId)
	if not registered then
		return nil
	end
	local bestLeft, bestQuest, bestIndex, said = nil, nil, nil, nil
	for _, entry in pairs(registered) do
		local objective, questId = Live(entry)
		local held = objective and (tonumber(objective.Collected) or 0) or 0
		local want = objective and (tonumber(objective.Needed) or 0) or 0
		local index = objective and (tonumber(objective.Index) or 0) or 0
		if objective and Beats(want - held, questId, index, bestLeft, bestQuest, bestIndex) then
			bestLeft, bestQuest, bestIndex = want - held, questId, index
			said = want > 0 and ("%d/%d"):format(held, want) or MARK
		end
	end
	return said
end

-- What that creature's plate should say, or nil.
function Drops.Badge(npcId)
	if type(npcId) ~= "number" then
		return nil
	end
	local held = badges[npcId]
	if held == nil then
		held = Build(npcId) or false
		badges[npcId] = held
	end
	return held or nil
end

-- Everything the plates were told, forgotten. Its own function because the
-- harness drives it directly: a section that had to fire a client event to
-- clear a cache would be testing the event frame rather than the cache.
function Drops.Forget()
	badges = {}
end

local log = CreateFrame("Frame")
log:RegisterEvent("QUEST_LOG_UPDATE")
log:SetScript("OnEvent", function()
	Drops.Forget()
end)

-- What the player would see, rather than what this file meant to do. Four
-- answers and each is a different thing being absent, because "no lines on a
-- mob" reads as broken and the reasons for it are not the same problem.
--
-- The drop table gets an answer of its own because it is the half most likely
-- to be missing on a working install: Questie answering everything else while
-- GetItemDroprate is not there at all is exactly what a v6 install looks like,
-- and the symptom is a percentage that never appears on any creature.
function Drops.Describe()
	local where = ns.QuestWhere
	if not where or not where.Ready() then
		return "nothing, because only Questie knows what a creature is wanted for and it is not answering"
	end
	local ledger = ns.db.questDrops
	local held = 0
	for _ in pairs(type(ledger) == "table" and ledger or {}) do
		held = held + 1
	end
	local rates = ns.Questie("QuestieDB", "GetItemDroprate") ~= nil
	return ("which quest and how many, %s, and %s"):format(
		rates and "with Questie's drop rate under an item"
			or "with no drop rate from Questie, which is a version of it that ships no drop table",
		held == 0 and ("your own once you have looted %d of something"):format(FLOOR)
			or ("your own on %d creature%s you have looted"):format(held, held == 1 and "" or "s"))
end
