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

	-- The two tones a dense list of numbers alternates between, row by row.
	--
	-- They are the accent and they are not a second name for it. The accent is a
	-- control you can press; these are the ground under a number, and the only
	-- thing either has to do is tell one row from the row under it without being
	-- read as anything. Two entries rather than one and an alpha at the call
	-- site, because the pair is the thing: change one and the stripe stops
	-- alternating, which is a decision about the palette and not about a row.
	--
	-- Low enough to be a tint over the world. The character sheet is a backdrop
	-- with no ground of its own, so these bands are the only surface its numbers
	-- have, and a band opaque enough to paint out the grass would be a panel
	-- through the middle of the page.
	band     = { 0.25, 0.62, 0.95, 0.20 },
	bandAlt  = { 0.25, 0.62, 0.95, 0.09 },

	-- Who a name belongs to. Three entries, and the mail window is what asks:
	-- a character on your own account, somebody you know, and everybody else.
	--
	-- Their own entries rather than the three colours above that happen to be
	-- the right hues. `tick` is a box you ticked, `accent` is a control you can
	-- press and `loss` is a number that went the wrong way, and none of the
	-- three is a fact about a person. A palette that says the same thing twice
	-- drifts on the first edit that meant one of them and not the other.
	--
	-- Red for a stranger is deliberate and it is not an error state. Mailing
	-- somebody you have never mailed is a thing you may well want to do; the
	-- colour is there so that doing it by accident, with a stack of ore or half
	-- your gold on the mail, is a thing you cannot do without seeing it.
	alt      = { 0.36, 0.84, 0.46, 1 },
	friend   = { 0.36, 0.66, 0.98, 1 },
	stranger = { 0.90, 0.36, 0.36, 1 },

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

-- What an item's grade is drawn in, keyed by the number the client grades on.
--
-- ITEM_QUALITY_COLORS is the client's own and would do for the numbers, but
-- every guard in UI/Feed.lua compares a colour by table identity, so a palette
-- read fresh out of the client on each row would fail every one of those guards
-- and repaint a colour that had not changed. These are stable references, which
-- is the same reason Unit/Color.lua owns its own tables.
--
-- The numbers are the client's where it will say and the game's well known ones
-- where it will not, so a client with no ITEM_QUALITY_COLORS draws the right
-- colours rather than eight greys.
--
-- Here rather than in Feeds/Loot.lua, where it was written, because the quest
-- log's reward column is a second reader and a part may not name a file outside
-- its own tree. A palette with two readers is a palette, which is what this
-- file is for.
UI.Quality = {
	[0] = { 0.62, 0.62, 0.62 },
	[1] = { 1.00, 1.00, 1.00 },
	[2] = { 0.12, 1.00, 0.00 },
	[3] = { 0.00, 0.44, 0.87 },
	[4] = { 0.64, 0.21, 0.93 },
	[5] = { 1.00, 0.50, 0.00 },
	[6] = { 0.90, 0.80, 0.50 },
	[7] = { 0.00, 0.80, 1.00 },
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
	--
	-- These six numbers are the chat window's only ones, and they are smaller
	-- than the settings window's equivalents on purpose. A settings window is
	-- opened, read and shut; a control in it is a thing you aim at once. The
	-- chat window is up all evening beside the game, and every pixel its rail,
	-- its field and its margins take is a pixel the conversation does not get.
	-- It is furniture, so it is drawn at furniture size.
	rooms    = 24,
	roomIcon = 14, -- the picture on one of those rows
	roomRow  = 18, -- one of those rows
	footer   = 30,
	-- The strip the chat window's line is typed in. Shorter than the footer
	-- above, which is sized for the buttons a settings window puts in it.
	entry    = 18,
	field    = 16, -- the box inside that strip
	-- The log's margin from the rail and from the window's own edge. Half the
	-- gutter, which is the distance from a label to the control it names and is
	-- twice what a wall of text wants around it.
	chatPad  = 4,
	bar      = 8,  -- the scrollbar column
	thumb    = 24, -- the shortest a scroll thumb is allowed to get

	font     = 12,
	small    = 11,
	heading  = 13,
	-- The count in the corner of an item square, and the only string in the
	-- addon that gets its own number. It is read at a glance across a bag of
	-- eighty four squares rather than looked at, it carries no word to guess
	-- the digits from, and it stands on a picture the addon did not paint.
	--
	-- Fourteen because it is UI.OutlineFloor exactly. Under the floor the
	-- number takes a shadow, which is one dark corner and leaves a pale 4 on a
	-- pale icon still half gone; at the floor it can take the rim instead, and
	-- a rim is dark on every side of every stroke. So this is the smallest size
	-- at which the count is legible on any icon in the game, which is what it
	-- has to be. It is also the largest that fits: three digits at fourteen is
	-- twenty pixels across a twenty seven pixel picture.
	tally    = 14,
	-- A chevron or a cross in the glyph face. Two under the body size, because a
	-- Font Awesome mark fills its em box while a letter of Arial Narrow uses
	-- about two thirds of one, so matching the numbers would draw an arrow half
	-- again the height of the word beside it.
	glyph    = 10,
}

-- How much of its own alpha a surface is drawn at, kept on the texture rather
-- than passed at every site.
--
-- A window the player has made transparent has to be transparent the whole way
-- through. The chat window is the case: its background takes the opacity
-- setting and the rail, the scroll bar and the button at the foot of the rail
-- were drawn at their own opaque alpha over it, so a window at twenty percent
-- was a pane of glass with three black rectangles floating on it.
--
-- The fraction cannot be an argument to UI.Tint, because most of the calls to
-- it are repaints: a row of the rail is retinted on the way past with the
-- cursor and on selection, a button on hover, and a site that forgot to pass
-- the fraction would paint the surface solid again on the first mouse move. So
-- it is a property of the texture, written once by whoever owns the window and
-- read by every repaint after it.
function UI.Fade(texture, fraction)
	texture.fade = fraction
	return texture
end

function UI.Tint(texture, color)
	texture:SetColorTexture(color[1], color[2], color[3],
		(color[4] or 1) * (texture.fade or 1))
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
