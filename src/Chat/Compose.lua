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

--------------------------------------------------------------------------
-- The commands the client will not take from us
--
-- /logout ends in Logout(), and Logout() is protected: the client refuses it
-- from any call stack an addon has been in. The field above is such a stack, so
-- what came back from typing it here was not a logout but a red line naming
-- WarriorKit. Every command that ends in a protected call is the same, which is
-- most of what people put in macros.
--
-- The way through is the way a macro gets there. A button of the secure kind
-- carries the line as its macrotext and the client runs it as its own work, on
-- the one condition that the click is a key press. A :Click() from a script is
-- still us. So the first enter loads the button and says so, and the second,
-- which the field is no longer holding because the focus went with the first,
-- runs the line.
--------------------------------------------------------------------------

-- One entry per slash word whose command ends in a protected call. Everything
-- else goes to the client's parser above and arrives in one press, because
-- /dance and /join are nobody's protected business.
--
-- A word listed here that turns out not to need it costs one extra key press
-- and nothing else, so the list errs long. A word missing from it costs the
-- blocked action this section exists to stop, so add to it when a command comes
-- back as a red line rather than as what you typed.
local SECURE = {
	-- Leaving: Logout() and Quit().
	logout = true, camp = true, quit = true, exit = true,
	-- Choosing a unit: TargetUnit, FocusUnit, AssistUnit.
	target = true, targetexact = true, targetenemy = true,
	targetfriend = true, targetlasttarget = true, cleartarget = true,
	assist = true, focus = true, clearfocus = true,
	-- Doing something: a spell, an item, the pet, a bar page, worn gear.
	cast = true, castsequence = true, castrandom = true,
	use = true, userandom = true, equip = true, equipslot = true,
	startattack = true, stopattack = true, stopcasting = true,
	cancelaura = true, cancelform = true, dismount = true,
	petattack = true, petfollow = true, petstay = true,
	petpassive = true, petdefensive = true, petaggressive = true,
	click = true, changeactionbar = true, swapactionbar = true,
}

local BUTTON_NAME = "WarriorKitChatSecureButton"

-- The button, once there has been a line for it, and the line it is holding.
local secure, armed

-- Made the first time a line needs one rather than at load, because most
-- evenings nobody types any of the words above and a secure frame is not free.
--
-- No size and no anchor, which is Marking/Keys.lua's arrangement and for its
-- reason: this is never meant to meet a real cursor, and a frame with no size
-- cannot be hit by one.
local function Button()
	if secure ~= nil then
		return secure or nil
	end
	secure = false
	if type(_G.CreateFrame) ~= "function" then
		return nil
	end
	local ok, made = pcall(_G.CreateFrame, "Button", BUTTON_NAME, _G.UIParent,
		"SecureActionButtonTemplate")
	if not ok or not made then
		return nil
	end
	made:RegisterForClicks("AnyDown")
	made:SetAttribute("type", "macro")
	-- The client has run the line by the time this fires. What is left is
	-- handing the enter key back to the chat window.
	made:SetScript("PostClick", function()
		Compose.Disarm()
	end)
	secure = made
	return made
end

-- The keys the field's enter is on, read back rather than assumed, because a
-- player who moved OPENCHAT off enter would otherwise be told to press a key
-- that does nothing.
--
-- Only true once the window has given the key up. While the chat window's own
-- override is sitting on enter, the key carries the window's button and not
-- OPENCHAT, so this asks and is told nothing at all. Every caller below yields
-- first, and the literal pair is the answer for a client that has no
-- GetBindingKey rather than one that answered no.
local function EnterKeys()
	if type(_G.GetBindingKey) == "function" then
		local ok, first, second = pcall(_G.GetBindingKey, "OPENCHAT")
		if ok and first then
			return { first, second }
		end
	end
	return { "ENTER", "NUMPADENTER" }
end

-- Whether the key really carries the button now. Read back rather than believed
-- for the reason Buttons/Bars.lua reads its own back: a client that takes the
-- call and does nothing with it leaves no other trace, and here the cost of not
-- noticing is a player told to press enter again and getting a chat line.
local function Carries(key)
	if type(_G.GetBindingAction) ~= "function" then
		return true
	end
	local ok, action = pcall(_G.GetBindingAction, key, true)
	if not ok or type(action) ~= "string" or action == "" then
		return true
	end
	return action == ("CLICK %s:LeftButton"):format(BUTTON_NAME)
end

-- Loads the line onto the button and puts the button under the enter key.
-- False when the client will not have it, which is combat: an override binding
-- is a change to the binding set and the client refuses those under lockdown.
--
-- The window gives the key up first. Both claims are override bindings on the
-- same key, and which one a press reaches is the client's arrangement rather
-- than ours; the window keeping its claim underneath was an enter that opened
-- the chat line instead of running the line it had just said it would run. One
-- owner at a time, and Disarm hands it straight back.
function Compose.Arm(text)
	local button = Button()
	if not button or type(_G.SetOverrideBindingClick) ~= "function" then
		return false
	end
	if _G.InCombatLockdown and _G.InCombatLockdown() then
		return false
	end
	if ns.ChatWindow and ns.ChatWindow.Yield then
		ns.ChatWindow.Yield()
	end
	local bound = false
	for _, key in ipairs(EnterKeys()) do
		if pcall(_G.SetOverrideBindingClick, button, true, key, BUTTON_NAME, "LeftButton")
			and Carries(key) then
			bound = true
		end
	end
	if not bound then
		-- Nothing is loaded, so the window takes its key back here rather than
		-- being left without one until the next thing that calls Keys.
		if ns.ChatWindow and ns.ChatWindow.Keys then
			ns.ChatWindow.Keys()
		end
		return false
	end
	button:SetAttribute("macrotext", text)
	armed = text
	return true
end

-- Takes the key back. Called when the line has run and when the field takes the
-- focus again, because coming back to the field is a change of mind and an
-- enter still loaded is an enter that will not open the window.
function Compose.Disarm()
	if not armed then
		return false
	end
	if _G.InCombatLockdown and _G.InCombatLockdown() then
		return false
	end
	if type(_G.ClearOverrideBindings) == "function" then
		pcall(_G.ClearOverrideBindings, secure)
	end
	secure:SetAttribute("macrotext", "")
	armed = nil
	-- The chat window owns enter the rest of the time, and this is where it
	-- gets it back rather than being assumed to have survived underneath.
	if ns.ChatWindow and ns.ChatWindow.Keys then
		ns.ChatWindow.Keys()
	end
	return true
end

-- The line the enter key is loaded with, or nil. Public because a loaded key is
-- state a player cannot see and nothing else could read it back.
function Compose.Armed()
	return armed
end

-- A line the client will only take from a key of its own. Loads it and says so,
-- in the log, where the rest of what the addon has to say already is.
local function Handover(text)
	if Compose.Arm(text) then
		ns.Print(("%s is the client's to run rather than the addon's. Press enter again and it goes."):format(text))
		return true
	end
	ns.Print(("%s is the client's to run and the addon cannot put it on a key now. Type it in the client's own chat line."):format(text))
	return false
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
		local word = text:match("^/(%a+)")
		if word and SECURE[word:lower()] then
			return Handover(text)
		end
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
