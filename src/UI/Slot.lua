local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The item square, and the headings over a column of them
--
-- Two things, in one file, because a window that draws items draws both and
-- neither is worth a file on its own. The bag window and the merchant window
-- are the two today; a bank, a loot window, a trade window and an auction house
-- are the same two pieces again.
--
-- **A square is a sunken ground, a hairline in the item's own grade, a crisp
-- icon and a count in the corner.** That is the whole definition and it is here
-- so that there is one of it. It was written twice, once in Bags/Grid.lua and
-- once in Merchant/Grid.lua, and the two windows are open beside each other at
-- a vendor: two squares that differ by a pixel of inset or a shade of grey is
-- the defect this file exists to make impossible rather than to fix.
--
-- **What is not here is what each window does with it.** A bag square is built
-- on the client's own bag button, carries a cooldown swirl, wears a coin when a
-- vendor will pay for what is on it and holds the count of the whole empty pile
-- when the pile folds into it. A merchant square carries none of that and sits
-- at the left of a row with a price on it. Every one of those is a fact about
-- one window and stays in that window's file. The line between the two is
-- drawn at "does this square look different", not at "does this square do
-- something different".
--
-- **Dressing and undressing are two calls because they are two situations.** A
-- square this addon makes arrives blank and only needs dressing. A square built
-- on one of the client's own templates arrives wearing a gold border, a
-- parchment stack count, a quickslot plate and a lit blue square over the whole
-- slot, all drawn for a window that looks nothing like either of these, and has
-- to be swept first. Bags/Grid.lua's header carries the argument for why that
-- sweep takes every region rather than a list of named ones.
--
-- **The grade rule is two colours and no more.** An item the client grades
-- white or grey takes the theme's own edge; everything above that takes its
-- grade. A window where every square has a coloured rim is a window with no
-- colour in it, and white and grey are what nearly everything you carry and
-- nearly everything on a vendor's rack is.
--------------------------------------------------------------------------

-- One square, and the gap to the next.
--
-- Thirty one leaves twenty seven pixels of picture once the two pixel inset
-- either side is taken off, and twenty seven is one of the two sizes an icon is
-- drawn at exactly on this client: the stored texture is sixty four texels, the
-- crop takes it to fifty four, and fifty four halves to twenty seven. Any other
-- number is a blend of two stored copies.
--
-- The gap is two rather than three because the square already draws its own
-- hairline. A rim and a rim with two pixels between them read as separated; the
-- third pixel is spent on nothing and there are twelve of those gaps down a
-- full bag.
UI.SLOT, UI.SLOT_GAP, UI.SLOT_INSET = 31, 2, 2

-- The air between the two lanes of a pile that is drawn in two.
--
-- Half a square, which is the smallest gap that reads as a division rather than
-- a wider gap between two squares. The bag window's equipment piles are split
-- down the middle -- what is already bound to you on the left, what is still
-- free to sell or give away on the right -- and the two halves have to be
-- tellable apart at a glance without a rule drawn between them.
--
-- Every other pile in that window is one lane of the full width, and the window
-- carries this much air at its right edge instead, so the two kinds of pile end
-- at the same place.
--
-- **It is a design number and the caller has to snap it.** Every other distance
-- in that grid is a whole number of square pitches, so every square in a row
-- lands on the same fraction of a pixel as the one before it and they all
-- rasterise the same way. A lane offset that is not a whole number of pixels
-- puts the second lane on a different fraction from the first, and a hairline
-- one pixel wide on the wrong fraction is a hairline the client draws on
-- neither of the two pixels it falls between. That is not hypothetical: at half
-- a pixel it took the right edge off the last square of the left lane and the
-- left edge off the first square of the right, and left every other edge in the
-- window alone. Bags/Grid.lua puts this through UI.Round for that reason, and a
-- whole number of pixels between the lanes means the second lane's squares
-- share the first lane's fractions exactly.
UI.SLOT_LANE = math.floor(UI.SLOT / 2)

-- What is left of a square you cannot act on: something a vendor will not take,
-- something he has run out of, something you cannot pay for. Dim enough to read
-- as unavailable beside a square next to it that is not, and not so dim that
-- you cannot see what the item is. The point is to say which of the things in
-- front of you the moment is about, not to hide the rest.
UI.SLOT_DIM = 0.4

-- The line a pile's name sits on, and the air under the last row of one pile
-- before the next name.
--
-- Both are the smallest they can be and still do their job, because a full bag
-- is sixteen piles and every pixel here is paid sixteen times. The heading is
-- the heading face plus three, which is a line box for a thirteen pixel font
-- and nothing else; M.row is twenty because it is sized for a control with a
-- tick box in it, and there is no control here. The break is one row gap rather
-- than two: what separates two piles is the heading under the air, not the air.
UI.SLOT_HEADER, UI.SLOT_BREAK = M.heading + 3, M.rowGap
-- The line a sub-pile's caption sits on: Cloth under Trade Goods. The small
-- face plus the same three, for the same reason, and dim rather than the
-- heading colour so the pile's own heading is still the thing the eye lands
-- on.
UI.SLOT_SUBHEADER = M.small + 3

-- How wide a line of this many squares is.
--
-- Here rather than in the window that asks because it is the square and the
-- gap, and those are this file's. The bag window sizes itself off it. The
-- merchant window used to as well and no longer does: its unit is a card with a
-- name and a price on it rather than a bare square, so Merchant/Grid.lua owns
-- that width and says why.
function UI.SlotSpan(columns)
	return columns * UI.SLOT + (columns - 1) * UI.SLOT_GAP
end

--------------------------------------------------------------------------
-- The grade
--------------------------------------------------------------------------

-- The hairline round a square: the item's own grade, or the theme's edge for
-- anything the client grades white or grey.
function UI.SlotEdge(quality)
	if not quality or quality < 2 then
		return C.edge
	end
	return UI.Quality[quality] or C.edge
end

-- The same rule for a word rather than a rim, which is what a window that puts
-- an item's name beside its square wants. The floor is the body colour rather
-- than the edge colour, because a white item's name has to be readable and its
-- rim only has to be quiet.
function UI.SlotInk(quality)
	if not quality or quality < 2 then
		return C.text
	end
	return UI.Quality[quality] or C.text
end

--------------------------------------------------------------------------
-- Building one
--------------------------------------------------------------------------

-- One region a template drew, drawing nothing.
--
-- Three writes rather than one, because no single one of them holds on every
-- build. The file is cleared, so a region the client's own update shows again
-- has nothing in it. The alpha goes to zero, so one whose file is written again
-- draws nothing either. And ns.Strip puts Hide on the Show method, which is how
-- the rest of the addon answers Blizzard code that turns its regions back on.
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

-- A frame's own regions, in a table, behind a pcall. GetRegions answers a list
-- rather than a value, which is the one shape ns.Measure cannot carry.
local function Gather(frame)
	return { frame:GetRegions() }
end

-- The two textures a button keeps off its region list on some builds, which is
-- why the sweep is not the whole of it. The pressed one is not here and is held
-- back from the sweep as well: UI.Dress gives the square its own black one, and
-- a stripped texture cannot be given one.
local STATES = { "GetNormalTexture", "GetHighlightTexture" }

-- Everything a template arrived wearing, off.
--
-- Swept rather than named, and Bags/Grid.lua's header carries the two bugs that
-- argument came out of. The short version: which regions a build carries and
-- what it calls them is a fact about that build, taking every region the frame
-- came with is one answer for all of them, and it is safe because UI.Dress
-- draws the square again afterwards.
function UI.Undress(frame)
	local pushed = ns.Measure(frame, "GetPushedTexture")
	local ok, regions = pcall(Gather, frame)
	if ok then
		for index = 1, #regions do
			if regions[index] ~= pushed then
				Erase(regions[index])
			end
		end
	end
	for index = 1, #STATES do
		Erase(ns.Measure(frame, STATES[index]))
	end
	return frame
end

-- What the addon draws instead: the square itself.
--
-- `size` is how big the picture is inset inside, and it is an argument because
-- the two windows using it today happen to agree and the next one need not.
-- Everything else is fixed, because everything else is what makes a square in
-- this addon recognisable as one.
function UI.Dress(square, size)
	square.bg = ns.Fill(square, "BACKGROUND", C.sunken[1], C.sunken[2], C.sunken[3], 1)
	square.bg:SetAllPoints()
	square.edges = ns.Outline(square, C.edge[1], C.edge[2], C.edge[3], 1)
	ns.EdgeSize(square.edges, ns.Pixel(square))

	square.art = UI.Icon(square, "ARTWORK")
	square.art:SetPoint("TOPLEFT", UI.SLOT_INSET, -UI.SLOT_INSET)
	square.art:SetPoint("BOTTOMRIGHT", -UI.SLOT_INSET, UI.SLOT_INSET)

	-- Outlined, not flat. The count lands on the item's own picture, which is
	-- art this addon did not paint and cannot predict: a 4 on turtle meat was
	-- pale text on a pale icon and it disappeared. This square was reading the
	-- first of UI/Text.lua's three roles, which is the one for a surface whose
	-- colour the palette knows.
	--
	-- The rim rather than the shadow, and M.tally is sized to buy it: a shadow
	-- is dark on one corner, and an icon that is bright on that corner takes
	-- the number back. Blizzard outlines this same number for this same reason.
	square.tally = UI.Label(square, M.tally, C.text, "RIGHT", UI.OUTLINE)
	square.tally:SetPoint("BOTTOMRIGHT", -3, 3)
	UI.Wrap(square.tally, false)

	-- On the way down, in the addon's own black rather than a template's
	-- quickslot plate. A square that does not move under the mouse reads as a
	-- square that did not take the click. The widget draws this itself between
	-- mouse down and mouse up, so it costs one texture and no script, the same
	-- way an ability square answers a press.
	--
	-- Guarded, because a square is not always a button: the merchant window's is
	-- a plain frame at the left of a row and the row is what takes the press.
	if type(square.SetPushedTexture) == "function" then
		square:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
		local pushed = ns.Measure(square, "GetPushedTexture")
		if pushed then
			pushed:SetColorTexture(0, 0, 0, 0.36)
			square.pushed = pushed
		end
	end
	square.size = size or UI.SLOT
	return square
end

-- A square this addon makes from nothing, dressed. The two windows that have
-- one built on a client template call UI.Undress and UI.Dress themselves,
-- because what they hand over is a frame that already exists.
function UI.Slot(parent, size)
	local square = CreateFrame("Frame", nil, parent)
	square:SetSize(size or UI.SLOT, size or UI.SLOT)
	return UI.Dress(square, size)
end

-- One square filled in: the picture, the count in the corner, the grade on the
-- rim, and whether the whole thing is dimmed.
--
-- `count` is a number to draw or nothing. A stack of one draws nothing at all,
-- which is a decision rather than an omission: a window where every square
-- carries a 1 is a window of ones.
function UI.SlotPaint(square, icon, count, quality, dim)
	square.art:SetTexture(icon)
	square.art:SetShown(icon ~= nil)
	square.art:SetDesaturated(dim and true or false)
	square.tally:SetText((count and count > 1) and tostring(count) or "")
	ns.Recolor(square.edges, UI.SlotEdge(quality))
	return square
end

--------------------------------------------------------------------------
-- The headings over them
--------------------------------------------------------------------------

local Headings = {}
Headings.__index = Headings

-- A pool of pile captions on one canvas.
--
-- Pooled rather than made per pile for the same reason the squares under them
-- are: a bag update arrives five times for one loot and this client cannot
-- destroy a frame, so a caption made per pass is a caption leaked per pass.
function UI.Headings(canvas)
	return setmetatable({ canvas = canvas, labels = {}, subs = {} }, Headings)
end

-- One caption at `top`, and where the first thing under it starts. Returning
-- the next offset rather than the caption is what lets a caller write its
-- layout as one running number.
function Headings:Name(index, text, top)
	local label = self.labels[index]
	if not label then
		label = UI.Label(self.canvas, M.heading, C.heading, "LEFT", UI.FLAT)
		UI.Wrap(label, false)
		self.labels[index] = label
	end
	label:ClearAllPoints()
	label:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -top)
	label:SetText(text)
	label:Show()
	return top + UI.SLOT_HEADER
end

-- One sub-caption at `top`, and where the first thing under it starts. Its
-- own pool rather than a restyled caption, because a string's face and colour
-- are set when it is made, and two pools are cheaper than resetting both on
-- every caption every pass.
function Headings:Sub(index, text, top)
	local label = self.subs[index]
	if not label then
		label = UI.Label(self.canvas, M.small, C.dim, "LEFT", UI.FLAT)
		UI.Wrap(label, false)
		self.subs[index] = label
	end
	label:ClearAllPoints()
	label:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -top)
	label:SetText(text)
	label:Show()
	return top + UI.SLOT_SUBHEADER
end

-- Everything the pool made and this pass did not use. A caller that draws no
-- sub-captions passes nothing for them and every one it ever drew goes away.
function Headings:Trim(used, subsUsed)
	for index = used + 1, #self.labels do
		self.labels[index]:Hide()
	end
	for index = (subsUsed or 0) + 1, #self.subs do
		self.subs[index]:Hide()
	end
	return #self.labels
end

-- The pool, for the harness. It reads the captions to say that the piles a scan
-- found are the piles that were drawn.
function Headings:All()
	return self.labels
end

function Headings:Subs()
	return self.subs
end
