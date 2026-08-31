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
-- gold border, a parchment stack count and a normal texture, drawn for a window
-- that looks nothing like this one. Every one of those regions is stripped and
-- the square is drawn again in the addon's palette: a sunken ground, a hairline
-- in the item's own grade colour, a crisp icon and a flat count. What is left
-- of the template is the part with no picture in it.
--
-- The cooldown frame is the one exception and it is exactly the shape of the
-- rule: it is stripped from nothing because nothing here draws a replacement,
-- and the client's own call is what fills it in.
--
-- The hover is the addon's own box for the same reason. A window drawn in this
-- palette with the client's tiled parchment opening over it is two designs on
-- one screen, which is the defect the addon's own box exists to stop.
--------------------------------------------------------------------------

-- One square, and the gap to the next. Thirty one leaves twenty seven pixels of
-- picture once the two pixel inset either side is taken off, and twenty seven is
-- one of the two sizes an icon is drawn at exactly on this client: the stored
-- texture is sixty four texels, the crop takes it to fifty four, and fifty four
-- halves to twenty seven. Any other number is a blend of two stored copies.
local SLOT, GAP = 31, 3

-- The line a pile's name sits on, and the air under the last row of one pile
-- before the next name.
local HEADER, BREAK = M.row, M.rowGap * 2

Grid.SLOT, Grid.GAP, Grid.HEADER = SLOT, GAP, HEADER

local TEMPLATE = "ContainerFrameItemButtonTemplate"

local squares, headers, holders = {}, {}, {}
local canvas
local inherited = true

-- How wide a grid of this many columns is, which is the number the window sizes
-- itself off. Public because the window owns its own width and this file owns
-- what a square costs.
function Grid.Width(columns)
	return columns * SLOT + (columns - 1) * GAP
end

--------------------------------------------------------------------------
-- Building one
--------------------------------------------------------------------------

-- A region the template put on the button, or nothing.
--
-- Probed rather than named, because which of them a build carries is a fact
-- about that build: the quality border and the search overlay arrived in later
-- clients and the quest texture is spelled differently across them. The type
-- test is not decoration either. A frame answers a method for anything asked of
-- it by capitalised name, so a missing region reads as a function rather than
-- as nil, and calling Hide on a function is a login error.
local function Theirs(button, key)
	local region = button[key]
	if type(region) ~= "table" or type(region.Hide) ~= "function" then
		return nil
	end
	return region
end

-- Everything the template draws, out of the way. ns.Strip rather than Hide,
-- because the client's own bag update code turns its regions back on and Strip
-- is how the rest of the addon answers that: the Show method becomes Hide, so a
-- region that is told to come back stays down.
local STRIPPED = { "icon", "Count", "IconBorder", "IconOverlay",
	"IconQuestTexture", "searchOverlay", "Stock" }

local function Undress(button)
	for index = 1, #STRIPPED do
		local region = Theirs(button, STRIPPED[index])
		if region then
			ns.Strip(region)
		end
	end
	local normal = ns.Measure(button, "GetNormalTexture")
	if normal then
		ns.Strip(normal)
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

local function Enter(button)
	UI.Tint(button.bg, C.control)
	-- On the square. An item in a bag is a thing you are pointing at, and the
	-- corner of the screen is a long way from a grid of a hundred of them.
	ns.Tip.Open(button, Subject(button), nil, UI.Tooltip.BESIDE)
end

local function Leave(button)
	UI.Tint(button.bg, C.sunken)
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
	UI.PassCamera(button)
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

local function Paint(button, entry)
	button.link, button.name, button.count = entry.link, entry.name, entry.count
	button.art:SetTexture(entry.icon)
	button.art:SetShown(entry.link ~= nil)
	button.tally:SetText((entry.count or 1) > 1 and tostring(entry.count) or "")
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
	for index = 1, state.shown do
		local group = state.groups[index]
		local entries = group.entries
		top = Name(index, group.name, top)
		for held = 1, #entries do
			at = at + 1
			local button = Square(at)
			Paint(button, entries[held])
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
