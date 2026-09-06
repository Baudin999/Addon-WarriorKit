local ADDON, ns = ...

local Near = {}
ns.QuestNear = Near

--------------------------------------------------------------------------
-- Who nearby has a quest you have never taken
--
-- One list, rebuilt a few npcs at a time: the people standing near you with a
-- quest on them that has never been in your log. It is the half of "what is
-- close" the client cannot answer at all. Your own log is answered by
-- Where.Nearest and is not read here, because that reader is memoised one
-- quest deep for one second and is shaped for the window's paint rather than
-- for a walk.
--
-- **The budget is the design.** Questie hands over thousands of npcs and each
-- one costs a zone-to-world transform per spawn. Asked all at once that is a
-- visible stall; asked on a paint it is the stutter Where.lua's header
-- describes. So this walks STRIDE of them per tick off ns.UI.Ticker, keeps the
-- answer, and finishes a pass in a couple of seconds. It never runs on a paint
-- and never on QUEST_LOG_UPDATE, which is the client saying it looked rather
-- than the log changing, and which it says several times a second while you
-- are killing things.
--
-- **Nothing runs until something asks.** Near.List stamps the clock, and a
-- walk with no reader for IDLE seconds stops starting passes. A tick that
-- nobody is reading is a frame spent on an answer thrown away.
--
-- **It idles indoors.** Questie's own distance function adds half a million
-- yards to every spawn outside the instance you are standing in, so a pass run
-- in a dungeon is a thousand npcs measured and every one of them thrown away
-- at the cut below. ns.QuestHere carries the flag and it is IsInInstance, so
-- raids and battlegrounds are covered as well as the book's forty. The flag is
-- read on the two events that can change it rather than on the tick, because a
-- tick reaching into Core would make that file's memo a hot path.
--
-- **Two of the three reads are fields rather than calls.**
-- AvailableQuests.__availableQuestsByNpc is a table on a module and npc.spawns
-- is a table on a row, so ns.Questie's own check covers neither: it asks
-- whether the calls you named are functions, and a data field is filled in
-- after login rather than at load. Both types are read here, next to the read,
-- which is the rule that function's header sets.
--
-- **QuestieDB:GetNPC is a colon method.** Everything else this addon reaches
-- on Questie is a dot call. Called with a dot, GetNPC takes the npc id as its
-- self, queries nothing, and hands back nil for every npc in the game without
-- raising a word.
--
-- Unsorted, and in whole yards. Ordering is the caller's: this is the reading,
-- not the ranking.
--------------------------------------------------------------------------

-- Past this, Questie is saying the npc is not where you are. The constant is
-- Where.lua's and is read rather than copied, because two spellings of half a
-- million is one edit away from a list full of other continents.
local ELSEWHERE = ns.QuestWhere.ELSEWHERE

-- Seconds between ticks, npcs looked at on each one, and the wait between the
-- end of one pass and the start of the next. Twenty ticks a second at twenty
-- five npcs is five hundred a second, so a pass over the two thousand or so an
-- ordinary character is offered lands inside four seconds and no single frame
-- carries more than a couple of dozen transforms.
local BEAT = 0.05
local STRIDE = 25
local REST = 2.0

-- Nobody has read the answer in this long, so stop working one out. Long
-- enough that a tracker redrawing between fights keeps the walk warm.
local IDLE = 30.0

-- Two arrays and a swap. The pass writes into one while callers read the
-- other, so a reader never sees a half-built list, and the entries in each are
-- kept and refilled rather than thrown away every pass.
local held, building = {}, {}

-- The npc ids of the pass in flight, snapshotted at its start, and how far
-- through them it is.
local pending = {}
local starters
local walking = false
local cursor, count = 0, 0

local restUntil, askedAt = 0, 0
local indoors = false

--------------------------------------------------------------------------
-- What Questie is asked
--------------------------------------------------------------------------

-- Every quest you could accept, keyed by the npc holding it, or nil.
--
-- The module comes back on any client with Questie loaded, so the module
-- proves nothing at all and the field is what is checked.
local function Starters()
	local available = ns.Questie("AvailableQuests")
	if not available then
		return nil
	end
	local byNpc = available.__availableQuestsByNpc
	if type(byNpc) ~= "table" then
		return nil
	end
	return byNpc
end

-- The compiled database, asked for by the one call this file makes on it.
local function Database()
	return ns.Questie("QuestieDB", "GetNPC")
end

-- Questie's npc-shaped distance. GetNearestSpawnForQuest is the other one and
-- walks a quest's objectives; this takes a spawn table and nothing else, which
-- is the whole reason the npc half is affordable and the log half is not.
local function Distances()
	return ns.Questie("DistanceUtils", "GetNearestSpawn")
end

--------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------

local function Empty()
	wipe(held)
end

-- One quest id off an npc and how many he is offering.
--
-- The lowest id rather than the first, because pairs answers in whatever order
-- the table happens to be in and a line that names a different quest on every
-- pass reads as a bug. One id and not a list: a caller naming two things is
-- writing a route, which is the module this is deliberately not.
local function Offer(npcId)
	local quests = starters and starters[npcId]
	if type(quests) ~= "table" then
		return nil, 0
	end
	local lowest, many = nil, 0
	for questId in pairs(quests) do
		many = many + 1
		if type(questId) == "number" and (not lowest or questId < lowest) then
			lowest = questId
		end
	end
	return lowest, many
end

-- One npc written into the pass in flight, over the entry that slot already
-- holds. The array is refilled rather than rebuilt: a pass is hundreds of
-- entries and it runs every few seconds for as long as you are logged in.
local function Record(npcId, name, spawn, area, distance)
	count = count + 1
	local entry = building[count]
	if not entry then
		entry = {}
		building[count] = entry
	end
	local quest, many = Offer(npcId)
	entry.npc = npcId
	entry.name = type(name) == "string" and name or nil
	entry.quest = quest
	entry.quests = many
	entry.area = area
	entry.x, entry.y = spawn[1], spawn[2]
	entry.distance = math.floor(distance)
end

--------------------------------------------------------------------------
-- The pass
--------------------------------------------------------------------------

-- The npc ids worth walking, copied out of Questie's table.
--
-- A copy rather than next() resumed across ticks. Questie rebuilds that table
-- on every turn-in and every reputation change, and next() given a key that
-- has since been removed raises rather than returning nil. The copy is one
-- walk of the keys with no arithmetic in it, which is the cheap half of the
-- work and what makes the expensive half interruptible.
--
-- An npc whose quests were all taken leaves an empty table behind rather than
-- coming off the list, so an empty one is not somebody to walk to.
local function Snapshot(byNpc)
	wipe(pending)
	local found = 0
	for npcId, quests in pairs(byNpc) do
		if type(npcId) == "number" and type(quests) == "table" and next(quests) then
			found = found + 1
			pending[found] = npcId
		end
	end
	return found
end

local function Begin()
	if indoors then
		return
	end
	local byNpc = Starters()
	if not byNpc then
		return
	end
	starters = byNpc
	if Snapshot(byNpc) == 0 then
		Empty()
		return
	end
	cursor, count = 0, 0
	walking = true
end

-- One npc measured, or dropped.
--
-- Both Questie calls are pcalled. GetNPC reads the compiled database and
-- GetNearestSpawn reaches HereBeDragons through a zone table that raises for a
-- zone it has no row for, and neither is worth taking a frame down over.
local function Look(db, distances, npcId)
	local known, npc = pcall(db.GetNPC, db, npcId)
	if not known or type(npc) ~= "table" then
		return
	end
	local spawns = npc.spawns
	if type(spawns) ~= "table" then
		return
	end
	local found, spawn, area, distance = pcall(distances.GetNearestSpawn, spawns)
	if not found or type(distance) ~= "number" or distance >= ELSEWHERE then
		return
	end
	if type(spawn) ~= "table" or type(area) ~= "number" then
		return
	end
	Record(npcId, npc.name, spawn, area, distance)
end

local function Finish(now)
	for index = count + 1, #building do
		building[index] = nil
	end
	held, building = building, held
	walking = false
	restUntil = now + REST
end

local function Step(now)
	local db = Database()
	local distances = Distances()
	if not db or not distances then
		walking = false
		return
	end
	local last = cursor + STRIDE
	if last > #pending then
		last = #pending
	end
	for index = cursor + 1, last do
		Look(db, distances, pending[index])
	end
	cursor = last
	if cursor >= #pending then
		Finish(now)
	end
end

-- One tick of the walk: either a slice of the pass in flight, or the start of
-- the next one.
--
-- Exported rather than local because ns.UI.Ticker takes a named function and
-- scripts/hot.lua walks out from the argument it is handed.
function Near.Beat()
	local now = GetTime()
	if (now - askedAt) > IDLE then
		return
	end
	if walking then
		Step(now)
		return
	end
	if now < restUntil then
		return
	end
	-- Set before the attempt rather than after it, so a pass that cannot start
	-- at all costs one try every REST rather than one every tick.
	restUntil = now + REST
	Begin()
end

--------------------------------------------------------------------------
-- The answer
--------------------------------------------------------------------------

-- Everybody near you with a quest you have never taken, in no order, and empty
-- until the first pass finishes.
--
--   npc       Questie's npc id
--   name      Questie's name for him, or nothing where the row carries none
--   quest     the lowest quest id he is offering, or nothing
--   quests    how many he is offering, which is at least one
--   area      Questie's area id for the spawn nearest you
--   x, y      where in that area he stands, nought to a hundred
--   distance  whole yards to that spawn, always under ELSEWHERE
--
-- The array is the held one and not a copy, and so are the entries in it. Read
-- it out again rather than keeping it: the pass after next writes into the
-- table this one hands back, and nothing here copies on the way out because
-- the caller wants one npc off it and a copy would be the expensive part.
function Near.List()
	askedAt = GetTime()
	return held
end

-- The answer dropped and the pass in flight abandoned, for the harness and for
-- anything that has to see the walk happen. Nothing in the addon calls it: a
-- pass expires on its own.
function Near.Forget()
	wipe(held)
	wipe(building)
	wipe(pending)
	starters = nil
	walking = false
	cursor, count = 0, 0
	restUntil, askedAt = 0, 0
end

function Near.Describe()
	if indoors then
		return "indoors, where everything is thirty yards away and nothing is worth saying"
	end
	if not Starters() then
		return "Questie is not saying who has a quest for you"
	end
	if walking then
		return ("walking, %d of %d asked"):format(cursor, #pending)
	end
	if #held == 0 then
		return "nobody near you has a quest you have never taken"
	end
	if #held == 1 then
		return ("%s has a quest you have never taken")
			:format(held[1].name or "somebody near you")
	end
	return ("%d near you have a quest you have never taken"):format(#held)
end

--------------------------------------------------------------------------
-- Where you are standing
--
-- Read on the two events that can change it rather than on the tick.
-- ns.QuestHere memoises on the map id, so asking it every tick is a table
-- lookup, but it is a table lookup in Core reached from an OnUpdate, and
-- scripts/hot.lua would then hold that whole file to the tick rules for the
-- sake of one boolean this file can keep itself.
--------------------------------------------------------------------------

local function Placed()
	local here = ns.QuestHere.Now()
	indoors = here ~= nil and here.dungeon == true
	if indoors then
		Empty()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function()
	Placed()
end)

ns.UI.Ticker(ns.UI.Forever, BEAT, "near", Near.Beat)
