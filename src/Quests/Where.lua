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
-- So this file is a reader and nothing else. Four facts come out of it:
--
--   the finisher   who or what you hand the quest to, off the quest object's
--                  own Finisher, which Questie fills in with the name already
--                  resolved.
--   the tag        what kind of quest it is, which is the word "Elite" and the
--                  handful like it, off Questie's corrected wrapper around the
--                  client's own call.
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

-- Handed out because Near.lua makes the same cut on the npc half of "what is
-- near you", off the same distance function. One constant rather than two
-- spellings of half a million in one folder.
Where.ELSEWHERE = ELSEWHERE

-- What a place on the map is for. Taken from the widget that draws them rather
-- than written out again here: UI/Chart.lua keys its palette on these three
-- strings, and two copies of the same word is one edit away from a dot with no
-- colour, which is a dot nobody can read.
Where.TODO = ns.UI.Chart.TODO -- something you still have to kill, pick up or click
Where.BACK = ns.UI.Chart.BACK -- who the quest goes back to
Where.YOU  = ns.UI.Chart.YOU  -- where you are standing, which no database knows

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

-- Questie's modules are asked for through ns.Questie, in Core/Core.lua, which
-- takes the name of the module and the names of the calls the reader below is
-- about to make. This file had its own copy of that probe and handed it out as
-- Where.Module for Quests/Drops.lua to borrow, which is how a probe becomes
-- five probes. Both are gone.

-- The live quest object for one id: the one Questie has filled in from your
-- log, not the bare database row. GetNearestQuestSpawn reads objectives off it
-- and a database row has none of them collected, so the bare row would answer
-- for a quest you had not started.
local function Quest(questId)
	if type(questId) ~= "number" then
		return nil
	end
	local player = ns.Questie("QuestiePlayer")
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

-- One question of the compiled database, by the name of the call rather than by
-- the function, because the function does not exist until the database has
-- compiled and this file holds no reference across that moment.
--
-- Every query is pcalled. It is another addon's database, it is compiled rather
-- than written out, and an id it has no row for is a miss rather than an error,
-- but none of that is this addon's to guarantee. Comfort/Clutter.lua asks the
-- same database the same way.
local function Ask(call, id, field)
	local db = ns.Questie("QuestieDB", call)
	if not db or type(id) ~= "number" then
		return nil
	end
	local ok, value = pcall(db[call], id, field)
	if not ok then
		return nil
	end
	return value
end

-- Which call answers for a kind of thing. Questie keeps creatures and world
-- objects in two tables and the row is the same shape in both.
local ASKS = { monster = "QueryNPCSingle", object = "QueryObjectSingle" }

-- Who takes it back, as the kind of thing it is and every id Questie holds for
-- it.
--
-- **Questie stopped resolving this for you.** Up to v6 the quest object carried
-- a Finisher with the Id, the Name and the Type already worked out, and this
-- file read the three fields straight off it. From v11 it carries the two id
-- lists the database row was compiled from and nothing else: NPC, GameObject,
-- and the name a query away. The old fields do not raise, they answer nil, so
-- every quest in the log lost its hand-in line and the map lost its dot without
-- one thing in the game going wrong out loud.
local function Finishers(quest)
	local finisher = quest and quest.Finisher
	if type(finisher) ~= "table" then
		return nil
	end
	if type(finisher.NPC) == "table" and finisher.NPC[1] then
		return "monster", finisher.NPC
	end
	if type(finisher.GameObject) == "table" and finisher.GameObject[1] then
		return "object", finisher.GameObject
	end
	return nil
end

-- The name of the one you hand it to, and whether that is a person or a thing
-- on the ground. The first of the list where there are several, because this is
-- a line of text with room for one answer; the map below draws all of them.
function Where.Finisher(questId)
	local kind, ids = Finishers(Quest(questId))
	if not kind then
		return nil
	end
	local name = Ask(ASKS[kind], ids[1], "name")
	if type(name) ~= "string" or name == "" then
		return nil
	end
	return name, kind
end

-- What kind of quest this is, in the client's own word, or nothing at all for
-- the ordinary ones.
--
-- "Elite" is the one that matters, and it is a fact about the walk rather than
-- about the quest text: an elite camp is a crossing of the zone and a corpse
-- run back, and the word is the only thing that says so before you get there.
--
-- Here rather than beside whichever box drew it first, because three boxes draw
-- it. The marker hover on the world map, the creature hover out in the world
-- and the line under a quest's name in the log are all naming the same quest,
-- and a word that came off a different call in each is three answers that
-- disagree the day Blizzard tags one wrongly.
--
-- Asked through Questie rather than by calling GetQuestTagInfo here, for two
-- reasons that are both Questie's own. It caches, and this is asked once per
-- marker over a zone that can hold two hundred and fifty of them, against an
-- API the client throttles. And it corrects the quests Blizzard has tagged
-- wrongly, which is a list this addon has no business keeping a second copy of.
--
-- **The first ask about a quest always answers nothing.** The client's own call
-- returns nil the first time it is asked and Questie says so in its wrapper: it
-- schedules one retry a second later and caches what that gets. So the answer
-- is worth asking for twice, and a caller that asks once while it is building
-- something is a caller that has warmed the cache rather than one that has
-- failed. Every box below asks again at the moment it draws the words.
--
-- The word is whatever the client hands back, with one exception, and the
-- exception is the one tag anybody cares about. The client has two calls that
-- name a quest's tag and they do not agree: GetQuestTagInfo calls tag 1
-- "Group", and GetQuestLogTitle, which is what Blizzard's own quest log prints
-- in brackets after the name, calls the same quest elite. Elite is also the
-- word the game uses for the mobs that make the walk what it is, and it is the
-- word the player is looking for. So that one id is named here and every other
-- tag keeps the client's own word, which is what stops this file inventing a
-- name for a tag it has never seen.
local ELITE = 1

function Where.Tag(questId)
	if type(questId) ~= "number" then
		return nil
	end
	local db = ns.Questie("QuestieDB", "GetQuestTagInfo")
	if not db then
		return nil
	end
	local ok, id, word = pcall(db.GetQuestTagInfo, questId)
	if not ok then
		return nil
	end
	if id == ELITE then
		return "Elite"
	end
	if type(word) ~= "string" or word == "" then
		return nil
	end
	return word
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
--
-- **It moved out of QuestieMap and shed two returns.** v6 answered this on the
-- map module as GetNearestQuestSpawn and handed back six things, of which this
-- wanted the second, third and sixth. v11 keeps it in DistanceUtils, calls it
-- GetNearestSpawnForQuest, takes no self and returns four: the coordinate pair,
-- the area, the name and the distance. Read the old way the module answered a
-- table with no such function in it and every quest reported no destination.
--
-- **Asked at most once a second, and that is not a nicety.** The walk behind
-- it reads every spawn of every objective still open, through a zone to world
-- coordinate transform per pair, which on an ordinary kill objective is
-- hundreds of them. Both callers below are in the quest window's paint, so a
-- paint used to cost two of these walks, and a paint is what QUEST_LOG_UPDATE
-- ends in. That event is not the log changing: it is the client saying it
-- looked, and it says so several times a second while you are killing things.
-- The whole cost arrived the day the name above was corrected, because the
-- wrong name cost nothing, and it landed as a stutter in the world rather than
-- as anything wrong in the window.
--
-- One slot, because the window draws one quest at a time and clicking a
-- different one is a different quest table, which is a miss and is answered
-- fresh. Nothing is held across the second, so a quest handed in or abandoned
-- cannot be answered for: Quest above reads the live log and returns nil first.
--
-- A second of staleness on a yardage is nothing. Standing still it is the same
-- number, and running flat out it is seven yards off a figure that is already
-- only as exact as a spawn table's idea of where a mob stands.
local FRESH = 1.0
local memoQuest, memoAt, memoArea, memoName, memoDistance

local function Soonest(quest)
	if memoQuest == quest and memoAt and (GetTime() - memoAt) < FRESH then
		return memoArea, memoName, memoDistance
	end
	local distances = ns.Questie("DistanceUtils", "GetNearestSpawnForQuest")
	if not distances then
		return nil
	end
	local ok, _, area, name, distance = pcall(distances.GetNearestSpawnForQuest, quest)
	if not ok then
		return nil
	end
	memoQuest, memoAt = quest, GetTime()
	memoArea, memoName, memoDistance = area, name, distance
	return area, name, distance
end

-- The slot dropped, for the harness and for anything that has to see the walk
-- happen. Nothing in the addon calls it: the second expires on its own.
function Where.Forget()
	memoQuest, memoAt = nil, nil
	memoArea, memoName, memoDistance = nil, nil, nil
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
--
-- **Finished is Questie's own Completed field and not the two counts beside
-- it.** This read the counts first, as "needed is not collected", and that is
-- wrong for a whole kind of objective. Questie forces numRequired to 0 for
-- anything the client counts no items or kills for, which is every "speak to",
-- "explore" and "use the thing" step in the game, so the two counts are 0 and 0
-- and equal, and every such objective was dropped as done. A quest whose only
-- step is one of those dropped its whole self and the map said Questie had
-- nothing for it.
local function FromObjectives(into, objectives)
	if type(objectives) ~= "table" then
		return false
	end
	for _, objective in pairs(objectives) do
		if type(objective) == "table" and type(objective.spawnList) == "table"
			and not objective.Completed then
			FromList(into, objective.spawnList, Where.TODO)
		end
	end
	return true
end

-- Who takes it back, drawn whether or not the quest is finished.
--
-- Questie's own tracker only offers this once every objective is done, which is
-- the right rule for a line of text that has room for one answer. A map has
-- room for both, and knowing that the hand-in is on the way back rather than
-- across the zone is worth having while you are still killing things.
local function FromFinisher(into, quest)
	local kind, ids = Finishers(quest)
	if not kind then
		return false
	end
	local call = ASKS[kind]
	local drawn = false
	for _, id in ipairs(ids) do
		local spawns = Ask(call, id, "spawns")
		if type(spawns) == "table" then
			Scatter(into, spawns, Ask(call, id, "name"), Where.BACK)
			drawn = true
		end
	end
	return drawn
end

--------------------------------------------------------------------------
-- The same question, asked of the database instead
--
-- **A spawnList is not always there.** Questie fills one in per objective when
-- it draws that quest's icons and empties it again the moment the objective
-- completes or the icons are unloaded, so an empty one is an ordinary state and
-- not a broken one. Turn Questie's icons off, open the log before it has
-- finished drawing, or come back to a quest it has already tidied up after, and
-- every objective answers nothing at all.
--
-- What is always there is quest.ObjectiveData, which QuestieDB fills in the
-- moment it builds the quest object, out of the row the quest was compiled
-- from. It is one entry per objective carrying the kind and the id, and the
-- coordinates are one more lookup away. So where the live answer is empty the
-- same question is put to the database, and the map draws whether or not
-- anything has been drawn on the world map first.
--------------------------------------------------------------------------

-- One creature or object, by id. The name is asked for as well as the spawns,
-- because the database's name is the creature's and the objective's text is the
-- line off the quest, and a dot wants the first one.
local function FromThing(into, kind, id, text)
	local call = ASKS[kind]
	local spawns = call and Ask(call, id, "spawns")
	if type(spawns) ~= "table" then
		return false
	end
	Scatter(into, spawns, Ask(call, id, "name") or text, Where.TODO)
	return true
end

local function FromEach(into, ids, kind, text)
	for _, id in ipairs(ids) do
		FromThing(into, kind, id, text)
	end
end

-- Where an item comes from, which is the one kind the database cannot answer in
-- one hop. The row for the item names what carries it and the rows for those
-- are where the coordinates are.
local DROPPERS = { npcDrops = "monster", objectDrops = "object" }

local function FromItem(into, id, text)
	for key, kind in pairs(DROPPERS) do
		local carriers = Ask("QueryItemSingle", id, key)
		if type(carriers) == "table" then
			FromEach(into, carriers, kind, text)
		end
	end
	return true
end

-- One row of ObjectiveData. Five kinds, and an event carries its coordinates
-- itself rather than pointing at something that has them: that is the "speak
-- to", "explore" and "use the thing" objective, and it is exactly the one the
-- counts used to drop.
local function FromRow(into, row)
	if type(row) ~= "table" then
		return false
	end
	if row.Type == "event" then
		if type(row.Coordinates) ~= "table" then
			return false
		end
		Scatter(into, row.Coordinates, row.Text, Where.TODO)
		return true
	end
	if row.Type == "item" then
		return FromItem(into, row.Id, row.Text)
	end
	if row.Type == "killcredit" then
		if type(row.IdList) ~= "table" then
			return false
		end
		FromEach(into, row.IdList, "monster", row.Text)
		return true
	end
	return FromThing(into, row.Type, row.Id, row.Text)
end

-- Nothing here is filtered by what you have already done, and that is the
-- honest answer rather than a shortcut. This runs only where Questie has said
-- nothing about the quest's progress at all, so there is nothing to filter on,
-- and a map with one camp too many on it beats a map with a line saying there
-- is no map.
local function FromDatabase(into, quest)
	if type(quest.ObjectiveData) ~= "table" then
		return false
	end
	for _, row in ipairs(quest.ObjectiveData) do
		FromRow(into, row)
	end
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
	local zones = ns.Questie("ZoneDB", "GetUiMapIdByAreaId")
	if not zones then
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
	FromObjectives(into, quest.Objectives)
	FromObjectives(into, quest.SpecialObjectives)
	-- The live answer where there is one, the database where there is not, and
	-- the test is whether anything at all came back rather than whether each
	-- objective did. An objective Questie has drawn and one it has not are the
	-- same quest, and asking the database for half of it would draw the camps
	-- you have already emptied beside the ones you have not.
	if #into.order == 0 then
		FromDatabase(into, quest)
	end
	-- After the test above, so that a quest whose only live answer is who takes
	-- it back still reaches the database for the half that says what to do.
	FromFinisher(into, quest)
	return Atlas(into.order, (Soonest(quest)))
end

--------------------------------------------------------------------------

-- Whether Questie is answering at all. The window drops the two lines rather
-- than drawing them empty, and the panel says which way round it is.
function Where.Ready()
	return ns.Questie("QuestiePlayer") ~= nil and ns.Questie("QuestieMap") ~= nil
end

-- Whether the compiled database is answering yet.
--
-- Its own question, separate from whether Questie is loaded, because the two
-- come true minutes apart. Questie compiles after login and nils every query
-- function out while it works, so a quest log opened in that window finds
-- Questie present, its quest objects present, and every coordinate in the game
-- unreachable. That is the state the map used to report as "Questie has no
-- place on the map for this quest", which is a sentence about the wrong thing.
function Where.Compiled()
	return ns.Questie("QuestieDB", "QueryNPCSingle") ~= nil
end

function Where.Describe()
	if not Where.Ready() then
		return "Questie is not answering, so no quest says where to go"
	end
	if not Where.Compiled() then
		return "Questie is loaded and its database has not compiled yet"
	end
	local player = ns.Questie("QuestiePlayer")
	local held = 0
	if player and type(player.currentQuestlog) == "table" then
		for _ in pairs(player.currentQuestlog) do
			held = held + 1
		end
	end
	return ("reading Questie, which has %d of your quests"):format(held)
end
