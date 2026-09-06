-- Who Questie says has a quest for you, and how far away he is standing.
--
-- Three names, every one read off the installed Questie 11.37.1 rather than
-- remembered, because two of the three were spelled differently in v6 and one
-- of those wrong spellings has already shipped here as a bug:
--
--   AvailableQuests.__availableQuestsByNpc   Modules/Quest/AvailableQuests/
--                                            AvailableQuests.lua:57. A field
--                                            on the module, npc id -> quest id
--                                            -> true, and empty rather than
--                                            absent for an npc whose quests
--                                            have all been taken.
--   QuestieDB:GetNPC(npcId)                  Database/QuestieDB.lua:1836. A
--                                            colon method, and the only one
--                                            this addon calls that way.
--   DistanceUtils.GetNearestSpawn(spawns)    Modules/Libs/DistanceUtils.lua:18.
--                                            A dot call over an npc's spawn
--                                            table, answering the coordinate
--                                            pair, the area and the yardage.
--
-- **The colon is the fixture's whole job on GetNPC.** The stub takes a self it
-- ignores, so a caller that reaches it with a dot hands the npc id in as that
-- self, asks for npc nil, and gets nil back for every npc in the game without
-- raising anything. That is exactly what the real one does, and it is the
-- failure that looks like Questie not being installed.
--
-- **The yardage is per area rather than per coordinate.** Questie's own
-- distance runs a zone-to-world transform through HereBeDragons, which is a
-- library the harness does not have and a number nothing here should be
-- asserting on anyway. What the addon has to get right is which spawn wins and
-- where the half-million cut falls, so an area is worth a fixed number of
-- yards and 1519 is the other continent: Questie adds 500000 to a spawn
-- outside the instance you are standing in so local things always sort first.
--
-- Three names on modules two files above this one already made, none of them a
-- key those files write. QuestieDB carries QueryNPCSingle from 12-questlog.lua
-- and GetNPC from here, and the two answer different questions.

local H = ...

-- What a spawn in each area is worth. Two areas near you rather than one, so a
-- section can put two npcs at the same yardage and a third at a different one.
local YARDS = {
	[40] = 60,             -- Westfall
	[12] = 220,            -- Elwynn Forest
	[1519] = 500000 + 310, -- Stormwind, standing in for anywhere you are not
}

-- The rows GetNPC answers, in the shape the real one builds: an id, a name and
-- a spawn table keyed on area. Four of them are a case the walk has to survive
-- rather than a person worth naming.
local NPCS = {
	[1234] = { id = 1234, name = "Farmer Furlbrow",
		spawns = { [40] = { { 42.5, 61.0 } } } },
	[1235] = { id = 1235, name = "Salma Saldean",
		spawns = { [40] = { { 43.0, 62.0 } } } },
	[1236] = { id = 1236, name = "Marshal Dughan",
		spawns = { [12] = { { 41.0, 65.5 } } } },
	-- Two spawn tables, and the near one has to win. This is the whole of what
	-- GetNearestSpawn is for.
	[1237] = { id = 1237, name = "Gryan Stoutmantle",
		spawns = { [12] = { { 56.0, 47.0 } }, [1519] = { { 60.0, 60.0 } } } },
	-- A row with no spawns at all, which is a field and not a call, so nothing
	-- in ns.Questie's check covers it.
	[1239] = { id = 1239, name = "A Voice From The Deep" },
	-- Standing on the other continent, which is the cut rather than a person.
	[1240] = { id = 1240, name = "Thrall",
		spawns = { [1519] = { { 50.0, 50.0 } } } },
	-- A row with no name, so an entry has to survive one.
	[1242] = { id = 1242, spawns = { [12] = { { 44.0, 60.0 } } } },
}

-- Questie's offer table. 1238 is deliberately absent from NPCS above: Questie
-- keeps offering a quest on an npc the compiled database has no row for, which
-- is what a half-loaded database looks like from outside.
local BY_NPC = {
	[1234] = { [26] = true },
	[1235] = { [22] = true, [19] = true },
	[1236] = { [239] = true },
	[1237] = { [155] = true },
	[1238] = { [99] = true },
	[1239] = { [98] = true },
	[1240] = { [3] = true },
	[1242] = { [62] = true },
	-- Emptied by a turn-in. Questie leaves the table behind rather than taking
	-- the npc off the list, so an empty one is not somebody to walk to.
	[1241] = {},
}

-- Enough of them that a pass cannot finish on one tick.
--
-- The walk takes twenty five npcs per tick, so a fixture of eight would prove
-- nothing about the budget that is the whole design. These forty three are all
-- on the other continent, so they cost the pass a tick each and add nothing to
-- the answer, which is the shape of the real table on a low level character.
local FILLERS = 43
for index = 1, FILLERS do
	local npcId = 2000 + index
	NPCS[npcId] = { id = npcId, name = "A Stranger",
		spawns = { [1519] = { { 50.0, 50.0 } } } }
	BY_NPC[npcId] = { [5000 + index] = true }
end

local questie = _G.QuestieLoader
local available = questie:ImportModule("AvailableQuests")
local knows = questie:ImportModule("QuestieDB")
local distancing = questie:ImportModule("DistanceUtils")

-- A self it ignores, and that is the point. See the header.
local function GetNPC(_, npcId)
	return NPCS[npcId]
end

-- No self, matching the real declaration, and the first spawn of the winning
-- area rather than the nearest inside it: everything in one area is one
-- yardage here, so the pair that comes back is only ever asserted as the pair
-- the fixture put in that area.
local function GetNearestSpawn(spawns)
	local best, bestArea, bestSpawn
	for area, list in pairs(spawns) do
		local yards = YARDS[area] or 999999999
		if (not best) or yards < best then
			best, bestArea, bestSpawn = yards, area, list[1]
		end
	end
	if not best then
		return nil, nil, 999999999
	end
	return bestSpawn, bestArea, best
end

-- The three names put back, so a section can take one away, prove the walk
-- goes quiet, and hand the client back the way it found it.
local function Restore()
	available.__availableQuestsByNpc = BY_NPC
	knows.GetNPC = GetNPC
	distancing.GetNearestSpawn = GetNearestSpawn
end

Restore()

H.near = {
	NPCS = NPCS,
	BY_NPC = BY_NPC,
	YARDS = YARDS,
	FILLERS = FILLERS,
	-- The three modules, so a section can break one field or one call.
	available = available,
	db = knows,
	distances = distancing,
	Restore = Restore,
}
