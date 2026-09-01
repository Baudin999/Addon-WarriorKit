local ADDON, ns = ...

local UI = ns.UI
local C = UI.Color

local Grid = {}
ns.MerchantGrid = Grid

--------------------------------------------------------------------------
-- The rack
--
-- One square per thing the vendor sells, drawn where the pile it belongs to
-- puts it. The pool never shrinks and a square is reassigned to whatever the
-- scan put on it this pass, which is the same trick Bags/Grid.lua plays and for
-- the same reason: a merchant update arrives in bursts and every one of them is
-- answered by laying the whole rack out again.
--
-- **It is the bag window's grid, and that is the point.** This was a list of
-- rows, one line each, with the name and the price written out, and it was the
-- wrong shape for the thing it was drawing. A quartermaster with sixty items is
-- sixty lines, which is four screens of scrolling to find out what he has, and
-- you scroll it while the bag window beside it shows a hundred and fifty slots
-- at once without moving. Eight columns of squares put the same sixty items in
-- eight lines. What you are doing at a vendor is looking for a thing, and a
-- picture is how you find one; the price is what you read once you have.
--
-- **So the price is in the box and not on the square.** There is nowhere on a
-- thirty one pixel square to write a price anybody could read, and a window
-- that shrinks the price until it fits has kept the number and lost the reason
-- for it. UI/Tip.lua already opens on the square: the price goes in it, with
-- the tokens under it, what a single press buys, and how many the vendor has
-- left. One hover, everything about that entry.
--
-- **What stays on the square is what you read without pointing at anything.**
-- The picture, the grade on the rim, how many one press buys in the corner, and
-- the dim on everything you cannot buy this minute. That last one is the whole
-- argument for a grid over a list: out of stock and cannot afford are facts
-- about the rack you take in at a glance, and a glance is what a grid is for.
--
-- **The square is the bag window's square, and it is one file.** UI/Slot.lua
-- draws it for both, because a vendor's rack and your bags are open beside each
-- other and two squares that differ by a pixel of inset or a shade of grey is
-- worse than either. The two windows are the same columns wide for the same
-- reason.
--
-- **One pool draws both racks.** The window has two: what the vendor sells and
-- what you sold him. A square is the same square on either, so which rack is
-- being drawn arrives as the thing that answers questions about an entry rather
-- than as a flag. Stock.lua and Buyback.lua both answer InStock, Left, Afford
-- and Buy, this file calls those four on whichever it was handed, and the tab
-- swaps it. A second pool would be a second copy of the layout below, kept in
-- step by hand.
--
-- **Nothing here is a secure button and nothing needs to be.** A bag square
-- inherits the client's own template because a right click on one means eat,
-- equip, open, sell or attach depending on what is in front of you, and the
-- rules for which are inside the client. Buying is one call with one meaning,
-- so the square is an ordinary button, the click is BuyMerchantItem, and the
-- right button goes to the camera like everything else in the addon that is not
-- a bag slot.
--------------------------------------------------------------------------

local SLOT, GAP, BREAK = UI.SLOT, UI.SLOT_GAP, UI.SLOT_BREAK

local squares = {}
local canvas, headings

-- Which rack the squares are drawing. Set by every pass and read by a click, so
-- a press lands on the rack the square was painted from rather than on
-- whichever one the window happens to be showing when the mouse comes down.
local source

--------------------------------------------------------------------------
-- What the box says
--------------------------------------------------------------------------

-- The price, in the loss colour when the purse cannot meet it.
--
-- Drawn for nought as well as for a number, because nought is a real price on
-- this rack: a badge vendor's helm costs no money and forty tokens, and a box
-- that says nothing at all about money there reads as a box that did not know.
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

-- The two facts about the sale rather than about the item: what one press buys,
-- and how many the vendor has left. Both are left out where they have no answer,
-- which is most of the rack.
local function Sale(lines, entry, rack)
	if (entry.quantity or 1) > 1 then
		lines[#lines + 1] = { "One press buys", tostring(entry.quantity) }
	end
	local left = rack.Left(entry)
	if left then
		lines[#lines + 1] = { "Left", tostring(left),
			tone = left > 0 and C.text or C.loss }
	end
	if not entry.usable then
		lines[#lines + 1] = { "Your class cannot use this", color = C.quiet }
	end
	return lines
end

-- What the box over a square says: the client's own lines for the item, and
-- under them everything about this vendor's offer that the item itself does not
-- know. Nothing at all for a square nothing is lying on, which is a square the
-- pool has not trimmed yet rather than a gap in the rack.
local function Subject(square)
	local entry, rack = square.entry, square.source
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

local function Enter(square)
	UI.Tint(square.bg, C.control)
	ns.Tip.Open(square, Subject(square), nil, UI.Tooltip.BESIDE)
end

local function Leave(square)
	UI.Tint(square.bg, C.sunken)
	ns.Tip.Close()
end

local function Click(square)
	local going, why = (square.source or ns.Stock).Buy(square.entry)
	if not going then
		ns.Print(why .. ".")
	end
end

-- One square. Named, because a square that has landed somewhere wrong has to be
-- findable from a macro, and because the bag squares beside it are named for the
-- same reason.
local function Build(index)
	local square = CreateFrame("Button", "WarriorKitMerchantSlot" .. index, canvas)
	square:SetSize(SLOT, SLOT)
	UI.Dress(square, SLOT)

	square:SetScript("OnEnter", Enter)
	square:SetScript("OnLeave", Leave)
	square:SetScript("OnClick", Click)
	-- The right button turns the camera and there is nothing on this square it
	-- could mean instead. A bag square is the one place in the addon that keeps
	-- it, because a right click there is the whole of eat, equip, open and sell.
	UI.PassCamera(square)
	-- After the pass-through and not before, and it is not belt and braces.
	-- Handing two buttons to the camera is a write to which buttons this frame
	-- answers at all, so the one it still wants has to be asked for again
	-- afterwards or the square is a button you can press and nothing happens.
	square:RegisterForClicks("LeftButtonUp")
	return square
end

local function Square(index)
	local square = squares[index]
	if not square then
		square = Build(index)
		squares[index] = square
	end
	return square
end

--------------------------------------------------------------------------
-- Filling one in
--------------------------------------------------------------------------

local function Paint(square, entry, rack)
	-- Dim for the two things that stop a press: none left, and more than you are
	-- carrying. Both are facts about this minute rather than about the item,
	-- which is the same statement the bag window makes when it dims what a
	-- vendor will not take, in the same shade.
	local refused = not rack.InStock(entry) or not rack.Afford(entry)

	square.entry, square.name, square.source = entry, entry.name, rack
	-- The count in the corner is how many one press buys rather than how many
	-- are in a stack, which is the same corner a bag square keeps its stack size
	-- in and means the same thing from the other side: a vendor selling arrows
	-- two hundred at a time draws 200 there, and that is what you get.
	UI.SlotPaint(square, entry.icon, entry.quantity, entry.quality, refused)
	square:SetAlpha(refused and UI.SLOT_DIM or 1)
end

local function Place(square, top, column, line)
	square:ClearAllPoints()
	square:SetPoint("TOPLEFT", canvas, "TOPLEFT",
		column * (SLOT + GAP), -(top + line * (SLOT + GAP)))
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
	for index = used + 1, #squares do
		squares[index]:Hide()
	end
	headings:Trim(captions)
end

--------------------------------------------------------------------------

-- Where the rack is drawn. Called once, before any square exists, because a
-- square is parented to this frame when it is made.
function Grid.Attach(where)
	canvas = where
	headings = UI.Headings(canvas)
	return canvas
end

-- Every pile laid out, and how tall the result is. The height is handed back
-- rather than written anywhere, because the thing that has to know is the
-- scroll view and the scroll view belongs to the window.
function Grid.Paint(state, columns, rack)
	local at, top, named = 0, 0, 0
	source = rack or ns.Stock
	for index = 1, state.shown do
		local entries = state.groups[index].entries
		named, top = Name(named, state.groups[index].name, top)
		for held = 1, #entries do
			at = at + 1
			local square = Square(at)
			Paint(square, entries[held], source)
			Place(square, top, (held - 1) % columns, math.floor((held - 1) / columns))
			square:Show()
		end
		local lines = math.ceil(#entries / columns)
		top = top + lines * SLOT + (lines - 1) * GAP + BREAK
	end
	Trim(at, named)
	return math.max(top - BREAK, 1)
end

-- The pool, for the harness. It reads the squares to say that what a square
-- shows and what a press on it buys are the same entry, which is the one claim
-- about this file that cannot be made from the outside.
function Grid.Squares()
	return squares
end

function Grid.Headers()
	return headings:All()
end

function Grid.Describe()
	if #squares == 0 then
		return "no squares drawn yet"
	end
	return ("%d squares, the bag window's square with the price in the box")
		:format(#squares)
end
