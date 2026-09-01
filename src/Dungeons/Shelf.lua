local ADDON, ns = ...

local Shelf = {}
ns.DungeonShelf = Shelf

local UI = ns.UI
local C, M = UI.Color, UI.Metric
local Book, Art = ns.DungeonBook, ns.DungeonArt

--------------------------------------------------------------------------
-- The shelf
--
-- The front page of the adventure guide: forty cards, one per dungeon, each
-- wearing a painting of the place, in the order a character meets them. Click
-- one and the window becomes that dungeon's bosses, its map and its drops.
-- Right click anywhere in there and you are back here.
--
-- **This replaces a column of two hundred and thirty seven rows.** The window
-- used to put every boss in the game down its left edge at once, and the
-- argument for that was a real one: the question anybody opens this window with
-- is "what should I be running now", and it is a question about the whole list
-- rather than about one dungeon. The column answered it and answered it badly.
-- Two hundred rows is four screens of scrolling, thirty six of the rows are the
-- answer and the other two hundred are names of bosses inside dungeons you have
-- not chosen yet, and a name is the thinnest possible description of a place.
--
-- A shelf answers the same question with the same information in a third of the
-- height, because a card is a picture and a picture is recognised rather than
-- read. Somebody who has run Uldaman once knows the Uldaman card at a glance
-- and will never find the word in a list of forty as fast.
--
-- **The picture is the loading screen.** Retail's adventure guide has art cut
-- for exactly this and the 2.5 client ships none of it; Dungeons/Art.lua says
-- so at length and says where the loading screens come from instead. What
-- matters here is that they are wider than they are tall in a file that is
-- square, so a card shows a band across the middle of one rather than the whole
-- of it, and the band is taken high because the subject of a painting is
-- usually above its middle.
--
-- **A card says three things over the picture.** The dungeon's name, the levels
-- it is for, and how many of its bosses you have looted. The third is the one
-- that makes the page worth opening twice: it is the only thing on the shelf
-- that changes as you play, and it turns forty cards into a list of what is
-- left.
--
-- **Everything is built once.** This client cannot destroy a frame, so cards
-- are pooled and the ones past the end are hidden, which is the same trick the
-- vendor's rack and the chat window's rail play and for the same reason.
--------------------------------------------------------------------------

-- The narrowest a card is allowed to get before the page drops a column. Wide
-- enough for the longest name in the book, which is "The Temple of Atal'Hakkar"
-- at the heading size, because a name that wraps onto two lines takes the room
-- the levels under it are drawn in.
local CARD = 190

-- How tall a card is against its width, and the air between two of them.
--
-- Wider than it is tall because that is the shape of the thing being drawn: a
-- painting of a room, seen from inside it. A square card of the same width
-- would be half again as tall and put fourteen cards on the page instead of
-- twenty.
local ASPECT, GAP = 0.56, 8

-- How much of the loading screen a card shows, as the top of the band it takes
-- and nothing else: the height follows from the card's own shape, so a card of
-- any width crops the same picture the same way.
--
-- Above the middle rather than across it. A loading screen is a painting with
-- its subject in the upper half and its foreground in the lower, and a band
-- taken across the centre of one is mostly floor.
local SKY = 0.06

-- The plate the words are drawn on, and how far the name sits above the foot of
-- the card. The plate is a flat wash rather than a gradient because a gradient
-- is a texture and the addon ships no art it does not need: three quarters of
-- an opaque black over the bottom third of a painting is legible over every one
-- of the thirty five.
local PLATE, PLATE_ALPHA = 34, 0.72

--------------------------------------------------------------------------

local canvas, cards = nil, {}
local onPick = nil

-- What one card says under the name: the levels it is for, and how much of it
-- you have seen. The second half is left off a dungeon you have never looted,
-- because "0 of 8 looted" on thirty of the forty cards is a column of noise
-- saying what the absence of the line says on its own.
local function Caption(dungeon, held)
	local levels = dungeon.low == dungeon.high and tostring(dungeon.low)
		or ("%d-%d"):format(dungeon.low, dungeon.high)
	if held == 0 then
		return ("%s  ·  %d bosses"):format(levels, #dungeon.bosses)
	end
	return ("%s  ·  %d of %d looted"):format(levels, held, #dungeon.bosses)
end

-- How many of a dungeon's bosses you have looted, which is the one thing on
-- this page that changes while you play. The caption says it and the card is
-- drawn back when it reaches the end, so it is counted once and handed to both.
local function Placed(dungeon)
	local held = 0
	for _, boss in ipairs(dungeon.bosses) do
		if Book.Where(boss.id) then
			held = held + 1
		end
	end
	return held
end

-- What a card is worth against the character reading it, in the client's own
-- experience ladder. The same ladder the boss rows are coloured on and the
-- quest log colours a quest with, read off the top of the dungeon's range: a
-- dungeon is a thing you do at a level, and the level it is done at is the one
-- you can still be killed in it at.
local function Tint(dungeon)
	return ns.Unit.Level.WorthOf(dungeon.high)
end

--------------------------------------------------------------------------

local function Card(index)
	local card = cards[index]
	if card then
		return card
	end

	card = CreateFrame("Button", nil, canvas)

	-- The card a dungeon with no picture gets, and the card every dungeon gets
	-- for the instant before its texture resolves. Sunken rather than the window
	-- colour so that an empty card still reads as a thing you can press.
	--
	-- Made before the painting and not after it. Two textures on one layer are
	-- drawn in the order they were created, so a wash made second is a wash over
	-- every card in the page.
	card.blank = ns.Fill(card, "BACKGROUND", C.sunken[1], C.sunken[2], C.sunken[3], 1)
	card.blank:SetAllPoints()

	-- BACKGROUND rather than ARTWORK, so the plate and the words above it are
	-- drawn over the painting without either having to name a sublevel.
	card.art = card:CreateTexture(nil, "BACKGROUND")
	card.art:SetAllPoints()
	UI.Crisp(card.art)

	card.plate = ns.Fill(card, "BORDER", 0, 0, 0, PLATE_ALPHA)
	card.plate:SetPoint("BOTTOMLEFT")
	card.plate:SetPoint("BOTTOMRIGHT")
	card.plate:SetHeight(PLATE)

	card.edges = ns.Outline(card, C.edge[1], C.edge[2], C.edge[3], 1)
	ns.EdgeSize(card.edges, ns.Pixel(card))

	card.name = UI.Label(card, M.heading, C.heading, "LEFT", UI.FLAT)
	card.name:SetPoint("BOTTOMLEFT", M.rowGap, PLATE - M.heading - M.rowGap)
	card.name:SetPoint("RIGHT", -M.rowGap, 0)
	UI.Wrap(card.name, false)

	card.caption = UI.Label(card, M.small, C.dim, "LEFT", UI.FLAT)
	card.caption:SetPoint("BOTTOMLEFT", M.rowGap, M.rowGap)
	card.caption:SetPoint("RIGHT", -M.rowGap, 0)
	UI.Wrap(card.caption, false)

	-- The hover is the edge rather than a wash over the picture, because a wash
	-- over a painting is a card that looks broken and an edge is a card that
	-- looks aimed at.
	card:SetScript("OnEnter", function(self)
		ns.Recolor(self.edges, C.accent)
		self.art:SetAlpha(1)
	end)
	card:SetScript("OnLeave", function(self)
		ns.Recolor(self.edges, C.edge)
		self.art:SetAlpha(self.rested or 1)
	end)
	card:SetScript("OnClick", function(self)
		if self.dungeon and onPick then
			onPick(self.dungeon)
		end
	end)

	cards[index] = card
	return card
end

-- One card filled in. The picture is set every pass rather than only when it
-- changes, because a card is reused for whichever dungeon lands on it next and
-- the two are never the same one twice running.
local function Paint(card, dungeon)
	local held = Placed(dungeon)
	card.dungeon = dungeon
	card.name:SetText(dungeon.name)
	card.caption:SetText(Caption(dungeon, held))

	local color = Tint(dungeon)
	card.caption:SetTextColor(color[1], color[2], color[3])

	local art = Art.PLACES[ns.DungeonPlaces.Place(dungeon.name)]
	card.art:SetShown(art ~= nil)
	if art then
		card.art:SetTexture(art)
		card.art:SetTexCoord(0, 1, SKY, SKY + ASPECT)
	end

	-- A dungeon you have finished is drawn back a little, which is the only
	-- state a card carries. The same statement the quest log makes about a
	-- quest you have handed in, in the same way: dimmer, still there, still
	-- something you can open.
	card.rested = held == #dungeon.bosses and 0.55 or 1
	card.art:SetAlpha(card.rested)
end

-- Where one card sits, in whole pixels. The width is handed in rather than
-- measured off the card, because the row's own arithmetic has to round the same
-- way twice: a column computed per card leaves a seam down the page wherever
-- two roundings disagree.
local function Place(card, width, height, column, line)
	card:ClearAllPoints()
	card:SetSize(width, height)
	card:SetPoint("TOPLEFT", canvas, "TOPLEFT",
		column * (width + GAP), -(line * (height + GAP)))
end

--------------------------------------------------------------------------

-- Where the shelf is drawn, and what a press on a card means. Called once,
-- before any card exists, because a card is parented to this frame when it is
-- made.
function Shelf.Attach(where, pick)
	canvas = where
	onPick = pick
	return canvas
end

-- Every card laid out at this width, and how tall the result is. The height is
-- handed back rather than written anywhere, because the thing that has to know
-- is the scroll view and the scroll view belongs to the window.
function Shelf.Paint(width)
	local columns = math.max(1, math.floor((width + GAP) / (CARD + GAP)))
	local size = UI.Round(canvas, (width - (columns - 1) * GAP) / columns)
	local height = UI.Round(canvas, size * ASPECT)

	local at = 0
	for _, dungeon in ipairs(Book.All()) do
		at = at + 1
		local card = Card(at)
		Paint(card, dungeon)
		Place(card, size, height, (at - 1) % columns, math.floor((at - 1) / columns))
		card:Show()
	end
	for index = at + 1, #cards do
		cards[index]:Hide()
	end

	local lines = math.ceil(at / math.max(columns, 1))
	return math.max(lines * height + (lines - 1) * GAP, 1)
end

--------------------------------------------------------------------------

-- The cards, for the harness. It reads them to say that what a card shows and
-- what a press on it opens are the same dungeon, which is the one claim about
-- this file that cannot be made from outside.
function Shelf.Cards()
	return cards
end

-- How many dungeons have a painting and how many the shelf draws. The gap
-- between the two is a card that is a dark rectangle with a name on it, which
-- looks like a bug and is a bake that did not reach that place.
function Shelf.Count()
	local drawn, held = 0, 0
	for _, dungeon in ipairs(Book.All()) do
		drawn = drawn + 1
		if Art.PLACES[ns.DungeonPlaces.Place(dungeon.name)] then
			held = held + 1
		end
	end
	return held, drawn
end

function Shelf.Describe()
	local held, drawn = Shelf.Count()
	if drawn == 0 then
		return "the shelf has no cards on it, which means the book is empty"
	end
	if held < drawn then
		return ("%d cards, and %d of them have no picture")
			:format(drawn, drawn - held)
	end
	return ("%d cards, each wearing that instance's own loading screen"):format(drawn)
end
