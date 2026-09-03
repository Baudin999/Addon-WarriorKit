local ADDON, ns = ...

-- What is worth picking up.
--
-- Fast loot empties a corpse, which is the right thing to do on the four
-- corpses of a pull and the wrong thing on the twelfth corpse of an old
-- dungeon you are running for one drop. The bags fill with teeth and vendor
-- mail, and clearing them out again is the tax the fast loot was supposed to
-- save you.
--
-- So this file is one question asked once per slot: do you want this. It has
-- four kinds of answer and any one of them takes the slot.
--
--   The colour. A quality floor, because "greens and up" is the sentence
--   people say out loud when they describe how they run an old instance. Five
--   is the floor switched off, and off has to be reachable: a run you are
--   doing for the ore is a run where a green is clutter too.
--
--   The kind. Cloth, ore, herbs, leather, enchanting, gems and meat, one tick
--   box each, read off the class and subclass the client already files the
--   item under. Nothing here is a name or a search string, for the reason
--   Core/Piles.lua gives: the client has already sorted every item in the game
--   and every bag addon in the world throws the answer away.
--
--   The price. A grey or white the vendor pays at least your floor for, the
--   floor written as gold, silver and copper on the settings page and read
--   against the whole slot. This is the rule that keeps a white sword worth
--   two gold out of the bin on a run where the colour floor is green, and
--   nought is the rule switched off.
--
--   What your professions use, which is Comfort/Reagents.lua's answer rather
--   than this file's. It is asked for by name at the moment the question comes
--   up, so a build where that part is missing is a build where nothing is
--   crafted and every other rule still works.
--
-- Two things are never refused. Money, because there is no corpse whose coins
-- you did not want, and a quest item, because the client flags that slot
-- itself and a quest item left behind is a walk back.
--
-- Every setting here is this character's. Which professions you have and what
-- your bags are for is a fact about the character standing over the corpse,
-- and the alternative is a bank alt looting mageweave.
--
-- This part owns no frame and draws nothing. Comfort/Loot.lua is the only
-- caller of the question and it calls once per slot on LOOT_READY. The bag
-- window's filter button is the only other file that reaches in, and it
-- reaches the switch at the foot of this file rather than the question.

local Wanted = {}
ns.Wanted = Wanted

-- The kind rules, by the two numbers the client files an item under.
--
-- Trade Goods is class 7 and its subclasses are the six professions worth
-- picking up for: cloth 5, leather 6, metal and stone 7, meat 8, herb 9 and
-- enchanting 12. The numbers are the client's own, read off Questie's TBC item
-- database rather than typed from memory, and they are the same numbers
-- Core/Piles.lua cuts the trade pile into sub-piles with.
local KINDS = {
	[7] = {
		[5] = "lootCloth",
		[6] = "lootLeather",
		[7] = "lootOre",
		[8] = "lootMeat",
		[9] = "lootHerbs",
		[12] = "lootEnchanting",
	},
}

-- Gems are the one rule that is a whole class rather than a subclass. Class 3
-- is every gem in the game, cut or raw, and there is no subclass of it a
-- prospector would want and another they would not.
local GEMS = 3

-- The floor switched off. Nothing in the game is quality 5 to a looter, so a
-- floor there is the colour rule taking nothing and leaving the decision to
-- the kind rules and to your professions.
local NO_COLOUR = 5

-- White. The price rule reads a grey and a white and nothing above, because
-- above white the colour floor is the rule that speaks and a green under it
-- was refused by name: a run with the floor at blue is a run where a green
-- is clutter whatever a vendor pays for it.
local PLAIN = 1

-- Which setting decides an item of this class and subclass, or nil for an item
-- no kind rule has anything to say about.
local function KindOf(classId, subClassId)
	if classId == GEMS then
		return "lootGems"
	end
	local row = KINDS[classId]
	return row and row[subClassId] or nil
end

-- Whether fast loot should take this slot.
--
-- The order is cheapest first and it is also the order of certainty: the
-- switch, then the two slots that are never refused, then the colour, then the
-- kind, and last the profession scan, which is the only one of them that reads
-- another part.
function Wanted.Take(slot)
	if not ns.dbc.lootFilter then
		return true
	end

	local kind, link = ns.LootKind(slot)
	if kind ~= "item" then
		return true
	end

	-- The third return is how many are in the slot, the fifth is the quality
	-- and the seventh is the quest flag the client sets on the slot itself,
	-- which is a fact about your log rather than about the item: the same grey
	-- tooth is a quest item on one character and litter on the next. The
	-- sixth, between them, is whether the slot is locked, and nothing here has
	-- anything to say about that.
	local _, _, quantity, _, quality, _, isQuestItem = GetLootSlotInfo(slot)
	if isQuestItem then
		return true
	end

	local floor = ns.dbc.lootFloor
	if floor < NO_COLOUR and quality and quality >= floor then
		return true
	end

	local itemId, classId, subClassId = ns.ItemKind(link)
	if not itemId then
		-- The client would say nothing about this one. Nothing can be decided
		-- about an item with no class, and of the two ways to be wrong here,
		-- leaving something behind is the one you cannot undo from a bag.
		return true
	end

	local key = KindOf(classId, subClassId)
	if key and ns.dbc[key] then
		return true
	end

	-- The whole slot against the floor, for the reason Comfort/Clutter.lua
	-- reads a whole stack: a slot is what you are short of and a slot holds
	-- the stack, so five whites at five silver each are a slot worth twenty
	-- five.
	--
	-- An item the client has not cached yet is taken, the same answer the
	-- class check above gives and for a sharper reason: with the leftovers on,
	-- refused means destroyed, and a white sword worth two gold that the
	-- client had not priced by the time the corpse opened is the one thing
	-- this rule exists to keep.
	local worth = ns.dbc.lootWorth or 0
	if worth > 0 and quality and quality <= PLAIN then
		local graded, price = ns.ItemValue(link)
		if graded == nil then
			return true
		end
		if (price or 0) * (quantity or 1) >= worth then
			return true
		end
	end

	-- Resolved here rather than at load, because Comfort/Reagents.lua is a
	-- separate part and a missing one answers "no profession asked for this"
	-- rather than a Lua error over a corpse.
	if ns.dbc.lootCrafted then
		local reagents = ns.Reagents
		if reagents and reagents.Has(itemId) then
			return true
		end
	end

	return false
end

-- What each floor is called, in the words somebody would use for it out loud.
local COLOURS = {
	[0] = "greys and up",
	[1] = "whites and up",
	[2] = "greens and up",
	[3] = "blues and up",
	[4] = "epics only",

	-- The floor switched off, in the words the reading falls back to. It is in
	-- the table rather than only in Describe because the settings page offers
	-- all six as one cycle, and a sixth phrase written on the page would be a
	-- second wording of this one that is free to drift away from it.
	[NO_COLOUR] = "nothing by colour",
}

-- The same six as an array in floor order, so the page can hand the cycle a
-- list. Built once at load rather than per call, because a list built when a
-- window opens is a table built for a window.
local FLOOR_WORDS = {}
for floor = 0, NO_COLOUR do
	FLOOR_WORDS[floor + 1] = COLOURS[floor]
end

-- The six words the colour rule can be set to, lowest floor first.
function Wanted.Floors()
	return FLOOR_WORDS
end

-- Which floor one of those words stands for, and nil for anything else. The
-- cycle hands back the word it is showing rather than a number, so this is the
-- other half of the same table and the page carries no copy of either.
function Wanted.Floor(word)
	for floor = 0, NO_COLOUR do
		if COLOURS[floor] == word then
			return floor
		end
	end
	return nil
end

-- The kind rules in the order they are read out, which is the order the
-- settings page draws them in and has nothing to do with the numbers above.
local WORDS = {
	{ key = "lootCloth", word = "cloth" },
	{ key = "lootOre", word = "ore" },
	{ key = "lootHerbs", word = "herbs" },
	{ key = "lootLeather", word = "leather" },
	{ key = "lootEnchanting", word = "enchanting" },
	{ key = "lootGems", word = "gems" },
	{ key = "lootMeat", word = "meat" },
}

-- The kind rules for the settings page, which draws one tick box per entry in
-- this order. Handed back rather than copied into Comfort/Feature.lua so that
-- the boxes and the sentence under them are one list and read in one order.
function Wanted.Kinds()
	return WORDS
end

-- A plain list. Two things are a comma between them and three or more take an
-- and before the last, which is how the same sentence is written by hand.
local function Listed(parts)
	if #parts < 3 then
		return table.concat(parts, ", ")
	end
	return table.concat(parts, ", ", 1, #parts - 1) .. ", and " .. parts[#parts]
end

-- One phrase for the status line and for the panel's reading, saying what is
-- coming home with you. Money and quest items are left out of it: they are not
-- a rule anybody turned on and a list that named them would be a list where
-- the things you chose are outnumbered by the things you did not.
function Wanted.Describe()
	if not ns.dbc.lootFilter then
		return "off"
	end

	local parts = { COLOURS[ns.dbc.lootFloor] or "nothing by colour" }
	for index = 1, #WORDS do
		local entry = WORDS[index]
		if ns.dbc[entry.key] then
			parts[#parts + 1] = entry.word
		end
	end
	if (ns.dbc.lootWorth or 0) > 0 then
		parts[#parts + 1] = ("a grey or white worth %s"):format(ns.Coin(ns.dbc.lootWorth))
	end
	if ns.dbc.lootCrafted then
		parts[#parts + 1] = "what my professions use"
	end

	return Listed(parts)
end

--------------------------------------------------------------------------
-- The switch
--
-- The filter and the leftovers as one thing, which is what the button on the
-- bag window presses. On its own the filter leaves what it refused on the
-- corpse, and a corpse with a grey on it is a corpse nobody can skin, so the
-- mode a person means when they say "the filter" for a run of an old dungeon
-- is both switches at once. The settings page still has them apart, for the
-- person who wants the refusals left where they lie.
--
-- Comfort/Leftovers.lua holds events rather than answering a question, so it
-- is told, the same as Comfort/Feature.lua tells it from the page.
--------------------------------------------------------------------------

function Wanted.Running()
	return ns.dbc.lootFilter and true or false
end

function Wanted.Switch(on)
	on = on and true or false
	ns.dbc.lootFilter = on
	ns.dbc.lootDestroy = on
	ns.Leftovers.Apply()
	return on
end

function Wanted.Toggle()
	return Wanted.Switch(not Wanted.Running())
end
