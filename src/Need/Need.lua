local ADDON, ns = ...

--------------------------------------------------------------------------
-- One question: why does this item matter to you
--
-- Asked of one item at a time and answered in a word, a colour, a short phrase
-- and a sentence, or not answered at all, which is what most items get. Four
-- sources, each of which already exists somewhere else in the addon and none of
-- which knows about the others.
--
-- **The phrase and the sentence are two answers and not one wrapped twice.**
-- The phrase goes in a column a row can spare, which on the loot feed is 48
-- units and never more than 81; the sentence goes on a line of a tooltip, which
-- has as much room as it asks for. A profession's name measures 104 units in
-- the shipped face at a row's text size and "Lederverarbeitung" measures 123, so
-- there is no width at which a row can draw one, and a row that drew part of one
-- would be drawing half a word. So skill answers a sentence and no phrase, and
-- the reason it is worth saying at all on the row is the colour.
--
--   quest    an objective in your log this item feeds, and how far along it
--            is. Quests/Client.lua does the reading.
--   skill    a reagent a profession of yours uses, and whether the recipes
--            using it can still gain you a point. Comfort/Reagents.lua holds
--            the list.
--   trash    something Comfort/Wanted.lua would have left on the corpse.
--   nothing  which is most items, and is answered out of a table.
--
-- **It is a tree of its own because three parts outside src/Feeds/ are going to
-- want it and a part may not name a file outside its own tree.** It was written
-- in Core for the first half of that sentence, on the model of
-- Core/QuestItems.lua, and Core is the one place it cannot go. Core is the base
-- every other tree names freely, and this file reads Quests/Client.lua,
-- Comfort/Reagents.lua and Comfort/Wanted.lua: put it in the base and every
-- window that wants a colour on a row depends on the quest log through the
-- floor. scripts/trees.lua refuses that outright and it is the one rule there
-- that carries no allow-list, because a base that reaches back into a feature
-- is not a base.
--
-- So it is src/Need/, loading after all three parts it reads, and a window that
-- asks carries one allow-listed edge saying so. The rest of what the Core
-- version claimed is still true: it wraps readings other parts own, owns no
-- setting and draws nothing. Nothing here knows what a loot row or a bag square
-- looks like, and every source is reached through ns rather than named as a
-- file, so a build missing one of those parts answers "no" for that source and
-- the rest still work.
--
-- **The order is fixed here and not left to the caller.** A wolf liver that is
-- also a leatherworking reagent is a wolf liver you need eight of, and two
-- callers ranking the same item differently is the thing this function exists
-- to stop.
--
-- **The answer is cached per item id, because a pull drives this.** AddItem in
-- Feeds/Loot.lua asks once per drop and a corpse in a pull is four of them, so
-- a walk of the quest log per item is the one thing this path cannot afford.
-- What is cached is the quest and the skill answer, which are facts about the
-- item; the whole cache is dropped on the events that change either, which are
-- the quest log's, SKILL_LINES_CHANGED and the trade window's.
--
-- The trash answer is not in it and could not be. It is a fact about a corpse
-- rather than about the item, so it is asked live and costs a handful of table
-- reads, which is what Comfort/Loot.lua already pays per slot. The memory it
-- falls back to for a caller with no slot ages out on its own, which is a thing
-- a cache emptied by events could not do: no event fires when a corpse you
-- walked away from stops being the corpse in front of you.
--------------------------------------------------------------------------

-- What the log is waiting for, by the name the client writes on the objective,
-- against the phrase a row would show. Nil until something asks, and nil again
-- the moment the log changes.
--
-- Built once and read many times rather than the other way round. One item
-- looked up against the whole log is a walk per drop; the whole log looked up
-- once is a walk per change to it, and the log changes far less often than a
-- corpse is emptied.
local objectives

-- The three cached answers, by item id. `false` in the first is an id both
-- sources have been asked about and neither claimed, which has to be told apart
-- from an id nobody has asked about yet or every miss walks the log again.
--
-- Three tables rather than one holding a triple, because a triple is a table per
-- item and this fills on a path a pull drives.
local reason, phrase, sentence = {}, {}, {}

-- Only an objective that counts items can be about an item. A kill count and a
-- thing found in the world are named after a mob and a chest, and neither is a
-- name a loot row will ever hand over.
local COUNTED = "item"

--------------------------------------------------------------------------
-- The sources
--------------------------------------------------------------------------

-- Every unfinished item objective in the log, by name. Names are lowered on the
-- way in and on the way out, because the client writes the objective and the
-- item link in two places and this addon has no promise that they agree on a
-- capital.
--
-- Matching by name is what Quests/Client.lua's reading gives and it is right
-- for the great majority and wrong for the handful whose objective is worded
-- differently from the item. Questie knows the real mapping and Quests/Drops.lua
-- already reads it; a Questie lookup on a path a pull drives is not worth
-- catching the one item in fifty.
--
-- An objective already at its total is not a reason. The question this file
-- answers is why you would keep the thing, and a line reading 8 of 8 wants no
-- more of it.
--
-- The first quest in the log to want a name wins, the way Core/QuestItems.lua
-- takes the lowest row for an item three quests want. Two quests wanting the
-- same item is two counts, and the log's own order is the only tiebreak in the
-- addon that a player can also see.
local function Lines(client, wanted, index)
	for _, line in ipairs(client.Objectives(index) or {}) do
		if line.kind == COUNTED then
			local name, have, need = client.Counted(line.text, line.kind)
			have = have or 0
			if name and need and have < need then
				name = name:lower()
				wanted[name] = wanted[name] or ("%d/%d"):format(have, need)
			end
		end
	end
end

local function Walk()
	local wanted = {}
	local client = ns.QuestClient
	if not client or not client.Ready() then
		return wanted
	end

	client.Open()
	local entries = client.Count()
	for index = 1, entries do
		local entry = client.Entry(index)
		if entry and not entry.header then
			Lines(client, wanted, index)
		end
	end
	return wanted
end

-- How far along the objective this item feeds is, or nil for an item no quest
-- of yours is counting.
local function Quest(link)
	if not objectives then
		objectives = Walk()
	end
	local name = ns.ItemInfo(link)
	if not name then
		return nil
	end
	return objectives[name:lower()]
end

-- The profession a reagent belongs to, and only where a recipe wanting it can
-- still gain that profession a point. Six stacks of linen is a reagent tailoring
-- uses and has not given you a point for in twelve levels, and a row that says
-- tailoring about it is a row telling you to keep something you should be
-- selling.
local function Skill(itemId)
	local reagents = ns.Reagents
	if not reagents then
		return nil
	end
	local profession, point = reagents.Skill(itemId)
	if profession and point then
		return profession
	end
	return nil
end

-- What trash says on a hover, which is the only place it says anything at all.
--
-- Worded as the filter's doing and not as a verdict on the item. The filter is
-- a rule you wrote, and the row a grey turns up on is where you find out you
-- wrote it too tight; "junk" would be the addon telling you what your own
-- settings already decided.
local LEFT = "your loot filter would have left it"

-- Whether the loot filter would have left this where it lay, asked two ways
-- because two callers hold two halves of the one fact.
--
-- With a slot there is a corpse in front of you and Comfort/Wanted.lua answers
-- live. Take answers true, false or nil, and nil is "the client cannot price it
-- yet": only a plain false is the filter refusing something.
--
-- Without one the answer is Comfort/Loot.lua's memory of the slot it refused a
-- moment ago. That is the loot feed's half and it is the only one it can have:
-- CHAT_MSG_LOOT is the server naming what reached your bags, the corpse behind
-- it is already gone, and asking Take harder would not put one back.
--
-- Neither half speaks while the filter is off. Take answers true on its first
-- line and nothing is written down, so a feed with the filter off marks nothing,
-- which is the whole column it would otherwise be marking.
local function Trash(link, slot)
	if type(slot) == "number" then
		local wanted = ns.Wanted
		return wanted ~= nil and wanted.Take(slot) == false
	end
	local loot = ns.Loot
	return loot ~= nil and loot.Refused(link) == true
end

--------------------------------------------------------------------------
-- The answer
--------------------------------------------------------------------------

-- Why this item matters: the word, the phrase a row has room for, the colour
-- that word is drawn in and the sentence a tooltip has room for, or nothing at
-- all.
--
-- The slot is optional and is the loot slot the item is sitting in. With one the
-- filter is asked about the corpse in front of you; without one the trash source
-- reads what Comfort/Loot.lua refused off the last corpse instead, which is the
-- loot feed's only way to the answer and is why it is a source a caller with a
-- link alone can still have.
--
-- Two of the three carry no phrase, and for the same reason from opposite ends.
-- Trash is the commonest answer and the one nobody is looking for, so a column
-- of grey rows each captioned "trash" is the feed back where it started. Skill
-- is a profession's own name in the player's own language, which is 104 units
-- of a column that is never wider than 81. Both are a colour on the row and a
-- line on the hover, and the hover is where skill names the profession and trash
-- names the filter.
--
-- Quest is the one reason with a number in it, which is the one thing a colour
-- cannot carry and a row has room for. Its two forms are the same fact spelled
-- for two widths: `4/8` is what fits a column, "4 of 8" is what reads on a line.
function ns.Need(link, slot)
	local itemId = ns.ItemKind(link)
	if not itemId then
		return nil
	end

	local found = reason[itemId]
	if found == nil then
		local counted = Quest(link)
		if counted then
			found, phrase[itemId] = "quest", counted
			-- Spelled out once and kept, rather than on every hover. The slash
			-- is what makes a count fit a column and the one thing a sentence
			-- has no use for.
			sentence[itemId] = (counted:gsub("/", " of "))
		else
			local profession = Skill(itemId)
			if profession then
				found, sentence[itemId] = "skill", profession
			else
				found = false
			end
		end
		reason[itemId] = found
	end

	if found then
		return found, phrase[itemId], ns.UI.Color[found], sentence[itemId]
	end
	if Trash(link, slot) then
		return "trash", nil, ns.UI.Color.trash, LEFT
	end
	return nil
end

-- Everything worked out again from scratch next time somebody asks.
--
-- Emptied rather than replaced, because these three tables are held as upvalues
-- and a fresh set per event is three tables of garbage every time the quest log
-- so much as ticks.
local function Forget()
	objectives = nil
	wipe(reason)
	wipe(phrase)
	wipe(sentence)
end

-- The three things that change an answer. The quest log's two are the count on
-- an objective and a quest arriving or leaving; SKILL_LINES_CHANGED is a point
-- gained, which is what turns a recipe grey; and the trade window's four are
-- the moments Comfort/Reagents.lua rewrites the reagent list under us.
local events = CreateFrame("Frame")
events:SetScript("OnEvent", Forget)
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("TRADE_SKILL_SHOW")
events:RegisterEvent("TRADE_SKILL_UPDATE")
events:RegisterEvent("CRAFT_SHOW")
events:RegisterEvent("CRAFT_UPDATE")
