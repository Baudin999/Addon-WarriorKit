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

-- The nearest thing that would tick something off, and how many yards away it
-- is. Two returns rather than a table, because the caller draws them on one
-- line and neither is any use without the other.
--
-- A quest that is already complete answers with its finisher instead, which is
-- Questie's own behaviour rather than a choice made here: once there is nothing
-- left to kill, the nearest thing that matters is the person waiting for you.
function Where.Nearest(questId)
	local quest = Quest(questId)
	if not quest then
		return nil
	end
	local map = Module("QuestieMap")
	if not map or type(map.GetNearestQuestSpawn) ~= "function" then
		return nil
	end

	local ok, _, _, name, _, _, distance = pcall(map.GetNearestQuestSpawn, map, quest)
	if not ok or type(name) ~= "string" or name == "" then
		return nil
	end
	if type(distance) ~= "number" or distance >= ELSEWHERE then
		return name, nil
	end
	return name, math.floor(distance)
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
