local ADDON, ns = ...

-- Everything Core and the panel need to know about the social part.
-- People.lua holds the list, Feed.lua captures what is said, Window.lua draws
-- it and Voice.lua puts you in a voice channel, and none of them names anything
-- outside this folder.
--
-- Three sections under one rail entry, because they are one subject: who you
-- play with. The people list feeds the window's first tab and the voice pick is
-- how you talk to the same people out loud.

local WIDTH_LOW, WIDTH_HIGH, WIDTH_STEP = 260, 900, 10
local HEIGHT_LOW, HEIGHT_HIGH, HEIGHT_STEP = 120, 700, 10
local FONT_LOW, FONT_HIGH = 9, 20

local function SetChat(value)
	ns.db.chat = value
	if value then
		-- Nothing is built while the part is off, so turning it on after login
		-- has to build what login skipped.
		ns.ChatWindow.Ensure()
	end
	ns.ChatFeed.Apply()
	if ns.ChatWindow.Built() then
		ns.ChatWindow.Apply()
	end
end

local function SetClaim(value)
	ns.db.chatClaim = value
	ns.ChatFeed.Apply()
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
-- The people page
--
-- The same shape the loadouts page has, because it is the same job: a strip of
-- rows with a + on the end, a field for the one you picked, and a delete. A
-- person is one name, so there is one field.
--------------------------------------------------------------------------

local function PeoplePage(ui)
	ui.Section("People", "Readouts")
	ui.Lede("Names whose every line, in any channel, is copied to the People tab of the chat window.")

	ui.Tabs(
		function()
			local labels = {}
			for index, entry in ipairs(ns.People.All()) do
				labels[index] = entry.name ~= "" and entry.name or "unnamed"
			end
			return labels
		end,
		ns.People.Shown,
		function(index) ns.People.Show(index) end,
		{
			onAdd = function()
				local index, why = ns.People.Add("")
				if not index then
					ns.Print(why .. ".")
				end
			end,
		})

	ui.TextField("name",
		function()
			local entry = ns.People.Get(ns.People.Shown())
			return entry and entry.name or ""
		end,
		function(value)
			local ok, why = ns.People.Rename(ns.People.Shown(), value)
			if not ok and why then
				ns.Print(why .. ".")
			end
			ns.ChatWindow.Apply()
		end)

	ui.Hint("The realm is not needed and is ignored if you type it, so one row covers somebody whether they are beside you or whispering from another realm.")

	ui.ActionPair(
		function()
			local size = 0
			if type(GetNumGroupMembers) == "function" then
				size = GetNumGroupMembers() or 0
			end
			if size <= 1 then
				return "add everyone in your group"
			end
			return ("add the %d with you"):format(size - 1)
		end,
		function()
			local added, skipped = ns.People.AddGroup()
			if added == 0 then
				ns.Print(skipped > 0 and "everyone with you is already on the list."
					or "you are not in a group.")
			else
				ns.Print(("%d added, %s on the list.")
					:format(added, ns.People.Describe()))
			end
			ns.ChatWindow.Apply()
		end,
		function() return true end,
		function()
			local entry = ns.People.Get(ns.People.Shown())
			if not entry then
				return "remove"
			end
			return "remove " .. (entry.name ~= "" and entry.name or "this row")
		end,
		function()
			ns.People.Remove(ns.People.Shown())
			ns.ChatWindow.Apply()
		end,
		function() return ns.People.Get(ns.People.Shown()) ~= nil end)
	ui.Hint("The list is shared by every character on this account, because who matters to you is not a fact about the character you happen to be standing in.")

	ui.Reading("rows used", function()
		return ("%d of %d"):format(ns.People.Count(), ns.People.MAX)
	end)
end

--------------------------------------------------------------------------

ns.Register({
	name = "chat",
	order = 12,

	switch = {
		key = "chat",
		label = "the chat window",
		apply = function(value) SetChat(value) end,
	},

	defaults = {
		-- On, because a part whose whole point is that the window it replaces is
		-- unreadable does not ship switched off. Everything it does is
		-- reversible in one press and nothing of Blizzard's is hidden.
		chat = true,
		chatShown = true,

		-- The conversation is taken out of Blizzard's frames rather than drawn
		-- twice. This is the setting that makes the window a replacement rather
		-- than a second copy, and it is the first one to turn off if something
		-- looks missing.
		chatClaim = true,

		-- The numbered channels are off. General and Trade are most of the
		-- volume in a city and none of the conversation, and they stay in
		-- Blizzard's window where scrolling past them costs nothing.
		chatChannels = false,

		chatStamp = true,
		chatSound = true,

		chatWidth = 440,
		chatHeight = 240,
		chatFont = 12,
		-- Not opaque. A chat window sits in a corner all evening and the world
		-- behind it is the game.
		chatAlpha = 80,
		chatPoint = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 16, 120 },

		-- Account-wide, both of them. Who matters to you and which voice channel
		-- you want to be in are facts about you rather than about one character.
		people = {},
		voiceJoin = "none",
		-- What the pick was called on the row you clicked. The communities are
		-- not loaded for the first few seconds of a session, so without this the
		-- picker and the status line spell your voice channel as the pair of
		-- numbers behind it until they are.
		voiceLabel = "",
	},

	words = {
		chat = function(arg)
			if arg == "show" then
				ns.ChatWindow.Show()
				return
			end
			if arg == "hide" then
				ns.ChatWindow.Hide()
				return
			end
			if arg == "claim" then
				SetClaim(not ns.db.chatClaim)
				ns.Print("chat " .. ns.ChatFeed.Describe() .. ".")
				return
			end
			if arg == "on" or arg == "off" then
				SetChat(arg == "on")
				ns.Print("chat window " .. (ns.db.chat and "on" or "off") .. ".")
				return
			end
			ns.ChatWindow.Toggle()
		end,

		people = function(arg, raw)
			if arg == "list" or arg == nil or arg == "" then
				if ns.People.Count() == 0 then
					ns.Print("nobody on the list. /wk people add <name>.")
					return
				end
				for _, entry in ipairs(ns.People.All()) do
					ns.Print("  " .. (entry.name ~= "" and entry.name or "an unnamed row"))
				end
				return
			end
			if arg == "group" then
				local added = ns.People.AddGroup()
				ns.Print(("%d added, %s on the list."):format(added, ns.People.Describe()))
				ns.ChatWindow.Apply()
				return
			end

			local verb, name = raw:match("^%s*(%a+)%s+(.+)$")
			if verb == "add" then
				local index, why = ns.People.Add(name)
				ns.Print(index and (name .. " is on the list.") or (why .. "."))
				ns.ChatWindow.Apply()
				return
			end
			if verb == "remove" then
				local key = ns.People.Key(name)
				for position, entry in ipairs(ns.People.All()) do
					if ns.People.Key(entry.name) == key then
						ns.People.Remove(position)
						ns.Print(name .. " is off the list.")
						ns.ChatWindow.Apply()
						return
					end
				end
				ns.Print(name .. " is not on the list.")
				return
			end
			ns.Print("people list|group|add <name>|remove <name>.")
		end,

		voice = function(arg)
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
			-- Every answer the client gave, rather than the one sentence this
			-- part decided out of them. The first bug in this part was a probe
			-- refusing a join the client would have taken, and there was no way
			-- to see which probe it was without reading the source.
			if arg == "why" then
				ns.Print("voice: " .. ns.Voice.Diagnose() .. ".")
				return
			end
			ns.Print("voice: " .. ns.Voice.Describe() .. ".")
		end,
	},

	help = {
		"chat, open or close the chat window",
		"chat on|off, draw it at all",
		"chat claim, whether the same lines still draw in Blizzard's window",
		"people list|group|add <name>|remove <name>, who gets their own tab",
		"voice, what the voice pick is doing",
		"voice group|off, join your party or raid channel, or nothing",
		"voice join, ask for it again now",
		"voice why, every answer the client gives about voice",
	},

	status = function()
		return ("window %s; feed %s; people %s; voice %s")
			:format(ns.ChatWindow.Describe(), ns.ChatFeed.Describe(),
				ns.People.Describe(), ns.Voice.Describe())
	end,

	lock = function()
		ns.ChatWindow.Lock()
	end,

	reset = function()
		ns.ChatWindow.Reset()
	end,

	panel = function(ui)
		ui.Section("Chat", "Readouts")
		ui.Lede("A chat window of the addon's own: three tabs, class coloured names, a click to answer one.")
		ui.Hint("Blizzard's window is not hidden and nothing of it is unregistered. It keeps loot, experience, system text and every addon's output, this one's included.")

		ui.Check("take those lines out of Blizzard's window",
			function() return ns.db.chatClaim end,
			SetClaim)
		ui.Hint("This is FrameXML's own filter rather than a hidden frame, so turning it off puts the conversation back in Blizzard's window on the next line, with no reload.")

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
		ui.Hint("The client's own whisper sound, and only while you are not already looking at the People tab. A sound for a line you watched arrive is a sound you turn off.")

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
		ui.Hint("There is a key for it under WarriorKit in the client's own key bindings, which opens the window and puts the cursor in the line.")

		ui.Reading("chat", function()
			if not ns.ChatFeed.Installed() then
				return "this client has no chat message filter, so both windows draw it"
			end
			return ns.ChatFeed.Describe()
		end)

		PeoplePage(ui)

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
