local ADDON, ns = ...

local Where = {}
ns.QuestWhere = Where

--------------------------------------------------------------------------
-- Where the quest actually is, borrowed from Questie
--
-- This addon does not replace Questie and will not try to. Questie carries a
-- quest database and draws the map icons, and both of those are the reason it
-- is installed. What it also carries, and barely uses, is the answer to the one
-- question a quest log cannot answer on its own: where do I go.
--
-- The client will tell you a quest wants eight Kobold Miners. It will not tell
-- you where a Kobold Miner is, who takes the quest back, or which of the eleven
-- things in your log is nearest to where you are standing. Questie knows all
-- three and spends them on a tracker sorted by zone.
--
-- So this file is a reader and nothing else. Two facts come out of it:
--
--   the finisher   who or what you hand the quest to, off the quest object's
--                  own Finisher, which Questie fills in with the name already
--                  resolved.
--   the nearest    the closest thing that would tick an objective, and how far
--                  away it is, off QuestieMap:GetNearestQuestSpawn.
--   the places     every spawn the quest has, grouped by the zone it is in and
--                  translated into the map id the client draws that zone under.
--                  This is the one Questie has and never shows you as a list:
--                  it draws them on the world map as icons and the tracker
--                  turns them into a single line of text.
--
-- **Every one of them degrades to nil.** Questie may not be installed, may be a
-- version whose internals moved, or may not have compiled its database yet, and
-- a quest log that raises because another addon changed a field name is a
-- quest log that has made the player's evening worse for no gain. Nil is drawn
-- as a column with a line missing, and that is the whole cost.
--
-- **Nothing here is cached.** Comfort/Clutter.lua makes the same call and
-- carries the reason: the database is compiled after login, so an answer taken
-- too early is wrong for the rest of the session. The distance has a second
-- reason on top of that one, which is that it changes every step you take.
--------------------------------------------------------------------------

-- Past this, Questie is telling you the thing is on another continent. Its own
-- distance function adds half a million yards to a spawn outside your instance
-- so that anything local always sorts first, and reading that number as a
-- distance would put "483,204 yards" under a quest name.
local ELSEWHERE = 500000

-- What a place on the map is for. Three strings rather than three booleans,
-- because Quests/Chart.lua keys its palette on them and a dot with no colour
-- is a dot nobody can read.
Where.TODO = "todo"   -- something you still have to kill, pick up or click
Where.BACK = "back"   -- who the quest goes back to
Where.YOU  = "you"    -- where you are standing, which no database knows

-- How near two spawns have to be before they count as one place.
--
-- A zone coordinate is a percentage, so this is a step of a hundred and fiftieth
-- of the zone across, and a zone map at the width the middle column gives it is
-- about five pixels to the step. The reason is not tidiness. A quest that sends
-- you at forty murlocs has forty database rows inside one camp, and forty dots
-- on the same five pixels is one dot drawn forty times: the same picture, forty
-- frames, and a pool that grows to whatever the worst quest in the database
-- asks for. Rounded to the step, the camp is drawn once.
local STEP = 1.5

-- The most places one zone gets. Past this the map is a texture with confetti
-- over it rather than an answer, and the quest that reaches it is one whose
-- database row covers a continent.
local CROWD = 80

-- One of Questie's modules, or nil.
--
-- ImportModule hands back a fresh empty table for a name it has never heard of
-- rather than nil, so the module coming back proves nothing at all. Every
-- caller below checks for the function it is about to make, which is the same
-- test Comfort/Clutter.lua makes and for the same reason.
local function Module(name)
	local loader = _G.QuestieLoader
	if not loader or type(loader.ImportModule) ~= "function" then
		return nil
	end
	local ok, module = pcall(loader.ImportModule, loader, name)
	if not ok or type(module) ~= "table" then
		return nil
	end
	return module
end

-- The live quest object for one id: the one Questie has filled in from your
-- log, not the bare database row. GetNearestQuestSpawn reads objectives off it
-- and a database row has none of them collected, so the bare row would answer
-- for a quest you had not started.
local function Quest(questId)
	if type(questId) ~= "number" then
		return nil
	end
	local player = Module("QuestiePlayer")
	if not player or type(player.currentQuestlog) ~= "table" then
		return nil
	end
	local quest = player.currentQuestlog[questId]
	if type(quest) ~= "table" then
		return nil
	end
	return quest
end

--------------------------------------------------------------------------

-- Who takes it back, and whether that is a person or a thing on the ground.
function Where.Finisher(questId)
	local quest = Quest(questId)
	if not quest or type(quest.Finisher) ~= "table" then
		return nil
	end
	local name = quest.Finisher.Name
	if type(name) ~= "string" or name == "" then
		return nil
	end
	return name, quest.Finisher.Type
end

-- Questie's own answer to "where next", unpicked: the zone it is in, what it
-- is called and how far away it is.
--
-- Its own function because two callers want different thirds of it. The right
-- column draws the name and the distance on one line; the map wants only the
-- zone, so that the zone it opens on is the one you would walk to.
--
-- A quest that is already complete answers with its finisher instead, which is
-- Questie's behaviour rather than a choice made here: once there is nothing
-- left to kill, the nearest thing that matters is the person waiting for you.
local function Soonest(quest)
	local map = Module("QuestieMap")
	if not map or type(map.GetNearestQuestSpawn) ~= "function" then
		return nil
	end
	local ok, _, area, name, _, _, distance = pcall(map.GetNearestQuestSpawn, map, quest)
	if not ok then
		return nil
	end
	return area, name, distance
end

-- The nearest thing that would tick something off, and how many yards away it
-- is. Two returns rather than a table, because the caller draws them on one
-- line and neither is any use without the other.
function Where.Nearest(questId)
	local quest = Quest(questId)
	if not quest then
		return nil
	end
	local _, name, distance = Soonest(quest)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	if type(distance) ~= "number" or distance >= ELSEWHERE then
		return name, nil
	end
	return name, math.floor(distance)
end

--------------------------------------------------------------------------
-- Every place at once
--------------------------------------------------------------------------

-- The zone one area id belongs to, and nil for a bucket collected off a spawn
-- Questie has a row for and the client has no map of. Both happen: the database
-- is keyed on the area ids the server uses and the map is drawn under the ids
-- the client's own atlas uses, and Questie carries the table between them.
local function Bucket(into, area)
	local zone = into.byArea[area]
	if zone then
		return zone
	end
	zone = { area = area, points = {}, seen = {} }
	into.byArea[area] = zone
	into.order[#into.order + 1] = zone
	return zone
end

-- One place, unless the step already holds one.
--
-- A coordinate of -1 is Questie saying the thing is inside an instance, whose
-- entrance is a separate row it does not hand over here. Dropped rather than
-- drawn at the top left corner of the zone, which is where a -1 lands.
local function Mark(zone, x, y, name, kind)
	if type(x) ~= "number" or type(y) ~= "number" or x <= 0 or y <= 0 then
		return false
	end
	if #zone.points >= CROWD then
		return false
	end
	local step = ("%d.%d.%s"):format(math.floor(x / STEP), math.floor(y / STEP), kind)
	if zone.seen[step] then
		return false
	end
	zone.seen[step] = true
	zone.points[#zone.points + 1] = { x = x, y = y, name = name, kind = kind }
	return true
end

-- One creature's or object's whole spawn table, which Questie keys by area id.
local function Scatter(into, spawns, name, kind)
	for area, places in pairs(spawns) do
		local zone = Bucket(into, area)
		for _, at in ipairs(places) do
			Mark(zone, at[1], at[2], name, kind)
		end
	end
end

-- Everything one objective would have you go and find. Questie fills a
-- spawnList in per objective once the quest is in your log, keyed by the id of
-- the thing, and each entry carries the name as well as the spawns.
local function FromList(into, spawnList, kind)
	for _, entry in pairs(spawnList) do
		if type(entry.Spawns) == "table" then
			Scatter(into, entry.Spawns, entry.Name, kind)
		end
	end
end

-- Every objective that is not finished. A collected one is left off on purpose:
-- the map answers "where do I go now", and the four camps you already emptied
-- are the half of the answer that would make the other half hard to see.
local function FromObjectives(into, objectives)
	for _, objective in pairs(objectives) do
		if type(objective.spawnList) == "table"
			and objective.Needed ~= objective.Collected then
			FromList(into, objective.spawnList, Where.TODO)
		end
	end
end

-- Who takes it back, drawn whether or not the quest is finished.
--
-- Questie's own tracker only offers this once every objective is done, which is
-- the right rule for a line of text that has room for one answer. A map has
-- room for both, and knowing that the hand-in is on the way back rather than
-- across the zone is worth having while you are still killing things.
local function FromFinisher(into, quest)
	local finisher = quest.Finisher
	if type(finisher) ~= "table" or type(finisher.Id) ~= "number" then
		return false
	end
	local db = Module("QuestieDB")
	local query = db and (finisher.Type == "object"
		and db.QueryObjectSingle or db.QueryNPCSingle)
	if type(query) ~= "function" then
		return false
	end
	local ok, spawns = pcall(query, finisher.Id, "spawns")
	if not ok or type(spawns) ~= "table" then
		return false
	end
	Scatter(into, spawns, finisher.Name, Where.BACK)
	return true
end

-- The area ids turned into the map ids the client draws, with the zone Questie
-- would send you to first put at the front. A zone the client has no map id for
-- is dropped here rather than further down, because a zone nothing can draw is
-- not a zone the window should offer as a choice.
local function Atlas(zones, leader)
	local out = {}
	for _, zone in ipairs(zones) do
		zone.map = Where.Map(zone.area)
		zone.seen = nil
		local at = (zone.area == leader) and 1 or (#out + 1)
		if zone.map and #zone.points > 0 then
			table.insert(out, at, zone)
		end
	end
	return out
end

-- Which map the client draws one of Questie's area ids under.
function Where.Map(area)
	local zones = Module("ZoneDB")
	if not zones or type(zones.GetUiMapIdByAreaId) ~= "function" then
		return nil
	end
	local ok, map = pcall(zones.GetUiMapIdByAreaId, zones, area)
	if not ok or type(map) ~= "number" then
		return nil
	end
	return map
end

-- Every place this quest has anything at, grouped by zone, nearest zone first.
--
-- An empty list is the ordinary answer, not a failure. Questie may not be
-- installed, may not have compiled its database yet, or may simply have no row
-- for a quest, and the window says so in a line rather than drawing an empty
-- rectangle.
function Where.Places(questId)
	local quest = Quest(questId)
	if not quest then
		return {}
	end
	local into = { byArea = {}, order = {} }
	if type(quest.Objectives) == "table" then
		FromObjectives(into, quest.Objectives)
	end
	if type(quest.SpecialObjectives) == "table" then
		FromObjectives(into, quest.SpecialObjectives)
	end
	FromFinisher(into, quest)
	return Atlas(into.order, (Soonest(quest)))
end

--------------------------------------------------------------------------

-- Whether Questie is answering at all. The window drops the two lines rather
-- than drawing them empty, and the panel says which way round it is.
function Where.Ready()
	return Module("QuestiePlayer") ~= nil and Module("QuestieMap") ~= nil
end

function Where.Describe()
	if not Where.Ready() then
		return "Questie is not answering, so no quest says where to go"
	end
	local player = Module("QuestiePlayer")
	local held = 0
	if player and type(player.currentQuestlog) == "table" then
		for _ in pairs(player.currentQuestlog) do
			held = held + 1
		end
	end
	return ("reading Questie, which has %d of your quests"):format(held)
end
