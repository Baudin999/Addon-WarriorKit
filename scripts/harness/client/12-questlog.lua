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

-- What a section reads to check the etiquette rather than the drawing. The
-- cursor is the one that matters: every reading the window takes has to leave
-- the selection where it found it.
H.quests = {
	rows = ROWS,
	text = TEXT,
	watched = watched,
	shared = shared,
	abandoned = abandoned,
	Selection = function() return selection end,
	Expanded = function() return expanded end,
	Stranded = function() return stranded end,
	Opened = function() return opened end,
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
