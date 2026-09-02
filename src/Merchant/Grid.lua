local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

local Grid = {}
ns.MerchantGrid = Grid

--------------------------------------------------------------------------
-- The rack
--
-- One card per thing the vendor sells, drawn where the pile it belongs to puts
-- it. The pool never shrinks and a card is reassigned to whatever the scan put
-- on it this pass, which is the same trick Bags/Grid.lua plays with its squares
-- and for the same reason: a merchant update arrives in bursts and every one of
-- them is answered by laying the whole rack out again.
--
-- **A card is a square with the name and the price beside it.** This was a bare
-- grid of squares for a day and the day was enough. A vendor's rack is not a
-- bag: a bag is a hundred and fifty pictures of things you already own and
-- recognise, and a rack is a price list. Squares alone drew a run of small
-- pictures with no word anywhere on them, which is the one shape a shop must
-- not have, and the price was a hover away on every single entry. What you are
-- deciding at a vendor is whether a thing is worth what he is asking, and both
-- halves of that have to be on the screen at once.
--
-- **Two columns of them, which is the client's own shape.** Blizzard's merchant
-- frame is two columns of exactly this card, ten to a page, and the reason it
-- reads well at a glance is the reason it is copied here. What is not copied is
-- the paging: the columns run down one scrolling list, so a quartermaster with
-- sixty things is three flicks of a wheel rather than six presses of an arrow,
-- and the piles keep their headings the whole way down.
--
-- **The square is the bag window's square, and it is one file.** UI/Slot.lua
-- draws it for both, because a vendor's rack and your bags are open beside each
-- other and two squares that differ by a pixel of inset or a shade of grey is
-- worse than either. The count in its corner is how many one press buys, which
-- is the same corner a bag square keeps its stack size in and means the same
-- thing from the other side.
--
-- **One pool draws both racks.** The window has two: what the vendor sells and
-- what you sold him. A card is the same card on either, so which rack is being
-- drawn arrives as the thing that answers questions about an entry rather than
-- as a flag. Stock.lua and Buyback.lua both answer InStock, Left, Afford,
-- Batches and Buy, this file calls those five on whichever it was handed, and
-- the tab swaps it. A second pool would be a second copy of the layout below,
-- kept in step by hand.
--
-- **A press buys one of the vendor's own batches and shift picks a number.**
-- Both of those are the client's gestures and neither was here: a plain press
-- bought a single item off a rack that sells water five at a time, which is a
-- fifth of what the square said it would buy, and there was no way at all to
-- ask for four stacks. The number picker is UI/Amount.lua, which is a window of
-- its own rather than a control on sixty cards.
--
-- **Nothing here is a secure button and nothing needs to be.** A bag square
-- inherits the client's own template because a right click on one means eat,
-- equip, open, sell or attach depending on what is in front of you, and the
-- rules for which are inside the client. Buying is one call with one meaning,
-- so the card is an ordinary button and the right button goes to the camera
-- like everything else in the addon that is not a bag slot.
--------------------------------------------------------------------------

local SLOT, GAP, BREAK = UI.SLOT, UI.SLOT_GAP, UI.SLOT_BREAK

-- One card is a square tall, so a line of them is a line of bag squares and the
-- two windows keep their rhythm open beside each other.
local ROW = UI.SLOT

-- How wide a card wants to be.
--
-- The square, the air after it, room for the longest item name anybody sells
-- without cutting it short, and room for a price with all three coins in it.
-- Under this the names start ending in nothing and the window stops being the
-- thing it was widened to be; over it the second column costs more screen than
-- it is worth. Window.lua sizes the window off this, so the number lives here,
-- beside the layout it decides.
local CARD = 236

-- How many tokens one card will draw before it stops. Three is every extended
-- cost in the game this addon has seen and one more than the badge vendors
-- need; a fourth would be drawn over the price.
local CHIPS = 3

-- The token chip, and the air between two of them. Smaller than the item's own
-- square because it is a price rather than a thing: what you are reading is the
-- number on it.
local CHIP, CHIP_GAP = 14, 3

local cards = {}
local canvas, headings

-- Which rack the cards are drawing. Set by every pass and read by a click, so a
-- press lands on the rack the card was painted from rather than on whichever
-- one the window happens to be showing when the mouse comes down.
local source

--------------------------------------------------------------------------
-- What the box says
--------------------------------------------------------------------------

-- The price, in the loss colour when the purse cannot meet it.
--
-- In the box as well as on the card, because the box is where the whole of an
-- offer is written out and a reader who opened it should not have to look back
-- behind it for the one number they came for.
local function Money(lines, entry)
	if (entry.price or 0) <= 0 then
		return lines
	end
	lines[#lines + 1] = { "Price", ns.Coined(entry.price),
		tone = (entry.price <= GetMoney()) and C.text or C.loss }
	return lines
end

-- Every token this costs, and how many of it you are carrying.
--
-- Both numbers, because the one you cannot work out by looking at anything else
-- on the screen is how many badges you have. The colour says whether you have
-- enough, and the pair says how far off you are.
local function Tokens(lines, entry)
	for which = 1, (entry.wants or 0) do
		local cost = entry.costs[which]
		local short = (cost.held or 0) < (cost.count or 0)
		lines[#lines + 1] = { cost.name or "Tokens",
			("%d of %d"):format(cost.held or 0, cost.count or 1),
			tone = short and C.loss or C.text }
	end
	return lines
end

-- The facts about the sale rather than about the item: what one press buys, how
-- many the vendor has left, and how many you may ask for at once. All three are
-- left out where they have no answer, which on the last one is most of a rack.
--
-- The shift line is the only sentence in this addon that says what to press,
-- and it earns the exception by being conditional. It is on an entry where more
-- than one batch can be bought and nowhere else, so it is a fact about that
-- offer rather than a footnote under every hover in the window.
local function Sale(lines, entry, rack)
	if (entry.quantity or 1) > 1 then
		lines[#lines + 1] = { "One press buys", tostring(entry.quantity) }
	end
	local left = rack.Left(entry)
	if left then
		lines[#lines + 1] = { "Left", tostring(left),
			tone = left > 0 and C.text or C.loss }
	end
	local batches = rack.Batches(entry)
	if batches > 1 then
		lines[#lines + 1] = { "Shift-click",
			("up to %d"):format(batches * (entry.quantity or 1)) }
	end
	if not entry.usable then
		lines[#lines + 1] = { "Your class cannot use this", color = C.quiet }
	end
	return lines
end

-- What the box over a card says: the client's own lines for the item, and under
-- them everything about this vendor's offer that the item itself does not know.
-- Nothing at all for a card nothing is lying on, which is a card the pool has
-- not trimmed yet rather than a gap in the rack.
local function Subject(card)
	local entry, rack = card.entry, card.source
	if not entry then
		return nil
	end
	local lines = Sale(Tokens(Money({}, entry), entry), entry, rack)
	return {
		-- An item the client has not cached yet has a name, a picture and a
		-- price and no link to read a tooltip out of. It gets the addon's own
		-- lines under its own name rather than no box at all, because a rack
		-- you cannot hover for a minute after you open it is the rack of every
		-- vendor you have not visited before.
		kind = entry.link and "item" or "note",
		link = entry.link,
		title = entry.name,
		count = entry.quantity,
		lines = lines,
	}
end

--------------------------------------------------------------------------
-- Building one
--------------------------------------------------------------------------

-- One token chip: a picture and how many of it this costs, with what you are
-- carrying deciding the colour of the number.
local function Chip(card, index)
	local chip = CreateFrame("Frame", nil, card)
	chip:SetSize(CHIP, CHIP)
	chip.art = UI.Icon(chip, "ARTWORK")
	chip.art:SetAllPoints()
	chip.count = UI.Label(chip, M.small, C.text, "LEFT", UI.FLAT)
	chip.count:SetPoint("LEFT", chip, "RIGHT", 1, 0)
	UI.Wrap(chip.count, false)
	card.chips[index] = chip
	return chip
end

local function Enter(card)
	UI.Tint(card.bg, C.hover)
	ns.Tip.Open(card, Subject(card), nil, UI.Tooltip.BESIDE)
end

local function Leave(card)
	UI.Tint(card.bg, C.rail)
	ns.Tip.Close()
end

-- Whether the player is asking for a number rather than for one batch.
--
-- Asked at the moment of the press rather than tracked, because the client
-- already knows and the answer is only ever wanted here. Guarded for the call's
-- existence the way Buttons/Placing.lua guards the same one.
local function Picking()
	return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false
end

-- The line under the number in the picker: what that many batches comes to, in
-- things and in money.
--
-- Plain money in the loss colour where the purse cannot meet it, and the
-- painted three-colour version where it can. A colour cannot be laid over text
-- that carries its own, so the two cases use the two spellings Core offers
-- rather than one spelling and a tone that does nothing.
local function Worth(entry, batches)
	local items = batches * math.max(entry.quantity or 1, 1)
	local price = (entry.price or 0) * batches
	if price <= 0 then
		return ("%d of them"):format(items)
	end
	if price > GetMoney() then
		return ("%d of them for %s, which is more than your purse")
			:format(items, ns.Coin(price)), C.loss
	end
	return ("%d of them for %s"):format(items, ns.Coined(price))
end

-- The number picker, opened on the entry under the cursor.
local function Pick(rack, entry)
	UI.Amount({
		title = "How many",
		name = entry.name,
		icon = entry.icon,
		quality = entry.quality,
		each = entry.quantity,
		low = 1,
		high = rack.Batches(entry),
		value = 1,
		accept = "buy",
		note = function(batches) return Worth(entry, batches) end,
		onAccept = function(batches)
			local going, why = rack.Buy(entry, batches)
			if not going then
				ns.Print(why .. ".")
			end
		end,
	})
end

local function Click(card)
	local rack = card.source or ns.Stock
	local entry = card.entry
	if not entry then
		return
	end
	if Picking() and rack.InStock(entry) and rack.Batches(entry) > 1 then
		return Pick(rack, entry)
	end
	local going, why = rack.Buy(entry)
	if not going then
		ns.Print(why .. ".")
	end
end

-- One card. Named, because a card that has landed somewhere wrong has to be
-- findable from a macro, and because the bag squares beside it are named for
-- the same reason.
local function Build(index)
	local card = CreateFrame("Button", "WarriorKitMerchantSlot" .. index, canvas)
	card:SetHeight(ROW)
	card.chips = {}

	card.bg = ns.Fill(card, "BACKGROUND", C.rail[1], C.rail[2], C.rail[3], 1)
	card.bg:SetAllPoints()

	-- A plain frame rather than a button, because the card is what takes the
	-- press. UI/Slot.lua's own header names this as the case it guards for.
	card.square = UI.Slot(card, SLOT)
	card.square:SetPoint("LEFT")

	card.label = UI.Label(card, M.font, C.text, "LEFT", UI.FLAT)
	card.label:SetPoint("TOPLEFT", card.square, "TOPRIGHT", M.gutter, -1)
	UI.Wrap(card.label, false)

	card.price = UI.Label(card, M.small, C.text, "LEFT", UI.FLAT)
	card.price:SetPoint("BOTTOMLEFT", card.square, "BOTTOMRIGHT", M.gutter, 2)
	UI.Wrap(card.price, false)

	-- What is left of a limited supply, at the right of the price line. Its own
	-- string rather than a mark on the square, because it is a fact about the
	-- vendor and the square is where facts about the item go.
	card.note = UI.Label(card, M.small, C.dim, "RIGHT", UI.FLAT)
	card.note:SetPoint("BOTTOMRIGHT", -M.rowGap, 2)
	UI.Wrap(card.note, false)

	for chip = 1, CHIPS do
		Chip(card, chip)
	end

	card:SetScript("OnEnter", Enter)
	card:SetScript("OnLeave", Leave)
	card:SetScript("OnClick", Click)
	-- The right button turns the camera and there is nothing on this card it
	-- could mean instead. A bag square is the one place in the addon that keeps
	-- it, because a right click there is the whole of eat, equip, open and sell.
	UI.PassCamera(card)
	-- After the pass-through and not before, and it is not belt and braces.
	-- Handing two buttons to the camera is a write to which buttons this frame
	-- answers at all, so the one it still wants has to be asked for again
	-- afterwards or the card is a button you can press and nothing happens.
	card:RegisterForClicks("LeftButtonUp")

	-- On the way down, in the addon's own black. A card that does not move under
	-- the mouse reads as a card that did not take the click, and the click here
	-- spends money.
	card:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
	local pushed = ns.Measure(card, "GetPushedTexture")
	if pushed then
		pushed:SetColorTexture(0, 0, 0, 0.36)
	end
	return card
end

local function Card(index)
	local card = cards[index]
	if not card then
		card = Build(index)
		cards[index] = card
	end
	return card
end

--------------------------------------------------------------------------
-- Filling one in
--------------------------------------------------------------------------

-- The name, in the item's own grade, unless your class cannot use it.
--
-- Quiet rather than a red of its own. The client draws an unusable merchant
-- item in red and this palette has no red that means that: the one it has is
-- for a number that went the wrong way. Quiet is the dimmest thing on the
-- window and it says the same thing without inventing a colour.
local function Ink(entry)
	if not entry.usable then
		return C.quiet
	end
	return UI.SlotInk(entry.quality)
end

-- Every token this card costs, left to right from wherever the money ends.
local function Chips(card, entry)
	local anchor, side = card.price, "RIGHT"
	local drawn = math.min(entry.wants or 0, CHIPS)
	for index = 1, CHIPS do
		local chip = card.chips[index]
		if index > drawn then
			chip:Hide()
		else
			local cost = entry.costs[index]
			chip.art:SetTexture(cost.icon)
			chip.count:SetText(tostring(cost.count or 1))
			-- The number in the loss colour when you have not got that many. It
			-- is the one fact on the card you cannot work out by looking at your
			-- purse.
			local short = (cost.held or 0) < (cost.count or 0)
			local ink = short and C.loss or C.text
			chip.count:SetTextColor(ink[1], ink[2], ink[3])
			chip:ClearAllPoints()
			chip:SetPoint("LEFT", anchor, side, CHIP_GAP, 0)
			chip:Show()
			anchor, side = chip.count, "RIGHT"
		end
	end
end

local function Paint(card, entry, rack)
	-- Dim for the two things that stop a press: none left, and more than you are
	-- carrying. Both are facts about this minute rather than about the item,
	-- which is the same statement the bag window makes when it dims what a
	-- vendor will not take, in the same shade.
	local refused = not rack.InStock(entry) or not rack.Afford(entry)

	card.entry, card.name, card.source = entry, entry.name, rack
	-- The count in the corner is how many one press buys rather than how many
	-- are in a stack, which is the same corner a bag square keeps its stack size
	-- in and means the same thing from the other side: a vendor selling arrows
	-- two hundred at a time draws 200 there, and that is what you get.
	UI.SlotPaint(card.square, entry.icon, entry.quantity, entry.quality, refused)

	card.label:SetText(entry.name or "")
	local ink = Ink(entry)
	card.label:SetTextColor(ink[1], ink[2], ink[3])

	card.price:SetText((entry.price or 0) > 0 and ns.Coined(entry.price) or "")
	Chips(card, entry)

	local left = rack.Left(entry)
	card.note:SetText(left and ("%d left"):format(left) or "")
	local tone = (left and left <= 0) and C.loss or C.dim
	card.note:SetTextColor(tone[1], tone[2], tone[3])

	card:SetAlpha(refused and UI.SLOT_DIM or 1)
end

-- One anchor and an explicit width rather than two anchors.
--
-- A card pinned to both edges of a column is the same rectangle and it is a
-- rectangle with no width of its own, which is a frame nothing can measure
-- until the client has laid it out. The name is cut to the card's width and the
-- count of what is left is placed against its right edge, so the width has to be
-- a number this file knows rather than one it finds out afterwards.
local function Place(card, top, column, line, width)
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", canvas, "TOPLEFT",
		column * (width + GAP), -(top + line * (ROW + GAP)))
	card:SetWidth(width)
	-- Cut to what is left of the card after the square, the air and the room
	-- the count of a limited supply needs. Set per pass because the width
	-- follows the window.
	card.label:SetWidth(width - SLOT - M.gutter - M.rowGap)
end

-- The heading over a pile, and nothing at all where a pile has no name. The
-- buyback rack is the one that has not: it is a single pile in the order you
-- sold things, and a heading over it would say what the tab above it says.
--
-- The caption index is a count of the named piles rather than the pile's own
-- number, so a nameless pile spends no caption and the trim below hides exactly
-- the ones this pass did not write.
local function Name(named, text, top)
	if not text or text == "" then
		return named, top
	end
	return named + 1, headings:Name(named + 1, text, top)
end

-- Everything the pool made and this pass did not use.
local function Trim(used, captions)
	for index = used + 1, #cards do
		cards[index]:Hide()
	end
	headings:Trim(captions)
end

-- How many cards fit across a rack this wide, and how wide each of them comes
-- out. At least one, because a window narrower than a card still has to draw
-- one rather than none.
local function Columns(width)
	local columns = math.max(math.floor((width + GAP) / (CARD + GAP)), 1)
	return columns, math.floor((width - (columns - 1) * GAP) / columns)
end

--------------------------------------------------------------------------

-- Where the rack is drawn. Called once, before any card exists, because a card
-- is parented to this frame when it is made.
function Grid.Attach(where)
	canvas = where
	headings = UI.Headings(canvas)
	return canvas
end

-- Every pile laid out, and how tall the result is. The height is handed back
-- rather than written anywhere, because the thing that has to know is the
-- scroll view and the scroll view belongs to the window.
--
-- The width comes in and the columns are worked out from it, rather than the
-- other way round. The window is a rectangle whose size is its own business;
-- how many cards that holds is this file's, because this file is the one that
-- knows how wide a card has to be to say what it says.
function Grid.Paint(state, width, rack)
	local at, top, named = 0, 0, 0
	local columns, span = Columns(width)
	source = rack or ns.Stock
	for index = 1, state.shown do
		local entries = state.groups[index].entries
		named, top = Name(named, state.groups[index].name, top)
		for held = 1, #entries do
			at = at + 1
			local card = Card(at)
			Paint(card, entries[held], source)
			Place(card, top, (held - 1) % columns, math.floor((held - 1) / columns), span)
			card:Show()
		end
		local lines = math.ceil(#entries / columns)
		top = top + lines * ROW + (lines - 1) * GAP + BREAK
	end
	Trim(at, named)
	return math.max(top - BREAK, 1)
end

-- How wide a rack of this many columns is, which is the number Window.lua sizes
-- itself off. Here rather than there because the card's width is here.
function Grid.Span(columns)
	return columns * CARD + (columns - 1) * GAP
end

-- The pool, for the harness. It reads the cards to say that what a card shows
-- and what a press on it buys are the same entry, which is the one claim about
-- this file that cannot be made from the outside.
function Grid.Cards()
	return cards
end

function Grid.Headers()
	return headings:All()
end

function Grid.Describe()
	if #cards == 0 then
		return "no cards drawn yet"
	end
	return ("%d cards, the bag window's square with the name and the price beside it")
		:format(#cards)
end
