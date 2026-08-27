local ADDON, ns = ...

local Rooms = {}
ns.Rooms = Rooms

--------------------------------------------------------------------------
-- Rooms
--
-- What the chat window is a window onto. A room is one conversation: your
-- party, your guild, the family, one person whispering you. It has a name, a
-- log of its own, a count of what arrived while you were reading something
-- else, and one answer to the question the whole part turns on, which is where
-- a line you type in it goes.
--
-- **This is the reimagining.** The window this replaced had three tabs and a
-- button beside the field that cycled six channels, and the two had nothing to
-- do with each other: you could be reading Whispers and typing into guild, and
-- nothing on the screen would have told you. A room is the two of them made one
-- thing. What you are reading is what you are typing into. Selecting the party
-- room is the same act as choosing to talk to your party, and there is nothing
-- else to press.
--
-- That is also the answer to a sliding spill of messages. A message does not
-- arrive in "the chat"; it arrives in a room, the room says so in the rail with
-- a count against its name, and a room you are not in cannot push anything you
-- are reading off the top of the screen.
--
-- **A room is a view, not a box.** One line lands in every room it belongs to:
-- a whisper from your wife is in Whispers with her name on it, in Family, and
-- in Conversation. Nothing is filed away somewhere you have to remember to go
-- and look, and no room has to be a compromise between two audiences.
--
-- This file knows nothing about frames. It knows which rooms exist right now,
-- where a line goes, and what is unread. Chat/Window.lua draws it.
--------------------------------------------------------------------------

Rooms.ALL = "all"
Rooms.SYSTEM = "system"

-- How many people you can be in the middle of a conversation with before the
-- oldest one stops having a room of its own. Eight is a rail you can read; the
-- ninth conversation pushes the least recent off, and everything anybody said
-- is still in Conversation.
local WHISPERS = 8

--------------------------------------------------------------------------
-- Whether a channel exists right now
--
-- Asked rather than remembered. A room for a party you left is a room whose
-- Enter key would type into a channel the server refuses, and the refusal
-- arrives as an error message rather than as anything you could see coming.
--------------------------------------------------------------------------

local function InGroup()
	if type(_G.IsInGroup) == "function" then
		return _G.IsInGroup() and true or false
	end
	if type(_G.GetNumGroupMembers) == "function" then
		return (_G.GetNumGroupMembers() or 0) > 0
	end
	if type(_G.GetNumPartyMembers) == "function" then
		return (_G.GetNumPartyMembers() or 0) > 0
	end
	return false
end

local function InRaid()
	if type(_G.IsInRaid) == "function" then
		return _G.IsInRaid() and true or false
	end
	if type(_G.GetNumRaidMembers) == "function" then
		return (_G.GetNumRaidMembers() or 0) > 0
	end
	return false
end

local function InGuild()
	return type(_G.IsInGuild) == "function" and _G.IsInGuild() and true or false
end

-- The dungeon group's own channel. It exists on one of the two clients this
-- addon ships for and not on the other, so the room is offered only where the
-- client says you are in such a group, and lines that arrive anyway are still
-- captured into Conversation.
local function InLFG()
	return type(_G.IsPartyLFG) == "function" and _G.IsPartyLFG() and true or false
end

local function Always()
	return true
end

-- Blizzard's window being hidden is what makes a system room worth having: the
-- loot, the experience and every addon's output have nowhere else to be drawn.
-- With it up, that room would be a second copy of a window already on screen.
local function Hiding()
	return ns.db.hideBlizzChat and true or false
end

--------------------------------------------------------------------------
-- The rooms that are not made by you
--
--   id       what a line is routed to and what the rail selects by
--   label    what the row says
--   under    the heading the row is drawn beneath
--   kind     what SendChatMessage is told when you type here
--   live     whether the channel behind it exists right now
--
-- Say carries yells and emotes as well, because all three are the same
-- conversation: the people standing near you. Splitting them would be three
-- rooms where two are empty all evening.
--------------------------------------------------------------------------

-- Two tables rather than one with a heading field, because your groups are
-- drawn between them and a single list would have to be walked twice to get
-- that order.
local TOP = {
	{ id = Rooms.ALL,    label = "Conversation", under = "Everything",
	  kind = "SAY", live = Always },
	{ id = Rooms.SYSTEM, label = "System", under = "Everything",
	  kind = "SAY", live = Hiding },
}

local CHANNELS = {
	{ id = "say",      label = "Say",      under = "Channels", kind = "SAY",   live = Always },
	{ id = "party",    label = "Party",    under = "Channels", kind = "PARTY", live = InGroup },
	{ id = "raid",     label = "Raid",     under = "Channels", kind = "RAID",  live = InRaid },
	{ id = "instance", label = "Instance", under = "Channels", kind = "INSTANCE_CHAT",
	  live = InLFG },
	{ id = "guild",    label = "Guild",    under = "Channels", kind = "GUILD", live = InGuild },
}

local byId = {}
for _, list in ipairs({ TOP, CHANNELS }) do
	for _, room in ipairs(list) do
		byId[room.id] = room
	end
end

--------------------------------------------------------------------------

-- How many lines arrived in a room you were not reading. Zeroed by reading it.
local unread = {}

-- Whisper rooms, most recently spoken first. Each is { key, name }, where the
-- key is the normalised name and the name is what the client spelled it, which
-- is what a whisper has to be addressed to.
local whispers = {}

-- Who spoke last in a room, by room id. A group is a set of people rather than
-- a channel, so the only honest thing Enter can do in one is answer whoever
-- last said something in it.
local speaker = {}

-- Set by whoever draws, the same way ns.ChatFeed.OnLine is. Called with the id
-- of a whisper room that has fallen off the end, so the log behind it can be
-- emptied and handed to the next conversation rather than kept forever.
Rooms.OnClose = nil

--------------------------------------------------------------------------
-- Whisper rooms
--------------------------------------------------------------------------

function Rooms.WhisperId(name)
	local key = ns.People.Key(name)
	return key and ("whisper:" .. key) or nil
end

-- The room for a conversation with one person, made if this is the first thing
-- either of you has said. Moving it to the front is what keeps the rail in the
-- order you would look for it in, and it is also what decides who is dropped
-- when a ninth person speaks.
function Rooms.Whisper(name)
	local key = ns.People.Key(name)
	if not key then
		return nil
	end

	for at, entry in ipairs(whispers) do
		if entry.key == key then
			entry.name = name
			table.remove(whispers, at)
			table.insert(whispers, 1, entry)
			return "whisper:" .. key
		end
	end

	table.insert(whispers, 1, { key = key, name = name })
	while #whispers > WHISPERS do
		local dropped = table.remove(whispers)
		local id = "whisper:" .. dropped.key
		unread[id], speaker[id] = nil, nil
		if Rooms.OnClose then
			Rooms.OnClose(id)
		end
	end
	return "whisper:" .. key
end

-- Who /r answers: the person at the front of that list, which is whoever last
-- said something to you or was last said something to. The client keeps its own
-- answer to this and will not hand it out, so this is the addon's, and it is
-- the same answer as long as the whisper came through the window.
function Rooms.Recent()
	local entry = whispers[1]
	return entry and entry.name or nil
end

--------------------------------------------------------------------------
-- Where a line goes
--
-- Called once per captured message. It allocates one table per line, which is
-- the same table the feed built before rooms existed: this is not a ticker
-- path, and a line of chat that has already been formatted into a string is not
-- a line to be counting tables on.
--------------------------------------------------------------------------

-- room     the fixed room this kind of message belongs to, or nil
-- who      whose line it is, which for one you sent is who you sent it to
-- whisper  whether it belongs in a conversation with that person
function Rooms.Route(room, who, whisper)
	local out = { Rooms.ALL }
	if room and room ~= Rooms.ALL then
		out[#out + 1] = room
	end

	if whisper and who then
		local id = Rooms.Whisper(who)
		if id then
			out[#out + 1] = id
			speaker[id] = who
		end
	end

	local groups = who and ns.People.Match(who)
	if groups then
		for _, group in ipairs(groups) do
			local id = "group:" .. group.key
			out[#out + 1] = id
			speaker[id] = who
		end
	end
	return out
end

--------------------------------------------------------------------------
-- What is drawn, and in what order
--
-- Everything first, because it is the room that is never empty and never wrong.
-- Then your groups, because they are the people you would answer first. Then
-- the channels, then the whispers, which is the order of how much of the
-- screen's attention each deserves rather than the order they were invented in.
--
-- A room is drawn when the channel behind it exists, or when it holds something
-- you have not read. That second clause is what keeps a party line that arrived
-- as you left the group reachable instead of deleting the row it was on, and
-- reading it is what makes the row go away.
--------------------------------------------------------------------------

local function Add(rows, id, label, header)
	if header and rows.under ~= header then
		rows[#rows + 1] = { header = header }
		rows.under = header
	end
	rows[#rows + 1] = { id = id, label = label, unread = unread[id] or 0 }
end

local function AddGroups(rows)
	for position, group in ipairs(ns.People.All()) do
		Add(rows, "group:" .. group.key, ns.People.Name(position), "Groups")
	end
end

local function AddWhispers(rows)
	for _, entry in ipairs(whispers) do
		Add(rows, "whisper:" .. entry.key, entry.name:gsub("%-.*$", ""), "Whispers")
	end
end

local function AddFixed(rows, list)
	for _, room in ipairs(list) do
		local id = room.id
		if room.live() or (unread[id] or 0) > 0 then
			Add(rows, id, room.label, room.under)
		end
	end
end

function Rooms.List()
	local rows = {}
	AddFixed(rows, TOP)
	AddGroups(rows)
	AddFixed(rows, CHANNELS)
	AddWhispers(rows)
	rows.under = nil
	return rows
end

-- Whether the window is still allowed to be sitting in this room. Selecting one
-- and then leaving the party has to move you somewhere rather than leave you
-- typing into nothing.
function Rooms.Exists(id)
	local fixed = byId[id]
	if fixed then
		return fixed.live() or (unread[id] or 0) > 0
	end
	for _, group in ipairs(ns.People.All()) do
		if id == "group:" .. group.key then
			return true
		end
	end
	for _, entry in ipairs(whispers) do
		if id == "whisper:" .. entry.key then
			return true
		end
	end
	return false
end

function Rooms.Title(id)
	local fixed = byId[id]
	if fixed then
		return fixed.label
	end
	for position, group in ipairs(ns.People.All()) do
		if id == "group:" .. group.key then
			return ns.People.Name(position)
		end
	end
	for _, entry in ipairs(whispers) do
		if id == "whisper:" .. entry.key then
			return entry.name:gsub("%-.*$", "")
		end
	end
	return "chat"
end

--------------------------------------------------------------------------
-- Where a line you type in this room goes
--
-- One function, and everything about the compose line is downstream of it: the
-- slash the field is filled in with, the note that says what Enter will do, and
-- the send itself. Two places that answer this would be two places to disagree.
--
-- A group is the only room that has to guess, because a group is people rather
-- than a channel. It answers whoever last spoke there, which is what you meant
-- ninety nine times in a hundred, and it says so out loud above the log rather
-- than leaving you to find out by sending. With nobody having spoken yet it
-- falls back to the party you are in, and then to say, so the field is never
-- empty and Enter never does something you were not shown.
--------------------------------------------------------------------------

local function GroupTarget(id)
	local who = speaker[id]
	if who then
		return "WHISPER", who
	end
	if InGroup() then
		return "PARTY", nil
	end
	return "SAY", nil
end

function Rooms.Target(id)
	local fixed = byId[id]
	if fixed then
		return fixed.kind, nil
	end
	if type(id) == "string" and id:sub(1, 8) == "whisper:" then
		for _, entry in ipairs(whispers) do
			if id == "whisper:" .. entry.key then
				return "WHISPER", entry.name
			end
		end
	end
	if type(id) == "string" and id:sub(1, 6) == "group:" then
		return GroupTarget(id)
	end
	return "SAY", nil
end

--------------------------------------------------------------------------
-- What you have not read
--------------------------------------------------------------------------

function Rooms.Mark(id)
	unread[id] = (unread[id] or 0) + 1
	return unread[id]
end

function Rooms.Read(id)
	if not unread[id] or unread[id] == 0 then
		return false
	end
	unread[id] = 0
	return true
end

function Rooms.Unread(id)
	return unread[id] or 0
end

function Rooms.Waiting()
	local total = 0
	for _, count in pairs(unread) do
		total = total + count
	end
	return total
end

function Rooms.Describe()
	local rows, count = Rooms.List(), 0
	for _, row in ipairs(rows) do
		if row.id then
			count = count + 1
		end
	end
	local waiting = Rooms.Waiting()
	if waiting == 0 then
		return ("%d rooms"):format(count)
	end
	return ("%d rooms, %d unread"):format(count, waiting)
end

-- Everything this file is holding that is not a saved setting. The whisper
-- rooms and the unread counts are facts about this session, so turning the part
-- off and on again starts the rail clean rather than resurrecting a
-- conversation from before the reload.
function Rooms.Wipe()
	for _, entry in ipairs(whispers) do
		local id = "whisper:" .. entry.key
		if Rooms.OnClose then
			Rooms.OnClose(id)
		end
	end
	whispers, unread, speaker = {}, {}, {}
end
