local ADDON, ns = ...

local Window = {}
ns.MailWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The mail window
--
-- Two pages behind a strip of two tabs. Sending is a column of favourites down
-- the left, the name and the coin beside it, the attachments beside that, and
-- the subject and the letter under both. Receiving is a list of what is
-- waiting, one row a message.
--
-- **The band along the bottom is the point of the whole thing.**
--
-- Everything above it is furniture that the client's own window also has, drawn
-- better. The band is the thing the client has nothing like: one line, forty six
-- pixels of it, in the colour of whoever you are sending to. Green is a
-- character on your own account. Blue is somebody on your friends list or in one
-- of your groups. Red is a name this addon has never seen, and it says what is
-- riding on the letter while it says so.
--
-- It is one element rather than a warning that appears. A warning that appears
-- is a warning you have to notice appearing, and it moves everything under it
-- when it does. This is always there, always says who, and changes colour, so
-- there is no state in which the window is not telling you.
--
-- Red also arms the send. The button turns with the band and reads "send
-- anyway"; pressing it once says the band again and pressing it twice sends.
-- Anything you change in between disarms it, because the thing you changed is
-- the thing the warning was about.
--
-- The send button sits under the right end of that band, at the right end of
-- the footer, for the reason spelled out at BuildFoot: everything you touch
-- while writing is in the compose column, and the corner of the window that
-- column does not reach is the corner the button used to be in.
--
-- **Why the favourites are a column and not a dropdown.** A dropdown answers
-- "who can I pick" only after a click, which is one click more than a name you
-- mail every day is worth. The column is the same argument the chat window's
-- room rail makes: the thing you came for should be the thing you click.
--
-- **Nothing here is on a ticker.** The window changes when you type in it, when
-- you drop something on it, and when the server says the mailbox moved. All
-- three are events, and Paint is what every one of them ends in.
--------------------------------------------------------------------------

local WIDTH, HEIGHT = 640, 470

-- The favourites column. Wide enough for a name and no wider: past about
-- fifteen characters a character name is somebody's alt with a title in it, and
-- the row cuts rather than the column growing.
local RAIL = 120

-- One attachment square, and the block of them. Six to a line because twelve is
-- what a mail holds, so a full line and another full line is exactly one mail
-- and you can see the split without counting.
local SLOT, SLOT_GAP, COLUMNS = 34, 4, 6
local GRID_W = COLUMNS * SLOT + (COLUMNS - 1) * SLOT_GAP
local GRID_ROWS = 3
local GRID_H = GRID_ROWS * SLOT + (GRID_ROWS - 1) * SLOT_GAP

-- One line of text you type in, and one of the three coin fields.
local FIELD = 20
local COIN = 44

-- The band. Two lines: who, in the heading size, and what is going with it.
local BAND = 46

-- One message in the inbox list.
local ROW = 40
local ROW_ICON = 24

local CAPTION = M.small + 4

local window, tabs
local page = { }
local rail, grid, band, foot
local field = {}
local armed = false

-- Whether a field is being written into by the window rather than by you.
--
-- Every field commits on every keystroke and every commit ends in a repaint, and
-- the repaint puts each field back in step with the draft. Without the latch
-- those two chase each other: the paint writes the field, the write fires the
-- change handler, the handler repaints. It is the same latch UI/Scroll.lua keeps
-- between a bar's value and the content behind it, and for the same reason.
local syncing = false

-- Whether the client says you are standing at one. Every way out of the window
-- ends in CloseMail, and CloseMail on a mailbox that is already shut fires
-- MAIL_CLOSED again, which is the handler that closed the window. So the flag
-- is what breaks that circle, and it is the client's word rather than ours:
-- MAIL_SHOW sets it and MAIL_CLOSED clears it.
local atMailbox = false

--------------------------------------------------------------------------
-- The small kit this window is built out of
--
-- Four things UI/Widgets.lua does not have, because the kit there is a settings
-- page: every row in it is a label on the left and a control on the right, and
-- none of the four below is that shape. They are here rather than there for the
-- reason UnitFrames/Cast.lua is not in UI/: nothing else in the addon wants a
-- mail attachment square, and a widget with one caller is a widget that would
-- be shaped by that caller anyway.
--------------------------------------------------------------------------

-- A line you type in, with a ghost word in it while it is empty. Commits on
-- every keystroke rather than on enter, because everything downstream of it is
-- a readout: the band has to go red while you are still typing the name, not
-- after you have pressed something.
local function Field(parent, opts)
	local box = UI.Box(parent, C.sunken, C.edge)

	local ghost = UI.Label(box, M.font, C.quiet, "LEFT", UI.FLAT)
	ghost:SetPoint("LEFT", 4, 0)
	ghost:SetText(opts.ghost or "")
	UI.Wrap(ghost, false)

	local edit = CreateFrame("EditBox", nil, box)
	edit:SetPoint("TOPLEFT", 4, -2)
	edit:SetPoint("BOTTOMRIGHT", -4, 2)
	edit:SetFontObject(UI.Font(M.font, UI.FLAT))
	edit:SetTextColor(C.text[1], C.text[2], C.text[3])
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(opts.max or 64)
	if opts.multiline and type(edit.SetMultiLine) == "function" then
		edit:SetMultiLine(true)
		edit:SetPoint("TOPLEFT", 4, -3)
		ghost:ClearAllPoints()
		ghost:SetPoint("TOPLEFT", 4, -4)
	end
	if opts.numeric and type(edit.SetNumeric) == "function" then
		edit:SetNumeric(true)
		edit:SetJustifyH("RIGHT")
	end

	edit:SetScript("OnTextChanged", function(self)
		ghost:SetShown(self:GetText() == "")
		if syncing then
			return
		end
		opts.onType(self:GetText())
	end)
	edit:SetScript("OnEscapePressed", function(self)
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

	box.edit, box.ghost = edit, ghost
	return box
end

-- One attachment square. It takes a drop, it takes a click carrying something,
-- and a right click takes it back off. The same three gestures the gear slots
-- in UI/Widgets.lua answer, because a square you can put an item in should not
-- answer two different ways in two windows of one addon.
local function Slot(parent, at)
	local square = UI.Box(parent, C.sunken, C.edge)
	square:SetSize(SLOT, SLOT)

	local icon = UI.Icon(square, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", -2, 2)

	local count = UI.Label(square, M.small, C.text, "RIGHT", UI.FLAT)
	count:SetPoint("BOTTOMRIGHT", -3, 3)
	UI.Wrap(count, false)

	local button = CreateFrame("Button", nil, parent)
	button:SetAllPoints(square)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button.at = at

	square.icon, square.count, square.button = icon, count, button
	return square
end

-- One favourite, or one message. Both are a button with a coloured line of text
-- on it and a second dim line under, so they are made by the same call and
-- filled in differently.
local function Row(parent, height)
	local button = CreateFrame("Button", nil, parent)
	button:SetHeight(height)
	button.bg = ns.Fill(button, "BACKGROUND", C.rail[1], C.rail[2], C.rail[3], 1)
	button.bg:SetAllPoints()
	button.mark = ns.Fill(button, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
	button.mark:SetPoint("TOPLEFT")
	button.mark:SetPoint("BOTTOMLEFT")
	button.mark:SetWidth(2)
	button.mark:Hide()

	button.text = UI.Label(button, M.font, C.text, "LEFT", UI.FLAT)
	UI.Wrap(button.text, false)
	button.note = UI.Label(button, M.small, C.dim, "LEFT", UI.FLAT)
	UI.Wrap(button.note, false)
	return button
end

local function Shade(button, over)
	UI.Tint(button.bg, over and C.hover or (button.selected and C.selected or C.rail))
	button.mark:SetShown(button.selected and true or false)
end

-- Faded and deaf, which is what a disabled control is everywhere else in this
-- addon. Button:Disable is the client's own and does neither on a frame this
-- addon built, because the fontstring and the background are ours.
local function Enable(frame, enabled)
	frame:SetAlpha(enabled and 1 or 0.4)
	frame:EnableMouse(enabled and true or false)
end

--------------------------------------------------------------------------
-- What the window does when something changes
--------------------------------------------------------------------------

local function Disarm()
	armed = false
end

-- One field, put back in step with the draft. Never while it has the keyboard,
-- because a paint landing between two keystrokes would put the saved value back
-- under the cursor, and never when it already says the right thing, because a
-- SetText costs a measure whether or not the string changed.
local function Sync(box, text)
	if box.edit:HasFocus() or box.edit:GetText() == text then
		return false
	end
	syncing = true
	box.edit:SetText(text)
	syncing = false
	return true
end

-- Every field at once. A finished send empties the draft, and without this the
-- subject you typed is still sitting on the screen under a mail that has gone,
-- which is a field and a draft that disagree about what would be sent next.
local function PaintFields()
	local Draft = ns.MailDraft
	Sync(field.to, Draft.To())
	Sync(field.subject, Draft.Subject())
	Sync(field.body, Draft.Body())

	local gold, silver, copper = ns.Coins(Draft.Money())
	Sync(field.gold, gold > 0 and tostring(gold) or "")
	Sync(field.silver, silver > 0 and tostring(silver) or "")
	Sync(field.copper, copper > 0 and tostring(copper) or "")
end

local function Changed()
	Disarm()
	Window.Paint()
end

--------------------------------------------------------------------------
-- The favourites column
--------------------------------------------------------------------------

local function FavouriteTip(button)
	local name = button.name
	if not name then
		return {
			kind = "note",
			title = "add a favourite",
			lines = { "Puts whoever is in the name field on this list." },
		}
	end
	return {
		kind = "note",
		title = name,
		color = ns.MailWho.Color(ns.MailWho.Of(name)),
		lines = { ns.MailWho.Say(name) },
	}
end

local function RailRow(index)
	local button = Row(rail.stack.frame, M.railRow)
	button.text:SetPoint("LEFT", M.rowGap, 0)
	button.text:SetPoint("RIGHT", -M.rowGap, 0)
	button.note:Hide()
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	button:SetScript("OnClick", function(this, which)
		if not this.name then
			local ok, why = ns.MailWho.Add(ns.MailDraft.To())
			if not ok and why then
				ns.Print(why .. ".")
			end
		elseif which == "RightButton" then
			ns.MailWho.Remove(this.name)
		else
			ns.MailDraft.SetTo(this.name)
			field.to.edit:SetText(this.name)
		end
		Changed()
	end)
	button:SetScript("OnEnter", function(this)
		Shade(this, true)
		ns.Tip.Open(this, FavouriteTip(this))
	end)
	button:SetScript("OnLeave", function(this)
		Shade(this, false)
		ns.Tip.Close()
	end)
	UI.PassCamera(button)

	rail.pool[index] = button
	return button
end

local function PaintRail()
	local Who = ns.MailWho
	local to = ns.MailDraft.To()
	rail.stack.cells = {}

	for index = 1, Who.Count() + 1 do
		local button = rail.pool[index] or RailRow(index)
		local name = Who.At(index)
		button.name = name
		button.selected = name ~= nil and Who.Key(name) == Who.Key(to)
		if name then
			local color = Who.Color(Who.Of(name))
			button.text:SetText(name)
			button.text:SetTextColor(color[1], color[2], color[3])
		else
			button.text:SetText("+ add")
			button.text:SetTextColor(C.quiet[1], C.quiet[2], C.quiet[3])
		end
		button:Show()
		Shade(button, false)
		rail.stack:Add(button, { height = M.railRow, gap = 1 })
	end

	for index = Who.Count() + 2, #rail.pool do
		rail.pool[index]:Hide()
	end

	rail.stack:SetWidth(rail.view.width or 0)
	rail.view:Update(rail.stack:Reflow())
end

--------------------------------------------------------------------------
-- The attachment block
--------------------------------------------------------------------------

local function SlotTip(button)
	local entry = ns.MailDraft.At(button.at)
	if not entry then
		return {
			kind = "note",
			title = "an empty slot",
			lines = { "Right click a stack in your bags, or drag one onto the block." },
		}
	end
	return {
		kind = "item",
		link = entry.link,
		title = entry.name,
		count = entry.count,
		lines = {
			{ "count", tostring(entry.count) },
			{ "mail", tostring(math.floor((button.at - 1) / ns.MailDraft.PerMail()) + 1) },
		},
	}
end

-- What is on the cursor, onto the end of the list. Onto the end rather than
-- into the square you dropped on, because a list with a hole in it would be a
-- mail with an empty attachment slot in the middle of it, and the order of
-- twelve things going to one person is not a thing anybody arranges.
local function Drop()
	local kind, _, link = GetCursorInfo()
	if kind ~= "item" or type(link) ~= "string" then
		return false
	end
	local ok, why = ns.MailDraft.Attach(link)
	if ok then
		ClearCursor()
	elseif why then
		ns.Print(why .. ".")
	end
	Changed()
	return ok and true or false
end

local function GridSlot(index)
	local square = Slot(grid.canvas, index)
	local button = square.button

	button:SetScript("OnReceiveDrag", Drop)
	button:SetScript("OnClick", function(this, which)
		if which == "RightButton" then
			ns.MailDraft.Detach(this.at)
			Changed()
			return
		end
		Drop()
	end)
	button:SetScript("OnEnter", function(this)
		UI.Tint(square.bg, C.control)
		-- On the slot. An attachment is an item you are pointing at, and the
		-- corner is a long way from a row of twelve squares.
		ns.Tip.Open(this, SlotTip(this), nil, ns.UI.Tooltip.BESIDE)
	end)
	button:SetScript("OnLeave", function()
		UI.Tint(square.bg, C.sunken)
		ns.Tip.Close()
	end)
	UI.PassCamera(button)

	local line = math.floor((index - 1) / COLUMNS)
	local column = (index - 1) % COLUMNS
	square:SetPoint("TOPLEFT", grid.canvas, "TOPLEFT",
		column * (SLOT + SLOT_GAP), -(line * (SLOT + SLOT_GAP)))

	grid.pool[index] = square
	return square
end

-- One more square than there is something in, rounded up to a full line, so the
-- block is as big as what you are carrying rather than a wall of thirty six
-- empty boxes. Two lines minimum, because one line reads as a limit of six.
local function GridSize(held)
	local wanted = math.min(held + 1, ns.MailDraft.MAX)
	return math.max(2, math.ceil(wanted / COLUMNS))
end

local function PaintGrid()
	local Draft = ns.MailDraft
	local held = Draft.Held()
	local lines = GridSize(held)
	local shown = math.min(lines * COLUMNS, Draft.MAX)

	for index = 1, shown do
		local square = grid.pool[index] or GridSlot(index)
		local entry = Draft.At(index)
		square.icon:SetTexture(entry and entry.icon or nil)
		square.icon:SetShown(entry ~= nil)
		square.count:SetText((entry and entry.count > 1) and tostring(entry.count) or "")
		-- The line that would go on a second mail is drawn on the theme's own
		-- divider colour rather than the sunken one, so where the split falls is
		-- something you can see before you press send.
		ns.Recolor(square.edges, index > Draft.PerMail() and C.accent or C.edge)
		square:Show()
	end
	for index = shown + 1, #grid.pool do
		grid.pool[index]:Hide()
	end

	local extent = lines * SLOT + (lines - 1) * SLOT_GAP
	grid.canvas:SetHeight(math.max(extent, 1))
	grid.view:Update(extent)
	grid.count:SetText(("%d of %d"):format(held, Draft.MAX))
end

--------------------------------------------------------------------------
-- The band
--------------------------------------------------------------------------

-- What is riding on the letter, in words. Nil where nothing is, which is the
-- one case the band has nothing to warn about whoever it is going to.
local function Carrying()
	local Draft = ns.MailDraft
	local held, money = Draft.Held(), Draft.Money()
	if held == 0 and money == 0 then
		return nil
	end
	if held == 0 then
		return ns.Coin(money)
	end
	local items = ("%d %s"):format(held, held == 1 and "item" or "items")
	if money == 0 then
		return items
	end
	return items .. " and " .. ns.Coin(money)
end

local function BandWords(name, relation)
	local carrying = Carrying()
	if not ns.MailWho.Key(name) then
		return "nobody yet", "Pick a favourite on the left, or type a name."
	end
	if relation ~= ns.MailWho.STRANGER or not carrying then
		if not carrying then
			return name, ns.MailWho.Say(name)
		end
		return name, ("%s, carrying %s"):format(ns.MailWho.Say(name), carrying)
	end
	if armed then
		return name .. " is not one of yours",
			("Press send again and %s goes to them. They are on no list of yours."):format(carrying)
	end
	return name .. " is not one of yours",
		("%s would go to a name this addon has never seen. Add them on the left if you meant it."):format(carrying)
end

local function PaintBand()
	local Who = ns.MailWho
	local name = ns.MailDraft.To()
	local relation = Who.Of(name)
	local risky = ns.MailDraft.Risky()
	local color = Who.Key(name) and Who.Color(relation) or C.quiet

	local title, under = BandWords(name, relation)
	band.title:SetText(title)
	band.title:SetTextColor(color[1], color[2], color[3])
	band.note:SetText(under)

	-- The ground under it is the same colour at a tenth, which is a tint you can
	-- read a sentence on rather than a block of paint with words lost in it.
	band.bg:SetColorTexture(color[1], color[2], color[3], risky and 0.22 or 0.10)
	ns.Recolor(band.edges, color)
end

--------------------------------------------------------------------------
-- The footer
--------------------------------------------------------------------------

local function SendLabel()
	local Send = ns.MailSend
	if Send.Running() then
		local done, total = Send.Progress()
		return ("sending %d of %d"):format(done + 1, total)
	end
	if armed then
		return "yes, send it"
	end
	if ns.MailDraft.Risky() then
		return ns.db.mailWarn and "send anyway" or "send"
	end
	local mails = ns.MailDraft.Mails()
	return mails > 1 and ("send %d mails"):format(mails) or "send"
end

local function Press()
	local Draft, Send = ns.MailDraft, ns.MailSend
	if Send.Running() then
		return
	end
	if Draft.Risky() and ns.db.mailWarn and not armed then
		armed = true
		Window.Paint()
		return
	end
	armed = false

	local ok, why = Send.Start()
	if not ok and why then
		ns.Print(why .. ".")
	end
	Window.Paint()
end

local function PaintFoot()
	local Draft, Send = ns.MailDraft, ns.MailSend
	local why = Draft.Problem()
	local risky = Draft.Risky()

	foot.send.text:SetText(SendLabel())
	local shade = risky and C.danger or C.control
	foot.send.shade, foot.send.lit = shade, risky and C.dangerHover or C.hover
	UI.Tint(foot.send.bg, shade)
	Enable(foot.send, why == nil and not Send.Running())

	foot.stop:SetShown(Send.Running())
	foot.clear:SetShown(not Send.Running())

	if why then
		foot.note:SetText(why)
		foot.note:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
		return
	end
	foot.note:SetText(("%s, postage %s"):format(Draft.Describe(), ns.Coin(Draft.Cost())))
	foot.note:SetTextColor(C.quiet[1], C.quiet[2], C.quiet[3])
end

--------------------------------------------------------------------------
-- The inbox page
--------------------------------------------------------------------------

local waiting = { pool = {}, rows = {} }

local function LetterTip(button)
	local row = waiting.rows[button.at]
	if not row then
		return nil
	end
	local lines = {
		{ "from", row.sender },
		{ "expires", ("%d days"):format(math.floor(row.days)) },
	}
	if row.money > 0 then
		lines[#lines + 1] = { "money", ns.Coin(row.money) }
	end
	for index = 1, #row.attachments do
		local held = row.attachments[index]
		lines[#lines + 1] = { held.name, held.count > 1 and ("x%d"):format(held.count) or "1" }
	end

	local read = _G.GetInboxText
	if type(read) == "function" then
		local ok, text = pcall(read, row.index)
		if ok and type(text) == "string" and text ~= "" then
			lines[#lines + 1] = { blank = true }
			lines[#lines + 1] = { text }
		end
	end

	return {
		kind = "note",
		title = row.subject,
		color = ns.MailWho.Color(ns.MailWho.Of(row.sender)),
		lines = lines,
	}
end

local function LetterAct(at, what)
	local row = waiting.rows[at]
	if not row then
		return
	end
	if what == "delete" then
		ns.MailInbox.Delete(row.index)
	elseif what == "return" then
		ns.MailInbox.Return(row.index)
	else
		ns.MailInbox.Take(row.index)
	end
	-- On the spot rather than lingering: the letter the box was describing has
	-- just been deleted, returned or emptied, and a sentence about it is a
	-- sentence about a row that is not there any more.
	ns.Tip.Close(true)
	Window.Paint()
end

local function LetterButton(parent, glyph, what, at)
	local button = UI.Button(parent, { label = glyph, glyph = true,
		width = M.control, height = M.control,
		onClick = function(this) LetterAct(this.at, what) end })
	button.at = at
	return button
end

local function LetterRow(index)
	local button = Row(waiting.stack.frame, ROW)
	button.at = index

	button.icon = UI.Icon(button, "ARTWORK")
	button.icon:SetSize(ROW_ICON, ROW_ICON)
	button.icon:SetPoint("LEFT", M.gutter, 0)

	button.text:SetPoint("TOPLEFT", button.icon, "TOPRIGHT", M.gutter, -1)
	button.note:SetPoint("BOTTOMLEFT", button.icon, "BOTTOMRIGHT", M.gutter, 1)

	button.give = LetterButton(button, ">", "return", index)
	button.give:SetPoint("RIGHT", -(M.control + M.rowGap + M.gutter), 0)
	button.drop = LetterButton(button, "x", "delete", index)
	button.drop:SetPoint("RIGHT", -M.gutter, 0)

	button.text:SetPoint("RIGHT", button.give, "LEFT", -M.gutter, 0)
	button.note:SetPoint("RIGHT", button.give, "LEFT", -M.gutter, 0)

	button:SetScript("OnClick", function(this)
		local row = waiting.rows[this.at]
		if row and not ns.MailInbox.Payable(row) then
			ns.Print(("%s wants %s before it will open. Take it in the client's own window.")
				:format(row.subject, ns.Coin(row.cod)))
			return
		end
		LetterAct(this.at, "take")
	end)
	button:SetScript("OnEnter", function(this)
		Shade(this, true)
		ns.Tip.Open(this, LetterTip(this))
	end)
	button:SetScript("OnLeave", function(this)
		Shade(this, false)
		ns.Tip.Close()
	end)
	UI.PassCamera(button)

	waiting.pool[index] = button
	return button
end

local function LetterNote(row)
	local parts = {}
	if row.items > 0 then
		parts[#parts + 1] = ("%d %s"):format(row.items, row.items == 1 and "item" or "items")
	end
	if row.money > 0 then
		parts[#parts + 1] = ns.Coin(row.money)
	end
	if row.cod > 0 then
		parts[#parts + 1] = "COD " .. ns.Coin(row.cod)
	end
	parts[#parts + 1] = ("%dd"):format(math.floor(row.days))
	return table.concat(parts, "  ")
end

local function PaintWaiting()
	local Who = ns.MailWho
	waiting.rows = ns.MailInbox.Rows()
	waiting.stack.cells = {}

	for index = 1, #waiting.rows do
		local row = waiting.rows[index]
		local button = waiting.pool[index] or LetterRow(index)
		local color = Who.Color(Who.Of(row.sender))
		button.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Letter_15")
		button.text:SetText(row.sender ~= "" and row.sender or "the auction house")
		button.text:SetTextColor(color[1], color[2], color[3])
		button.note:SetText(row.subject .. "   " .. LetterNote(row))
		local tone = ns.MailInbox.Holds(row) and C.dim or C.quiet
		button.note:SetTextColor(tone[1], tone[2], tone[3])
		button:Show()
		Shade(button, false)
		waiting.stack:Add(button, { height = ROW, gap = 1 })
	end
	for index = #waiting.rows + 1, #waiting.pool do
		waiting.pool[index]:Hide()
	end

	waiting.stack:SetWidth(waiting.view.width or 0)
	waiting.view:Update(waiting.stack:Reflow())
	waiting.note:SetText(ns.MailInbox.Describe())
	waiting.sweep.text:SetText(ns.MailInbox.Sweeping() and "stop" or "take everything")
	waiting.blank:SetShown(#waiting.rows == 0)
end

--------------------------------------------------------------------------
-- Painting the lot
--------------------------------------------------------------------------

-- Only the page you are looking at, and the count on the other tab.
--
-- The inbox half is the reason for the branch rather than tidiness. Rebuilding
-- it walks every message and asks the client for every attachment on each, which
-- is one call plus twelve per message; Paint runs on every keystroke in the
-- recipient field, so painting both pages would be six hundred API calls per
-- letter typed on a mailbox holding fifty. The count on the tab is one call and
-- is worth having either way.
function Window.Paint()
	if not window then
		return false
	end

	PaintFields()
	if tabs.selected == 2 then
		PaintWaiting()
	else
		PaintRail()
		PaintGrid()
		PaintBand()
	end
	PaintFoot()

	local waitingCount = ns.MailInbox.Count()
	tabs:SetLabel(2, waitingCount > 0 and ("Inbox (%d)"):format(waitingCount) or "Inbox")
	tabs:SetUnread(2, waitingCount > 0)
	return true
end

--------------------------------------------------------------------------
-- Building it
--------------------------------------------------------------------------

local function Money()
	local gold = tonumber(field.gold.edit:GetText()) or 0
	local silver = tonumber(field.silver.edit:GetText()) or 0
	local copper = tonumber(field.copper.edit:GetText()) or 0
	ns.MailDraft.SetMoney(gold * ns.GOLD + silver * ns.SILVER + copper)
	Changed()
end

local function BuildTarget(parent, width)
	field.to = Field(parent, { ghost = "who it goes to", max = 32,
		onType = function(text)
			ns.MailDraft.SetTo(text)
			Changed()
		end })
	field.to:SetSize(width, FIELD)
	field.to:SetPoint("TOPLEFT")

	local caption = UI.Label(parent, M.small, C.quiet, "LEFT", UI.FLAT)
	caption:SetPoint("TOPLEFT", field.to, "BOTTOMLEFT", 0, -M.gutter)
	caption:SetText("money on the mail")
	UI.Wrap(caption, false)

	local names = { "gold", "silver", "copper" }
	local marks = { "g", "s", "c" }
	for index = 1, 3 do
		local box = Field(parent, { ghost = marks[index], max = 6, numeric = true,
			onType = Money })
		box:SetSize(COIN, FIELD)
		box:SetPoint("TOPLEFT", caption, "BOTTOMLEFT",
			(index - 1) * (COIN + M.gutter + 10), -M.rowGap)

		local mark = UI.Label(parent, M.small, C.dim, "LEFT", UI.FLAT)
		mark:SetPoint("LEFT", box, "RIGHT", 3, 0)
		mark:SetText(marks[index])
		UI.Wrap(mark, false)
		field[names[index]] = box
	end
	return field.gold
end

local function BuildGrid(parent, width)
	local caption = UI.Label(parent, M.small, C.quiet, "LEFT", UI.FLAT)
	caption:SetPoint("TOPLEFT")
	caption:SetText("attachments")
	UI.Wrap(caption, false)

	grid = { pool = {} }
	grid.count = UI.Label(parent, M.small, C.dim, "RIGHT", UI.FLAT)
	grid.count:SetPoint("TOPRIGHT")
	UI.Wrap(grid.count, false)

	grid.view = UI.ScrollView(parent, { overlay = true })
	grid.view.frame:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -M.rowGap)
	grid.view:Resize(width, GRID_H)
	grid.canvas = grid.view.canvas
	return grid.view.frame
end

local function BuildBand(parent)
	band = UI.Box(parent, C.window, C.edge)
	band:SetHeight(BAND)
	band:SetPoint("BOTTOMLEFT")
	band:SetPoint("BOTTOMRIGHT")

	band.title = UI.Label(band, M.heading, C.text, "LEFT", UI.FLAT)
	band.title:SetPoint("TOPLEFT", M.gutter, -M.rowGap - 1)
	band.title:SetPoint("RIGHT", -M.gutter, 0)
	UI.Wrap(band.title, false)

	band.note = UI.Label(band, M.font, C.text, "LEFT", UI.FLAT)
	band.note:SetPoint("TOPLEFT", band.title, "BOTTOMLEFT", 0, -3)
	band.note:SetPoint("RIGHT", band, "RIGHT", -M.gutter, 0)
	UI.Wrap(band.note, false)
	return band
end

-- `tall` is how much of the window the tab strip left, and it has to be handed
-- down rather than measured: a scroll view is sized in the call that makes it,
-- and the frames these hang on take their height from anchors the client has
-- not resolved yet at build time.
local function BuildSend(parent, tall)
	local body = CreateFrame("Frame", nil, parent)
	body:SetAllPoints()

	rail = { pool = {} }
	rail.frame = CreateFrame("Frame", "WarriorKitMailFavourites", body)
	rail.frame:SetPoint("TOPLEFT")
	rail.frame:SetPoint("BOTTOMLEFT")
	rail.frame:SetWidth(RAIL)
	ns.Fill(rail.frame, "BACKGROUND", C.rail[1], C.rail[2], C.rail[3], 1):SetAllPoints()
	rail.view = UI.ScrollView(rail.frame, { overlay = true })
	rail.view.frame:SetPoint("TOPLEFT", M.rowGap, -M.rowGap)
	rail.view:Resize(RAIL - M.rowGap * 2, tall - M.rowGap * 2)
	rail.stack = UI.Stack(rail.view.canvas)

	local right = CreateFrame("Frame", nil, body)
	right:SetPoint("TOPLEFT", rail.frame, "TOPRIGHT", M.pad, 0)
	right:SetPoint("BOTTOMRIGHT", -M.pad, 0)

	-- The compose column, which is the window less the favourites column and the
	-- pad either side of it. Every width below is carved out of this one, so if
	-- it is wrong everything on the page is wrong by the same amount.
	local width = WIDTH - RAIL - M.pad * 2
	local target = CreateFrame("Frame", nil, right)
	target:SetPoint("TOPLEFT")
	target:SetSize(width - GRID_W - M.gutter, GRID_H + CAPTION)
	BuildTarget(target, width - GRID_W - M.gutter)

	local block = CreateFrame("Frame", nil, right)
	block:SetPoint("TOPRIGHT")
	block:SetSize(GRID_W, GRID_H + CAPTION)
	BuildGrid(block, GRID_W)

	field.subject = Field(right, { ghost = "subject, or leave it and the addon writes one",
		max = 64,
		onType = function(text)
			ns.MailDraft.SetSubject(text)
			Changed()
		end })
	field.subject:SetHeight(FIELD)
	field.subject:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, -M.gutter)
	field.subject:SetPoint("RIGHT", right, "RIGHT")

	BuildBand(right)

	field.body = Field(right, { ghost = "anything you want to say", multiline = true,
		max = ns.MailDraft.BodyMax(),
		onType = function(text)
			ns.MailDraft.SetBody(text)
			Changed()
		end })
	field.body:SetPoint("TOPLEFT", field.subject, "BOTTOMLEFT", 0, -M.rowGap)
	field.body:SetPoint("RIGHT", right, "RIGHT")
	field.body:SetPoint("BOTTOM", band, "TOP", 0, M.rowGap)

	-- The order the tab key walks, which is the order somebody filling this in
	-- reads it. The body is last and takes the key itself, because a multi line
	-- field is where you would want a tab character and does not get one.
	field.to.edit:SetScript("OnTabPressed", function()
		field.subject.edit:SetFocus()
	end)
	field.subject.edit:SetScript("OnTabPressed", function()
		field.body.edit:SetFocus()
	end)

	-- What the page is made of, recorded on it the way Comfort/Destroy.lua
	-- records its card. Nothing in the addon reads it; the harness measures the
	-- three columns through it rather than through a hook cut in for its
	-- benefit, because three columns that do not add up to the window is a page
	-- that draws over itself and every other assertion here would still pass.
	body.parts = { rail = rail.frame, target = target, block = block,
		band = band, to = field.to, subject = field.subject,
		grid = grid.view.frame }
	return body
end

local function BuildWaiting(parent, tall)
	local body = CreateFrame("Frame", nil, parent)
	body:SetAllPoints()

	-- One button with two jobs, and the second one is not a nicety. A sweep is a
	-- chain of takes and each link is the server answering the one before it, so
	-- a server that answers nothing leaves the sweep waiting with no way to
	-- start another. Mail/Send.lua has the same shape and the same answer: a
	-- stop where the go was, rather than a timeout this addon would then have to
	-- defend forever.
	waiting.sweep = UI.Button(body, { label = "take everything", width = 130, height = M.row,
		onClick = function()
			local Inbox = ns.MailInbox
			if Inbox.Sweeping() then
				Inbox.Stop()
				ns.Print(Inbox.Describe() .. ".")
			else
				local ok, why = Inbox.Sweep()
				if not ok and why then
					ns.Print(why .. ".")
				end
			end
			Window.Paint()
		end })
	local sweep = waiting.sweep
	sweep:SetPoint("TOPLEFT", M.pad, -M.rowGap)

	waiting.note = UI.Label(body, M.font, C.dim, "RIGHT", UI.FLAT)
	waiting.note:SetPoint("RIGHT", body, "RIGHT", -M.pad, 0)
	waiting.note:SetPoint("TOP", sweep, "TOP", 0, -3)
	waiting.note:SetPoint("LEFT", sweep, "RIGHT", M.gutter, 0)
	UI.Wrap(waiting.note, false)

	local rule = UI.Rule(body, C.hairline)
	rule:SetPoint("TOPLEFT", M.pad, -(M.rowGap + M.row + M.rowGap))
	rule:SetPoint("TOPRIGHT", -M.pad, -(M.rowGap + M.row + M.rowGap))

	local above = M.rowGap + M.row + M.rowGap + M.hairline + M.rowGap
	waiting.view = UI.ScrollView(body)
	waiting.view.frame:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -M.rowGap)
	waiting.view:Resize(WIDTH - M.pad * 2, tall - above)
	waiting.stack = UI.Stack(waiting.view.canvas)

	waiting.blank = UI.Label(body, M.font, C.quiet, "CENTER", UI.FLAT)
	waiting.blank:SetPoint("CENTER")
	waiting.blank:SetText("nothing is waiting for you")
	UI.Wrap(waiting.blank, false)
	return body
end

local function BuildFoot()
	foot = {}

	-- **The send is at the right end of the row, and that is a fix rather than a
	-- taste.** It was at the left, which put it under the favourites column and
	-- outside the compose column entirely: every part of the letter you touch
	-- with a mouse is to the right of that rail, and the attachment block, the
	-- one thing here you cannot do from the keyboard, is at the far top right.
	-- The button pressed at the end of every letter was the longest reach on
	-- the page, corner to opposite corner, and it was that on every letter.
	--
	-- Here it sits under the right edge of the band, which is the line you read
	-- immediately before pressing it, and under the attachment block above that.
	-- The reason a send is refused goes where the send used to be, so the row
	-- reads left to right the way the page does: what is wrong, undo, go.
	foot.send = UI.Button(window.footer, { label = "send", width = 118, height = M.row,
		onClick = Press })
	foot.send:SetPoint("RIGHT")
	foot.send:SetScript("OnEnter", function(this)
		UI.Tint(this.bg, this.lit or C.hover)
	end)
	foot.send:SetScript("OnLeave", function(this)
		UI.Tint(this.bg, this.shade or C.control)
	end)

	foot.stop = UI.Button(window.footer, { label = "stop", width = 70, height = M.row,
		onClick = function()
			ns.MailSend.Stop()
			ns.MailInbox.Stop()
			Window.Paint()
		end })
	foot.stop:SetPoint("RIGHT", foot.send, "LEFT", -M.rowGap, 0)
	foot.stop:Hide()

	-- Empties the draft and nothing else. The fields follow on the repaint,
	-- because putting each of them back by hand here is the second place that
	-- would have to know what a draft is made of.
	foot.clear = UI.Button(window.footer, { label = "clear", width = 70, height = M.row,
		onClick = function()
			ns.MailDraft.Clear()
			Changed()
		end })
	foot.clear:SetPoint("RIGHT", foot.send, "LEFT", -M.rowGap, 0)

	foot.note = UI.Label(window.footer, M.small, C.quiet, "LEFT", UI.FLAT)
	foot.note:SetPoint("LEFT")
	foot.note:SetPoint("RIGHT", foot.clear, "LEFT", -M.gutter, 0)
	foot.note:SetPoint("TOP", foot.send, "TOP", 0, -4)
	UI.Wrap(foot.note, false)
end

local function Build()
	window = UI.Window({
		name = "WarriorKitMail",
		title = "Mail",
		width = WIDTH,
		height = HEIGHT,
		zoom = function() return ns.Zoom("mailZoom") end,
	})
	ns.Remember(window)

	tabs = UI.TabStrip(window.content, { onSelect = function(index)
		page[1]:SetShown(index == 1)
		page[2]:SetShown(index == 2)
		Window.Paint()
	end })
	tabs.frame:SetPoint("TOPLEFT", M.pad, 0)
	tabs.frame:SetPoint("TOPRIGHT", -M.pad, 0)
	tabs:Add("Send")
	tabs:Add("Inbox")
	local strip = tabs:Resize(WIDTH - M.pad * 2)

	local body = CreateFrame("Frame", nil, window.content)
	body:SetPoint("TOPLEFT", 0, -strip)
	body:SetPoint("BOTTOMRIGHT")

	local tall = window:Body(HEIGHT) - strip
	body:SetSize(WIDTH, tall)
	page[1] = BuildSend(body, tall)
	page[2] = BuildWaiting(body, tall)
	BuildFoot()
	tabs:Select(1)

	-- Closing our window is walking away from the mailbox, which is what the
	-- client would have done with its own. Hung off the frame rather than off
	-- the close box, because escape reaches the frame through UISpecialFrames
	-- and knows nothing about a button, and a mailbox left open with nothing on
	-- screen driving it is the one state this window must not be able to leave
	-- behind. HookScript rather than SetScript: UI/Window.lua already has a
	-- handler there and it is the one that shuts an open dropdown.
	if type(window.frame.HookScript) == "function" then
		window.frame:HookScript("OnHide", function()
			ns.MailBlizzard.Apply()
			ns.MailBags.Apply()
			if atMailbox and type(_G.CloseMail) == "function" then
				pcall(_G.CloseMail)
			end
		end)
	end

	return window
end

--------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------

function Window.Built()
	return window ~= nil
end

function Window.Shown()
	return window ~= nil and window.frame:IsShown()
end

function Window.Show()
	if not window then
		Build()
	end
	window:Show()
	Disarm()
	ns.MailBlizzard.Apply()
	ns.MailBags.Apply()
	Window.Paint()
	return true
end

-- Everything the close needs is on the frame's own OnHide, so every route out
-- of the window goes through one place: this call, the close box, escape, and
-- the client saying the mailbox shut.
function Window.Hide()
	if not window or not window.frame:IsShown() then
		return false
	end
	window:Hide()
	return true
end

-- The draft changed from somewhere that is not this window. Mail/Bags.lua's
-- right click is the only caller, and it goes through the same two steps every
-- field in here goes through: a stack that arrived out of the bags is the same
-- kind of change as one dropped on the block, and it has to disarm the send for
-- the same reason.
function Window.Changed()
	if not window then
		return false
	end
	Changed()
	return true
end

function Window.Toggle()
	if Window.Shown() then
		return Window.Hide()
	end
	return Window.Show()
end

-- How wide one row of the favourites column came out. Handed out for the reason
-- Chat/Window.lua hands out its rail's: a column whose rows are two pixels wide
-- draws nothing, clicks nowhere and answers every other question correctly.
function Window.Rail()
	return rail and rail.stack.width or 0
end

function Window.Favourites()
	return rail and #rail.pool or 0
end

function Window.Letters()
	return #waiting.rows
end

-- The frames the send page is laid out from, and the two numbers a square of
-- the attachment block is drawn at. Handed out for the reason Window.Rail is:
-- the arithmetic is the half that can be wrong, and a block one pixel narrower
-- than six squares draws five of them.
function Window.Parts()
	return page[1] and page[1].parts or nil
end

function Window.Block()
	return SLOT, SLOT_GAP, COLUMNS
end

-- Which page is up, and a way to ask for the other one. The harness drives the
-- strip through this rather than through its own buttons, for the reason
-- Comfort/Destroy.lua hands out its card: reaching into a widget's pool from
-- outside is a test asserting the widget library rather than this window.
function Window.Tab(index)
	if index and tabs then
		tabs:Select(index)
	end
	return tabs and tabs.selected or 0
end

function Window.Page(index)
	return page[index] and page[index]:IsShown() or false
end

-- The send button, pressed.
--
-- Handed out because the warning is the whole point of the window and it lives
-- between two presses of one button. A test that called ns.MailSend.Start would
-- be testing the send and never the gate in front of it, which is the half that
-- stands between four hundred gold and a name you mistyped.
function Window.Press()
	Press()
	return armed
end

-- What the band is saying right now, which is the other half of that warning.
-- The colour is the thing you see and the sentence is the thing a screenshot
-- carries, so both are readable from here.
function Window.Band()
	if not band then
		return nil
	end
	return band.title:GetText(), band.note:GetText()
end

function Window.Describe()
	if not window then
		return "not built yet"
	end
	return Window.Shown() and "open" or "closed"
end

--------------------------------------------------------------------------

-- The mailbox itself. MAIL_SHOW is standing at one, MAIL_CLOSED is walking
-- away, and both are the client's word rather than ours: there is no state in
-- which this window is useful away from a mailbox, because every call under it
-- would be refused.
local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_SHOW")
events:RegisterEvent("MAIL_CLOSED")
events:RegisterEvent("MAIL_INBOX_UPDATE")
events:RegisterEvent("MAIL_SEND_SUCCESS")
events:RegisterEvent("MAIL_FAILED")
events:SetScript("OnEvent", function(_, event)
	if event == "MAIL_SHOW" then
		atMailbox = true
		if ns.db.mail then
			Window.Show()
		end
		return
	end
	if event == "MAIL_CLOSED" then
		atMailbox = false
		Window.Hide()
		-- The letter goes with the mailbox. The client has already handed its
		-- attachments back to your bags by the time this fires, so a draft that
		-- survives is what the window reopens on: a list of things it is not
		-- carrying, over a name and a body you have finished with. Emptied on
		-- the way down rather than on the way up, because the client's word is
		-- what ends the letter and Window.Show is reached by a toggle as well.
		ns.MailDraft.Reset()
		return
	end
	-- Everything else is the server saying something moved, and the window is
	-- the thing that has to agree with it. Guarded on being open, because these
	-- three fire at a mailbox whether or not this part is switched on.
	if Window.Shown() then
		Disarm()
		Window.Paint()
	end
end)
