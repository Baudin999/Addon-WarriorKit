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
--   how many      what the client's own counter says, as collected of needed
--   how often     what fraction of the corpses you have looted had it on them
--
-- **The first two are Questie's and the client's, and the third is ours.**
--
-- Questie is the only thing on either client that knows a creature drops a
-- quest item at all. There is no API for it: the client will tell you what a
-- quest wants and never what carries it. Questie carries a database row per
-- creature and registers, per objective, the key `m_<npc id>` against every
-- spawn that would tick it. That table is what this file reads, and reads only:
-- nothing here calls Update on one of Questie's objectives or writes a field on
-- it. A part that mutates another addon's state is a part that breaks when the
-- other addon changes and cannot be blamed for it.
--
-- **The drop chance is measured, not looked up.** No database on either client
-- carries one. Questie's item rows have a name, a list of npcs and a list of
-- quests, and no percentage anywhere. What this addon can do instead is count,
-- because it is standing there while you do it: every corpse of that creature
-- you open the loot window on is one sample, and every one that had the item on
-- it is a hit. That is a drop chance in the only sense that matters to somebody
-- killing boars, and it is honest in a way a scraped number is not, because it
-- is your kills, on your server, this week.
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

-- Every objective Questie has registered against that creature, or nil.
--
-- The table is Questie's own and is handed back rather than copied, so nothing
-- downstream may write to it. Everything below only reads.
local function Registered(npcId)
	local where = ns.QuestWhere
	if not npcId or not where or type(where.Module) ~= "function" then
		return nil
	end
	local tips = where.Module("QuestieTooltips")
	if not tips or type(tips.lookupByKey) ~= "table" then
		return nil
	end
	return tips.lookupByKey["m_" .. npcId]
end

-- One quest's name, as Questie's database has it. The client cannot be asked:
-- its own log is indexed by position and the whole point of holding an id is
-- not to have to walk it.
local function QuestName(questId)
	local where = ns.QuestWhere
	if type(questId) ~= "number" or not where or type(where.Module) ~= "function" then
		return nil
	end
	local db = where.Module("QuestieDB")
	if not db or type(db.QueryQuestSingle) ~= "function" then
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
	local where = ns.QuestWhere
	if not where or type(where.Module) ~= "function" then
		return false
	end
	local player = where.Module("QuestiePlayer")
	if not player or type(player.currentQuestlog) ~= "table" then
		return false
	end
	return player.currentQuestlog[questId] ~= nil
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

-- One corpse of one creature, and what was on it.
--
-- `items` is a set of item ids rather than a list, because a corpse carrying
-- two stacks of the same thing is still one corpse that had it and counting it
-- twice would put the fraction over one.
function Drops.Record(npcId, items)
	if type(npcId) ~= "number" or not Registered(npcId) then
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
			local read = _G.GetLootSlotLink
			local link = type(read) == "function" and read(slot) or nil
			local itemId = link and ns.ItemKind(link)
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
-- What the hover says
--------------------------------------------------------------------------

-- The lines for one quest, given the objectives of that quest this creature
-- feeds. One name line, then one line per item objective, then the fraction
-- where there is one worth printing.
local function Quest(into, npcId, questId, objectives)
	local name = QuestName(questId)
	if not name then
		return into
	end
	into[#into + 1] = { name, color = C.heading }

	for _, objective in ipairs(objectives) do
		local held = tonumber(objective.Collected) or 0
		local want = tonumber(objective.Needed) or 0
		local what = objective.Description
		if type(what) ~= "string" or what == "" then
			what = "the item"
		end
		if want > 0 then
			into[#into + 1] = { what, ("%d/%d"):format(held, want) }
		else
			into[#into + 1] = { what }
		end

		local rate, corpses = Drops.Chance(npcId, objective.Id)
		if rate then
			into[#into + 1] = { "dropped by",
				("%d%% of %d looted"):format(math.floor(rate * 100 + 0.5), corpses) }
		end
	end
	return into
end

-- Every quest item this creature carries, grouped by the quest that wants it.
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
		local objective = entry.objective
		local questId = entry.questId
		if type(objective) == "table" and objective.Type == "item"
			and objective.Id and not objective.Completed and Carrying(questId) then
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

-- What the player would see, for the panel. Three answers and each is a
-- different thing being absent, because "no lines on a mob" reads as broken and
-- the three reasons for it are not the same problem.
function Drops.Describe()
	local where = ns.QuestWhere
	if not where or not where.Ready() then
		return "nothing, because only Questie knows what a creature drops and it is not answering"
	end
	local ledger = ns.db.questDrops
	local held = 0
	for _ in pairs(type(ledger) == "table" and ledger or {}) do
		held = held + 1
	end
	if held == 0 then
		return "which quest and how many, and a drop chance once you have looted"
			.. (" %d of something"):format(FLOOR)
	end
	return ("which quest and how many, with %d creature%s counted for a drop chance")
		:format(held, held == 1 and "" or "s")
end
