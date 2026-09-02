local ADDON, ns = ...

-- Which quest items in your bags are finished with.
--
-- The client will tell you an item is a quest item and will not tell you which
-- quest. There is no API for it, which is why no addon does this without a
-- quest database behind it. Questie carries one and is loaded on both of these
-- clients, so this file asks Questie and degrades to saying it cannot answer
-- when Questie is not there.
--
-- Nothing here destroys anything. It produces a list with a reason against
-- every line, and Destroy.lua is the only file that acts on it.

local Clutter = {}
ns.Clutter = Clutter

local BAGS = 4

-- GetItemInfoInstant's sixth value. Baganator files its Quest category on the
-- same number on this client, which is what proves it.
local QUEST_CLASS = 12

-- Two verdicts, and everything else is left alone.
--
--   "spent"  every quest this item belongs to is behind you
--   "open"   a quest it belongs to is still out there to be picked up
--
-- Anything the database has never heard of, anything tied to a quest in your
-- log, and anything that starts a quest you have not done gets no verdict at
-- all and never reaches the window.
local SPENT, OPEN = "spent", "open"

--------------------------------------------------------------------------
-- Questie
--------------------------------------------------------------------------

-- The two query functions are named because a module coming back proves nothing
-- on its own, and because this file cannot do its work without either of them:
-- an item id is turned into a quest id by the first and into a quest name by
-- the second. ns.Questie in Core is the probe, and it is asked again on every
-- scan rather than cached, for the same reason EditMode.CanApply is not cached:
-- the database is compiled after login and an answer taken too early would be
-- wrong for the rest of the session.
local function Database()
	return ns.Questie("QuestieDB", "QueryItemSingle", "QueryQuestSingle")
end

-- Every query is pcalled. The database is another addon's, it is compiled
-- rather than written out, and an item id it has no row for is a miss rather
-- than an error, but none of that is this addon's to guarantee.
local function Ask(db, itemId, field)
	local ok, value = pcall(db.QueryItemSingle, itemId, field)
	if not ok then
		return nil
	end
	return value
end

local function QuestName(db, questId)
	local ok, name = pcall(db.QueryQuestSingle, questId, "name")
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	return ("quest %d"):format(questId)
end

--------------------------------------------------------------------------
-- What you are on and what you have done
--------------------------------------------------------------------------

local inLog = {}

-- The quest log, as a set keyed by id. Header rows come back through the same
-- call with no quest id, which is what the number test below is for.
local function RefreshLog()
	wipe(inLog)
	if type(_G.GetNumQuestLogEntries) ~= "function"
		or type(_G.GetQuestLogTitle) ~= "function" then
		return false
	end

	local entries = _G.GetNumQuestLogEntries() or 0
	for index = 1, entries do
		local questId = select(8, _G.GetQuestLogTitle(index))
		if type(questId) == "number" and questId > 0 then
			inLog[questId] = true
		end
	end
	return true
end

-- True, false, or nil where the client will not say. Nil is not false and the
-- callers below have to keep them apart: "I do not know whether you finished
-- this" is a reason to leave an item alone, not a reason to offer it up.
--
-- Resolved the way Questie resolves it, the loose global first and the
-- C_QuestLog copy behind it.
local function Completed(questId)
	local check = _G.IsQuestFlaggedCompleted
		or (_G.C_QuestLog and _G.C_QuestLog.IsQuestFlaggedCompleted)
	if type(check) ~= "function" then
		return nil
	end

	local ok, done = pcall(check, questId)
	if not ok then
		return nil
	end
	return done and true or false
end

--------------------------------------------------------------------------
-- The verdict
--------------------------------------------------------------------------

-- The starter rule, and it is first because it is the one that earns its place.
-- An item that begins a quest looks exactly like an orphan sitting in your
-- bags, and destroying one is how a chain you never knew existed is lost. So an
-- item that starts anything you have not provably finished is kept, and that
-- includes the case where the client will not say whether you finished it.
local function StartsSomethingLive(db, itemId)
	local startQuest = Ask(db, itemId, "startQuest")
	if type(startQuest) ~= "number" or startQuest == 0 then
		return false, nil
	end
	if Completed(startQuest) == true then
		return false, startQuest
	end
	return true, startQuest
end

local function Judge(db, itemId)
	local live, startQuest = StartsSomethingLive(db, itemId)
	if live then
		return nil
	end

	local related = Ask(db, itemId, "relatedQuests")
	if type(related) ~= "table" then
		related = nil
	end

	-- On a quest right now. Nothing else matters and the item never appears.
	if related then
		for _, questId in pairs(related) do
			if inLog[questId] then
				return nil
			end
		end
	end

	local spent, pending = 0, 0
	local firstSpent, firstPending

	if related then
		for _, questId in pairs(related) do
			if Completed(questId) == true then
				spent = spent + 1
				firstSpent = firstSpent or questId
			else
				-- Not done, or the client will not say. Both land here, which is
				-- what keeps an unanswerable client on the cautious side.
				pending = pending + 1
				firstPending = firstPending or questId
			end
		end
	end

	if pending > 0 then
		local name = QuestName(db, firstPending)
		if pending == 1 then
			return OPEN, ("%s wants it and you have not taken that quest."):format(name)
		end
		return OPEN, ("%s wants it, and so do %d other quests you have not taken.")
			:format(name, pending - 1)
	end

	if spent > 0 then
		local name = QuestName(db, firstSpent)
		if spent == 1 then
			return SPENT, ("Left over from %s, which you have completed."):format(name)
		end
		return SPENT, ("Left over from %s and %d other quests you have completed.")
			:format(name, spent - 1)
	end

	-- No related quests at all. The only thing left that can make this clutter
	-- is a starter for a quest already behind you.
	if startQuest then
		return SPENT, ("Starts %s, which you have already completed."):format(QuestName(db, startQuest))
	end
	return nil
end

--------------------------------------------------------------------------
-- The scan
--------------------------------------------------------------------------

-- Spent before open, so the certain ones come first and the window is not
-- asking a hard question on its first card.
local function Rank(entry)
	return entry.verdict == SPENT and 1 or 2
end

-- Returns the list, and a word saying why it is empty when the reason is not
-- "your bags are clean". Nothing is cached: the bags move, the quest log moves,
-- and this runs when a window opens rather than on a ticker.
function Clutter.Scan()
	local found = {}

	local db = Database()
	if not db then
		return found, "questie"
	end
	if not RefreshLog() then
		return found, "questlog"
	end

	for bag = 0, BAGS do
		for slot = 1, ns.ContainerSlots(bag) do
			local link = ns.ContainerItemLink(bag, slot)
			if link then
				local itemId, classId = ns.ItemKind(link)
				if itemId and classId == QUEST_CLASS then
					local verdict, reason = Judge(db, itemId)
					if verdict then
						local name, icon, _, color = ns.ItemInfo(link)
						found[#found + 1] = {
							bag = bag, slot = slot, link = link, id = itemId,
							name = name or link, icon = icon, color = color,
							verdict = verdict, reason = reason,
						}
					end
				end
			end
		end
	end

	table.sort(found, function(a, b)
		if Rank(a) ~= Rank(b) then
			return Rank(a) < Rank(b)
		end
		return (a.name or "") < (b.name or "")
	end)

	return found
end

function Clutter.Certain(entry)
	return entry ~= nil and entry.verdict == SPENT
end

-- Whether the database is answering at all, which is the one thing the panel
-- can say without walking the bags on every refresh.
function Clutter.Ready()
	return Database() ~= nil
end

function Clutter.Describe()
	if not Clutter.Ready() then
		return "Questie is not answering, so no quest item can be traced to its quest"
	end
	return "reading Questie's quest database"
end
