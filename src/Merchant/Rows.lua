local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

local Rows = {}
ns.MerchantRows = Rows

--------------------------------------------------------------------------
-- The rack
--
-- One row per thing the vendor sells, drawn where the pile it belongs to puts
-- it. The pool never shrinks and a row is reassigned to whatever the scan put
-- on it this pass, which is the same trick Bags/Grid.lua plays with its squares
-- and for the same reason: a merchant update arrives in bursts and every one of
-- them is answered by laying the whole rack out again.
--
-- **A row and not a square, and the price is the whole argument.** The bag
-- window is a grid because a bag is a grid: a hundred and fifty slots you scan
-- by picture, where the only number that matters is how many are in the stack.
-- A vendor is a list of prices. A grid of squares hides the one fact you are
-- standing there to read, and putting a price under a thirty one pixel square
-- is a price nobody can read either. So the square stays, at exactly the size
-- the bag window draws it, and a line of text runs off the side of it.
--
-- **The square is the bag window's square, and it is one file.** UI/Slot.lua
-- draws it for both, because a vendor's rack and your bags are open beside each
-- other and two squares that differ by a pixel of inset or a shade of grey is
-- worse than either. What is left here is the row around it.
--
-- **Nothing here is a secure button and nothing needs to be.** A bag square
-- inherits the client's own template because a right click on one means eat,
-- equip, open, sell or attach depending on what is in front of you, and the
-- rules for which are inside the client. Buying is one call with one meaning,
-- so the row is an ordinary button and the click is BuyMerchantItem. That is
-- the whole difference between the two files' buttons.
--------------------------------------------------------------------------

-- One row, and the gap to the next. A row is a square tall and the gap is the
-- gap between two squares, so the two windows line up when they are open beside
-- each other. Both are UI/Slot.lua's numbers, which is what makes that true
-- rather than a coincidence somebody has to keep checking.
local ROW, GAP = UI.SLOT, UI.SLOT_GAP
local HEADER, BREAK = UI.SLOT_HEADER, UI.SLOT_BREAK

-- How many tokens one row will draw before it stops. Three is every extended
-- cost in the game that this addon has seen and one more than the badge
-- vendors need; a fourth would be drawn over the item's name.
local CHIPS = 3

-- The token chip, and the air between two of them. Smaller than the item's own
-- square because it is a price rather than a thing: what you are reading is the
-- number beside it.
local CHIP, CHIP_GAP = 14, 3

local rows, headers = {}, {}
local canvas

--------------------------------------------------------------------------
-- Building one
--------------------------------------------------------------------------

-- The square at the left of a row.
--
-- A plain frame rather than a button, because the row is what takes the press.
-- The count in its corner is how many one press buys rather than how many are
-- in a stack, which is the same corner a bag square keeps its stack size in and
-- means the same thing from the other side: a vendor selling arrows two hundred
-- at a time draws 200 there, and that is what you get.
local function Square(row)
	local square = UI.Slot(row, ROW)
	square:SetPoint("LEFT")
	return square
end

-- One token chip: a picture and how many of it this costs, with what you are
-- carrying deciding the colour of the number.
local function Chip(row, index)
	local chip = CreateFrame("Frame", nil, row)
	chip:SetSize(CHIP, CHIP)
	chip.art = UI.Icon(chip, "ARTWORK")
	chip.art:SetAllPoints()
	chip.count = UI.Label(chip, M.small, C.text, "RIGHT", UI.FLAT)
	chip.count:SetPoint("BOTTOMRIGHT", 1, -1)
	UI.Wrap(chip.count, false)
	row.chips[index] = chip
	return chip
end

local function Enter(row)
	UI.Tint(row.bg, C.hover)
	if row.link then
		ns.Tip.Open(row, { kind = "item", link = row.link, title = row.name },
			nil, UI.Tooltip.BESIDE)
	end
end

local function Leave(row)
	UI.Tint(row.bg, C.rail)
	ns.Tip.Close()
end

local function Click(row)
	local going, why = ns.Stock.Buy(row.entry)
	if not going then
		ns.Print(why .. ".")
	end
end

local function Build(index)
	local row = CreateFrame("Button", "WarriorKitMerchantRow" .. index, canvas)
	row:SetHeight(ROW)
	row.chips = {}

	row.bg = ns.Fill(row, "BACKGROUND", C.rail[1], C.rail[2], C.rail[3], 1)
	row.bg:SetAllPoints()

	row.square = Square(row)

	row.label = UI.Label(row, M.font, C.text, "LEFT", UI.FLAT)
	UI.Wrap(row.label, false)

	-- What is left of a limited supply, under the name. Its own line rather than
	-- a mark on the square, because it is a fact about the vendor and the square
	-- is where facts about the item go.
	row.note = UI.Label(row, M.small, C.dim, "LEFT", UI.FLAT)
	UI.Wrap(row.note, false)

	row.price = UI.Label(row, M.font, C.text, "RIGHT", UI.FLAT)
	row.price:SetPoint("RIGHT", -M.gutter, 0)
	UI.Wrap(row.price, false)

	for chip = 1, CHIPS do
		Chip(row, chip)
	end

	row:SetScript("OnEnter", Enter)
	row:SetScript("OnLeave", Leave)
	row:SetScript("OnClick", Click)
	-- The right button turns the camera and there is nothing on this row it
	-- could mean instead. A bag square is the one place in the addon that keeps
	-- it, because a right click there is the whole of eat, equip, open and sell.
	UI.PassCamera(row)
	-- After the pass-through and not before, and it is not belt and braces.
	-- Handing two buttons to the camera is a write to which buttons this frame
	-- answers at all, so the one it still wants has to be asked for again
	-- afterwards or the row is a button you can press and nothing happens.
	row:RegisterForClicks("LeftButtonUp")

	-- On the way down, in the addon's own black. A row that does not move under
	-- the mouse reads as a row that did not take the click, and the click here
	-- spends money.
	row:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
	local pushed = ns.Measure(row, "GetPushedTexture")
	if pushed then
		pushed:SetColorTexture(0, 0, 0, 0.36)
	end
	return row
end

local function Row(index)
	local row = rows[index]
	if not row then
		row = Build(index)
		rows[index] = row
	end
	return row
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

-- Every token this row costs, right to left from wherever the money ends.
-- Returns the leftmost edge anything on the right of the row reached, which is
-- where the name has to stop.
local function Chips(row, entry)
	local anchor, side = row.price, "LEFT"
	local drawn = math.min(entry.wants or 0, CHIPS)
	for index = 1, CHIPS do
		local chip = row.chips[index]
		if index > drawn then
			chip:Hide()
		else
			local cost = entry.costs[index]
			chip.art:SetTexture(cost.icon)
			chip.count:SetText(tostring(cost.count or 1))
			-- The number in the loss colour when you have not got that many.
			-- It is the one fact on the row you cannot work out by looking at
			-- your purse.
			local short = (cost.held or 0) < (cost.count or 0)
			local ink = short and C.loss or C.text
			chip.count:SetTextColor(ink[1], ink[2], ink[3])
			chip:ClearAllPoints()
			chip:SetPoint("RIGHT", anchor, side, -CHIP_GAP, 0)
			chip:Show()
			anchor, side = chip, "LEFT"
		end
	end
	return anchor
end

local function Paint(row, entry)
	-- Dim for the two things that stop a press: none left, and more than you are
	-- carrying. Both are facts about this minute rather than about the item,
	-- which is the same statement the bag window makes when it dims what a
	-- vendor will not take, in the same shade.
	local refused = not ns.Stock.InStock(entry) or not ns.Stock.Afford(entry)

	row.entry, row.link, row.name = entry, entry.link, entry.name
	UI.SlotPaint(row.square, entry.icon, entry.quantity, entry.quality, refused)

	row.label:SetText(entry.name or "")
	local ink = Ink(entry)
	row.label:SetTextColor(ink[1], ink[2], ink[3])

	local left = ns.Stock.Left(entry)
	row.note:SetText(left and ("%d left"):format(left) or "")
	row.note:SetShown(left ~= nil)

	row.price:SetText((entry.price or 0) > 0 and ns.Coined(entry.price) or "")
	local edge = Chips(row, entry)

	-- The name runs from the square to whatever the price and the tokens left
	-- of it, re-anchored every pass because both of those change width as you
	-- spend. One line and centred when there is nothing under it, two lines
	-- when the vendor is counting down.
	row.label:ClearAllPoints()
	row.note:ClearAllPoints()
	if left then
		row.label:SetPoint("TOPLEFT", row.square, "TOPRIGHT", M.gutter, -2)
		row.note:SetPoint("BOTTOMLEFT", row.square, "BOTTOMRIGHT", M.gutter, 3)
		row.note:SetPoint("RIGHT", edge, "LEFT", -M.gutter, 0)
	else
		row.label:SetPoint("LEFT", row.square, "RIGHT", M.gutter, 0)
	end
	row.label:SetPoint("RIGHT", edge, "LEFT", -M.gutter, 0)

	row:SetAlpha(refused and UI.SLOT_DIM or 1)
end

-- One anchor and an explicit width rather than two anchors.
--
-- A row pinned to both edges of the canvas is the same rectangle and it is a
-- rectangle with no width of its own, which is a frame nothing can measure
-- until the client has laid it out. Everything on this row is placed against
-- its right edge, so the width has to be a number this file knows rather than
-- one it finds out afterwards.
local function Place(row, top, width)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -top)
	row:SetWidth(width)
end

local function Name(index, text, top)
	local label = headers[index]
	if not label then
		label = UI.Label(canvas, M.heading, C.heading, "LEFT", UI.FLAT)
		UI.Wrap(label, false)
		headers[index] = label
	end
	label:ClearAllPoints()
	label:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -top)
	label:SetText(text)
	label:Show()
	return top + HEADER
end

-- Everything the pool made and this pass did not use.
local function Trim(rowsUsed, headersUsed)
	for index = rowsUsed + 1, #rows do
		rows[index]:Hide()
	end
	for index = headersUsed + 1, #headers do
		headers[index]:Hide()
	end
end

--------------------------------------------------------------------------

-- Where the rack is drawn. Called once, before any row exists, because a row is
-- parented to this frame when it is made.
function Rows.Attach(where)
	canvas = where
	return canvas
end

-- Every pile laid out, and how tall the result is. The height is handed back
-- rather than written anywhere, because the thing that has to know is the
-- scroll view and the scroll view belongs to the window.
function Rows.Paint(state, width)
	local at, top = 0, 0
	for index = 1, state.shown do
		local group = state.groups[index]
		local entries = group.entries
		top = Name(index, group.name, top)
		for held = 1, #entries do
			at = at + 1
			local row = Row(at)
			Paint(row, entries[held])
			Place(row, top, width)
			row:Show()
			top = top + ROW + GAP
		end
		top = top - GAP + BREAK
	end
	Trim(at, state.shown)
	return math.max(top - BREAK, 1)
end

-- The pool, for the harness. It reads the rows to say that what a row says and
-- what a press on it buys are the same entry, which is the one claim about this
-- file that cannot be made from the outside.
function Rows.Rows()
	return rows
end

function Rows.Headers()
	return headers
end

function Rows.Describe()
	if #rows == 0 then
		return "no rows drawn yet"
	end
	return ("%d rows, %d pixels tall, a square and a price on each")
		:format(#rows, ROW)
end
