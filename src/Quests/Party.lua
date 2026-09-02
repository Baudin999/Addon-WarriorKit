local ADDON, ns = ...

local Party = {}
ns.QuestParty = Party

local Client = ns.QuestClient

--------------------------------------------------------------------------
-- Who else is on this quest
--
-- The one fact a quest log has never carried and the one everybody in a party
-- wants: of the four people standing next to you, how many are on this. It
-- decides which quest you do next, and without it the answer is somebody
-- reading their log out loud in voice chat.
--
-- **Two things can answer and neither of them always can.**
--
-- The client's own IsUnitOnQuest takes a row of your log and a unit and says
-- whether they are on it. It is the better answer where it exists, because it
-- is true of everybody in the group whatever they are running. It does not
-- exist on every build this addon ships for, which is why it goes through
-- Quests/Client.lua and comes back nil rather than false.
--
-- Questie's comms is the other. It broadcasts your log to the group and keeps
-- what it hears back, so QuestieComms:GetQuest hands over the names of everyone
-- who has told it they are on the quest. That is only ever the people running
-- Questie, so it is a floor rather than a count.
--
-- Both are read and the answers are merged by name, because each one knows
-- somebody the other does not: the client knows the party member with no
-- addons, and Questie knows them on a client that will not say. Merging on the
-- name rather than counting is what stops the same person being counted twice.
--
-- **Nobody and cannot say are both an empty list.** The row draws no number for
-- either, which is the honest thing: a "0" beside a quest would be this addon
-- claiming it asked and got an answer, and on Classic Era with Questie switched
-- off it asked nothing at all. Party.Describe is where the difference is said
-- out loud, for the panel and for the slash word.
--
-- **Nothing here is a client quest log call.** The one there is, IsUnitOnQuest,
-- is in Quests/Client.lua with the rest of them. What this file names is the
-- group: the roster the addon already keeps, and UnitName for the member's own
-- name, which is what the two lists are merged on.
--------------------------------------------------------------------------

-- Questie's comms, or nil. ns.Questie in Core takes the call this file is about
-- to make, because a module coming back proves nothing on its own.
local function Comms()
	return ns.Questie("QuestieComms", "GetQuest")
end

--------------------------------------------------------------------------

-- Everyone in the group but you, off the roster the addon already keeps rather
-- than a walk of the party tokens. It is rebuilt on every roster change, it
-- holds a raid as readily as a party, and the pets it also knows about are not
-- in the list it hands out.
local function Others()
	local units = ns.Unit.Roster.Units()
	local others = {}
	for index = 1, #units do
		if units[index] ~= "player" then
			others[#others + 1] = units[index]
		end
	end
	return others
end

-- What the client says, and how many members it would say anything about.
local function FromClient(index, found)
	local units, answered = Others(), 0
	for at = 1, #units do
		local on = Client.OnQuest(index, units[at])
		if on ~= nil then
			answered = answered + 1
			if on then
				found[UnitName(units[at]) or units[at]] = true
			end
		end
	end
	return answered
end

-- What Questie has heard. Your own name is dropped: you are on the quest, that
-- is why it is in your log, and a row saying one party member has it when the
-- one it means is you is worse than a row saying nothing.
local function FromQuestie(questId, found)
	local comms = Comms()
	if not comms or type(questId) ~= "number" then
		return 0
	end
	local ok, logs = pcall(comms.GetQuest, comms, questId)
	if not ok or type(logs) ~= "table" then
		return 0
	end
	local mine, heard = UnitName("player"), 0
	for name in pairs(logs) do
		if type(name) == "string" and name ~= mine then
			found[name] = true
			heard = heard + 1
		end
	end
	return heard
end

--------------------------------------------------------------------------

-- Who else in your group is on this quest, by name, in a stable order.
--
-- The index is the row of your own log the quest is at, because that is what
-- the client's call takes; the id is what Questie keys its own answer on. Both
-- are passed because the two sources ask different questions of the same quest.
function Party.On(questId, index)
	local found = {}
	if type(index) == "number" then
		FromClient(index, found)
	end
	FromQuestie(questId, found)

	local names = {}
	for name in pairs(found) do
		names[#names + 1] = name
	end
	-- Sorted, so the same party draws the same hover twice running. `pairs` is
	-- in whatever order the hash happens to be in, and a tooltip whose lines
	-- shuffle every time you open it reads as three different answers.
	table.sort(names)
	return names
end

-- Whether anything at all would answer. Both sources are asked about nothing in
-- particular, which is the only way to tell "nobody has it" from "nothing here
-- can say".
function Party.Ready()
	return Client.OnQuest(1, "player") ~= nil or Comms() ~= nil
end

function Party.Describe()
	local client = Client.OnQuest(1, "player") ~= nil
	local questie = Comms() ~= nil
	if client and questie then
		return "the client answers, and Questie fills in what it has heard"
	end
	if client then
		return "the client answers for every member of the group"
	end
	if questie then
		return "only Questie answers, so only party members running it are counted"
	end
	return "nothing on this client can say who else is on a quest"
end
