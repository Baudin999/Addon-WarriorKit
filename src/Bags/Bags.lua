local ADDON, ns = ...

local Bags = {}
ns.Bags = Bags

--------------------------------------------------------------------------
-- What you are carrying, in piles
--
-- The scan, and no frame anywhere in the file. Grid.lua draws what this answers
-- and Window.lua decides when to ask.
--
-- **The piles themselves are Core/Piles.lua's.** Which class an item is filed
-- under, what that class is called in your language, and what order the piles
-- are drawn in were all in this file until the merchant window wanted the same
-- answers about a vendor's stock. What is left here is the half that is
-- genuinely about your bags: which five of them to walk, what a slot is worth,
-- and the one fold that turns forty empty squares into one.
--
-- **The bank is not here.** Five bags, the backpack and the four on the belt,
-- which is what you are carrying. A bank window is a second window reading a
-- second set of bag numbers, and it can be written the day somebody wants it
-- without changing a line of this file.
--------------------------------------------------------------------------

-- The backpack and the four on the belt. The bank's bags are numbered past
-- these and the keyring below them, and neither is what this window is about.
local FIRST_BAG, LAST_BAG = 0, 4

-- The two piles this part names by hand. Both are Core's, aliased here because
-- Grid.lua and Merchant.lua ask a question about a bag square and a bag square
-- is this file's subject.
Bags.EMPTY, Bags.JUNK = ns.Piles.EMPTY, ns.Piles.JUNK

-- One table, refilled on every scan rather than rebuilt.
--
-- A bag update arrives five times for one loot and the window answers each of
-- them, so a scan that allocated a table per slot would be a hundred and fifty
-- objects for a stack of cloth. The entries are a pool keyed by how far into
-- the walk they are, which is stable because the walk is: bag zero slot one is
-- entry one whatever is in it.
local state = { groups = {}, entries = {}, shown = 0, free = 0, slots = 0 }

--------------------------------------------------------------------------

-- Whether a vendor will take what is on this square.
--
-- The client's own sell price and no rule of ours. Nought is the answer for a
-- quest item, a soulbound token and everything else the game will not buy back,
-- and nil is an item this client has not cached yet, which reads as no for the
-- reason the junk pile refuses to grade one: a guess here is a square drawn as
-- sellable that a merchant then refuses.
function Bags.Sellable(entry)
	return entry.link ~= nil and (entry.price or 0) > 0
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
local function Consolidate(key, held)
	if key ~= ns.Piles.EMPTY or #held < 2 then
		return false
	end
	held[1].count = #held
	for index = #held, 2, -1 do
		held[index] = nil
	end
	return true
end

--------------------------------------------------------------------------
-- The scan
--------------------------------------------------------------------------

-- One slot, into the pooled entry that belongs to it. Every field is written
-- whether or not there is anything in the slot, because an entry the pool hands
-- back is the entry some other slot used on the last pass.
--
-- `at` is how far into the walk this slot is, which is the number Core/Piles.lua
-- breaks a tie on. It is bag and slot flattened, so it sorts the way the two of
-- them did.
local function Fill(index, bag, slot)
	local entry = state.entries[index]
	if not entry then
		entry = {}
		state.entries[index] = entry
	end

	local link = ns.ContainerItemLink(bag, slot)
	entry.at, entry.bag, entry.slot, entry.link = index, bag, slot, link
	entry.name, entry.icon, entry.quality, entry.count = nil, nil, nil, 1
	entry.price = nil
	if link then
		entry.name, entry.icon = ns.ItemInfo(link)
		-- Both halves of one call. The grade decides the pile and the price
		-- decides whether the square wears a coin and whether it goes dim at a
		-- merchant, and asking for the second one separately would be a second
		-- cache lookup per slot for a number the first one already handed back.
		entry.quality, entry.price = ns.ItemValue(link)
		entry.count = ns.ContainerItem(bag, slot) or 1
	end
	entry.group = ns.Piles.Of(link)
	return entry
end

-- Every slot in the five bags, into the pooled entries, and the two numbers
-- along the bottom counted off the slots themselves.
local function Sweep()
	local used, free, slots = 0, 0, 0
	for bag = FIRST_BAG, LAST_BAG do
		local count = ns.ContainerSlots(bag)
		slots = slots + count
		for slot = 1, count do
			used = used + 1
			if not Fill(used, bag, slot).link then
				free = free + 1
			end
		end
	end
	state.free, state.slots = free, slots
	return used
end

-- Everything you are carrying, in piles, with the two numbers along the bottom.
--
-- The table handed back is the same table every time. A caller that wants to
-- keep an answer has to copy it, and nothing does: the window draws it and
-- forgets it, which is the shape that makes the pooling safe.
function Bags.Read()
	local used = Sweep()
	ns.Piles.Fill(Bags, state.entries, used)
	ns.Piles.Collect(Bags, state, Consolidate)
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
