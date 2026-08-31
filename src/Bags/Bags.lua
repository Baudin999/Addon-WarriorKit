local ADDON, ns = ...

local Bags = {}
ns.Bags = Bags

--------------------------------------------------------------------------
-- What you are carrying, in piles
--
-- The scan and the grouping, and no frame anywhere in the file. Grid.lua draws
-- what this answers and Window.lua decides when to ask.
--
-- **A pile is the class the client already files an item under.** Not a search
-- string, not a rule anybody typed. `ns.ItemKind` reads GetItemInfoInstant,
-- which comes out of the client's own item database and cannot miss the way a
-- cache lookup can, so the pile an item lands in is decided by the client and
-- is right on the first frame after a login. That is the whole reason the
-- grouping is fifteen lines rather than a feature: the client has already done
-- it and every bag addon in the world throws the answer away.
--
-- Two piles are not a class and both are worth the exception. Junk is quality
-- zero whatever class it is, because the thing every grey has in common is
-- that a vendor is where it goes. Empty is the absence of an item, and it is a
-- pile rather than a gap so the free count has something you can point at.
--
-- **Quality can be nil and the pile still has to be right.** GetItemInfo, which
-- is the only call that grades an item, answers nothing for an item the client
-- has not cached. That is rare for something sitting in your own bags and it is
-- not impossible, and the honest reading of nil is "do not know" rather than
-- zero. So an ungraded item stays in its class pile instead of being called
-- junk, and moves the moment GET_ITEM_INFO_RECEIVED arrives. The window listens
-- for that event for this reason and no other.
--
-- **The bank is not here.** Five bags, the backpack and the four on the belt,
-- which is what you are carrying. A bank window is a second window reading a
-- second set of bag numbers, and it can be written the day somebody wants it
-- without changing a line of this file.
--------------------------------------------------------------------------

-- The backpack and the four on the belt. The bank's bags are numbered past
-- these and the keyring below them, and neither is what this window is about.
local FIRST_BAG, LAST_BAG = 0, 4

-- The one item that gets a pile of its own.
--
-- It is not a class and it does not need to be: it is the most clicked item in
-- the game, it is a Miscellaneous item, and Miscellaneous is where everything
-- goes that the client could not think of a word for. A hearthstone sitting
-- eleventh in that pile is a hearthstone you hunt for every time.
local HEARTHSTONE = 6948

-- Every pile, in the order they are drawn, and the class each one takes.
--
-- The order is the order Baganator ships on this client, because it is right
-- and because it was arrived at by people using it: what you press is at the
-- top, what you wear is under that, what you carry for a reason is under that,
-- and what you are about to be rid of is at the bottom. A pile with nothing in
-- it is not drawn at all, so the list being long costs an empty bag nothing.
--
-- `name` is the fallback, in English. What is actually drawn is the client's
-- own word for the class where it will say one, resolved once at the first
-- scan, so a German client reads Handwerkswaren rather than Trade Goods.
local ORDER = {
	{ key = "hearthstone", name = "Hearthstone" },
	{ key = "consumable",  name = "Consumable",   classId = 0 },
	{ key = "weapon",      name = "Weapon",       classId = 2 },
	{ key = "armor",       name = "Armor",        classId = 4 },
	{ key = "container",   name = "Container",    classId = 1 },
	{ key = "quiver",      name = "Quiver",       classId = 11 },
	{ key = "projectile",  name = "Projectile",   classId = 6 },
	{ key = "trade",       name = "Trade Goods",  classId = 7 },
	{ key = "reagent",     name = "Reagent",      classId = 5 },
	{ key = "recipe",      name = "Recipe",       classId = 9 },
	{ key = "quest",       name = "Quest",        classId = 12 },
	{ key = "key",         name = "Key",          classId = 13 },
	{ key = "misc",        name = "Miscellaneous", classId = 15 },
	{ key = "other",       name = "Other" },
	{ key = "junk",        name = "Junk" },
	{ key = "empty",       name = "Empty" },
}

Bags.EMPTY, Bags.JUNK, Bags.OTHER = "empty", "junk", "other"

-- Class number to pile, built off the list above so the two cannot drift.
local BY_CLASS = {}
local buckets = {}
for index = 1, #ORDER do
	local group = ORDER[index]
	buckets[group.key] = {}
	if group.classId then
		BY_CLASS[group.classId] = group.key
	end
end

-- One table, refilled on every scan rather than rebuilt.
--
-- A bag update arrives five times for one loot and the window answers each of
-- them, so a scan that allocated a table per slot would be a hundred and fifty
-- objects for a stack of cloth. The entries are a pool keyed by how far into
-- the walk they are, which is stable because the walk is: bag zero slot one is
-- entry one whatever is in it.
local state = { groups = {}, entries = {}, shown = 0, free = 0, slots = 0 }

--------------------------------------------------------------------------
-- The words on the piles
--------------------------------------------------------------------------

-- The client's own word for an item class, or nothing where it will not say.
--
-- Both homes are tried for the reason every item lookup in Core tries both: the
-- newer client moved these into C_Item and took the loose global away. pcall
-- rather than a type test alone, because a class number this client has never
-- heard of is a real answer to give and not a reason to stop drawing bags.
local function ClassWord(classId)
	local lookup = (_G.C_Item and _G.C_Item.GetItemClassInfo) or _G.GetItemClassInfo
	if type(lookup) ~= "function" then
		return nil
	end
	local ok, word = pcall(lookup, classId)
	if ok and type(word) == "string" and word ~= "" then
		return word
	end
	return nil
end

-- What a pile is called, resolved once and kept on the pile.
--
-- Once rather than per scan because it cannot change inside a session, and on
-- the pile rather than in a second table because there is exactly one of these
-- per pile and a lookup that can go missing is a header that draws in English
-- on a client that had a word for it.
local function Word(group)
	if group.word == nil then
		group.word = (group.classId and ClassWord(group.classId)) or group.name
	end
	return group.word
end

Bags.Word = Word

--------------------------------------------------------------------------
-- The grouping
--------------------------------------------------------------------------

-- Which pile an item belongs in. The whole of the categorisation.
function Bags.GroupOf(link)
	if type(link) ~= "string" then
		return Bags.EMPTY
	end
	local itemId, classId = ns.ItemKind(link)
	if itemId == HEARTHSTONE then
		return "hearthstone"
	end
	-- Quality, and only where the client will grade it. Nil is "not cached
	-- yet" and has to stay out of the junk pile: an item wrongly called junk
	-- is an item sitting under the heading that means sell me.
	if ns.ItemValue(link) == 0 then
		return Bags.JUNK
	end
	return BY_CLASS[classId] or Bags.OTHER
end

-- What order two things in the same pile come in.
--
-- Grade first and then the name. Grade first because a pile is scanned for the
-- one thing in it that matters and the blue is nearly always it, and the name
-- second because two things of one grade have to hold still between scans or
-- the pile shuffles every time a stack changes size. Bag and slot break the
-- last tie, which is what makes the order total rather than nearly total.
--
-- Empty slots sort by where they are instead, because they have neither of the
-- other two and because a bag emptying should not renumber the squares.
local function Before(a, b)
	if a.group == Bags.EMPTY then
		if a.bag ~= b.bag then
			return a.bag < b.bag
		end
		return a.slot < b.slot
	end
	local left, right = a.quality or -1, b.quality or -1
	if left ~= right then
		return left > right
	end
	if a.name ~= b.name then
		return (a.name or "") < (b.name or "")
	end
	if a.bag ~= b.bag then
		return a.bag < b.bag
	end
	return a.slot < b.slot
end

-- The empty pile, folded into the one square that says how many there are.
--
-- Forty free slots drew forty identical grey squares, which is forty squares
-- carrying one number between them and a screen of scrolling to reach the pile
-- under them. What is kept is the first slot of the pile, which after the sort
-- is the lowest bag and slot you have free, and it carries the count of the
-- whole pile.
--
-- The square that survives is a real slot and not a placard, which is the
-- reason the first one is kept rather than a made up entry: it has a bag and a
-- slot, so the client's own handlers still take a drag onto it and the item
-- lands somewhere free. The count on it is the pile's size rather than a stack
-- size, and Grid.lua draws it in the middle of the square for that reason.
--
-- The free count in the footer is not read from here. Sweep counts it off the
-- slots themselves, so folding the pile cannot change the number.
local function Consolidate(held)
	if #held < 2 then
		return
	end
	held[1].count = #held
	for index = #held, 2, -1 do
		held[index] = nil
	end
end

--------------------------------------------------------------------------
-- The scan
--------------------------------------------------------------------------

-- One slot, into the pooled entry that belongs to it. Every field is written
-- whether or not there is anything in the slot, because an entry the pool hands
-- back is the entry some other slot used on the last pass.
local function Fill(index, bag, slot)
	local entry = state.entries[index]
	if not entry then
		entry = {}
		state.entries[index] = entry
	end

	local link = ns.ContainerItemLink(bag, slot)
	entry.bag, entry.slot, entry.link = bag, slot, link
	entry.name, entry.icon, entry.quality, entry.count = nil, nil, nil, 1
	if link then
		entry.name, entry.icon = ns.ItemInfo(link)
		entry.quality = ns.ItemValue(link)
		entry.count = ns.ContainerItem(bag, slot) or 1
	end
	entry.group = Bags.GroupOf(link)
	return entry
end

-- The piles, emptied and then handed the entries in the order they were found.
local function Sweep()
	local used, free, slots = 0, 0, 0
	for index = 1, #ORDER do
		wipe(buckets[ORDER[index].key])
	end

	for bag = FIRST_BAG, LAST_BAG do
		local count = ns.ContainerSlots(bag)
		slots = slots + count
		for slot = 1, count do
			used = used + 1
			local entry = Fill(used, bag, slot)
			local held = buckets[entry.group]
			held[#held + 1] = entry
			if not entry.link then
				free = free + 1
			end
		end
	end

	state.free, state.slots = free, slots
	return used
end

-- The piles that have anything in them, sorted, in drawing order.
local function Collect()
	local shown = 0
	for index = 1, #ORDER do
		local group = ORDER[index]
		local held = buckets[group.key]
		if #held > 0 then
			table.sort(held, Before)
			if group.key == Bags.EMPTY then
				Consolidate(held)
			end
			shown = shown + 1
			local row = state.groups[shown]
			if not row then
				row = {}
				state.groups[shown] = row
			end
			row.key, row.name, row.entries = group.key, Word(group), held
		end
	end
	state.shown = shown
end

-- Everything you are carrying, in piles, with the two numbers along the bottom.
--
-- The table handed back is the same table every time. A caller that wants to
-- keep an answer has to copy it, and nothing does: the window draws it and
-- forgets it, which is the shape that makes the pooling safe.
function Bags.Read()
	Sweep()
	Collect()
	return state
end

-- How many piles the last scan found. Public because the grid walks them by
-- number and the harness counts them.
function Bags.Groups()
	return state.groups, state.shown
end

function Bags.Free()
	return state.free, state.slots
end

function Bags.Describe()
	Bags.Read()
	if state.slots == 0 then
		return "no bag slots, which is a client that answered nothing"
	end
	return ("%d slots, %d free, in %d piles")
		:format(state.slots, state.free, state.shown)
end
