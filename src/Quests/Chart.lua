local ADDON, ns = ...

local Chart = {}
ns.QuestChart = Chart

local UI = ns.UI
local C = UI.Color
local Where = ns.QuestWhere

--------------------------------------------------------------------------
-- The zone, drawn
--
-- Quests/Where.lua answers where a quest is as a list of coordinates. This is
-- the half that puts them on a picture, and it is the only file in the addon
-- that reads the client's map art.
--
-- **The picture is the client's own, in tiles.** A zone map is a single image
-- about a thousand pixels across, and the client does not store it that way: it
-- stores it cut into 256 pixel squares, twelve of them for a zone, and hands
-- over the list through C_Map. The last column and the last row are part
-- squares padded out to 256, so each one is drawn at its real width with the
-- padding cropped off by a texture coordinate. Draw all twelve at full size and
-- the map comes out with two seams of black through it, which is exactly what
-- it looked like before the crop was there.
--
-- **Nothing here knows what a quest is.** It takes a map id and a list of
-- points and draws them, which is what makes it the same code for the zone you
-- are standing in and the zone you have never been to. Where.lua decides which
-- points, Window.lua decides which zone.
--
-- **Every call into the client is probed and pcalled.** C_Map is not an addon's
-- to assume: this ships for two clients, one of them a build where half the
-- namespace was added later, and a quest log that raises because a map id has
-- no art is a quest log that has made the evening worse to save a rectangle.
-- Every path out of this file that cannot draw returns nothing and the window
-- writes a line instead.
--
-- **The dots are pooled and the tiles are pooled.** This client cannot destroy
-- a frame or a texture, and the map is redrawn on every click in the left
-- column, so a map that built its own would leak twelve textures and eighty
-- frames per quest. It is the same argument the two scrolling columns make one
-- file across.
--
-- **The wheel zooms, and it zooms at the cursor.** A zone drawn at the width of
-- one column is about three hundred pixels across a place that takes twenty
-- minutes to walk, which is enough to say which end of Westfall and not enough
-- to say which side of the road. So the picture is drawn inside a viewport it
-- is allowed to be bigger than, and the wheel makes it bigger. Six times is the
-- far end, which is where one of the client's 256 pixel tiles is drawn at twice
-- its own size and the art gives out.
--
-- The point under the cursor stays where it is. That is the whole of the
-- navigation and it is deliberate: a map that zoomed to its own centre would
-- need dragging as well, dragging means following the cursor, and following the
-- cursor means an OnUpdate on a window that is open all evening. Zooming at the
-- cursor is a pan and a zoom in one wheel notch and costs no ticker at all.
--
-- **The viewport grows with the zoom and the box never outruns the picture.**
-- The column has room under the map for a strip of zone names and a line of
-- text, and at rest the map takes only the height its own shape asks for and
-- leaves the rest empty. Zoom in and the box claims that space, up to the
-- height the caller says is going spare, so the wheel buys height as well as
-- scale. The box is never larger than the canvas inside it on either axis,
-- which is what keeps the picture off a scroll offset no client agrees about.
--------------------------------------------------------------------------

-- One dot, and the pale square behind it.
--
-- Five pixels was too few and it is worth writing down why. Zone art is a
-- painting of hills, roads and rivers in every colour a dot can be, and a five
-- pixel square with a one pixel border round it is a three pixel core: the same
-- size as the specks the texture is full of, and the same colours. The mark was
-- there and nobody could find it, which for the one thing the whole page exists
-- to say is the same as not drawing it.
--
-- So the dot is nine and it carries a wash of its own colour behind it. The
-- wash is what does the finding. A dot has to be looked for and a soft
-- seventeen pixel patch of blue on a green hillside does not, and where a camp
-- puts four dots inside one step the washes run together into one cloud, which
-- is the honest picture: not four things, one place with things in it.
local PIN, HALO = 9, 17

-- How much of the wash is there. Enough to lift the dot off the art and not
-- enough to hide what is under it, because the road beside the camp is half of
-- why you are looking at a map at all.
local MIST = 0.3

-- How far in the wheel will take the zone, and what one notch of it is worth.
--
-- Six is where a 256 pixel tile of the client's own art is drawn at about twice
-- its size, which is the point past which zooming buys blur rather than detail.
-- The notch is a third bigger each time, so five notches cross the whole range
-- and no single one of them loses you.
local DEEPEST, NOTCH = 6, 1.3

-- The most tiles one zone is allowed to be cut into. Every zone on these
-- clients is 1002 by 668 in squares of 256, which is four across and three
-- down; the cap is what stops a map this addon has never seen from making
-- textures until the frame runs out.
local TILES = 24

-- What each kind of place is drawn in. Blue for what is left to do, because
-- blue is the colour a control is drawn in and a place on a map is a thing to
-- go and press. Green for the hand-in, which is the same green a finished quest
-- is in down the left column. Gold for you, which is the colour of a heading
-- and is the one dot on the map that is not a fact about the quest.
local INK = {
	[Where.TODO] = C.accent,
	[Where.BACK] = C.tick,
	[Where.YOU] = C.heading,
}

--------------------------------------------------------------------------
-- What the client will say about a map
--------------------------------------------------------------------------

local function Api()
	local api = _G.C_Map
	if type(api) ~= "table" then
		return nil
	end
	return api
end

-- The layout of the art: how big the whole image is and how big one tile of it
-- is. Four numbers, and every one of them divides something below, so a zero
-- from a client that answers the shape and not the values is refused here
-- rather than raising four lines later.
local function Layer(map)
	local api = Api()
	if not api or type(api.GetMapArtLayers) ~= "function" then
		return nil
	end
	local ok, layers = pcall(api.GetMapArtLayers, map)
	if not ok or type(layers) ~= "table" or type(layers[1]) ~= "table" then
		return nil
	end
	local layer = layers[1]
	for _, side in ipairs({ "layerWidth", "layerHeight", "tileWidth", "tileHeight" }) do
		if type(layer[side]) ~= "number" or layer[side] < 1 then
			return nil
		end
	end
	return layer
end

-- The tiles themselves, in reading order: left to right, then down.
local function Files(map)
	local api = Api()
	if not api or type(api.GetMapArtLayerTextures) ~= "function" then
		return nil
	end
	local ok, files = pcall(api.GetMapArtLayerTextures, map, 1)
	if not ok or type(files) ~= "table" or #files < 1 then
		return nil
	end
	return files
end

-- Everything needed to draw one zone, or nothing at all.
local function Art(map)
	if type(map) ~= "number" then
		return nil
	end
	local layer = Layer(map)
	local files = layer and Files(map)
	if not files then
		return nil
	end
	local across = math.ceil(layer.layerWidth / layer.tileWidth)
	local down = math.ceil(layer.layerHeight / layer.tileHeight)
	if across * down > TILES or across * down > #files then
		return nil
	end
	return { layer = layer, files = files, across = across, down = down }
end

-- What the client calls a zone. Questie has its own names in its own
-- localisation and this asks the client instead, because the name over the map
-- and the name on the client's own map ought to be the same word.
function Chart.Name(map)
	local api = Api()
	if not api or type(api.GetMapInfo) ~= "function" or type(map) ~= "number" then
		return nil
	end
	local ok, info = pcall(api.GetMapInfo, map)
	if not ok or type(info) ~= "table" or type(info.name) ~= "string" then
		return nil
	end
	return info.name
end

-- Which map you are on and where you are standing on it, as the same 0 to 100
-- coordinates Questie's spawns are in. Absent on a client that will not say,
-- which draws a map with everything on it except you.
function Chart.Here()
	local api = Api()
	if not api or type(api.GetBestMapForUnit) ~= "function" then
		return nil
	end
	local ok, map = pcall(api.GetBestMapForUnit, "player")
	if not ok or type(map) ~= "number" then
		return nil
	end
	if type(api.GetPlayerMapPosition) ~= "function" then
		return map
	end
	local fine, at = pcall(api.GetPlayerMapPosition, map, "player")
	if not fine or type(at) ~= "table" or type(at.GetXY) ~= "function" then
		return map
	end
	local read, x, y = pcall(at.GetXY, at)
	if not read or type(x) ~= "number" or type(y) ~= "number" then
		return map
	end
	return map, x * 100, y * 100
end

--------------------------------------------------------------------------
-- One board
--------------------------------------------------------------------------

local Board = {}
Board.__index = Board

-- A frame that hides what its child hangs over the edge of, the frame that
-- child is, and a way to move the second inside the first.
--
-- Three paths, and the argument for each is the one UI/Scroll.lua already makes
-- one layer up. SetClipsChildren is one method on an ordinary frame and is
-- preferred where the client has it. Where it is missing a ScrollFrame clips by
-- construction, has existed since the first client, and takes its offsets on
-- two setters instead of an anchor. Where neither answers, the map is drawn and
-- nothing is hidden, which at rest is exactly the picture this file drew before
-- there was a zoom at all.
--
-- The offsets are always positive here: how far right and how far down the
-- picture has been pushed. That is the ScrollFrame's own convention, and it is
-- the reason the box is never allowed to be bigger than the canvas on either
-- axis. A negative scroll is the one number the two clients this ships for do
-- not agree about.
local function Viewport(parent)
	local port = CreateFrame("Frame", nil, parent)
	if type(port.SetClipsChildren) == "function" then
		port:SetClipsChildren(true)
		local canvas = CreateFrame("Frame", nil, port)
		canvas:SetPoint("TOPLEFT")
		return port, canvas, function(x, y)
			canvas:ClearAllPoints()
			canvas:SetPoint("TOPLEFT", port, "TOPLEFT", -x, y)
		end
	end

	local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, parent)
	if ok and scroll and type(scroll.SetScrollChild) == "function" then
		local canvas = CreateFrame("Frame", nil, scroll)
		canvas:SetPoint("TOPLEFT")
		scroll:SetScrollChild(canvas)
		return scroll, canvas, function(x, y)
			scroll:SetHorizontalScroll(x)
			scroll:SetVerticalScroll(y)
		end
	end

	local canvas = CreateFrame("Frame", nil, port)
	canvas:SetPoint("TOPLEFT")
	return port, canvas, function() end
end

-- Where the pointer is inside the box, as two fractions from 0 to 1.
--
-- Half and half where the client will not say, which zooms on the middle of the
-- picture. It is not what the player pointed at and it is the only honest
-- fallback: a fraction derived from a frame with no position on screen would
-- send the map somewhere nobody asked for and look deliberate doing it.
local function Under(board)
	local port = board.port
	local wide, tall = port:GetWidth(), port:GetHeight()
	local scale = port:GetEffectiveScale()
	local left, top = port:GetLeft(), port:GetTop()
	local ok, x, y = pcall(_G.GetCursorPosition)
	if not ok or type(x) ~= "number" or type(y) ~= "number"
		or type(scale) ~= "number" or scale <= 0
		or type(left) ~= "number" or type(top) ~= "number"
		or type(wide) ~= "number" or type(tall) ~= "number"
		or wide < 1 or tall < 1 then
		return 0.5, 0.5
	end
	return math.max(0, math.min(1, (x / scale - left) / wide)),
		math.max(0, math.min(1, (top - y / scale) / tall))
end

local function Tile(board, index)
	local tile = board.tiles[index]
	if tile then
		return tile
	end
	tile = board.canvas:CreateTexture(nil, "ARTWORK")
	UI.Crisp(tile)
	board.tiles[index] = tile
	return tile
end

-- One dot, with the hover hung once and reading whatever the dot is carrying
-- now. A dot with no name answers nothing and no box opens, which is what stops
-- the last creature's name staying on screen over a dot that is now you.
local function Pin(board, index)
	local pin = board.pins[index]
	if pin then
		return pin
	end
	pin = CreateFrame("Frame", nil, board.canvas)
	pin:SetSize(PIN, PIN)
	pin:SetFrameLevel(board.canvas:GetFrameLevel() + 2)
	-- The wash, anchored to the middle of the dot and sized once. It is a
	-- texture on the pin's own frame rather than a bigger frame behind it,
	-- because the frame is what the hover is hung on and a hover the size of the
	-- wash would name a creature you were nowhere near.
	pin.halo = ns.Fill(pin, "BACKGROUND", 1, 1, 1, MIST)
	pin.halo:SetSize(HALO, HALO)
	pin.halo:SetPoint("CENTER")
	pin.dot = ns.Fill(pin, "OVERLAY", 1, 1, 1, 1)
	pin.dot:SetAllPoints()
	-- A dark hairline round every dot. The zone art is a painting of hills and
	-- roads, so a square of any one colour lands on something the same colour
	-- somewhere in the zone, and the ring is what keeps a dot readable over sand
	-- as well as over water.
	pin.ring = ns.Outline(pin, 0, 0, 0, 0.7)
	ns.EdgeSize(pin.ring, ns.Pixel(pin))
	ns.Tip.Hang(pin, function(self)
		if not self.name then
			return nil
		end
		return { kind = "note", title = self.name, lines = { self.note } }
	end)
	board.pins[index] = pin
	return pin
end

-- The wheel, hung once on the box rather than on the picture. The dots enable
-- the mouse for their hovers and none of them enables the wheel, so a notch
-- turned with the pointer over a camp reaches this and not the camp.
local function Wheel(board)
	local port = board.port
	if type(port.EnableMouseWheel) ~= "function" then
		return false
	end
	port:EnableMouseWheel(true)
	port:SetScript("OnMouseWheel", function(_, delta)
		board:Zoom(delta, Under(board))
	end)
	return true
end

function Chart.New(parent, name)
	local board = setmetatable({
		tiles = {}, pins = {},
		width = 0, height = 0, tall = 0,
		fitWide = 0, fitTall = 0,
		zoom = 1, x = 0, y = 0,
	}, Board)
	-- Named for the reason the two scrolling columns beside it are: a map that
	-- has laid itself out wrongly has to be measurable from a macro and from
	-- scripts/harness.lua, and the alternative is this file handing out a
	-- reference to its own pools.
	board.frame = CreateFrame("Frame", name, parent)
	board.port, board.canvas, board.Move = Viewport(board.frame)
	-- Centred rather than pinned left, because a zone whose art is taller than
	-- it is wide is fitted by its height and the picture is then narrower than
	-- the column it was given. Nothing in the game is that shape and the strip
	-- of buttons under the map is anchored to this frame's corner, so the choice
	-- costs nothing and stops the strip walking inward on a zone nobody has
	-- seen yet.
	board.port:SetPoint("TOP")
	board.bg = ns.Fill(board.port, "BACKGROUND", C.sunken[1], C.sunken[2], C.sunken[3], 1)
	board.bg:SetAllPoints()
	-- Over the art rather than under it. The picture fills the box to its own
	-- edge, so a hairline on any layer below ARTWORK is a hairline the map
	-- covers, and the one thing a zoomed picture needs is a line saying where
	-- the box it is inside of ends.
	board.edges = ns.Outline(board.port, C.hairline[1], C.hairline[2], C.hairline[3], 1, "OVERLAY")
	ns.EdgeSize(board.edges, ns.Pixel(board.port))
	Wheel(board)
	return board
end

-- How wide the map may be drawn, and how much height there is going spare under
-- it. Neither is the size it comes out: a zone has the shape the client's art
-- gives it, a map stretched to fill a column is a map whose distances are lies
-- on one axis, and at rest the box takes only the height the shape asks for.
-- The spare height is what the wheel is allowed to spend.
function Board:Fit(width, tall)
	self.width = math.max(width or 0, 1)
	self.tall = math.max(tall or self.tall, 1)
	self.frame:SetWidth(self.width)
	return self.width
end

local function LayTile(board, art, index, column, row, scale)
	local layer = art.layer
	local wide = math.min(layer.tileWidth, layer.layerWidth - column * layer.tileWidth)
	local tall = math.min(layer.tileHeight, layer.layerHeight - row * layer.tileHeight)
	local tile = Tile(board, index)
	tile:SetTexture(art.files[index])
	tile:SetTexCoord(0, wide / layer.tileWidth, 0, tall / layer.tileHeight)
	tile:ClearAllPoints()
	tile:SetPoint("TOPLEFT", board.canvas, "TOPLEFT",
		column * layer.tileWidth * scale, -row * layer.tileHeight * scale)
	tile:SetSize(math.max(wide * scale, 1), math.max(tall * scale, 1))
	tile:Show()
end

local function LayTiles(board, art, wide)
	local scale = wide / art.layer.layerWidth
	local count = art.across * art.down
	for index = 1, count do
		LayTile(board, art, index, (index - 1) % art.across,
			math.floor((index - 1) / art.across), scale)
	end
	for index = count + 1, #board.tiles do
		board.tiles[index]:Hide()
	end
	return count
end

-- One dot on the canvas, which is the picture at whatever size the wheel has
-- left it. The dot itself is not scaled: a mark is a thing you look for on a
-- screen and it wants the same number of pixels at every zoom, and a wash that
-- grew with the picture would swallow the zone at six times.
local function Place(board, pin, point, wide, high)
	local ink = INK[point.kind] or C.accent
	local size = (point.kind == Where.YOU) and PIN + 2 or PIN
	UI.Tint(pin.dot, ink)
	pin.halo:SetColorTexture(ink[1], ink[2], ink[3], MIST)
	pin:SetSize(size, size)
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", board.canvas, "TOPLEFT",
		point.x / 100 * wide, -(point.y / 100 * high))
	pin.name, pin.note = point.name, point.note
	pin:EnableMouse(point.name and true or false)
	pin:Show()
end

local function LayPins(board, points, wide, high)
	for index = 1, #points do
		Place(board, Pin(board, index), points[index], wide, high)
	end
	for index = #points + 1, #board.pins do
		board.pins[index]:Hide()
	end
	return #points
end

-- Everything the zoom decides, in one place, because the wheel and a fresh
-- quest both change it and two copies of this arithmetic would drift.
--
-- The canvas is the picture at scale. The box is the canvas clipped to what the
-- column will give it, which at rest is the picture's own height and after a
-- notch or two is every pixel the caller said was spare. The offsets are how
-- far into the picture the box is looking, clamped so it never looks past the
-- edge, which is what stops the zone drifting off into the sunken colour behind
-- it when a click on another quest makes the picture smaller under a scroll
-- that was right for the last one.
local function Settle(board)
	local art = board.art
	if not art or board.fitWide < 1 then
		return 0
	end
	local wide = board.fitWide * board.zoom
	local high = board.fitTall * board.zoom
	local boxWide = math.min(board.width, wide)
	local boxHigh = math.min(board.tall, high)
	board.height = UI.Round(board.frame, boxHigh)

	board.canvas:SetSize(math.max(wide, 1), math.max(high, 1))
	board.canvas:Show()
	board.port:SetSize(math.max(boxWide, 1), math.max(board.height, 1))
	board.port:Show()
	board.frame:SetHeight(math.max(board.height, 1))

	board.x = math.max(0, math.min(board.x, wide - boxWide))
	board.y = math.max(0, math.min(board.y, high - boxHigh))
	board.Move(UI.Round(board.frame, board.x), UI.Round(board.frame, board.y))

	LayTiles(board, art, wide)
	LayPins(board, board.points or {}, wide, high)
	return board.height
end

-- Draw one zone, and answer how tall it came out so the caller can put its own
-- lines under it. Nothing to draw answers zero, and the frame collapses rather
-- than leaving the last quest's map standing under the wrong heading.
--
-- The zoom survives a redraw of the same zone and not a move to another one.
-- Clicking down the left column repaints this on every quest, and a player who
-- has zoomed into a corner of Westfall to read a road wants it still zoomed
-- when they come back to the tab; a player who has stepped to another zone is
-- looking at a different picture and has said nothing about any part of it.
function Board:Draw(map, points)
	local art = Art(map)
	if not art or self.width < 1 then
		self.art, self.points = nil, nil
		self.height, self.zoom, self.x, self.y = 0, 1, 0, 0
		-- The box goes as well as the picture inside it. It carries the sunken
		-- fill and the hairline round the map, and a frame collapsed to one
		-- pixel with a box still at the last zone's size hanging out of it is
		-- the zone strip drawn over a rectangle of nothing.
		self.canvas:Hide()
		self.port:Hide()
		self.frame:SetHeight(1)
		LayPins(self, {}, 1, 1)
		return 0
	end

	if map ~= self.map then
		self.map, self.zoom, self.x, self.y = map, 1, 0, 0
	end
	self.art, self.points = art, points or {}

	local layer = art.layer
	self.fitWide = self.width
	self.fitTall = UI.Round(self.frame, self.width * layer.layerHeight / layer.layerWidth)
	if self.fitTall > self.tall then
		self.fitTall = self.tall
		self.fitWide = UI.Round(self.frame, self.tall * layer.layerWidth / layer.layerHeight)
	end
	return Settle(self)
end

-- One notch of the wheel, about the point the pointer is over.
--
-- The fractions are where in the box that point is, and the arithmetic keeps
-- the piece of zone under them exactly where it was: read the point as a
-- fraction of the whole picture before the zoom, put it back at the same
-- fraction after, and the offsets fall out. Settle does the clamping, so
-- zooming at the very edge of the box slides rather than refusing.
function Board:Zoom(delta, atX, atY)
	if not self.art or self.fitWide < 1 then
		return self.zoom
	end
	atX, atY = atX or 0.5, atY or 0.5
	local was = self.zoom
	local now = math.max(1, math.min(DEEPEST,
		was * ((delta or 0) > 0 and NOTCH or 1 / NOTCH)))
	if now == was then
		return was
	end

	local acrossWas = math.min(self.width, self.fitWide * was)
	local downWas = math.min(self.tall, self.fitTall * was)
	local u = (self.x + atX * acrossWas) / (self.fitWide * was)
	local v = (self.y + atY * downWas) / (self.fitTall * was)

	self.zoom = now
	self.x = u * self.fitWide * now - atX * math.min(self.width, self.fitWide * now)
	self.y = v * self.fitTall * now - atY * math.min(self.tall, self.fitTall * now)
	Settle(self)
	return now
end

-- How far in the wheel has taken it. Handed out for the reason Drawn below is:
-- a zoom that did not move, or moved past its own far end, is a claim
-- scripts/harness.lua has to be able to make from outside the file.
function Board:Level()
	return self.zoom
end

-- How many dots are on the board, and how big it is. Handed out because a map
-- that drew the wrong number of places is a claim scripts/harness.lua has to be
-- able to make, and there is no answering it from outside otherwise.
function Board:Drawn()
	local shown = 0
	for index = 1, #self.pins do
		if self.pins[index]:IsShown() then
			shown = shown + 1
		end
	end
	return shown, self.width, self.height
end
