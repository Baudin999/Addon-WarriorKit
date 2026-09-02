local ADDON, ns = ...

-- What in your bags is finished with.
--
-- Three questions, one list. A quest item whose quests are all behind you, a
-- grey that is not worth the slot it is sitting in, and a piece of gear you
-- outgrew twenty levels ago are the three things that fill a bag, and none of
-- them is answered by the client's own interface: it will tell you an item is a
-- quest item and not which quest, it will tell you a price and never compare it
-- to the slot, and it will tell you a level requirement and never mention that
-- you passed it.
--
-- The quest half needs a database. The client carries no map from an item to
-- its quest, which is why no addon does that part without one; Questie carries
-- one and is loaded on both of these clients. The other two halves need nothing
-- but the client, so a session with no Questie in it still answers: the quest
-- items are left out and the list says why.
--
-- Nothing here destroys anything. It produces a list with a reason against
-- every line, and Destroy.lua is the only file that acts on it.

local Clutter = {}
ns.Clutter = Clutter

local BAGS = 4

-- GetItemInfoInstant's sixth value. Baganator files its Quest category on the
-- same number on this client, which is what proves it.
local QUEST_CLASS = 12

-- The two classes you wear, which are the only two the level rule looks at. A
-- container is not one of them and neither is a reagent, so neither can be
-- offered up for being old.
local WORN = { [2] = true, [4] = true }

-- Grey. The one quality the money rule reads, because a grey is the only thing
-- in the game whose entire reason to exist is the coins a vendor pays for it:
-- everything else is worth something you cannot put a price on.
local JUNK_QUALITY = 0

-- Green, and the rule reads everything at or below it. A blue you outgrew is
-- still worth carrying to a bank or an auction house, and this window is not
-- the place that decision gets made for you.
local PLAIN_QUALITY = 2

-- The two things you wear that have no level on them and never will. A guild
-- tabard is a white class four item that anybody can put on, which is exactly
-- the shape the level rule catches, and offering to destroy somebody's tabard
-- is the one way this list loses trust in a single card.
local KEPT = { INVTYPE_TABARD = true, INVTYPE_BODY = true }

-- The weapons that are not weapons, by the client's own subclass number.
--
-- A mining pick is a level four white one hander and a skinning knife is a
-- level four white one hander, and against the level rule they read exactly
-- like the quest green you picked up at four and should have thrown away at
-- twenty. They are not that. They are the tool your profession does not work
-- without, they never get replaced, and the rule offered both of them.
--
-- 14 is Miscellaneous and 20 is Fishing Poles, read off Wowhead's own item data
-- for this client rather than typed from memory: Mining Pick (2901), Skinning
-- Knife (7005) and Blacksmith Hammer (5956) are all class 2 subclass 14, and
-- Fishing Pole (6256) is class 2 subclass 20. The other tools need no entry
-- because they are not weapons at all: an enchanting rod and an engineering
-- spanner are both Trade Goods, which the level rule never looks at.
local WEAPON_CLASS = 2
local TOOLS = { [14] = true, [20] = true }

-- Five verdicts, and everything else is left alone.
--
--   "worthless" a vendor will not take it and it does nothing
--   "spent"     every quest this item belongs to is behind you
--   "cheap"     the whole stack is worth less than you said a slot is worth
--   "outgrown"  you can wear it, it is plain, it is under the floor, and you
--               passed its level long ago
--   "open"      a quest it belongs to is still out there to be picked up
--
-- Anything the database has never heard of, anything tied to a quest in your
-- log, anything that starts a quest you have not done, and anything the client
-- will not price or grade gets no verdict at all and never reaches the window.
local SPENT, OPEN = "spent", "open"
local WORTHLESS, CHEAP, OUTGROWN = "worthless", "cheap", "outgrown"

-- Which of them you are asked first, and which of them the window calls
-- certain. Certain is not "safe": it is "there is no second reading of this".
-- A vendor refusing an item is a fact, a completed quest is a fact, and a price
-- under a floor you set yourself is arithmetic on your own number. A level
-- gap and a quest still out there are both judgements, and the button says so.
local RANK = {
	[WORTHLESS] = 1, [SPENT] = 2, [CHEAP] = 3, [OUTGROWN] = 4, [OPEN] = 5,
}

local CERTAIN = { [WORTHLESS] = true, [SPENT] = true, [CHEAP] = true }

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
-- The two rules the client can answer on its own
--
-- Both read a number off the settings page rather than one written down here,
-- because both are a judgement about the character you are on. A grey worth
-- eleven copper is clutter at seventy and is a meal at twelve, and how far
-- behind you a piece of gear has to be before you will never wear it again is
-- the same kind of question. What is fixed is which items the rules are allowed
-- to look at at all, and that is above: grey for money, and plain gear you can
-- wear that is not a tool for the level.
--
-- **The floor is one floor and both rules read it.** Nothing is ever offered
-- that a vendor would pay more than the floor for. That is not a tidiness: the
-- level rule without it offered a green worth twenty two silver out of a bag
-- that was keeping a grey worth six, which is the window destroying the more
-- valuable of two things it looked at in the same pass.
--------------------------------------------------------------------------

-- What a bag slot has to be worth to keep, in copper. Nought switches the money
-- rule off and leaves the vendor's own refusal behind it, which still catches a
-- Broken Twig.
local function Floor()
	return math.max(0, (ns.db.clutterWorth or 0)) * 100
end

-- How far behind you an item has to be rated. Read the same way and for the
-- same reason.
local function Gap()
	return math.max(1, ns.db.clutterLevel or 10)
end

-- A grey, against the vendor and then against your floor.
--
-- The number handed in is the whole stack rather than one of them, because a
-- slot is what you are short of and a slot holds the stack. Twenty Tattered
-- Cloth worth eight copper each is a slot worth one silver sixty, and that is
-- the number you set the floor against.
local function Worth(worth)
	if worth <= 0 then
		return WORTHLESS, "A vendor will not take it, and it does nothing else."
	end
	if worth < Floor() then
		return CHEAP, ("The whole stack is worth %s at a vendor."):format(ns.Coin(worth))
	end
	return nil
end

-- Plain gear you passed a long time ago, and worth less than the slot it is in.
--
-- **The floor is read here too, and that is the whole of the second rule.** The
-- level rule on its own offered a green worth twenty two silver while a grey
-- worth six sat in the next square untouched, which is the window contradicting
-- itself inside one bagful: it destroyed the more valuable of the two and kept
-- the other. There is one floor and everything the window offers is under it,
-- whichever rule found it. Gear over the floor is not clutter, it is a thing to
-- sell, and a bag window that has just told you a vendor will pay for it is the
-- wrong place to be offering a delete.
--
-- The level itself is the higher of the two numbers the client carries. An
-- item's own level and the level it asks of you are different numbers and
-- either can be the honest one: a green rated forty that anybody may wear reads
-- as level nought off the requirement alone, and a piece with a requirement and
-- no rating reads as nought the other way. Taking the higher keeps the newer of
-- the two readings, which is the cautious direction: it makes an item look more
-- current than either number alone, so the gap has to be real before anything
-- is offered.
local function Outgrown(link, quality, classId, subClassId, worth)
	if not WORN[classId] or quality > PLAIN_QUALITY then
		return nil
	end
	if classId == WEAPON_CLASS and TOOLS[subClassId] then
		return nil
	end
	if worth >= Floor() then
		return nil
	end
	local needs, rating = ns.ItemNeeds(link), ns.ItemLevel(link)
	if needs == nil or rating == nil then
		return nil
	end
	local _, _, equip = ns.ItemInfo(link)
	if KEPT[equip] then
		return nil
	end
	local rated = math.max(needs, rating)
	local yours = UnitLevel("player") or 0
	if yours - rated < Gap() then
		return nil
	end
	return OUTGROWN, ("Rated for level %d, and you are %d."):format(rated, yours)
end

--------------------------------------------------------------------------
-- The scan
--------------------------------------------------------------------------

-- One slot's verdict, or nothing. The quest class is the database's question
-- and every other class is the client's, so an item is only ever put to one of
-- the three rules and a session with no Questie in it still gets the other two.
local function Consider(db, link, count)
	local itemId, classId, subClassId = ns.ItemKind(link)
	if not itemId then
		return nil, nil, 0
	end
	-- Nil is an item the client has not cached, which is not a grade of nought
	-- and not a price of nought. Every rule below would read it as clutter, so
	-- none of them is asked: the window is opened again a moment later and by
	-- then the client has answered.
	local quality, price = ns.ItemValue(link)
	if quality == nil then
		return nil, nil, 0
	end
	-- The whole stack rather than one of them, because a slot is what you are
	-- short of and a slot holds the stack. Worked out once, here, because both
	-- the money rule and the level rule now read it and the order the cards come
	-- in is built on it.
	local worth = (price or 0) * (count or 1)
	if classId == QUEST_CLASS then
		if not db then
			return nil, nil, worth
		end
		local verdict, reason = Judge(db, itemId)
		return verdict, reason, worth
	end
	if quality == JUNK_QUALITY then
		local verdict, reason = Worth(worth)
		return verdict, reason, worth
	end
	local verdict, reason = Outgrown(link, quality, classId, subClassId, worth)
	return verdict, reason, worth
end

-- One slot, onto the end of the list if it has a verdict.
local function Offer(found, db, bag, slot)
	local link = ns.ContainerItemLink(bag, slot)
	if not link then
		return false
	end
	local count = ns.ContainerItem(bag, slot) or 1
	local verdict, reason, worth = Consider(db, link, count)
	if not verdict then
		return false
	end
	local name, icon, _, color = ns.ItemInfo(link)
	found[#found + 1] = {
		bag = bag, slot = slot, link = link, id = ns.ItemKind(link),
		name = name or link, icon = icon, color = color,
		verdict = verdict, reason = reason,
		-- What saying yes to this card costs, which is what the order below is
		-- built on and is nought for everything the quest rules offered.
		worth = worth,
	}
	return true
end

-- Certain first, so the window is not asking a hard question on its first card,
-- and the least valuable first inside each kind. That second half is the whole
-- reason the list is ordered rather than walked in bag order: you press clear
-- because you are full, and the first card should be the one that costs least
-- to say yes to.
local function Before(a, b)
	local left, right = RANK[a.verdict] or 9, RANK[b.verdict] or 9
	if left ~= right then
		return left < right
	end
	if a.worth ~= b.worth then
		return a.worth < b.worth
	end
	return (a.name or "") < (b.name or "")
end

-- Why the quest half of the list is missing, or nothing.
--
-- It is no longer a reason to answer nothing at all. The money and the level
-- rules need neither Questie nor the quest log, so a client that cannot
-- enumerate one and a session that never loaded the other both still get a
-- list; what they get told is that the quest items in it were left out.
local function Missing(db)
	if not db then
		return "questie"
	end
	if not RefreshLog() then
		return "questlog"
	end
	return nil
end

-- Returns the list, and a word saying what is missing from it. Nothing is
-- cached: the bags move, the quest log moves, and this runs when a window opens
-- rather than on a ticker.
function Clutter.Scan()
	local found = {}
	local db = Database()
	local problem = Missing(db)
	if problem then
		db = nil
	end

	for bag = 0, BAGS do
		for slot = 1, ns.ContainerSlots(bag) do
			Offer(found, db, bag, slot)
		end
	end

	table.sort(found, Before)
	return found, problem
end

function Clutter.Certain(entry)
	return entry ~= nil and CERTAIN[entry.verdict] == true
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
	return ("reading Questie, and clearing a grey under %s or gear %d levels behind you")
		:format(ns.Coin(Floor()), Gap())
end
