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
-- **The button is the client's own template and that is the whole design.**
-- `ContainerFrameItemButtonTemplate` is what every bag button in the game is
-- built on, Blizzard's and every addon's, and inheriting it means the click, the
-- drag, the stack split, the shift-link and the merchant sale are the client's
-- code rather than ours. None of that is reimplementable: a right click on a
-- bag slot means eat, equip, open, sell or attach depending on which window is
-- in front of you, and the rules for which are inside the client.
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
-- **The art is ours and the behaviour is theirs.** The template arrives with a
-- gold border, a parchment stack count, a quickslot plate and a lit blue square
-- over the whole slot, all drawn for a window that looks nothing like this one.
-- Every region it brought is swept off and the square is drawn again in the
-- addon's palette: a sunken ground, a hairline in the item's own grade colour, a
-- crisp icon and a flat count. What is left of the template is the part with no
-- picture in it.
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

-- One square, and the gap to the next. Thirty one leaves twenty seven pixels of
-- picture once the two pixel inset either side is taken off, and twenty seven is
-- one of the two sizes an icon is drawn at exactly on this client: the stored
-- texture is sixty four texels, the crop takes it to fifty four, and fifty four
-- halves to twenty seven. Any other number is a blend of two stored copies.
--
-- The gap is two rather than three because the square already draws its own
-- hairline. A rim and a rim with two pixels between them read as separated; the
-- third pixel is spent on nothing and there are twelve of those gaps down a full
-- bag.
local SLOT, GAP = 31, 2

-- The line a pile's name sits on, and the air under the last row of one pile
-- before the next name.
--
-- Both are the smallest they can be and still do their job, because a full bag
-- is sixteen piles and every pixel here is paid sixteen times. The header is the
-- heading face plus three, which is a line box for a thirteen pixel font and
-- nothing else; M.row is twenty because it is sized for a control with a tick
-- box in it, and there is no control here. The break is one row gap rather than
-- two: what separates two piles is the heading under the air, not the air.
local HEADER, BREAK = M.heading + 3, M.rowGap

Grid.SLOT, Grid.GAP, Grid.HEADER = SLOT, GAP, HEADER

-- The mark on a square a vendor will take, which is the same coin the loot
-- feed's money chip draws. Named rather than written at the call site because
-- scripts/bake-glyphs.sh is what decides which letter carries which mark, and a
-- literal `$` sitting in the middle of the layout gives nobody reading this file
-- a way to find that out.
local COIN = "$"

-- What is left of a square holding something a merchant will not buy. Dim
-- enough to read as unavailable beside a full-strength square next to it, and
-- not so dim that you cannot see what the item is: the point is to say which of
-- the things in front of you the sale is about, not to hide the rest.
local REFUSED = 0.4

-- The pointer over something this vendor will pay for.
--
-- The client's own cursor, by the name its own bag buttons ask for. Blizzard's
-- ContainerFrameItemButton_OnEnter sets exactly this one over a slot while a
-- merchant is up, so a square in this window and a square in theirs read the
-- same at the same moment, and the coin under the pointer is the coin the
-- player already knows.
local BUY = "BUY_CURSOR"

local TEMPLATE = "ContainerFrameItemButtonTemplate"

local squares, headers, holders = {}, {}, {}
local canvas
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
-- itself off. Public because the window owns its own width and this file owns
-- what a square costs.
function Grid.Width(columns)
	return columns * SLOT + (columns - 1) * GAP
end

--------------------------------------------------------------------------
-- Building one
--------------------------------------------------------------------------

-- One region the template drew, drawing nothing.
--
-- Three writes rather than one, because no single one of them holds on every
-- build. The file is cleared, so a region the client's own bag update shows
-- again has nothing in it. The alpha goes to zero, so one whose file is written
-- again draws nothing either. And ns.Strip puts Hide on the Show method, which
-- is how the rest of the addon answers Blizzard code that turns its regions back
-- on.
--
-- Every call is guarded on its own type. A frame answers a method for anything
-- asked of it by capitalised name, so a call a build does not have reads as a
-- function rather than as nil, and a font string has no SetTexture at all.
local function Erase(region)
	if type(region) ~= "table" or type(region.Hide) ~= "function" then
		return
	end
	if type(region.SetTexture) == "function" then
		pcall(region.SetTexture, region, nil)
	end
	if type(region.SetAtlas) == "function" then
		pcall(region.SetAtlas, region, nil)
	end
	if type(region.SetAlpha) == "function" then
		pcall(region.SetAlpha, region, 0)
	end
	ns.Strip(region)
end

-- The button's own regions, in a table, behind a pcall. GetRegions answers a
-- list rather than a value, which is the one shape ns.Measure cannot carry.
local function Gather(button)
	return { button:GetRegions() }
end

-- The two textures a button keeps off its region list on some builds, which is
-- why the sweep is not the whole of it.
--
-- The pressed one is not here and is held back from the sweep as well: Dress
-- gives the square its own black one, and a stripped texture cannot be given
-- one.
local STATES = { "GetNormalTexture", "GetHighlightTexture" }

-- Everything the template arrived wearing, off.
--
-- Swept rather than named. The list this file used to keep held the seven
-- regions a build was expected to spell that way, and the one that reached the
-- screen was not among them: every square in the window wore a lit blue square
-- over the whole slot, ButtonHilight-Square at additive blend, which is what a
-- hover looks like on Blizzard's parchment and nothing like one here.
--
-- Blanking the state texture the getter answers did not take it off, and what is
-- left is an ordinary region of the button: a template puts one there showing
-- and hides it again in its own OnLeave, and this file takes OnEnter and OnLeave
-- for the tooltip, so nothing was left to hide it. That is why it was on every
-- square at once rather than on the one under the cursor, and why the alpha is
-- written as well as the file: a region nothing here can name still draws
-- nothing at zero, whatever else turns it back on.
--
-- The sweep also ends the guessing. Which regions a build carries and what it
-- calls them is a fact about that build: the quality border and the search
-- overlay arrived in later clients and the quest texture is spelled differently
-- across them. Taking every region the button came with is one answer for all of
-- them, and it is safe because the addon draws its own afterwards. Nothing on
-- the button at this point is worth keeping.
local function Undress(button)
	local pushed = ns.Measure(button, "GetPushedTexture")
	local ok, regions = pcall(Gather, button)
	if ok then
		for index = 1, #regions do
			if regions[index] ~= pushed then
				Erase(regions[index])
			end
		end
	end
	for index = 1, #STATES do
		Erase(ns.Measure(button, STATES[index]))
	end
end

-- What the addon draws instead.
local function Dress(button)
	button.bg = ns.Fill(button, "BACKGROUND", C.sunken[1], C.sunken[2], C.sunken[3], 1)
	button.bg:SetAllPoints()
	button.edges = ns.Outline(button, C.edge[1], C.edge[2], C.edge[3], 1)
	ns.EdgeSize(button.edges, ns.Pixel(button))

	button.art = UI.Icon(button, "ARTWORK")
	button.art:SetPoint("TOPLEFT", 2, -2)
	button.art:SetPoint("BOTTOMRIGHT", -2, 2)

	button.tally = UI.Label(button, M.small, C.text, "RIGHT", UI.FLAT)
	button.tally:SetPoint("BOTTOMRIGHT", -3, 3)
	UI.Wrap(button.tally, false)

	-- How many slots you have free, on the one square the empty pile folds
	-- into. Its own string rather than the tally above it, and in the middle of
	-- the square rather than the corner, because the two numbers are not the
	-- same kind of number: the tally is a fact about the item lying on the
	-- square and this is a fact about the square. A single free slot reads "1"
	-- in the centre, where the tally would have drawn nothing at all.
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

	-- On the way down, in the addon's own black rather than the template's
	-- quickslot plate. A square that does not move under the mouse reads as a
	-- square that did not take the click. The widget draws this itself between
	-- mouse down and mouse up, so it costs one texture and no script, the same
	-- way an ability square answers a press.
	button:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
	local pushed = ns.Measure(button, "GetPushedTexture")
	if pushed then
		pushed:SetColorTexture(0, 0, 0, 0.36)
		button.pushed = pushed
	end
end

-- What the box over a square says. Nothing at all for an empty one: a slot with
-- nothing in it has nothing to tell you, and a box that opens to say so is a box
-- that opens over every gap in the window.
local function Subject(button)
	if not button.link then
		return nil
	end
	return {
		kind = "item",
		link = button.link,
		title = button.name,
		count = button.count,
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
	Undress(button)
	Dress(button)
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

-- The hairline round a square: the item's own grade, or the theme's edge for
-- anything the client grades white or grey.
--
-- Two colours rather than eight is the point. A window where every square has a
-- coloured rim is a window with no colour in it, and white and grey are what
-- nearly everything you carry is.
local function Edge(entry)
	local quality = entry.quality
	if not quality or quality < 2 then
		return C.edge
	end
	return UI.Quality[quality] or C.edge
end

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
	button.link, button.name, button.count = entry.link, entry.name, entry.count
	button.art:SetTexture(entry.icon)
	button.art:SetShown(entry.link ~= nil)
	button.tally:SetText((not free and (entry.count or 1) > 1)
		and tostring(entry.count) or "")
	button.free:SetText(free and tostring(entry.count or 1) or "")
	button.coin:SetShown(sellable and entry.group == ns.Bags.JUNK)

	-- Dim while a merchant is open, and only then. What a vendor will not buy
	-- is a fact about this minute rather than about the item: a quest item you
	-- cannot sell is an ordinary square in a bag you opened to find something,
	-- and it is the one square in the way when you are standing at a vendor
	-- deciding what to be rid of. An empty slot is not refused, it is empty.
	local refused = selling and entry.link ~= nil and not sellable
	button.sells = selling and sellable
	-- The square under the pointer just sold, so what is lying on it now is
	-- whatever the layout moved up into its place. The pointer follows the
	-- square rather than the item, and nothing else would take the coin off it.
	if paying == button and not button.sells then
		Give()
	end
	button:SetAlpha(refused and REFUSED or 1)
	button.art:SetDesaturated(refused and true or false)

	ns.Recolor(button.edges, Edge(entry))
	button:SetParent(Holder(entry.bag))
	button:SetID(entry.slot)
	Sweep(button, entry)
end

local function Place(button, top, column, line)
	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT",
		column * (SLOT + GAP), -(top + line * (SLOT + GAP)))
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
local function Trim(squaresUsed, headersUsed)
	for index = squaresUsed + 1, #squares do
		squares[index]:Hide()
	end
	for index = headersUsed + 1, #headers do
		headers[index]:Hide()
	end
end

--------------------------------------------------------------------------

-- Where the squares are drawn. Called once, before any square exists, because a
-- square is parented to this frame when it is made.
function Grid.Attach(where)
	canvas = where
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
		top = Name(index, group.name, top)
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
	return headers
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
