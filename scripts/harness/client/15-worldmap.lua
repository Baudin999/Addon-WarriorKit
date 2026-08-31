-- The world map: the client's map tree, Questie's icon frames, and the
-- window this addon puts in the attic.
--
-- Three fixtures, and each one exists because the part reads something no file
-- above this one installs.
--
-- **The tree.** C_Map answers a map's children, and Map/Zones.lua walks that
-- to build the column of zones. The shape here is the shape the client really
-- has: a cosmic map over a world over two continents over their zones, with
-- every node carrying the parent that Map/Zones.lua climbs to find the top.
-- The zones under a continent are handed over out of alphabetical order on
-- purpose, because sorting them is a claim that file makes.
--
-- The ids are the ones these two clients really use, read off Questie's own
-- generated areaIdToUiMapId, and that matters more here than anywhere else in
-- the stub: Map/Zones.lua carries a table of level ranges keyed on them, so a
-- fixture with invented ids would test the walk and never once test the table.
-- One zone is deliberately an id nothing has a row for, which is the branch
-- where the footer has to say so rather than guess.
--
-- **Questie's icon frames.** Questie draws a marker by making a frame and
-- handing it to HereBeDragons, and Map/Pins.lua reads the frames rather than
-- the picture. So the fixture is frames: one for a world marker, one for its
-- minimap twin, one Questie has fake-hidden, one in another zone, and one out
-- of the second register, which is where the flight masters and the trainers
-- go. Only two of the five belong on the zone being drawn, which is what makes
-- this worth a fixture rather than a list of points.
--
-- **Blizzard's window and the M key.** Both plain and both probed by the addon
-- before they are touched, so the cage and the key swap have something to act
-- on.

local H = ...
local region = H.region

--------------------------------------------------------------------------
-- The map tree
--------------------------------------------------------------------------

_G.Enum.UIMapType = {
	Cosmic = 0, World = 1, Continent = 2, Zone = 3,
	Dungeon = 4, Micro = 5, Orphan = 6,
}

-- name, parent, and what kind of node it is. The two continents and the five
-- zones under them, plus the world and the cosmic map over the lot.
local NODES = {
	[946] = { name = "Cosmic", kind = 0 },
	[947] = { name = "Azeroth", kind = 1, parent = 946 },
	[1415] = { name = "Eastern Kingdoms", kind = 2, parent = 947 },
	[1414] = { name = "Kalimdor", kind = 2, parent = 947 },
	-- Eastern Kingdoms, handed over out of order so the sort is measurable.
	[1436] = { name = "Westfall", kind = 3, parent = 1415 },
	[1429] = { name = "Elwynn Forest", kind = 3, parent = 1415 },
	[1453] = { name = "Stormwind City", kind = 3, parent = 1415 },
	-- Kalimdor, and the one zone this addon has no level range for.
	[1411] = { name = "Durotar", kind = 3, parent = 1414 },
	[9001] = { name = "Somewhere Else", kind = 3, parent = 1414 },
}

-- Everything under one node of one kind, at any depth, which is what the
-- client answers when allDescendants is true.
local function under(map, kind, into)
	into = into or {}
	for id, node in pairs(NODES) do
		if node.parent == map then
			if node.kind == kind then
				into[#into + 1] = { mapID = id, name = node.name, mapType = kind }
			end
			under(id, kind, into)
		end
	end
	return into
end

-- The order pairs walks a table in is not an order, and the whole point of one
-- of these fixtures is that the addon sorts what it is given. So the client's
-- answer is made stable by id, descending, which for Eastern Kingdoms is
-- Stormwind City, Westfall, Elwynn Forest: not alphabetical, and not the
-- reverse of it either.
local function children(map, kind)
	local out = under(map, kind)
	table.sort(out, function(a, b) return a.mapID > b.mapID end)
	return out
end

local api = _G.C_Map
local named = api.GetMapInfo
local layers = api.GetMapArtLayers
local tiles = api.GetMapArtLayerTextures

-- The art, in the shape 12-questlog.lua already installs it for the quest
-- log's two zones: 1002 by 668 in squares of 256. Every zone in the tree has a
-- picture except Somewhere Else, which is the branch where the board collapses
-- and the footer says the client has no picture for that zone.
local ART = { [1436] = true, [1429] = true, [1453] = true, [1411] = true }
local LAYER = {
	layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256,
}

api.GetMapInfo = function(map)
	local node = NODES[map]
	if not node then
		return named(map)
	end
	return { name = node.name, mapID = map, mapType = node.kind,
		parentMapID = node.parent or 0 }
end

api.GetMapChildrenInfo = function(map, kind, all)
	if not all or type(kind) ~= "number" then
		return {}
	end
	return children(map, kind)
end

-- What map is at a point of another map, which is what Blizzard's own map asks
-- on every click and what makes the edge of a zone a way into the one next
-- door. The client's answer comes out of a table of border strips it does not
-- otherwise hand over, so the fixture is one strip per zone rather than a real
-- border: the left tenth of a zone belongs to its neighbour and the rest of it
-- belongs to itself.
--
-- Durotar's neighbour is the zone with no picture on purpose. A click that
-- steps somewhere the client cannot draw is still a click that has to move the
-- column, and it is the one that would otherwise be found in somebody's game.
local EDGES = {
	[1436] = 1429, -- the left of Westfall is Elwynn Forest
	[1429] = 1436, -- and the left of Elwynn Forest is Westfall
	[1411] = 9001, -- the left of Durotar is Somewhere Else
	[1453] = 1415, -- and Stormwind's is the continent, which the column has no row for
}

api.GetMapInfoAtPosition = function(map, x, y)
	if type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	local into = (x < 0.1) and EDGES[map] or nil
	return api.GetMapInfo(into or map)
end

api.GetMapArtLayers = function(map)
	if not ART[map] then
		return layers(map)
	end
	return { LAYER }
end

api.GetMapArtLayerTextures = function(map, layer)
	if not ART[map] then
		return tiles(map, layer)
	end
	local files = {}
	for index = 1, 12 do
		files[index] = 700000 + map * 100 + index
	end
	return files
end

--------------------------------------------------------------------------
-- What you have uncovered, and which way you are pointing
--------------------------------------------------------------------------

-- The client's exploration tables, in the shape C_MapExplorationInfo answers
-- them: one entry per area you have walked into, each with an offset into the
-- map, a size, and the tiles it is cut into.
--
-- Westfall has three and the addon draws two of them. The one it leaves off is
-- the kind the client only paints while the pointer is over it, which is not
-- part of the resting picture on Blizzard's own map either.
--
-- The second is the reason there is a fixture at all rather than one square.
-- It is 300 by 100 in tiles of 256, so it is two across and one down, and the
-- last column is 44 pixels stored in a 64 pixel file rather than padded out to
-- a whole tile the way the base art is. A reader that cropped it against the
-- tile would draw those 44 pixels at a fifth of their width, and every edge of
-- everywhere you had been would pull towards the middle of its own patch.
local UNCOVERED = {
	[1436] = {
		{ textureWidth = 256, textureHeight = 256, offsetX = 0, offsetY = 0,
			fileDataIDs = { 800001 } },
		{ textureWidth = 300, textureHeight = 100, offsetX = 256, offsetY = 128,
			fileDataIDs = { 800002, 800003 } },
		{ textureWidth = 256, textureHeight = 256, offsetX = 512, offsetY = 0,
			isShownByMouseOver = true, fileDataIDs = { 800004 } },
	},
}

_G.C_MapExplorationInfo = {
	GetExploredMapTextures = function(map)
		return UNCOVERED[map]
	end,
}

-- Which way you are facing, in radians anticlockwise from north. Half of pi is
-- west, which is a quarter turn and the one value that cannot be confused with
-- its own negative.
local facing = 0
_G.GetPlayerFacing = function() return facing end

--------------------------------------------------------------------------
-- Questie's icon frames
--------------------------------------------------------------------------

local questie = _G.QuestieLoader:ImportModule("QuestieMap")
questie.questIdFrames = {}
questie.manualFrames = {}

-- One of Questie's frames, in the shape QuestieMap:DrawWorldIcon leaves it: the
-- map it belongs to, where on it, the texture it chose and the colour it
-- tinted, with the quest hanging off .data.
-- The counter starts a thousand up on purpose. Questie names its frames
-- QuestieFrame1, QuestieFrame2 and so on out of one pool, and
-- client/08-blizzard.lua already makes a dozen of those as the minimap pins the
-- corral has to leave alone. It runs after this file, so a counter starting at
-- one hands every marker here to that file to overwrite, and the symptom is a
-- map with no markers on it and a fixture that looks correct.
local made = 1000

local function icon(spec)
	made = made + 1
	local name = "QuestieFrame" .. made
	_G[name] = {
		x = spec.x, y = spec.y, UiMapID = spec.map,
		miniMapIcon = spec.mini, hidden = spec.hidden,
		texture = {
			r = 1, g = 0.75, b = 0.15, a = 1,
			GetTexture = function() return spec.art or "Questie/Icons/available" end,
		},
		data = { Id = spec.quest, Name = spec.name,
			QuestData = spec.title and { name = spec.title } or nil },
	}
	return name
end

-- Into the quest register, which Questie keys by frame name, or into the manual
-- one, which it keys by kind and then by id and fills by position.
local function register(spec)
	local name = icon(spec)
	if spec.kind then
		questie.manualFrames[spec.kind] = questie.manualFrames[spec.kind] or {}
		local held = questie.manualFrames[spec.kind][spec.id] or {}
		held[#held + 1] = name
		questie.manualFrames[spec.kind][spec.id] = held
		return name
	end
	local held = questie.questIdFrames[spec.quest] or {}
	held[name] = name
	questie.questIdFrames[spec.quest] = held
	return name
end

-- The five. Two of them belong on Westfall and three do not, and each of the
-- three is a different reason: it is the minimap's copy of a marker, Questie
-- has fake-hidden it, or it is in another zone altogether.
register({ quest = 102, map = 1436, x = 30, y = 40,
	name = "Kobold Miner", title = "Kobold Camp" })
register({ quest = 102, map = 1436, x = 30, y = 40, mini = true,
	name = "Kobold Miner", title = "Kobold Camp" })
register({ quest = 102, map = 1436, x = 60, y = 20, hidden = true,
	name = "Hidden Miner", title = "Kobold Camp" })
register({ quest = 201, map = 1429, x = 50, y = 50,
	name = "Hogger", title = "Wanted: Hogger" })
register({ kind = "flightMaster", id = 55, map = 1436, x = 75, y = 25,
	name = "Thor", art = "Questie/Icons/flight" })

--------------------------------------------------------------------------
-- Blizzard's window and the M key
--------------------------------------------------------------------------

_G.WorldMapFrame = region("Frame", _G.UIParent, "WorldMapFrame")

local opened = 0
_G.ToggleWorldMap = function()
	opened = opened + 1
end

--------------------------------------------------------------------------

H.worldmap = {
	nodes = NODES,
	uncovered = UNCOVERED,
	-- Which way you are pointing, so a section can turn you and read the arrow.
	Face = function(radians)
		facing = radians
		return facing
	end,
	-- How many times the client's own toggle ran. It must be none once the
	-- addon has taken the key, and it has to move again when the switch hands
	-- it back, which is the only way to prove the original was kept rather
	-- than rebuilt.
	Opened = function() return opened end,
	-- More markers than one zone is allowed, so the cap can be measured. Each
	-- one is a fresh frame in its own register entry, which is the shape a
	-- zone full of available quests really has.
	Flood = function(count, map)
		for index = 1, count do
			register({ quest = 5000 + index, map = map, x = 10 + index % 80,
				y = 10 + index % 70, name = "Flooded " .. index })
		end
		return count
	end,
}
