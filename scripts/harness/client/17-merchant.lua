-- The vendor.
--
-- Five things on a rack, chosen so that every branch a row can take is on the
-- screen at once: an ordinary price, a stack the vendor sells two hundred at a
-- time, a limited supply, something this class cannot use, and one priced in
-- tokens rather than in money. Nothing here is convenient; each row is a shape
-- the real merchant API answers and the addon has to draw differently.
--
-- What this does not model is the item arriving in your bags. A purchase moves
-- the purse, counts down a limited supply and fires the update the client fires,
-- which is every part of the sale the merchant window reads. Where the thing
-- lands is the container API's business and 04-hands.lua already owns it, and
-- putting a sixth item in a bag here would move the slot counts three other
-- sections are written against.

local H = ...
local ITEMS, itemLink, CARRIED = H.ITEMS, H.itemLink, H.CARRIED
local carrying, unitName, state = H.carrying, H.unitName, H.state

-- What the vendor sells, added to the item table the rest of the client reads
-- so a link off this rack grades and prices the same way a link out of a bag
-- does.
ITEMS["Refreshing Spring Water"] = { id = 5001, classId = 0, quality = 1,
	price = 0, icon = "Interface\\Icons\\Water" }
ITEMS["Sharp Arrow"] = { id = 5002, classId = 6, quality = 1,
	price = 0, icon = "Interface\\Icons\\Arrow" }
ITEMS["Flask of Petrification"] = { id = 5003, classId = 0, quality = 3,
	price = 4500, icon = "Interface\\Icons\\Flask" }
ITEMS["Runed Copper Rod"] = { id = 5004, classId = 15, quality = 1,
	price = 200, icon = "Interface\\Icons\\Rod" }
ITEMS["Gladiator's Plate Helm"] = { id = 5005, classId = 4, quality = 4,
	price = 0, icon = "Interface\\Icons\\Helm", equip = "INVTYPE_HEAD" }
-- The token the last of those is priced in. It is an item like any other, which
-- is the whole point: what you pay with is counted out of your bags.
ITEMS["Mark of Honor Hold"] = { id = 5006, classId = 12, quality = 1,
	price = 0, icon = "Interface\\Icons\\Mark" }

-- `available` is -1 for an endless supply, which is the client's own answer and
-- the one number a window must not draw as a count. `quantity` is what one
-- press buys and `stack` is what one call can carry, and the four combinations
-- of the two are on this rack: five in a batch and four batches to a stack, two
-- hundred in a batch and five batches, a single that stacks and a single that
-- does not.
local RACK = {
	{ name = "Refreshing Spring Water", price = 25, quantity = 5, stack = 20,
		available = -1, usable = true },
	{ name = "Sharp Arrow", price = 200, quantity = 200, stack = 1000,
		available = -1, usable = true },
	{ name = "Flask of Petrification", price = 90000, quantity = 1, stack = 5,
		available = 2, usable = true },
	{ name = "Runed Copper Rod", price = 4000, quantity = 1, stack = 1,
		available = -1, usable = false },
	{ name = "Gladiator's Plate Helm", price = 0, quantity = 1, stack = 1,
		available = -1, usable = true,
		costs = { { name = "Mark of Honor Hold", count = 40 } } },
}

local open = false
local bought = {}

-- The buyback rack. A stack of what has been sold this session, oldest at the
-- bottom, which is the order the client holds it in: the slot number goes up
-- as you sell and the newest thing is the highest one.
--
-- A slot taken back leaves a hole rather than closing up, and the hole is the
-- part worth modelling. GetNumBuybackItems answers the top of the range and
-- not how many things are in it, so a window that trusted the count as a list
-- length would draw a blank row for every gap. Nothing in the real client says
-- that out loud either.
local SOLD = {}

--------------------------------------------------------------------------

local function entry(index)
	return open and RACK[index] or nil
end

_G.GetMerchantNumItems = function()
	return open and #RACK or 0
end

-- Seven values in the order both clients this addon ships to answer them:
-- name, texture, price, quantity, numAvailable, isUsable, extendedCost.
_G.GetMerchantItemInfo = function(index)
	local row = entry(index)
	if not row then
		return nil
	end
	return row.name, ITEMS[row.name].icon, row.price, row.quantity,
		row.available, row.usable, row.costs ~= nil
end

_G.GetMerchantItemLink = function(index)
	local row = entry(index)
	return row and itemLink(row.name) or nil
end

_G.GetMerchantItemCostInfo = function(index)
	local row = entry(index)
	return (row and row.costs) and #row.costs or 0
end

_G.GetMerchantItemCostItem = function(index, which)
	local row = entry(index)
	local cost = row and row.costs and row.costs[which]
	if not cost then
		return nil
	end
	return ITEMS[cost.name].icon, cost.count, itemLink(cost.name), cost.name
end

-- How many of something you are carrying, counted off the bags rather than kept
-- as a number. A token you spend has to stop being countable, and the only
-- honest way to model that is to read the same bags the sale takes it out of.
_G.GetItemCount = function(link)
	local want = type(link) == "string" and link:match("%[(.-)%]")
	if not want then
		return 0
	end
	local held = 0
	for bag = 0, 4 do
		for slot = 1, (CARRIED[bag] and #CARRIED[bag] or 0) do
			if carrying(bag, slot) == want then
				held = held + 1
			end
		end
	end
	return held
end

-- The most of one entry the client will sell in one call, in items.
--
-- The item's own stack size and not the vendor's batch, which is the difference
-- the window has to do arithmetic on: water is five a batch and twenty a stack,
-- so four presses' worth is what one call can carry. A rack row with no stack
-- of its own answers its batch, which is one call's worth and no choice.
_G.GetMerchantItemMaxStack = function(index)
	local row = entry(index)
	if not row then
		return 0
	end
	return row.stack or row.quantity or 1
end

-- The sale. The purse moves, a limited supply counts down, and the client says
-- so, which is the whole of what the window reads.
--
-- `count` is items and not batches, which is the post-4.1 spelling both clients
-- this addon ships to answer. The price and the supply are per batch, so both
-- are worked out from how many batches the count came to: asking for five water
-- off a vendor selling five at a time is one batch, one price and one off his
-- shelf. Asking for fewer than a batch is what the addon did for a day, and it
-- is modelled rather than rounded away: the client charges the batch price for
-- the part batch, which is what makes buying one water cost five water's money.
_G.BuyMerchantItem = function(index, count)
	local row = entry(index)
	if not row then
		return
	end
	count = count or row.quantity or 1
	local batches = math.ceil(count / (row.quantity or 1))
	if row.available >= 0 then
		if row.available < batches then
			return
		end
		row.available = row.available - batches
	end
	state.purse = state.purse - row.price * batches
	bought[index] = (bought[index] or 0) + count
	H.fire("MERCHANT_UPDATE")
end

-- A batch picked up onto the cursor, which is the client's left click. Nothing
-- moves in the purse: the sale happens when the client puts the thing down in
-- a bag, and that half is not modelled here for the reason the header gives.
_G.PickupMerchantItem = function(index)
	local row = entry(index)
	if not row then
		return
	end
	H.hold({ merchant = index })
end

-- The client's first look at any modified click on an item. Recorded rather
-- than flat, because the fact worth asserting is that the rack offered the
-- link to the client before it decided anything of its own; it never takes
-- the press here, since no chat box is open and there is no dressing room.
local linked = {}
_G.HandleModifiedItemClick = function(link)
	linked[#linked + 1] = link
	return false
end

--------------------------------------------------------------------------

-- What you sold him, and what taking it back costs. Five values in the order
-- both clients answer them: name, texture, price, quantity, numAvailable, and
-- whether your class can use it.
_G.GetNumBuybackItems = function()
	if not open then
		return 0
	end
	local top = 0
	for index = 1, #SOLD do
		if SOLD[index] then
			top = index
		end
	end
	return top
end

local function sold(index)
	return open and SOLD[index] or nil
end

_G.GetBuybackItemInfo = function(index)
	local row = sold(index)
	if not row then
		return nil
	end
	return row.name, ITEMS[row.name].icon, row.price, row.quantity, 1, true
end

_G.GetBuybackItemLink = function(index)
	local row = sold(index)
	return row and itemLink(row.name) or nil
end

-- Taking one back. The purse pays what he paid you, the slot empties, and the
-- client says so with the same update a purchase fires, which is the whole of
-- what the window reads.
_G.BuybackItem = function(index)
	local row = sold(index)
	if not row then
		return
	end
	SOLD[index] = false
	state.purse = state.purse - row.price
	H.fire("MERCHANT_UPDATE")
end

--------------------------------------------------------------------------

-- The frame the addon parks. It is given a size because the park is checked by
-- reading where its left edge landed, and a frame with no width has no edges.
_G.MerchantFrame:SetSize(336, 400)

local function shut()
	if not open then
		return false
	end
	open = false
	_G.MerchantFrame:Hide()
	H.fire("MERCHANT_CLOSED")
	return true
end

_G.CloseMerchant = shut

-- What a section drives the scene with. `open` is walking up to the vendor and
-- `close` is walking away from him; `rack` and `bought` are what the section
-- asserts against.
H.merchant = {
	rack = RACK,
	bought = bought,
	linked = linked,
	open = function(who)
		if open then
			return false
		end
		unitName.npc = who or "Innkeeper Allison"
		open = true
		_G.MerchantFrame:Show()
		H.fire("MERCHANT_SHOW")
		return true
	end,
	close = shut,
	shown = function() return open end,
	-- Selling him something, from the section rather than from a bag. What a
	-- sale does to your bags is 04-hands.lua's business and what it does to the
	-- vendor is this: the purse goes up and a slot appears on the buyback rack.
	sell = function(name, price, quantity)
		if not open then
			return false
		end
		SOLD[#SOLD + 1] = { name = name, price = price or 1,
			quantity = quantity or 1 }
		state.purse = state.purse + (price or 1)
		H.fire("MERCHANT_UPDATE")
		return #SOLD
	end,
	sold = SOLD,
}
