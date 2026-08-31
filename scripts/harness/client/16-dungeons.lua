-- The dungeon log: dungeon maps in the client's tree, a loot window over a
-- boss, and the item lookups answering by id.
--
-- Four fixtures, and each one is a question the part cannot be read for.
--
-- **Dungeon maps in the tree.** A dungeon is a node of its own kind hanging
-- under the zone it is in, and Dungeons/Places.lua walks for that kind the way
-- Map/Zones.lua walks for zones. Two of them, one with art and two floors and
-- one with art and a single floor, plus a micro map that must not turn up in
-- the answer. The names are the names the book uses, because binding is by
-- name and a fixture with invented names would test the walk and never once
-- test the binding.
--
-- This chains over 15-worldmap.lua the way that file chains over
-- 12-questlog.lua: the same C_Map answers the quest log's two zones, the world
-- map's five and these dungeons, and a second table would leave one of the
-- three reading the wrong one.
--
-- **A map group.** Blizzard cuts an instance into floors and files them as a
-- group, and the strip under the picture is built out of the members. One
-- dungeon has two floors and one has none at all, which is the branch where
-- the strip is not drawn and the map is the dungeon's own id.
--
-- **The item lookups, by id.** Every other item in the addon is asked about by
-- link, so 04-hands.lua keys its table on the name inside one. The dungeon log
-- is the one part that starts from an id, because that is what a baked drop is,
-- so the two lookups are wrapped to answer a number as well. Three rows and
-- each is a branch: one the client agrees with, one it has never cached, and
-- one whose name does not match what the book says, which is the row that has
-- to be refused rather than drawn.
--
-- **A loot window over a boss.** Where a boss stands is learned from the corpse
-- you loot, so the fixture is the two calls that say which corpse a slot came
-- out of and what was in it. Both are absent until a section installs them, on
-- purpose: they are absent on a real client until something is being looted,
-- and every other section runs with a loot window that has no sources on it.

local H = ...

local api = _G.C_Map
local named = api.GetMapInfo
local children = api.GetMapChildrenInfo
local layers = api.GetMapArtLayers
local tiles = api.GetMapArtLayerTextures

--------------------------------------------------------------------------
-- The dungeons in the tree
--------------------------------------------------------------------------

-- name, the zone it hangs under, and what kind of node it is. Kind 4 is a
-- dungeon. The last one is a micro map under the same parent, kind 5, which is
-- what the client files an inn or a cellar as: it is there so a walk that asked
-- for the wrong kind, or for every kind, comes back with something the
-- assertions can name. A zone-kind node would have done the same job and would
-- also have changed what 54-world-map.lua counts, which is a fixture breaking a
-- test rather than a test finding a bug.
local NODES = {
	[291] = { name = "The Deadmines", parent = 1436, kind = 4 },
	[292] = { name = "Ironclad Cove", parent = 1436, kind = 4 },
	[225] = { name = "The Stockade", parent = 1453, kind = 4 },
	[9002] = { name = "A Cellar", parent = 1453, kind = 5 },
}

-- Which floors belong to one group, and which group each map is in. The
-- Deadmines is two floors; the Stockade is in no group at all, which is what a
-- single floor dungeon really is and is the branch the strip must not draw for.
local GROUPS = { [77] = { 291, 292 } }
local INGROUP = { [291] = 77, [292] = 77 }

local ART = { [291] = true, [292] = true, [225] = true }
local LAYER = {
	layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256,
}

api.GetMapInfo = function(map)
	local node = NODES[map]
	if not node then
		return named(map)
	end
	return { name = node.name, mapID = map, mapType = node.kind,
		parentMapID = node.parent }
end

-- The dungeons under a node, at any depth, added to whatever the tree already
-- answered. The world map's own nodes are handed back untouched, so a walk for
-- continents or for zones comes out exactly as it did before this file loaded.
local function under(map, kind, into)
	for id, node in pairs(NODES) do
		if node.kind == kind then
			-- One level of parenthood is enough here: every dungeon in the
			-- fixture hangs off a zone, and the zones hang off the continents
			-- the file below already answers for.
			local parent = node.parent
			for _ = 1, 4 do
				if parent == map then
					into[#into + 1] = { mapID = id, name = node.name, mapType = kind }
					break
				end
				local up = NODES[parent] or nil
				parent = up and up.parent or (named(parent) or {}).parentMapID
				if type(parent) ~= "number" or parent < 1 then
					break
				end
			end
		end
	end
	return into
end

api.GetMapChildrenInfo = function(map, kind, all)
	local held = children(map, kind, all)
	if not all or type(kind) ~= "number" then
		return held
	end
	local out = under(map, kind, held)
	table.sort(out, function(a, b) return a.mapID > b.mapID end)
	return out
end

api.GetMapGroupID = function(map)
	return INGROUP[map]
end

api.GetMapGroupMembersInfo = function(group)
	local held = GROUPS[group]
	if not held then
		return nil
	end
	local out = {}
	for index, map in ipairs(held) do
		out[index] = { mapID = map, name = (NODES[map] or {}).name, relativeIndex = index }
	end
	return out
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
		files[index] = 900000 + map * 100 + index
	end
	return files
end

--------------------------------------------------------------------------
-- The item lookups, answering an id
--------------------------------------------------------------------------

-- Three real ids out of Dungeons/Baked.lua, and what the client says about
-- each. The third is the whole reason this table exists: the book says 5192 is
-- Thief's Blade and the client here says it is something else, which is what a
-- wrong id in a baked file looks like from inside the addon, and the row has to
-- be refused rather than drawn with the client's name on it.
local BY_ID = {
	[5191] = { name = "Cruel Barb", quality = 3, level = 24,
		icon = "Interface\\Icons\\INV_Sword_04", equip = "INVTYPE_WEAPONMAINHAND" },
	[5192] = { name = "Somebody Else's Dagger", quality = 2, level = 22,
		icon = "Interface\\Icons\\INV_Weapon_ShortBlade_05", equip = "INVTYPE_WEAPON" },
	-- 5193 is deliberately not here. It is the row the client has never cached,
	-- which is most of the column the first time a dungeon is opened, and it has
	-- to draw from the book rather than going blank.
}

local info, instant = _G.GetItemInfo, _G.GetItemInfoInstant

local function byId(id)
	return type(id) == "number" and BY_ID[id] or nil
end

local function itemInfo(subject)
	local item = byId(subject)
	if not item then
		return info(subject)
	end
	return item.name, ("|cffffffff|Hitem:%d|h[%s]|h|r"):format(subject, item.name),
		item.quality, item.level, item.level, nil, nil, 1, item.equip, item.icon, 0
end

-- A link as well as an id, and that is not a convenience. What comes off a loot
-- window is a link, and the ledger reads an item id back out of one through
-- ns.ItemKind, so a stub that only answered for names 04-hands.lua carries would
-- have every drop off a boss come back as nothing at all. Only where the file
-- below has no row for the link, so nothing already written against that table
-- changes.
local function fromLink(link)
	local id = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)"))
	if not id then
		return nil
	end
	return id, (link:match("%[(.-)%]")) or ""
end

local function itemInfoInstant(subject)
	local item = byId(subject)
	if not item then
		local held = { instant(subject) }
		if held[1] then
			return unpack(held)
		end
		local id, name = fromLink(subject)
		if not id then
			return nil
		end
		return id, name, nil, "INVTYPE_WEAPON", "Interface\\Icons\\INV_Misc_QuestionMark", 2
	end
	return subject, item.name, nil, item.equip, item.icon, 2
end

-- Both homes, for the reason 04-hands.lua gives: the older client carries the
-- loose globals and the newer one carries C_Item, and the addon resolves the
-- pair at load.
_G.GetItemInfo, _G.GetItemInfoInstant = itemInfo, itemInfoInstant
_G.C_Item.GetItemInfo, _G.C_Item.GetItemInfoInstant = itemInfo, itemInfoInstant

-- What the addon calls to warm an item the client has not cached. Counted
-- rather than answered, because what a section has to be able to say is that
-- the window asked, not that the stub replied.
local asked = {}
_G.C_Item.RequestLoadItemDataByID = function(id)
	asked[#asked + 1] = id
	return true
end

--------------------------------------------------------------------------
-- A loot window over a corpse
--------------------------------------------------------------------------

-- Installed by a section around its own LOOT_OPENED and taken away again, so
-- every other section runs with the loot window 04-hands.lua already put up and
-- no sources on it, which is what a client that will not say answers.
local function Loot(corpse)
	local slots = corpse and corpse.slots or {}
	_G.GetNumLootItems = function() return #slots end
	_G.GetLootSourceInfo = function(slot)
		return slots[slot] and corpse.guid or nil
	end
	_G.GetLootSlotLink = function(slot)
		local held = slots[slot]
		if not held then
			return nil
		end
		return ("|cffffffff|Hitem:%d|h[%s]|h|r"):format(held[1], held[2])
	end
end

local size = _G.GetNumLootItems

local function Unloot()
	_G.GetNumLootItems = size
	_G.GetLootSourceInfo = nil
	_G.GetLootSlotLink = nil
end

H.dungeons = {
	NODES = NODES,
	Asked = function() return asked end,
	-- A corpse over a creature id, with the items that were on it.
	Loot = Loot,
	Unloot = Unloot,
}
