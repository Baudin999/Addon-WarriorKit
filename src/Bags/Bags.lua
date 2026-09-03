local ADDON, ns = ...

local UI = ns.UI

local Bags = {}
ns.Bags = Bags

--------------------------------------------------------------------------
-- What you are carrying, in piles
--
-- The scan, and no frame anywhere in the file. Grid.lua draws what this answers
-- and Window.lua decides when to ask.
--
-- **One question here goes through a frame and it is not this file's.** Whether
-- an item has already bound to you is written nowhere an API will hand over, and
-- the only way to it is the client's own tooltip pointed at the slot. UI/Scan.lua
-- owns that frame and is the one file allowed to, so what this file does is ask
-- it a question and get a yes or a no back. See Lane below.
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

-- The client's own word for an item that has already bound to you.
--
-- The global rather than the English, because this is compared against text the
-- client wrote and on a German client it wrote "Seelengebunden". The fallback
-- is there so a build that has renamed the global still reads right on an
-- English client rather than filing every sword as unbound.
local SOULBOUND = _G.ITEM_SOULBOUND or "Soulbound"

-- One table, refilled on every scan rather than rebuilt.
--
-- A bag update arrives five times for one loot and the window answers each of
-- them, so a scan that allocated a table per slot would be a hundred and fifty
-- objects for a stack of cloth. The entries are a pool keyed by how far into
-- the walk they are, which is stable because the walk is: bag zero slot one is
-- entry one whatever is in it.
local state = { groups = {}, entries = {}, shown = 0, free = 0, slots = 0 }

-- Where each bag's slots begin in the walk, so a square can find the entry for
-- its own slot by arithmetic rather than by searching a hundred and fifty.
-- Written on every sweep, because a bag swapped for a bigger one moves every
-- bag after it.
local starts = {}

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

-- Which lane a square in a split pile goes in, which is whether the thing on
-- it is yours: bound to you, or wanted by a quest you are on.
--
-- Core/Piles.lua says which fact a pile divides on and this is where each is
-- read, because each is read off something only a bag scan can reach.
--
-- **Binding is read off the client's own tooltip and there is no other way to
-- it.** The link carries no history: a sword you have been swinging for three
-- months and the same sword on a vendor's shelf are character for character
-- the same string, and GetItemInfo answers "binds when equipped" about both.
-- Only the slot knows, which is why this takes a bag and a slot and why
-- UI/Scan.lua's `bag` kind exists. See Head in UI/Tip.lua, which is the other
-- caller that had to know.
--
-- Asked every scan and cached nowhere. The obvious cache is the pooled entry
-- itself, keyed on the link and the slot, and it is wrong in both directions.
-- An item the client has not graded yet answers a tooltip that says so, and a
-- cached "not bound" from the first scan after a login never gets asked again
-- however many times GET_ITEM_INFO_RECEIVED repaints the window. A bind on use
-- item bound in place is the other half: same link, same slot, different answer.
-- Scan.Has allocates nothing, so what a cache would buy here is a handful of C
-- calls, and what it costs is a lane that is quietly wrong for the session.
--
-- Nil from the probe is a client that will not take the question, and it reads
-- as unbound: one lane holding everything is a pile that looks like every other
-- pile in the window, and the alternative is a lane of soulbound greens that are
-- nothing of the sort.
--
-- **A quest item is read off Questie's item rows and the quest log.**
-- Core/QuestItems.lua answers two things: where in the log the quest that
-- wants it sits, which is the item's rank and what the pile sorts on, and
-- whether anything wants it at all, which is the lane. Its "cannot say" is the
-- left lane, for the reason that file gives, so a session with no Questie in
-- it draws the quest pile in one lane like every other pile and never offers
-- anything up.
--
-- Asked only of a pile that is drawn in two lanes, which is twenty squares in
-- a full bag rather than a hundred and fifty. Everything else is filed the
-- same whatever its binding, so either read would be paid for nothing.
local function Lane(entry, bag, slot, link)
	local kind = link and ns.Piles.Splits(entry.group)
	entry.rank = nil
	if not kind then
		entry.yours = false
		return false
	end
	if kind == "quest" then
		entry.rank, entry.yours = ns.QuestItems.Place(link)
		return entry.yours
	end
	entry.yours = UI.Scan.Has("bag", SOULBOUND, bag, slot) == true
	return entry.yours
end

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
	entry.price, entry.level = nil, nil
	if link then
		entry.name, entry.icon = ns.ItemInfo(link)
		-- Both halves of one call. The grade decides the pile and the price
		-- decides whether the square wears a coin and whether it goes dim at a
		-- merchant, and asking for the second one separately would be a second
		-- cache lookup per slot for a number the first one already handed back.
		entry.quality, entry.price = ns.ItemValue(link)
		-- The item's own level, which is what orders a sub-pile: linen before
		-- wool before silk. Read for every slot rather than only the two piles
		-- that sort on it, because the pile is not known until the line after
		-- this and a cache lookup per slot is what every other field costs.
		entry.level = ns.ItemLevel(link)
		entry.count = ns.ContainerItem(bag, slot) or 1
	end
	-- The pile, and for a pile that is cut into sub-piles, which one. Both from
	-- the one call, so `sub` is never a subclass the pile does not cut on.
	entry.group, entry.sub = ns.Piles.Of(link)
	-- The session pile overrules the class, and it is the only thing that does.
	-- What you picked up in the last hour is not a fact about the item, so it
	-- cannot be a rule in Core/Piles.lua and it must not reach the merchant
	-- window: a vendor's rack goes through Piles.Of and never comes here.
	--
	-- The count on the square is the session's rather than the stack's, because
	-- they are different numbers and the session's is the one you opened the
	-- window to read. See Bags/Session.lua on why this client cannot tell the
	-- twelve you looted from the eight you were already carrying.
	if link and ns.BagsSession.Holds(link) then
		entry.group = ns.Piles.SESSION
		entry.gained = ns.BagsSession.Gained(link)
	else
		entry.gained = nil
	end
	Lane(entry, bag, slot, link)
	return entry
end

-- Every slot in the five bags, into the pooled entries, and the two numbers
-- along the bottom counted off the slots themselves.
local function Sweep()
	local used, free, slots = 0, 0, 0
	for bag = FIRST_BAG, LAST_BAG do
		local count = ns.ContainerSlots(bag)
		slots = slots + count
		starts[bag] = used
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

-- What the last scan found on one slot, or nothing for a slot it did not walk.
--
-- Asked by Grid.lua while the layout is held at a merchant: the squares keep
-- their places and each one asks what is lying on its own slot now. The answer
-- is checked against the slot it names rather than trusted, because a bag
-- swapped in the middle of a hold shifts every entry after it, and the pool
-- keeps entries past the end of a walk that has shrunk.
function Bags.Entry(bag, slot)
	local start = starts[bag]
	if not start or start + slot > state.slots then
		return nil
	end
	local entry = state.entries[start + slot]
	if not entry or entry.bag ~= bag or entry.slot ~= slot then
		return nil
	end
	return entry
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
