local ADDON, ns = ...

local Book = {}
ns.DungeonBook = Book

--------------------------------------------------------------------------
-- Every dungeon, every boss, and everything a boss drops
--
-- The list itself is in Dungeons/Baked.lua, which loads after this file and
-- fills in Book.DUNGEONS. This file is what the rest of the addon asks.
--
-- **Two halves, and each checks the other.** Which dungeons there are and what
-- order their bosses are fought in is a judgement, written out by hand in
-- scripts/bake-dungeons.lua. Every number is not: each creature id, each level,
-- each item id and each item name is read out of Questie's own generated
-- databases, which come from the client rather than from anybody typing them.
-- A boss name in the hand-written list that Questie cannot place stops the bake
-- and writes no file at all, so the editorial half cannot drift away from the
-- game without somebody being told.
--
-- That is the whole reason there is a bake script rather than a table typed in
-- here. An item id nobody generated is an id somebody remembered, and an id
-- remembered wrongly resolves to a real item with the wrong name on it, which
-- is a window confidently showing you the wrong sword. The client is asked
-- again at draw time as a second check, in Dungeons/Loot.lua.
--
-- **Where a boss stands is not baked and cannot be.** Questie files every
-- creature inside an instance at the coordinate {-1, -1}, which is its way of
-- saying it does not know, and no call on either of these clients will answer
-- it either. So a position is something this addon learns: Dungeons/Seen.lua
-- writes down where you were standing when the boss died, and that is what the
-- map draws. A dungeon you have never run has its bosses down the left and its
-- drops down the right and no marks on the picture, and the line under the map
-- says so rather than putting them somewhere plausible.
--
-- **The TBC half of the loot is thin, and it is worth saying out loud.**
-- Questie's Classic database carries the full drop table of every creature in
-- the game; its Burning Crusade database carries only what its quests need,
-- which for a five man boss is a pattern, a key fragment and a quest item. So
-- the twenty five Classic dungeons come to about eight hundred drops and the
-- fifteen Outland ones to about forty. Both fill in as you play, from the same
-- ledger that learns positions.
--------------------------------------------------------------------------

-- Filled in by Dungeons/Baked.lua, which loads next. Declared here so this file
-- reads correctly on its own and so a bake that wrote nothing leaves an empty
-- book rather than a nil one.
Book.DUNGEONS = Book.DUNGEONS or {}

-- Which dungeons this client has. Outland is not in a vanilla client, and a
-- column offering fifteen places you cannot walk to is a column that has to be
-- read past every time.
local shown = nil

local function Wanted(dungeon)
	return not (ns.vanilla and dungeon.era == "tbc")
end

-- Every dungeon this client can reach, in the order the list was written, which
-- is the order a character meets them. Kept, because the answer cannot change
-- while you are logged in and the left column asks for it on every repaint.
function Book.All()
	if shown then
		return shown
	end
	shown = {}
	for _, dungeon in ipairs(Book.DUNGEONS) do
		if Wanted(dungeon) then
			shown[#shown + 1] = dungeon
		end
	end
	return shown
end

-- One dungeon, by the name it is filed under. The name rather than an index,
-- because the left column's rows have to survive the list being re-baked with
-- a dungeon inserted in the middle of it.
function Book.Dungeon(name)
	for _, dungeon in ipairs(Book.All()) do
		if dungeon.name == name then
			return dungeon
		end
	end
	return nil
end

-- One boss, by the creature id, and the dungeon it is in.
--
-- The id rather than the name, because two dungeons hold a creature of the same
-- name and because the id is what a combat log line carries. Dungeons/Seen.lua
-- has nothing but an id to work from.
function Book.Boss(id)
	for _, dungeon in ipairs(Book.All()) do
		for order, boss in ipairs(dungeon.bosses) do
			if boss.id == id then
				return boss, dungeon, order
			end
		end
	end
	return nil
end

-- Which dungeon holds this boss, by the key the window's left column selects
-- on. A row's key is the creature id as a string, because UI.List keys on one
-- value and a header row's key is a name.
function Book.Key(boss)
	return tostring(boss.id)
end

function Book.Found(key)
	return Book.Boss(tonumber(key) or -1)
end

--------------------------------------------------------------------------
-- What you have seen
--
-- One row per boss you have killed, written by Dungeons/Seen.lua and kept in
-- the account's saved variables, because where a boss stands does not change
-- between characters. Two things go in it: where you were standing when it
-- died, as a map and a coordinate, and every item you have watched come off it.
--
-- Read through this file rather than out of ns.db directly, so the shape of the
-- record is decided in one place. The window and the loot column both ask.
--------------------------------------------------------------------------

local function Ledger()
	local held = ns.db and ns.db.dungeonSeen
	if type(held) ~= "table" then
		return nil
	end
	return held
end

-- Where this boss died, as the map it died on and two coordinates out of a
-- hundred. Nothing at all for a boss you have not killed, or for one you killed
-- on a client that would not say where you were standing.
function Book.Where(id)
	local held = Ledger()
	local row = held and held[id]
	if type(row) ~= "table" or type(row.map) ~= "number" then
		return nil
	end
	return row.map, row.x, row.y
end

-- Every item you have watched come off this boss that the baked list did not
-- already have, as the same { id, name } pairs the baked rows are.
function Book.Extra(id)
	local held = Ledger()
	local row = held and held[id]
	local drops = type(row) == "table" and row.drops or nil
	if type(drops) ~= "table" then
		return nil
	end
	return drops
end

-- Everything this boss drops: what was baked, then anything you have seen come
-- off it that the bake did not know about.
--
-- A fresh table each call rather than one kept, because the two halves change
-- at different times and a cache would be a third thing to get wrong. It is
-- built once per click on a boss, which is not a path anything is measured on.
function Book.Loot(boss)
	local rows = {}
	for _, drop in ipairs(boss.loot) do
		rows[#rows + 1] = drop
	end
	local known = {}
	for _, drop in ipairs(rows) do
		known[drop[1]] = true
	end
	for _, drop in ipairs(Book.Extra(boss.id) or {}) do
		if not known[drop[1]] then
			rows[#rows + 1] = drop
			known[drop[1]] = true
		end
	end
	return rows
end

--------------------------------------------------------------------------

-- How much of the book there is, which is the one reading that says whether the
-- bake ran at all: dungeons, bosses, drops, and how many of those bosses you
-- have a position for.
function Book.Count()
	local dungeons, bosses, drops, placed = 0, 0, 0, 0
	for _, dungeon in ipairs(Book.All()) do
		dungeons = dungeons + 1
		for _, boss in ipairs(dungeon.bosses) do
			bosses = bosses + 1
			drops = drops + #Book.Loot(boss)
			if Book.Where(boss.id) then
				placed = placed + 1
			end
		end
	end
	return dungeons, bosses, drops, placed
end

function Book.Describe()
	local dungeons, bosses, drops, placed = Book.Count()
	if dungeons == 0 then
		return "the book is empty, which means Dungeons/Baked.lua was never baked"
	end
	return ("%d dungeons, %d bosses, %d drops, %d bosses placed on a map")
		:format(dungeons, bosses, drops, placed)
end
