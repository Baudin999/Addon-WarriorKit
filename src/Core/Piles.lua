local ADDON, ns = ...

local Piles = {}
ns.Piles = Piles

--------------------------------------------------------------------------
-- Items, in piles
--
-- A pile is the class the client already files an item under. Not a search
-- string, not a rule anybody typed. `ns.ItemKind` reads GetItemInfoInstant,
-- which comes out of the client's own item database and cannot miss the way a
-- cache lookup can, so the pile an item lands in is decided by the client and
-- is right on the first frame after a login. That is the whole reason the
-- grouping is fifteen lines rather than a feature: the client has already done
-- it and every bag addon in the world throws the answer away.
--
-- Three piles are not a class and each is worth the exception. Junk is quality
-- zero whatever class it is, because the thing every grey has in common is that
-- a vendor is where it goes. Empty is the absence of an item, and it is a pile
-- rather than a gap so a free count has something you can point at.
--
-- Session is the third and it is the odd one, because nothing in this file can
-- decide it. It is what reached your bags between pressing record and pressing
-- stop, which is a fact about an hour of your evening rather than about an
-- item, and the only part that knows it is Bags/Session.lua. What is here is
-- the pile's place in the order and its heading, and Piles.Rename below is how
-- that heading comes to say Dire Maul. Nothing fills it but the bag window: a
-- vendor's rack goes through Piles.Of, which never answers this key.
--
-- **Quality can be nil and the pile still has to be right.** GetItemInfo, which
-- is the only call that grades an item, answers nothing for an item the client
-- has not cached. That is rare for something sitting in your own bags and it is
-- not impossible, and the honest reading of nil is "do not know" rather than
-- zero. So an ungraded item stays in its class pile instead of being called
-- junk, and moves the moment GET_ITEM_INFO_RECEIVED arrives. Every window built
-- on this file listens for that event for this reason and no other.
--
-- **It is in Core because two windows now ask.** This was Bags/Bags.lua's
-- private knowledge until the merchant window wanted the same answer about a
-- vendor's stock, and a part may not name a file outside its own tree. It is
-- the shape Core/Gear.lua and Core/Stance.lua already have: a shared file that
-- wraps a client API, owns no setting and draws nothing.
--
-- What is deliberately not here is the scan. Where the entries come from is the
-- caller's: five bags for one window and a merchant's index for the other, and
-- neither has anything to say about how the piles are ordered. This file takes
-- entries that already carry a `group` and hands back the piles that have
-- anything in them, in the order they are drawn.
--------------------------------------------------------------------------

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
-- it is not drawn at all, so the list being long costs an empty bag nothing,
-- and costs a vendor who sells one class of thing nothing either.
--
-- `name` is the fallback, in English. What is actually drawn is the client's
-- own word for the class where it will say one, resolved once at the first
-- scan, so a German client reads Handwerkswaren rather than Trade Goods.
local ORDER = {
	-- First, above even the hearthstone. It is what you pressed a button to
	-- start recording, so it is the reason the window is open.
	{ key = "session",     name = "Session" },
	{ key = "hearthstone", name = "Hearthstone" },
	{ key = "consumable",  name = "Consumable",   classId = 0 },
	{ key = "weapon",      name = "Weapon",       classId = 2, split = "bound" },
	{ key = "armor",       name = "Armor",        classId = 4, split = "bound" },
	{ key = "container",   name = "Container",    classId = 1 },
	{ key = "quiver",      name = "Quiver",       classId = 11 },
	{ key = "projectile",  name = "Projectile",   classId = 6 },
	{ key = "trade",       name = "Trade Goods",  classId = 7, nested = true },
	{ key = "reagent",     name = "Reagent",      classId = 5 },
	{ key = "recipe",      name = "Recipe",       classId = 9 },
	{ key = "quest",       name = "Quest",        classId = 12, split = "quest" },
	{ key = "key",         name = "Key",          classId = 13 },
	{ key = "misc",        name = "Miscellaneous", classId = 15, nested = true },
	{ key = "other",       name = "Other" },
	{ key = "junk",        name = "Junk" },
	{ key = "empty",       name = "Empty" },
}

Piles.EMPTY, Piles.JUNK, Piles.OTHER = "empty", "junk", "other"
Piles.SESSION = "session"

-- The three piles that are drawn in two lanes, and why the flag is here.
--
-- Weapons and armour are the only things you carry that bind, so they are the
-- only piles where "already yours" and "still worth something to somebody else"
-- is a division you can make at all. The quest pile divides on a different
-- fact and draws the same way: what a quest in your log still wants on the
-- left, and what nothing in your log wants on the right, where it is one
-- click from gone. The flag says which fact, "bound" or "quest", because the
-- two are read off different things, a tooltip for one and Questie's item rows
-- for the other, and only the window that walks a bag can read either. It is
-- on the pile rather than in the window because it falls out of the class: an
-- item class either binds or it does not, either is a quest item or is not,
-- and that is the same fact for every window that ever draws this list.
--
-- What a lane means and how wide it is are not here. Bags/Grid.lua decides
-- both, because they are drawing, and a vendor's rack reads the same flag and
-- ignores it: nothing on a shelf is bound to anybody yet.
--
-- A lookup rather than a walk, built off the list above so the two cannot
-- drift, the same way BY_CLASS below is. It is asked once per bag slot on every
-- bag update, and a linear scan of seventeen piles a hundred and fifty times
-- for an answer that never changes is the shape this file exists to avoid.
local SPLIT = {}
for index = 1, #ORDER do
	if ORDER[index].split then
		SPLIT[ORDER[index].key] = ORDER[index].split
	end
end

-- Which fact a pile divides on, or nil for a pile drawn in one lane.
function Piles.Splits(key)
	return SPLIT[key]
end

-- The two piles that are cut into sub-piles, and why.
--
-- Trade goods and miscellany are the two classes the client files everything
-- under that it has a word for and no better word for. A full bag holds forty
-- squares of cloth, ore, herbs, leather and pigment under one heading, and
-- the four totems a shaman carries are in among the pets and the holiday
-- trinkets. Both classes carry a subclass the client will name, Cloth or
-- Metal & Stone or Reagent, and that is the cut: one sub-pile per subclass,
-- each under the client's own word for it, and the items in one sorted by
-- their level so linen sits before wool before silk.
--
-- The subclass is the second thing Piles.Of answers and it is answered only
-- for these piles, so an entry's `sub` means "which sub-pile" and nothing
-- else. A pile whose entries all share one subclass is drawn as one pile
-- under its own heading: a sub-heading over everything says nothing.
--
-- Keyed the way SPLIT is and for the same reason.
local NESTED = {}
for index = 1, #ORDER do
	if ORDER[index].nested then
		NESTED[ORDER[index].key] = true
	end
end

function Piles.Nests(key)
	return NESTED[key] == true
end

-- Pile key to pile, for the sort below, which has to know what kind of pile
-- two entries are in and is handed only their key.
local BY_KEY = {}
for index = 1, #ORDER do
	BY_KEY[ORDER[index].key] = ORDER[index]
end

-- Class number to pile, built off the list above so the two cannot drift.
local BY_CLASS = {}
for index = 1, #ORDER do
	local group = ORDER[index]
	if group.classId then
		BY_CLASS[group.classId] = group.key
	end
end

-- One set of buckets per caller, made on first use and refilled from then on.
--
-- Per caller rather than one set shared, because two windows are open at a
-- merchant and the second scan would empty the first one's piles out from under
-- the frames still pointing at them. Keyed by the caller's own name so a part
-- asking twice gets the same set, which is what makes a scan allocate nothing
-- after the first one.
local sets = {}

local function Buckets(owner)
	local held = sets[owner]
	if not held then
		held = {}
		for index = 1, #ORDER do
			held[ORDER[index].key] = {}
		end
		sets[owner] = held
	end
	return held
end

--------------------------------------------------------------------------
-- The words on the piles
--------------------------------------------------------------------------

-- The client's own word for an item class, or nothing where it will not say.
--
-- Both homes are tried for the reason every item lookup in Core tries both: the
-- newer client moved these into C_Item and took the loose global away. pcall
-- rather than a type test alone, because a class number this client has never
-- heard of is a real answer to give and not a reason to stop drawing piles.
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

-- The client's own word for a subclass, or nothing where it will not say.
-- Resolved the way ClassWord is: Baganator reads C_Item.GetItemSubClassInfo
-- on this client and the loose global is what the older one carries.
local function SubClassWord(classId, subClassId)
	local lookup = (_G.C_Item and _G.C_Item.GetItemSubClassInfo) or _G.GetItemSubClassInfo
	if type(lookup) ~= "function" then
		return nil
	end
	local ok, word = pcall(lookup, classId, subClassId)
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

Piles.Word = Word

-- What a sub-pile is called, resolved once per subclass and kept on the pile.
--
-- A client with no word for the number gets the pile's word and the number
-- after it, which is a heading nobody should see and one that still tells two
-- sub-piles apart. An entry with no subclass at all is headed with the pile's
-- own word: it is the sub-pile of things the client did not file further.
local function SubWord(group, sub)
	if sub == nil then
		return Word(group)
	end
	group.subs = group.subs or {}
	local word = group.subs[sub]
	if word == nil then
		word = SubClassWord(group.classId, sub) or ("%s %d"):format(Word(group), sub)
		group.subs[sub] = word
	end
	return word
end

-- The heading on a pile, said by the part that owns it.
--
-- One pile takes one and it is the session's: its heading is the zone you were
-- standing in when you pressed record, which no table in this file could hold.
-- Written onto the pile rather than into a second table for the reason Word
-- caches there, and nil puts the fallback name back, so a cleared session is a
-- pile called Session again rather than one still wearing last night's dungeon.
function Piles.Rename(key, word)
	for index = 1, #ORDER do
		if ORDER[index].key == key then
			ORDER[index].word = (type(word) == "string" and word ~= "") and word or nil
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------
-- The grouping
--------------------------------------------------------------------------

-- Which pile an item belongs in, and which sub-pile of it. The whole of the
-- categorisation.
--
-- The sub-pile is the client's subclass number and it is answered only for a
-- pile that is cut into them, so a caller can write both answers onto an
-- entry and read `sub` as "which sub-pile" without asking again.
function Piles.Of(link)
	if type(link) ~= "string" then
		return Piles.EMPTY, nil
	end
	local itemId, classId, subClassId = ns.ItemKind(link)
	if itemId == HEARTHSTONE then
		return "hearthstone", nil
	end
	-- Quality, and only where the client will grade it. Nil is "not cached
	-- yet" and has to stay out of the junk pile: an item wrongly called junk
	-- is an item sitting under the heading that means sell me.
	if ns.ItemValue(link) == 0 then
		return Piles.JUNK, nil
	end
	local key = BY_CLASS[classId] or Piles.OTHER
	if NESTED[key] then
		return key, subClassId
	end
	return key, nil
end

-- What order two things in the same pile come in.
--
-- Grade first and then the name. Grade first because a pile is scanned for the
-- one thing in it that matters and the blue is nearly always it, and the name
-- second because two things of one grade have to hold still between scans or
-- the pile shuffles every time a stack changes size. `at` breaks the last tie,
-- which is what makes the order total rather than nearly total: it is bag and
-- slot for a bag window and the merchant's own index for a vendor, and either
-- way it is where the client put the thing.
--
-- Two kinds of pile put something in front of the grade. A pile cut into
-- sub-piles sorts by subclass first, which is what makes the cut possible
-- from one sorted list, and by the item's own level inside a subclass, so
-- the cloth runs linen to netherweave the way the game hands it out. The
-- quest pile sorts by rank, which is the row of the log the item belongs to,
-- with the ranked ahead of the unranked: what you are on, in the order you
-- are on it, and then the leftovers. Both fall through to the grade and the
-- name after that, so two things at one level hold still the same way.
--
-- Empty slots sort by where they are instead, because they have neither of the
-- other two and because a bag emptying should not renumber the squares.
local function Ahead(a, b)
	local group = BY_KEY[a.group]
	if not group then
		return nil
	end
	if group.nested then
		local left, right = a.sub or math.huge, b.sub or math.huge
		if left ~= right then
			return left < right
		end
		left, right = a.level or 0, b.level or 0
		if left ~= right then
			return left < right
		end
	elseif group.split == "quest" then
		if (a.rank == nil) ~= (b.rank == nil) then
			return a.rank ~= nil
		end
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
	end
	return nil
end

local function Before(a, b)
	if a.group == Piles.EMPTY then
		return (a.at or 0) < (b.at or 0)
	end
	local ahead = Ahead(a, b)
	if ahead ~= nil then
		return ahead
	end
	local left, right = a.quality or -1, b.quality or -1
	if left ~= right then
		return left > right
	end
	if a.name ~= b.name then
		return (a.name or "") < (b.name or "")
	end
	return (a.at or 0) < (b.at or 0)
end

Piles.Before = Before

--------------------------------------------------------------------------

-- Every entry dropped into the pile its own `group` names.
--
-- The buckets are emptied first and the entries are handed over in the order
-- they were found, which is what makes the sort below stable in the only sense
-- that matters: two scans of an unchanged bag come out identical.
function Piles.Fill(owner, entries, used)
	local buckets = Buckets(owner)
	for index = 1, #ORDER do
		wipe(buckets[ORDER[index].key])
	end
	for index = 1, used do
		local entry = entries[index]
		local held = buckets[entry.group]
		held[#held + 1] = entry
	end
	return buckets
end

-- One row of the caller's state: a pile, or one sub-pile of a pile, under the
-- heading it is drawn with.
--
-- `under` is the sub-pile flag and the window reads it as a smaller heading.
-- A pile that is cut writes one row with nothing in it for its own heading
-- and then a row per sub-pile, so a reader walking the rows draws a heading,
-- a sub-heading, some squares, a sub-heading, some squares. The empty row is
-- the one shape a reader has to expect that it did not before: a heading with
-- no squares under it and no air after it.
local function Row(state, shown, group, held, name, under, sub)
	shown = shown + 1
	local row = state.groups[shown]
	if not row then
		row = {}
		state.groups[shown] = row
	end
	row.key, row.name, row.entries = group.key, name, held
	row.split = group.split ~= nil
	row.under, row.sub = under, sub
	return shown
end

-- The heading row of a cut pile has nothing under it, and this is that
-- nothing: one table, never written to, so no reader can mistake it for a
-- pile that emptied.
local NONE = {}

-- The sub-pile tables, one pool per caller and refilled from then on, for the
-- reason the buckets are. `used` is how many this pass has handed out.
local slices = {}

local function Slice(owner)
	local pool = slices[owner]
	if not pool then
		pool = { used = 0 }
		slices[owner] = pool
	end
	pool.used = pool.used + 1
	local slice = pool[pool.used]
	if not slice then
		slice = {}
		pool[pool.used] = slice
	end
	wipe(slice)
	return slice
end

-- One sorted pile, cut at every change of subclass into a heading row and a
-- row per sub-pile. A pile whose entries all share one subclass is one row
-- under its own heading, which is the only case where the first and the last
-- entry of a list sorted by subclass agree.
local function Nest(owner, state, shown, group, held)
	if held[1].sub == held[#held].sub then
		return Row(state, shown, group, held, Word(group), false, nil)
	end
	shown = Row(state, shown, group, NONE, Word(group), false, nil)
	local start = 1
	for index = 2, #held + 1 do
		if index > #held or held[index].sub ~= held[start].sub then
			local slice = Slice(owner)
			for at = start, index - 1 do
				slice[#slice + 1] = held[at]
			end
			local sub = held[start].sub
			shown = Row(state, shown, group, slice, SubWord(group, sub), true, sub)
			start = index
		end
	end
	return shown
end

-- The piles that have anything in them, sorted, in drawing order, written into
-- the caller's own state table.
--
-- `fold` is handed a pile that is about to be drawn and may shorten it. One
-- caller passes one: the bag window folds its empty pile into the single square
-- that says how many free slots there are. Nothing else has an equivalent, and
-- a hook is cheaper than the alternative, which is this loop written twice.
--
-- A cut pile comes out as more than one row; see Nest. A caller whose entries
-- carry no `sub`, which is the merchant's rack, gets every pile in one row the
-- way it always did.
function Piles.Collect(owner, state, fold)
	local buckets = sets[owner]
	local shown = 0
	if not buckets then
		state.shown = 0
		return 0
	end
	if slices[owner] then
		slices[owner].used = 0
	end
	for index = 1, #ORDER do
		local group = ORDER[index]
		local held = buckets[group.key]
		if #held > 0 then
			table.sort(held, Before)
			if fold then
				fold(group.key, held)
			end
			if group.nested then
				shown = Nest(owner, state, shown, group, held)
			else
				shown = Row(state, shown, group, held, Word(group), false, nil)
			end
		end
	end
	state.shown = shown
	return shown
end

-- How many piles there are at all. The harness reads it to say that the order
-- above and the buckets underneath it cannot drift.
function Piles.Count()
	return #ORDER
end
