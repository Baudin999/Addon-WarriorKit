local ADDON, ns = ...

local ChatWindow = {}
ns.ChatWindow = ChatWindow

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The chat window
--
-- Three tabs, one log each, and a line to type in. Everything in it comes out
-- of UI/: the chrome is UI.Window, the strip is UI.TabStrip, each log is
-- UI.Log, the bar beside it is UI.ScrollBar and the colours and the pixel
-- metrics are the theme's. There is no Blizzard template anywhere in it and no
-- art asset behind it.
--
-- **Why three tabs and not one, and not eight.**
--
-- People is the reason the part exists. Anything anyone on your list says, in
-- any channel, lands here, and so does anything you whisper to them. One tab
-- for all of them: what you want to know is whether anybody you care about has
-- said something, and that is one question. It is not drawn at all until there
-- is somebody on the list, which is what makes it appear on its own when you
-- add the first name.
--
-- Chat is every person talking, in every channel the addon captures, in one
-- column. That is what a chat window is, and the reason Blizzard's is hard to
-- read is not that it lacks tabs, it is the fifteen kinds of system text
-- running through the same column. Those stay where they were.
--
-- Whispers is the one stream that must never scroll past, on the one screen
-- where it does.
--
-- The tabs mark themselves when something arrives on one you are not looking
-- at, and selecting a tab clears its own mark. That is the whole of the alert
-- design: no flashing, no toast, no sound unless you asked for one.
--------------------------------------------------------------------------

local FRAME_NAME = "WarriorKitChat"

-- The strip, in order. The id is what Chat/Feed.lua streams a line to, so the
-- feed and the window agree on three strings and on nothing else.
local TABS = {
	{ id = ns.ChatFeed.PEOPLE,  label = "People" },
	{ id = ns.ChatFeed.CHAT,    label = "Chat" },
	{ id = ns.ChatFeed.WHISPER, label = "Whispers" },
}

-- How wide the button that says which channel you are typing into is. Fixed,
-- because it changes label as you cycle it and a control that resizes under
-- your cursor is a control you misclick.
local SEND_W = 58

local window, tabs, entry, sendButton
local logs, byId = {}, {}
local active = 1
local built = false

-- Who a plain message goes to when the channel is a whisper. Set by clicking a
-- name in the log, by a whisper arriving, and by the reply word. Not saved: who
-- you were talking to is a fact about this session.
local replyTo

--------------------------------------------------------------------------
-- What you are typing into
--
-- Only the channels that exist right now. A guild line typed by somebody with
-- no guild is an error message from the server, and a party line typed alone is
-- the same, so the button skips them rather than offering them and letting the
-- server say no.
--------------------------------------------------------------------------

local function InGroup()
	if type(_G.IsInGroup) == "function" then
		return _G.IsInGroup()
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
		return _G.IsInRaid()
	end
	if type(_G.GetNumRaidMembers) == "function" then
		return (_G.GetNumRaidMembers() or 0) > 0
	end
	return false
end

local CHANNELS = {
	{ key = "SAY", label = "say", live = function() return true end },
	{ key = "PARTY", label = "party", live = InGroup },
	{ key = "RAID", label = "raid", live = InRaid },
	{ key = "GUILD", label = "guild",
		live = function() return type(_G.IsInGuild) == "function" and _G.IsInGuild() end },
	{ key = "YELL", label = "yell", live = function() return true end },
	{ key = "WHISPER", label = "reply", live = function() return replyTo ~= nil end },
}

local channel = 1

local function Channel()
	local row = CHANNELS[channel]
	if row and row.live() then
		return row
	end
	-- Whatever was chosen has stopped being possible, which is what leaving a
	-- party looks like from here. Say is always possible and is where the
	-- client's own field lands too.
	channel = 1
	return CHANNELS[1]
end

local function PaintSend()
	if not sendButton then
		return
	end
	local row = Channel()
	local label = row.label
	if row.key == "WHISPER" and replyTo then
		label = replyTo:gsub("%-.*$", "")
	end
	sendButton.text:SetText(label)
end

function ChatWindow.Cycle(step)
	local count = #CHANNELS
	for offset = 1, count do
		local index = ((channel - 1 + step * offset) % count) + 1
		if CHANNELS[index].live() then
			channel = index
			PaintSend()
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------
-- Sending
--
-- Two paths, and the split is at the slash.
--
-- Anything starting with a slash is the client's own business: /w, /join,
-- /dance, another addon's command. Rebuilding that parser here would mean
-- keeping up with every command in the game, so the text is handed to
-- ChatEdit_SendText, which is FrameXML's own and is what Blizzard's field
-- calls when you press enter in it.
--
-- Everything else is a message to the channel the button says, which is one
-- SendChatMessage. Doing that through the client's field instead would mean
-- driving the field's own channel state, which is a second place for "which
-- channel am I typing into" to live and disagree.
--------------------------------------------------------------------------

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

-- Public, because the edit box is not the only thing that sends: a key
-- binding, a slash word and the harness all want the same path, and a send
-- that lives inside a script handler is a send nothing else can reach.
function ChatWindow.Send(text)
	if type(text) ~= "string" then
		return false
	end
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		return false
	end

	if text:sub(1, 1) == "/" then
		return SendSlash(text)
	end

	local row = Channel()
	if type(_G.SendChatMessage) ~= "function" then
		return false
	end
	if row.key == "WHISPER" then
		if not replyTo then
			return false
		end
		_G.SendChatMessage(text, "WHISPER", nil, replyTo)
		return true
	end
	_G.SendChatMessage(text, row.key)
	return true
end

--------------------------------------------------------------------------
-- Lines arriving
--------------------------------------------------------------------------

-- A line goes to every stream it belongs to, which for a whisper from somebody
-- on the list is all three. Each log holds its own copy, because each has its
-- own scroll position and a shared buffer would mean scrolling one scrolls the
-- others.
local function OnLine(streams, text, r, g, b, important)
	for _, id in ipairs(streams) do
		local log = byId[id]
		if log then
			log:Add(text, r, g, b)
			-- Whether or not the window is up. A mark is what you look at when
			-- you open it, and one that was only set while you were watching
			-- would tell you nothing about the hour you were not.
			if log.index ~= active then
				tabs:SetUnread(log.index, true)
			end
		end
	end

	if important and ns.db.chatSound and byId[ns.ChatFeed.PEOPLE] then
		-- Only when you are not already looking at them. A sound for a line you
		-- are watching arrive is a sound you turn off, and then you have no
		-- sound for the one you miss.
		local shown = window and window:IsShown() and active == byId[ns.ChatFeed.PEOPLE].index
		if not shown then
			local kit = _G.SOUNDKIT
			if type(_G.PlaySound) == "function" and kit and kit.TELL_MESSAGE then
				_G.PlaySound(kit.TELL_MESSAGE)
			end
		end
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

local function Relayout()
	if not built then
		return
	end

	local db = ns.db
	local width, height = window:Resize(db.chatWidth, db.chatHeight)
	local px = ns.Pixel(window.frame)

	tabs.frame:ClearAllPoints()
	tabs.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT", M.pad, -M.rowGap)
	local strip = tabs:Resize(width - M.pad * 2)

	local top = M.rowGap + strip + M.rowGap
	local body = height - M.title - M.footer - top - M.rowGap
	for _, log in ipairs(logs) do
		log.frame:ClearAllPoints()
		log.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT", M.pad, -top)
		log:SetFontSize(db.chatFont)
		log:Resize(width - M.pad * 2, math.max(body, M.row))
	end

	sendButton:ClearAllPoints()
	sendButton:SetPoint("LEFT", window.footer, "LEFT", 0, 0)
	sendButton:SetSize(SEND_W, M.control)

	entry.box:ClearAllPoints()
	entry.box:SetPoint("LEFT", sendButton, "RIGHT", M.rowGap, 0)
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

local function Select(index)
	active = index
	for _, log in ipairs(logs) do
		log.frame:SetShown(log.index == index)
		if log.index == index then
			log:Sync()
		end
	end
end

-- A click on a name in the log. Ours rather than the client's, because the
-- client's answer is to open its own chat field, and a window with its own
-- field that sends you to another one is two fields.
local function OnLink(link, _, button)
	local name = link:match("^player:([^:]+)")
	if not name then
		return false
	end
	if button == "RightButton" then
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
	-- Tab cycles the channel, which is the one shortcut worth keeping from every
	-- chat field in every game.
	edit:SetScript("OnTabPressed", function()
		ChatWindow.Cycle(1)
	end)

	-- The box is a frame rather than a button, so the click that lands on the
	-- gap either side of the text has to be caught for the field to feel like a
	-- field.
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function()
		edit:SetFocus()
	end)

	return { box = box, edit = edit }
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

	tabs = UI.TabStrip(window.content, { onSelect = Select })

	for index, tab in ipairs(TABS) do
		tabs:Add(tab.label)
		local log, why = UI.Log(window.content, { onLink = OnLink })
		if not log then
			ns.Print("no chat window: " .. why .. ".")
			return false
		end
		log.index = index
		log.id = tab.id
		logs[index] = log
		byId[tab.id] = log
	end

	sendButton = UI.Button(window.footer, {
		label = "say",
		width = SEND_W,
		height = M.control,
		-- Left goes forward through the channels and right goes back, because
		-- six is enough that cycling past the one you wanted is a real thing to
		-- do and going round again is four more clicks.
		onClick = function(_, pressed)
			ChatWindow.Cycle(pressed == "RightButton" and -1 or 1)
		end,
	})
	sendButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	entry = BuildEntry()
	built = true

	-- The close box is the window's own and hides the frame. Here it has to
	-- record that you closed it, or the next thing that applies a setting would
	-- put the window straight back up.
	window.close:SetScript("OnClick", function() ChatWindow.Hide() end)

	Relayout()
	-- Chat, not People, because People is empty on a fresh install and a window
	-- that opens on an empty tab looks broken. The strip remembers nothing
	-- across a reload on purpose: where you were in a chat window an hour ago is
	-- not a preference.
	tabs:Select(2)

	ns.ChatFeed.Attach(OnLine)
	return true
end

--------------------------------------------------------------------------
-- The surface everything else uses
--------------------------------------------------------------------------

function ChatWindow.Built()
	return built
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

	-- The people tab is drawn only when there is somebody on the list, which is
	-- what makes it appear the moment you add the first name.
	local people = ns.People.Count() > 0
	tabs:SetShown(1, people)
	if not people and active == 1 then
		tabs:Select(2)
	end

	Relayout()
	window.frame:SetShown((ns.db.chat and ns.db.chatShown) and true or false)
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

-- Who a plain line goes to while the button says reply. Also what a click on a
-- name in the log does, which is the whole of "answer that".
function ChatWindow.Reply(name)
	if type(name) ~= "string" or name == "" then
		return false
	end
	replyTo = name
	for index, row in ipairs(CHANNELS) do
		if row.key == "WHISPER" then
			channel = index
		end
	end
	PaintSend()
	ChatWindow.Focus()
	return true
end

-- Put the cursor in the field, opening the window first if it is shut. This is
-- what the key binding calls, and it is the only way to type in this window
-- without reaching for the mouse: the client owns the enter key and an addon
-- that took it would be taking it from the client's own field.
function ChatWindow.Focus()
	if not built then
		return false
	end
	if not window:IsShown() then
		ChatWindow.Show()
	end
	entry.edit:SetFocus()
	return true
end

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
	local log = logs[active]
	return ("%s, %s"):format(window:IsShown() and "open" or "closed",
		log and log:Describe() or "no log")
end

-- Which channel a plain line goes to right now, and who it is addressed to
-- when that channel is a whisper.
function ChatWindow.Channel()
	local row = Channel()
	return row.key, replyTo
end

-- How many tabs are drawn right now, which is two until somebody is on the
-- people list and three after. The strip holds three either way: a tab with
-- nothing behind it is hidden rather than unmade, because a frame cannot be
-- destroyed on this client.
function ChatWindow.Tabs()
	return (built and tabs.shown) or 0
end

-- How many lines are on one tab. Named by the feed's own stream ids, so
-- nothing outside has to know that a tab is a log or that a log is a frame.
function ChatWindow.Count(id)
	local log = byId[id]
	return log and log:Count() or 0
end

-- What the tabs are holding, for the panel and for /wk status.
function ChatWindow.Held()
	local total = 0
	for _, log in ipairs(logs) do
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

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	if not ns.db.chat then
		-- Nothing is built while the part is off, so a player who has turned it
		-- off pays nothing at all for it: no frames, no logs, no font objects.
		-- Turning it back on builds it.
		return
	end
	if Build() then
		ChatWindow.Lock()
		ChatWindow.Apply()
	end
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

