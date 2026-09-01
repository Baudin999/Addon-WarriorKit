local ADDON, ns = ...

local Here = {}
ns.DungeonHere = Here

--------------------------------------------------------------------------
-- Which dungeon you are standing in
--
-- One question, asked when a window opens: is the place around me one of the
-- book's. Press the map key in the Deadmines and the guide opens on the
-- Deadmines, on the floor you are standing on, rather than on the shelf.
--
-- **It is answered off the map id and never off a name.** GetInstanceInfo will
-- hand back what the client calls the place, and that is the wrong string twice
-- over. It is Blizzard's own name rather than the book's, which for eight of
-- the forty is a different name: the client files the Underbog under "Coilfang:
-- The Underbog" and the Black Morass under "Opening of the Dark Portal", and
-- scripts/bake-dungeon-art.lua carries that whole list because the art bake ran
-- into it first. And it is in the player's language, so a match on English text
-- is a feature that works on one client in ten.
--
-- The map id is a number both halves already agree on. Dungeons/Sheets.lua
-- bakes one per floor out of Blizzard's own tables, and the 2.5 client hands
-- the same id back from GetBestMapForUnit while you are standing on that floor.
-- So the join is a table lookup against something already baked, and nothing
-- here has to know a single dungeon's name.
--
-- **A wing is picked off the floor you are on.** Scarlet Monastery is one place
-- with four rows in the book, because the four wings are four runs at four
-- levels, and the client has one map group for the lot. What tells them apart
-- is the floor: standing in the Library gives map 303, which is the floor the
-- bake named "Library", which is the wing after the colon in the book's own
-- "Scarlet Monastery: Library". So the floor name and the wing are matched, and
-- the right one of the four opens.
--
-- Dire Maul is the one place that will not answer that way. Its six floors are
-- named after the parts of the ruin rather than after the three runs, so
-- nothing joins "Warpwood Quarter" to "Dire Maul: West", and it lands on the
-- first wing with the floor you are on already selected. That is a page one
-- click from the right one rather than a wrong answer dressed as a right one.
--
-- **The vanilla client answers nothing, and that is the same silence the marks
-- live with.** 1.15 ships no dungeon in its map tree, so there is no id to hand
-- back and no landing: the guide opens on the shelf, which is where it opened
-- before any of this. Dungeons/Places.lua carries why that client is like that.
--------------------------------------------------------------------------

local Chart = ns.UI.Chart

-- The wing a book name carries, which is the part after the colon. Nothing at
-- all for the thirty three dungeons that are one run and one row.
local function Wing(name)
	return (name:match(":%s*(.+)$"))
end

-- Which floor of this dungeon that map id is, as an index into its floors.
local function Floor(dungeon, map)
	for index, floor in ipairs(ns.DungeonPlaces.Floors(dungeon.name)) do
		if floor.map == map then
			return index
		end
	end
	return nil
end

-- Whether this row of the book is the wing whose name the floor is wearing.
local function Wears(dungeon, at)
	local floor = ns.DungeonPlaces.Floors(dungeon.name)[at]
	local wing = Wing(dungeon.name)
	return wing ~= nil and floor ~= nil and wing == floor.name
end

--------------------------------------------------------------------------

-- The dungeon you are standing in and the floor of it you are on, or nothing at
-- all when the id belongs to no picture in the book. The map is an argument so
-- that a caller with one in hand does not ask the client twice.
function Here.Dungeon(map)
	map = map or (Chart.Here())
	if type(map) ~= "number" then
		return nil
	end
	local first, floor
	for _, dungeon in ipairs(ns.DungeonBook.All()) do
		local at = Floor(dungeon, map)
		if at and Wears(dungeon, at) then
			return dungeon, at
		end
		if at and not first then
			first, floor = dungeon, at
		end
	end
	return first, floor
end

function Here.Describe()
	local dungeon, at = Here.Dungeon()
	if not dungeon then
		return "not standing anywhere the book has a picture of"
	end
	local floor = ns.DungeonPlaces.Floors(dungeon.name)[at]
	return ("standing in %s, on %s"):format(dungeon.name,
		floor and floor.name or "a floor the bake did not name")
end
