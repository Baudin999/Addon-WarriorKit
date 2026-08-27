local ADDON, ns = ...

local UI = ns.UI

--------------------------------------------------------------------------
-- The theme
--
-- One table of colours and one table of measurements, read by every widget in
-- this layer. They are here rather than written at each site for the reason the
-- font cache is: a number repeated in twenty places is a number that drifts in
-- nineteen of them, and an interface that means to replace Blizzard's has to be
-- able to restate its whole palette in a single edit.
--
-- Every measurement is a whole number of physical pixels. That is only true
-- inside a frame ns.UI.Adopt has taken onto the grid, which is why the window
-- adopts itself and everything below assumes it. Off the grid the numbers are
-- still the right numbers, they just land on fractions of a pixel, which is the
-- look the addon had before the grid existed and is the honest degradation.
--
-- Nothing here is a saved setting yet. A theme the player edits is a table
-- merged over this one and a rebuild of every window, and the shape is ready
-- for it, but a setting nothing reads twice is a setting that rots.
--------------------------------------------------------------------------

-- Four components, the fourth optional and taken as opaque. Kept as arrays
-- rather than named fields because ns.Fill, ns.Outline and ns.Recolor all count
-- in that order already.
UI.Color = {
	window   = { 0.05, 0.05, 0.06, 0.97 },
	chrome   = { 0.10, 0.10, 0.12, 1 },
	rail     = { 0.07, 0.07, 0.09, 1 },
	edge     = { 0.22, 0.22, 0.27, 1 },
	hairline = { 0.16, 0.16, 0.19, 1 },
	sunken   = { 0.03, 0.03, 0.04, 1 },
	control  = { 0.14, 0.14, 0.17, 1 },
	hover    = { 0.21, 0.21, 0.26, 1 },
	selected = { 0.17, 0.17, 0.21, 1 },
	accent   = { 0.25, 0.62, 0.95, 1 },
	-- The first destructive control in the addon, and the only one. A button
	-- that deletes an item you cannot get back has to be a different colour
	-- from the button next to it that does nothing, and hover has its own
	-- entry because UI.Button repaints its background on the way in and out.
	danger   = { 0.40, 0.13, 0.13, 1 },
	dangerHover = { 0.57, 0.18, 0.18, 1 },
	tick     = { 0.34, 0.80, 0.44, 1 },
	-- A number that has gone the wrong way, which so far is one number: the
	-- gold an hour along the bottom of the loot feed, on an hour where the
	-- repair bill beat the drops. Its own entry rather than the danger red
	-- above, because that one is a button you can press by accident and this
	-- is a fact about your afternoon.
	loss     = { 0.86, 0.38, 0.38, 1 },
	shadow   = { 0, 0, 0, 0.55 },

	text     = { 0.87, 0.87, 0.91 },
	dim      = { 0.56, 0.56, 0.62 },
	heading  = { 1.00, 0.82, 0.20 },
	quiet    = { 0.42, 0.42, 0.47 },

	-- The line in a tooltip that tells you what to type. It was a literal in
	-- Buffs/Nag.lua, 0.55 0.72 1, one of exactly two colours that file wrote by
	-- hand, and it came here when the tooltip it was written for became
	-- UI/Tooltip.lua. Blue rather than the accent because the accent is a
	-- control that can be clicked and this is a sentence that cannot.
	hint     = { 0.55, 0.72, 1.00 },
}

-- Whole pixels, every one of them. The three font sizes are pixels too, because
-- inside an adopted frame a font size is a pixel height rather than a point.
UI.Metric = {
	hairline = 1,
	pad      = 12, -- the window edge to anything inside it
	gutter   = 8,  -- a label to the control it names
	indent   = 12, -- a row inside its section
	rowGap   = 4,  -- one row to the next
	row      = 20, -- a control row with nothing to wrap
	control  = 18, -- a control inside such a row
	check    = 14, -- the tick box, one text line tall so the two sit level
	title    = 24, -- the title bar
	tab      = 22, -- one button in the tab strip
	railRow  = 22, -- one button in the side rail
	rail     = 180, -- the folding column down the left of the options window
	-- The column of rooms down the left of the chat window. One icon wide, and
	-- that is the whole of it: a word costs sixty pixels of every line anybody
	-- said to name a room you already know by sight, and thirteen of them cost a
	-- quarter of the window. The name is in the hover.
	rooms    = 30,
	roomIcon = 18, -- the picture on one of those rows
	roomRow  = 22, -- one of those rows
	footer   = 30,
	-- The strip the chat window's line is typed in. Shorter than the footer
	-- above, which is sized for the buttons a settings window puts in it.
	entry    = 22,
	bar      = 8,  -- the scrollbar column
	thumb    = 24, -- the shortest a scroll thumb is allowed to get

	font     = 12,
	small    = 11,
	heading  = 13,
	-- A chevron or a cross in the glyph face. Two under the body size, because a
	-- Font Awesome mark fills its em box while a letter of Arial Narrow uses
	-- about two thirds of one, so matching the numbers would draw an arrow half
	-- again the height of the word beside it.
	glyph    = 10,
}

function UI.Tint(texture, color)
	texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	return texture
end

-- A filled rectangle with an optional hairline round it, which is nine tenths
-- of every surface in the interface. The edge is resized to one real pixel
-- rather than left at the one unit ns.Outline hands back, because a frame that
-- never made it onto the grid still deserves the thinnest line its scale can
-- draw.
function UI.Box(parent, fill, edge)
	local box = CreateFrame("Frame", nil, parent)
	if fill then
		box.bg = ns.Fill(box, "BACKGROUND", fill[1], fill[2], fill[3], fill[4] or 1)
		box.bg:SetAllPoints()
	end
	if edge then
		box.edges = ns.Outline(box, edge[1], edge[2], edge[3], edge[4] or 1)
		ns.EdgeSize(box.edges, ns.Pixel(box))
	end
	return box
end

-- A one pixel rule. Horizontal unless told otherwise, and always exactly one
-- pixel on whichever axis it is thin, which is the only reason this is not four
-- lines at each site.
function UI.Rule(parent, color, vertical)
	local rule = ns.Fill(parent, "ARTWORK", color[1], color[2], color[3], color[4] or 1)
	local px = ns.Pixel(parent)
	if vertical then
		rule:SetWidth(px)
	else
		rule:SetHeight(px)
	end
	return rule
end
