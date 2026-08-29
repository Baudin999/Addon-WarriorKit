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
-- still us.
--
-- **The button is loaded while you are still typing.** Compose.Preload runs off
-- the field's OnTextChanged, so by the time `/logout` is spelled out the enter
-- key is already carrying it and the press that finishes the line is the press
-- that runs it. Arming after the enter was the whole reason this used to take
-- two: the first press was spent loading the key it had just arrived on.
--
-- Anything that arms late still works and still takes two, because Handover
-- below is unchanged and the key it loads is the key the next press lands on.
-- That is the path a fight leaves, and the path a slash word of ours takes.
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

-- The line the button carries, when it is not the line you typed.
--
-- /exit is nobody's command in this client. The two words it knows for leaving
-- are /quit and /camp, and a button loaded with /exit would arrive at a slash
-- list with no such entry and do nothing at all, which is the one failure that
-- looks exactly like the bug this whole section exists to fix.
--
-- Translating here rather than registering /exit as a slash command of our own
-- is the difference between working and not: a command of ours is our function,
-- our function is a tainted call stack, and Quit() is refused from one. The
-- client's own /quit is Blizzard's function, and the button runs it as the
-- client's work.
local ALIAS = {
	exit = "/quit",
}

--------------------------------------------------------------------------
-- The debug log
--
-- Off by default and silent when off. It is here for the reason Hover/Cast.lua
-- has one: this fails in three places that are indistinguishable from a chair.
-- The key was never loaded, the key was loaded and the client is not delivering
-- the press, or the press arrives and the protected call at the end of it is
-- dropped. From the field all three are an enter key that did nothing.
--
-- One line where the key is written, with the client's own readback beside it.
-- One line where the press arrives. A load line with no arrived line under it
-- is the second case; both lines and no character logging out is the third.
--
-- PostClick, never PreClick, and Hover/Cast.lua paid for that lesson: PreClick
-- runs insecure Lua inside the click and before the secure handler, which taints
-- the path and drops the protected call at the end of it. An early return does
-- not save you, because the taint is the script running at all. An instrument
-- that breaks what it measures is worse than no instrument.
--------------------------------------------------------------------------

local function Log(fmt, ...)
	if not (ns.db and ns.db.chatDebug) then
		return
	end
	ns.Print("|cff808080chatkey|r " .. (select("#", ...) > 0 and fmt:format(...) or fmt))
end

local BUTTON_NAME = "WarriorKitChatSecureButton"

-- The button, once there has been a line for it, the line it is holding, and
-- the keys it is holding it on. The keys are kept rather than asked for again:
-- while the override is on them GetBindingKey answers with nothing at all, and
-- the field has to know on the key going down whether to let it past.
local secure, armed, armedKeys

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
	-- One edge, the down one, and the attribute that names it set beside it.
	--
	-- Both edges against an unset attribute is what this shipped as, and it is
	-- the shape Buttons/Bars.lua settled on a live client and wrote down: a key
	-- bound with SetOverrideBindingClick fires on whichever edge useOnKeyDown
	-- names, and with the attribute unset that edge is the down one. So the
	-- edge this has always run on is the down one, and the second press is the
	-- press that has always worked. Hover/Cast.lua pairs these two the same way
	-- and its keys cast.
	--
	-- The up edge was tried here, on the reasoning that the down edge of the
	-- press that finishes the line belongs to the field and the up edge does
	-- not. It is a good argument and the client does not agree with it, which
	-- is what three evenings of `/logout` doing nothing cost to find out. The
	-- edge that works is the one that was already working.
	--
	-- So one press is not reachable from a field that has the focus. A key of
	-- its own would be one press, because there is no field in the way of it.
	--
	-- It cannot run twice. PostClick hands the key back and empties the
	-- macrotext, so a second dispatch finds a button with nothing on it.
	made:RegisterForClicks("AnyDown")
	made:SetAttribute("useOnKeyDown", true)
	made:SetAttribute("type", "macro")
	-- The client has run the line by the time this fires. What is left is
	-- handing the enter key back to the chat window, and saying that the press
	-- arrived at all, which is the one thing the field cannot tell you.
	made:SetScript("PostClick", function(_, click, down)
		Log("arrived on %s, down %s, carrying %s", tostring(click), tostring(down),
			tostring(made:GetAttribute("macrotext")))
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
--
-- Returns false and a reason, and the reason is the point. There are three ways
-- this can refuse and they need three different things from the player: a fight
-- ends, a client with no override bindings never will, and a key that would not
-- take the claim is somebody else's key. One "it did not work" for all three is
-- the sentence that sent this bug round twice.
--
-- The window gives the key up first. Both claims are override bindings on the
-- same key, and which one a press reaches is the client's arrangement rather
-- than ours; the window keeping its claim underneath was an enter that opened
-- the chat line instead of running the line it had just said it would run. One
-- owner at a time, and Disarm hands it straight back.
function Compose.Arm(text)
	local button = Button()
	if not button or type(_G.SetOverrideBindingClick) ~= "function" then
		return false, "this client will not let the addon put a line on a key"
	end
	if _G.InCombatLockdown and _G.InCombatLockdown() then
		Log("refused %s: in combat", text)
		return false, "the addon cannot move a key in combat"
	end
	if ns.ChatWindow and ns.ChatWindow.Yield then
		ns.ChatWindow.Yield()
	end
	local bound, keys = false, {}
	for _, key in ipairs(EnterKeys()) do
		if pcall(_G.SetOverrideBindingClick, button, true, key, BUTTON_NAME, "LeftButton")
			and Carries(key) then
			bound = true
			keys[key] = true
		end
	end
	if not bound then
		Log("refused %s: no key would take it", text)
		-- Nothing is loaded, so the window takes its key back here rather than
		-- being left without one until the next thing that calls Keys.
		if ns.ChatWindow and ns.ChatWindow.Keys then
			ns.ChatWindow.Keys()
		end
		return false, "the client would not put the line on the chat key"
	end
	button:SetAttribute("macrotext", text)
	armed, armedKeys = text, keys
	for key in pairs(keys) do
		Log("loaded %s onto %s, which the client reads back as %s", text, key,
			type(_G.GetBindingAction) == "function"
				and tostring((_G.GetBindingAction(key, true))) or "nothing it can be asked")
	end
	-- The field says what the key is holding. It is the only sentence a player
	-- who has hidden Blizzard's window is certain to read, because it is under
	-- the cursor they just pressed enter on.
	if ns.ChatWindow and ns.ChatWindow.Paint then
		ns.ChatWindow.Paint()
	end
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
	armed, armedKeys = nil, nil
	if ns.ChatWindow and ns.ChatWindow.Paint then
		ns.ChatWindow.Paint()
	end
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

-- How many slash words are on the list of ones the client will not take from
-- us. A count rather than the table, because the table is the thing that has to
-- err long and a caller that could read it is a caller that could shorten it.
function Compose.Words()
	local n = 0
	for _ in pairs(SECURE) do
		n = n + 1
	end
	return n
end

-- Whether this key is one of the ones the button is loaded on. The field asks
-- on every key going down, because a field that lets every key past to the
-- binding underneath is a field where typing "1" pulls the first thing off the
-- action bar.
function Compose.ArmedOn(key)
	return (armed and armedKeys and key ~= nil and armedKeys[key]) and true or false
end

-- The line the client would only take from a key of its own, for what you have
-- typed so far, or nil for everything the client's own parser will take from us
-- in one press. The translation is here rather than at the two callers because
-- a word that is on the list at one of them and not the other is the bug this
-- whole section exists to stop.
function Compose.Secure(text)
	if type(text) ~= "string" then
		return nil
	end
	local word, rest = text:match("^/(%a+)(.*)$")
	word = word and word:lower()
	if not word or not SECURE[word] then
		return nil
	end
	-- The alias replaces the word and keeps what was typed after it, so a
	-- translation stays a translation rather than a line with its argument
	-- dropped on the floor.
	return ALIAS[word] and (ALIAS[word] .. rest) or text
end

-- Load the key while the line is still being typed, or hand it back the moment
-- what is in the field is no longer a line that needs it.
--
-- Called on every character, so it says nothing and asks nothing. A refusal
-- here is not a thing to tell the player about: the line is half typed, and
-- what happens to a line that could not take the key early is that it takes the
-- slow path through Handover on the enter, which does have something to say.
function Compose.Preload(text)
	local line = Compose.Secure(text)
	if not line then
		if armed then
			Compose.Disarm()
		end
		return false
	end
	if armed then
		if armed == line then
			return true
		end
		-- The key is already ours and only the line has changed, which is what
		-- every character after the command word does. Handing the key back and
		-- taking it again per keystroke would leave it briefly nobody's, and a
		-- key that is nobody's is a key a press can fall through.
		if _G.InCombatLockdown and _G.InCombatLockdown() then
			return false
		end
		secure:SetAttribute("macrotext", line)
		armed = line
		if ns.ChatWindow and ns.ChatWindow.Paint then
			ns.ChatWindow.Paint()
		end
		return true
	end
	return Compose.Arm(line) and true or false
end

-- What the addon has to say about a line you just typed, in the room you typed
-- it in.
--
-- ns.Print writes to Blizzard's window, and every player this window is for has
-- hidden Blizzard's window. The sentence came back round through the hook on
-- AddMessage and landed in the System room, which is not the room anybody
-- typing has open, so the handover below announced itself into an empty theatre
-- and the whole thing looked from the field like a key press that did nothing.
local function Say(text)
	if ns.ChatWindow and ns.ChatWindow.Tell and ns.ChatWindow.Tell(text) then
		return
	end
	ns.Print(text)
end

-- A line the client will only take from a key of its own. Loads it and says so.
--
-- The refusal carries the reason it was given rather than a sentence of its
-- own, because a player who is told "it did not work" three different ways for
-- three different causes learns nothing from any of them.
local function Handover(text)
	local ok, why = Compose.Arm(text)
	if ok then
		Say(("%s is the client's to run rather than the addon's, so it is on the enter key. Press enter."):format(text))
		return true
	end
	Say(("%s is the client's to run and %s. Type it in the client's own chat line."):format(text, why))
	return false
end

--------------------------------------------------------------------------
-- Leaving
--
-- /exit, because the client has no word for quitting that reads like one. /quit
-- is the word it has, and nobody types it, because every other program in the
-- world calls it exit.
--
-- The handler cannot call Quit() itself. It is our function, our function is a
-- tainted call stack, and Quit() is refused from one, which is the same wall
-- /logout hits. So it does what the field does and puts the client's own /quit
-- on the enter key.
--
-- Registered whether or not the chat part is on, because a word for leaving is
-- not a chat feature and Compose.Arm needs no window.
--------------------------------------------------------------------------

SLASH_WARRIORKITEXIT1 = "/exit"
SlashCmdList.WARRIORKITEXIT = function()
	Handover("/quit")
end

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
		local word = text:match("^/(%a+)")
		word = word and word:lower()
		if word and SECURE[word] then
			return Handover(ALIAS[word] or text)
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
