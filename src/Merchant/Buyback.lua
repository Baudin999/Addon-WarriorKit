local ADDON, ns = ...

local Buyback = {}
ns.Buyback = Buyback

--------------------------------------------------------------------------
-- What you sold
--
-- The second rack. The last twelve things you sold are on it at the price you
-- were paid, and taking one back is the only undo the game has for a sale. It
-- is not the vendor's list: you can sell to one vendor, walk to another, and
-- buy the thing back off him, which is why nothing in this file is keyed on who
-- you are talking to. Comfort/Destroy.lua leans on that fact and
-- so does the junk sweep: a sale is safe because it is recoverable, and it is
-- only recoverable while there is a window to recover it in.
--
-- **The addon has to draw it or nobody can reach it.** The client keeps buyback
-- behind the second tab of its own merchant frame, and that frame spends the
-- session parked off the side of the screen so its cross cannot end the
-- conversation by accident. Parking it took the buyback tab with it. So this is
-- not a feature added beside the merchant window; it is the half of the client's
-- window the merchant window replaced and had not put back.
--
-- **It is not in piles and it must not be.** Stock.lua files a rack under the
-- bag window's class headings because a rack is a shop and you are looking for
-- a kind of thing. You open buyback for one reason: the thing you just sold. So
-- the order is the order you sold them in, newest first, and there are at most
-- twelve. A pile of one Consumable over a pile of one Armor would bury the one
-- square anybody came here for.
--
-- **The slots are a range, not a list.** GetNumBuybackItems answers the highest
-- slot the vendor is holding rather than how many things are in it, and a slot
-- you have already taken something out of answers no name at all. So the walk
-- runs the whole range and skips the holes, which is what the client's own
-- frame does with the same numbers.
--------------------------------------------------------------------------

-- One table, refilled on every pass, the same pooling Stock.lua uses. The
-- entries are keyed by where they are drawn rather than by the merchant slot,
-- because the drawing order is the reverse of the slot order and the pool has
-- no opinion about either.
local state = { groups = {}, entries = {}, shown = 0, count = 0 }

-- The one pile, made once. Nameless on purpose: Grid.lua draws a heading for a
-- group that has a name, and the heading over this one would say what the tab
-- above it already says.
local group = { key = "buyback", name = nil, entries = {} }
state.groups[1] = group

--------------------------------------------------------------------------

-- One slot, into the pooled entry that belongs to it. Every field is written
-- whether or not the client answered, because an entry the pool hands back is
-- the entry some other slot used on the last pass.
--
-- `index` is the vendor's own buyback slot, which is what the purchase is made
-- with, and `at` is where the row sits. They are different numbers here and the
-- same number in Stock.lua, which is why both are written in both files.
local function Fill(at, index)
	local entry = state.entries[at]
	if not entry then
		entry = { costs = {} }
		state.entries[at] = entry
	end

	local name, icon, price, quantity, available, usable = ns.BuybackItem(index)
	local link = ns.BuybackItemLink(index)
	entry.at, entry.index, entry.link, entry.name, entry.icon = at, index, link, name, icon
	entry.price = price or 0
	entry.quantity = quantity or 1
	entry.available = available or 1
	entry.usable = usable ~= false
	entry.extended = false
	entry.wants = 0
	entry.quality = link and ns.ItemValue(link) or nil
	entry.group = group.key
	return entry
end

--------------------------------------------------------------------------
-- What a row asks about an entry
--
-- The four calls Grid.lua makes on whichever rack it is drawing. Stock.lua
-- answers them about the vendor's stock and this answers them about your own
-- returns, which is what lets one pool of squares draw both racks: the square
-- knows how to lay a thing out and nothing about which of the two it came off.
--------------------------------------------------------------------------

-- Always. What is on this rack is one of a thing you sold, and the vendor
-- cannot run out of it while it is sitting there.
function Buyback.InStock()
	return true
end

-- Nothing, every time. A count in the box means a limited supply, and there is
-- no such thing here: every slot holds exactly what you sold out of it.
function Buyback.Left()
	return nil
end

-- Whether you could pay for it back. Money only, because nothing that reaches
-- this rack was bought with tokens: what a badge vendor sells is soulbound
-- before it lands in a bag, and a soulbound item cannot be sold.
function Buyback.Afford(entry)
	return (entry.price or 0) <= GetMoney()
end

--------------------------------------------------------------------------

-- Everything the vendor is holding for you, newest first.
--
-- The same table every time, the same contract Stock.Read makes: the window
-- draws it and forgets it. `shown` is one when there is anything and nought
-- when there is not, so a rack with nothing on it draws nothing rather than an
-- empty heading.
function Buyback.Read()
	local slots = ns.BuybackCount()
	local entries = group.entries
	local at = 0
	for index = slots, 1, -1 do
		local name = ns.BuybackItem(index)
		if name then
			at = at + 1
			entries[at] = Fill(at, index)
		end
	end
	for extra = at + 1, #entries do
		entries[extra] = nil
	end
	state.count = at
	state.shown = at > 0 and 1 or 0
	return state
end

function Buyback.Count()
	return state.count
end

-- Take one back.
--
-- No question in front of it, unlike a rack priced in tokens. This is the
-- undo: the money involved is money the vendor handed you a minute ago, and a
-- window that asks whether you are sure you want your own item back has
-- misread which of the two directions is the one you cannot recover from.
function Buyback.Buy(entry)
	if not entry or not entry.index then
		return false, "nothing on that row"
	end
	if not ns.TakeBack(entry.index) then
		return false, "this client has no call to buy back with"
	end
	return true
end

function Buyback.Describe()
	if state.count == 0 then
		return "nothing sold yet"
	end
	return ("%d to buy back, newest first"):format(state.count)
end
