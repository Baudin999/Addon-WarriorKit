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
-- **The parser is ours down to the slash and the client's after it.** Every
-- prefix in the table below is a channel this addon can send to with one
-- SendChatMessage, and it does, because that is exact and needs nothing of
-- FrameXML. Anything else with a slash in front of it is the client's business,
-- from /dance to another addon's command, and goes to ChatEdit_SendText, which
-- is what Blizzard's own field calls. Rebuilding that half here would mean
-- keeping up with every command in the game.
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
local function SendSlash(text)
	local box = _G.ChatFrame1EditBox or (_G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.editBox)
	if not box or type(_G.ChatEdit_SendText) ~= "function" then
		ns.Print("this client will not let the addon run a slash command for you, so type it in the client's own chat line.")
		return false
	end
	box:SetText(text)
	_G.ChatEdit_SendText(box, 1)
	box:SetText("")
	return true
end

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
