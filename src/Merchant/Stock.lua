local ADDON, ns = ...

local Stock = {}
ns.Stock = Stock

--------------------------------------------------------------------------
-- What the vendor has, in piles
--
-- The scan and no frame anywhere in the file, which is the shape Bags/Bags.lua
-- has and for the same reason: Grid.lua draws what this answers and Window.lua
-- decides when to ask.
--
-- **The piles are the bag window's piles.** Core/Piles.lua files a merchant's
-- stock under the same class headings it files your bags under, in the same
-- order, in the same words. That is worth more here than it looks. Two windows
-- are open at a vendor and both are lists of items; a reagent vendor's rack
-- reading Reagent while the stack of the same reagents in your bags reads
-- Reagent means you can see at a glance which of the two you are looking at
-- something in.
--
-- **A page is not a thing here.** The client draws ten at a time and puts an
-- arrow under them, so buying the fourth thing on the second page of a
-- quartermaster is two clicks of an arrow before the click that matters. The
-- merchant index runs from one to GetMerchantNumItems and this walks all of it,
-- because a scroll bar is what a list longer than a window is for and the addon
-- already has one.
--
-- **Everything is read fresh on every pass.** A vendor with limited stock counts
-- down as you buy, an entry priced in tokens changes what you can afford as you
-- spend them, and MERCHANT_UPDATE is the client saying one of those moved. The
-- rack is thirty rows at most, so there is nothing here worth caching and a
-- cache would be the thing that draws a row you can no longer buy.
--------------------------------------------------------------------------

-- What the client means by an endless supply. It is not a count and must not be
-- drawn as one: a stack of thread that says "-1 left" is worse than one that
-- says nothing.
local ENDLESS = -1

-- One table, refilled on every scan rather than rebuilt, the same pooling
-- Bags/Bags.lua uses and for the same reason: MERCHANT_UPDATE arrives in bursts
-- and every one of them is answered in full.
local state = { groups = {}, entries = {}, shown = 0, count = 0 }

--------------------------------------------------------------------------

-- Who you are standing in front of.
--
-- The unit rather than a name kept from MERCHANT_SHOW, because the client
-- answers this for as long as the session is open and a name held in a local is
-- a name that outlives the session it belonged to.
function Stock.Vendor()
	local name = UnitName("npc")
	if type(name) ~= "string" or name == "" then
		return nil
	end
	return name
end

-- What this entry wants in payment other than money, into the entry's own
-- pooled table.
--
-- Nought for nearly everything. An entry with an extended cost is the badge
-- vendor, the honour quartermaster and the reputation rack: it is paid for in
-- tokens, the tokens are read one at a time, and the price in copper beside
-- them may be nought or may be a second half of the same bill.
local function Costs(entry, index)
	local held = entry.costs
	if not held then
		held = {}
		entry.costs = held
	end
	local wanted = entry.extended and ns.MerchantCosts(index) or 0
	for which = 1, wanted do
		local row = held[which]
		if not row then
			row = {}
			held[which] = row
		end
		row.icon, row.count, row.link, row.name = ns.MerchantCost(index, which)
		row.held = ns.ItemCount(row.link)
	end
	entry.wants = wanted
	return wanted
end

-- One thing on the rack, into the pooled entry that belongs to it. Every field
-- is written whether or not the client answered, because an entry the pool
-- hands back is the entry some other index used on the last pass.
--
-- `at` is the merchant's own index, which is what Core/Piles.lua breaks a tie
-- on and what every call about this entry is made with.
local function Fill(index)
	local entry = state.entries[index]
	if not entry then
		entry = {}
		state.entries[index] = entry
	end

	local name, icon, price, quantity, available, usable, extended = ns.MerchantItem(index)
	local link = ns.MerchantItemLink(index)
	entry.at, entry.index, entry.link, entry.name, entry.icon = index, index, link, name, icon
	entry.price = price or 0
	entry.quantity = quantity or 1
	entry.available = available or ENDLESS
	entry.usable = usable and true or false
	entry.extended = extended and true or false
	entry.quality = link and ns.ItemValue(link) or nil
	-- The most the client will sell in one call, in items. Read per entry
	-- rather than worked out from the batch size, because it is the item's own
	-- stack and the two are unrelated: water is five a batch and twenty a
	-- stack, arrows are two hundred a batch and a thousand a stack, and a helm
	-- is one of each.
	entry.stack = ns.MerchantMaxStack(index)
	-- A link the client has not handed over yet is a row that still has a name,
	-- a picture and a price, so it is drawn under Other rather than under Empty.
	-- Empty is the bag window's pile for a slot with nothing in it and a vendor
	-- has no such thing.
	entry.group = link and ns.Piles.Of(link) or ns.Piles.OTHER
	Costs(entry, index)
	return entry
end

--------------------------------------------------------------------------

-- Whether this vendor has any of these left. True for everything on an ordinary
-- rack: a limited supply is the quartermaster's two mounts and the innkeeper's
-- one recipe.
function Stock.InStock(entry)
	return entry.available == ENDLESS or (entry.available or 0) > 0
end

-- How many are left where that is a number, and nothing where the supply is
-- endless. Two returns rather than one because "no answer" and "none left" are
-- opposite facts and a single number cannot carry both.
function Stock.Left(entry)
	if entry.available == ENDLESS then
		return nil
	end
	return entry.available or 0
end

-- Whether you could pay for one right now.
--
-- Money and tokens, because an entry with an extended cost may want both and
-- because the token half is the one you cannot work out by looking at your
-- purse. What this answers is used to dim a row rather than to refuse a click:
-- the server is what decides a sale, and a window that greys out a row on its
-- own arithmetic is a window that can be wrong in the direction that matters.
function Stock.Afford(entry)
	if (entry.price or 0) > GetMoney() then
		return false
	end
	for which = 1, (entry.wants or 0) do
		local row = entry.costs[which]
		if (row.held or 0) < (row.count or 0) then
			return false
		end
	end
	return true
end

--------------------------------------------------------------------------

-- Everything the vendor has, in piles.
--
-- The table handed back is the same table every time, the same contract
-- Bags.Read makes: the window draws it and forgets it.
function Stock.Read()
	local count = ns.MerchantCount()
	for index = 1, count do
		Fill(index)
	end
	state.count = count
	ns.Piles.Fill(Stock, state.entries, count)
	ns.Piles.Collect(Stock, state)
	return state
end

function Stock.Groups()
	return state.groups, state.shown
end

function Stock.Count()
	return state.count
end

-- How many batches one call can buy, which is what the number picker's range
-- is.
--
-- The client sells in items and the vendor prices in batches, so this is the
-- one place the two units meet: the stack divided by the batch, floored, and
-- never under one. Water is twenty over five and comes out four presses' worth;
-- a flask is one over one and comes out one, which is a rack entry with nothing
-- to choose.
--
-- A limited supply caps it as well, because `available` counts batches and the
-- server refuses the call that asks for more than he has. That refusal is
-- silent, so a picker that offered five of the two he is holding would look
-- like a window whose buy button does nothing.
--
-- One where the client has no stack call at all. That is the honest floor: the
-- feature stops offering a choice rather than guessing at a number the server
-- may refuse.
function Stock.Batches(entry)
	local batch = math.max(entry.quantity or 1, 1)
	local most = math.floor(math.max(entry.stack or batch, batch) / batch)
	local left = Stock.Left(entry)
	if left then
		most = math.min(most, left)
	end
	return math.max(most, 1)
end

-- Buy that many batches of what is on this row.
--
-- Batches in and items out, because those are the two units and the conversion
-- has to happen once. `quantity` is the client's own batch size: a vendor
-- selling water five at a time and asked for one press is asked for five water,
-- and asking him for one buys one water for the price of five. That was the
-- bug this call is written around, and it is the whole difference between a
-- press that fills your bags and a press that looks like it did nothing.
local function Spend(entry, batches)
	local items = math.max(batches or 1, 1) * math.max(entry.quantity or 1, 1)
	if not ns.BuyMerchant(entry.index, items) then
		return false, "this client has no call to buy with"
	end
	return true
end

-- What a token purchase asks before it spends.
--
-- Gold is not asked about and this is, and the difference is what you can get
-- back. Sell an item to the wrong vendor and the buyback tab has it for an
-- hour; spend forty badges and the badges are gone, with no window anywhere in
-- the game that returns them. That is the one kind of thing UI/Ask.lua exists
-- for, and a rack where one click costs a fortnight of dailies is the case the
-- client puts its own confirmation in front of too.
local function Sentence(entry, batches)
	local first = entry.costs[1]
	local wants = ("%d %s"):format((first.count or 1) * batches, first.name or "tokens")
	if (entry.wants or 0) > 1 then
		wants = ("%s and %d other"):format(wants, entry.wants - 1)
	end
	return ("Buy %s for %s? Tokens do not come back.")
		:format(entry.name or "this", wants)
end

-- `batches` is how many of the vendor's own units to take, and one where the
-- caller did not say. A plain press does not say; the number picker does.
function Stock.Buy(entry, batches)
	if not entry or not entry.index then
		return false, "nothing on that row"
	end
	if not Stock.InStock(entry) then
		return false, "this vendor has none of those left"
	end
	batches = math.min(math.max(math.floor(batches or 1), 1), Stock.Batches(entry))
	if (entry.wants or 0) > 0 then
		ns.UI.Ask({
			title = "Spend tokens",
			question = Sentence(entry, batches),
			accept = "buy it",
			onAccept = function() Spend(entry, batches) end,
		})
		return true
	end
	return Spend(entry, batches)
end

function Stock.Describe()
	if state.count == 0 then
		return "no merchant is open"
	end
	local who = Stock.Vendor()
	return ("%d things in %d piles%s")
		:format(state.count, state.shown, who and (", from " .. who) or "")
end
