local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

local Grid = {}
ns.BagsGrid = Grid

--------------------------------------------------------------------------
-- The squares
--
-- One button per bag slot, drawn where the pile it belongs to puts it. The
-- pool never shrinks and a square is reassigned to whatever slot lands on it
-- this pass, which is what lets a hundred and fifty of them be laid out again
-- for the price of a hundred and fifty anchors.
--
-- **What a square looks like is UI/Slot.lua's.** The sunken ground, the
-- hairline in the item's own grade, the crisp icon and the count in the corner
-- are the same in the merchant window, and one of them differing by a pixel
-- when the two are open beside each other is why that file exists. What is left
-- here is everything that is a fact about a bag slot and about nothing else.
--
-- **The button is the client's own template and that is the whole design.**
-- `ContainerFrameItemButtonTemplate` is what every bag button in the game is
-- built on, Blizzard's and every addon's, and inheriting it means the click, the
-- drag, the stack split, the shift-link and the merchant sale are the client's
-- code rather than ours. None of that is reimplementable: a right click on a
-- bag slot means eat, equip, open, sell or attach depending on which window is
-- in front of you, and the rules for which are inside the client. That is the
-- one thing the merchant window's rows do not do and do not want: buying is one
-- call with one meaning.
--
-- It also keeps a seam this addon already depends on. Mail/Bags.lua takes over
-- `ContainerFrameItemButton_OnClick` while the mail window is open so a right
-- click attaches a stack to the letter, and it works by name at click time
-- rather than by frame, so a square built on this template arrives there with
-- no change to that file at all.
--
-- **A slot is its own id and its bag is its parent's.** That is where the
-- client keeps it and the only thing the template's own handlers have to go on,
-- so every square is parented to a holder frame carrying the bag number. The
-- holders are all the size of the canvas, so a square is anchored inside its
-- own parent and the layout never has to know which holder it landed in.
--
-- **The art is ours and the behaviour is theirs.** The template arrives dressed
-- for a window that looks nothing like this one, so UI.Undress sweeps every
-- region it brought and UI.Dress draws the square again in the addon's palette.
--
-- The cooldown frame is the one exception and it is exactly the shape of the
-- rule: it is stripped from nothing because nothing here draws a replacement,
-- and the client's own call is what fills it in.
--
-- The hover is the addon's own box for the same reason. A window drawn in this
-- palette with the client's tiled parchment opening over it is two designs on
-- one screen, which is the defect the addon's own box exists to stop.
--
-- **Nothing here hands the right button to the camera.** UI.PassCamera is on
-- every other hoverable frame in the addon and it is deliberately off these, for
-- the reason Character/Paperdoll.lua spells out at its own squares: a square
-- whose right click is an action cannot also pass the right button through. The
-- right click on a bag slot is the whole of eat, equip, open, sell, attach and
-- put a stone on your axe, and with the button passed through every one of them
-- went to the camera instead. The square drew, hovered and said what was in it,
-- and a right click turned the view.
--
-- The price is the one named in UI/Tip.lua and it is paid here on purpose: a
-- right drag begun on a square does not turn the camera. There are two pixels
-- between squares and a frame around the window, so there is somewhere on it to
-- start a drag; there is nowhere else to put a right click.
--------------------------------------------------------------------------

local SLOT, GAP, BREAK = UI.SLOT, UI.SLOT_GAP, UI.SLOT_BREAK

-- The mark on a square a vendor will take, which is the same coin the loot
-- feed's money chip draws. Named rather than written at the call site because
-- scripts/bake-glyphs.sh is what decides which letter carries which mark, and a
-- literal `$` sitting in the middle of the layout gives nobody reading this file
-- a way to find that out.
local COIN = "$"

-- The pointer over something this vendor will pay for.
--
-- The client's own cursor, by the name its own bag buttons ask for. Blizzard's
-- ContainerFrameItemButton_OnEnter sets exactly this one over a slot while a
-- merchant is up, so a square in this window and a square in theirs read the
-- same at the same moment, and the coin under the pointer is the coin the
-- player already knows.
local BUY = "BUY_CURSOR"

local TEMPLATE = "ContainerFrameItemButtonTemplate"

local squares, holders = {}, {}
local canvas, headings
local inherited = true

-- The square whose pointer this file changed, or nothing.
--
-- Held rather than worked out again on the way off, because the cursor is one
-- thing on the screen and this file is not the only one that writes it. A
-- square that reset the pointer on every OnLeave would take back whatever the
-- cursor was doing for somebody else, and an empty slot in a bag has no
-- business saying anything about it.
local paying

-- How wide a grid of this many columns is, which is the number the window sizes
-- itself off. UI/Slot.lua answers it, because the merchant window asks the same
-- question of the same squares and two files with the same arithmetic in them
-- is how the two windows end up a pixel apart.
function Grid.Width(columns)
	return UI.SlotSpan(columns)
end

--------------------------------------------------------------------------
-- Building one
--------------------------------------------------------------------------

-- The two strings a bag square carries that no other square in the addon does.
local function Extras(button)
	-- How many slots you have free, on the one square the empty pile folds
	-- into. Its own string rather than the tally in the corner, and in the
	-- middle of the square, because the two numbers are not the same kind of
	-- number: the tally is a fact about the item lying on the square and this is
	-- a fact about the square. A single free slot reads "1" in the centre, where
	-- the tally would have drawn nothing at all.
	button.free = UI.Label(button, M.font, C.dim, "CENTER", UI.FLAT)
	button.free:SetPoint("CENTER")
	UI.Wrap(button.free, false)

	-- The coin on a grey a vendor will take, in the corner the tally is not in.
	--
	-- It says one thing and it is not "this is junk": the pile heading over the
	-- square already says that. It says a merchant will pay for this, which the
	-- pile cannot, because a grey with no sell price on it is filed as junk like
	-- every other grey and is the one thing in that pile the sale will leave
	-- behind.
	button.coin = UI.Glyph(button, M.glyph, C.heading, "LEFT")
	button.coin:SetPoint("TOPLEFT", 3, -3)
	UI.Wrap(button.coin, false)
	button.coin:SetText(COIN)
	button.coin:Hide()
	return button
end

-- What the box over a square says. Nothing at all for an empty one: a slot with
-- nothing in it has nothing to tell you, and a box that opens to say so is a box
-- that opens over every gap in the window.
local function Subject(button)
	if not button.link then
		return nil
	end
	-- The bag and the slot travel with the link, and they are what makes the
	-- binding line true. A link on its own says "Binds when picked up" about
	-- something you picked up months ago; the slot it is lying in says
	-- "Soulbound". See Head in UI/Tip.lua.
	return {
		kind = "item",
		link = button.link,
		title = button.name,
		count = button.count,
		bag = button.bag,
		slot = button.slot,
	}
end

-- The coin on the pointer, and off it again.
--
-- Both are guarded on which square is holding it, so the pointer is written
-- once on the way in and once on the way out however many times the client
-- calls the handlers, and a square that never changed it never resets it.
local function Take(button)
	if paying == button then
		return
	end
	paying = button
	SetCursor(BUY)
end

local function Give()
	if not paying then
		return
	end
	paying = nil
	ResetCursor()
end

local function Enter(button)
	UI.Tint(button.bg, C.control)
	-- The pointer says what the click would do, which at a vendor is sell this.
	-- The window already dims what the merchant refuses, and dimming is a fact
	-- about the whole grid you read at a glance. This is the answer for the one
	-- square you are actually pointing at.
	if button.sells then
		Take(button)
	end
	-- On the square. An item in a bag is a thing you are pointing at, and the
	-- corner of the screen is a long way from a grid of a hundred of them.
	ns.Tip.Open(button, Subject(button), nil, UI.Tooltip.BESIDE)
end

local function Leave(button)
	UI.Tint(button.bg, C.sunken)
	if paying == button then
		Give()
	end
	ns.Tip.Close()
end

-- The bag's holder frame, made on first use.
--
-- Every one of them is the whole canvas, so which holder a square is parented
-- to changes nothing about where it is drawn. The frame exists to carry one
-- number, and it carries it because the client's own click handler reads the bag
-- off the parent and there is nowhere else to put it.
local function Holder(bag)
	local holder = holders[bag]
	if not holder then
		holder = CreateFrame("Frame", nil, canvas)
		holder:SetAllPoints()
		holder:SetID(bag)
		holders[bag] = holder
	end
	return holder
end

-- One square. Named, because a bag button is one of the frames the client and
-- other addons reach for by name, and because a square that has landed
-- somewhere wrong has to be findable from a macro.
local function Build(index)
	local made, button = pcall(CreateFrame, "Button",
		"WarriorKitBagSlot" .. index, canvas, TEMPLATE)
	-- A client with no such template is a client where the squares are still
	-- drawn and still say what is in them, and where a click does nothing.
	-- Recorded rather than raised, because the window is worth having either way
	-- and because the panel has to be able to say which of the two you have.
	if not made or type(button) ~= "table" then
		inherited = false
		button = CreateFrame("Button", "WarriorKitBagSlot" .. index, canvas)
	end

	button:SetSize(SLOT, SLOT)
	UI.Undress(button)
	UI.Dress(button, SLOT)
	Extras(button)
	button:SetScript("OnEnter", Enter)
	button:SetScript("OnLeave", Leave)
	-- The template refreshes its own box by calling this while the pointer is
	-- still on the square. Ours has to answer the same name or the client's would
	-- open underneath the addon's on the next refresh.
	button.UpdateTooltip = Enter
	return button
end

local function Square(index)
	local button = squares[index]
	if not button then
		button = Build(index)
		squares[index] = button
	end
	return button
end

--------------------------------------------------------------------------
-- Filling one in
--------------------------------------------------------------------------

-- Whether the client's own cooldown call has answered so far. One refusal takes
-- it off for the session rather than being tried a hundred and fifty times a bag
-- update for the rest of the evening.
local sweeps = true

-- The swirl over a potion you just drank.
--
-- The client's own call, by name and guarded, because there is no other way to
-- it: the sweep is drawn on the frame the template brought with it, off a
-- reading of the slot that this addon has no equivalent for, and building a
-- second cooldown model beside the client's to redraw a circle is not a trade
-- worth making. It is also the one region the template carries that is not
-- stripped, for the same reason: nothing here draws a replacement.
--
-- A build with no such call, or one whose call refuses a button parented
-- somewhere it did not expect, loses the swirl and keeps the square.
local function Sweep(button, entry)
	if not sweeps or type(_G.ContainerFrame_UpdateCooldown) ~= "function" then
		return false
	end
	if type(button.Cooldown) ~= "table" then
		return false
	end
	if not pcall(_G.ContainerFrame_UpdateCooldown, entry.bag, button) then
		sweeps = false
		return false
	end
	return true
end

local function Paint(button, entry, selling)
	-- The one square the empty pile folded into, which is the only entry in the
	-- window whose count is a number of slots rather than a number of items.
	local free = entry.group == ns.Bags.EMPTY
	local sellable = ns.Bags.Sellable(entry)
	-- Dim while a merchant is open, and only then. What a vendor will not buy
	-- is a fact about this minute rather than about the item: a quest item you
	-- cannot sell is an ordinary square in a bag you opened to find something,
	-- and it is the one square in the way when you are standing at a vendor
	-- deciding what to be rid of. An empty slot is not refused, it is empty.
	local refused = selling and entry.link ~= nil and not sellable

	button.link, button.name, button.count = entry.link, entry.name, entry.count
	button.bag, button.slot = entry.bag, entry.slot
	UI.SlotPaint(button, entry.icon, not free and entry.count or nil,
		entry.quality, refused)
	button.free:SetText(free and tostring(entry.count or 1) or "")
	button.coin:SetShown(sellable and entry.group == ns.Bags.JUNK)

	button.sells = selling and sellable
	-- The square under the pointer just sold, so what is lying on it now is
	-- whatever the layout moved up into its place. The pointer follows the
	-- square rather than the item, and nothing else would take the coin off it.
	if paying == button and not button.sells then
		Give()
	end
	button:SetAlpha(refused and UI.SLOT_DIM or 1)

	button:SetParent(Holder(entry.bag))
	button:SetID(entry.slot)
	Sweep(button, entry)
end

local function Place(button, top, column, line)
	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT",
		column * (SLOT + GAP), -(top + line * (SLOT + GAP)))
end

-- Everything the pool made and this pass did not use.
local function Trim(squaresUsed, headersUsed)
	for index = squaresUsed + 1, #squares do
		squares[index]:Hide()
	end
	headings:Trim(headersUsed)
end

--------------------------------------------------------------------------

-- Where the squares are drawn. Called once, before any square exists, because a
-- square is parented to this frame when it is made.
function Grid.Attach(where)
	canvas = where
	headings = UI.Headings(canvas)
	return canvas
end

-- Every pile laid out, and how tall the result is.
--
-- The height is handed back rather than written anywhere, because the thing that
-- has to know is the scroll view and the scroll view belongs to the window.
function Grid.Paint(state, columns)
	local at, top = 0, 0
	-- Asked once for the whole pass rather than per square. It cannot change
	-- inside one layout, and a hundred and fifty squares asking the same
	-- question is a hundred and fifty answers that are the same.
	local selling = ns.BagsMerchant.Open()
	-- Walking away from a vendor with the pointer still on a square you could
	-- have sold. There is no OnLeave for that, because the mouse did not move:
	-- the merchant closed under it, and the repaint is where this file finds
	-- out.
	if not selling then
		Give()
	end
	for index = 1, state.shown do
		local group = state.groups[index]
		local entries = group.entries
		top = headings:Name(index, group.name, top)
		for held = 1, #entries do
			at = at + 1
			local button = Square(at)
			Paint(button, entries[held], selling)
			Place(button, top, (held - 1) % columns, math.floor((held - 1) / columns))
			button:Show()
		end
		local lines = math.ceil(#entries / columns)
		top = top + lines * SLOT + (lines - 1) * GAP + BREAK
	end
	Trim(at, state.shown)
	return math.max(top - BREAK, 1)
end

-- The pool, for the harness. It reads the squares to say that a click on one
-- lands on the bag and slot the scan put there, which is the one claim about
-- this file that cannot be made from the outside.
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
	if not inherited then
		return ("%d squares, and this client refused the bag button template, so a click does nothing")
			:format(#squares)
	end
	return ("%d squares on the client's own bag button"):format(#squares)
end
