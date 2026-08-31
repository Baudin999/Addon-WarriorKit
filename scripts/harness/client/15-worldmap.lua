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
