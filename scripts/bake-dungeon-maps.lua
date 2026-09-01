-- Bakes src/Dungeons/Sheets.lua out of Blizzard's own map tables.
--
--   lua5.1 scripts/bake-dungeon-maps.lua <path to a folder of wago.tools exports>
--
-- Run through scripts/bake-dungeon-maps.sh, which fetches the exports and
-- checks the result.
--
-- **Why there is a baked file at all.** Every other picture in this addon is
-- asked for: UI/Chart.lua hands C_Map a zone and gets back the size of the art
-- and the tiles it is cut into, and Map/Window.lua draws whatever comes out.
-- Ask the same thing about a dungeon on either of these two clients and the
-- answer is nothing, and it is nothing for two different reasons.
--
-- The 1.15 client has no dungeon maps in its map tree. Its UiMap table is
-- fifty four rows: a world, six continents, sixty five zones and three
-- battlegrounds, and not one node of the dungeon kind. There is nothing there
-- to ask about.
--
-- The 2.5 client has a hundred and four of them, with the right names and the
-- right parents, and files no art for a single one. Its UiMapXMapArt table has
-- seventy three rows and every one of them is a zone or a continent, so
-- GetMapArtLayers answers nothing for every dungeon in the game. It has no
-- UiMapGroupMember table either, so GetMapGroupID cannot say that the
-- Deadmines and Ironclad Cove are two floors of one place.
--
-- **The pictures are there.** Both clients ship the tiles themselves as
-- ordinary textures, twelve to a floor, under Interface\WorldMap. Nothing in
-- the client's own data points at them any more, which is why C_Map will not
-- hand them over, but a texture is drawn by path and a path still resolves.
-- That is what this file bakes: the path, the floors it is cut into, and the
-- map id each floor answers to so a mark can land on it.
--
-- **Everything here is generated.** The tiles come from Blizzard's UiMapArtTile
-- keyed through UiMapXMapArt, the floor names and their order from
-- UiMapGroupMember, the map ids and their names from the 2.5 client's own
-- UiMap, and every path is checked against the community listfile before it is
-- written. A path that does not resolve draws nothing at all and says nothing
-- about it, so a path nobody checked is a blank rectangle waiting to happen.
--
-- The editorial half is three lines long and it is the names, below.

--------------------------------------------------------------------------
-- The editorial half
--
-- The book calls a place what a player calls it, and twice that is not what
-- the client calls it.
--
-- Blackrock Spire is one place to the client and two runs to everybody else,
-- the way Scarlet Monastery is one place and four wings. The book splits it
-- and the split has no colon in it, because nobody says "Blackrock Spire:
-- Lower".
--
-- Scholomance is the client's own scar. Cataclysm replaced the instance and
-- the old map was left in the table under a name with OLD stuck on the end,
-- which is the name the 2.5 client still carries.
--------------------------------------------------------------------------

local CALLED = {
	["Lower Blackrock Spire"] = "Blackrock Spire",
	["Upper Blackrock Spire"] = "Blackrock Spire",
	["Scholomance"] = "ScholomanceOLD",
}

-- What the client files a dungeon and an orphan as. An orphan is a dungeon
-- Blizzard took out of the map tree without taking out of the table, which is
-- where Zul'Farrak, Old Hillsbrad Foothills and the Black Morass live.
local DUNGEON, ORPHAN = 4, 6

-- How the art is cut, and the only shape this addon draws. Every dungeon in
-- both clients is one style: a picture 1002 by 668 in twelve tiles of 256,
-- four across and three down. A floor that is baked as anything else is a
-- floor UI/Chart.lua would lay out wrongly, so the bake refuses it.
local WIDE, TALL, TILE, TILES = 1002, 668, 256, 12

--------------------------------------------------------------------------
-- Reading what wago.tools exported
--
-- In scripts/csv.lua, because the art bake beside this one reads the same
-- exports the same way and a second copy of a CSV reader is a second thing to
-- get wrong about quoted commas.
--------------------------------------------------------------------------

local CSV = dofile("scripts/csv.lua")
local Rows, Listing = CSV.Rows, CSV.Listing

--------------------------------------------------------------------------
-- The book
--------------------------------------------------------------------------

-- Which places the book wants a picture for, in the order it lists them. A
-- wing is the book's own label and the part before the colon is the place, so
-- the four Scarlet Monastery entries ask for one picture between them.
local function Wanted()
	local ns = { DungeonBook = {} }
	local chunk = assert(loadfile("src/Dungeons/Baked.lua"))
	chunk("WarriorKit", ns)
	local order, seen = {}, {}
	for _, dungeon in ipairs(ns.DungeonBook.DUNGEONS or {}) do
		local place = dungeon.name:match("^([^:]+)") or dungeon.name
		if not seen[place] then
			seen[place] = true
			order[#order + 1] = place
		end
	end
	return order
end

--------------------------------------------------------------------------
-- The client's maps
--------------------------------------------------------------------------

-- Every dungeon map the 2.5 client has, as the name it files it under to the
-- ids under that name.
local function Named(maps)
	local out = {}
	for _, map in ipairs(maps) do
		local kind = tonumber(map.Type)
		if kind == DUNGEON or kind == ORPHAN then
			local held = out[map.Name_lang] or {}
			held[#held + 1] = tonumber(map.ID)
			out[map.Name_lang] = held
		end
	end
	return out
end

-- Which floor of which group a map is, where Blizzard's own table says so. The
-- 2.5 client does not ship this table, which is why the answer is baked, and
-- it is read out of the build that still has it.
local function Grouped(members)
	local out = {}
	for _, row in ipairs(members) do
		out[tonumber(row.UiMapID)] = {
			name = row.Name_lang,
			at = tonumber(row.FloorIndex) or 0,
		}
	end
	return out
end

-- The floors of one place, in the order they are walked.
--
-- A place whose maps are grouped keeps only the grouped ones. Dire Maul is the
-- reason: the table carries the six wings and one older map of the whole
-- place, and the older one is a seventh floor that is really the same picture
-- again.
local function Floors(ids, groups)
	local out, any = {}, false
	for _, id in ipairs(ids) do
		if groups[id] then
			any = true
		end
	end
	for _, id in ipairs(ids) do
		if groups[id] or not any then
			out[#out + 1] = id
		end
	end
	table.sort(out, function(a, b)
		local one, two = groups[a], groups[b]
		if one and two and one.at ~= two.at then
			return one.at < two.at
		end
		return a < b
	end)
	return out
end

--------------------------------------------------------------------------
-- The art
--------------------------------------------------------------------------

-- Which art rows belong to which map, and which tiles belong to which art.
local function Art(links, tiles, styles, arts)
	local style = {}
	for _, row in ipairs(styles) do
		if tonumber(row.LayerIndex) == 0 then
			style[row.UiMapArtStyleID] = row
		end
	end
	local shape = {}
	for _, row in ipairs(arts) do
		shape[row.ID] = style[row.UiMapArtStyleID]
	end
	local held = {}
	for _, row in ipairs(tiles) do
		if tonumber(row.LayerIndex) == 0 then
			local group = held[row.UiMapArtID] or {}
			group[#group + 1] = row
			held[row.UiMapArtID] = group
		end
	end
	local out = {}
	for _, link in ipairs(links) do
		local map = tonumber(link.UiMapID)
		if not out[map] then
			out[map] = { art = link.UiMapArtID, shape = shape[link.UiMapArtID],
				tiles = held[link.UiMapArtID] }
		end
	end
	return out
end

-- The twelve tiles of one map, in reading order, as the paths they are filed
-- under. Nothing at all where the shape is not the one shape this addon draws.
local function Paths(art, listing)
	if not art or not art.tiles or not art.shape then
		return nil, "no art"
	end
	local shape = art.shape
	if tonumber(shape.LayerWidth) ~= WIDE or tonumber(shape.LayerHeight) ~= TALL
		or tonumber(shape.TileWidth) ~= TILE or tonumber(shape.TileHeight) ~= TILE then
		return nil, ("cut %sx%s in tiles of %sx%s"):format(shape.LayerWidth,
			shape.LayerHeight, shape.TileWidth, shape.TileHeight)
	end
	local rows = {}
	for _, tile in ipairs(art.tiles) do
		rows[#rows + 1] = tile
	end
	table.sort(rows, function(a, b)
		if a.RowIndex ~= b.RowIndex then
			return tonumber(a.RowIndex) < tonumber(b.RowIndex)
		end
		return tonumber(a.ColIndex) < tonumber(b.ColIndex)
	end)
	if #rows ~= TILES then
		return nil, ("%d tiles"):format(#rows)
	end
	local out = {}
	for index, tile in ipairs(rows) do
		local path = listing[tile.FileDataID]
		if not path then
			return nil, ("file %s is in no listing"):format(tile.FileDataID)
		end
		out[index] = path:gsub("%.blp$", "")
	end
	return out
end

-- The one thing every floor's tiles have in common: a prefix and then one to
-- twelve. Nothing at all where they do not, which is what stops a floor whose
-- tiles are numbered some other way from being baked as a prefix and drawn as
-- eleven blanks and a corner.
local function Prefix(paths)
	local held = nil
	for index, path in ipairs(paths) do
		local tail = tostring(index)
		if path:sub(-#tail) ~= tail then
			return nil
		end
		local stem = path:sub(1, #path - #tail)
		if held and held ~= stem then
			return nil
		end
		held = stem
	end
	return held
end

-- What the tiles of one floor would be called if they were named the way the
-- classic dungeon maps are named: a folder of the place's own name, and one
-- file per tile with the floor's number in it.
--
-- The second rule and not the first. A folder guessed from a name is a guess:
-- the listfile has an upperblackrockspire folder of its own, from the map
-- Blizzard drew for that run two expansions later, and a place whose floors are
-- the old Blackrock Spire's would have taken it. So this is only reached where
-- the art table cannot answer, which on this list is Scholomance and only
-- Scholomance: Cataclysm re-cut that picture, the rows now point at tiles the
-- 2.5 client has never had, and the ones it does have are still filed under the
-- old name.
local function Convention(place, order, filed)
	local key = place:lower():gsub("[^a-z0-9]", "")
	local stem = ("interface/worldmap/%s/%s%d_"):format(key, key, order)
	for index = 1, TILES do
		if not filed[stem .. index .. ".blp"] then
			return nil
		end
	end
	return stem
end

--------------------------------------------------------------------------

local function Quote(text)
	return '"' .. text:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

-- The path as the client wants it written: its own separator, and no extension,
-- which is how every texture Blizzard names in its own code is written.
local function Texture(stem)
	return (stem:gsub("/", "\\"))
end

local function Write(handle, places, order)
	handle:write(("\nSheets.LAYER = { layerWidth = %d, layerHeight = %d, tileWidth = %d, tileHeight = %d }\n")
		:format(WIDE, TALL, TILE, TILE))
	handle:write(("Sheets.TILES = %d\n\nSheets.PLACES = {\n"):format(TILES))
	for _, place in ipairs(order) do
		handle:write(("\t[%s] = {\n"):format(Quote(place)))
		for _, floor in ipairs(places[place]) do
			handle:write(("\t\t{ map = %d, name = %s, art = %s },\n")
				:format(floor.map, Quote(floor.name), Quote(Texture(floor.art))))
		end
		handle:write("\t},\n")
	end
	handle:write("}\n")
end

--------------------------------------------------------------------------

local root = ...
if not root then
	io.stderr:write("usage: lua5.1 bake-dungeon-maps.lua <path to a folder of exports>\n")
	os.exit(2)
end
root = root:gsub("/$", "")

local function Load(name, reader)
	local held, why = reader(root .. "/" .. name)
	if not held then
		io.stderr:write(tostring(why) .. "\n")
		os.exit(1)
	end
	return held
end

local listing = Load("files.json", Listing)
local filed = {}
for _, path in pairs(listing) do
	filed[path] = true
end
local named = Named(Load("uimap.csv", Rows))
local groups = Grouped(Load("groupmembers.csv", Rows))
local art = Art(Load("xmapart.csv", Rows), Load("tiles.csv", Rows),
	Load("styles.csv", Rows), Load("arts.csv", Rows))

local complaints, places, order = {}, {}, {}
local floors = 0

for _, place in ipairs(Wanted()) do
	local called = CALLED[place] or place
	local ids = named[called]
	if not ids then
		complaints[#complaints + 1] =
			("%s: this client has no map called %q"):format(place, called)
	else
		local built = {}
		for index, id in ipairs(Floors(ids, groups)) do
			local paths, why = Paths(art[id], listing)
			local stem = paths and Prefix(paths)
			if not stem then
				stem = Convention(place, index, filed)
				why = why or "tiles that are not one prefix and one to twelve"
			end
			if not stem then
				complaints[#complaints + 1] =
					("%s floor %d (map %d): %s"):format(place, index, id, why)
			else
				local group = groups[id]
				built[#built + 1] = {
					map = id,
					name = (group and group.name ~= "" and group.name) or called,
					art = stem,
				}
			end
		end
		if #built > 0 then
			places[place] = built
			order[#order + 1] = place
			floors = floors + #built
		end
	end
end

if #complaints > 0 then
	for _, line in ipairs(complaints) do
		io.stderr:write(line .. "\n")
	end
	io.stderr:write(("%d floors did not resolve: nothing was written\n"):format(#complaints))
	os.exit(1)
end

local out = assert(io.open("src/Dungeons/Sheets.lua", "w"))
out:write([[
local ADDON, ns = ...

-- Generated by ./scripts/bake-dungeon-maps.sh. Do not hand edit.
--
-- The picture of every dungeon, as the tiles the client has for it.
--
-- Neither of these clients will answer this. The 1.15 one has no dungeon maps
-- in its map tree at all, and the 2.5 one has a hundred and four of them and
-- files art for none, so C_Map.GetMapArtLayers comes back empty on every
-- dungeon in the game. Both of them ship the tiles themselves under
-- Interface\WorldMap, twelve to a floor, and a texture is drawn by path.
--
-- So this is the join, and every part of it is read out of Blizzard's own
-- tables by scripts/bake-dungeon-maps.lua: which floors a dungeon is cut into
-- and what each is called out of UiMapGroupMember, the tiles out of
-- UiMapArtTile, and the map id each floor answers to out of the 2.5 client's
-- own UiMap, which is the id a mark you leave is filed under.
--
-- `art` is a prefix. The twelve tiles are it and one to twelve, in reading
-- order, which is the order UI/Chart.lua lays a zone's out in.

local Sheets = {}
ns.DungeonSheets = Sheets
]])
Write(out, places, order)
out:close()

print(("%d dungeons, %d floors"):format(#order, floors))
