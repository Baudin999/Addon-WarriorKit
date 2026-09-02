local ADDON, ns = ...

local QuestItems = {}
ns.QuestItems = QuestItems

--------------------------------------------------------------------------
-- Which line of your log a quest item belongs to
--
-- One question, asked of one item at a time: is anything you are on still
-- waiting for this, and if so, how far down the log is it. The bag window
-- draws the quest pile in two lanes off the answer, the way it draws the
-- equipment piles in two off the binding. What a quest of yours wants is on
-- the left, in the order the log lists the quests, and what nothing in the
-- log wants is on the right, where it is one click from gone.
--
-- **The client cannot answer it and never could.** A quest item's tooltip
-- says "Quest Item" and stops. The map from an item to the quest that wants
-- it is a database, and Questie carries the only one loaded on either of
-- these clients, so this file reads Questie's item rows the way
-- Comfort/Clutter.lua reads them and answers nothing else. The two files ask
-- the same two fields and read them the same way on purpose: the item the
-- clutter window calls spent is the item this file puts in the right lane,
-- and one rule drawn two ways would have the window disagreeing with itself.
--
-- **Where it sits in the log is the client's number.** GetQuestLogIndexByID
-- is the row a quest occupies right now, headers counted, which is the order
-- the log draws it in. It is asked per related quest rather than the log being
-- walked once, because a walk with GetQuestLogTitle skips every quest under a
-- collapsed header and this call does not have to. The lowest row wins for an
-- item three quests want, so the item sits beside the first of them.
--
-- **Nil is "cannot say", and cannot say is the left lane.** No Questie, an
-- item the database has no row for, a client without the index call: every
-- one of them comes back as kept. The right lane is a suggestion to throw
-- something away, and a suggestion made on a guess is the one thing this file
-- must never produce. The right lane is for an item Questie knows and can tie
-- to no quest you are on, which is the same item the clutter window offers.
--
-- **It is in Core because two parts read Questie's item rows.** Clutter is
-- Comfort's and the bag window is Bags', and a part may not name a file
-- outside its own tree. This is the shape Core/Piles.lua has: it wraps another
-- addon's database and a client call, owns no setting and draws nothing.
--------------------------------------------------------------------------

-- After every row of the log. An item that starts a quest you have not done
-- is nothing the log lists yet, and it is still yours to keep: destroying one
-- is how a chain you never knew existed is lost. So it sorts under the last
-- quest you are on rather than among the leftovers.
local STARTER = math.huge

-- The one query function this file needs, probed on every call rather than
-- cached, for the reason Comfort/Clutter.lua gives: the database is compiled
-- after login and an answer taken too early would stand for the session.
local function Database()
	return ns.Questie("QuestieDB", "QueryItemSingle")
end

-- Every query is pcalled. The database is another addon's and an item id it
-- has no row for is a miss rather than an error, but none of that is this
-- addon's to guarantee.
local function Ask(db, itemId, field)
	local ok, value = pcall(db.QueryItemSingle, itemId, field)
	if not ok then
		return nil
	end
	return value
end

-- True, false, or nil where the client will not say. Resolved the way Questie
-- resolves it, the loose global first and the C_QuestLog copy behind it.
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

-- The row a quest occupies in the log, or nil when you are not on it.
local function Row(lookup, questId)
	local ok, at = pcall(lookup, questId)
	if ok and type(at) == "number" and at > 0 then
		return at
	end
	return nil
end

-- The lowest row any quest wanting this item sits on, or nil when none of
-- them is in the log.
local function First(db, lookup, itemId)
	local related = Ask(db, itemId, "relatedQuests")
	if type(related) ~= "table" then
		return nil
	end
	local first
	for _, questId in pairs(related) do
		local at = Row(lookup, questId)
		if at and (not first or at < first) then
			first = at
		end
	end
	return first
end

-- Whether this item begins a quest you have not provably finished. A client
-- that will not say whether you finished it lands on the kept side.
local function Starts(db, itemId)
	local startQuest = Ask(db, itemId, "startQuest")
	if type(startQuest) ~= "number" or startQuest == 0 then
		return false
	end
	return Completed(startQuest) ~= true
end

-- Where a quest item goes: its rank in the left lane and whether it is in
-- that lane at all.
--
-- The rank is the log row for an item a quest of yours wants, STARTER for one
-- that begins a quest you have not done, and nil otherwise. The second answer
-- is the lane: true is yours, false is nothing in your log wants it. Nil rank
-- with true is "cannot say", and every reader has to keep that apart from a
-- row: it sorts after the ranked items and it is still drawn as kept.
function QuestItems.Place(link)
	local db = Database()
	local lookup = _G.GetQuestLogIndexByID
	if not db or type(lookup) ~= "function" then
		return nil, true
	end
	local itemId = ns.ItemKind(link)
	-- No row is not "no quest wants it". It is a database that cannot say,
	-- and Comfort/Clutter.lua leaves the same item alone for the same reason.
	if not itemId or Ask(db, itemId, "name") == nil then
		return nil, true
	end
	local first = First(db, lookup, itemId)
	if first then
		return first, true
	end
	if Starts(db, itemId) then
		return STARTER, true
	end
	return nil, false
end

-- Whether the database is answering at all, which is what the panel can say
-- without walking a bag.
function QuestItems.Ready()
	return Database() ~= nil
end
