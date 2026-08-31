-- The quest log
--
-- Enough of one to stand the quest window up and drive every column of it. Two
-- things here are modelled rather than stubbed away, and both are places the
-- part can be wrong in a way no amount of reading it would show.
--
-- **The cursor is real.** SelectQuestLogEntry moves a selection this file
-- keeps, and every text and reward call reads whatever it is pointing at. A
-- stub that answered for the index it was handed would make Quests/Client.lua's
-- borrow-and-restore look correct while it was doing nothing at all, and the
-- symptom in the game is another addon's quest log jumping to whichever quest
-- this window last drew.
--
-- **Headers are rows.** The client's log is a flat run where a zone is a row
-- like any other, which is the whole reason Quests/Log.lua exists. A stub that
-- handed over a list of quests with a zone field on each would test a model
-- that does not have to do anything.
--
-- The log deliberately holds quest 102, and only 102, of the four quests
-- scripts/harness/client/05-quests.lua files under Questie. The clutter scan
-- reads this same pair of calls to decide which items are spent, so the two
-- files have to agree about what you are on.

local H = ...
local region = H.region

--------------------------------------------------------------------------
-- The log
--------------------------------------------------------------------------

-- One row of the client's log, in the order the client returns them. A header
-- carries a name and nothing else; a quest carries everything
-- Quests/Client.lua reads out of the first eight returns.
--
-- The five quests are one per branch the left column can take: one in progress,
-- one ready to hand in, one failed, one timed and grouped, and one already
-- being tracked. The three zones are what makes the column a column.
local ROWS = {
	{ header = "Elwynn Forest" },
	{ id = 102, title = "The Missing Diplomat", level = 20 },
	{ id = 201, title = "Wanted: Hogger", level = 11, complete = 1 },
	{ header = "Westfall" },
	{ id = 202, title = "The Defias Brotherhood", level = 22, group = 3, seconds = 900 },
	{ id = 203, title = "Red Silk Bandanas", level = 18, complete = -1 },
	{ header = "Duskwood" },
	{ id = 204, title = "Wolves at the Gate", level = 24, watched = true },
}

-- What each quest says when it is the one the cursor is on. Split from the rows
-- above because the client splits them: the row is one call and the text is
-- three more, all of them against the selection.
local TEXT = {
	[102] = {
		description = "Find out what became of the diplomat.",
		summary = "Speak to Baros Alexston.",
		objectives = {
			{ "Speak to Baros Alexston", "event", false },
		},
	},
	[201] = {
		description = "Hogger has been terrorising the road.",
		summary = "Bring Hogger's head to Marshal Dughan.",
		objectives = {
			{ "Hogger slain", "monster", true },
		},
		choices = {
			{ "Fetching Boots", 2, 1 },
			{ "Blunted Axe", 2, 1 },
		},
		items = {
			{ "Small Pouch", 1, 1 },
		},
		money = 4500,
		xp = 1200,
	},
	[202] = {
		description = "The Brotherhood is dug in beneath the mill.",
		summary = "Kill twelve Defias Trappers.",
		objectives = {
			{ "Defias Trapper slain: 5/12", "monster", false },
			{ "Trapper's Rope: 3/3", "item", true },
		},
		money = 2200,
		required = 500,
	},
	[203] = {
		description = "The bandanas were lost with the courier.",
		summary = "Recover six red silk bandanas.",
		objectives = {
			{ "Red Silk Bandana: 0/6", "item", false },
		},
	},
	[204] = {
		description = "The worgen come down off the ridge at dusk.",
		summary = "Kill eight Nightbane Vile Fangs.",
		objectives = {
			{ "Nightbane Vile Fang slain: 8/8", "monster", true },
		},
		spell = "Blessing of the Night",
	},
}

-- Which quests are being watched. Seeded off the rows so the window's track
-- button has something to turn off as well as something to turn on.
local watched = {}
for _, row in ipairs(ROWS) do
	if row.watched then
		watched[row.id] = true
	end
end

-- Where the shared selection is pointing. Nil until something selects, which is
-- what the client answers before any window has opened.
local selection = nil

-- How many times the cursor was left somewhere other than where it was found.
-- The window is not allowed to move it permanently, and a count is the only way
-- a section can assert that without reaching into this file.
local stranded = 0

-- Every header open. The rows here are never collapsed, so this records the
-- call rather than acting on it: what a section checks is that the part asked,
-- because a part that does not ask reads a short log on a real client and has
-- no way to know it did.
local expanded = 0

local function Row(index)
	return ROWS[index]
end

local function Selected()
	return selection and Row(selection) or nil
end

local function Text()
	local row = Selected()
	return row and row.id and TEXT[row.id] or nil
end

--------------------------------------------------------------------------
-- The calls
--------------------------------------------------------------------------

_G.GetNumQuestLogEntries = function()
	local quests = 0
	for _, row in ipairs(ROWS) do
		if not row.header then
			quests = quests + 1
		end
	end
	return #ROWS, quests
end

_G.GetQuestLogTitle = function(index)
	local row = Row(index)
	if not row then
		return nil
	end
	if row.header then
		return row.header, 0, nil, true, false, nil, nil, nil
	end
	-- The quest id is the eighth value, which is where Questie reads it from
	-- and where Quests/Client.lua and Comfort/Clutter.lua both read it.
	return row.title, row.level, row.group, false, false, row.complete, nil, row.id
end

_G.GetQuestLogIndexByID = function(questId)
	for index, row in ipairs(ROWS) do
		if row.id == questId then
			return index
		end
	end
	return 0
end

_G.ExpandQuestHeader = function()
	expanded = expanded + 1
end

_G.GetQuestLogSelection = function()
	return selection or 0
end

_G.SelectQuestLogEntry = function(index)
	selection = index
end

_G.GetQuestLogQuestText = function()
	local text = Text()
	if not text then
		return "", ""
	end
	return text.description, text.summary
end

_G.GetNumQuestLeaderBoards = function()
	local text = Text()
	return text and #text.objectives or 0
end

_G.GetQuestLogLeaderBoard = function(at)
	local text = Text()
	local line = text and text.objectives[at]
	if not line then
		return nil
	end
	return line[1], line[2], line[3]
end

_G.GetQuestLogTimeLeft = function()
	local row = Selected()
	return row and row.seconds or nil
end

--------------------------------------------------------------------------
-- What it pays
--------------------------------------------------------------------------

-- One reward list, answered as the client answers it: a count call and an info
-- call that takes an index. Both kinds of reward read the same shape, which is
-- why the addon reads them with one loop.
local function Payout(field)
	return function(at)
		local text = Text()
		local item = text and text[field] and text[field][at]
		if not item then
			return nil
		end
		-- name, texture, count, quality, usable
		return item[1], "Interface\\Icons\\" .. item[1], item[3] or 1, item[2], true
	end
end

local function Counter(field)
	return function()
		local text = Text()
		return text and text[field] and #text[field] or 0
	end
end

_G.GetNumQuestLogChoices = Counter("choices")
_G.GetQuestLogChoiceInfo = Payout("choices")
_G.GetNumQuestLogRewards = Counter("items")
_G.GetQuestLogRewardInfo = Payout("items")

_G.GetQuestLogItemLink = function(kind, at)
	local text = Text()
	local list = text and text[kind == "choice" and "choices" or "items"]
	local item = list and list[at]
	if not item then
		return nil
	end
	return ("|cffffffff|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(at * 100, item[1])
end

_G.GetQuestLogRewardMoney = function()
	local text = Text()
	return text and text.money or 0
end

_G.GetQuestLogRequiredMoney = function()
	local text = Text()
	return text and text.required or 0
end

_G.GetQuestLogRewardSpell = function()
	local text = Text()
	if not text or not text.spell then
		return nil
	end
	return "Interface\\Icons\\Spell", text.spell
end

-- Deliberately absent: GetQuestLogRewardHonor, GetQuestLogRewardTitle and
-- GetQuestLogRewardXP. The first two exist on one of the two clients this addon
-- ships for and not the other, and the third is not a client call at all until
-- Questie's LibQuestXP writes it. Leaving all three off is what makes the
-- window's "a client that will not say" path the one the harness runs.

--------------------------------------------------------------------------
-- What you can do to one
--------------------------------------------------------------------------

_G.IsQuestWatched = function(index)
	local row = Row(index)
	return (row and row.id and watched[row.id]) and true or false
end

_G.AddQuestWatch = function(index)
	local row = Row(index)
	if row and row.id then
		watched[row.id] = true
	end
end

_G.RemoveQuestWatch = function(index)
	local row = Row(index)
	if row and row.id then
		watched[row.id] = nil
	end
end

-- A quest with a group size is one somebody else could take, which is the only
-- rule the client's own answer has that a test can hold it to.
_G.GetQuestLogPushable = function()
	local row = Selected()
	return (row and row.group) and true or false
end

local shared = {}
_G.QuestLogPushQuest = function()
	local row = Selected()
	if row and row.id then
		shared[#shared + 1] = row.id
	end
end

-- The abandon pair, modelled as two calls with state between them, because that
-- is what it is: SetAbandonQuest arms the client off the cursor and AbandonQuest
-- fires at whatever was armed. A stub that took an index on the second call
-- would make the window's confirmation look safe without the cursor ever having
-- mattered.
local armed = nil
local abandoned = {}

_G.SetAbandonQuest = function()
	armed = Selected()
end

_G.GetAbandonQuestName = function()
	return armed and armed.title or nil
end

_G.AbandonQuest = function()
	if not armed then
		return
	end
	for index, row in ipairs(ROWS) do
		if row == armed then
			table.remove(ROWS, index)
			break
		end
	end
	abandoned[#abandoned + 1] = armed.title
	armed = nil
end

--------------------------------------------------------------------------
-- Who else is on it
--------------------------------------------------------------------------

-- The client's own answer, which exists on some builds and not others. Keyed by
-- quest and then by unit, because that is what the call takes: a row of your own
-- log and somebody else's unit token.
--
-- Quest 102 is the one two of the party are also on. Nothing else is, so the
-- column has rows with a number and rows without, which is the difference the
-- window draws.
local COMPANY = {
	[102] = { party1 = true, party3 = true },
}

_G.IsUnitOnQuest = function(index, unit)
	local row = Row(index)
	local on = row and row.id and COMPANY[row.id]
	return (on and on[unit]) and true or false
end

--------------------------------------------------------------------------
-- The window it replaces
--------------------------------------------------------------------------

_G.QuestLogFrame = region("Frame", _G.UIParent, "QuestLogFrame")

-- The client's own toggle, which Quests/Blizzard.lua replaces and has to be
-- able to hand back. Counted, so a section can prove the key opens this addon's
-- window rather than this one.
local opened = 0
_G.ToggleQuestLog = function()
	opened = opened + 1
end

--------------------------------------------------------------------------
-- Questie, and the client's own map under it
--------------------------------------------------------------------------

-- Where a quest is, which is two addons' worth of answer.
--
-- Questie carries the spawns, keyed on the area ids the server uses. The client
-- carries the picture, keyed on the map ids its own atlas uses. Neither one is
-- any good alone and the join between them is Questie's own table, so all three
-- are modelled here rather than stubbed flat: a fixture that handed over map
-- ids directly would test a window that cannot exist.
--
-- Every branch the map can take is one row of this data.
--
--   two zones      the quest has spawns in Elwynn and in Westfall, so the strip
--                  of zones under the map has something to choose between
--   a third zone   area 606, which Questie has a row for and the client has no
--                  map id for. It must not reach the strip: a zone nothing can
--                  draw is not a choice.
--   two spawns
--     on one step  30,40 and 30.4,40.4 are the same camp. Two dots in five
--                  pixels is one dot drawn twice, and the pool grows to
--                  whatever the worst quest in the database asks for.
--   a -1 spawn     Questie saying the thing is inside an instance, whose
--                  entrance is a row it does not hand over here. Drawn, it
--                  lands in the top left corner of the zone.
--   a finished
--     objective    its spawns are the half of the answer that would make the
--                  other half hard to see
--   the finisher   a spawn that comes from the database rather than from the
--                  quest object, off a different call
local questie = _G.QuestieLoader
local knows = questie:ImportModule("QuestieDB")
local carrying = questie:ImportModule("QuestiePlayer")
local finding = questie:ImportModule("QuestieMap")
local placing = questie:ImportModule("ZoneDB")

local SPAWNS = {
	miners = { Name = "Kobold Miner", Type = "monster", Spawns = {
		[12] = { { 30, 40 }, { 30.4, 40.4 }, { 60, 20 }, { -1, -1 } },
		[40] = { { 50, 50 } },
		[606] = { { 10, 10 } },
	} },
	rope = { Name = "Trapper's Rope", Type = "object", Spawns = {
		[12] = { { 90, 90 } },
	} },
	-- The one an objective with no counts sends you to. Questie files it at 0
	-- of 0 like every other "speak to" step in the game.
	baros = { Name = "Baros Alexston", Type = "monster", Spawns = {
		[12] = { { 22, 70 } },
	} },
}

carrying.currentQuestlog = {
	[102] = {
		Id = 102,
		Finisher = { Type = "monster", Id = 900, Name = "Baros Alexston" },
		Objectives = {
			{ Needed = 8, Collected = 3, spawnList = { [700] = SPAWNS.miners } },
			-- Finished, and said so the way Questie says it. The two counts are
			-- not the test and must not be: Questie forces numRequired to 0 for
			-- every objective the client counts nothing for, so a "speak to" or
			-- an "explore" step reads 0 of 0, which is equal, which is how a
			-- whole kind of quest used to come back with no map at all. The
			-- third objective below is one of those and is not finished.
			{ Needed = 3, Collected = 3, Completed = true,
				spawnList = { [701] = SPAWNS.rope } },
			{ Needed = 0, Collected = 0, spawnList = { [702] = SPAWNS.baros } },
		},
		SpecialObjectives = {},
	},
	-- The other half of the same failure: a quest Questie holds and has drawn
	-- nothing for, so every spawnList on it is empty. That is what an addon
	-- sees with Questie's icons switched off, before it has finished drawing at
	-- login, or after it has tidied up behind a finished objective. The
	-- coordinates are still in ObjectiveData, which is filled in the moment the
	-- quest object is built, so the map has to fall back to it.
	--
	-- One row per kind the fallback can take: a creature, an item that has to be
	-- traced to what drops it, and an event that carries its own coordinates.
	[201] = {
		Id = 201,
		Objectives = {},
		SpecialObjectives = {},
		ObjectiveData = {
			{ Type = "monster", Id = 901, Text = "Hogger slain" },
			{ Type = "item", Id = 3010, Text = "Hogger's Head" },
			{ Type = "event", Text = "Report to Dughan",
				Coordinates = { [12] = { { 20, 60 } } } },
		},
	},
}

-- The finisher's spawns come off the compiled database rather than off the
-- quest object, which is why they are a second call and not a third field.
local NPCS = {
	[900] = { spawns = { [12] = { { 35, 45 } } }, name = "Baros Alexston" },
	[901] = { spawns = { [12] = { { 70, 70 } } }, name = "Hogger" },
	[902] = { spawns = { [12] = { { 80, 30 } } }, name = "Riverpaw Gnoll" },
}
knows.QueryNPCSingle = function(id, field)
	local npc = NPCS[id]
	return npc and npc[field] or nil
end
knows.QueryObjectSingle = function() return nil end

-- What carries an item, which is the one hop the database cannot answer
-- directly. Layered over the query 05-quests.lua installed rather than
-- replacing it, because the clutter scan reads the same call for its own
-- fields and both sets of fixtures have to keep answering.
local DROPS = { [3010] = { npcDrops = { 902 } } }
local asked = knows.QueryItemSingle
knows.QueryItemSingle = function(id, field)
	local row = DROPS[id]
	if row and row[field] ~= nil then
		return row[field]
	end
	return asked(id, field)
end

-- Questie's comms, which is the other half of who else is on a quest.
--
-- It hears from party members running Questie and nobody else, so it knows one
-- name the client's call does not know here and misses one the client has. The
-- window must end up with three and not four: Sneaky is in both answers and is
-- one person.
--
-- Tusksfirst is you in the party scripts/harness/sections/39-party-raid.lua
-- stands up. Questie hands your own name back with everyone else's, and a row
-- that counted it would say one party member is on every quest in your log.
local talking = questie:ImportModule("QuestieComms")
local HEARD = {
	[102] = { Sneaky = {}, Tusksfirst = {}, Ironhide = {} },
}
talking.GetQuest = function(_, questId)
	return HEARD[questId]
end

-- Questie's tracker, and the one function every route into the client's quest
-- log goes through: the click on a tracked quest and the "Show in Quest Log"
-- line of its right-click menu both land here. Counted rather than acted on, so
-- a section can prove the addon's window took the click and that the original
-- is handed back when the switch is off.
--
-- The module name is TrackerUtils and the function is a field on the module
-- itself. Both halves are read off the installed addon rather than guessed:
-- Modules/Tracker/TrackerUtils.lua opens with ImportModule("TrackerUtils") and
-- declares function TrackerUtils:ShowQuestLog(quest). This fixture used to
-- hang a utils table off QuestieTracker, which no build of Questie has, and a
-- swap that found nothing in the game passed every check here.
local watching = questie:ImportModule("TrackerUtils")
local tracked = 0
watching.ShowQuestLog = function()
	tracked = tracked + 1
end

-- The join. Area 606 is deliberately absent.
local ATLAS = { [12] = 37, [40] = 52 }
placing.GetUiMapIdByAreaId = function(_, area) return ATLAS[area] end

-- Questie's own "where next", which decides which zone the map opens on. It
-- answers Westfall, so a map that opened on the first zone it happened to
-- collect would open on the wrong one and this fixture would catch it.
finding.GetNearestQuestSpawn = function(_, quest)
	if type(quest) ~= "table" or quest.Id ~= 102 then
		return nil
	end
	return { 50, 50 }, 40, "Kobold Miner", 700, "monster", 260
end

-- The client's map art, in the shape C_Map really answers it: one layer saying
-- how big the whole image is and how big a tile of it is, and a flat list of
-- tiles in reading order. 1002 by 668 in squares of 256 is four across and
-- three down, and the right column and the bottom row are part tiles padded out
-- to 256, which is the whole reason the addon crops them.
local ART = {
	[37] = { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 },
	[52] = { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 },
}
local NAMED = { [37] = "Elwynn Forest", [52] = "Westfall" }

-- Where you are standing. Westfall, which is the zone the map opens on, so the
-- dot for you is drawn; step to Elwynn and it must not be.
local standing = { map = 52, x = 48, y = 52 }

_G.C_Map = {
	GetMapArtLayers = function(map)
		local art = ART[map]
		return art and { art } or {}
	end,
	GetMapArtLayerTextures = function(map)
		if not ART[map] then
			return {}
		end
		local files = {}
		for index = 1, 12 do
			files[index] = 500000 + map * 100 + index
		end
		return files
	end,
	GetMapInfo = function(map)
		local name = NAMED[map]
		return name and { name = name, mapID = map } or nil
	end,
	GetBestMapForUnit = function() return standing.map end,
	GetPlayerMapPosition = function(map)
		if map ~= standing.map then
			return nil
		end
		return { GetXY = function() return standing.x / 100, standing.y / 100 end }
	end,
}

--------------------------------------------------------------------------

-- What a section reads to check the etiquette rather than the drawing. The
-- cursor is the one that matters: every reading the window takes has to leave
-- the selection where it found it.
H.quests = {
	-- The map art, so a section can take a zone's picture away and reach the
	-- one branch a fixture cannot hold permanently: a map id Questie knows and
	-- this client has no picture for.
	art = ART,
	standing = standing,
	rows = ROWS,
	text = TEXT,
	watched = watched,
	shared = shared,
	abandoned = abandoned,
	Selection = function() return selection end,
	Expanded = function() return expanded end,
	Stranded = function() return stranded end,
	Opened = function() return opened end,
	-- How many clicks in Questie's tracker reached Blizzard's log rather than
	-- this addon's window.
	Tracked = function() return tracked end,
	company = COMPANY,
	heard = HEARD,
	-- Put the cursor somewhere and record where, so a section can take a
	-- reading through the window and then prove it came back.
	Park = function(index)
		selection = index
		stranded = 0
	end,
	-- Called by a section after it has driven the window, with the index it
	-- parked on. Anything else means a borrow did not restore.
	Check = function(index)
		if selection ~= index then
			stranded = stranded + 1
		end
		return selection
	end,
}
