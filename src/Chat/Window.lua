local ADDON, ns = ...

local ChatWindow = {}
ns.ChatWindow = ChatWindow

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The chat window
--
-- A column of rooms down the left, the room you picked filling the rest, and
-- one line to type in. Everything in it comes out of UI/: the chrome is
-- UI.Window, the column is UI.List, each log is UI.Log, the bar beside it is
-- UI.ScrollBar and the colours and the pixel metrics are the theme's. There is
-- no Blizzard template anywhere in it and no art asset behind it.
--
-- **Why a column of rooms and not a row of tabs.**
--
-- The window this replaced had three tabs. Three is what fits across the top of
-- a chat window, and that number is what decided the design rather than
-- anything about a conversation: everything anyone said went in one column,
-- because there was nowhere else to put it. A rail has room for thirteen, so a
-- room can be one conversation instead of one compromise. Your party is a room.
-- Your guild is a room. Each family member whispering you is a room. What was
-- one river with a search problem is a list with a count against each name.
--
-- The other half of it is that a tab strip only ever answered where you were
-- reading. This rail answers where you are talking, because they are the same
-- thing now: the room you have selected is the channel the line goes to, and
-- Chat/Compose.lua puts that room's own slash in the field when you start
-- typing. There is no channel button beside the field any more, no second piece
-- of state to disagree with the first, and nothing to press twice.
--
-- **What marks a room.** A count of what arrived while you were reading
-- somewhere else, in the accent colour in the corner of its icon, and the icon
-- brighter than a room with nothing in it. Selecting a room clears its own
-- count. That is the whole of the alert design: no flashing, no toast, no sound
-- unless somebody in one of your groups spoke.
--
-- **Why the rail is icons and the window has no title bar.**
--
-- Both are the same sum. Thirteen room names are a hundred and four pixels of
-- every line anybody said, spent labelling rooms you know by sight; a title bar
-- is twenty four more naming a window you have had open all evening; the
-- heading and the note under it were twenty eight under that. That is a third
-- of a small chat window given over to captions.
--
-- Nothing they said was thrown away. A room's name, what the enter key would do
-- in it and how much is waiting are in its hover. Which room you are in and
-- what enter will do are written into the empty line you type on, which is
-- where you are looking when it matters and is the same argument the slash in
-- the field has always been.
--
-- **There is no close box, and no saved hidden state.** A cross sat at the foot
-- of the rail once. It took the conversation off the screen in one press, wrote
-- that down, and left nothing behind saying where it had gone, so the window
-- stayed gone across reloads and the way back was a slash word you had to know.
-- The way to be rid of the window is the setting that turns the part off, which
-- is where every other part of this addon is switched off and which the panel
-- lists. /wk chat still hides it for the session, and a reload brings it back.
--------------------------------------------------------------------------

local FRAME_NAME = "WarriorKitChat"

-- The buttons the client's two chat keys are bound onto while Blizzard's window
-- is hidden. A name is what SetOverrideBindingClick binds to, which is the whole
-- reason either frame is named at all.
--
-- Two rather than one, because the client has two keys and they do different
-- things. Enter opens an empty line. Slash opens a line with a slash already in
-- it, which is how every slash command in the game gets typed, and a player who
-- presses it expecting that and gets an empty line has to type the character
-- again.
local ENTER_NAME = "WarriorKitChatEnterButton"
local SLASH_NAME = "WarriorKitChatSlashButton"

local window, rail, entry, enterButton, slashButton, voice

-- Where a log goes and how big it is, written in the layout section below and
-- named here because the log pool above needs it: a room's log is made the
-- first time somebody speaks in that room, which is after the layout ran.
local Frame, Place

-- One log per room that has ever held a line, and the ones whose rooms have
-- gone. A frame cannot be destroyed on this client, so a whisper conversation
-- that fell off the end of the rail leaves its log here to be emptied and given
-- to the next one rather than kept forever.
local logs, spare, every = {}, {}, {}

local active
local built = false

-- Work the client refused because combat was up, retried at
-- PLAYER_REGEN_ENABLED. Only the enter key can land here: everything else this
-- window does is an ordinary frame and works in a fight.
local pending = false

--------------------------------------------------------------------------
-- What the last attempt did
--
-- One sentence, written at every step of standing the window up, and written to
-- the saved variables as well as to this local.
--
-- The saved copy is the point. The failure this is for is the one nobody can
-- see: no window on the screen, the client swallowing the error because
-- scriptErrors ships off, and Blizzard's own window left up by the coupling
-- that is meant to be a safety net. Three silences, and every one of them looks
-- from the outside like a part that did nothing. A sentence in a local is no
-- help there, because the thing that would print it is the window that did not
-- build; a sentence in the saved file is still there after the reload, and the
-- panel, `/wk status` and anyone reading WTF all get the same answer out of it.
--
-- It is a saved variable that is not a setting, which is the one of those in the
-- addon. It earns that by being the only channel out of a failure that has no
-- other channel.
local said = "nothing has tried to build it yet"

local function Note(why)
	said = why
	if ns.db then
		ns.db.chatWhy = why
	end
	return why
end

-- Where the window came out, in physical pixels off the bottom left of the
-- screen.
--
-- This is the whole diagnostic on the success path, and it exists because
-- "built" and "shown" are both true in the two cases that look identical from a
-- chair: a window that came out at no size, and a window that landed off the
-- edge of the screen. Neither raises, neither prints, and both read straight
-- off these numbers.
local function Placed()
	local frame = window.frame
	local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
	local left = frame.GetLeft and frame:GetLeft()
	local bottom = frame.GetBottom and frame:GetBottom()
	if not left or not bottom then
		return ("open at %d by %d units and anchored to nothing the client will "
			.. "resolve, which is a window with no place on the screen")
			:format(math.floor(frame:GetWidth() or 0), math.floor(frame:GetHeight() or 0))
	end
	return ("open, %d by %d px at %d across and %d up, alpha %.2f, strata %s")
		:format(math.floor((frame:GetWidth() or 0) * scale),
			math.floor((frame:GetHeight() or 0) * scale),
			math.floor(left * scale), math.floor(bottom * scale),
			frame:GetAlpha() or 1,
			frame.GetFrameStrata and frame:GetFrameStrata() or "unknown")
end

--------------------------------------------------------------------------
-- Logs
--------------------------------------------------------------------------

local function LogFor(id)
	local log = logs[id]
	if log then
		return log
	end

	log = table.remove(spare)
	if log then
		log:Clear()
	else
		local made, why = UI.Log(window.content, { onLink = ChatWindow.OnLink })
		if not made then
			ns.Print("no chat window: " .. why .. ".")
			return nil
		end
		log = made
		every[#every + 1] = log
	end

	-- Placed here rather than only in Relayout, because a room's log is made on
	-- the first line that lands in it and that is usually long after the window
	-- was laid out.
	Place(log)
	log.frame:Hide()
	logs[id] = log
	return log
end

-- A room that has gone. Its log is emptied and put back in the pool, because
-- the alternative is one ScrollingMessageFrame per person you have ever
-- whispered, kept for the session.
local function Close(id)
	local log = logs[id]
	if not log then
		return false
	end
	logs[id] = nil
	log.frame:Hide()
	log:Clear()
	spare[#spare + 1] = log
	return true
end

--------------------------------------------------------------------------
-- Which room is up
--------------------------------------------------------------------------

-- What the empty line says: which room you are in, and what the enter key is
-- about to do in it.
--
-- It is written into the field rather than above the log, and that is what
-- replaced the heading row and the note beside it. Those two cost twenty eight
-- pixels of every window to answer a question the field itself is the answer
-- to, and they answered it in the one place you are not looking when you start
-- typing. Here it is under the cursor, and the moment there is a character in
-- the line it gets out of the way, because from then on the line says it.
local function Paint()
	local kind, target = ns.Rooms.Target(active)
	entry.ghost:SetText(("%s, %s"):format(ns.Rooms.Title(active),
		ns.Compose.Note(kind, target)))
end

local function Show(id)
	active = id
	for _, log in ipairs(every) do
		log.frame:SetShown(logs[id] == log)
	end
	local log = logs[id]
	if log then
		log:Sync()
	end
	ns.Rooms.Read(id)
	rail:Mark(id, 0)
	Paint()
end

-- The column, rebuilt from what exists right now. Called when a room appears or
-- goes away, which is a roster change, a guild change, a group edited in the
-- panel and the first whisper from somebody new. Not called per line: a line
-- moves one number and List:Mark is what moves it.
-- The microphone, painted for the answer to one question: are you in a voice
-- channel right now. Green for yes and the quiet grey every unclickable thing
-- in this interface is drawn in for no.
--
-- Two colours rather than three. "Voice is off in the client's settings" and
-- "you picked nothing" and "the channel has not come up yet" are all the same
-- thing from a chair, which is that nobody can hear you, and the sentence that
-- tells them apart is one hover away in Voicing below.
local function Lit()
	if not built then
		return false
	end
	local on = ns.Voice.Active() and true or false
	local color = on and C.tick or C.quiet
	voice.text:SetTextColor(color[1], color[2], color[3])
	return on
end

-- What the microphone's hover says. All three of the things the colour cannot:
-- which channel, what the setting is doing about it, and what the click opens.
local function Voicing()
	local ok, why = ns.Voice.Supported()
	local channel = ok and ns.Voice.Active()
	return {
		title = "Voice",
		{ ok and ns.Voice.Describe() or why },
		{ channel and "Who is in it, and how loud each of them is."
			or "Opens the client's own Chat Channels window." },
	}
end

local function Refresh()
	local rows = ns.Rooms.List()
	rail:Set(rows)
	if not ns.Rooms.Exists(active) then
		-- Whatever you were reading has stopped existing, which is what leaving
		-- a party looks like from here. Everything is where a line always is.
		Show(ns.Rooms.ALL)
	end
	rail:Select(active)
	Paint()
	Lit()
end

--------------------------------------------------------------------------
-- Lines arriving
--
-- A line goes to every room it belongs to, and each room holds its own copy,
-- because each has its own scroll position and a shared buffer would mean
-- scrolling one scrolls the others.
--------------------------------------------------------------------------

local function Sound(important)
	if not important or not ns.db.chatSound then
		return false
	end
	-- Only while you are not already looking at one of your groups. A sound for
	-- a line you are watching arrive is a sound you turn off, and then you have
	-- no sound for the one you miss.
	local watching = window and window:IsShown() and type(active) == "string"
		and active:sub(1, 6) == "group:"
	if watching then
		return false
	end
	local kit = _G.SOUNDKIT
	if type(_G.PlaySound) ~= "function" or not kit or not kit.TELL_MESSAGE then
		return false
	end
	_G.PlaySound(kit.TELL_MESSAGE)
	return true
end

local function Draw(rooms, text, r, g, b, important)
	local appeared = false
	for _, id in ipairs(rooms) do
		local log = LogFor(id)
		if log then
			log:Add(text, r, g, b)
			-- Marked whether or not the window is up. A count that was only kept
			-- while you were watching would tell you nothing about the hour you
			-- were not.
			if id ~= active then
				local count = ns.Rooms.Mark(id)
				if not rail:Mark(id, count) then
					appeared = true
				end
			end
		end
	end

	if appeared then
		Refresh()
	end
	Sound(important)
end

-- Drawing a line is the one thing this window does from inside an event handler
-- for the rest of the session, and an event handler is where the client eats a
-- raise. A window that quietly stops taking lines is the same blank corner as
-- one that never built, so the first refusal is caught, recorded and said out
-- loud, and the ones after it are counted instead: a draw that is broken at all
-- is broken on every line, and on a raid night that is a wall of text.
local broke = 0

local function OnLine(rooms, text, r, g, b, important)
	local ok, why = pcall(Draw, rooms, text, r, g, b, important)
	if ok then
		return
	end
	broke = broke + 1
	if broke == 1 then
		ns.Print("the chat window " .. Note("stopped drawing lines: " .. tostring(why)))
	end
end

--------------------------------------------------------------------------
-- Layout
--
-- One function that places everything, run when the window is built, when a
-- setting moves it and when the pixel grid moves under it. It recomputes rather
-- than caches, the same as the options panel: this is never on a ticker and a
-- cached rectangle that is wrong once is wrong until a reload.
--------------------------------------------------------------------------

-- Where the log sits in the window: the rail's width and a margin in from the
-- left, the same margin in from every other side. One function because two
-- places that answer it would be two places to disagree, and because a log made
-- after the window was laid out has to be able to ask.
function Frame()
	local left = M.rooms + M.chatPad
	local top = M.chatPad
	local room = (window.width or 0) - left - M.chatPad
	local body = window:Body()
	return left, top, math.max(room, M.row), math.max(body - top - M.chatPad, M.row)
end

-- One log, put where the logs go and sized to it.
--
-- Called from Relayout for the ones that exist and from LogFor for the one
-- being made, and that second call is the whole reason this is a function. A
-- room's log is made on the first line that lands in it, which for Say is the
-- first thing you say all evening, long after the window was laid out. Without
-- this the frame came out anchored to nothing and no size, so the line went
-- into the buffer, the count went up on the rail, and the room drew nothing at
-- all: you could see what you had said in Conversation and not in Say.
function Place(log)
	local left, top, room, height = Frame()
	log.frame:ClearAllPoints()
	log.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT", left, -top)
	log:SetFontSize(ns.db.chatFont)
	log:Resize(room, height)
end

local function Relayout()
	if not built then
		return
	end

	local db = ns.db
	window:Resize(db.chatWidth, db.chatHeight)
	local px = ns.Pixel(window.frame)
	local body = window:Body()

	rail.frame:ClearAllPoints()
	rail.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT")
	rail:Resize(M.rooms, math.max(body - M.roomRow, M.roomRow))

	for _, log in ipairs(every) do
		Place(log)
	end

	-- The line you type in starts where the lines you read start, so the rail
	-- runs the whole height of the window, down its own column to the left of
	-- everything you read.
	window.footer:ClearAllPoints()
	window.footer:SetPoint("BOTTOMLEFT", M.rooms + M.chatPad, 0)
	window.footer:SetPoint("BOTTOMRIGHT", -M.chatPad, 0)
	window.footerRule:ClearAllPoints()
	window.footerRule:SetPoint("BOTTOMLEFT", M.rooms, window.foot)
	window.footerRule:SetPoint("BOTTOMRIGHT", -M.chatPad, window.foot)

	-- The voice button sits at the foot of the rail, one room row tall, in the
	-- column the rooms are in. That is where it belongs because it is the same
	-- question the rail asks: the rooms are who you are typing to and this is
	-- who you are talking to. It is last in the column rather than first because
	-- it is the one row there that is not a room, and the rail is shortened by
	-- exactly its height so the two never overlap.
	voice:ClearAllPoints()
	voice:SetPoint("BOTTOMLEFT", window.content, "BOTTOMLEFT", 0, 0)
	voice:SetSize(M.rooms, M.roomRow)

	entry.box:ClearAllPoints()
	entry.box:SetPoint("LEFT", window.footer, "LEFT", 0, 0)
	entry.box:SetPoint("RIGHT", window.footer, "RIGHT", 0, 0)
	entry.box:SetHeight(M.field)
	-- The line you type in is drawn at the size the lines you read are. A field
	-- that stays at twelve while the log goes to eighteen is the one part of the
	-- window that did not take the setting.
	entry.edit:SetFontObject(UI.Font(db.chatFont, UI.FLAT))

	window:SetOpacity(db.chatAlpha / 100)
	local point = db.chatPoint
	window.frame:ClearAllPoints()
	window.frame:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	-- Nothing to resize while the window is drawn without an edge, and it is.
	-- The line stays gone rather than coming back at the next grid change.
	if window.edges then
		ns.EdgeSize(window.edges, px)
	end
end

--------------------------------------------------------------------------
-- Building it
--------------------------------------------------------------------------

-- A click on a name in the log. Ours rather than the client's, because the
-- client's answer is to open its own chat field, and a window with its own
-- field that sends you to another one is two fields.
function ChatWindow.OnLink(link, _, button)
	local name = link:match("^player:([^:]+)")
	if not name or button == "RightButton" then
		return false
	end
	ChatWindow.Reply(name)
	return true
end

-- The line you type in, drawn or not drawn.
--
-- Not drawn means nothing at all: no fill, no hairline, so what is behind the
-- line is the window's own background at whatever opacity the player set. That
-- is the whole change. A sunken near black strip across the foot of a window
-- that is eighty percent transparent is not a field, it is a bar of paint over
-- the picture, and it was the heaviest thing on a screen whose design is that
-- the conversation is the only thing on it. Where the line is was never in
-- doubt: the ghost text sitting in it names the room and says what enter does.
--
-- Drawn is the moment the cursor lands in it, and at that moment the rectangle
-- earns its ink, because it is the difference between a key going into your
-- sentence and a key going into the game.
local function Light(box, on)
	box.bg:SetShown(on)
	for _, edge in ipairs(box.edges) do
		edge:SetShown(on)
	end
end

local function BuildEntry()
	-- Built in the colours it wears while you are typing, and then switched off.
	-- The alternative is a second pair of colours meaning "invisible", and a
	-- colour that is not a colour is a thing to explain at every site that reads
	-- it.
	local box = UI.Box(window.footer, C.selected, C.edge)
	Light(box, false)
	local edit = CreateFrame("EditBox", nil, box)
	edit:SetPoint("TOPLEFT", 3, 0)
	edit:SetPoint("BOTTOMRIGHT", -3, 0)
	edit:SetFontObject(UI.Font(M.font, UI.FLAT))
	edit:SetTextColor(C.text[1], C.text[2], C.text[3])
	edit:SetAutoFocus(false)
	-- The server's own cap on one line of chat. A longer one is refused whole,
	-- so it is better to stop the typing than to lose the sentence.
	edit:SetMaxLetters(255)

	-- What the empty line says: the room you are in and what enter will do in
	-- it. Drawn behind the text rather than above the log, which is where the
	-- heading row that used to say it went. Hidden the moment there is a
	-- character in the field, because from then on the field says it better.
	local ghost = UI.Label(box, M.small, C.quiet, "LEFT", UI.FLAT)
	ghost:SetPoint("LEFT", 4, 0)
	ghost:SetPoint("RIGHT", -4, 0)
	UI.Wrap(ghost, false)

	edit:SetScript("OnTextChanged", function(self)
		ghost:SetShown((self:GetText() or "") == "")
	end)

	edit:SetScript("OnEnterPressed", function(self)
		ChatWindow.Send(self:GetText())
		self:SetText("")
		self:ClearFocus()
	end)
	edit:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	edit:SetScript("OnEditFocusGained", function()
		-- A click that lands on the field itself never goes through
		-- ChatWindow.Focus, and it means the same thing that one does.
		ns.Compose.Disarm()
		Light(box, true)
	end)
	edit:SetScript("OnEditFocusLost", function()
		Light(box, false)
	end)
	edit:SetScript("OnHide", function(self)
		self:ClearFocus()
	end)
	-- Tab steps to the next room, which rewrites the slash in front of the
	-- cursor. It is the same key that cycled the channel in the window this
	-- replaced, and it means the same thing: change where this line is going.
	edit:SetScript("OnTabPressed", function()
		ChatWindow.Step(IsShiftKeyDown and IsShiftKeyDown() and -1 or 1)
	end)

	-- The box is a frame rather than a button, so the click that lands on the
	-- gap either side of the text has to be caught for the field to feel like a
	-- field.
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function()
		ChatWindow.Focus()
	end)

	return { box = box, edit = edit, ghost = ghost }
end

-- What a room's hover says: its name, what enter would do there, and how much
-- is waiting in it. The rail is a column of pictures, so this is where the
-- words went, and it has to carry all three of them because none of them is on
-- the screen any more.
local function Describe(row)
	local kind, target = ns.Rooms.Target(row.id)
	local waiting = row.unread or 0
	return {
		title = row.label,
		{ ns.Compose.Note(kind, target) },
		waiting > 0 and { ("%d waiting"):format(waiting) } or nil,
	}
end

local function Build()
	window = UI.Window({
		name = FRAME_NAME,
		width = ns.db.chatWidth,
		height = ns.db.chatHeight,
		-- No title bar. A bar across the top of a window says which window it
		-- is, and this one is a window you have had open all evening drawing
		-- the conversation it is named after. The twenty four pixels are worth
		-- more as another line of what somebody said.
		bare = true,
		-- No hairline round the outside either. Eighty percent transparent with
		-- a bright rectangle drawn round it is a window that is trying to be
		-- both a pane of glass and a box; the conversation is the thing on the
		-- screen and the box was the part saying otherwise.
		edge = false,
		-- One line of text rather than a row of buttons, which is what the
		-- default footer is sized for.
		footer = M.entry,
		-- Under the tooltip and under anything the client puts over the world.
		-- A chat window is furniture, not a dialog.
		strata = "MEDIUM",
		-- Escape is what clears a target and steps out of a field. It must not
		-- be what closes the window you have had up all evening.
		escape = false,
	})

	window.frame:SetScript("OnDragStart", function(self)
		if not ns.db.locked then
			self:StartMoving()
		end
	end)
	window.frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint()
		ns.db.chatPoint = { point, "UIParent", relativePoint, x, y }
	end)

	rail = UI.List(window.content, {
		name = "WarriorKitChatRooms",
		-- A picture per room rather than a word. Thirteen words down the left
		-- were a hundred and four pixels of every line anybody said, spent
		-- naming rooms you know by sight; the name is in the hover now.
		icons = true,
		describe = Describe,
		onSelect = function(id) Show(id) end,
	})
	entry = BuildEntry()

	-- Voice, at the foot of the rail. A microphone rather than a word, the same
	-- as every room above it, and lit green while you are in a channel.
	--
	-- **The colour is the point.** The setting joins you at login and says so in
	-- a panel you are not looking at; from the game there was nothing at all
	-- that said whether the join had landed. A player who cannot see that they
	-- are connected has voice chat they do not trust, which is voice chat they
	-- do not use.
	--
	-- **What it opens is the client's own window,** through Voice.Open. The one
	-- that lists who is in the channel with you and puts a volume slider against
	-- each of them. That is the thing you reach for voice to get at, none of it
	-- is drawn by this addon, and the button that used to open it is
	-- ChatFrameChannelButton, which Chat/Blizzard.lua takes off the screen along
	-- with the rest of the client's chat frame. So this is not a new door. It is
	-- the same door, back on the window that hid it.
	voice = UI.Button(window.frame, { label = "m", glyph = true,
		onClick = function() ChatWindow.Voice() end })
	UI.Tip(voice, Voicing)

	-- The colour follows the service rather than a ticker: Chat/Voice.lua already
	-- listens to every event that can move the answer, so it says when it moves.
	ns.Voice.OnChange = Lit

	enterButton = CreateFrame("Button", ENTER_NAME, window.frame)
	enterButton:SetScript("OnClick", function() ChatWindow.Focus() end)
	slashButton = CreateFrame("Button", SLASH_NAME, window.frame)
	slashButton:SetScript("OnClick", function() ChatWindow.Slash() end)

	built = true
	active = ns.Rooms.ALL
	if not LogFor(ns.Rooms.ALL) then
		built = false
		return false
	end

	Relayout()
	Refresh()
	Show(ns.Rooms.ALL)

	ns.Rooms.OnClose = Close
	ns.ChatFeed.Attach(OnLine)
	return true
end

--------------------------------------------------------------------------
-- The chat keys
--
-- Taken exactly while Blizzard's chat window is hidden, and handed back the
-- moment it is not. That is not a setting of its own on purpose. The client's
-- chat keys open the client's chat line; with that window hidden the line they
-- open is invisible, so the keys have to come here or typing is broken. With
-- that window on screen they still work and there is nothing to fix.
--
-- **Both keys, not one.** This took ENTER and NUMPADENTER and left the slash
-- key alone, and the slash key is the one half the things you type in a chat
-- window start with. Pressing it opened Blizzard's invisible line, which from
-- the outside is a window that swallows every slash command in the game.
--
-- **Asked for rather than assumed.** The keys are read back out of the client's
-- own binding set by the two actions FrameXML names them by, so a player who
-- moved OPENCHAT off enter gets the key they moved it to. A key the player has
-- unbound comes back nil and is left unbound, because taking a key somebody
-- deliberately cleared is the addon deciding it knows better. The literal
-- defaults are the answer only where the client has no GetBindingKey at all,
-- which is a client that cannot be asked rather than one that answered no.
--
-- An override sits on top of whatever the key already carried and is dropped by
-- one call, unlike SetBinding, which the next SaveBindings would make permanent.
-- Both calls are refused in combat, so a fight defers the work to
-- PLAYER_REGEN_ENABLED, which is the shape Buttons/Bars.lua uses for the same
-- reason. One owner frame for every override, so one clear drops all of them.
--------------------------------------------------------------------------

local CHAT_KEYS = {
	{ action = "OPENCHAT", button = ENTER_NAME, keys = { "ENTER", "NUMPADENTER" } },
	{ action = "OPENCHATSLASH", button = SLASH_NAME, keys = { "/" } },
}

local function WantsEnter()
	return built and ns.db.chat and ns.db.hideBlizzChat and window:IsShown()
end

-- Which keys carry one of the client's chat actions right now.
local function BoundTo(action, fallback)
	local get = _G.GetBindingKey
	if type(get) ~= "function" then
		return fallback
	end
	local held = {}
	local ok, first, second = pcall(get, action)
	if ok then
		held[#held + 1] = first
		held[#held + 1] = second
	end
	return held
end

function ChatWindow.Keys()
	if not built then
		return false
	end
	if InCombatLockdown and InCombatLockdown() then
		pending = true
		return false
	end
	pending = false

	if type(ClearOverrideBindings) == "function" then
		pcall(ClearOverrideBindings, enterButton)
	end
	if not WantsEnter() or type(SetOverrideBindingClick) ~= "function" then
		return true
	end
	for _, chat in ipairs(CHAT_KEYS) do
		for _, key in ipairs(BoundTo(chat.action, chat.keys)) do
			pcall(SetOverrideBindingClick, enterButton, true, key, chat.button, "LeftButton")
		end
	end
	return true
end

-- Hand the chat keys back to whatever carried them, so somebody else can take
-- one. Chat/Compose.lua does that with the enter key when a line has to be run
-- by the client rather than by the addon.
--
-- Two owners on one key is the bug this exists to stop. An override binding is
-- a claim by a frame, and which of two claims on the same key wins is the
-- client's business rather than something this addon should be betting a key
-- press on. So the window gives the key up before the other claim goes on, and
-- ChatWindow.Keys takes it back afterwards.
--
-- The second reason is quieter and just as load bearing: GetBindingKey answers
-- with what the key carries now, and while this window's override is on enter
-- the answer to "which key is OPENCHAT" is nothing at all. A caller that wants
-- to read the chat keys has to clear them first, which is what this does.
function ChatWindow.Yield()
	if not built then
		return false
	end
	if InCombatLockdown and InCombatLockdown() then
		return false
	end
	if type(ClearOverrideBindings) ~= "function" then
		return false
	end
	pcall(ClearOverrideBindings, enterButton)
	return true
end

--------------------------------------------------------------------------
-- The surface everything else uses
--------------------------------------------------------------------------

-- The line you type in, for the harness. Handed out for the reason the
-- microphone below is: what is being checked is whether a texture is drawn, and
-- a boolean this file computed is a boolean this file could compute wrongly and
-- still agree with itself.
function ChatWindow.Field()
	return built and entry.box or nil
end

-- The microphone, for the harness. Handed out rather than answered about,
-- because what is being checked is the colour on a font string and a boolean
-- this file computed is a boolean this file could compute wrongly and still
-- agree with itself.
function ChatWindow.Mic()
	return built and voice.text or nil
end

function ChatWindow.Built()
	return built
end

function ChatWindow.Shown()
	return built and window:IsShown() and true or false
end

-- The window, built if it is not already. Nothing is built while the part is
-- off, so a player who has turned it off pays nothing at all for it: no frames,
-- no logs, no font objects. Turning it back on, or asking for the window from a
-- key or a slash word, is what builds it.
function ChatWindow.Ensure()
	if built or not ns.db.chat then
		return false
	end
	return ChatWindow.Start()
end

function ChatWindow.Apply()
	if not built then
		return false
	end
	Relayout()
	Refresh()

	local shown = ns.db.chat and true or false
	window.frame:SetShown(shown)
	-- Three things follow the window rather than the settings, and all three for
	-- the same reason: each of them takes something off the screen on the
	-- promise that this window is drawing it instead, and a closed window keeps
	-- no such promise.
	ns.ChatFeed.Watched(shown)
	ns.ChatBlizzard.Apply()
	ChatWindow.Keys()
	return true
end

function ChatWindow.Show()
	-- Nothing is built while the part is off, so the first thing a show has to
	-- do is find out whether there is a window to show.
	ChatWindow.Ensure()
	if not built then
		return false
	end
	ChatWindow.Apply()
	return true
end

function ChatWindow.Hide()
	if not built then
		return false
	end
	window.frame:Hide()
	ns.ChatFeed.Watched(false)
	ns.ChatBlizzard.Apply()
	ChatWindow.Keys()
	return true
end

-- The client's own Chat Channels window, which is where the voice roster and
-- the per person volume live. A method here rather than a call written into the
-- button so the slash word and the harness reach the same door.
--
-- A refusal is printed rather than swallowed. The failure this has is a client
-- with no such window, and a button that does nothing on a client that cannot
-- do it looks exactly like a button that is broken.
function ChatWindow.Voice()
	local ok, what = ns.Voice.Open()
	if not ok then
		ns.Print("voice: " .. what .. ".")
	end
	return ok
end

function ChatWindow.Toggle()
	ChatWindow.Ensure()
	if not built then
		return false
	end
	if window:IsShown() then
		return ChatWindow.Hide()
	end
	return ChatWindow.Show()
end

function ChatWindow.Reset()
	ns.db.chatPoint = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 16, 120 }
	return ChatWindow.Apply()
end

--------------------------------------------------------------------------
-- Rooms, from outside
--------------------------------------------------------------------------

-- Go to a room by id. Anything that is not there right now is refused rather
-- than made, because the rooms that exist are a fact about your party and your
-- guild rather than something a caller gets to assert.
function ChatWindow.Go(id)
	if not built or not ns.Rooms.Exists(id) then
		return false
	end
	rail:Select(id)
	if active ~= id then
		Show(id)
	end
	return true
end

function ChatWindow.Step(delta)
	if not built then
		return false
	end
	local id = rail:Step(delta)
	if not id then
		return false
	end
	ChatWindow.Go(id)
	ChatWindow.Fill()
	return true
end

function ChatWindow.Room()
	return active
end

-- Which channel a line typed right now goes to, and who it is addressed to when
-- that channel is a whisper.
function ChatWindow.Channel()
	return ns.Rooms.Target(active)
end

-- Answer that person: their own room if there is one, and their name in the
-- field either way. A click on a name in the log is what calls this.
function ChatWindow.Reply(name)
	if not built or type(name) ~= "string" or name == "" then
		return false
	end
	local id = ns.Rooms.Whisper(name)
	if id then
		Refresh()
		ChatWindow.Go(id)
	end
	ChatWindow.Focus()
	return true
end

--------------------------------------------------------------------------
-- Typing
--------------------------------------------------------------------------

-- What the field starts with: the room's own slash, so the line reads /p with
-- the cursor after it the moment you start typing into your party. Only into an
-- empty field, because a half typed sentence you clicked away from is not
-- something to write over.
function ChatWindow.Fill()
	if not built or not ns.db.chatPrefix then
		return false
	end
	local text = entry.edit:GetText() or ""
	if text ~= "" and text:sub(1, 1) ~= "/" then
		return false
	end
	local prefix = ns.Compose.Prefix(ns.Rooms.Target(active))
	entry.edit:SetText(prefix)
	if type(entry.edit.SetCursorPosition) == "function" then
		entry.edit:SetCursorPosition(#prefix)
	end
	return true
end

-- Put the cursor in the field, opening the window first if it is shut. This is
-- what the enter key calls and what the key binding calls.
function ChatWindow.Focus()
	if not built then
		return false
	end
	-- Going back to the field is a change of mind about a line the client was
	-- going to run from the enter key, so the key comes back here. The script
	-- below catches the click that lands on the field directly; this catches
	-- the same decision made from the window, the slash key or a hover.
	ns.Compose.Disarm()
	if not window:IsShown() then
		ChatWindow.Show()
	end
	ChatWindow.Fill()
	entry.edit:SetFocus()
	return true
end

-- The slash key, which opens the line with a slash already in it. That is what
-- the client's own OPENCHATSLASH does and it is the whole reason the key exists
-- separately from enter: every slash command in the game starts with it.
--
-- No room prefix here, unlike Focus. A slash is you addressing the client
-- rather than a room, and Chat/Compose.lua already sends a line it cannot parse
-- as a channel through to the client's own slash handler. Prefixing it with the
-- room would turn /dance into a sentence said out loud in party.
--
-- A sentence already half typed is left alone and only focused. The test for
-- that is Fill's: an empty line or one starting with a slash is a line nobody
-- has invested anything in, and anything else is a draft you clicked away from.
function ChatWindow.Slash()
	if not built then
		return false
	end
	if not window:IsShown() then
		ChatWindow.Show()
	end
	local text = entry.edit:GetText() or ""
	if text == "" or text:sub(1, 1) == "/" then
		entry.edit:SetText("/")
		if type(entry.edit.SetCursorPosition) == "function" then
			entry.edit:SetCursorPosition(1)
		end
	end
	entry.edit:SetFocus()
	return true
end

-- What is in the line right now. Public because the field is where the answer
-- to "which channel is this going to" is written down: there is no second piece
-- of state holding it, which is the whole point of the redesign, so anything
-- checking that behaviour has to be able to read the text.
function ChatWindow.Line()
	if not built then
		return ""
	end
	return entry.edit:GetText() or ""
end

-- One line, sent to wherever the room and the text between them say. Public
-- because a slash word and the harness want the same path, and a send that
-- lives inside a script handler is a send nothing else can reach.
function ChatWindow.Send(text)
	local kind, target = ns.Rooms.Target(active)
	return ns.Compose.Send(text, kind, target)
end

--------------------------------------------------------------------------
-- What it is doing
--------------------------------------------------------------------------

function ChatWindow.Lock()
	if not built then
		return false
	end
	window.frame:SetMovable(not ns.db.locked)
	return true
end

function ChatWindow.Describe()
	if not ns.db.chat then
		return "off"
	end
	if not built then
		-- The sentence rather than "not built yet", because "not built yet" is
		-- the answer that sent somebody looking at the wrong file.
		return "not built: " .. said
	end
	return ("%s, %s, in %s"):format(window:IsShown() and "open" or "closed",
		ns.Rooms.Describe(), ns.Rooms.Title(active))
end

-- What the last attempt to stand the window up did, whether it worked or not.
-- The panel draws it and `/wk status` folds it into the chat line, so the thing
-- you do when the corner is empty is read one line rather than guess.
function ChatWindow.Why()
	return said
end

-- How many rooms are drawn right now. Named for the panel and for /wk status,
-- so nothing outside has to know that a room is a row or that a row is a frame.
function ChatWindow.Rooms()
	if not built then
		return 0
	end
	local count = 0
	for _, row in ipairs(ns.Rooms.List()) do
		if row.id then
			count = count + 1
		end
	end
	return count
end

-- How wide a row of the rail came out. Named for the harness, and for the
-- failure in List:RowWidth's own note: a rail that is the right width with rows
-- that are not is invisible to everything else that measures this window.
function ChatWindow.Rail()
	if not built then
		return 0
	end
	return rail:RowWidth()
end

-- How big one room's log came out, in the window's own units.
--
-- Named for the harness, and it earns the surface. A log is made on the first
-- line that lands in its room, which for a whisper from somebody new is hours
-- after the window was laid out, and a log that is never placed comes out
-- anchored to nothing at no size. It still takes lines, the count against it in
-- the rail still rises, and it draws nothing at all. Nothing that reads a line
-- or a count can see that, which is why it survived: what you said in Say went
-- into the buffer and only Conversation ever showed it.
function ChatWindow.Shape(id)
	local log = logs[id]
	if not log then
		return 0, 0
	end
	return log.frame:GetWidth() or 0, log.frame:GetHeight() or 0
end

-- How many lines one room is holding.
function ChatWindow.Count(id)
	local log = logs[id]
	return log and log:Count() or 0
end

-- What every room is holding, for the panel and for /wk status.
function ChatWindow.Held()
	local total = 0
	for _, log in ipairs(every) do
		total = total + log:Count()
	end
	return total
end

--------------------------------------------------------------------------
-- Standing the window up, out loud
--
-- Every route into this window goes through here, and it is pcalled, and the
-- reason is worth writing down because it cost an evening.
--
-- The client swallows a Lua error raised inside an event handler unless
-- scriptErrors is on, and it ships off. A window that fails to build is then
-- three silences at once: no window, no message, and Blizzard's own chat left on
-- the screen by the coupling that is supposed to be a safety net. From the
-- outside that is indistinguishable from a part that did nothing, which is
-- exactly what it looked like.
--
-- So the build says what went wrong, in the window every addon prints to, which
-- during a failure is the only chat window there is. The same shape as the log
-- refusing a ScrollingMessageFrame and saying so: a part that cannot draw has to
-- be able to say why.
--------------------------------------------------------------------------

function ChatWindow.Start()
	if built then
		return true
	end
	if not ns.db.chat then
		Note("off, so nothing is built")
		return false
	end

	local ok, made = pcall(Build)
	if not ok then
		built = false
		ns.Print("the chat window " .. Note("did not build, so Blizzard's is still "
			.. "your chat: " .. tostring(made)))
		return false
	end
	if not made then
		-- LogFor has already said which piece the client refused. Recorded here
		-- anyway, because the line it printed goes into a window that scrolls
		-- and this one survives the reload.
		ns.Print("the chat window " .. Note("did not build: the log refused, and "
			.. "the line above it says what the client would not make"))
		return false
	end

	local applied, why = pcall(function()
		ChatWindow.Lock()
		ChatWindow.Apply()
	end)
	if not applied then
		ns.Print("the chat window " .. Note("built and would not lay itself out: "
			.. tostring(why)))
		return false
	end
	Note(Placed())
	return true
end

--------------------------------------------------------------------------

-- What the client's own key binding list calls it. Beside the function it
-- calls, the way the marking keys are.
BINDING_NAME_WARRIORKIT_CHAT = "Type in the WarriorKit chat window"

function WarriorKit_ChatEnter()
	ChatWindow.Focus()
end

--------------------------------------------------------------------------

-- The size the window shipped with before the chrome came off it.
--
-- A saved pair that is exactly this is a pair nobody chose: it is what a player
-- who never touched the two steppers has in their file. The window under it is
-- a different window now, a hundred pixels of rail and fifty of chrome
-- narrower and shorter, so that pair is a rectangle sized for furniture that is
-- gone. It is moved to the new default once and anything else is left alone,
-- because a number somebody set is a number somebody set.
--
-- The same argument covers the log's size. Twelve was the default until the
-- window was drawn at furniture size, and a file holding exactly twelve is a
-- file nobody typed a number into.
--
-- Delete this and its call a release after 1.10, when nobody's file still has
-- the old numbers in it. 1.9 is what shipped it.
local WAS = { width = 520, height = 260, font = 12 }

local function Shrink()
	local moved = false
	if ns.db.chatWidth == WAS.width and ns.db.chatHeight == WAS.height then
		ns.db.chatWidth = ns.DefaultFor("chatWidth")
		ns.db.chatHeight = ns.DefaultFor("chatHeight")
		moved = true
	end
	if ns.db.chatFont == WAS.font then
		ns.db.chatFont = ns.DefaultFor("chatFont")
		moved = true
	end
	return moved
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
-- What changes which rooms exist. Two spellings of the roster change, because
-- the two clients this addon ships for do not use the same one, and registering
-- an event a client has never heard of raises rather than answering.
for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED",
	"RAID_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }) do
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		Shrink()
		-- Written before anything is tried, so a session where this file never
		-- reached login is told apart from one that reached it and failed. Those
		-- are two different bugs, and from a chair they are the same blank
		-- corner of the screen. Everything below overwrites it.
		Note("login reached, nothing built yet")
		if not ns.db.chat then
			-- Nothing is built while the part is off, so a player who has turned
			-- it off pays nothing at all for it: no frames, no logs, no font
			-- objects. Turning it back on builds it.
			Note("off, so nothing is built")
			return
		end
		ChatWindow.Start()
		return
	end

	if not built then
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		-- A line loaded onto the enter key is dropped when the fight ends if it
		-- was not pressed. The client refuses a binding change under lockdown,
		-- so a key armed before the pull and fired during it could not give
		-- itself back at the time, and this is when it can.
		ns.Compose.Disarm()
		if pending then
			ChatWindow.Keys()
		end
		return
	end
	Refresh()
end)

-- The window is on the pixel grid, so a resolution change or a UI size change
-- moves every number in it at once. The zoom first, because every measurement
-- below is in the window's own units and those units are what the zoom decides.
ns.UI.OnRescale(function()
	if not built then
		return
	end
	UI.Rezoom(window.frame, UI.WindowZoom())
	window.zoom = UI.WindowZoom()
	Relayout()
end)
