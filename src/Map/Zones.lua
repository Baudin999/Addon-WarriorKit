local ADDON, ns = ...

local Zones = {}
ns.MapZones = Zones

--------------------------------------------------------------------------
-- Every zone there is, and who each one is for
--
-- Two questions, and they have two different kinds of answer.
--
-- **Which zones exist is the client's to say.** The map is a tree: a cosmic
-- map holding a world holding continents holding zones, and C_Map will walk it.
-- Nothing here writes a list of zone names, because a list written here is a
-- list that is wrong on the client this addon was not built on and wrong in
-- every language but one. The walk is done once and kept, because the tree does
-- not change while you are logged in.
--
-- **What level a zone is for is not.** No call on either of these clients
-- answers it. The client knows a zone's name, its art, its shape and its
-- children, and has never known that Westfall is where you go at ten. Blizzard
-- draws the number on its own map from a table compiled into the client that
-- addons cannot reach.
--
-- So it is a table here, and that is worth being honest about rather than
-- dressing up. It is keyed on the map ids these two clients use, it covers
-- Azeroth and Outland, and a zone missing from it draws a footer that says so
-- rather than a range somebody guessed. The ids are read off Questie's
-- areaIdToUiMapId, which is generated from the client rather than typed, and
-- the ranges are the ones the game has shipped since 2004.
--
-- **A city has no range and that is not a gap.** Seven of them, and the footer
-- says "a city" rather than leaving the line empty, because an empty line reads
-- as a table that forgot one.
--------------------------------------------------------------------------

-- What the client calls the two kinds of node this walks for. Read off Enum
-- where the client has it and taken as the numbers it has always used where it
-- does not, because a client that answers the tree and not the enum is one that
-- would otherwise get no zones at all.
local function Kinds()
	local kinds = _G.Enum and _G.Enum.UIMapType
	if type(kinds) == "table" and type(kinds.Continent) == "number"
		and type(kinds.Zone) == "number" then
		return kinds.Continent, kinds.Zone
	end
	return 2, 3
end

-- How far up the tree the walk to the root will climb. A map's parent chain is
-- four long on these clients, zone to continent to world to cosmic, and the cap
-- is what stops a client whose root points at itself spinning here forever.
local CLIMB = 12

-- What level each zone is for. Empty means a city: somewhere with no range
-- rather than somewhere the table has forgotten.
local LEVELS = {
	-- Eastern Kingdoms
	[1426] = { 1, 10 },  -- Dun Morogh
	[1429] = { 1, 10 },  -- Elwynn Forest
	[1420] = { 1, 10 },  -- Tirisfal Glades
	[1421] = { 10, 20 }, -- Silverpine Forest
	[1432] = { 10, 20 }, -- Loch Modan
	[1436] = { 10, 20 }, -- Westfall
	[1433] = { 15, 25 }, -- Redridge Mountains
	[1424] = { 20, 30 }, -- Hillsbrad Foothills
	[1431] = { 20, 30 }, -- Duskwood
	[1437] = { 20, 30 }, -- Wetlands
	[1416] = { 30, 40 }, -- Alterac Mountains
	[1417] = { 30, 40 }, -- Arathi Highlands
	[1434] = { 30, 45 }, -- Stranglethorn Vale
	[1418] = { 35, 45 }, -- Badlands
	[1435] = { 35, 45 }, -- Swamp of Sorrows
	[1425] = { 40, 50 }, -- The Hinterlands
	[1427] = { 43, 50 }, -- Searing Gorge
	[1419] = { 45, 55 }, -- Blasted Lands
	[1428] = { 50, 58 }, -- Burning Steppes
	[1422] = { 51, 58 }, -- Western Plaguelands
	[1423] = { 53, 60 }, -- Eastern Plaguelands
	[1430] = { 55, 60 }, -- Deadwind Pass
	[1453] = {},         -- Stormwind City
	[1455] = {},         -- Ironforge
	[1458] = {},         -- Undercity
	[1941] = { 1, 10 },  -- Eversong Woods
	[1942] = { 10, 20 }, -- Ghostlands
	[1954] = {},         -- Silvermoon City

	-- Kalimdor
	[1411] = { 1, 10 },  -- Durotar
	[1412] = { 1, 10 },  -- Mulgore
	[1438] = { 1, 10 },  -- Teldrassil
	[1943] = { 1, 10 },  -- Azuremyst Isle
	[1413] = { 10, 25 }, -- The Barrens
	[1439] = { 10, 20 }, -- Darkshore
	[1950] = { 10, 20 }, -- Bloodmyst Isle
	[1442] = { 15, 27 }, -- Stonetalon Mountains
	[1440] = { 18, 30 }, -- Ashenvale
	[1441] = { 25, 35 }, -- Thousand Needles
	[1443] = { 30, 40 }, -- Desolace
	[1445] = { 35, 45 }, -- Dustwallow Marsh
	[1444] = { 40, 50 }, -- Feralas
	[1446] = { 40, 50 }, -- Tanaris
	[1447] = { 45, 55 }, -- Azshara
	[1448] = { 48, 55 }, -- Felwood
	[1449] = { 48, 55 }, -- Un'Goro Crater
	[1451] = { 55, 60 }, -- Silithus
	[1452] = { 55, 60 }, -- Winterspring
	[1450] = {},         -- Moonglade
	[1454] = {},         -- Orgrimmar
	[1456] = {},         -- Thunder Bluff
	[1457] = {},         -- Darnassus
	[1947] = {},         -- The Exodar

	-- Outland
	[1944] = { 58, 63 }, -- Hellfire Peninsula
	[1946] = { 60, 64 }, -- Zangarmarsh
	[1952] = { 62, 65 }, -- Terokkar Forest
	[1951] = { 64, 67 }, -- Nagrand
	[1949] = { 65, 68 }, -- Blade's Edge Mountains
	[1948] = { 67, 70 }, -- Shadowmoon Valley
	[1953] = { 67, 70 }, -- Netherstorm
	[1957] = { 70, 70 }, -- Isle of Quel'Danas
	[1955] = {},         -- Shattrath City
}

-- The walk, done once. Nil until the first ask, because at load the client has
-- not finished building its own map tree and an empty answer kept forever is
-- worse than an answer taken a second late.
local tree = nil

--------------------------------------------------------------------------
-- What the client will say about the tree
--------------------------------------------------------------------------

local function Api()
	local api = _G.C_Map
	if type(api) ~= "table" then
		return nil
	end
	return api
end

-- One node's own row: what it is called and what holds it.
local function Info(map)
	local api = Api()
	if not api or type(api.GetMapInfo) ~= "function" or type(map) ~= "number" then
		return nil
	end
	local ok, info = pcall(api.GetMapInfo, map)
	if not ok or type(info) ~= "table" then
		return nil
	end
	return info
end

-- Every child of one node of one kind, at any depth under it. Depth matters:
-- Outland's zones hang off the continent directly and the Blood Elf and Draenei
-- starting isles hang off a sub-map on some builds, and a walk that took only
-- the immediate children would quietly drop them.
local function Children(map, kind)
	local api = Api()
	if not api or type(api.GetMapChildrenInfo) ~= "function" then
		return {}
	end
	local ok, list = pcall(api.GetMapChildrenInfo, map, kind, true)
	if not ok or type(list) ~= "table" then
		return {}
	end
	return list
end

-- The top of the tree, climbed from wherever you are standing.
--
-- Climbed rather than named, because the id of the cosmic map is a number this
-- file would otherwise be asserting about two clients it cannot test. Where the
-- climb answers nothing useful, the two ids the game has used for the world are
-- tried in turn.
local FALLBACK = { 946, 947 }

-- As far up as the parent chain goes from where you are standing.
local function Climb()
	local api = Api()
	if not api or type(api.GetBestMapForUnit) ~= "function" then
		return nil
	end
	local ok, map = pcall(api.GetBestMapForUnit, "player")
	if not ok or type(map) ~= "number" then
		return nil
	end
	for _ = 1, CLIMB do
		local info = Info(map)
		local parent = info and info.parentMapID
		if type(parent) ~= "number" or parent < 1 or parent == map then
			return map
		end
		map = parent
	end
	return map
end

-- Whether a node is worth walking, which is the only honest test: it has
-- continents under it.
--
-- The test is the whole reason the fallbacks are still here after the climb.
-- A client that answers no parent at all, which is what a build with a partial
-- C_Map does, ends the climb on the zone you are standing in, and a zone has no
-- continents under it. Taking that as the root drew an empty column and looked
-- exactly like a client that had refused the walk.
local function Roots(map, continent)
	return type(map) == "number" and #Children(map, continent) > 0
end

local function Root()
	local continent = (Kinds())
	local climbed = Climb()
	if Roots(climbed, continent) then
		return climbed
	end
	for _, guess in ipairs(FALLBACK) do
		if Roots(guess, continent) then
			return guess
		end
	end
	return nil
end

--------------------------------------------------------------------------

-- One continent and the zones under it, sorted by name.
--
-- Sorted rather than left in the client's order, which is the order the ids
-- happen to be in and reads as no order at all in a column of thirty names.
-- Sorted by what is written on the row, so the column is alphabetical in
-- whatever language the client is running in.
local function Continent(node, zone)
	local out = { name = node.name, map = node.mapID, zones = {} }
	for _, child in ipairs(Children(node.mapID, zone)) do
		if type(child.mapID) == "number" and type(child.name) == "string" then
			out.zones[#out.zones + 1] = { name = child.name, map = child.mapID }
		end
	end
	table.sort(out.zones, function(a, b) return a.name < b.name end)
	return out
end

-- The whole tree: continents in the client's own order, zones under each in
-- alphabetical order. An empty list is the ordinary answer on a client that
-- will not walk its own map, and the window writes a line rather than drawing
-- an empty rail.
function Zones.Tree()
	if tree then
		return tree
	end
	local continent, zone = Kinds()
	local root = Root()
	tree = {}
	for _, node in ipairs(root and Children(root, continent) or {}) do
		if type(node.mapID) == "number" and type(node.name) == "string" then
			local held = Continent(node, zone)
			if #held.zones > 0 then
				-- The continent itself, first in its own group.
				--
				-- A continent is a map with a picture like any other and the
				-- column had no way to reach one, so the window could show you
				-- Desolace and could not show you Kalimdor. It is a row rather
				-- than a click on the group heading because the heading already
				-- means fold, and a row is what the right button on the picture
				-- moves to when it steps out of a zone.
				--
				-- First rather than sorted in with the zones, because it is not
				-- one of them: it is the thing they are all inside. Everything
				-- that counts zones skips it by the flag.
				table.insert(held.zones, 1,
					{ name = held.name, map = held.map, whole = true })
				tree[#tree + 1] = held
			end
		end
	end
	return tree
end

-- Thrown away so the next ask walks again. The tree is built out of a client
-- that is still starting up when this file loads, so the part that owns the
-- window drops it once the world is in rather than living with whatever was
-- there at load.
function Zones.Forget()
	tree = nil
	return true
end

-- How many zones there are altogether, which is the one number that says
-- whether the walk worked without naming a zone this addon cannot promise is on
-- every client.
function Zones.Count()
	local continents, zones = 0, 0
	for _, held in ipairs(Zones.Tree()) do
		continents = continents + 1
		for _, zone in ipairs(held.zones) do
			if not zone.whole then
				zones = zones + 1
			end
		end
	end
	return continents, zones
end

-- Where a zone sits in the tree, as the two numbers the rail selects by.
function Zones.Find(map)
	for at, held in ipairs(Zones.Tree()) do
		for index, zone in ipairs(held.zones) do
			if zone.map == map then
				return at, index
			end
		end
	end
	return nil
end

-- The continent a map is on, which is what the right button on the picture
-- steps out to. Nothing at all for a continent, because the column has no row
-- above one, and nothing for a map the tree has never heard of.
function Zones.Above(map)
	local at = Zones.Find(map)
	local held = at and Zones.Tree()[at]
	if not held or held.map == map then
		return nil
	end
	return held.map
end

-- What level this zone is for. Two numbers for a zone, nothing at all for a
-- city, and nothing for a map the table has never heard of. The caller tells
-- the last two apart with Zones.Known.
function Zones.Level(map)
	local range = LEVELS[map]
	if not range or #range < 2 then
		return nil
	end
	return range[1], range[2]
end

-- Whether the table has a row for this map, which is what separates "a city,
-- and cities have no range" from "this addon has no number for that place".
function Zones.Known(map)
	return LEVELS[map] ~= nil
end

-- The footer's line about one zone.
function Zones.Says(map)
	if not Zones.Known(map) then
		return "no level range known for this place"
	end
	local low, high = Zones.Level(map)
	if not low then
		return "a city, so no level range"
	end
	if low == high then
		return ("for level %d"):format(low)
	end
	return ("for levels %d to %d"):format(low, high)
end

function Zones.Describe()
	local continents, zones = Zones.Count()
	if zones == 0 then
		return "this client will not walk its own map tree, so there are no zones to choose from"
	end
	return ("%d zones over %d continents, %d of them with a level range")
		:format(zones, continents, (select(2, Zones.Ranged())))
end

-- How many of the zones the client offers this file has a row for. Its own
-- function because the panel's reading and the harness both want the number,
-- and because it is the one measurement that catches a client whose map ids
-- are not the ones the table above is keyed on.
function Zones.Ranged()
	local total, known = 0, 0
	for _, held in ipairs(Zones.Tree()) do
		for _, zone in ipairs(held.zones) do
			if not zone.whole then
				total = total + 1
				if Zones.Known(zone.map) then
					known = known + 1
				end
			end
		end
	end
	return total, known
end
