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
-- somewhere else, in the accent colour against the right edge of its row.
-- Selecting a room clears its own count. That is the whole of the alert design:
-- no flashing, no toast, no sound unless somebody in one of your groups spoke.
--------------------------------------------------------------------------

local FRAME_NAME = "WarriorKitChat"

-- The button the enter key is bound onto while Blizzard's window is hidden. A
-- name is what SetOverrideBindingClick binds to, which is the whole reason this
-- frame is named at all.
local ENTER_NAME = "WarriorKitChatEnterButton"

local window, rail, entry, enterButton
local title, note

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

local function Paint()
	local kind, target = ns.Rooms.Target(active)
	title:SetText(ns.Rooms.Title(active))
	note:SetText(ns.Compose.Note(kind, target))
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

local function OnLine(rooms, text, r, g, b, important)
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
-- Layout
--
-- One function that places everything, run when the window is built, when a
-- setting moves it and when the pixel grid moves under it. It recomputes rather
-- than caches, the same as the options panel: this is never on a ticker and a
-- cached rectangle that is wrong once is wrong until a reload.
--------------------------------------------------------------------------

local function Relayout()
	if not built then
		return
	end

	local db = ns.db
	local width, height = window:Resize(db.chatWidth, db.chatHeight)
	local px = ns.Pixel(window.frame)
	local body = height - M.title - M.footer

	rail.frame:ClearAllPoints()
	rail.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT")
	rail:Resize(M.rooms, body)

	local left = M.rooms + M.pad
	local room = width - left - M.pad

	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", window.content, "TOPLEFT", left, -M.rowGap)
	note:ClearAllPoints()
	note:SetPoint("TOPRIGHT", window.content, "TOPRIGHT", -M.pad, -M.rowGap)
	note:SetPoint("LEFT", title, "RIGHT", M.gutter, 0)

	local top = M.rowGap + M.row + M.rowGap
	for _, log in ipairs(every) do
		log.frame:ClearAllPoints()
		log.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT", left, -top)
		log:SetFontSize(db.chatFont)
		log:Resize(math.max(room, M.row), math.max(body - top - M.rowGap, M.row))
	end

	entry.box:ClearAllPoints()
	entry.box:SetPoint("LEFT", window.footer, "LEFT", 0, 0)
	entry.box:SetPoint("RIGHT", window.footer, "RIGHT", 0, 0)
	entry.box:SetHeight(M.control)
	-- The line you type in is drawn at the size the lines you read are. A field
	-- that stays at twelve while the log goes to eighteen is the one part of the
	-- window that did not take the setting.
	entry.edit:SetFontObject(UI.Font(db.chatFont, UI.FLAT))

	window:SetOpacity(db.chatAlpha / 100)
	local point = db.chatPoint
	window.frame:ClearAllPoints()
	window.frame:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	-- The window is on the grid, so the hairline it is drawn with has to be
	-- resized whenever the grid moves under it.
	ns.EdgeSize(window.edges, px)
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

local function BuildEntry()
	local box = UI.Box(window.footer, C.sunken, C.edge)
	local edit = CreateFrame("EditBox", nil, box)
	edit:SetPoint("TOPLEFT", 4, 0)
	edit:SetPoint("BOTTOMRIGHT", -4, 0)
	edit:SetFontObject(UI.Font(M.font, UI.FLAT))
	edit:SetTextColor(C.text[1], C.text[2], C.text[3])
	edit:SetAutoFocus(false)
	-- The server's own cap on one line of chat. A longer one is refused whole,
	-- so it is better to stop the typing than to lose the sentence.
	edit:SetMaxLetters(255)

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
		UI.Tint(box.bg, C.selected)
	end)
	edit:SetScript("OnEditFocusLost", function()
		UI.Tint(box.bg, C.sunken)
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

	return { box = box, edit = edit }
end

local function BuildHeader()
	title = UI.Label(window.content, M.heading, C.heading, "LEFT", UI.FLAT)
	title:SetHeight(M.row)
	UI.Wrap(title, false)

	-- What the enter key is about to do, in the words it will do it in. It is
	-- here rather than beside the field because this line is about the room and
	-- the room's name is the thing beside it.
	note = UI.Label(window.content, M.small, C.quiet, "RIGHT", UI.FLAT)
	note:SetHeight(M.row)
	UI.Wrap(note, false)
end

local function Build()
	window = UI.Window({
		name = FRAME_NAME,
		title = "Chat",
		width = ns.db.chatWidth,
		height = ns.db.chatHeight,
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
		onSelect = function(id) Show(id) end,
	})
	BuildHeader()
	entry = BuildEntry()

	enterButton = CreateFrame("Button", ENTER_NAME, window.frame)
	enterButton:SetScript("OnClick", function() ChatWindow.Focus() end)

	built = true
	active = ns.Rooms.ALL
	if not LogFor(ns.Rooms.ALL) then
		built = false
		return false
	end

	-- The close box is the window's own and hides the frame. Here it has to
	-- record that you closed it, or the next thing that applies a setting would
	-- put the window straight back up.
	window.close:SetScript("OnClick", function() ChatWindow.Hide() end)

	Relayout()
	Refresh()
	Show(ns.Rooms.ALL)

	ns.Rooms.OnClose = Close
	ns.ChatFeed.Attach(OnLine)
	return true
end

--------------------------------------------------------------------------
-- The enter key
--
-- Taken exactly while Blizzard's chat window is hidden, and handed back the
-- moment it is not. That is not a setting of its own on purpose. The client's
-- enter key opens the client's chat line; with that window hidden the line it
-- opens is invisible, so the key has to come here or typing is broken. With
-- that window on screen the key still works and there is nothing to fix.
--
-- An override sits on top of whatever the key already carried and is dropped by
-- one call, unlike SetBinding, which the next SaveBindings would make permanent.
-- Both calls are refused in combat, so a fight defers the work to
-- PLAYER_REGEN_ENABLED, which is the shape Buttons/Bars.lua uses for the same
-- reason.
--------------------------------------------------------------------------

local function WantsEnter()
	return built and ns.db.chat and ns.db.hideBlizzChat and window:IsShown()
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
	for _, key in ipairs({ "ENTER", "NUMPADENTER" }) do
		pcall(SetOverrideBindingClick, enterButton, true, key, ENTER_NAME, "LeftButton")
	end
	return true
end

--------------------------------------------------------------------------
-- The surface everything else uses
--------------------------------------------------------------------------

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
	if Build() then
		ChatWindow.Lock()
		ChatWindow.Apply()
		return true
	end
	return false
end

function ChatWindow.Apply()
	if not built then
		return false
	end
	Relayout()
	Refresh()

	local shown = (ns.db.chat and ns.db.chatShown) and true or false
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
	ns.db.chatShown = true
	ChatWindow.Apply()
	return true
end

function ChatWindow.Hide()
	if not built then
		return false
	end
	ns.db.chatShown = false
	window.frame:Hide()
	ns.ChatFeed.Watched(false)
	ns.ChatBlizzard.Apply()
	ChatWindow.Keys()
	return true
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
	if not window:IsShown() then
		ChatWindow.Show()
	end
	ChatWindow.Fill()
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
		return "not built yet"
	end
	return ("%s, %s, in %s"):format(window:IsShown() and "open" or "closed",
		ns.Rooms.Describe(), ns.Rooms.Title(active))
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

-- What the client's own key binding list calls it. Beside the function it
-- calls, the way the marking keys are.
BINDING_NAME_WARRIORKIT_CHAT = "Type in the WarriorKit chat window"

function WarriorKit_ChatEnter()
	ChatWindow.Focus()
end

--------------------------------------------------------------------------

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
		if not ns.db.chat then
			-- Nothing is built while the part is off, so a player who has turned
			-- it off pays nothing at all for it: no frames, no logs, no font
			-- objects. Turning it back on builds it.
			return
		end
		if Build() then
			ChatWindow.Lock()
			ChatWindow.Apply()
		end
		return
	end

	if not built then
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
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
