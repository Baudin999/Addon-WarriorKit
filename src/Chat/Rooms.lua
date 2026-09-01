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
-- The picture on a room
--
-- The rail is a column of icons twenty six pixels wide and the label is in the
-- hover, so this is what you actually navigate by. Every one is a texture the
-- client has shipped since the first release, because a path that does not
-- resolve draws a green question mark and writes nothing to the log.
--
-- They are chosen to be told apart at sixteen pixels rather than to be right in
-- a glossary. Say is a shout, because say carries yells and emotes as well.
-- Your groups are the prayer, because a group is the people you would answer
-- first and nothing else in the set is a huddle of figures.
local ICON = "Interface\\Icons\\"
Rooms.ICONS = {
	all      = ICON .. "INV_Misc_Note_01",
	system   = ICON .. "INV_Misc_Gear_01",
	say      = ICON .. "Ability_Warrior_BattleShout",
	party    = ICON .. "INV_Misc_GroupLooking",
	raid     = ICON .. "INV_Misc_GroupNeedMore",
	instance = ICON .. "INV_Misc_Key_04",
	guild    = ICON .. "INV_Shirt_GuildTabard_01",
	group    = ICON .. "Spell_Holy_PrayerOfHealing",
	whisper  = ICON .. "INV_Letter_15",
}

--------------------------------------------------------------------------
-- The rooms that are not made by you
--
--   id       what a line is routed to and what the rail selects by
--   label    what the row says, and what its hover says in the rail
--   icon     the picture on its row
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

-- Every fixed room is named after its own icon, so the picture is looked up by
-- the id rather than written twice.
for _, list in ipairs({ TOP, CHANNELS }) do
	for _, room in ipairs(list) do
		room.icon = Rooms.ICONS[room.id]
	end
end

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

-- Rooms holding lines brought back from the saved transcript.
--
-- A fixed room is drawn while one of these is true of it, the same way it is
-- drawn while it holds something unread. The party you were in last night is
-- not a party you are in now, and without this the room would come off the
-- rail at the login that restored it and take the evening's conversation with
-- it.
local brought = {}

-- Set by whoever draws, the same way ns.ChatFeed.OnLine is. Called with the id
-- of a whisper room that has fallen off the end, so the log behind it can be
-- emptied and handed to the next conversation rather than kept forever.
Rooms.OnClose = nil

--------------------------------------------------------------------------
-- Reading an id
--
-- A room id is either the name of a fixed room or one of two prefixes and a
-- key. Four functions below used to spell that out for themselves, each with
-- its own `id:sub(1, 6) == "group:"` and its own loop over the whispers, and
-- the prefix was written as a literal in nine places. One reader, so the shape
-- of an id is decided once.
--------------------------------------------------------------------------

local GROUP, WHISPER = "group:", "whisper:"

-- The fixed room, or nil where the id names one of yours.
local function Fixed(id)
	return byId[id]
end

-- The key after a prefix, or nil where the id is not that kind.
local function Keyed(id, prefix)
	if type(id) ~= "string" or id:sub(1, #prefix) ~= prefix then
		return nil
	end
	return id:sub(#prefix + 1)
end

-- The conversation this id names, by the key in it.
local function Whispered(id)
	local key = Keyed(id, WHISPER)
	if not key then
		return nil
	end
	for _, entry in ipairs(whispers) do
		if entry.key == key then
			return entry
		end
	end
	return nil
end

-- The group this id names, and where it sits, because a group's name is read
-- off its position rather than off the group itself.
local function Grouped(id)
	local key = Keyed(id, GROUP)
	if not key then
		return nil
	end
	for position, group in ipairs(ns.People.All()) do
		if group.key == key then
			return group, position
		end
	end
	return nil
end

-- Whether this id names one of your groups. Asked by the window, which plays a
-- sound for a line in a group you are not already reading.
function Rooms.IsGroup(id)
	return Keyed(id, GROUP) ~= nil
end

--------------------------------------------------------------------------
-- Whisper rooms
--------------------------------------------------------------------------

function Rooms.WhisperId(name)
	local key = ns.People.Key(name)
	return key and (WHISPER .. key) or nil
end

-- A conversation you are already having, moved to the front. Which is what
-- keeps the rail in the order you would look for it in, and is also what
-- decides who is dropped when a ninth person speaks.
local function Promote(key, name)
	for at, entry in ipairs(whispers) do
		if entry.key == key then
			entry.name = name
			table.remove(whispers, at)
			table.insert(whispers, 1, entry)
			return true
		end
	end
	return false
end

-- The least recent conversations, off the end of the rail. Everything anybody
-- said is still in Conversation.
local function Sink()
	while #whispers > WHISPERS do
		local dropped = table.remove(whispers)
		local id = WHISPER .. dropped.key
		unread[id], speaker[id], brought[id] = nil, nil, nil
		if Rooms.OnClose then
			Rooms.OnClose(id)
		end
	end
end

-- The room for a conversation with one person, made if this is the first thing
-- either of you has said.
function Rooms.Whisper(name)
	local key = ns.People.Key(name)
	if not key then
		return nil
	end
	if not Promote(key, name) then
		table.insert(whispers, 1, { key = key, name = name })
		Sink()
	end
	-- The saved record is this list in this order, so it is written where the
	-- order moves rather than at each of the two things that move it.
	ns.ChatHistory.Talked(whispers)
	return WHISPER .. key
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
			local id = GROUP .. group.key
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

local function Add(rows, id, label, header, icon)
	if header and rows.under ~= header then
		rows[#rows + 1] = { header = header }
		rows.under = header
	end
	rows[#rows + 1] = { id = id, label = label, icon = icon,
		unread = unread[id] or 0 }
end

local function AddGroups(rows)
	for position, group in ipairs(ns.People.All()) do
		Add(rows, GROUP .. group.key, ns.People.Name(position), "Groups",
			Rooms.ICONS.group)
	end
end

local function AddWhispers(rows)
	for _, entry in ipairs(whispers) do
		Add(rows, WHISPER .. entry.key, entry.name:gsub("%-.*$", ""), "Whispers",
			Rooms.ICONS.whisper)
	end
end

local function AddFixed(rows, list)
	for _, room in ipairs(list) do
		local id = room.id
		if room.live() or (unread[id] or 0) > 0 or brought[id] then
			Add(rows, id, room.label, room.under, room.icon)
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
	local fixed = Fixed(id)
	if fixed then
		return fixed.live() or (unread[id] or 0) > 0 or brought[id] == true
	end
	return (Grouped(id) or Whispered(id)) ~= nil
end

-- The picture for one room, by id. The rail asks through Rooms.List; this is
-- for anything holding an id on its own, which is the window's hover.
function Rooms.Icon(id)
	local fixed = Fixed(id)
	if fixed then
		return fixed.icon
	end
	if Keyed(id, GROUP) then
		return Rooms.ICONS.group
	end
	if Keyed(id, WHISPER) then
		return Rooms.ICONS.whisper
	end
	return Rooms.ICONS.all
end

function Rooms.Title(id)
	local fixed = Fixed(id)
	if fixed then
		return fixed.label
	end
	local _, position = Grouped(id)
	if position then
		return ns.People.Name(position)
	end
	local entry = Whispered(id)
	if entry then
		return (entry.name:gsub("%-.*$", ""))
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
	local fixed = Fixed(id)
	if fixed then
		return fixed.kind, nil
	end
	local entry = Whispered(id)
	if entry then
		return "WHISPER", entry.name
	end
	if Keyed(id, GROUP) then
		return GroupTarget(id)
	end
	return "SAY", nil
end

--------------------------------------------------------------------------
-- The other direction: which room a channel is
--
-- Rooms.Target answers where a line typed in this room goes. This answers the
-- reverse, and the reverse is a real question because the field is the state.
-- Typing `/p` into the line does not leave `/p` in it: the client reads the
-- slash, sets the field's channel from it and takes the slash back out. So a
-- player who types `/p` has chosen the party room by the only means the design
-- offers, and without this the rail went on saying Conversation, the room's own
-- slash was written back over theirs the next time the line opened, and the two
-- halves of "what you are reading is what you are typing into" had come apart.
--
-- More kinds than there are rooms, because Say carries yells and emotes and the
-- guild room carries officer chat. Those are the same conversation and splitting
-- them would be rooms that are empty all evening.
--------------------------------------------------------------------------

local ROOM_FOR = {
	SAY = "say", YELL = "say", EMOTE = "say",
	PARTY = "party", PARTY_LEADER = "party",
	RAID = "raid", RAID_LEADER = "raid", RAID_WARNING = "raid",
	INSTANCE_CHAT = "instance", INSTANCE_CHAT_LEADER = "instance",
	GUILD = "guild", OFFICER = "guild",
}

function Rooms.For(kind, target)
	if kind == "WHISPER" then
		-- Only a conversation that is already on the rail. The name arrives one
		-- letter at a time while somebody types `/w Aria`, and a room made off
		-- each of them is a rail filling with Ar and Ari.
		local id = target and Rooms.WhisperId(target)
		return (id and Whispered(id)) and id or nil
	end
	return ROOM_FOR[kind]
end

-- The room you would be talking in, or nil where that is nobody in particular.
--
-- What this is for is the moment you join a party. The rail grows a party room,
-- nothing selects it, and the first thing you type goes to say in front of the
-- two strangers standing beside you. The window moves itself on this, and only
-- ever out of Conversation: a room you picked is a room you picked.
--
-- The order is narrowest first. In a dungeon group the channel everybody is
-- reading is the instance one, and in a raid it is the raid, and both of those
-- are live at the same time as party.
local TALKING = { "instance", "raid", "party" }

function Rooms.Talking()
	for _, id in ipairs(TALKING) do
		local room = byId[id]
		if room and room.live() then
			return id
		end
	end
	return nil
end

--------------------------------------------------------------------------
-- What survives a reload
--
-- Two rooms out of the thirteen, and the two are the whole of the reason this
-- part has a record on disk at all.
--
-- A whisper is a conversation with one person and half of one is not a
-- conversation, so the answer you gave last night has to still be under the
-- question you were asked. Party chat is where the summon location, the pull
-- order and the number somebody linked go, and an addon update in the middle
-- of an evening used to take all three.
--
-- Everything else is left to go. Say is the people standing near you and they
-- are not standing there any more. Guild and the numbered channels are a room
-- full of strangers, which is the volume this window exists to get away from.
-- A raid is forty people over one evening, and forty people would push every
-- whisper you had off the end of a transcript with a cap on it, which is the
-- one way this could be made worse rather than better.
--
-- A group room is not asked about here and does not need to be. A line in one
-- arrived on a channel, and it is kept when that channel is kept: a whisper
-- from your wife carries her group's room with it, and a guild line from her
-- does not.
--------------------------------------------------------------------------

function Rooms.Kept(rooms)
	for _, id in ipairs(rooms) do
		if id == "party" or Keyed(id, WHISPER) then
			return true
		end
	end
	return false
end

-- Whether a room named in the record is a room there is still such a thing as.
--
-- The fixed ones always are. A conversation is one the record itself brought
-- back. A group is one you have not deleted since, and that is the clause that
-- earns this function: a line filed under a group you dropped last week would
-- otherwise make a log for a room the rail never draws, and a log is a frame
-- this client cannot destroy.
local function Restorable(id)
	if Fixed(id) then
		return true
	end
	if Keyed(id, WHISPER) then
		return Whispered(id) ~= nil
	end
	if Keyed(id, GROUP) then
		return Grouped(id) ~= nil
	end
	return false
end

-- Once, and the latch is the point rather than an optimisation. This is called
-- from the window's build, the window is built again whenever the part is
-- turned back on, and a second pass would draw yesterday's evening twice.
local restored = false

-- The conversations put back on the rail, and the lines handed to whoever
-- draws. Nothing here touches a log or a frame: this file has never known what
-- one is, and the restore is not the place to start.
function Rooms.Restore()
	if restored then
		return {}
	end
	restored = true

	local talked, lines = ns.ChatHistory.Read()
	for _, name in ipairs(talked) do
		local key = ns.People.Key(name)
		if key and #whispers < WHISPERS then
			whispers[#whispers + 1] = { key = key, name = name }
		end
	end

	local out = {}
	for _, held in ipairs(lines) do
		local rooms = {}
		for _, id in ipairs(held.rooms) do
			if Restorable(id) then
				rooms[#rooms + 1] = id
				brought[id] = true
			end
		end
		if #rooms > 0 then
			out[#out + 1] = { rooms = rooms, line = held.line,
				r = held.r, g = held.g, b = held.b }
		end
	end
	return out
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
		local id = WHISPER .. entry.key
		if Rooms.OnClose then
			Rooms.OnClose(id)
		end
	end
	whispers, unread, speaker, brought = {}, {}, {}, {}
	restored = false
end
