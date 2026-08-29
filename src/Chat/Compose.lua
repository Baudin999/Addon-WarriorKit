local ADDON, ns = ...

local Compose = {}
ns.Compose = Compose

--------------------------------------------------------------------------
-- The line you type
--
-- Where it goes, and what is already in the field when you start.
--
-- **The field is filled in with the room's own slash.** Select the party room,
-- press the key, and the line reads `/p ` with the cursor after it. That is the
-- one thing this part was asked for and it is worth saying why it is the slash
-- rather than a label beside the field, which is what the window used to have.
--
-- A label is the addon telling you where the line will go. The slash is the
-- line itself, and it is the same slash you have typed ten thousand times. You
-- can see it, you can delete it, you can change the p to a g, and everything
-- you already know about typing in this game still works: `/w Aria` from inside
-- the guild room whispers Aria and leaves the guild room where it was. There is
-- no second state anywhere saying what channel you are in, because the state is
-- the text in the field.
--
-- **A line you typed is read by the client, not by this file.** The field is
-- Blizzard's, so the enter key hands what is in it to FrameXML's own parser,
-- which knows every slash word in the game including the ones that log you out.
-- The prefix above is the whole of what this file contributes to a typed line.
--
-- What is left below is for code. Compose.Send is the path a slash word of ours
-- and the harness take, and it splits the same way the client does: a channel
-- this addon can name goes out with one SendChatMessage, and anything else goes
-- to ChatEdit_SendText. Rebuilding the second half here would mean keeping up
-- with every command in the game.
--------------------------------------------------------------------------

-- What you type for a channel, and what the client calls it. Both spellings of
-- everything, because a habit is per person: /p and /party are the same key
-- press to two different people.
--
-- /r is reply and not raid. That is the client's own arrangement and getting it
-- the wrong way round here would send a whisper meant for one person to forty.
local WORDS = {
	s = "SAY", say = "SAY",
	p = "PARTY", pa = "PARTY", party = "PARTY",
	ra = "RAID", raid = "RAID",
	rw = "RAID_WARNING", raidwarning = "RAID_WARNING",
	g = "GUILD", gc = "GUILD", guild = "GUILD",
	o = "OFFICER", officer = "OFFICER",
	y = "YELL", yell = "YELL",
	i = "INSTANCE_CHAT", instance = "INSTANCE_CHAT",
	e = "EMOTE", em = "EMOTE", me = "EMOTE", emote = "EMOTE",
	w = "WHISPER", t = "WHISPER", tell = "WHISPER", msg = "WHISPER", whisper = "WHISPER",
	r = "REPLY", reply = "REPLY",
}

-- The other direction: what to put in the field for a room. One entry per
-- channel the rooms can name, and the shortest spelling of each, because it is
-- the one already in front of the cursor and every character of it is a
-- character of the message's width.
local SLASH = {
	SAY = "/s",
	PARTY = "/p",
	RAID = "/raid",
	RAID_WARNING = "/rw",
	GUILD = "/g",
	OFFICER = "/o",
	YELL = "/y",
	INSTANCE_CHAT = "/i",
	EMOTE = "/e",
	WHISPER = "/w",
}

--------------------------------------------------------------------------

-- What the field starts with for a room, including the trailing space, so the
-- cursor lands where you would have put it.
function Compose.Prefix(kind, target)
	local slash = SLASH[kind]
	if not slash then
		return ""
	end
	if kind == "WHISPER" then
		if not target or target == "" then
			return ""
		end
		return ("%s %s "):format(slash, (target:gsub("%-.*$", "")))
	end
	return slash .. " "
end

-- The same thing in a sentence, for the note above the log that says what Enter
-- is about to do. It reads what is in the field rather than describing it,
-- because those are the two things that must never disagree.
function Compose.Note(kind, target)
	local prefix = Compose.Prefix(kind, target)
	if prefix == "" then
		return "nothing to type into"
	end
	return "enter types " .. prefix:gsub("%s+$", "")
end

--------------------------------------------------------------------------
-- Reading a typed line
--
-- Returns the channel, who it is addressed to and what to say, or nil when the
-- line is not this file's business and belongs to the client's parser.
--------------------------------------------------------------------------

local function Whisper(rest)
	local name, body = rest:match("^(%S+)%s+(.*)$")
	if not name or body == "" then
		return nil
	end
	return "WHISPER", name, body
end

function Compose.Parse(text, kind, target)
	if text:sub(1, 1) ~= "/" then
		return kind, target, text
	end

	local word, rest = text:match("^/(%a+)%s*(.*)$")
	local named = word and WORDS[word:lower()]
	if not named then
		return nil
	end

	if named == "REPLY" then
		local who = ns.Rooms.Recent()
		if not who or rest == "" then
			return nil
		end
		return "WHISPER", who, rest
	end
	if named == "WHISPER" then
		return Whisper(rest)
	end
	-- A prefix with nothing after it is somebody who changed their mind, or the
	-- field as the window filled it in and Enter pressed twice. Sending it would
	-- be an empty line in front of forty people.
	if rest == "" then
		return named, nil, ""
	end
	return named, nil, rest
end

--------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------

-- The client's own parser, for everything that is not a channel: /dance, /join,
-- another addon's command. Blizzard's field is where it has to happen, because
-- ChatEdit_SendText reads the box it is given.
--
-- Only ever reached from code. A line the player typed never comes through
-- here: it is already sitting in the client's field and the client's own enter
-- key sends it, which is the whole arrangement Chat/Field.lua sets up. What is
-- left for this is the harness and a slash word of ours that wants to say
-- something, and neither of those is a key press.
--
-- So a protected command handed to this is still refused, and that is correct
-- rather than a gap. ChatEdit_SendText called from Lua is a stack an addon has
-- been in whoever calls it, and no arrangement of ours can make code that runs
-- with no player behind it log the player out.
local function SendSlash(text)
	local box = ns.ChatField.Box()
		or (_G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.editBox)
	if not box or type(_G.ChatEdit_SendText) ~= "function" then
		ns.Print("this client will not let the addon run a slash command for you, so type it in the client's own chat line.")
		return false
	end
	box:SetText(text)
	_G.ChatEdit_SendText(box, 1)
	box:SetText("")
	return true
end

--------------------------------------------------------------------------
-- The commands the client will not take from us
--
-- There is nothing here any more, and the emptiness is the fix.
--
-- `/logout` ends in Logout(), and the client refuses Logout() from any call
-- stack an addon has been in. For a long time this file answered that with a
-- secure button: the line went onto the enter key as macrotext, the client ran
-- it as its own work on the next press, and the player was told to press enter
-- twice. Around it stood a list of thirty five slash words that might end in a
-- protected call, an alias table, a debug log, and four functions arming and
-- disarming a key binding.
--
-- All of it was compensation for one line in Chat/Window.lua that made an edit
-- box. That line is gone. The field this window types into is the client's own,
-- its OnEnterPressed is Blizzard's and set in XML, and the press that finishes
-- a command goes from the keyboard into FrameXML with nothing of ours between.
-- So `/logout` logs you out, on the first press, and no list of words is needed
-- to know which commands are special, because none of them are.
--
-- Chat/Field.lua is where the arrangement lives and why it is safe.
--------------------------------------------------------------------------

--------------------------------------------------------------------------

-- One line, in the room named by kind and target. Public because the edit box
-- is not the only thing that sends: a slash word and the harness want the same
-- path, and a send that lives inside a script handler is a send nothing else
-- can reach.
function Compose.Send(text, kind, target)
	if type(text) ~= "string" then
		return false
	end
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		return false
	end

	local channel, who, body = Compose.Parse(text, kind, target)
	if not channel then
		return SendSlash(text)
	end
	if body == "" then
		return false
	end
	if type(_G.SendChatMessage) ~= "function" then
		return false
	end

	if channel == "WHISPER" then
		if not who or who == "" then
			return false
		end
		_G.SendChatMessage(body, "WHISPER", nil, who)
		return true
	end
	_G.SendChatMessage(body, channel)
	return true
end
