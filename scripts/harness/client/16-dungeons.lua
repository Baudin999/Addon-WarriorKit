-- The dungeon log: which dungeon maps this client has, a loot window over a
-- boss, and the item lookups answering by id.
--
-- Four fixtures, and each one is a question the part cannot be read for.
--
-- **The dungeon maps this client has.** The addon draws a dungeon out of a
-- baked table of texture paths, because neither of the two clients will answer
-- anything about one, and Dungeons/Places.lua carries the argument. The one
-- thing it does still ask the client is whether it has a map of its own under
-- the id a mark is filed against, which is the difference between a dungeon
-- whose marks land where you looted them and one that only ever draws the
-- picture. So the fixture is three of the baked ids answered and the rest of
-- them not, which is the shape of the 2.5 client: it has the dungeon maps, and
-- it has fewer of them than the book has floors.
--
-- This chains over 15-worldmap.lua the way that file chains over
-- 12-questlog.lua: the same C_Map answers the quest log's two zones, the world
-- map's five and these dungeons, and a second table would leave one of the
-- three reading the wrong one.
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
--
-- **Where you are standing, in both number spaces.** ns.QuestHere reads the map
-- id off the client, asks whether the place around you is an instance, and
-- joins the map id to the area id Questie's database is keyed on. None of the
-- three is installed above this line, and the join is the reason all three are
-- here rather than beside the world map: it has to answer for 15-worldmap.lua's
-- zones and for this file's dungeons out of one table, so it can only be built
-- after the last of the three C_Map layers.

local H = ...

local api = _G.C_Map
local named = api.GetMapInfo

--------------------------------------------------------------------------
-- The dungeons this client has a map of
--------------------------------------------------------------------------

-- Three of the ids Dungeons/Sheets.lua bakes, with the names and the parents
-- the 2.5 client really gives them. Kind 4 is a dungeon. Every other id in the
-- baked table is deliberately absent, because a client that answered for all of
-- them would never once take the branch where it does not.
local NODES = {
	[291] = { name = "The Deadmines", parent = 1436, kind = 4 },
	[292] = { name = "The Deadmines", parent = 1436, kind = 4 },
	[225] = { name = "The Stockade", parent = 1453, kind = 4 },
}

api.GetMapInfo = function(map)
	local node = NODES[map]
	if not node then
		return named(map)
	end
	return { name = node.name, mapID = map, mapType = node.kind,
		parentMapID = node.parent }
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

-- What this file answers for a link it has no row for: the id read back out of
-- the link, and a weapon, which is enough for a drop off a boss to be counted.
local function unknown(subject)
	local id, name = fromLink(subject)
	if not id then
		return nil
	end
	return id, name, nil, "INVTYPE_WEAPON", "Interface\\Icons\\INV_Misc_QuestionMark", 2
end

-- The older stub's answer, forwarded whole, or this file's own where it had
-- none.
--
-- A round trip through a table and unpack is not the same thing and this is the
-- second time that has cost a morning. GetItemInfoInstant answers nil in the
-- middle of its returns, twice: the item type at three and the subclass at
-- seven for anything that has none. `#` on a table with a hole in it is not the
-- number of values that went into it, so `{ instant(subject) }` came back two
-- long the day a seventh return was added, and every item in the suite lost the
-- class that decides which pile it is in and whether the clutter window may
-- look at it. The varargs are never put in a table now.
local function forward(subject, first, ...)
	if first == nil then
		return unknown(subject)
	end
	return first, ...
end

local function itemInfoInstant(subject)
	local item = byId(subject)
	if item then
		return subject, item.name, nil, item.equip, item.icon, 2
	end
	return forward(subject, instant(subject))
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

-- Both calls as 04-hands.lua left them, so a section that opens a dungeon loot
-- window hands the ordinary corpse back rather than a client that has no loot
-- window at all. GetLootSourceInfo is the one this file invents outright: a
-- client only answers it while something is being looted, and nothing else in
-- the suite stands a source up.
local size, link = _G.GetNumLootItems, _G.GetLootSlotLink

local function Unloot()
	_G.GetNumLootItems = size
	_G.GetLootSourceInfo = nil
	_G.GetLootSlotLink = link
end

--------------------------------------------------------------------------
-- Whether you are inside an instance
--------------------------------------------------------------------------

-- IsInInstance, which nothing above this line installs and which is the whole
-- of the dungeon flag on a client that carries the call. The real one answers
-- a boolean and the kind of instance, and the kind is "none" in the open
-- world rather than nothing at all.
local instance

local function inInstance()
	return instance ~= nil, instance or "none"
end

_G.IsInInstance = inInstance

-- Set by a section. A string stands you inside an instance of that kind, nil
-- puts you back outdoors, and false takes the call off the client altogether,
-- which is the branch where the flag has to come off Questie's own table
-- instead. Every section that moves it puts it back.
-- An `if` and not `and or`, because the value being chosen is nil and `x and
-- nil or y` is always y. That one cost a run: the call stayed installed, the
-- fallback was never reached, and two checks that read as passing were passing
-- for the wrong reason.
local function Inside(kind)
	instance = kind or nil
	if kind == false then
		_G.IsInInstance = nil
	else
		_G.IsInInstance = inInstance
	end
end

--------------------------------------------------------------------------
-- Questie's number space, joined to the client's
--------------------------------------------------------------------------

-- 12-questlog.lua stubs GetUiMapIdByAreaId, which is the direction the quest
-- window's zone list goes. This is the other one, and the values are read off
-- the installed Questie's own generated tables rather than typed from memory:
-- Database/Zones/data/areaIdToUiMapId.lua for the join, dungeons.lua for which
-- areas are dungeons and which alternative ids they carry, and
-- subZoneToParentZone.lua for the parent.
--
-- It is not the inverse of that file's ATLAS and must not be read as one.
-- 12-questlog.lua files Westfall under map 52 and this tree files it under
-- 1436, because the quest window's fixture was written against the older id
-- space and the map tree was written against the one 2.5.6 really uses. Every
-- id here is the live client's.
--
-- 9001 is deliberately absent, and it is the branch that matters most. The real
-- ZoneDB:GetAreaIdByUiMapId falls through to a scan by name and then calls
-- error() outright for a map it has no row for, so a caller without a pcall
-- takes the frame down. The stub errors for the same id the world map tree
-- already has no picture for.
--
-- The quest tree's two ids are here as well, and that is the one place the two
-- spaces have to meet. The tracker folds a subzone header up to the area of the
-- map you are standing on, so a section that stands in 12-questlog's Elwynn
-- Forest needs an area for it, and a map with no area would leave that join
-- untested rather than failing.
local AREAS = {
	[1429] = 12,   -- Elwynn Forest
	[1436] = 40,   -- Westfall
	[37] = 12,     -- Elwynn Forest, as the quest tree numbers it
	[52] = 40,     -- Westfall, the same
	[1453] = 1519, -- Stormwind City
	[1411] = 14,   -- Durotar
	[291] = 1581,  -- The Deadmines
	[292] = 10029, -- its second floor, which Questie files under its own area
	[225] = 717,   -- The Stockade
}

-- dungeons.lua has a row for each of these, which is what IsDungeonZone reads,
-- and 10029 reaches it through the alternative id table rather than directly.
local DUNGEONS = { [1581] = true, [10029] = true, [717] = true }

-- What GetParentZoneId really answers, which is not the dungeon's zone. It
-- reads the alternative id table and then the subzone table, so a top level
-- zone and a top level dungeon both come back with nothing, and only the
-- second floor of the Deadmines has a parent.
--
-- Northshire Valley is the second, and it is the row every character in the
-- game starts on: the client files the first quests under it, vanilla draws no
-- map of it, and Questie's own subZoneToParentZone is what puts them on
-- Elwynn Forest. `[9] = 12` is that table's own line, copied.
local PARENTS = { [10029] = 1581, [9] = 12 }

local zones = _G.QuestieLoader:ImportModule("ZoneDB")

zones.GetAreaIdByUiMapId = function(_, map)
	local area = AREAS[map]
	if not area then
		error("No AreaId found for UiMapId: " .. tostring(map))
	end
	return area
end

-- No self, and that is not a slip. ZoneDB.IsDungeonZone is declared with a dot
-- where the two beside it are declared with a colon, and a stub that took a
-- self here would certify a call the addon makes wrongly.
zones.IsDungeonZone = function(area)
	return DUNGEONS[area] == true
end

zones.GetParentZoneId = function(_, area)
	return PARENTS[area]
end

H.dungeons = {
	NODES = NODES,
	Asked = function() return asked end,
	-- A corpse over a creature id, with the items that were on it.
	Loot = Loot,
	Unloot = Unloot,
	-- The kind of instance you are standing in, or nil for the open world, or
	-- false for a client with no IsInInstance at all.
	Inside = Inside,
	-- The join, so a section can read what it is asserting against.
	AREAS = AREAS,
}
