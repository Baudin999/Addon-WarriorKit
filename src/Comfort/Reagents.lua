local ADDON, ns = ...

-- What your professions eat.
--
-- The loot filter can be told to keep what you craft with, and there is no call
-- that answers "is this one of mine". The client will say what a recipe wants
-- while its window is open and says nothing at all once it is shut, so the only
-- way to have the list when a corpse is in front of you is to have written it
-- down the last time a profession window was up.
--
-- So this part is a scribe and nothing else. Open blacksmithing and every
-- reagent every blacksmithing recipe you know wants goes on the list under the
-- word Blacksmithing. Open enchanting and the enchanting ones join it. Nothing
-- here reads the list back: Comfort/Wanted.lua asks Reagents.Has(itemId) when
-- it is deciding whether a slot on a corpse is yours.
--
-- Per character, in ns.dbc, because a profession is. Your warrior's mining has
-- nothing to say about the ore an alt does not smelt, and an account-wide list
-- would have one character's loot filter keeping the other one's reagents for
-- the rest of its life.
--
-- Keyed by item id and valued by the profession that named it, which is what
-- makes a rescan safe. A walk of the mining list replaces exactly the ids
-- mining put there and leaves blacksmithing's alone. A plain set of ids could
-- only ever be added to, and a profession you dropped would keep its reagents
-- on the filter until you cleared the whole list by hand.
--
-- It scans whether or not the filter is switched on, and that is the one place
-- this part does work for nothing. A list that only filled while the setting
-- was on would be empty at the moment somebody turns the setting on, and the
-- first thing they would see is a filter keeping no reagents at all until they
-- had been round every profession window again. The walk is a few hundred table
-- writes on a window you opened by hand, so there is nothing worth saving.
--
-- This part owns no frame anybody can see and draws nothing, so nothing here is
-- on a ticker.

local Reagents = {}
ns.Reagents = Reagents

-- One second, per profession.
--
-- TRADE_SKILL_UPDATE fires on every change the window makes to itself: the
-- search box, the have-materials tick, a category opening, a craft finishing.
-- A profession with four hundred recipes is four hundred reagent counts and a
-- link for each, and running that on every one of a burst is work nobody asked
-- for. Keyed by the profession's name rather than held as one number, because
-- closing mining and opening enchanting in the same second is two windows and
-- two answers, and a single throttle would swallow the second one.
local THROTTLE = 1

local frame
local walked = {}

--------------------------------------------------------------------------
-- Categories that are folded up
--
-- A trade skill window lists a category as a row of its own, and a category
-- somebody has folded up hides its recipes: they are not in the count and
-- there is no index to ask about them. So a walk of a half folded window sees
-- half the reagents.
--
-- The client will open every category with ExpandTradeSkillSubClass(0), and
-- this does not call it. Two reasons and the second is the one that decides it.
-- The window belongs to the player, they folded that category up on purpose,
-- and unfolding it under their hand while they are reading it is the addon
-- rearranging furniture nobody asked it to touch. And expanding fires
-- TRADE_SKILL_UPDATE, which is the event that got us here, so the part would be
-- answering its own event with a change to the window that fires it again.
--
-- What that costs is handled instead of being lived with. A walk that saw every
-- category opened out replaces this profession's ids, because it saw the whole
-- list and anything missing from it is a recipe you no longer know. A walk that
-- found a category folded up adds and never takes away, because a category you
-- folded is not a reagent you stopped using. So the list only ever loses an id
-- on the evidence of a window that could see all of them.
--------------------------------------------------------------------------

-- This character's list, made on first use. ns.dbc is not there until Core has
-- merged the saved variables, which is before PLAYER_LOGIN and therefore before
-- anything below can run, but the guard is here because a nil ns.dbc is a
-- silent nothing and an indexed nil is a Lua error in somebody's game.
local function List()
	if not ns.dbc then
		return nil
	end
	local list = ns.dbc.lootReagents
	if type(list) ~= "table" then
		list = {}
		ns.dbc.lootReagents = list
	end
	return list
end

-- Every reagent one recipe wants, onto the table this walk is filling. A link
-- the client will not hand over is skipped rather than guessed at: an id the
-- filter invented is an item it keeps for a reason nobody can read back.
local function Recipe(found, index, count, link)
	for which = 1, count(index) do
		local itemId = ns.ItemKind(link(index, which))
		if itemId then
			found[itemId] = true
		end
	end
end

-- One window, walked. The five calls are the only thing that differs between
-- the trade skill window and the craft window, so they arrive as arguments and
-- there is one walk rather than two that drift apart.
local function Walk(profession, count, row, reagents, reagent)
	local list = List()
	if not list or not profession then
		return
	end

	local found, whole = {}, true
	for index = 1, count() do
		local kind, expanded = row(index)
		if kind ~= "header" then
			Recipe(found, index, reagents, reagent)
		elseif not expanded then
			whole = false
		end
	end

	if whole then
		for itemId, owner in pairs(list) do
			if owner == profession then
				list[itemId] = nil
			end
		end
	end
	for itemId in pairs(found) do
		list[itemId] = profession
	end
end

-- Whether this window has been walked recently enough to leave alone.
local function Due(profession)
	local now = GetTime()
	if walked[profession] and now - walked[profession] < THROTTLE then
		return false
	end
	walked[profession] = now
	return true
end

-- The trade skill window, which is every profession but enchanting.
--
-- A linked window is somebody else's list, opened from a link they put in
-- chat. Reading it as yours is how a warrior who has never held a pick ends up
-- with the whole of a stranger's mining list on his loot filter, and the
-- profession name on the window is theirs too, so the entries could not even be
-- told apart afterwards.
local function Trade()
	if ns.TradeSkillLinked() then
		return
	end
	local profession = ns.TradeSkillName()
	if not profession or not Due(profession) then
		return
	end
	Walk(profession, ns.TradeSkillCount, ns.TradeSkillRow,
		ns.TradeSkillReagents, ns.TradeSkillReagent)
end

-- The craft window, which is enchanting here and beast training on Classic Era.
-- A beast training list has no reagents at all, so it walks to nothing and
-- writes nothing, which is the right answer and costs one pass.
local function Craft()
	local profession = ns.CraftName()
	if not profession or not Due(profession) then
		return
	end
	Walk(profession, ns.CraftCount, ns.CraftRow,
		ns.CraftReagents, ns.CraftReagent)
end

local function OnEvent(_, event)
	if event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
		Craft()
	else
		Trade()
	end
end

function Reagents.Has(itemId)
	local list = List()
	return (list and list[itemId]) ~= nil
end

function Reagents.Count()
	local list = List()
	if not list then
		return 0
	end
	local count = 0
	for _ in pairs(list) do
		count = count + 1
	end
	return count
end

-- Which professions have put something on the list, sorted, for the panel and
-- for the reading below. Sorted rather than in the order they were scanned,
-- because the order they were scanned in is the order you happened to open two
-- windows in and would have the panel say something different every session.
function Reagents.Professions()
	local names, seen = {}, {}
	local list = List()
	if list then
		for _, owner in pairs(list) do
			if not seen[owner] then
				seen[owner] = true
				names[#names + 1] = owner
			end
		end
	end
	table.sort(names)
	return names
end

-- Everything off the list, and how many went. The count is what the caller
-- prints: an empty list and a list that was already empty read the same on the
-- panel and are not the same answer to "did that do anything".
function Reagents.Clear()
	local list = List()
	if not list then
		return 0
	end
	local count = 0
	for itemId in pairs(list) do
		list[itemId] = nil
		count = count + 1
	end
	return count
end

-- The professions in one phrase. Two are joined with an and, more than two are
-- a list with the and on the last, which is how a person would say it.
local function Phrase(names)
	if #names <= 1 then
		return names[1] or ""
	end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

function Reagents.Describe()
	local count = Reagents.Count()
	if count == 0 then
		return "none scanned yet, open each profession once"
	end
	return ("%d reagent%s from %s"):format(count, count == 1 and "" or "s",
		Phrase(Reagents.Professions()))
end

-- Registered at login and never unregistered, which is the one part of this
-- file that is not the shape the rest of Comfort has. Every other chore here
-- leaves the event list when its setting goes off, because a chore that is
-- switched off must not be on the path it acts on. This one acts on nothing:
-- it writes a list down and the switch decides whether anything reads it, so
-- staying registered costs a walk of a window you opened yourself and buys a
-- list that is already there for whoever turns the setting on tomorrow.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	if frame then
		return
	end
	frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", OnEvent)
	frame:RegisterEvent("TRADE_SKILL_SHOW")
	frame:RegisterEvent("TRADE_SKILL_UPDATE")
	frame:RegisterEvent("CRAFT_SHOW")
	frame:RegisterEvent("CRAFT_UPDATE")
end)
