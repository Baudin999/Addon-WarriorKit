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

-- The client's two chat keys are the client's. This window took both of them
-- onto buttons of its own for a while, so that enter opened the line down here
-- rather than the invisible one behind it, and that arrangement is gone.
--
-- What it cost was `/logout`. A key bound to a button of ours opens the line
-- from a script of ours, and a line opened from a script is a line whose enter
-- key runs down a stack an addon has been in, which is a stack the client will
-- not finish a protected command on. Now the keys go straight into FrameXML,
-- FrameXML opens the field this window borrowed, and the press that finishes a
-- command is Blizzard's from the keyboard down. See Chat/Field.lua.

local window, rail, entry, voice

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
	log:SetOpacity(ns.db.chatAlpha / 100)
	-- Shown when it belongs to the room you are already reading, and that is not
	-- a nicety. A log is made by the first line that lands in its room, which is
	-- after Show picked that room and hid every log there was. Hiding it here as
	-- well meant the room you were sitting in drew nothing: you whispered
	-- somebody, the rail said one line had arrived, the log held it, and the
	-- window was blank until you stepped to another room and back. The first
	-- thing you say to anybody is the case, every time.
	log.frame:SetShown(id == active)
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
--
-- There is nothing here about pressing enter twice any more. The sentence that
-- used to take this line over said which command was waiting on a second press,
-- and no command waits on a second press now.
local function Paint()
	local kind, target = ns.Rooms.Target(active)
	entry.ghost:SetText(("%s, %s"):format(ns.Rooms.Title(active),
		ns.Compose.Note(kind, target)))
end

-- Written again from outside when something other than the room has changed
-- what the empty line has to say.
function ChatWindow.Paint()
	if not built then
		return false
	end
	Paint()
	return true
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
		kind = "note",
		title = "Voice",
		lines = {
			{ ok and ns.Voice.Describe() or why },
			{ channel and "Who is in it, and how loud each of them is."
				or "Opens the client's own Chat Channels window." },
		},
	}
end

-- Which room the last automatic move landed on.
--
-- Held so that joining a party moves you into it once and a roster tick five
-- minutes later does not move you back out of the room you chose in the
-- meantime. Leaving the group puts this back to nothing, so rejoining moves you
-- again.
local followed

-- Into the room you would be talking in, when you have not said otherwise.
--
-- The case is joining a party. The rail grows a party room, nothing selects it,
-- and the first line you type goes to say in front of the two strangers
-- standing beside you, because Conversation types into say. That is the one
-- place this window made you press something to get what it had just worked
-- out for itself.
--
-- Only out of Conversation, which is the room nobody chose. A player sitting in
-- their guild or in a whisper picked that, and a window that moved them out of
-- it on a roster change would be worse than the thing it fixes.
local function Joined()
	local want = ns.Rooms.Talking()
	if want == followed then
		return false
	end
	followed = want
	if not want or active ~= ns.Rooms.ALL then
		return false
	end
	return ChatWindow.Go(want)
end

local function Refresh()
	local rows = ns.Rooms.List()
	rail:Set(rows)
	if not ns.Rooms.Exists(active) then
		-- Whatever you were reading has stopped existing, which is what leaving
		-- a party looks like from here. Everything is where a line always is.
		Show(ns.Rooms.ALL)
	end
	Joined()
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
	local watching = window and window:IsShown() and ns.Rooms.IsGroup(active)
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
	-- Written down before it is drawn. What survives a reload is two rooms out
	-- of the thirteen and Chat/History.lua says no to everything else, so this
	-- is one call and no allocation on nearly every line.
	ns.ChatHistory.Note(rooms, text, r, g, b)

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

--------------------------------------------------------------------------
-- What was said before the reload
--
-- The lines Chat/History.lua kept, back in the rooms they were said in, at the
-- moment the window is stood up and before the rail is drawn. A room restored
-- after the refresh is a row the refresh did not know to draw.
--------------------------------------------------------------------------

-- Where the last session ended, under what it said.
--
-- Every line carries a clock and no line carries a date, so without this the
-- whisper you answered last night is the whisper at the top of this evening's
-- log and reads as one that has just arrived. Plain hyphens rather than a rule
-- character: the client draws this in Arial Narrow and a glyph the face does
-- not carry is drawn as nothing at all, with nothing written anywhere saying
-- so.
local EARLIER = "|cff6b6b73-------- earlier --------|r"

local function Replay(held, touched, order)
	for _, id in ipairs(held.rooms) do
		local log = LogFor(id)
		if log then
			log:Add(held.line, held.r, held.g, held.b)
			if not touched[id] then
				touched[id] = true
				order[#order + 1] = id
			end
		end
	end
end

local function Restore()
	local lines = ns.Rooms.Restore()
	local touched, order = {}, {}
	for _, held in ipairs(lines) do
		Replay(held, touched, order)
	end

	local color = ns.UI.Color.text
	for _, id in ipairs(order) do
		logs[id]:Add(EARLIER, color[1], color[2], color[3])
	end
	return #lines
end

--------------------------------------------------------------------------

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
-- How big it is drawn
--
-- Its own zoom, off its own setting, and not UI.WindowZoom.
--
-- Every other window in the addon is something you open, read and shut, so one
-- size for all of them is right: the slider on the settings page says how big
-- this addon looks to you and they all take it. The chat window is the one that
-- is up while you play. It sits in a corner beside the game all evening and how
-- big you want it there has nothing to do with how big you want a settings
-- panel you have open for a minute, which is why a player who had sized the
-- rest of the interface up found the conversation had gone with it.
--
-- The screen's own whole step is still in it, because that step is not a
-- preference: it is what keeps a 21 pixel row from being half a row on a 4K
-- panel. What is left out is UI.Size, and the setting below stands in its place
-- for this window alone.
--------------------------------------------------------------------------

-- The range and the stops, here rather than beside the control that offers
-- them. The clamp below is what the window will actually honour, and a panel
-- that offered a stop this refused would be a control that does nothing at one
-- end of its own travel.
ChatWindow.SCALE_LOW, ChatWindow.SCALE_HIGH, ChatWindow.SCALE_STEP = 0.5, 3, 0.25

-- Clamped rather than trusted, the same as the addon-wide size is: a file
-- edited by hand can hold a nought, and a nought here is SetScale(0), which is
-- a window with no pixels in it and nothing anywhere saying why.
function ChatWindow.Zoom()
	local scale = tonumber(ns.db.chatScale) or 1
	if scale < ChatWindow.SCALE_LOW then
		scale = ChatWindow.SCALE_LOW
	elseif scale > ChatWindow.SCALE_HIGH then
		scale = ChatWindow.SCALE_HIGH
	end
	return UI.ScreenZoom() * scale
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
	-- Before the measurements, because every number below is in the window's own
	-- units and the zoom is what decides how big one of those is. Rezoom answers
	-- false when nothing moved, so a layout run for any other reason costs one
	-- comparison.
	local zoom = ChatWindow.Zoom()
	UI.Rezoom(window.frame, zoom)
	window.zoom = zoom
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
	-- window that did not take the setting. It is the client's frame, so this
	-- goes through Chat/Field.lua.
	--
	-- Adopted again rather than once at build, because the count of chat windows
	-- is the client's and a whisper can raise it: a tenth window opened this
	-- evening has a line the first pass never saw.
	ns.ChatField.Adopt()
	ns.ChatField.Font(db.chatFont)
	-- The anchor only while the window is up. A layout runs on a setting moving
	-- and on the pixel grid moving under it, and both of those happen with the
	-- window closed, where anchoring the client's line into our footer would be
	-- a game with no line to type in at all. ChatWindow.Apply is where the
	-- window being open or shut is decided, and it moves the line either way.
	if window.frame:IsShown() then
		ns.ChatField.Anchor(entry.box)
	end

	-- Every surface in the window at the one opacity, and not only the sheet
	-- behind it.
	--
	-- The rail and the bar beside the log were painted in their own colours at
	-- full alpha, so a window the player had made transparent came out as a pane
	-- of glass with a solid black column down one side of it and a solid black
	-- stripe down the other.
	--
	-- The pictures, the counts and the text are left alone, and so is the
	-- microphone at the foot of the rail. Those are what you read the window by,
	-- and the microphone is the only control in it: a window you can see through
	-- is not the same request as a window you cannot read or press.
	local alpha = db.chatAlpha / 100
	window:SetOpacity(alpha)
	rail:SetOpacity(alpha)
	for _, log in ipairs(every) do
		log:SetOpacity(alpha)
	end

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

	-- What the empty line says: the room you are in and what enter will do in
	-- it. Drawn behind the text rather than above the log, which is where the
	-- heading row that used to say it went. Gone the moment the cursor lands in
	-- the line, because from then on the line itself says it.
	local ghost = UI.Label(box, M.small, C.quiet, "LEFT", UI.FLAT)
	ghost:SetPoint("LEFT", 4, 0)
	ghost:SetPoint("RIGHT", -4, 0)
	UI.Wrap(ghost, false)

	-- And the line itself is the client's. Chat/Field.lua says why at length;
	-- the short of it is that a field of ours puts a function of ours in the
	-- stack the enter key runs down, and the client drops the protected call at
	-- the end of any stack an addon has been in. So there is no CreateFrame
	-- here. The rectangle above is ours, the sentence in it is ours, and the
	-- frame the characters go into is ChatFrame1EditBox with its art taken off.
	ns.ChatField.Adopt()

	-- The room's own slash, written into the client's field when it opens
	-- empty. This is Fill below, handed over rather than called, because the
	-- moment it has to happen is inside the client's own activation and only
	-- Chat/Field.lua can see that moment.
	ns.ChatField.OnFill = function(field)
		return ChatWindow.Fill(field)
	end
	-- The rectangle is drawn only while the cursor is in the line, and the
	-- sentence behind it only while the cursor is out of it.
	--
	-- **Out of it, and not "while the line is empty", which is what this said
	-- first and what made the line unreadable.** The client draws a word of its
	-- own in the field saying which channel you are on, at the same margin this
	-- sentence starts at, and a line the window has just filled in with `/p ` is
	-- an empty line: the client's parser reads the slash, sets the channel from
	-- it and takes the slash back out. So the field was empty, the sentence came
	-- back, and it was drawn underneath the client's word with both of them
	-- legible through the other. The cursor being in the line is the whole test:
	-- the line is what says where it is going from that moment on.
	ns.ChatField.OnLight = function(on)
		Light(box, on)
		ghost:SetShown(not on)
	end

	-- Typing `/p` is choosing the party room, so the rail follows the line.
	--
	-- This is the other half of "what you are reading is what you are typing
	-- into", and it was missing: the slash went to the right channel and the
	-- window went on saying Conversation, so the next time the line opened it
	-- was filled in with Conversation's slash over the player's own choice.
	ns.ChatField.OnChannel = function(kind, target, meant)
		ChatWindow.Follow(kind, target, meant)
	end

	-- Tab steps to the next room, which rewrites the slash in front of the
	-- cursor. It is the same key that cycled the channel in the window this
	-- replaced, and it means the same thing: change where this line is going.
	--
	-- Under the client's own tab rather than instead of it. FrameXML cycles the
	-- field's chat type on this key and we cannot take that away without taking
	-- the script, so both run and the slash written here is the one that decides
	-- where the line goes: the client's parser reads the slash on send and sets
	-- the type from it, whatever the type was a moment before.
	ns.ChatField.OnTab = function()
		ChatWindow.Step(IsShiftKeyDown and IsShiftKeyDown() and -1 or 1)
	end

	-- The box is a frame rather than a button, so the click that lands on the
	-- gap either side of the text has to be caught for the field to feel like a
	-- field.
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function()
		ChatWindow.Focus()
	end)

	return { box = box, ghost = ghost }
end

-- What a room's hover says: its name, what enter would do there, and how much
-- is waiting in it. The rail is a column of pictures, so this is where the
-- words went, and it has to carry all three of them because none of them is on
-- the screen any more.
local function Describe(row)
	local kind, target = ns.Rooms.Target(row.id)
	local waiting = row.unread or 0
	return {
		kind = "note",
		title = row.label,
		lines = {
			{ ns.Compose.Note(kind, target) },
			waiting > 0 and { ("%d waiting"):format(waiting) } or nil,
		},
	}
end

local function Build()
	window = UI.Window({
		name = FRAME_NAME,
		width = ns.db.chatWidth,
		height = ns.db.chatHeight,
		-- Its own, rather than the size every other window in the addon takes.
		-- See ChatWindow.Zoom.
		zoom = ChatWindow.Zoom(),
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
		-- Where you left it. Every other window in the addon opens in the
		-- middle of the screen because you opened it on purpose and will close
		-- it again in a minute; this one is up all evening and belongs in the
		-- corner you put it in. This used to be a copy of UI.Window's own drag
		-- scripts written over the top of them, which is what made placing a
		-- window and placing anything else two different pieces of code.
		moved = function(anchor)
			ns.db.chatPoint = anchor
		end,
		-- And the only window /wk lock reaches, for the same reason it saves
		-- its corner: this one is furniture on the HUD rather than a window you
		-- opened for a minute, so it locks down with the rest of the furniture.
		lockable = true,
	})

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
	ns.Tip.Hang(voice, Voicing)

	-- The colour follows the service rather than a ticker: Chat/Voice.lua already
	-- listens to every event that can move the answer, so it says when it moves.
	ns.Voice.OnChange = Lit

	built = true
	active = ns.Rooms.ALL
	if not LogFor(ns.Rooms.ALL) then
		built = false
		return false
	end

	Relayout()
	-- What the last session said, before either of the two below. Conversation
	-- has to be selected over a rail that already lists the rooms the record
	-- brought back, and the refresh below is what draws that rail.
	Restore()
	-- Conversation first and the refresh after it, in that order.
	--
	-- The refresh is what moves the window into the party room when you log in
	-- already standing in a party, and a Show written under it put you straight
	-- back in Conversation and left the move recorded as done, so nothing tried
	-- again for the rest of the session. That is the same bug as never having
	-- written the move at all, on the one login where it matters most.
	Show(ns.Rooms.ALL)
	Refresh()

	ns.Rooms.OnClose = Close
	ns.ChatFeed.Attach(OnLine)
	return true
end

--------------------------------------------------------------------------
-- The surface everything else uses
--------------------------------------------------------------------------

-- The rectangle round the line, for the harness. Ours, unlike the line inside
-- it, which is ChatWindow.Entry above and the client's. Handed out for the
-- reason the microphone below is: what is being checked is whether a texture is
-- drawn, and a boolean this file computed is a boolean this file could compute
-- wrongly and still agree with itself.
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

-- The sentence in the empty line, or nil while it is not on the screen.
--
-- Named for the harness, for the reason the field and the microphone above are:
-- what is being checked is the words a player reads under the cursor, and a
-- string this file recomputed is a string this file could recompute wrongly and
-- still agree with itself.
--
-- Whether it is drawn is half the answer rather than a detail. The sentence
-- sits at the same margin as the word the client draws in the field saying
-- which channel you are on, so a version that leaves it up while the cursor is
-- in the line is two strings over each other, both legible through the other.
-- A getter that only answered the text could not tell that version from this
-- one.
function ChatWindow.Ghost()
	if not built or not entry.ghost:IsShown() then
		return nil
	end
	return entry.ghost:GetText()
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
	-- The line you type in follows the window, because it is the client's frame
	-- sitting in our footer: a window that is not on the screen is a footer that
	-- is not on the screen, and a field anchored inside one is a game with no
	-- way to type at all.
	if shown then
		ns.ChatField.Anchor(entry.box)
	else
		ns.ChatField.Release()
	end
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
	ns.ChatField.Release()
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
	ns.db.chatPoint = ns.DefaultCopy("chatPoint")
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

-- Into the room a channel belongs to, because the player has just put that
-- channel in the line by hand.
--
-- Refused where the room the window is already in types into that same channel,
-- and that clause is what makes this safe to hang off every keystroke. Filling
-- Conversation's line in with `/s ` sets the channel to say; so does typing it;
-- and neither is a reason to march the window out of Conversation and into the
-- Say room. Nothing moves unless the channel is one the room you are in would
-- not have sent to.
--
-- Refused as well where the channel names no room that exists: a whisper to
-- somebody with no conversation on the rail yet, a channel the client knows and
-- this window does not, a party you have left.
function ChatWindow.Follow(kind, target, meant)
	if not built then
		return false
	end
	local here, at = ns.Rooms.Target(active)
	if kind == here and (target or "") == (at or "") then
		return false
	end
	local id = ns.Rooms.For(kind, target)
	-- Except for a whisper the client aimed itself, which is Whisper on the
	-- unit menu and the same word on a name in the friends list. There is no
	-- conversation with that person yet by definition, and refusing to make one
	-- leaves the rail sitting in Conversation while the line under it says To
	-- Aria. The window's one promise is that those two agree.
	--
	-- Only ever on `meant`. The same channel arriving because somebody typed a
	-- name into the line is the case above and stays refused: a room per
	-- keystroke is a rail full of people who do not exist.
	if not id and meant and kind == "WHISPER" and target and target ~= "" then
		id = ns.Rooms.Whisper(target)
		if id then
			Refresh()
		end
	end
	if not id or id == active then
		return false
	end
	return ChatWindow.Go(id)
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
-- the cursor after it the moment you start typing into your party.
--
-- Called by Chat/Field.lua from inside the client's own activation, with the
-- client's own field, which is why it takes one. It is also called on its own
-- from Focus below, for the paths that open the line without a key press.
--
-- Only into an empty field, because a half typed sentence you clicked away from
-- is not something to write over.
function ChatWindow.Fill(field)
	field = field or ns.ChatField.Box()
	if not built or not field or not ns.db.chatPrefix then
		return false
	end
	local text = field:GetText() or ""
	if text ~= "" and text:sub(1, 1) ~= "/" then
		return false
	end
	local prefix = ns.Compose.Prefix(ns.Rooms.Target(active))
	if prefix == "" then
		return false
	end
	field:SetText(prefix)
	if type(field.SetCursorPosition) == "function" then
		field:SetCursorPosition(#prefix)
	end
	return true
end

-- Put the cursor in the field, opening the window first if it is shut.
--
-- Not what the enter key calls any more, and that is the change this window was
-- rebuilt for. The two chat keys are the client's own again, so the press that
-- opens the line and the press that sends it both run down a stack with nothing
-- of ours in it, and `/logout` typed here logs you out on the first press.
--
-- What still comes through here is every way of opening the line that was never
-- a key press: a click on the line itself, a click on a name in the log, the
-- rail picking a room, `/wk chat`. None of those is a command, so none of them
-- needs the clean stack.
function ChatWindow.Focus()
	if not built then
		return false
	end
	if not window:IsShown() then
		ChatWindow.Show()
	end
	ns.ChatField.Open()
	ChatWindow.Fill()
	return true
end

-- The slash key's line: one with a slash already in it and no room prefix. The
-- prefix would turn /dance into a sentence said out loud in party.
--
-- The client's own OPENCHATSLASH does this without us now. What is left here is
-- the same line opened from somewhere that is not a key, and the harness, which
-- has no keys at all.
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
	ns.ChatField.Open()
	local field = ns.ChatField.Box()
	if not field then
		return false
	end
	local text = field:GetText() or ""
	if text == "" or text:sub(1, 1) == "/" then
		field:SetText("/")
		if type(field.SetCursorPosition) == "function" then
			field:SetCursorPosition(1)
		end
	end
	return true
end

-- What is in the line right now. Public because the field is where the answer
-- to "which channel is this going to" is written down: there is no second piece
-- of state holding it, which is the whole point of the redesign, so anything
-- checking that behaviour has to be able to read the text.
function ChatWindow.Line()
	local field = built and ns.ChatField.Box() or nil
	if not field then
		return ""
	end
	return field:GetText() or ""
end

-- The client's own field, for the harness. Handed out for the reason the
-- rectangle round it is: what is being checked is which frame the characters go
-- into, and a boolean this file computed is a boolean this file could compute
-- wrongly and still agree with itself.
function ChatWindow.Entry()
	return built and ns.ChatField.Box() or nil
end

-- Typing, as far as the field is concerned. Public because what a key press
-- does to the field lives inside the client's own script handlers, and a path
-- nothing else can reach is a path nothing else can check.
function ChatWindow.Type(text)
	local field = built and ns.ChatField.Box() or nil
	if not field then
		return false
	end
	field:SetText(text or "")
	return true
end

-- The enter key, as far as the field is concerned.
--
-- Nothing of ours runs on it in the game: the client dispatches the press
-- straight into FrameXML's own OnEnterPressed, which is the entire point of
-- borrowing the field. This calls whatever script is on the frame so that the
-- harness, which has no keyboard, can reach the same path.
function ChatWindow.Enter()
	local field = built and ns.ChatField.Box() or nil
	if not field then
		return false
	end
	local pressed = field:GetScript("OnEnterPressed")
	if pressed then
		pressed(field)
	end
	return true
end

-- The focus going, on its own and after the fact, which is the shape the client
-- reports it in. Public for the reason Type above is: the handler is the
-- client's and nothing else can raise it.
function ChatWindow.Blur()
	local field = built and ns.ChatField.Box() or nil
	if not field then
		return false
	end
	field:ClearFocus()
	return true
end

-- One line, sent to wherever the room and the text between them say. Public
-- because a slash word and the harness want the same path, and a send that
-- lives inside a script handler is a send nothing else can reach.
function ChatWindow.Send(text)
	local kind, target = ns.Rooms.Target(active)
	return ns.Compose.Send(text, kind, target)
end

-- One line from the addon, in the room you are reading.
--
-- The addon's own voice is ns.Print, and ns.Print writes to Blizzard's window.
-- While that window is hidden the line comes back round through the hook on
-- AddMessage and lands in the System room, which is not the room anybody typing
-- has open. A sentence about the line you just typed belongs where you typed
-- it, so this exists and Chat/Compose.lua uses it.
--
-- Refused while the window is down, and the refusal is what sends the caller
-- back to ns.Print. A window that is not on the screen is a window whose logs
-- nobody is reading, and Blizzard's own is up in that case anyway.
function ChatWindow.Tell(text)
	if not built or not window:IsShown() or type(text) ~= "string" or text == "" then
		return false
	end
	OnLine({ active }, ("%s|cff40c0f0WarriorKit|r: %s"):format(ns.ChatFeed.Stamp(), text),
		C.quiet[1], C.quiet[2], C.quiet[3], false)
	return true
end

--------------------------------------------------------------------------
-- What it is doing
--------------------------------------------------------------------------

function ChatWindow.Lock()
	if not built then
		return false
	end
	window.place:Lock(not ns.db.locked)
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

-- Whether the room's log is the one on the screen.
--
-- Named for the harness, and it earns the surface for the reason Shape above
-- does. A log is made by the first line that lands in its room, which is after
-- Show picked that room and hid every log there was, so a log made hidden is a
-- room that holds the line, raises the count against its own name, and draws
-- nothing at all. Everything else about it reads correctly.
function ChatWindow.Drawn(id)
	local log = logs[id]
	return (log and log.frame:IsShown()) and true or false
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
		ns.db.chatWidth = ns.DefaultCopy("chatWidth")
		ns.db.chatHeight = ns.DefaultCopy("chatHeight")
		moved = true
	end
	if ns.db.chatFont == WAS.font then
		ns.db.chatFont = ns.DefaultCopy("chatFont")
		moved = true
	end
	return moved
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
-- No PLAYER_REGEN_ENABLED. Nothing in this window is refused in a fight any
-- more: the one thing that was is the override binding on the enter key, and
-- the client owns that key again.
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
	Refresh()
end)

-- The window is on the pixel grid, so a resolution change or a UI size change
-- moves every number in it at once. The zoom first, because every measurement
-- below is in the window's own units and those units are what the zoom decides.
-- The screen's own step is half of this window's zoom, so a resolution change
-- still moves it. Relayout is what re-zooms now, because the setting under it
-- can move without the screen moving at all.
ns.UI.OnRescale(function()
	if not built then
		return
	end
	Relayout()
end)
