local ADDON, ns = ...

local Window = {}
ns.SocketWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The socketing window
--
-- Blizzard's socketing frame is three holes and a button, and everything it
-- does not tell you is what makes socketing tedious. It does not know what you
-- are carrying, so putting a gem in means finding it in your bags and dragging
-- it across the screen. It says whether a gem matched with a sparkle that is
-- over in half a second. And it names the gem you are about to destroy nowhere
-- at all: replacing one is a click, a confirm dialog with the word "gem" in it,
-- and a thing you owned is gone.
--
-- So this window is the item, its holes, and every gem in your bags that goes
-- in one, on one page. Click a hole, click a gem, and it is in front of that
-- hole. Nothing is spent until you press apply, and the line beside apply is
-- what applying costs you.
--
-- **The session drives the window and not the other way round.** Every route
-- into socketing on this client, the shift click on this addon's gear page and
-- the client's own on a bag square, ends in the same server session and the
-- same SOCKET_INFO_UPDATE. This window listens for that event rather than being
-- opened by the thing that started it, which is why a gesture the addon does
-- not own still lands here, and why there is one place that knows the window is
-- up.
--
-- **Closing the window ends the session.** That is the client's own rule for
-- this frame and it is why Sockets/Blizzard.lua parks Blizzard's rather than
-- hiding it. Ours closes on the cross, on escape and on the session ending
-- underneath, and only the first two call back into the client.
--
-- **The bonus line is the reading Blizzard's frame does not have.** An item
-- pays its socket bonus only when every hole holds a gem of its own colour, so
-- that is a yes or a no about the whole item rather than a sparkle per hole,
-- and it is the number you are actually socketing for. It is read off the
-- client's own `matches` for each hole rather than off the colour table in
-- Core/Sockets.lua, so the sentence cannot claim a bonus the server disagrees
-- with.
--------------------------------------------------------------------------

local WIDTH = 404

-- One hole. Bigger than a bag square, because it is the thing you aim at and
-- there are at most three of them, and the picture in it is a gem, which is one
-- shape with one colour and reads badly small.
local HOLE = 40

-- The line under a hole holding a gem you have not paid for. Two pixels, the
-- same underscore the gear page draws durability with, and in the accent rather
-- than in the socket's colour: what it says is "this is not saved yet", which
-- is a fact about the window and not about the gem.
local WAIT = 2

-- The item's own picture at the head, at bag square size, because that is what
-- it is.
local PIECE = 31

-- The gems, in as many columns as the width holds.
local GEM_COLUMNS = 11

-- The most gem squares the pool will ever build. A jewelcrafter carrying more
-- socketing gems than this is carrying eleven rows of them, and the twelfth row
-- is a scroll nobody reads to the end of. Said out loud in the caption when it
-- bites, rather than silently dropped.
local MOST_GEMS = 121

-- What each hole is painted. Blizzard's own three, kept because they are the
-- colours the gem itself is and every guide in the game is written against
-- them. Meta is the exception and is this addon's: the client draws that socket
-- in a washed grey that disappears against a dark window.
local INK = {
	Red    = { 1.00, 0.47, 0.47 },
	Yellow = { 0.97, 0.82, 0.29 },
	Blue   = { 0.47, 0.67, 1.00 },
	Meta   = { 0.78, 0.78, 0.88 },
}

local HEAD_Y = M.pad
local HEAD_H = PIECE
local HOLES_Y = HEAD_Y + HEAD_H + M.pad
local WORD_Y = HOLES_Y + HOLE + 3
local RULE_Y = WORD_Y + M.small + M.pad
local CAPTION_Y = RULE_Y + M.hairline + M.rowGap
local LIST_Y = CAPTION_Y + M.heading + 3 + M.rowGap
local LIST_ROWS = 4
local LIST_H = LIST_ROWS * (UI.SLOT + UI.SLOT_GAP)

local HEIGHT = M.title + LIST_Y + LIST_H + M.pad + M.footer

local window
local face, title, holes = nil, nil, {}
local view, caption, verdict, apply
local squares = {}
local gems = {}

-- Whether the client has a session open right now. Held here rather than asked
-- for, because the question the window needs answered is "did this addon open
-- one and has the client not closed it", and the count answers zero both while
-- a session is open on an item with no holes and while there is no session at
-- all.
local session = false

-- Which hole the next gem you click goes in. Held between paints, because the
-- paint that follows putting a gem in must not move the selection out from
-- under the next click.
local chosen = 1

--------------------------------------------------------------------------
-- Reading the session
--------------------------------------------------------------------------

local function Ink(colour)
	return INK[colour] or C.edge
end

-- What one hole is showing, and whether it has been paid for.
--
-- The gem you have put there wins over the gem that is already in it, because
-- what the window draws is the item you would have after pressing apply. The
-- fifth return is which of the two it was, which is the whole of what the
-- accent bar under a hole says.
local function Held(index)
	local name, icon, link, matches = ns.Sockets.Waiting(index)
	if name then
		return name, icon, link, matches, true
	end
	name, icon, link, matches = ns.Sockets.Filled(index)
	return name, icon, link, matches, false
end

-- Whether anything is waiting to be paid for, and what the payment costs.
-- Two numbers out of one walk: how many holes hold a gem you have not applied,
-- and how many of those are sitting over a gem that would be destroyed.
local function Pending(count)
	local waiting, destroying = 0, 0
	for index = 1, count do
		if ns.Sockets.Waiting(index) then
			waiting = waiting + 1
			if ns.Sockets.Filled(index) then
				destroying = destroying + 1
			end
		end
	end
	return waiting, destroying
end

-- Whether every hole would hold a gem of its own colour once you applied.
-- Nil where a hole is still empty, because an item with a hole in it pays no
-- bonus whatever the other two are.
local function Bonus(count)
	for index = 1, count do
		local _, _, _, matches = Held(index)
		if matches == nil then
			return nil
		end
		if not matches then
			return false
		end
	end
	return count > 0
end

-- The hole a window that has just opened points at: the first one with nothing
-- in it, or the first one on an item that is already full.
local function FirstEmpty(count)
	for index = 1, count do
		if not (ns.Sockets.Filled(index)) then
			return index
		end
	end
	return 1
end

--------------------------------------------------------------------------
-- One hole
--------------------------------------------------------------------------

local function HoleSubject(index)
	local _, _, link = Held(index)
	if link then
		return { kind = "item", link = link }
	end
	local colour = ns.Sockets.Colour(index)
	return { kind = "note", title = (colour and colour:lower() or "empty") .. " socket",
		lines = { { "nothing in it", color = C.dim } } }
end

-- Left picks the hole the next gem goes in. Right takes back what is waiting
-- there, which is the one gesture that can undo a click without spending
-- anything.
local function HoleClick(self, button)
	if button == "RightButton" then
		ns.Sockets.Take(self.index)
	else
		chosen = self.index
	end
	Window.Paint()
end

local function HoleEnter(self)
	ns.Tip.Open(self, HoleSubject(self.index), nil, UI.Tooltip.BESIDE)
end

local function TipClose()
	ns.Tip.Close()
end

local function BuildHole(parent, index)
	local hole = CreateFrame("Button", nil, parent)
	hole:SetSize(HOLE, HOLE)
	hole:SetPoint("TOPLEFT", M.pad + (index - 1) * (HOLE + M.gutter), -HOLES_Y)
	UI.Dress(hole, HOLE)
	hole.index = index
	hole:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	hole:SetScript("OnClick", HoleClick)
	hole:SetScript("OnEnter", HoleEnter)
	hole:SetScript("OnLeave", TipClose)

	hole.wait = ns.Fill(hole, "OVERLAY", C.accent[1], C.accent[2], C.accent[3], 1)
	hole.wait:SetHeight(WAIT)
	hole.wait:SetPoint("BOTTOMLEFT")
	hole.wait:SetPoint("BOTTOMRIGHT")
	hole.wait:Hide()

	hole.word = UI.Label(hole, M.small, C.dim, "CENTER", UI.FLAT)
	hole.word:SetPoint("TOP", hole, "BOTTOM", 0, -3)
	hole.word:SetWidth(HOLE + M.gutter)
	UI.Wrap(hole.word, false)

	hole:Hide()
	return hole
end

local function PaintHole(index)
	local hole = holes[index]
	local colour = ns.Sockets.Colour(index)
	local name, icon, _, matches, waiting = Held(index)

	UI.SlotPaint(hole, icon, nil, nil, false)
	ns.Recolor(hole.edges, Ink(colour))
	UI.Tint(hole.bg, index == chosen and C.selected or C.sunken)
	hole.wait:SetShown(waiting and true or false)

	hole.word:SetText(colour and colour:lower() or "")
	local ink = name and (matches and Ink(colour) or C.loss) or C.quiet
	hole.word:SetTextColor(ink[1], ink[2], ink[3])
	hole:Show()
end

--------------------------------------------------------------------------
-- One gem out of your bags
--------------------------------------------------------------------------

local function GemClick(self)
	local gem = self.gem
	if not gem then
		return
	end
	-- Into the hole you picked. A hole holding something already takes it
	-- anyway: that is the replacement, and the line beside apply is what says
	-- what it costs.
	ns.Sockets.Put(chosen, gem.bag, gem.slot)
	Window.Paint()
end

local function GemEnter(self)
	local gem = self.gem
	if not gem then
		return
	end
	ns.Tip.Open(self, { kind = "item", link = gem.link, bag = gem.bag, slot = gem.slot },
		nil, UI.Tooltip.BESIDE)
end

local function BuildGem(parent, index)
	local square = CreateFrame("Button", nil, parent)
	square:SetSize(UI.SLOT, UI.SLOT)
	local column = (index - 1) % GEM_COLUMNS
	local row = math.floor((index - 1) / GEM_COLUMNS)
	square:SetPoint("TOPLEFT", column * (UI.SLOT + UI.SLOT_GAP),
		-row * (UI.SLOT + UI.SLOT_GAP))
	UI.Dress(square, UI.SLOT)
	square:RegisterForClicks("LeftButtonUp")
	square:SetScript("OnClick", GemClick)
	square:SetScript("OnEnter", GemEnter)
	square:SetScript("OnLeave", TipClose)
	square:Hide()
	return square
end

local function PaintGems(colour)
	local shown = 0
	for index = 1, MOST_GEMS do
		local gem = gems[index]
		local square = squares[index]
		if not gem then
			if square then
				square:Hide()
			end
		else
			if not square then
				square = BuildGem(view.canvas, index)
				squares[index] = square
			end
			square.gem = gem
			UI.SlotPaint(square, gem.icon, nil, gem.quality,
				not ns.Sockets.Fits(gem.colour, colour))
			square:Show()
			shown = index
		end
	end
	return shown
end

--------------------------------------------------------------------------
-- What the window says
--------------------------------------------------------------------------

-- The gems you are carrying, the ones that go in the hole you have picked
-- first. Sorted rather than filtered: a gem that does not match is still a gem
-- you can socket, it only costs you the bonus, and a list that hid it would be
-- deciding that for you.
local function Sort(colour)
	table.sort(gems, function(a, b)
		local fitA = ns.Sockets.Fits(a.colour, colour)
		local fitB = ns.Sockets.Fits(b.colour, colour)
		if fitA ~= fitB then
			return fitA
		end
		if a.colour ~= b.colour then
			return a.colour < b.colour
		end
		return (a.name or "") < (b.name or "")
	end)
end

local function Caption(colour, shown)
	if #gems == 0 then
		return "no gem in your bags goes in a hole"
	end
	local fits = 0
	for index = 1, #gems do
		if ns.Sockets.Fits(gems[index].colour, colour) then
			fits = fits + 1
		end
	end
	-- "this hole" for a colour the client would not name, which is the one thing
	-- a hole can be that no gem is offered for.
	local said = ("%d of the %d gems you are carrying fit the %s hole")
		:format(fits, #gems, colour and colour:lower() or "this")
	if shown < #gems then
		return said .. (", and %d are not drawn"):format(#gems - shown)
	end
	return said
end

-- The line beside apply.
--
-- What it costs comes first, because that is the half you cannot undo, and the
-- bonus comes after, because that is the half you are socketing for. There is
-- no "two gems waiting" line: a hole with a gem in front of it already wears
-- the accent bar and the button is already lit, so a count would be the third
-- way of saying the same thing and would push the sentence that matters off the
-- footer.
--
-- The bonus is read off the client's `matches` for every hole rather than off
-- the colour table in Core/Sockets.lua, and Held prefers the gem you have put
-- there over the gem that is in it, so the sentence is about the item you would
-- have after pressing apply rather than the one you are holding now.
local function Verdict(count)
	local _, destroying = Pending(count)
	if destroying > 0 then
		return ("applying destroys %d gem%s you have already socketed")
			:format(destroying, destroying == 1 and "" or "s"), C.loss
	end
	if ns.Sockets.Binds() then
		return "applying binds this to you, so it can no longer be traded back", C.loss
	end
	local bonus = Bonus(count)
	if bonus == nil then
		return "an empty hole, so no socket bonus", C.dim
	end
	if bonus then
		return "every gem matches its hole, so the socket bonus is yours", C.tick
	end
	return "a gem is off colour, so there is no socket bonus", C.dim
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function Ask()
	local count = ns.Sockets.Count()
	local _, destroying = Pending(count)
	if destroying == 0 and not ns.Sockets.Binds() then
		ns.Sockets.Apply()
		return
	end
	UI.Ask({
		title = "Socket it",
		question = (Verdict(count)) .. ". This cannot be undone.",
		accept = "socket it",
		onAccept = function()
			ns.Sockets.Apply()
			Window.Paint()
		end,
	})
end

local function BuildHead(body)
	face = UI.Icon(body, "ARTWORK")
	face:SetSize(PIECE, PIECE)
	face:SetPoint("TOPLEFT", M.pad, -HEAD_Y)

	title = UI.Label(body, M.heading, C.text, "LEFT", UI.FLAT)
	title:SetPoint("LEFT", face, "RIGHT", M.gutter, 0)
	title:SetPoint("RIGHT", body, "RIGHT", -M.pad, 0)
	UI.Wrap(title, false)

	for index = 1, ns.Sockets.Most() do
		holes[index] = BuildHole(body, index)
	end

	local rule = UI.Rule(body, C.hairline)
	rule:SetPoint("TOPLEFT", M.pad, -RULE_Y)
	rule:SetPoint("TOPRIGHT", -M.pad, -RULE_Y)

	caption = UI.Label(body, M.heading, C.heading, "LEFT", UI.FLAT)
	caption:SetPoint("TOPLEFT", M.pad, -CAPTION_Y)
	caption:SetPoint("RIGHT", body, "RIGHT", -M.pad, 0)
	UI.Wrap(caption, false)
end

local function BuildFoot()
	verdict = UI.Label(window.footer, M.small, C.dim, "LEFT", UI.FLAT)
	verdict:SetPoint("LEFT")
	UI.Wrap(verdict, false)

	apply = UI.Button(window.footer, { label = "apply", width = 90, height = M.row,
		onClick = Ask })
	apply:SetPoint("RIGHT")
	verdict:SetPoint("RIGHT", apply, "LEFT", -M.gutter, 0)
end

local function Build()
	window = UI.Window({
		name = "WarriorKitSockets",
		title = "Sockets",
		width = WIDTH,
		height = HEIGHT,
		zoom = function() return ns.Zoom("socketsZoom") end,
	})
	ns.Remember(window)

	BuildHead(window.content)

	view = UI.ScrollView(window.content, { overlay = true })
	view.frame:SetPoint("TOPLEFT", M.pad, -LIST_Y)
	view:Resize(WIDTH - M.pad * 2, LIST_H)

	BuildFoot()

	-- What the harness reads. Recorded on the window the way the merchant window
	-- records its footer and for the same reason: a section presses what a
	-- player presses rather than calling the thing a press would call, and it
	-- reads the strings the window actually drew rather than the ones the
	-- source says it would.
	window.holes, window.squares = holes, squares
	window.caption, window.verdict, window.apply = caption, verdict, apply

	-- Hooked rather than set, because UI/Window.lua has its own handler here
	-- that closes an open dropdown. Every way out of this window is a way out of
	-- the session, so this is the one place that ends it.
	window.frame:HookScript("OnHide", function()
		ns.Tip.Close()
		Window.Leave()
	end)
	return window
end

--------------------------------------------------------------------------

-- Everything the session can move. Called on the client's own update event, on
-- every click in the window, and never on a tick.
function Window.Paint()
	if not window or not window:IsShown() then
		return false
	end

	local count = ns.Sockets.Count()
	if count < 1 then
		return false
	end
	if chosen > count then
		chosen = 1
	end

	local name, icon, quality = ns.Sockets.Piece()
	face:SetTexture(icon or "")
	title:SetText(name or "")
	local ink = UI.SlotInk(quality)
	title:SetTextColor(ink[1], ink[2], ink[3])

	for index = 1, ns.Sockets.Most() do
		if index <= count then
			PaintHole(index)
		else
			holes[index]:Hide()
		end
	end

	local colour = ns.Sockets.Colour(chosen)
	gems = ns.Sockets.Gems()
	Sort(colour)
	local shown = PaintGems(colour)
	caption:SetText(Caption(colour, shown))
	view:Update(math.ceil(shown / GEM_COLUMNS) * (UI.SLOT + UI.SLOT_GAP))

	local said, tone = Verdict(count)
	verdict:SetText(said)
	verdict:SetTextColor(tone[1], tone[2], tone[3])

	local waiting = Pending(count)
	if waiting > 0 then
		apply:Enable()
		apply.text:SetTextColor(C.text[1], C.text[2], C.text[3])
	else
		apply:Disable()
		apply.text:SetTextColor(C.quiet[1], C.quiet[2], C.quiet[3])
	end
	return true
end

-- The session opened. Which item it opened on is the client's business and is
-- read back rather than passed in, which is what lets a gesture this addon does
-- not own land here.
function Window.Show()
	if not ns.db.sockets or ns.Sockets.Count() < 1 then
		return false
	end
	if not window then
		Build()
	end
	chosen = FirstEmpty(ns.Sockets.Count())
	window:Show()
	-- Park the client's frame now rather than on the once-a-second pass. It is
	-- shown in the same handler that loaded it, and the pass is up to a second
	-- later, which was a flash of Blizzard's window over ours on every gem.
	ns.SocketBlizzard.Apply()
	Window.Paint()
	return true
end

function Window.Hide()
	if not window then
		return false
	end
	window:Hide()
	return true
end

-- The window went down by any route: the cross, escape, or the session ending
-- under it. The first two mean you are done with this item and the client has
-- to be told; the third is the client telling us, and calling back into it
-- there would be answering a message with itself.
function Window.Leave()
	if not session then
		return false
	end
	session = false
	ns.SocketBlizzard.Apply()
	return ns.Sockets.Close()
end

function Window.Shown()
	return (window and window:IsShown()) and true or false
end

-- The window itself, for the harness. Handed out rather than answered about,
-- for the reason ns.Attic.Frame is: what a section checks is the widget a
-- player presses, and a boolean this file computed is a boolean this file could
-- compute wrongly and still agree with itself.
function Window.Frame()
	return window
end

function Window.Describe()
	if not ns.Sockets.Available() then
		return "off, this client has no sockets"
	end
	if not ns.db.sockets then
		return "off"
	end
	if not session then
		return "shut, nothing is open"
	end
	local count = ns.Sockets.Count()
	local waiting = Pending(count)
	return ("open on %s, %d hole%s, %d waiting")
		:format(ns.Sockets.Piece() or "?", count, count == 1 and "" or "s", waiting)
end

--------------------------------------------------------------------------
-- What wakes it
--
-- The two edges of a session and the two answers to applying. SOCKET_INFO_UPDATE
-- is both the opening and every change inside it, which is the client's own
-- shape: it fires when the session opens, when a gem goes in front of a hole and
-- when one comes back out. BAG_UPDATE is the other half of the gem list, because
-- socketing one takes it out of your bags and the session says nothing about
-- that.
--------------------------------------------------------------------------

local function OnEvent(_, event)
	if event == "SOCKET_INFO_UPDATE" then
		session = true
		if not Window.Shown() then
			Window.Show()
		else
			Window.Paint()
		end
		return
	end
	if event == "SOCKET_INFO_CLOSE" then
		session = false
		Window.Hide()
		return
	end
	Window.Paint()
end

local events

function Window.Apply()
	if not ns.Sockets.Available() then
		return false
	end
	if not events then
		events = CreateFrame("Frame")
		events:SetScript("OnEvent", OnEvent)
		-- Registered whatever the setting says, because turning the setting off
		-- with a session open still has to shut this.
		events:RegisterEvent("SOCKET_INFO_CLOSE")
	end
	if ns.db.sockets then
		events:RegisterEvent("SOCKET_INFO_UPDATE")
		events:RegisterEvent("SOCKET_INFO_SUCCESS")
		events:RegisterEvent("SOCKET_INFO_FAILURE")
		events:RegisterEvent("BAG_UPDATE")
		return true
	end
	events:UnregisterEvent("SOCKET_INFO_UPDATE")
	events:UnregisterEvent("SOCKET_INFO_SUCCESS")
	events:UnregisterEvent("SOCKET_INFO_FAILURE")
	events:UnregisterEvent("BAG_UPDATE")
	Window.Hide()
	return false
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
	Window.Apply()
end)
