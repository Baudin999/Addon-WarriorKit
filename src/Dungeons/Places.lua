local ADDON, ns = ...

local Places = {}
ns.DungeonPlaces = Places

--------------------------------------------------------------------------
-- Which dungeon a picture belongs to, and what it is cut into
--
-- The book knows a dungeon by an English name. A picture is a folder of tiles
-- under Interface\WorldMap. This file is the join, and Dungeons/Sheets.lua is
-- the table it reads.
--
-- **The list is written down, and it is written down because the client will
-- not say.** Every other picture in this addon is asked for: Map/Window.lua
-- hands C_Map a zone and gets back the size of the art and the tiles it is cut
-- into, and UI/Chart.lua draws whatever comes out. Ask the same question about
-- a dungeon and the answer is nothing, on both of these clients and for two
-- different reasons.
--
-- The 1.15 client has no dungeon maps in its map tree at all. Its map table is
-- fifty four rows: a world, six continents, the zones and three battlegrounds.
-- There is no node to ask about.
--
-- The 2.5 client has a hundred and four of them, named and parented correctly,
-- and files art for not one. So GetMapArtLayers answers nothing for every
-- dungeon in the game. It ships no map group table either, which is what
-- GetMapGroupID reads, so it cannot say that the Deadmines and Ironclad Cove
-- are two floors of one place.
--
-- This file used to walk the map tree for all of that, the way Map/Zones.lua
-- walks it for zones, and the walk was correct and came back empty. Both halves
-- of that are worth keeping in mind: the answer was not a bug in the walk, and
-- no walk written any other way would have done better.
--
-- **The pictures are there all the same.** Both clients ship the tiles as
-- ordinary textures, twelve to a floor, and a texture is drawn by path whether
-- or not anything in the client's own tables still points at it. So the path is
-- what is baked, by scripts/bake-dungeon-maps.sh, out of Blizzard's own tables
-- in a build that still has them. Nothing in Dungeons/Sheets.lua was typed by
-- anybody, which is the same rule Dungeons/Baked.lua is held to and it is here
-- for the same reason: a path nobody generated is a path somebody remembered,
-- and a texture path that does not resolve draws nothing at all and says
-- nothing about it.
--
-- **A dungeon is several floors.** Blizzard cuts an instance into floors and
-- the strip under the picture steps between them, which is the same strip the
-- quest log puts under a quest that spans two zones. The floors and their names
-- are baked as well, because the table the client would answer them out of is
-- one of the tables it does not ship.
--
-- **The names are matched on the part before the colon.** The book calls one of
-- them "Scarlet Monastery: Library", because that is what a player calls it and
-- because the four wings are four different runs at four different levels. The
-- place is one picture in four floors, so the wing is the book's label and the
-- part before the colon is what binds.
--
-- **The map id is still the client's.** A mark is filed under the id of the
-- floor it was looted on, so that id is baked beside the picture, out of the
-- 2.5 client's own map table. On that client it is the id handed back while you
-- are standing there, which is what puts a looted mark on the right floor. On
-- the 1.15 client it is an id nothing will ever answer, so that client draws
-- the picture and never a mark on it, which is what Describe says out loud.
--------------------------------------------------------------------------

local Sheets = ns.DungeonSheets

-- Built once per place and kept, because a picture cannot change while you are
-- logged in and PaintMap asks for it on every click.
local held = nil

--------------------------------------------------------------------------

-- The place a book name binds to, which is the part before the colon. The wing
-- after it is what the player calls the run and what the left column shows, and
-- there is no separate picture for it.
function Places.Place(name)
	return (name:match("^([^:]+)")) or name
end

-- One floor's picture, in the shape UI/Chart.lua draws: the size of the art and
-- the tiles it is cut into, in reading order.
local function Sheet(floor)
	local files = {}
	for index = 1, Sheets.TILES do
		files[index] = floor.art .. index
	end
	return { layer = Sheets.LAYER, files = files }
end

-- Every floor of one dungeon, in the order they are walked. Each carries the
-- map id a mark on it is filed under, what the floor is called, and the picture.
--
-- Nothing at all for a place with no picture baked, which is a real answer
-- rather than a failure: the bosses down the left and the drops down the right
-- are the whole of what a dungeon log is for, and both work without one.
function Places.Floors(name)
	local place = Places.Place(name)
	held = held or {}
	if held[place] then
		return held[place]
	end
	local out = {}
	for index, floor in ipairs(Sheets.PLACES[place] or {}) do
		out[index] = { map = floor.map, name = floor.name, sheet = Sheet(floor) }
	end
	held[place] = out
	return out
end

-- Thrown away so the next ask builds again. Nothing about the answer changes
-- while you are logged in, so this is for the harness and for a reload.
function Places.Forget()
	held = nil
	return true
end

--------------------------------------------------------------------------

-- Whether this client has a map of its own under that id.
--
-- Not needed to draw anything, and asked anyway, because it is the difference
-- between a dungeon whose marks will land where you looted them and one where
-- the only marks are the ones you put down by hand. Both draw the same picture,
-- so nothing on the screen tells them apart.
local function Known(map)
	local api = _G.C_Map
	if type(api) ~= "table" or type(api.GetMapInfo) ~= "function" then
		return false
	end
	local ok, info = pcall(api.GetMapInfo, map)
	return ok and type(info) == "table"
end

-- How many of the book's dungeons have a picture, how many floors that comes
-- to, and how many of those floors this client knows the map id of.
function Places.Count()
	local wanted, drawn, floors, known = 0, 0, 0, 0
	for _, dungeon in ipairs(ns.DungeonBook.All()) do
		wanted = wanted + 1
		local sheets = Places.Floors(dungeon.name)
		if #sheets > 0 then
			drawn = drawn + 1
		end
	end
	for _, place in pairs(Sheets.PLACES) do
		for _, floor in ipairs(place) do
			floors = floors + 1
			if Known(floor.map) then
				known = known + 1
			end
		end
	end
	return drawn, wanted, floors, known
end

function Places.Describe()
	local drawn, wanted, floors, known = Places.Count()
	if drawn == 0 then
		return "no dungeon in the book has a picture, so every one of them draws its bosses and its drops without a map"
	end
	if known == 0 then
		return ("%d of the book's %d dungeons have a picture, in %d floors, and this client knows the map id of none of them, so a boss is marked where you put the mark yourself")
			:format(drawn, wanted, floors)
	end
	return ("%d of the book's %d dungeons have a picture, in %d floors, and this client knows the map id of %d of them")
		:format(drawn, wanted, floors, known)
end
