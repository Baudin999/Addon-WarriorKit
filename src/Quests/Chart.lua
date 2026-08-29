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
--------------------------------------------------------------------------

-- One dot. Five pixels, which is the smallest square that still reads as a mark
-- somebody put there rather than as a speck of the texture under it.
local PIN = 5

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
	pin.dot = ns.Fill(pin, "OVERLAY", 1, 1, 1, 1)
	pin.dot:SetAllPoints()
	-- A dark hairline round every dot. The zone art is a painting of hills and
	-- roads, so a five pixel square of any one colour lands on something the
	-- same colour somewhere in the zone, and the ring is what keeps a dot
	-- readable over sand as well as over water.
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

function Chart.New(parent, name)
	local board = setmetatable({ tiles = {}, pins = {}, width = 0, height = 0 }, Board)
	-- Named for the reason the two scrolling columns beside it are: a map that
	-- has laid itself out wrongly has to be measurable from a macro and from
	-- scripts/harness.lua, and the alternative is this file handing out a
	-- reference to its own pools.
	board.frame = CreateFrame("Frame", name, parent)
	board.canvas = CreateFrame("Frame", nil, board.frame)
	board.canvas:SetPoint("TOPLEFT")
	board.bg = ns.Fill(board.canvas, "BACKGROUND", C.sunken[1], C.sunken[2], C.sunken[3], 1)
	board.bg:SetAllPoints()
	board.edges = ns.Outline(board.canvas, C.hairline[1], C.hairline[2], C.hairline[3], 1)
	ns.EdgeSize(board.edges, ns.Pixel(board.canvas))
	return board
end

-- How wide the map is drawn. The height is not a caller's to pick: a zone has
-- the shape the client's art gives it, and a map stretched to fill a column is
-- a map whose distances are lies on one axis.
function Board:Resize(width)
	self.width = width
	self.frame:SetWidth(math.max(width, 1))
	return width
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

local function LayTiles(board, art)
	local scale = board.width / art.layer.layerWidth
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

local function Place(board, pin, point)
	local ink = INK[point.kind] or C.accent
	local size = (point.kind == Where.YOU) and PIN + 2 or PIN
	UI.Tint(pin.dot, ink)
	pin:SetSize(size, size)
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", board.canvas, "TOPLEFT",
		point.x / 100 * board.width, -(point.y / 100 * board.height))
	pin.name, pin.note = point.name, point.note
	pin:EnableMouse(point.name and true or false)
	pin:Show()
end

local function LayPins(board, points)
	for index = 1, #points do
		Place(board, Pin(board, index), points[index])
	end
	for index = #points + 1, #board.pins do
		board.pins[index]:Hide()
	end
	return #points
end

-- Draw one zone, and answer how tall it came out so the caller can put its own
-- lines under it. Nothing to draw answers zero, and the frame collapses rather
-- than leaving the last quest's map standing under the wrong heading.
function Board:Draw(map, points)
	local art = Art(map)
	if not art or self.width < 1 then
		self.height = 0
		self.canvas:Hide()
		self.frame:SetHeight(1)
		LayPins(self, {})
		return 0
	end

	self.height = UI.Round(self.frame,
		self.width * art.layer.layerHeight / art.layer.layerWidth)
	self.canvas:SetSize(self.width, math.max(self.height, 1))
	self.canvas:Show()
	self.frame:SetHeight(math.max(self.height, 1))
	LayTiles(self, art)
	LayPins(self, points or {})
	return self.height
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
