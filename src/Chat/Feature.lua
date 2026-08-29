local ADDON, ns = ...

-- Everything Core and the panel need to know about the social part.
--
-- People.lua holds the groups, Rooms.lua decides which conversation a line
-- belongs to, Feed.lua captures what is said, Compose.lua turns what you type
-- into a send, Blizzard.lua takes the client's own window off the screen,
-- Window.lua draws all of it, and Voice.lua puts you in a voice channel. None
-- of them names anything outside this folder.
--
-- Three sections under one rail entry, because they are one subject: who you
-- play with. The groups feed the window's rooms and the voice pick is how you
-- talk to the same people out loud.

local WIDTH_LOW, WIDTH_HIGH, WIDTH_STEP = 320, 900, 10
local HEIGHT_LOW, HEIGHT_HIGH, HEIGHT_STEP = 140, 700, 10
local FONT_LOW, FONT_HIGH = 9, 20

local function SetChat(value)
	ns.db.chat = value
	if value then
		-- Nothing is built while the part is off, so turning it on after login
		-- has to build what login skipped.
		ns.ChatWindow.Ensure()
	else
		-- Which conversations are open and what is unread in them are facts
		-- about this session rather than settings, so turning the part off drops
		-- them. Turning it back on starts with a clean rail instead of
		-- resurrecting a whisper from before the switch.
		ns.Rooms.Wipe()
	end
	ns.ChatFeed.Apply()
	if ns.ChatWindow.Built() then
		ns.ChatWindow.Apply()
	else
		-- The window is gone and the client's has to come back with it, which
		-- Apply would have done had there been a window to apply.
		ns.ChatBlizzard.Apply()
	end
end

local function SetClaim(value)
	ns.db.chatClaim = value
	ns.ChatFeed.Apply()
	if not value and ns.db.hideBlizzChat then
		ns.Print("the conversation stays out of Blizzard's window while that window is hidden, or it would be drawn in two places and one of them is off the screen.")
	end
end

local function SetChannels(value)
	ns.db.chatChannels = value
	ns.ChatFeed.Apply()
end

local function Redraw(key, value)
	ns.db[key] = value
	ns.ChatWindow.Apply()
end

--------------------------------------------------------------------------
-- The groups page
--
-- Two strips of tabs, one under the other: your groups, and who is in the one
-- you picked. It is the loadouts page's shape twice over, because it is the
-- same job twice over, and a person is one name so there is one field under
-- each.
--------------------------------------------------------------------------

local function GroupTabs(ui)
	ui.Tabs(
		function()
			local labels = {}
			for index in ipairs(ns.People.All()) do
				labels[index] = ns.People.Name(index)
			end
			return labels
		end,
		ns.People.Shown,
		function(index) ns.People.Show(index) end,
		{
			onAdd = function()
				local index, why = ns.People.AddGroup("")
				if not index then
					ns.Print(why .. ".")
				end
				ns.ChatWindow.Apply()
			end,
		})

	ui.TextField("group name",
		function()
			local group = ns.People.Get(ns.People.Shown())
			return group and group.name or ""
		end,
		function(value)
			ns.People.RenameGroup(ns.People.Shown(), value)
			ns.ChatWindow.Apply()
		end)
end

local function MemberTabs(ui)
	ui.Tabs(
		function()
			local labels = {}
			local group = ns.People.Get(ns.People.Shown())
			for index, name in ipairs(group and group.members or {}) do
				labels[index] = name ~= "" and name or "unnamed"
			end
			return labels
		end,
		ns.People.Member,
		function(index) ns.People.ShowMember(index) end,
		{
			onAdd = function()
				local at, why = ns.People.Add(ns.People.Shown(), "")
				if not at then
					ns.Print(why .. ".")
				end
			end,
		})

	ui.TextField("name",
		function()
			local group = ns.People.Get(ns.People.Shown())
			return group and group.members[ns.People.Member()] or ""
		end,
		function(value)
			local ok, why = ns.People.Rename(ns.People.Shown(), ns.People.Member(), value)
			if not ok and why then
				ns.Print(why .. ".")
			end
			ns.ChatWindow.Apply()
		end)
end

local function GroupActions(ui)
	ui.ActionPair(
		function()
			local size = 0
			if type(GetNumGroupMembers) == "function" then
				size = GetNumGroupMembers() or 0
			end
			if size <= 1 then
				return "add everyone in your party"
			end
			return ("add the %d with you"):format(size - 1)
		end,
		function()
			local added, skipped = ns.People.AddParty(ns.People.Shown())
			if added == 0 then
				ns.Print(skipped > 0 and "everyone with you is already in this group."
					or "you are not in a group.")
			else
				ns.Print(("%d added, %s."):format(added, ns.People.Describe()))
			end
			ns.ChatWindow.Apply()
		end,
		function() return ns.People.Get(ns.People.Shown()) ~= nil end,
		function()
			local group = ns.People.Get(ns.People.Shown())
			if not group or #group.members == 0 then
				return "remove"
			end
			local name = group.members[ns.People.Member()]
			return "remove " .. ((name and name ~= "") and name or "this row")
		end,
		function()
			ns.People.Remove(ns.People.Shown(), ns.People.Member())
			ns.ChatWindow.Apply()
		end,
		function()
			local group = ns.People.Get(ns.People.Shown())
			return group ~= nil and #group.members > 0
		end)

	ui.Action(
		function()
			return "delete " .. ns.People.Name(ns.People.Shown())
		end,
		function()
			ns.People.RemoveGroup(ns.People.Shown())
			ns.ChatWindow.Apply()
		end,
		function() return ns.People.Get(ns.People.Shown()) ~= nil end)
end

local function GroupsPage(ui)
	ui.Section("Groups", "Readouts")
	ui.Lede("A room in the chat window per group, holding every line anybody in it says and every whisper you send them.")

	GroupTabs(ui)
	MemberTabs(ui)

	ui.Hint("The realm is ignored if you type it, so one row covers somebody beside you or whispering from another realm.")

	GroupActions(ui)
	ui.Hint("The groups are shared by every character on this account, because who matters to you is not a fact about the character you happen to be standing in.")

	ui.Reading("groups", function()
		return ("%d of %d, %d people"):format(ns.People.Count(), ns.People.GROUPS,
			ns.People.Total())
	end)
end

--------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------

local function RoomWord(arg)
	if not arg or arg == "" then
		for _, row in ipairs(ns.Rooms.List()) do
			if row.id then
				local waiting = ns.Rooms.Unread(row.id)
				ns.Print(("  %s%s"):format(row.label,
					waiting > 0 and (", %d unread"):format(waiting) or ""))
			end
		end
		return
	end

	for _, row in ipairs(ns.Rooms.List()) do
		if row.id and row.label:lower() == arg:lower() then
			ns.ChatWindow.Show()
			ns.ChatWindow.Go(row.id)
			return
		end
	end
	ns.Print("no room called " .. arg .. ". /wk chat room lists them.")
end

local function ChatWord(arg, raw)
	if arg == "show" then
		ns.ChatWindow.Show()
		return
	end
	if arg == "hide" then
		ns.ChatWindow.Hide()
		return
	end
	if arg == "room" then
		RoomWord((raw:match("^%s*room%s+(.+)$")))
		return
	end
	if arg == "claim" then
		SetClaim(not ns.db.chatClaim)
		ns.Print("chat " .. ns.ChatFeed.Describe() .. ".")
		return
	end
	if arg == "debug" or arg:match("^debug%s") then
		ns.db.chatDebug = ns.Command.Toggle((raw:match("^%s*debug%s+(%S+)$")))
		ns.Print(ns.db.chatDebug
			and "the log is on. Type a line the client keeps to itself and read what it says."
			or "the log is off.")
		return
	end
	if arg == "on" or arg == "off" then
		SetChat(arg == "on")
		ns.Print("chat window " .. (ns.db.chat and "on" or "off") .. ".")
		return
	end
	ns.ChatWindow.Toggle()
end

-- Everything a slash word can do to one group, once the group has been found.
-- Split off because the word itself is a dispatcher and a dispatcher that also
-- does the work is a function nobody can read.
local function GroupEdit(position, verb, name)
	if verb == "add" and name then
		local at, why = ns.People.Add(position, name)
		ns.Print(at and (name .. " is in " .. ns.People.Name(position) .. ".") or (why .. "."))
		return true
	end
	if verb == "remove" and name then
		local group = ns.People.Get(position)
		local key = ns.People.Key(name)
		for at, held in ipairs(group.members) do
			if ns.People.Key(held) == key then
				ns.People.Remove(position, at)
				ns.Print(name .. " is out of " .. ns.People.Name(position) .. ".")
				return true
			end
		end
		ns.Print(name .. " is not in " .. ns.People.Name(position) .. ".")
		return true
	end
	if verb == "party" then
		local added = ns.People.AddParty(position)
		ns.Print(("%d added, %s."):format(added, ns.People.Describe()))
		return true
	end
	if verb == "drop" then
		local was = ns.People.Name(position)
		ns.People.RemoveGroup(position)
		ns.Print(was .. " is gone.")
		return true
	end
	return false
end

local function GroupWord(arg, raw)
	if not arg or arg == "" or arg == "list" then
		if ns.People.Count() == 0 then
			ns.Print("no groups. /wk group new <name>.")
			return
		end
		for index, group in ipairs(ns.People.All()) do
			ns.Print(("  %s: %s"):format(ns.People.Name(index),
				#group.members > 0 and table.concat(group.members, ", ") or "nobody yet"))
		end
		return
	end

	if arg == "new" then
		local name = raw:match("^%s*new%s+(.+)$")
		local index, why = ns.People.AddGroup(name or "")
		ns.Print(index and ((name or "a group") .. " is a group.") or (why .. "."))
		ns.ChatWindow.Apply()
		return
	end

	local which, verb, name = raw:match("^%s*(%S+)%s+(%a+)%s*(.*)$")
	local position = which and ns.People.Find(which)
	if position and GroupEdit(position, verb, name ~= "" and name or nil) then
		ns.ChatWindow.Apply()
		return
	end
	ns.Print("group list|new <name>|<group> add <name>|<group> remove <name>|<group> party|<group> drop.")
end

local function VoiceWord(arg)
	if arg == "off" then
		ns.Voice.Set(ns.Voice.NONE)
		ns.Print("voice: " .. ns.Voice.Describe() .. ".")
		return
	end
	if arg == "group" then
		ns.Voice.Set(ns.Voice.GROUP)
		ns.Print("voice: " .. ns.Voice.Describe() .. ".")
		return
	end
	if arg == "join" then
		local _, why = ns.Voice.Apply(true)
		ns.Print("voice: " .. why .. ".")
		return
	end
	-- The same door the microphone at the foot of the chat rail opens, on the
	-- keyboard. It goes to the client's own Chat Channels window, which is where
	-- the voice roster and the volume per person are.
	if arg == "who" or arg == "open" then
		local ok, what = ns.Voice.Open()
		ns.Print("voice: " .. (ok and ("opened " .. what) or what) .. ".")
		return
	end
	-- Every answer the client gave, rather than the one sentence this part
	-- decided out of them. The first bug in this part was a probe refusing a
	-- join the client would have taken, and there was no way to see which probe
	-- it was without reading the source.
	if arg == "why" then
		ns.Print("voice: " .. ns.Voice.Diagnose() .. ".")
		return
	end
	ns.Print("voice: " .. ns.Voice.Describe() .. ".")
end

--------------------------------------------------------------------------

ns.Register({
	name = "chat",
	order = 14,

	switch = {
		key = "chat",
		label = "the chat window",
		apply = function(value) SetChat(value) end,
	},

	defaults = {
		-- On, because a part whose whole point is that the window it replaces is
		-- unreadable does not ship switched off. Everything it does is
		-- reversible in one press and nothing of Blizzard's is destroyed.
		chat = true,

		-- The conversation is taken out of Blizzard's frames rather than drawn
		-- twice. This is the setting that makes the window a replacement rather
		-- than a second copy, and it is the first one to turn off if something
		-- looks missing.
		chatClaim = true,

		-- Blizzard's window goes off the screen, for the reason the part is on
		-- at all: a chat window whose whole point is that the one it replaces
		-- is unreadable does not ship beside it. Loot, experience, system text
		-- and every addon's output move to the System room, and the enter key
		-- moves to this window's line, because the line the client's own enter
		-- opens would be behind a window nobody can see.
		--
		-- Named the way the other six are and drawn on their page, because it
		-- answers the same question they do. The mechanism is Chat/Blizzard.lua
		-- and the switch is one line in UnitFrames/Blizzard.lua's table.
		hideBlizzChat = true,

		-- The room's own slash, put in the line when you start typing in it.
		-- This is the part's headline behaviour and it is a setting because it
		-- is also a habit: somebody who types /p by hand every time wants an
		-- empty field, and one tick gives them one.
		chatPrefix = true,

		-- The numbered channels are off. General and Trade are most of the
		-- volume in a city and none of the conversation, and they stay in
		-- Blizzard's window where scrolling past them costs nothing.
		chatChannels = false,

		chatStamp = true,
		chatSound = true,

		-- What the last attempt to build the window did. The one saved variable
		-- in the addon that is not a setting, and Chat/Window.lua's Note says
		-- why it has to be saved rather than held in memory: the failure it
		-- reports is one where the window that would print it is the window that
		-- did not build.
		chatWhy = "",

		-- Small. The rail is one icon wide rather than a hundred pixels of
		-- words, there is no title bar over it and no heading row under that,
		-- so the same message and the same number of lines fit in a rectangle
		-- a third smaller than the one this shipped with. Both steppers are
		-- still there for anyone who wants the window bigger.
		chatWidth = 400,
		chatHeight = 210,
		-- One under the interface's body size. The log is a wall of text read
		-- from the corner of the eye rather than a label you aim at, and a
		-- point off it buys another line of what somebody said in the same
		-- rectangle. The stepper goes to twenty for anyone who wants it back.
		chatFont = 11,
		-- Not opaque. A chat window sits in a corner all evening and the world
		-- behind it is the game.
		chatAlpha = 80,
		chatPoint = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 16, 120 },

		-- Account-wide, all of them. Who matters to you and which voice channel
		-- you want to be in are facts about you rather than about one character.
		groups = {},
		-- The number the next group's key comes off. A room is named by that key
		-- rather than by the group's position, so deleting the first group does
		-- not hand its unread lines to the second.
		groupSeq = 0,
		voiceJoin = "none",
		-- What the pick was called on the row you clicked. The communities are
		-- not loaded for the first few seconds of a session, so without this the
		-- picker and the status line spell your voice channel as the pair of
		-- numbers behind it until they are.
		voiceLabel = "",
	},

	words = {
		chat = ChatWord,
		group = GroupWord,
		voice = VoiceWord,
	},

	help = {
		"chat, open or close the chat window",
		"chat on|off, draw it at all",
		"chat room, list the rooms; chat room <name>, go to one",
		"chat claim, whether the same lines still draw in Blizzard's window",
		"chat debug on|off, say where a line the client keeps to itself gets to",
		"group, list your groups and who is in them",
		"group new <name>, group <group> add|remove <name>, group <group> party",
		"voice, what the voice pick is doing",
		"voice group|off, join your party or raid channel, or nothing",
		"voice join, ask for it again now",
		"voice who, the client's own window, for who is in it and how loud",
		"voice why, every answer the client gives about voice",
	},

	status = function()
		return ("window %s; feed %s; Blizzard's %s; %s; voice %s")
			:format(ns.ChatWindow.Describe(), ns.ChatFeed.Describe(),
				ns.ChatBlizzard.Describe(), ns.People.Describe(), ns.Voice.Describe())
	end,

	lock = function()
		ns.ChatWindow.Lock()
	end,

	reset = function()
		ns.ChatWindow.Reset()
	end,

	panel = function(ui)
		ui.Section("Chat", "Readouts")
		ui.Lede("A window of the addon's own: a room per conversation, and that room's own slash already in the line.")
		ui.Check("take those lines out of Blizzard's window",
			function() return ns.db.chatClaim end,
			SetClaim)
		ui.Hint("FrameXML's own filter rather than a hidden frame, so turning it off puts the conversation back in Blizzard's window on the next line. It stays on while that window is hidden.")

		ui.Check("start the line with the room's slash",
			function() return ns.db.chatPrefix end,
			function(value) Redraw("chatPrefix", value) end)
		ui.Hint("In the party room the field reads /p with the cursor after it. Change the p to a g and it goes to guild instead.")

		ui.Check("include the numbered channels",
			function() return ns.db.chatChannels end,
			SetChannels)
		ui.Hint("General, Trade and anything else you have joined. They are most of the volume in a city and none of the conversation, which is why they are off.")

		ui.Check("a timestamp on every line",
			function() return ns.db.chatStamp end,
			function(value) Redraw("chatStamp", value) end)

		ui.Check("a sound when one of your people speaks",
			function() return ns.db.chatSound end,
			function(value) Redraw("chatSound", value) end)
		ui.Hint("The client's own whisper sound, and only while you are not already reading one of your groups.")

		ui.Gap()
		ui.Size("width", WIDTH_LOW, WIDTH_HIGH, WIDTH_STEP,
			function() return ns.db.chatWidth end,
			function(value) Redraw("chatWidth", value) end)
		ui.Size("height", HEIGHT_LOW, HEIGHT_HIGH, HEIGHT_STEP,
			function() return ns.db.chatHeight end,
			function(value) Redraw("chatHeight", value) end)
		ui.Size("text size", FONT_LOW, FONT_HIGH, 1,
			function() return ns.db.chatFont end,
			function(value) Redraw("chatFont", value) end)
		ui.Opacity("background",
			function() return ns.db.chatAlpha end,
			function(value) Redraw("chatAlpha", value) end)
		ui.Hint("There is no drag handle on the corner: resizing on the mouse means reflowing every wrapped line on every mouse move, and two steppers say the same thing exactly.")

		ui.Action(function()
			return ns.ChatWindow.Built() and "open the chat window" or "not built yet"
		end,
			function() ns.ChatWindow.Show() end,
			function() return ns.ChatWindow.Built() end)
		ui.Hint("There is a key for it under WarriorKit in the client's own key bindings. Hiding Blizzard's window gives the enter key that job instead.")

		ui.Reading("chat", function()
			if not ns.ChatFeed.Installed() then
				return "this client has no chat message filter, so both windows draw it"
			end
			return ns.ChatFeed.Describe()
		end)
		ui.Reading("rooms", ns.Rooms.Describe)
		ui.Reading("Blizzard's window", ns.ChatBlizzard.Describe)
		ui.Reading("the last build", ns.ChatWindow.Why)

		GroupsPage(ui)

		ui.Section("Voice", "Readouts")
		ui.Lede("Joins one of the client's own voice channels for you at every login.")
		ui.Picker("join at login",
			function() return ns.db.voiceJoin end,
			function(value) ns.Voice.Set(value) end,
			function() return ns.Voice.Options() end)
		ui.Hint("A channel does not have to exist to be picked: this asks again at every login, at every roster change and whenever the voice service comes back, then stops after five refusals.")

		ui.Action(function() return "join it now" end,
			function()
				local _, why = ns.Voice.Apply(true)
				ns.Print("voice: " .. why .. ".")
				ns.Options.Refresh()
			end,
			function() return ns.db.voiceJoin ~= ns.Voice.NONE end)
		ui.Hint("This only ever joins. Nothing here leaves a channel, mutes anyone, picks a device or moves a volume: those are the client's own settings.")

		ui.Reading("voice", function()
			local ok, why = ns.Voice.Supported()
			return ok and ns.Voice.Describe() or why
		end)
		ui.Reading("the last attempt", ns.Voice.Diagnose)
	end,
})
