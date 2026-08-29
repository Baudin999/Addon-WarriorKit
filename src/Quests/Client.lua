local ADDON, ns = ...

local Client = {}
ns.QuestClient = Client

--------------------------------------------------------------------------
-- The client's quest log, asked once and asked properly
--
-- Every call this addon makes to the game's quest log is in this file, and no
-- other file in the folder touches a client API. That is the same seam
-- Mail/Send.lua draws, and it is drawn here for one extra reason: the quest log
-- has a global cursor, and a window that reads it without putting the cursor
-- back is a window that breaks every other addon reading the same log.
--
-- **The cursor.** SelectQuestLogEntry returns nothing. It moves a selection the
-- whole client shares, and GetQuestLogQuestText, every reward call and the
-- abandon pair all read whatever it is pointing at. Questie's own timer code
-- shows the etiquette: read GetQuestLogSelection, move it, take the reading,
-- move it back. Client.Borrow is that, once, so no caller can forget it.
--
-- **The indices move.** A collapsed header hides the quests under it from
-- GetQuestLogTitle entirely, so an index means nothing except against a log
-- with every header open. Questie expands them all before it hashes the log,
-- for this reason. Client.Open does the same and the model calls it before it
-- counts anything.
--
-- **What is named and what is probed.** GetNumQuestLogEntries and
-- GetQuestLogTitle are in src/.luacheckrc because Questie calls them unguarded
-- on both of the clients this addon ships for, which is this addon's standing
-- proof that a call exists. Everything else goes through _G and is type-checked
-- at its call site, because the two clients genuinely differ: TBC pays honor
-- for a quest and Classic Era does not, and neither client has a
-- GetQuestLogRewardXP at all until Questie's own LibQuestXP defines one.
--
-- So every function below answers nil where the call was missing, and nil is a
-- different answer from zero. A quest that pays no honor and a client that
-- cannot say are not the same fact, and the window draws them differently.
--------------------------------------------------------------------------

-- One probed call that answers something. Missing or raising both come back
-- nil, which is the answer every reader here is written against.
local function Call(name, ...)
	local fn = _G[name]
	if type(fn) ~= "function" then
		return nil
	end
	local held = { pcall(fn, ...) }
	if not held[1] then
		return nil
	end
	return unpack(held, 2)
end

-- One probed call that answers nothing, and whether it was made.
--
-- This is not the same function as Call and cannot be. Half the quest log API
-- is void: ExpandQuestHeader, the watch pair, QuestLogPushQuest and both halves
-- of the abandon all return nothing at all, so `Call(...) ~= nil` reads every
-- one of them as a failure. That bug shipped for about an hour and the harness
-- caught it on the one call where the difference is visible: the quest was
-- abandoned and the window reported that it had not been.
local function Fire(name, ...)
	local fn = _G[name]
	if type(fn) ~= "function" then
		return false
	end
	return (pcall(fn, ...))
end

--------------------------------------------------------------------------
-- The cursor
--------------------------------------------------------------------------

-- Every header open, so an index means the same thing twice running.
function Client.Open()
	return Fire("ExpandQuestHeader", 0)
end

-- Move the cursor, take a reading, put the cursor back.
--
-- The restore is unconditional and that is why this is a function rather than
-- three lines at each site. A read that raises still has to hand the selection
-- back, so the reader is pcalled and the restore runs either way.
function Client.Borrow(index, read)
	local select = _G.SelectQuestLogEntry
	if type(select) ~= "function" or type(index) ~= "number" then
		return nil
	end

	local was = Call("GetQuestLogSelection")
	pcall(select, index)
	local ok, answer = pcall(read)
	if type(was) == "number" then
		pcall(select, was)
	end
	if not ok then
		return nil
	end
	return answer
end

--------------------------------------------------------------------------
-- The log itself
--------------------------------------------------------------------------

-- How many rows the log has, headers included, and how many of those are
-- quests.
function Client.Count()
	local entries, quests = GetNumQuestLogEntries()
	return entries or 0, quests or 0
end

-- One row. The first eight returns are the eight Questie reads on both clients
-- and the only ones this addon relies on; everything past them differs between
-- builds and is deliberately not taken.
--
-- Answered as a table rather than eight values because every caller wants them
-- by name, and a row is read once per quest per rebuild rather than on a tick.
function Client.Entry(index)
	local title, level, tag, isHeader, isCollapsed, isComplete, frequency, questId =
		GetQuestLogTitle(index)
	if title == nil then
		return nil
	end
	return {
		index = index,
		title = title,
		level = level or 0,
		tag = tag,
		header = isHeader and true or false,
		collapsed = isCollapsed and true or false,
		-- isComplete is 1 for a quest ready to hand in and -1 for one that has
		-- failed. They are different rows and neither is "in progress".
		complete = isComplete == 1,
		failed = isComplete == -1,
		frequency = frequency,
		id = questId,
	}
end

-- Where a quest id sits in the log right now, or nil if you are not on it.
function Client.IndexOf(questId)
	if type(questId) ~= "number" then
		return nil
	end
	local at = Call("GetQuestLogIndexByID", questId)
	if type(at) == "number" and at > 0 then
		return at
	end
	return nil
end

--------------------------------------------------------------------------
-- One quest's own text
--------------------------------------------------------------------------

-- The two paragraphs: what the giver told you, and the summary of what to do.
-- Both come off the cursor, so both are taken in one borrow.
function Client.Text(index)
	return Client.Borrow(index, function()
		local description, objectives = Call("GetQuestLogQuestText")
		return {
			description = type(description) == "string" and description or "",
			summary = type(objectives) == "string" and objectives or "",
		}
	end)
end

-- The ticked list: what the client draws in its own log, the kind of thing each
-- line counts, and whether that line is done.
function Client.Objectives(index)
	return Client.Borrow(index, function()
		local count = Call("GetNumQuestLeaderBoards") or 0
		local lines = {}
		for at = 1, count do
			local text, kind, finished = Call("GetQuestLogLeaderBoard", at)
			if type(text) == "string" and text ~= "" then
				lines[#lines + 1] = {
					text = text,
					kind = kind,
					done = finished and true or false,
				}
			end
		end
		return lines
	end)
end

-- Seconds left on a timed quest, and nil for the great majority that are not.
function Client.TimeLeft(index)
	local seconds = Client.Borrow(index, function()
		return Call("GetQuestLogTimeLeft", index)
	end)
	if type(seconds) == "number" and seconds > 0 then
		return seconds
	end
	return nil
end

--------------------------------------------------------------------------
-- What it pays
--------------------------------------------------------------------------

-- One row of the reward column: a picture, a name, a stack size and a quality.
local function Item(kind, at, infoCall)
	local name, texture, count, quality, usable = Call(infoCall, at)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	return {
		kind = kind,
		at = at,
		name = name,
		texture = texture,
		count = (type(count) == "number" and count > 1) and count or nil,
		quality = type(quality) == "number" and quality or nil,
		usable = usable and true or false,
		link = Call("GetQuestLogItemLink", kind, at),
	}
end

local function Items(kind, countCall, infoCall)
	local count = Call(countCall) or 0
	local rows = {}
	for at = 1, count do
		local item = Item(kind, at, infoCall)
		if item then
			rows[#rows + 1] = item
		end
	end
	return rows
end

-- Everything the quest hands over, in one borrow.
--
-- Choices and items are kept apart because that is the split the client draws:
-- a choice is one of several and an item is one you get regardless, and a
-- column that ran the two together would be telling you that you get all six.
function Client.Rewards(index)
	return Client.Borrow(index, function()
		local spellTexture, spellName = Call("GetQuestLogRewardSpell")
		return {
			choices = Items("choice", "GetNumQuestLogChoices", "GetQuestLogChoiceInfo"),
			items = Items("reward", "GetNumQuestLogRewards", "GetQuestLogRewardInfo"),
			money = Call("GetQuestLogRewardMoney"),
			-- What handing it in costs, which a small number of them do.
			required = Call("GetQuestLogRequiredMoney"),
			honor = Call("GetQuestLogRewardHonor"),
			title = Call("GetQuestLogRewardTitle"),
			spell = (type(spellName) == "string" and spellName ~= "")
				and { name = spellName, texture = spellTexture } or nil,
			-- No client this addon ships for has this call. Questie's LibQuestXP
			-- writes the global off its own database, so the number is here when
			-- Questie is loaded and absent when it is not. Absent is not zero.
			xp = Call("GetQuestLogRewardXP"),
		}
	end)
end

--------------------------------------------------------------------------
-- What you can do to it
--------------------------------------------------------------------------

function Client.Watched(index)
	return Call("IsQuestWatched", index) and true or false
end

function Client.Watch(index, on)
	return Fire(on and "AddQuestWatch" or "RemoveQuestWatch", index)
end

-- Whether this one can be handed to the party, which the client refuses for a
-- quest nobody else could take.
function Client.Shareable(index)
	return Client.Borrow(index, function()
		return Call("GetQuestLogPushable") and true or false
	end) and true or false
end

function Client.Share(index)
	return Client.Borrow(index, function()
		return Fire("QuestLogPushQuest")
	end) and true or false
end

-- The name the client says it is about to abandon.
--
-- This is the only honest thing to put in a confirmation, because it comes off
-- the client's own armed state rather than off the row this addon believes is
-- selected. The two disagreeing is exactly the bug worth catching.
function Client.Arm(index)
	return Client.Borrow(index, function()
		Fire("SetAbandonQuest")
		local name = Call("GetAbandonQuestName")
		return type(name) == "string" and name or nil
	end)
end

-- Arms and fires inside one borrow, so nothing can run between the two calls
-- and move the cursor onto a different quest.
function Client.Abandon(index)
	return Client.Borrow(index, function()
		Fire("SetAbandonQuest")
		return Fire("AbandonQuest")
	end) and true or false
end

--------------------------------------------------------------------------

-- Whether the client answered at all. The window checks this before it draws an
-- empty log and calls it your quest log.
function Client.Ready()
	return type(_G.GetNumQuestLogEntries) == "function"
		and type(_G.GetQuestLogTitle) == "function"
		and type(_G.SelectQuestLogEntry) == "function"
end

function Client.Describe()
	if not Client.Ready() then
		return "this client will not answer for the quest log"
	end
	local entries, quests = Client.Count()
	return ("%d quests in %d rows"):format(quests, entries)
end
