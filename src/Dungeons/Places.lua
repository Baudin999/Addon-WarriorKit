local ADDON, ns = ...

local Places = {}
ns.DungeonPlaces = Places

--------------------------------------------------------------------------
-- Which dungeon maps this client has
--
-- The book knows a dungeon by an English name. The client knows one by a map
-- id, in whatever language it is running in, and it is the only thing that can
-- say whether it has a picture for the place at all. This file is the join.
--
-- **The list is walked, not written down.** C_Map holds a tree, the same tree
-- Map/Zones.lua walks for zones, and a dungeon is a node of its own kind
-- hanging under the zone it is in. So every dungeon map the client has comes
-- out of one walk, with its own id and its own name, and no number in this
-- addon is a dungeon map id somebody remembered.
--
-- It is not shared with Map/Zones.lua and that is deliberate twice over. A part
-- may not name a file in another part's folder, which is the rule the whole
-- registry is built on. And it is a different question: that file wants zones
-- and the level range each is for, this one wants dungeons and the floors each
-- is cut into, and the only thing the two share is the climb to the top of the
-- tree, which is nine lines.
--
-- **A dungeon is several maps.** Blizzard cuts an instance into floors and
-- files them as a group: the Deadmines is the mine and then Ironclad Cove, the
-- monastery is four wings, Blackrock Depths is most of a city. The client will
-- hand over the members of a group, so the window draws one floor at a time
-- with a strip under it, which is the same strip the quest log puts under a
-- quest that spans two zones.
--
-- **Every call is probed and pcalled**, the same as UI/Chart.lua and for the
-- same reason: this ships for two clients, C_Map is not the same size on both,
-- and a window that raises because a dungeon has no map is a window that has
-- made the evening worse to save a rectangle. Nothing that fails here draws an
-- error; it draws a dungeon with no picture and a line saying so.
--
-- **The names are matched on the part before the colon.** The book calls one of
-- them "Scarlet Monastery: Library", because that is what a player calls it and
-- because the four wings are four different runs at four different levels. The
-- client calls the whole place "Scarlet Monastery" and cuts it into floors. So
-- the wing is the book's label and the place is what binds.
--------------------------------------------------------------------------

-- How far up the tree the climb to the root will go, and the two ids the game
-- has used for the world. Both are Map/Zones.lua's numbers and both are here
-- for the reason that file gives: an id written down is a claim about a client
-- this addon cannot test, so the climb is tried first and the guesses second.
local CLIMB = 12
local FALLBACK = { 946, 947 }

-- The most floors one dungeon is allowed to be cut into. Blackrock Depths is
-- the deepest in the game at about ten, and the cap is what stops a client
-- this addon has never seen from filling a strip until the window runs out.
local FLOORS = 16

local tree = nil

--------------------------------------------------------------------------
-- What the client will say
--------------------------------------------------------------------------

local function Api()
	local api = _G.C_Map
	if type(api) ~= "table" then
		return nil
	end
	return api
end

-- What the client calls the three kinds of node this walks for, read off Enum
-- where the client has it and taken as the numbers it has always used where it
-- does not.
local function Kinds()
	local kinds = _G.Enum and _G.Enum.UIMapType
	if type(kinds) == "table" and type(kinds.Continent) == "number"
		and type(kinds.Dungeon) == "number" then
		return kinds.Continent, kinds.Dungeon
	end
	return 2, 4
end

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
-- continents under it. Map/Zones.lua's header carries the argument for why the
-- climb alone is not enough.
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

-- Every dungeon map the client has, as a name to an id.
--
-- Walked once and kept, because the tree does not change while you are logged
-- in. Nil until the first ask, because at load the client has not finished
-- building its own tree and an empty answer kept for the session is worse than
-- an answer taken a second late.
--
-- The first id wins where two dungeons share a name. Nothing in these two
-- clients does, and taking the first is what keeps the walk's answer stable
-- rather than depending on which order pairs happened to run in.
function Places.Tree()
	if tree then
		return tree
	end
	tree = {}
	local _, dungeon = Kinds()
	for _, node in ipairs(Children(Root(), dungeon)) do
		if type(node.mapID) == "number" and type(node.name) == "string"
			and not tree[node.name] then
			tree[node.name] = node.mapID
		end
	end
	return tree
end

-- Thrown away so the next ask walks again. Called once the world is in, for the
-- reason Map/Zones.lua drops its own: this file loads while the client is still
-- building the tree it walks.
function Places.Forget()
	tree = nil
	return true
end

-- The place a book name binds to, which is the part before the colon. The wing
-- after it is what the player calls the run and what the left column shows, and
-- the client has no node for it.
function Places.Place(name)
	return (name:match("^([^:]+)")) or name
end

-- Which map the client has for this dungeon, or nothing at all.
function Places.Of(name)
	return Places.Tree()[Places.Place(name)]
end

-- Every floor of one dungeon, as ids in the client's own order, the first of
-- them being the one asked about.
--
-- A dungeon the client cuts into floors answers a group, and the group's members
-- are the floors. A dungeon it does not, and a client with no group calls at
-- all, answer the one map, which is what a single floor dungeon really is.
function Places.Floors(map)
	if type(map) ~= "number" then
		return {}
	end
	local api = Api()
	local group = api and api.GetMapGroupID
	local members = api and api.GetMapGroupMembersInfo
	if type(group) ~= "function" or type(members) ~= "function" then
		return { map }
	end
	local ok, id = pcall(group, map)
	if not ok or type(id) ~= "number" then
		return { map }
	end
	local read, list = pcall(members, id)
	if not read or type(list) ~= "table" or #list == 0 then
		return { map }
	end
	local out = {}
	for _, floor in ipairs(list) do
		if type(floor.mapID) == "number" and #out < FLOORS then
			out[#out + 1] = floor.mapID
		end
	end
	if #out == 0 then
		return { map }
	end
	return out
end

-- What one floor is called, which is the client's own name for it. The name of
-- a group's first floor is the dungeon's own name, so the strip is labelled
-- with the level rather than repeating the heading over it.
function Places.Floor(map, order)
	local info = Info(map)
	local name = info and info.name
	if type(name) ~= "string" or name == "" then
		return ("floor %d"):format(order or 1)
	end
	return name
end

--------------------------------------------------------------------------

-- How many dungeon maps the client named, and how many of the book's dungeons
-- found one. The second number is the one that matters: it is what separates a
-- client with no dungeon maps at all from one whose names this addon is failing
-- to match, and the two look identical on the screen.
function Places.Count()
	local named = 0
	for _ in pairs(Places.Tree()) do
		named = named + 1
	end
	local wanted, bound = 0, 0
	for _, dungeon in ipairs(ns.DungeonBook.All()) do
		wanted = wanted + 1
		if Places.Of(dungeon.name) then
			bound = bound + 1
		end
	end
	return named, bound, wanted
end

function Places.Describe()
	local named, bound, wanted = Places.Count()
	if named == 0 then
		return "this client names no dungeon maps, so every dungeon draws its bosses and its drops without a picture"
	end
	return ("this client names %d dungeon maps, and %d of the book's %d dungeons found one")
		:format(named, bound, wanted)
end
