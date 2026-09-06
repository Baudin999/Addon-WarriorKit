local ADDON, ns = ...

local UI = ns.UI

local Chart = {}
UI.Chart = Chart

local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- A zone, drawn
--
-- The client's map art for one zone, at whatever size the caller gives it,
-- with a list of points on top and a wheel that zooms at the cursor. It is the
-- only file in the addon that reads the client's map art.
--
-- **It is in the kit because it has two callers.** It was Quests/Chart.lua,
-- built for the map behind the quest log's middle column, and its own header
-- said in its first paragraph that nothing in it knows what a quest is. The
-- world map is the second caller and it is a whole part rather than a page, so
-- the picture is a widget now: Map/Window.lua draws every zone in the game
-- with Questie's icons on it, Quests/Window.lua draws one zone with one
-- quest's places on it, and neither knows anything about the other.
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
-- **Every call into the client is probed and pcalled.** C_Map is not an addon's
-- to assume: this ships for two clients, one of them a build where half the
-- namespace was added later, and a window that raises because a map id has no
-- art is a window that has made the evening worse to save a rectangle. Every
-- path out of this file that cannot draw returns nothing and the caller writes
-- a line instead.
--
-- **The dots are pooled and the tiles are pooled.** This client cannot destroy
-- a frame or a texture, and the map is redrawn on every click in either
-- window's left column, so a map that built its own would leak twelve textures
-- and eighty frames per click. It is the same argument the quest log's two
-- scrolling columns make one file across.
--
-- **The wheel zooms, and it zooms at the cursor.** A zone drawn at the width of
-- one column is about three hundred pixels across a place that takes twenty
-- minutes to walk, which is enough to say which end of Westfall and not enough
-- to say which side of the road. So the picture is drawn inside a viewport it
-- is allowed to be bigger than, and the wheel makes it bigger. Six times is the
-- far end, which is where one of the client's 256 pixel tiles is drawn at twice
-- its own size and the art gives out.
--
-- The point under the cursor stays where it is, so one notch is a pan and a
-- zoom together. That was the whole of the navigation for a while, on the
-- argument that dragging means following the cursor and following the cursor
-- means an OnUpdate on a window that is open all evening. It is not enough. A
-- wheel notch pans towards whatever the pointer is already on, and at six times
-- the box is looking at a sixth of the zone: reading the road you have zoomed
-- in on means zooming out to find the next bit and back in again, which is the
-- gesture Blizzard's own map has never asked anybody for.
--
-- **So a drag on a zoomed picture pushes it under the box.** The tick that
-- follows the cursor lives for the length of the drag and is stopped on the
-- button coming up, which is the bargain UI/Placeable.lua already makes for the
-- other drag in the addon: an OnUpdate while a button is held is not a ticker
-- the addon has to defend, it is the gesture itself. Nothing is written unless
-- the offsets moved, and only the offsets move: the tiles, the fog and the
-- marks are placed on the canvas and the canvas is what slides.
--
-- **A click on the picture is answered by the client, not by this file.** The
-- caller hands over a function and gets back the map that was clicked and where
-- on it, as two fractions, and decides for itself what that means. It is the
-- only way the edges of a zone can be made to work: the client's zone art runs
-- over the border into whatever is next to it, and which strip of the picture
-- belongs to which neighbour is a table inside the client that only C_Map will
-- read. A caller that passes no function gets a picture the mouse goes
-- straight through, which is what the quest log's map wants and what it had.
--
-- **A drag with nothing to push moves the window it is in.** A frame that
-- answers the mouse stops the frame under it from seeing the drag, and the
-- window this board sits in is dragged from anywhere on itself rather than
-- from a bar. So a drag the picture has no room for is handed up to whichever
-- frame above this one is movable, and a drag that moved either one is not
-- also a click. Which of the two happens is decided by the picture rather than
-- by a modifier: a zone that fits its box has nowhere to go and the window
-- moves, and a zoomed one is what you meant to drag.
--
-- **The viewport grows with the zoom and the box never outruns the picture.**
-- The caller says how wide the picture may be and how much height there is
-- going spare under it. At rest the box takes only the height the zone's own
-- shape asks for and leaves the rest empty; zoom in and it claims that space up
-- to the spare. So the wheel buys height as well as scale. The box is never
-- larger than the canvas inside it on either axis, which is what keeps the
-- picture off a scroll offset no client agrees about.
--
-- **A point is a coloured square or somebody else's icon.** The quest log's
-- three kinds are named below and drawn as a square with a wash behind it. A
-- point carrying `icon` is drawn as that texture instead, at its own size and
-- with no wash and no ring, because the art is already a mark somebody
-- designed to be found on a map. That is the whole of what the world map
-- needed to reuse this file.
--
-- **A point may carry a unit, and one that does is taken again on the tick.**
-- Everything else on the picture is a fact about the zone: where a camp is, and
-- a camp does not walk. A person does, so the arrow and the party move ten
-- times a second while the board is up and the rest of the picture moves when
-- somebody asks for it. A point that names a unit the client will not place is
-- drawn nowhere rather than left off, which is what lets a mark come back on
-- when somebody walks into the zone with the map already open.
--
-- **The zone is drawn twice: dark, then the parts you have walked.** The tiles
-- above are the whole zone with nothing discovered on it, which is what the
-- client stores as the base art and is why a map drawn from tiles alone is the
-- map you had at level one for the whole game. What you have uncovered is a
-- second set of textures, one per area you have been into, and the client hands
-- them over through C_MapExplorationInfo with an offset and a size each. They
-- go over the tiles in the same layer at the next sublevel, at the same scale,
-- which is Blizzard's own arrangement on its own map. Nothing here decides what
-- you have seen; a zone you have not walked draws no pieces and stays dark,
-- which is the answer the player asked for.
--
-- **You are the client's arrow, and it turns.** A point of kind YOU is drawn as
-- Interface\WorldMap\WorldMapArrow rather than as a coloured square, rotated
-- to the direction you are facing, and it is the one mark on the board that is
-- taken again on a timer while the board is up. Everything else on the picture
-- is a fact about the zone and changes when somebody asks; where you are
-- standing changes because you walked, and a mark that only moved when the
-- window was repainted is a mark that is wrong most of the time it is on screen.
--------------------------------------------------------------------------

-- What a point is for. Three strings, because a caller keys its own data on
-- them and Quests/Where.lua takes its three constants from these rather than
-- writing the words twice.
Chart.TODO = "todo" -- something you still have to go and do
Chart.BACK = "back" -- who the thing goes back to
Chart.YOU  = "you"  -- where you are standing, which no database knows
Chart.MARK = "mark" -- a numbered place, which the dungeon log's bosses are
Chart.MATE = "mate" -- somebody else in your group, in their own class colour
Chart.DEAD = "dead" -- your corpse, which only the client knows the way back to

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

-- How big somebody else's icon is drawn. Bigger than the dot because it is a
-- picture rather than a colour: an exclamation mark at nine pixels is a yellow
-- smudge, and Questie draws its own at about this size on the client's map.
local BADGE = 14

-- Where you are standing, and which way you are pointing.
--
-- The texture and the size are the client's own, off its own map: Blizzard's
-- player pin is Interface\WorldMap\WorldMapArrow drawn at sixteen pixels, and
-- an arrow is the one mark on a map every player already knows how to read.
-- A gold square was here before and it said where you were standing without
-- saying which way you were facing, which is half of what you open a map for.
local ARROW, HEADING = "Interface\\WorldMap\\WorldMapArrow", 16

-- Where your corpse is, drawn as the client's own skull.
--
-- Blizzard's parity again, and this time it is a cell rather than a file: its
-- own map draws the corpse out of Interface\Minimap\POIIcons, the last eighth
-- of the top row of the sheet, at twenty four pixels scaled to eight tenths.
-- Same sheet, same cell, same nineteen pixels here. A skull is the mark every
-- player has run towards since the first client and nothing this addon could
-- draw instead would be read faster.
local BONES, BONING = "Interface\\Minimap\\POIIcons", 19
local CELL = { 0.875, 1, 0, 0.125 }

-- How often the arrow is taken again while the board is up.
--
-- Blizzard's own map pin does this on every frame. A tenth of a second is
-- under what anybody can see a mark jump at and is a fortieth of the work, and
-- it moves one texture and turns it: the picture, the tiles and every other
-- mark are still drawn only when somebody asks for them.
local FOLLOW = 0.1

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

-- The most pieces of uncovered ground one zone is allowed. A piece is one area
-- you have walked into, cut into tiles the same way the base art is, and the
-- busiest zone in the game is well under a hundred of them. Same bargain as the
-- cap above: a map this file has never seen draws part of itself rather than
-- making textures until the frame runs out.
local SEEN = 256

-- What each kind of place is drawn in. Blue for what is left to do, because
-- blue is the colour a control is drawn in and a place on a map is a thing to
-- go and press. Green for the hand-in, which is the same green a finished quest
-- is in down the left column. You are not in the table: you are the client's
-- own arrow rather than a colour, which is the one mark on the map that is not
-- a fact about the thing being drawn.
local INK = {
	[Chart.TODO] = C.accent,
	[Chart.BACK] = C.tick,
	[Chart.MARK] = C.accent,
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

-- The four numbers a layout is. Every one of them divides something below, so a
-- zero from a client that answers the shape and not the values is refused here
-- rather than raising four lines later.
local SIDES = { "layerWidth", "layerHeight", "tileWidth", "tileHeight" }

local function Shaped(layer)
	if type(layer) ~= "table" then
		return false
	end
	for _, side in ipairs(SIDES) do
		if type(layer[side]) ~= "number" or layer[side] < 1 then
			return false
		end
	end
	return true
end

-- The layout of the art: how big the whole image is and how big one tile of it
-- is.
local function Layer(map)
	local api = Api()
	if not api or type(api.GetMapArtLayers) ~= "function" then
		return nil
	end
	local ok, layers = pcall(api.GetMapArtLayers, map)
	if not ok or type(layers) ~= "table" or not Shaped(layers[1]) then
		return nil
	end
	return layers[1]
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

-- What you have uncovered, as the client hands it over: one entry per area you
-- have walked into, each saying where on the map it sits, how big it is, and
-- the tiles it is cut into.
--
-- Nothing at all on a client without the namespace, which draws the zone the
-- way this file drew it before there was any of this: dark, and the same dark
-- whether you have crossed it or not.
local function Uncovered(map)
	local api = _G.C_MapExplorationInfo
	if type(api) ~= "table" or type(api.GetExploredMapTextures) ~= "function" then
		return nil
	end
	local ok, pieces = pcall(api.GetExploredMapTextures, map)
	if not ok or type(pieces) ~= "table" then
		return nil
	end
	return pieces
end

-- How many tiles across and down a layout comes to, with the tiles to fill
-- them. Nothing at all where the two do not agree, which is the check that
-- stops a picture from being drawn as a grid with holes in it.
local function Cut(layer, files)
	local across = math.ceil(layer.layerWidth / layer.tileWidth)
	local down = math.ceil(layer.layerHeight / layer.tileHeight)
	if across * down > TILES or across * down > #files then
		return nil
	end
	return { layer = layer, files = files, across = across, down = down }
end

-- Everything needed to draw one picture, or nothing at all.
--
-- Two sources and the caller picks. A zone is asked for: the client is handed
-- the map id and answers the layout and the tiles. A dungeon is handed over,
-- because on both of these clients C_Map answers nothing at all about one and
-- Dungeons/Places.lua carries the argument for why. What arrives is the same
-- shape either way, so everything below this line draws them the same.
--
-- What you have uncovered is only ever asked about a zone. A dungeon has no fog
-- on either client, and asking about a map id one of them has never heard of is
-- a question with no answer.
local function Art(map, sheet)
	if type(sheet) == "table" then
		if not Shaped(sheet.layer) or type(sheet.files) ~= "table" then
			return nil
		end
		return Cut(sheet.layer, sheet.files)
	end
	if type(map) ~= "number" then
		return nil
	end
	local layer = Layer(map)
	local files = layer and Files(map)
	if not files then
		return nil
	end
	local art = Cut(layer, files)
	if art then
		art.seen = Uncovered(map)
	end
	return art
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

-- Where a unit is standing on one map, as the same 0 to 100 coordinates
-- Questie's spawns are in. Nothing at all where the client will not say.
--
-- The map is the caller's and not the unit's, which is the whole reason this
-- is a call of its own rather than Chart.Here with an argument. The client
-- answers a position as a fraction of the map it was handed, so a zone answers
-- for somebody standing in it and a continent answers for somebody standing
-- anywhere on it. One call therefore puts you on Desolace and on Kalimdor, and
-- puts the rest of the party on both.
--
-- **Two calls, because this client answers one of them for you alone.**
-- C_Map.GetPlayerMapPosition is documented as answering for the player and
-- the party, and on 2.5.6 it answers for the player. A party token comes back
-- as nothing, which drew a map with everybody on it except the people you were
-- playing with. Blizzard's own map never asks it for them: the group is placed
-- inside a C++ widget, UnitPositionFrame, that no Lua position call is behind.
--
-- What the client does answer for a group member is UnitPosition, which is
-- where they are standing in the continent's own yards, and it has answered
-- that for a party since the first Classic client: every range check on this
-- install reads it. C_Map.GetMapPosFromWorldPos is the other half, the client
-- turning those yards into a fraction of whichever map it is handed. Handed
-- the map being drawn, it answers against that map, so the zone and the
-- continent both come out of the same two calls and nothing here carries a
-- table of zone rectangles the way the libraries have to.
--
-- Only you, your party and your raid are ever answered for. That is the
-- client's rule rather than this file's, and it is the reason a map cannot
-- draw the friend who is not in your group. Neither call answers inside an
-- instance, which is the same rule and the same nothing.
local function Placed(ok, at)
	if not ok or type(at) ~= "table" or type(at.GetXY) ~= "function" then
		return nil
	end
	local read, x, y = pcall(at.GetXY, at)
	if not read or type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	-- Off the picture is not on it. What comes back is a fraction of the map's
	-- own rectangle, and anything outside that rectangle comes back as a
	-- fraction outside nought to one: a mark drawn off the edge of the board,
	-- or pinned to a corner nobody is standing in.
	if x < 0 or x > 1 or y < 0 or y > 1 then
		return nil
	end
	return x * 100, y * 100
end

-- The vectors a world position is handed over in, filled in place. Spot is on
-- the tick, ten times a second per person, and a fresh vector each time is
-- garbage on the same terms a table is. The mixin's own constructor where the
-- client has one, because that is what the call is documented to take; a bare
-- pair of fields where it does not, because that is all the mixin is.
--
-- Two of them, and the second is not a saving. Both conversions below take a
-- vector and only one of them is ever in flight, so one would do; two mean the
-- yards and the map fraction are never the same fields, and the field names
-- are the whole of what says which of the two a number is.
local function Vector()
	return type(_G.CreateVector2D) == "function" and _G.CreateVector2D(0, 0)
		or { x = 0, y = 0 }
end

local world, fraction = Vector(), Vector()

-- Somebody in your group, placed on one map by way of where they are standing
-- in the world.
--
-- UnitPosition answers north-south first and east-west second, and the vector
-- takes them in that order: the client's own conversion the other way, from
-- a map fraction to the world, hands back a vector whose x is the north-south
-- yard. Swapped, every mark lands mirrored about the diagonal and reads as
-- being placed, which is the failure this order is written down to prevent.
--
-- The map that comes back is checked against the one asked for. A client
-- that ignored the override and answered against the best map for that spot
-- would hand back a fraction of some other zone, and a fraction of the wrong
-- map is a mark in the wrong place rather than no mark.
local function Standing(api, map, unit)
	if type(api.GetMapPosFromWorldPos) ~= "function"
		or type(_G.UnitPosition) ~= "function" then
		return nil
	end
	local ok, north, east, _, continent = pcall(_G.UnitPosition, unit)
	if not ok or type(north) ~= "number" or type(east) ~= "number"
		or type(continent) ~= "number" then
		return nil
	end
	world.x, world.y = north, east
	local asked, found, at = pcall(api.GetMapPosFromWorldPos, continent, world, map)
	if not asked or found ~= map then
		return nil
	end
	return Placed(true, at)
end

function Chart.Spot(map, unit)
	local api = Api()
	if not api or type(map) ~= "number" then
		return nil
	end
	if unit ~= nil and unit ~= "player" then
		return Standing(api, map, unit)
	end
	if type(api.GetPlayerMapPosition) ~= "function" then
		return nil
	end
	return Placed(pcall(api.GetPlayerMapPosition, map, unit))
end

-- Where a place on a map is standing, in the world's own yards.
--
-- The other direction from Standing above, through the client's own call for
-- it: C_Map.GetWorldPosFromMapPos takes a map id and a fraction of that map
-- and answers the instance and a world vector. It is on 2.5.6, and it is what
-- Questie's tracker and HereBeDragons both go through on this install, which
-- is how a signature is read here rather than remembered.
--
-- **The two axes are named here because nothing in the client names them.**
-- The vector's first number grows to the north and its second grows to the
-- west, which is the frame GetPlayerFacing counts in: nought is north and the
-- number rises anticlockwise. So the bearing from one of these to another is
-- atan2 of the second difference over the first, with no sign to get wrong,
-- and that is the whole reason this answers yards and not a map fraction. A
-- map fraction is a percentage of a rectangle whose two sides are different
-- numbers of yards, and an angle taken in it is skewed by the ratio between
-- them.
--
-- Read off HereBeDragons on disk rather than from memory. Its zone to world
-- transform writes `left - width * x` for the east-west number, so that number
-- falls as you walk east and rises as you walk west, and `top - height * y`
-- for the other, so that one falls as you walk south.
--
-- The instance comes back with the pair and is the caller's to compare. Two
-- places in different instances have world coordinates that mean nothing to
-- each other, which is the same fact Questie spends half a million yards
-- saying.
function Chart.World(map, x, y)
	local api = Api()
	if not api or type(map) ~= "number" or type(x) ~= "number"
		or type(y) ~= "number" or type(api.GetWorldPosFromMapPos) ~= "function" then
		return nil
	end
	fraction.x, fraction.y = x / 100, y / 100
	local ok, instance, at = pcall(api.GetWorldPosFromMapPos, map, fraction)
	if not ok or type(instance) ~= "number" or type(at) ~= "table"
		or type(at.GetXY) ~= "function" then
		return nil
	end
	local read, north, west = pcall(at.GetXY, at)
	if not read or type(north) ~= "number" or type(west) ~= "number" then
		return nil
	end
	return north, west, instance
end

-- Where your corpse is on one map, in the same coordinates a unit is answered
-- in. Nothing at all while you are alive, and nothing on a map it is not on.
--
-- Its own namespace rather than C_Map, and asked the same way: C_DeathInfo
-- answers a position against whatever map it is handed, so the corpse lands on
-- the continent picture as well as on the zone one. This is the call Blizzard's
-- own map makes for its own corpse pin, on this client, in
-- Blizzard_SharedMapDataProviders.
--
-- The corner is refused as well as the numbers outside the rectangle. A client
-- with no corpse is meant to answer nothing, and one that answers a zeroed
-- vector instead would put a skull in the top left of every zone you opened,
-- forever. What that costs is a corpse in the first pixel of a map, which is
-- off the walkable part of every zone in the game.
function Chart.Corpse(map)
	local api = _G.C_DeathInfo
	if type(map) ~= "number" or type(api) ~= "table"
		or type(api.GetCorpseMapPosition) ~= "function" then
		return nil
	end
	local x, y = Placed(pcall(api.GetCorpseMapPosition, map))
	if not x or (x == 0 and y == 0) then
		return nil
	end
	return x, y
end

-- Which map you are on and where you are standing on it. Absent on a client
-- that will not say, which draws a map with everything on it except you.
function Chart.Here()
	local api = Api()
	if not api or type(api.GetBestMapForUnit) ~= "function" then
		return nil
	end
	local ok, map = pcall(api.GetBestMapForUnit, "player")
	if not ok or type(map) ~= "number" then
		return nil
	end
	local x, y = Chart.Spot(map, "player")
	return map, x, y
end

-- Which way you are pointing, in radians.
--
-- The client counts anticlockwise from north and SetRotation turns a texture
-- anticlockwise, so the number goes straight on with no sign to get wrong. A
-- client that will not say leaves the arrow pointing north, which is where it
-- pointed before there was a rotation at all and is the one wrong answer that
-- still looks like a map.
function Chart.Facing()
	if type(_G.GetPlayerFacing) ~= "function" then
		return 0
	end
	local ok, facing = pcall(_G.GetPlayerFacing)
	if not ok or type(facing) ~= "number" then
		return 0
	end
	return facing
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

-- Where the pointer is on the screen, in the board's own units.
--
-- Not Under, and the difference is what each one is for. Under answers a
-- fraction of the box, which is what a zoom at the cursor needs and what makes
-- a cursor at the edge of the box mean the edge of the picture. A drag is a
-- distance rather than a place: what it needs is the same number twice, a
-- frame apart, and a fraction of a box that is itself growing under the wheel
-- is not that number.
--
-- Nothing at all where the client will not say, which stops the drag rather
-- than pushing the picture to a place nobody pointed at.
local function Cursor(board)
	local scale = board.frame:GetEffectiveScale()
	local ok, x, y = pcall(_G.GetCursorPosition)
	if not ok or type(x) ~= "number" or type(y) ~= "number"
		or type(scale) ~= "number" or scale <= 0 then
		return nil
	end
	return x / scale, y / scale
end

local function Tile(board, index)
	local tile = board.tiles[index]
	if tile then
		return tile
	end
	tile = board.canvas:CreateTexture(nil, "ARTWORK", nil, 0)
	UI.Crisp(tile)
	board.tiles[index] = tile
	return tile
end

-- One piece of uncovered ground. Same layer as the tiles and one sublevel over
-- them, which is where Blizzard puts its own: the two sets are the same picture
-- at the same scale and anything that separated them by frame would be a second
-- thing to keep in step with the zoom.
local function Seen(board, index)
	local seen = board.seen[index]
	if seen then
		return seen
	end
	seen = board.canvas:CreateTexture(nil, "ARTWORK", nil, 1)
	UI.Crisp(seen)
	board.seen[index] = seen
	return seen
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
	-- Crisp for the reason a tile is: where the mark is somebody else's icon
	-- rather than a colour, it is drawn at fourteen pixels from art stored at
	-- sixteen or thirty two, and the client's own snapping smears that.
	UI.Crisp(pin.dot)
	-- A dark hairline round every dot. The zone art is a painting of hills and
	-- roads, so a square of any one colour lands on something the same colour
	-- somewhere in the zone, and the ring is what keeps a dot readable over sand
	-- as well as over water.
	pin.ring = ns.Outline(pin, 0, 0, 0, 0.7)
	ns.EdgeSize(pin.ring, ns.Pixel(pin))
	-- The number on a numbered mark, and nothing at all on the other three
	-- shapes. A dungeon's bosses are a numbered list down one column and a
	-- handful of squares on a picture, and the number is the whole of what
	-- joins the two: without it the map says there are seven places and not
	-- which of them is the third one. Drawn in the window's own background
	-- colour rather than in white, because the square under it is the accent
	-- and a dark figure on it reads at nine pixels where a pale one does not.
	pin.tag = UI.Label(pin, M.glyph, C.window, "CENTER", UI.FLAT)
	pin.tag:SetPoint("CENTER")
	UI.Wrap(pin.tag, false)
	pin.tag:Hide()
	-- One line, several, or a function that answers them when the box opens.
	-- The quest log's dots have one thing to say, the coordinate; a world map
	-- dot is somebody else's icon and carries the quest it belongs to as well as
	-- where it is. All three go through the same field so no caller has to know
	-- which shape another passes.
	--
	-- The third shape is there because one of those facts is not known when the
	-- dot is placed. Map/Pins.lua carries the case: a quest's tag arrives from
	-- Questie a second after it is first asked for, so lines written at paint
	-- time say less than the same lines written on the hover. A caller with
	-- nothing to defer passes the table and pays nothing.
	--
	-- On the dot, whatever the tooltip setting says, and above it rather than
	-- beside it. A dot is a place on a picture of a zone: which camp this is is
	-- a question about the nine pixels under the pointer, and an answer that
	-- opens in the bottom right corner of the screen leaves you moving the
	-- cursor off the map to read it and back again to be sure which dot you
	-- were on. Above because the dot is half the size of the pointer and the
	-- arrow hangs down and to the right of its own hotspot, so a box beside one
	-- opens underneath the arrow that opened it.
	ns.Tip.Hang(pin, function(self)
		if not self.name then
			return nil
		end
		local note = self.note
		if type(note) == "function" then
			note = note()
		end
		return { kind = "note", title = self.name,
			lines = (type(note) == "table") and note or { note },
			place = ns.UI.Tooltip.BESIDE, above = true }
	end)
	board.pins[index] = pin
	return pin
end

-- The wheel, hung once on the box rather than on the picture. The dots enable
-- the mouse for their hovers and none of them enables the wheel, so a notch
-- turned with the pointer over a camp reaches this and not the camp.
-- The arrow taken again while the board is on screen.
--
-- Hung on the board's own frame rather than driven from a window, because a
-- handler only runs while its frame is shown and the frame is hidden with
-- whatever page or window it is on. There is nothing to switch off and nothing
-- to leave running: close the map and the tick stops with it.
-- The board is found on its own frame rather than closed over, because a ticker
-- takes a named function and there is one board per map.
local function Aimed(_, frame)
	frame.board:Locate()
end

local function Follow(board)
	if type(board.frame.SetScript) ~= "function" then
		return false
	end
	board.frame.board = board
	UI.Ticker(board.frame, FOLLOW, "chart", Aimed)
	return true
end

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

-- Where the pointer is on the zone, as two fractions of the whole picture.
--
-- Not the same numbers Under answers, and the difference is the zoom. Under
-- says where the pointer is in the box, which is what a zoom at the cursor
-- needs; a click has to be a point on the map, and at six times the box is
-- looking at a sixth of one. So the box's own fraction is walked back through
-- the offset the picture is scrolled to and the size it is drawn at.
local function Spot(board)
	local x, y = Under(board)
	local wide, high = board.wide, board.high
	local boxWide, boxHigh = board.port:GetWidth(), board.port:GetHeight()
	if type(boxWide) ~= "number" or type(boxHigh) ~= "number"
		or wide < 1 or high < 1 then
		return x, y
	end
	return math.max(0, math.min(1, (board.x + x * boxWide) / wide)),
		math.max(0, math.min(1, (board.y + y * boxHigh) / high))
end

-- How far up the parent chain the drag is allowed to look for a window. Two
-- steps is the real depth on the map, the board's frame to the window's content
-- frame to the window, and the cap is what stops a board parented into a loop
-- climbing forever.
local CHAIN = 8

-- The movable frame this board is inside, or nothing at all. Found once at
-- build rather than on every drag: the window is built before its board is, so
-- the handlers this hands the drag to are already on it.
local function Owner(board)
	local up = board.frame
	for _ = 1, CHAIN do
		up = (type(up.GetParent) == "function") and up:GetParent() or nil
		if not up then
			return nil
		end
		if type(up.IsMovable) == "function" and up:IsMovable()
			and type(up.GetScript) == "function" and up:GetScript("OnDragStart") then
			return up
		end
	end
	return nil
end

-- One of the window's own drag handlers, run on the window. Its own scripts
-- rather than StartMoving, because the window's are what refuse a drag while
-- the frame is locked and what write down where it was let go of.
local function Hand(owner, script)
	local handler = owner and type(owner.GetScript) == "function"
		and owner:GetScript(script)
	if type(handler) ~= "function" then
		return false
	end
	handler(owner)
	return true
end

-- Whether the picture is bigger than the box it is in, which is the whole of
-- what decides between pushing the map and moving the window.
--
-- Half a unit of slack on each axis, because both numbers are the products of
-- a zoom and a fit and neither lands on a whole one. A zone at rest that
-- measured a thousandth over its box would take the drag and move by that
-- thousandth, which is a window that has stopped being draggable from its own
-- map for no reason anybody could see.
local function Room(board)
	return board.wide > board.width + 0.5 or board.high > board.tall + 0.5
end

-- Take hold of the picture: where the offsets were and where the cursor was,
-- kept so every frame of the drag is measured from the grab rather than from
-- the frame before it. Answers whether there was anything to take hold of.
--
-- Measuring from the grab is not a nicety. A drag summed frame by frame keeps
-- whatever the clamp took off at an edge, so a push into the edge of a zone and
-- back out again comes back short by however far it was pushed, and the picture
-- crawls away from the cursor over the length of one drag.
local function Grab(board)
	if not board.art or not board.pan or not Room(board) then
		return false
	end
	local x, y = Cursor(board)
	if not x then
		return false
	end
	board.grab.x, board.grab.y = board.x, board.y
	board.grab.atX, board.grab.atY = x, y
	board.pan:Start()
	return true
end

-- The button up. Answers whether it was the picture being dragged, because the
-- window's own handler has to be told the drag is over and only where it was
-- the one that started it.
local function Loose(board)
	if not board.pan or not board.pan:Running() then
		return false
	end
	board.pan:Stop()
	return true
end

-- What the drag ticks on. A named function at the top level for the reason
-- UI/Placeable.lua's is: scripts/hot.lua walks out from whatever a handler is
-- set to, and the board is found on the frame the tick hangs off rather than
-- closed over.
local function Drift(_, frame)
	frame.board:Pan()
end

-- The mouse on the box: a click that asks the caller what is under it, and a
-- drag that pushes the picture or, where it has nowhere to go, the window.
--
-- Hung only where the caller passed a function, because enabling the mouse is
-- not free of consequence: it is what stops the window under the picture from
-- seeing the click at all.
local function Clicks(board)
	local port = board.port
	if type(port.EnableMouse) ~= "function" or type(port.SetScript) ~= "function" then
		return false
	end
	port:EnableMouse(true)
	local owner = Owner(board)
	if type(port.RegisterForDrag) == "function" then
		board.frame.board = board
		board.grab = {}
		-- Every frame while the button is held, and stopped on the way out. The
		-- interval is zero because a picture that followed the cursor five times
		-- a second would be a picture that lagged behind it, and a tick that is
		-- only ever running inside a drag is one nothing has to switch off.
		board.pan = UI.Ticker(board.frame, 0, "chart", Drift)
		board.pan:Stop()
		port:RegisterForDrag("LeftButton")
		port:SetScript("OnDragStart", function()
			board.dragging = true
			if Grab(board) then
				return
			end
			Hand(owner, "OnDragStart")
		end)
		port:SetScript("OnDragStop", function()
			if Loose(board) then
				return
			end
			Hand(owner, "OnDragStop")
		end)
	end
	port:SetScript("OnMouseDown", function()
		board.dragging = false
	end)
	-- On the way up rather than the way down, so a press that turns into a drag
	-- of the window is not also a step into another zone.
	--
	-- Two buttons and they are the two directions. The left one steps into
	-- whatever is under the pointer, which at the edge of a zone is the zone
	-- next door and on a continent is the zone you pointed at. The right one
	-- steps back out to whatever holds this map, which is the move the client's
	-- own map has always had and the one this window had no gesture for at all:
	-- the column could reach a zone in one click and could not get back to the
	-- continent it is on without one.
	port:SetScript("OnMouseUp", function(_, button)
		local dragged = board.dragging
		board.dragging = false
		if dragged then
			return
		end
		if button == "RightButton" then
			board:Back()
		elseif not button or button == "LeftButton" then
			board:Tap(Spot(board))
		end
	end)
	return true
end

-- A board, and what a click on it means.
--
-- The third argument is called with the map being drawn and where on it the
-- click landed, as two fractions from the top left. The fourth is called with
-- the map alone, because stepping out of a picture is not a question about
-- where in it the pointer was. Neither is passed by the quest log, whose map is
-- a picture rather than a place you can navigate from.
function Chart.New(parent, name, onClick, onOut)
	local board = setmetatable({
		tiles = {}, seen = {}, pins = {},
		width = 0, height = 0, tall = 0,
		wide = 0, high = 0, since = 0,
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
	board.onClick = type(onClick) == "function" and onClick or nil
	board.onOut = type(onOut) == "function" and onOut or nil
	if board.onClick or board.onOut then
		Clicks(board)
	end
	Follow(board)
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

-- The uncovered pieces, laid over the tiles at the same scale.
--
-- The arithmetic is Blizzard's own and the part worth writing down is the last
-- tile of a row or a column. The base art pads a part tile out to a full 256
-- and is cropped against the tile size; these are stored in the smallest power
-- of two that will hold them instead, so the crop is against that rounded size.
-- Crop them against the tile and every edge of everywhere you have been comes
-- out squashed towards the middle of the piece.
local function Held(size)
	local file = 16
	while file < size do
		file = file * 2
	end
	return file
end

-- Where the last tile of a run ends: the remainder, and a whole tile where the
-- run divides exactly. Written this way rather than as a modulo and a zero
-- check because those are the same sentence twice.
local function Rest(size, tile)
	return (size - 1) % tile + 1
end

-- One area you have walked into, cut into tiles and put on the canvas. Answers
-- how many textures the pool has spent altogether, so the cap is counted across
-- every piece rather than inside each one.
local function LaySeen(board, layer, piece, spent, scale)
	if type(piece) ~= "table" or piece.isShownByMouseOver
		or type(piece.textureWidth) ~= "number" or type(piece.textureHeight) ~= "number"
		or type(piece.fileDataIDs) ~= "table" then
		return spent
	end
	local offX = type(piece.offsetX) == "number" and piece.offsetX or 0
	local offY = type(piece.offsetY) == "number" and piece.offsetY or 0
	local across = math.ceil(piece.textureWidth / layer.tileWidth)
	local down = math.ceil(piece.textureHeight / layer.tileHeight)
	for row = 1, down do
		local tall = (row < down) and layer.tileHeight
			or Rest(piece.textureHeight, layer.tileHeight)
		local high = (row < down) and layer.tileHeight or Held(tall)
		for column = 1, across do
			local file = piece.fileDataIDs[(row - 1) * across + column]
			if spent >= SEEN then
				return spent
			end
			if file then
				local wide = (column < across) and layer.tileWidth
					or Rest(piece.textureWidth, layer.tileWidth)
				local full = (column < across) and layer.tileWidth or Held(wide)
				spent = spent + 1
				local tile = Seen(board, spent)
				tile:SetTexture(file)
				tile:SetTexCoord(0, wide / full, 0, tall / high)
				tile:ClearAllPoints()
				tile:SetPoint("TOPLEFT", board.canvas, "TOPLEFT",
					(offX + layer.tileWidth * (column - 1)) * scale,
					-(offY + layer.tileHeight * (row - 1)) * scale)
				tile:SetSize(math.max(wide * scale, 1), math.max(tall * scale, 1))
				tile:Show()
			end
		end
	end
	return spent
end

-- Everywhere you have been in this zone. A zone you have never walked draws
-- nothing here and stays the dark picture the tiles are, which is the whole
-- point of drawing the two sets separately.
local function LaySeens(board, art, wide)
	local scale = wide / art.layer.layerWidth
	local spent = 0
	for _, piece in ipairs(art.seen or {}) do
		spent = LaySeen(board, art.layer, piece, spent, scale)
	end
	for index = spent + 1, #board.seen do
		board.seen[index]:Hide()
	end
	board.seens = spent
	return spent
end

-- A point drawn as this addon's own mark, and how big it comes out. A coloured
-- square, a wash of the same colour behind it and a dark hairline round it.
--
-- The colour and the size are the caller's where the caller says. Neither was,
-- and both had to become so for the same second caller: the dungeon log draws
-- one square per boss with the boss's number on it, which wants a bigger square
-- than a quest's camp, and it draws the boss you have selected in a different
-- colour from the other six, which is the whole of how the picture answers the
-- column. Every caller that says nothing gets exactly what it got before.
local function Square(pin, point)
	local ink = point.tint or INK[point.kind] or C.accent
	local size = point.size or PIN
	pin.dot:SetVertexColor(1, 1, 1, 1)
	UI.Tint(pin.dot, ink)
	pin.halo:SetColorTexture(ink[1], ink[2], ink[3], MIST)
	pin.halo:SetSize(size + (HALO - PIN), size + (HALO - PIN))
	pin.halo:Show()
	for index = 1, 4 do
		pin.ring[index]:Show()
	end
	return size
end

-- A point drawn as somebody else's icon, and how big it comes out.
--
-- No wash and no ring. The art is already a mark drawn to be found on a map,
-- and a black square round each of the forty Questie puts in a zone is forty
-- rectangles over the picture rather than forty things you can see.
local function Badge(pin, point)
	pin.dot:SetTexture(point.icon)
	local tint = point.tint
	if tint then
		pin.dot:SetVertexColor(tint[1], tint[2], tint[3], tint[4] or 1)
	else
		pin.dot:SetVertexColor(1, 1, 1, 1)
	end
	pin.halo:Hide()
	for index = 1, 4 do
		pin.ring[index]:Hide()
	end
	return point.size or BADGE
end

-- Which way the arrow is pointing, set on the texture rather than on the frame
-- because a frame has no rotation and the mark is one texture inside one.
--
-- Nothing is written unless you have turned. This is on the tick's path, and
-- standing still facing one way is the ordinary case for a window somebody has
-- opened to read.
local function Aim(pin)
	local facing = Chart.Facing()
	if facing ~= pin.turn and type(pin.dot.SetRotation) == "function" then
		pin.turn = facing
		pin.dot:SetRotation(facing)
	end
end

-- You, drawn as the client's own arrow.
--
-- No wash and no ring, for the reason somebody else's icon gets neither: the
-- arrow is already a shape drawn to be found on a map, and a black square round
-- it would only say where the texture ends.
local function Heading(pin)
	pin.art = ARROW
	pin.dot:SetTexture(ARROW)
	pin.dot:SetVertexColor(1, 1, 1, 1)
	pin.halo:Hide()
	for index = 1, 4 do
		pin.ring[index]:Hide()
	end
	Aim(pin)
	return HEADING
end

-- Your corpse, drawn as the client's own skull.
--
-- No wash and no ring, for the reason the arrow gets neither. The crop is the
-- whole of the difference from any other icon on this board: what is being
-- drawn is one cell of a sheet of sixty four, and a skull with no crop is the
-- entire sheet squeezed into nineteen pixels, which is a grey smudge that
-- looks like a mark somebody chose.
local function Grave(pin)
	pin.dot:SetTexture(BONES)
	pin.dot:SetTexCoord(CELL[1], CELL[2], CELL[3], CELL[4])
	pin.dot:SetVertexColor(1, 1, 1, 1)
	pin.halo:Hide()
	for index = 1, 4 do
		pin.ring[index]:Hide()
	end
	return BONING
end

-- Which of the four a point is drawn as. You first, because a point of kind
-- YOU carries no icon and would otherwise fall through to a coloured square,
-- which is what it was before.
local function Mark(pin, point)
	-- The whole of whatever texture comes next, because the pins are pooled and
	-- one of the shapes below draws a single cell out of a sheet. Written before
	-- the branch rather than inside the three that do not crop, so a shape added
	-- later cannot inherit a corner of POIIcons and be wrong in a way that reads
	-- as art.
	--
	-- Left, right, top, bottom, in that order, which is the order the client
	-- takes them in and not the order the four corners of a rectangle come to
	-- mind in. Written as 0, 0, 1, 1 this said a texture nought pixels wide and
	-- every mark on the map went out at once: placed correctly, coloured
	-- correctly and invisible. Board:Cropped is that failure made readable.
	if type(pin.dot.SetTexCoord) == "function" then
		pin.dot:SetTexCoord(0, 1, 0, 1)
	end
	if point.kind == Chart.YOU then
		return Heading(pin)
	end
	pin.art, pin.turn = nil, nil
	-- Turned back, because the pins are pooled: the dot that is a camp now may
	-- have been the arrow last zone, and nothing else on the board is ever
	-- rotated, so nothing else ever turns it back.
	--
	-- Above the icon rather than only above the square, which is where it was
	-- and is the whole of this bug. The arrow points wherever you were facing,
	-- so the mark that inherited it came out at whatever angle you happened to
	-- be standing at, and the one people saw was the exclamation mark upside
	-- down. A coloured square is a diamond when it is turned and reads as a
	-- choice; somebody else's art is simply wrong.
	if type(pin.dot.SetRotation) == "function" then
		pin.dot:SetRotation(0)
	end
	if point.kind == Chart.DEAD then
		return Grave(pin)
	end
	if point.icon then
		return Badge(pin, point)
	end
	return Square(pin, point)
end

-- One dot on the canvas, which is the picture at whatever size the wheel has
-- left it. The dot itself is not scaled: a mark is a thing you look for on a
-- screen and it wants the same number of pixels at every zoom, and a wash that
-- grew with the picture would swallow the zone at six times.
local function Place(board, pin, point, wide, high)
	local size = Mark(pin, point)
	-- Set here rather than inside one of the three shapes, because the pins are
	-- pooled: a mark that carried a number last time has to lose it when the
	-- frame comes back as somebody else's icon, and Place is the one path every
	-- shape goes through.
	pin.tag:SetShown(point.label ~= nil)
	if point.label then
		pin.tag:SetText(point.label)
	end
	pin:SetSize(size, size)
	pin.name, pin.note = point.name, point.note
	pin:EnableMouse(point.name and true or false)
	-- A point with no place is a mark that is not drawn, rather than one drawn
	-- in the corner. Only a point that names a unit can be in that state: the
	-- client answers where somebody is standing and it will not answer for
	-- somebody in an instance, on another continent, or off this picture. The
	-- mark is kept, named and turned off, and the tick puts it back the moment
	-- the client has an answer, which is how a party member walking into the
	-- zone appears on a map that has not been repainted.
	if type(point.x) ~= "number" or type(point.y) ~= "number" then
		pin:Hide()
		return
	end
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", board.canvas, "TOPLEFT",
		point.x / 100 * wide, -(point.y / 100 * high))
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

	-- Kept, because the arrow is moved between draws and the two numbers it is
	-- placed against are the picture's own size at the zoom it is at now.
	board.wide, board.high = wide, high

	LayTiles(board, art, wide)
	LaySeens(board, art, wide)
	LayPins(board, board.points or {}, wide, high)
	return board.height
end

-- Draw one place, and answer how tall it came out so the caller can put its own
-- lines under it. Nothing to draw answers zero, and the frame collapses rather
-- than leaving the last quest's map standing under the wrong heading.
--
-- `map` is the client's own id for the place and `sheet` is a picture the
-- caller brought with it. A zone passes the id alone. A dungeon passes both:
-- the picture, because neither client will answer one, and the id all the same,
-- because that is what a mark on it is filed under.
--
-- The zoom survives a redraw of the same place and not a move to another one.
-- Clicking down the left column repaints this on every quest, and a player who
-- has zoomed into a corner of Westfall to read a road wants it still zoomed
-- when they come back to the tab; a player who has stepped to another zone is
-- looking at a different picture and has said nothing about any part of it.
function Board:Draw(map, points, sheet)
	local art = Art(map, sheet)
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

-- The arrow moved to where you are standing now, and turned to face the way you
-- are facing now.
--
-- Only the arrow. Everything else on the picture is a fact about the zone, and
-- a tick that redrew the tiles or walked Questie's registers again ten times a
-- second would be paying a zone's worth of work for one texture that moved a
-- pixel.
--
-- Nothing is written unless something moved. The tick runs whether you are
-- walking or reading, and by far the most common answer is that you are in the
-- same spot facing the same way: an anchor set again costs a measure and a
-- relayout, and a comparison costs a comparison. Turning is guarded one layer
-- down, in Aim, because you can turn on the spot without moving.
--
-- The caller's own point is updated as well as the pin, because the hover under
-- the arrow says the coordinate and a coordinate from where you were standing
-- when the window opened is a wrong answer that reads as a right one.
--
-- The arrow goes off the board on a zone you are not in, and it goes without a
-- repaint: cross the border with Westfall up and the mark leaves with you
-- rather than staying at the crossing.
--
-- A local rather than the method below, because scripts/check.sh names the
-- functions an OnUpdate can reach and it names them by their declaration. What
-- is on that list is held to no unguarded widget write and no allocation, which
-- is the rule this whole function is shaped by.
--
-- Every point carrying a unit is taken again, not only you. A mark for a person
-- is the one kind on this board whose place is a fact about right now: the
-- others are where a camp is, and a camp does not walk. So the arrow and the
-- party move on the tick and the rest of the picture moves when somebody asks.
--
-- One question to the client per person per tick, which in a full raid with
-- this window open is forty of them a second. That is what Blizzard's own map
-- spends on the same picture, it is spent only while the window is up, and the
-- alternative is a party that stands still until something repaints.
local function Track(board)
	if not board.art or not board.points or board.wide < 1 then
		return false
	end
	local found = false
	for index = 1, #board.points do
		local point = board.points[index]
		local pin = board.pins[index]
		if pin and point.unit then
			found = true
			local x, y = Chart.Spot(board.map, point.unit)
			if not x then
				pin:Hide()
			elseif point.x ~= x or point.y ~= y then
				point.x, point.y = x, y
				pin.note = ("%.1f, %.1f"):format(x, y)
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", board.canvas, "TOPLEFT",
					x / 100 * board.wide, -(y / 100 * board.high))
				if point.kind == Chart.YOU then
					Aim(pin)
				end
				pin:Show()
			elseif point.kind == Chart.YOU then
				Aim(pin)
			end
		end
	end
	return found
end

-- The arrow taken again, from the tick or from outside. Answers whether there
-- was an arrow on the board to take.
function Board:Locate()
	return Track(self)
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

-- The picture pushed to an offset, without the rest of Settle.
--
-- Only the two offsets and the one call that moves the canvas. Everything
-- Settle does besides that is a size or a placement, and a pan changes neither:
-- the tiles, the fog and the marks are anchored to the canvas and the canvas is
-- what slides under the box. This is what makes a drag affordable at sixty
-- frames a second where a Settle would not be.
--
-- Clamped the same way Settle clamps, so a push past either edge slides to it
-- and stops rather than showing the colour behind the map. Answers whether
-- anything moved, which is what stops a frame in which the cursor sat still
-- from writing a point the picture is already at.
function Board:Push(x, y)
	local boxWide = math.min(self.width, self.wide)
	local boxHigh = math.min(self.tall, self.high)
	x = math.max(0, math.min(x, self.wide - boxWide))
	y = math.max(0, math.min(y, self.high - boxHigh))
	if x == self.x and y == self.y then
		return false
	end
	self.x, self.y = x, y
	self.Move(UI.Round(self.frame, x), UI.Round(self.frame, y))
	return true
end

-- One frame of a drag: wherever the cursor has gone since the grab, the picture
-- goes with it.
--
-- The signs are the difference between dragging a map and scrolling one. The
-- offsets say how far into the picture the box is looking, so a picture pulled
-- to the right is a box looking further left and x comes down. The client
-- counts the cursor upward and the offsets downward, which is why one of them
-- is a subtraction and the other is not.
function Board:Pan()
	local grab = self.grab
	local x, y = Cursor(self)
	if not grab or not x then
		return false
	end
	return self:Push(grab.x - (x - grab.atX), grab.y + (y - grab.atY))
end

-- The gesture without a cursor: the picture dragged by so many units right and
-- so many up, as the mouse would drag it.
--
-- Its own method for the reason Zoom takes a point rather than reading one:
-- what a drag does at the edge of a zoomed zone is a claim scripts/harness.lua
-- has to be able to make, and a harness has no cursor to hold down a button
-- with.
function Board:Drag(across, up)
	return self:Push(self.x - (across or 0), self.y + (up or 0))
end

-- How far into the picture the box is looking, and whether there is anywhere
-- for it to look. Handed out for the reason Level is: a drag that did nothing
-- and a drag at the far edge are the same picture from outside.
function Board:Where()
	return self.x, self.y, Room(self)
end

-- A click on the picture, given as two fractions of the zone rather than as a
-- cursor. Answers whatever the caller's own handler answered.
--
-- Its own method, and taking the point rather than reading one, for the reason
-- Zoom takes a point: what a click on a border does is a claim
-- scripts/harness.lua has to be able to make, and a harness has no cursor to
-- put anywhere.
--
-- Nothing at all where there is no picture, because a fraction of a zone that
-- is not being drawn is a fraction of nothing.
function Board:Tap(x, y)
	if type(self.onClick) ~= "function" or not self.art or not self.map then
		return nil
	end
	return self.onClick(self.map, x, y)
end

-- The step outward, which is what the right button on the picture means.
--
-- The map alone, because where in a picture you asked to leave it is not a
-- question with an answer. What is above this map is the caller's to decide:
-- this file knows what it is drawing and nothing about what holds it.
function Board:Back()
	if type(self.onOut) ~= "function" or not self.art or not self.map then
		return nil
	end
	return self.onOut(self.map)
end

-- How far in the wheel has taken it. Handed out for the reason Drawn below is:
-- a zoom that did not move, or moved past its own far end, is a claim
-- scripts/harness.lua has to be able to make from outside the file.
function Board:Level()
	return self.zoom
end

-- How many pieces of uncovered ground are on the board.
--
-- Handed out for the reason Drawn below is, and it is the one number on this
-- widget that no other number implies: a zone drawn dark and a zone drawn with
-- everywhere you have been painted on it have the same tiles, the same marks
-- and the same size, and differ only here.
function Board:Seen()
	return self.seens or 0
end

-- The arrow: what it is drawn as, and which way it is pointing. Nothing at all
-- where the board has no you on it, which is every zone but the one you are
-- standing in.
--
-- The heading rather than the position, because the position is the caller's
-- own point and it can read that; which way the arrow was turned is decided
-- here and is not readable from anywhere else.
function Board:Arrow()
	for index = 1, #(self.points or {}) do
		local pin = self.pins[index]
		if pin and pin.art and pin:IsShown() then
			return pin.art, pin:GetWidth(), pin.turn
		end
	end
	return nil
end

-- Your corpse: what it is drawn as, how big, and which cell of the sheet.
--
-- Handed out for the reason Arrow is, and the third number is the one that
-- matters. The art is one cell of a sheet of sixty four icons, so a mark that
-- lost its crop is the right texture at the right place on the right zone and
-- is a grey smudge, which is the failure no other reading here can see.
function Board:Grave()
	local points = self.points or {}
	for index = 1, #points do
		local pin = self.pins[index]
		if points[index].kind == Chart.DEAD and pin and pin:IsShown() then
			local left = type(pin.dot.GetTexCoord) == "function"
				and pin.dot:GetTexCoord() or nil
			return pin.dot:GetTexture(), pin:GetWidth(), left
		end
	end
	return nil
end

-- How many marks are cropped to nothing.
--
-- Handed out for the reason Turned is, and it catches the same kind of defect
-- from the other side. The pins are pooled and one shape on this board draws a
-- single cell of a sheet, so a crop is something a mark can inherit or be given
-- backwards, and four numbers in the wrong order is a texture with no width. A
-- mark like that is at the right place on the right zone in the right colour
-- and is not on the screen, which is invisible to every other reading here:
-- Drawn counts it, Grave names its art, and nothing says it has no width.
function Board:Cropped()
	local cropped = 0
	for index = 1, #self.pins do
		local pin = self.pins[index]
		local dot = pin.dot
		if pin:IsShown() and type(dot.GetTexCoord) == "function" then
			local left, top, _, bottom, right = dot:GetTexCoord()
			if left and (right - left == 0 or bottom - top == 0) then
				cropped = cropped + 1
			end
		end
	end
	return cropped
end

-- How many dots are on the board, and how big it is. Handed out because a map
-- that drew the wrong number of places is a claim scripts/harness.lua has to be
-- able to make, and there is no answering it from outside otherwise.
-- How many marks are drawn on their side, which should never be more than the
-- one: the arrow is the only thing on this board that is ever rotated.
--
-- Handed out for the reason Arrow is. The pins are pooled and the arrow turns
-- one of them, so a mark that came back as somebody else's icon and kept the
-- angle is a defect no other reading catches: it is the right art, at the right
-- place, on the right zone, upside down.
function Board:Turned()
	local turned = 0
	for index = 1, #self.pins do
		local pin = self.pins[index]
		local dot = pin.dot
		if pin:IsShown() and type(dot.GetRotation) == "function"
			and (dot:GetRotation() or 0) ~= 0 then
			turned = turned + 1
		end
	end
	return turned
end

-- The pointer put on the mark at `index`, as the mouse would put it, and
-- whether there was a mark there to put it on.
--
-- Handed out for the reason Turned is: where a dot's box opens is invisible to
-- every other reading, and a harness has no cursor to point at one with. It
-- hands over no pin, because the pins are a pool this file will not give out
-- and it does not have to: the box that opens carries its own owner, so a
-- caller reads the rest off the tooltip.
function Board:Hover(index)
	local pin = self.pins[index]
	if not pin or not pin:IsShown() then
		return false
	end
	local enter = pin:GetScript("OnEnter")
	if type(enter) ~= "function" then
		return false
	end
	enter(pin)
	return true
end

function Board:Drawn()
	local shown = 0
	for index = 1, #self.pins do
		if self.pins[index]:IsShown() then
			shown = shown + 1
		end
	end
	return shown, self.width, self.height
end
