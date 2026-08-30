local ADDON, ns = ...

local Log = {}
ns.QuestLog = Log

--------------------------------------------------------------------------
-- Your quest log, as a shape rather than as a list of rows
--
-- The client hands the log over as a flat run of rows where a header is a row
-- like any other and the quests under it are the rows that follow until the
-- next header. That shape is why the client's own log is a scrolling strip of
-- six lines: it has nothing to draw except the run.
--
-- This file turns it into zones, each holding its quests, which is the shape
-- the window's left column draws and the shape a player already has in their
-- head. Nothing else here is clever. The whole of the work is the two things
-- Quests/Client.lua explains: every header has to be open before the rows mean
-- anything, and the cursor has to go back where it was found.
--
-- **The selection is a quest id, never an index.** An index is a position in a
-- list that moves whenever you accept or hand in anything, so a window holding
-- one is a window that changes which quest it is showing while you read it.
-- The id survives all of that. Where the client will not give an id, which is
-- the older builds, the title is the fallback key and the failure that leaves
-- is two quests of the same name in two zones, which is a smaller wrong answer
-- than the index gives on every turn-in.
--
-- **What is cached and what is not.** The zones are, because the left column
-- rebuilds from them on every event and walking sixty rows to redraw one tick
-- box is the kind of waste this addon has a gate for. One quest's text and
-- rewards are not: they are read when you click a quest and thrown away, both
-- because they are two borrows of a shared cursor and because a cache of them
-- would need invalidating on the events that are exactly the reason the window
-- redraws.
--------------------------------------------------------------------------

local Client = ns.QuestClient
local Party = ns.QuestParty

-- What the last Read found. A list of zones in the client's own order, each
-- with a list of quests in the client's own order.
local zones = {}

-- Every quest by its key, so the window can ask about the one it is showing
-- without walking the zones.
local byKey = {}

-- How many quests are in the log at all, and how many of those can be handed
-- in. Both are read off the last Read rather than counted again.
local total, done = 0, 0

--------------------------------------------------------------------------

-- What a quest is called in this addon's own tables.
--
-- A number where the client gave one, and the title where it did not. Kept as a
-- string either way, because it is a UI.List row id and a list keyed on a
-- number in one build and a string in another is a list that silently stops
-- matching its own selection.
function Log.Key(quest)
	if not quest then
		return nil
	end
	if type(quest.id) == "number" and quest.id > 0 then
		return ("q%d"):format(quest.id)
	end
	return ("t%s"):format(quest.title or "")
end

-- The heading a quest with no header above it goes under.
--
-- The client does not produce one on either of these builds, so this is the
-- honest name for a row that arrived without a zone rather than a case anybody
-- has seen. It is here because the alternative is a quest that exists in the
-- log and is drawn nowhere at all.
local UNSORTED = "Elsewhere"

--------------------------------------------------------------------------

-- The two facts about a quest that are not on its own row.
--
-- Whether it can be handed to the party comes off the shared cursor, so all of
-- them are asked in one sweep rather than one borrow each: the left column
-- draws a share mark on the rows that can take one, and that is a question per
-- quest on every rebuild.
--
-- Who else in the group is on it comes off Quests/Party.lua, which asks the
-- client and Questie and merges what both say. Both are read here rather than
-- in Detail, because both belong to the row in the left column and Detail is
-- only ever asked about the one quest you are reading.
local function Company(quests)
	local indices = {}
	for at = 1, #quests do
		indices[at] = quests[at].index
	end

	local pushable = Client.Pushables(indices)
	for at = 1, #quests do
		local quest = quests[at]
		quest.shareable = pushable[quest.index] and true or false
		quest.party = Party.On(quest.id, quest.index)
	end
	return quests
end

-- Read the whole log.
--
-- Every header is opened first, because a collapsed one hides its quests from
-- the client's own row count and this addon draws the fold itself.
function Log.Read()
	Client.Open()

	zones = {}
	byKey = {}
	total, done = 0, 0

	local entries = Client.Count()
	local zone = nil
	local carried = {}

	for index = 1, entries do
		local entry = Client.Entry(index)
		if entry and entry.header then
			zone = { name = entry.title, index = index, quests = {}, done = 0 }
			zones[#zones + 1] = zone
		elseif entry then
			if not zone then
				zone = { name = UNSORTED, index = index, quests = {}, done = 0 }
				zones[#zones + 1] = zone
			end
			entry.key = Log.Key(entry)
			entry.zone = zone.name
			entry.watched = Client.Watched(index)
			zone.quests[#zone.quests + 1] = entry
			byKey[entry.key] = entry
			carried[#carried + 1] = entry
			total = total + 1
			if entry.complete then
				done = done + 1
				zone.done = zone.done + 1
			end
		end
	end

	Company(carried)
	return zones
end

-- The zones from the last Read, without taking another one. Every caller that
-- draws wants this; Read is what the events call.
function Log.Zones()
	return zones
end

function Log.Quest(key)
	return key and byKey[key] or nil
end

-- How many quests, and how many of those are ready to hand in.
function Log.Tally()
	return total, done
end

-- A zone with nothing in it is not drawn, which only happens on a log the
-- client has half handed over. Counted rather than asserted, because the window
-- would rather draw the eleven zones it did get.
function Log.Count()
	local drawn = 0
	for _, zone in ipairs(zones) do
		if #zone.quests > 0 then
			drawn = drawn + 1
		end
	end
	return drawn
end

--------------------------------------------------------------------------
-- One quest, in full
--------------------------------------------------------------------------

-- Everything the middle and right columns draw, read on the click rather than
-- kept. Three borrows of the shared cursor, which is three more than a redraw
-- of the left column costs and is why this is not part of Read.
function Log.Detail(key)
	local quest = Log.Quest(key)
	if not quest then
		return nil
	end

	-- The index is looked up again rather than trusted, because the log may have
	-- moved since the Read that produced this quest and an index into the wrong
	-- row would draw another quest's text under this quest's name.
	local index = Client.IndexOf(quest.id) or quest.index
	local text = Client.Text(index) or { description = "", summary = "" }

	return {
		quest = quest,
		index = index,
		description = text.description,
		summary = text.summary,
		objectives = Client.Objectives(index) or {},
		rewards = Client.Rewards(index) or {},
		seconds = Client.TimeLeft(index),
		-- Read with the rest of the log rather than asked again here. It is a
		-- fact about the row in the left column before it is a fact about the
		-- quest you have open, and asking twice is a second borrow of the
		-- shared cursor for an answer this addon already has.
		shareable = quest.shareable,
	}
end

-- Which quest to show when the window opens or when the one it was showing has
-- gone. The first one ready to hand in, because that is the one you opened the
-- log to find, and the first quest in the log otherwise.
function Log.First()
	for _, zone in ipairs(zones) do
		for _, quest in ipairs(zone.quests) do
			if quest.complete then
				return quest.key
			end
		end
	end
	for _, zone in ipairs(zones) do
		if zone.quests[1] then
			return zone.quests[1].key
		end
	end
	return nil
end

--------------------------------------------------------------------------
-- What you can do to one
--------------------------------------------------------------------------

-- Every one of these takes the key rather than the index and looks the index up
-- itself, for the reason Detail does: an index this addon is holding is an
-- index that may have moved, and every call below acts on your character.
local function Index(key)
	local quest = Log.Quest(key)
	if not quest then
		return nil
	end
	return Client.IndexOf(quest.id) or quest.index
end

function Log.Watch(key, on)
	local index = Index(key)
	if not index then
		return false
	end
	local quest = Log.Quest(key)
	quest.watched = on and true or false
	return Client.Watch(index, on)
end

function Log.Share(key)
	local index = Index(key)
	return index ~= nil and Client.Share(index)
end

-- The name the client says it would abandon, which is what the confirmation
-- puts in front of you. Nil means the client would not arm, and the window
-- refuses to offer a button that would do nothing.
function Log.Abandoning(key)
	local index = Index(key)
	if not index then
		return nil
	end
	return Client.Arm(index)
end

function Log.Abandon(key)
	local index = Index(key)
	return index ~= nil and Client.Abandon(index)
end

--------------------------------------------------------------------------

function Log.Describe()
	if not Client.Ready() then
		return Client.Describe()
	end
	if total == 0 then
		return "no quests"
	end
	return ("%d quests in %d zones, %d ready to hand in"):format(total, Log.Count(), done)
end
