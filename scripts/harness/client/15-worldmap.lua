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
-- The two continents are in here as well as the four zones. A continent is a
-- map with art like any other and the column has a row for each of them, so a
-- fixture that gave them no picture would test the row and never the board.
local ART = {
	[1436] = true, [1429] = true, [1453] = true, [1411] = true,
	[1415] = true, [1414] = true,
}
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
	[1453] = 946,  -- Stormwind's is the cosmic map, which the column has no row for
	[1415] = 1436, -- and the left of Eastern Kingdoms is Westfall, which is the
	               -- move a continent picture is for: point at a zone, open it
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
-- Where everybody is standing
--------------------------------------------------------------------------

-- Two calls, the way the real client splits them. C_Map.GetPlayerMapPosition
-- answers a position as a fraction of whatever map it was handed, and on 2.5.6
-- it answers for you and for nobody else: the fixture used to answer it for a
-- party token as well, and certified a map that drew the party on a client
-- that did not. UnitPosition is what answers for a group member, in the
-- continent's own yards, and C_Map.GetMapPosFromWorldPos is the client turning
-- those yards into a fraction of the map it is handed. The fixture has to hold
-- both halves: who is where, and which maps will answer for a place.
--
-- The player is the quest log's own record rather than a second one here, so
-- the two files cannot drift apart about where you are standing. Everybody else
-- is set by a section and cleared by it.
local placed = {}

-- A zone answers for somebody standing in it; the continent over it answers for
-- somebody standing anywhere on it. The coordinates are the same either way,
-- which no real client does, and it does not matter: what is being tested is
-- which maps answer at all.
local function answers(at, map)
	if at.map == map then
		return true
	end
	local node = NODES[at.map]
	return (node and node.parent) == map
end

local standing = H.quests.standing

api.GetPlayerMapPosition = function(map, unit)
	if unit ~= nil and unit ~= "player" then
		return nil
	end
	if not standing or not answers(standing, map) then
		return nil
	end
	return { GetXY = function() return standing.x / 100, standing.y / 100 end }
end

-- The continent a map is on, which is what the real client calls the instance
-- a world position is in. The zone's parent is the continent in this tree.
local function continentOf(map)
	local node = NODES[map]
	while node and node.kind ~= 2 do
		map, node = node.parent, NODES[node.parent]
	end
	return node and map or nil
end

-- Yards, north-south first and east-west second, which is the order the real
-- call answers in. The map is folded into the north-south number so that the
-- conversion below can find its way back: a real client knows the zone from
-- the yards, and this one has no yards, only the section's record of where
-- somebody was stood. A caller that puts the two numbers into the vector the
-- wrong way round decodes a map that does not exist and places nobody, which
-- is the swap read back as a failure rather than as a mirrored mark.
_G.UnitPosition = function(unit)
	local at = (unit == nil or unit == "player") and standing or placed[unit]
	if not at then
		return nil
	end
	return at.map * 1000 + at.y, at.x, 0, continentOf(at.map)
end

-- The map asked for, and the place on it, where the yards are on that map's
-- continent and the map answers for the zone they are in. Nothing otherwise,
-- which is the documented shape: the call may return nothing.
api.GetMapPosFromWorldPos = function(continent, world, override)
	if type(world) ~= "table" or type(world.x) ~= "number" then
		return nil
	end
	local map = math.floor(world.x / 1000)
	local y, x = world.x - map * 1000, world.y
	if continent ~= continentOf(map) then
		return nil
	end
	local target = override or map
	if not answers({ map = map }, target) then
		return nil
	end
	return target, { GetXY = function() return x / 100, y / 100 end }
end

--------------------------------------------------------------------------
-- Where your corpse is
--------------------------------------------------------------------------

-- C_DeathInfo answers the corpse against whatever map it is handed, exactly the
-- way a unit's position is answered, and answers nothing at all while you are
-- alive. Both halves are the fixture: a section has to be able to die in one
-- zone and read the other zone's map, and it has to be able to come back.
local dead = nil

_G.C_DeathInfo = {
	GetCorpseMapPosition = function(map)
		if not dead or not answers(dead, map) then
			return nil
		end
		return { GetXY = function() return dead.x / 100, dead.y / 100 end }
	end,
}

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

-- What kind of quest each of these is, in the shape QuestieDB.GetQuestTagInfo
-- answers: the client's tag id and the word for it, and nothing at all for an
-- ordinary quest, which is most of them. Questie's wrapper is what the addon
-- asks rather than the client's own call, so the wrapper is what is modelled.
-- One quest is tagged and one deliberately is not, because a hover that prints
-- the word for every marker is as wrong as one that prints it for none.
--
-- Tag 1 is handed over as "Group", which is what the live client really said
-- when the map printed it back. The quest log's own call names the same quest
-- elite and so does the addon, so a fixture that said "Elite" here would agree
-- with the addon by handing it the answer.
local TAGS = {
	[102] = { 1, "Group" },
}

local knows = _G.QuestieLoader:ImportModule("QuestieDB")
knows.GetQuestTagInfo = function(questId)
	local tag = TAGS[questId]
	if not tag then
		return nil, nil
	end
	return tag[1], tag[2]
end

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
		data = { Id = spec.quest, Name = spec.name, Type = spec.type,
			QuestData = spec.title and { name = spec.title } or nil,
			-- The objective the marker was drawn from, in the shape
			-- QuestieQuest._DetermineIconsToDraw hangs on icon data: the
			-- sentence the log prints and the two numbers Questie keeps up to
			-- date on the client's log event. A marker with no objective on it
			-- is a quest giver or a flight master, and those have none.
			ObjectiveData = spec.step and {
				Description = spec.step,
				Collected = spec.have, Needed = spec.want,
			} or nil },
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
--
-- Each carries the Type Questie stamps on its icon data, because that word is
-- what Map/Pins.lua sorts on when a zone is fuller than the cap: an objective
-- dot is a "monster", a turn-in is a "complete", and a marker out of the manual
-- register has no Type at all.
register({ quest = 102, map = 1436, x = 30, y = 40, type = "monster",
	name = "Kobold Miner", title = "Kobold Camp",
	step = "Kobold Skin", have = 3, want = 6 })
register({ quest = 102, map = 1436, x = 30, y = 40, mini = true, type = "monster",
	name = "Kobold Miner", title = "Kobold Camp" })
register({ quest = 102, map = 1436, x = 60, y = 20, hidden = true, type = "monster",
	name = "Hidden Miner", title = "Kobold Camp" })
register({ quest = 201, map = 1429, x = 50, y = 50, type = "monster",
	name = "Hogger", title = "Wanted: Hogger" })
register({ kind = "flightMaster", id = 55, map = 1436, x = 75, y = 25,
	name = "Thor", art = "Questie/Icons/flight" })

--------------------------------------------------------------------------
-- Questie's townsfolk menu
--------------------------------------------------------------------------

-- The three lists Questie's dropdown is built from, in the shape
-- Modules/QuestieMenu/QuestieMenu.lua (v11) leaves an entry: the label in the
-- player's language, whether the profile has it on, and a function that flips
-- the profile and spawns or unloads the frames. Map/Places.lua reads nothing
-- else off an entry, and a divider is what Questie puts between the primary
-- and secondary professions.
--
-- The flip is modelled the way Questie's is, as a toggle rather than a set,
-- because that is the trap: a caller that calls it on a box already ticked
-- unticks it.
local menu = _G.QuestieLoader:ImportModule("QuestieMenu")

-- What Questie's profile holds, keyed the way townsfolkConfig is.
local townsfolk = {
	["Flight Master"] = true, ["Innkeeper"] = false, ["Mailbox"] = true,
	["Food"] = false, ["Blacksmithing"] = false, ["Cooking"] = false,
}

-- The frames a kind spawns when it goes on, so a section can see the map
-- change. One per kind, all on Westfall, named after who stands there.
local stands = {
	["Innkeeper"] = { id = 295, x = 56, y = 47, name = "Innkeeper Heather" },
	["Food"] = { id = 1500, x = 52, y = 53, name = "Vendor Wilhelm" },
}

local function flip(key)
	townsfolk[key] = not townsfolk[key]
	local stand = stands[key]
	if not stand then
		return
	end
	if townsfolk[key] then
		register({ kind = key, id = stand.id, map = 1436, x = stand.x, y = stand.y,
			name = stand.name, art = "Questie/Icons/townsfolk" })
	else
		questie.manualFrames[key] = nil
	end
end

local function entry(key)
	return {
		text = key,
		func = function() flip(key) end,
		notCheckable = false,
		checked = townsfolk[key],
		isNotRadio = true,
		keepShownOnClick = true,
	}
end

local divider = { isSeparator = true, notCheckable = true, text = "" }

menu.buildTownsfolkMenu = function()
	return { entry("Flight Master"), entry("Innkeeper"), entry("Mailbox") }
end
menu.buildVendorMenu = function()
	return { entry("Food") }
end
menu.buildProfessionMenu = function()
	return { entry("Blacksmithing"), divider, entry("Cooking") }
end

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
	-- Questie's profile for the places, so a section can read back whether a
	-- tick reached Questie rather than only this addon's own reading of it.
	townsfolk = townsfolk,
	-- The three builders taken away and put back, which is a Questie that is
	-- installed and has not built its lists, or one whose menu has moved.
	Menuless = function(gone)
		if gone then
			menu.buildTownsfolkMenu = nil
		else
			menu.buildTownsfolkMenu = function()
				return { entry("Flight Master"), entry("Innkeeper"), entry("Mailbox") }
			end
		end
	end,
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
	-- Where somebody in your group is standing, so a section can put the party
	-- on a zone, walk one of them out of it and take them all away again. A map
	-- of nothing forgets them, which is what leaving the group looks like to
	-- everything that reads a position.
	Stand = function(unit, map, x, y)
		placed[unit] = map and { map = map, x = x, y = y } or nil
		return placed[unit]
	end,
	-- Where you left your corpse, so a section can die in a zone, read the map
	-- and be resurrected. Nothing at all is being alive, which is the state
	-- every other claim in the section is made in.
	Died = function(map, x, y)
		dead = map and { map = map, x = x, y = y } or nil
		return dead
	end,
	-- More markers than one zone is allowed, so the cap can be measured. Each
	-- one is a fresh frame in its own register entry, which is the shape a
	-- zone full of objective dots really has.
	--
	-- Objective dots rather than turn-ins, because the whole of what the cap has
	-- to get right is which tier it cuts. A flood of "complete" would be a flood
	-- the sort has no reason to touch.
	Flood = function(count, map)
		for index = 1, count do
			register({ quest = 5000 + index, map = map, x = 10 + index % 80,
				y = 10 + index % 70, type = "monster",
				name = "Flooded " .. index })
		end
		return count
	end,
	-- One turn-in, dropped into a zone the flood has already filled. Named so a
	-- section can find it in the list the cap handed back, which is the only way
	-- to ask whether the question mark survived the crowd.
	TurnIn = function(map, name, quest)
		register({ quest = quest or 6001, map = map, x = 44, y = 44,
			type = "complete", name = name, title = "Something Finished" })
		return name
	end,
}
