local ADDON, ns = ...

local C = ns.UI.Color

--------------------------------------------------------------------------
-- What an item is worth, on any tooltip in the addon
--
-- Two numbers that answer different questions.
--
-- The vendor price is what the merchant hands you and it is a fact the client
-- holds. It is on the item's own tooltip already, in copper, per item, and the
-- thing it does not say is what a stack of eleven silk cloth is worth, which is
-- the number you actually want when deciding whether to walk back.
--
-- The auction price is not a fact the client holds at all. It comes out of
-- whichever scanner the player has installed, and it is the difference between
-- vendoring a green and posting it. See Feeds/Auction.lua for who is asked and
-- why the line names them.
--
-- **This is a hook rather than four lines in the loot feed, and that is the
-- point.** It was four lines in Feeds/Loot.lua, which meant the only item in
-- the game whose worth the addon would tell you was one that had just dropped.
-- A mail attachment, an item somebody linked in chat, a square on the action
-- bar holding a healthstone: all items, all hovered, all silent. It is one
-- source registered against the item kind now, so every one of them says the
-- same two lines in the same place.
--
-- **Neither line appears when there is nothing true to put on it.** An item the
-- client has not cached has no vendor price and gets no vendor line, which is
-- not the same as a price of zero: an item a vendor will not take is a real
-- thing and says so in words. A client with no auction addon gets no auction
-- line and no note about it, because a tooltip is not the place to advertise
-- somebody else's addon.
--
-- **A caller may hand over the price it already knew.** The loot feed does, and
-- it has to: it records the sell price when the item drops, because the client
-- will answer about something in your bags and go quiet about one you have
-- already sold. Everything else leaves the field out and gets the live answer.
--------------------------------------------------------------------------

-- What the merchant pays, per item and for the stack.
--
-- The stack line only appears where it says something the first does not, which
-- is a stack of more than one that a vendor will actually pay for.
local function Vendor(lines, subject)
	local price = subject.price
	if price == nil then
		local _, sell = ns.ItemValue(subject.link)
		price = sell
	end
	if not price then
		return lines
	end
	if price <= 0 then
		lines[#lines + 1] = { "Vendor", "will not take it", tone = C.quiet }
		return lines
	end

	lines[#lines + 1] = { "Vendor", ns.Coin(price) }
	local count = subject.count or 1
	if count > 1 then
		lines[#lines + 1] = { ("Stack of %d"):format(count),
			ns.Coin(price * count), tone = C.heading }
	end
	return lines
end

ns.Tip.Source({
	name = "what it is worth",
	kind = "item",
	band = "extra",
	order = 10,
	fill = function(subject)
		if type(subject.link) ~= "string" then
			return nil
		end

		local lines = Vendor({}, subject)

		local going, scanner = ns.Auction.Price(subject.link)
		if going then
			lines[#lines + 1] = { scanner, ns.Coin(going), tone = C.accent }
		end
		return lines
	end,
})
