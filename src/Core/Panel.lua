local ADDON, ns = ...

local Options = {}
ns.Options = Options

-- The panel window and the widget kit. It builds no section of its own: at
-- PLAYER_LOGIN it walks the registry, gives each feature a page and a tab, and
-- hands it the kit so the feature draws its own rows. Adding a part to the
-- addon adds a tab here without this file changing.
--
-- One page per feature rather than one column of every setting. The column was
-- past 700 pixels on six parts and the window had to scale itself down to fit
-- a screen, which shrank the text to buy room for settings nobody was looking
-- at. A page is as tall as its own feature and no taller.
--
-- Built out of CreateFrame and coloured textures on purpose. Every Blizzard
-- widget template is one more thing that has to exist in 2.5.6, and the only
-- ones this file leans on are the font objects, which the rest of the addon
-- already uses.

local RAIL_W = 122
local PAGE_W = 364
local PANEL_W = RAIL_W + PAGE_W
local TITLE_H = 24
local FOOTER_H = 34
local PAD = 14
local INDENT = 12
local ROW = 22
local TAB_H = 24
local LINE_H = 12
local MENU_ROW = 20
local MENU_W = 200

local panel, widgets = nil, {}
local pages, tabs, active = {}, {}, 1
local divider, footerRule
local content = 0 -- the height of the page area, which every page is sized to
local capturing   -- the key field currently listening, at most one
local menu        -- the open picker list, at most one
local page        -- the page being built, and what the kit adds a row to

--------------------------------------------------------------------------
-- Pieces
--------------------------------------------------------------------------

-- A coloured rectangle and a one pixel outline. Both live in Core, because the
-- enemy bars draw themselves out of the same two pieces.
local Fill, Outline = ns.Fill, ns.Outline

local function Box(parent, w, h)
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(w, h)
	local bg = Fill(box, "BACKGROUND", 0.08, 0.08, 0.10, 0.95)
	bg:SetAllPoints()
	Outline(box, 0.30, 0.30, 0.34, 1)
	return box
end

local function PushButton(parent, label, w, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(w, 20)
	button.bg = Fill(button, "BACKGROUND", 0.17, 0.17, 0.20, 1)
	button.bg:SetAllPoints()
	Outline(button, 0.34, 0.34, 0.40, 1)
	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.text:SetPoint("CENTER")
	button.text:SetText(label)
	button:SetScript("OnEnter", function(self)
		self.bg:SetColorTexture(0.26, 0.26, 0.32, 1)
	end)
	button:SetScript("OnLeave", function(self)
		self.bg:SetColorTexture(0.17, 0.17, 0.20, 1)
	end)
	button:SetScript("OnClick", onClick)
	return button
end

--------------------------------------------------------------------------
-- The page area
--
-- Every page is sized to the tallest one, so switching tabs does not resize
-- the window under the mouse. It only ever grows: a note that wraps onto a
-- third line pushes the window out once and leaves it there, rather than
-- breathing in and out as the text under it changes.
--------------------------------------------------------------------------

local function SetContent(height)
	content = height

	for _, frame in ipairs(pages) do
		frame:SetHeight(content)
	end
	if divider then
		divider:SetHeight(content)
	end
	if footerRule then
		footerRule:ClearAllPoints()
		footerRule:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -TITLE_H - content)
	end

	panel:SetHeight(TITLE_H + content + FOOTER_H)
	-- Scale is recomputed from 1 rather than adjusted, so a page that grows
	-- twice does not shrink the window twice for the same overflow.
	panel:SetScale(1)
	if panel:GetHeight() > UIParent:GetHeight() - 40 then
		-- Small screen or a big UI scale. Better squashed than off the edge.
		panel:SetScale((UIParent:GetHeight() - 40) / panel:GetHeight())
	end
end

--------------------------------------------------------------------------
-- Rows
--
-- A page is a list of rows laid out top down, not a running cursor. The cursor
-- came first and it could not survive a note: a note is as tall as its text
-- wraps, its text changes while the panel is open, and a row whose height is
-- decided before its text is drawn on top of by the row under it.
--
-- Every row also registers a refresh function, so one Refresh call after any
-- change puts the whole panel back in step with the database, no matter
-- whether the change came from a click or from a slash command. Rows on a
-- hidden page refresh too: they cost nothing, and it means opening a tab never
-- shows a stale value.
--------------------------------------------------------------------------

local function Layout(target)
	local y = -PAD
	for _, row in ipairs(target.rows) do
		if row.frame then
			row.frame:ClearAllPoints()
			row.frame:SetPoint("TOPLEFT", target, "TOPLEFT", PAD + row.indent, y)
		end
		y = y - row.height
	end
	target.height = -y + PAD
	return target.height
end

-- Lay the page out again, and push the window out if the page no longer fits.
local function Refit(target)
	if Layout(target) > content then
		SetContent(target.height)
	end
end

local function Place(frame, height, indent)
	local row = { frame = frame, height = height or ROW, indent = indent or 0 }
	page.rows[#page.rows + 1] = row
	return row
end

local function Register(frame, refresh)
	frame.Refresh = refresh
	widgets[#widgets + 1] = frame
	if refresh then
		refresh()
	end
	return frame
end

local function StopCapture(field)
	if not field then
		return
	end
	capturing = nil
	field:EnableKeyboard(false)
	if field.SetPropagateKeyboardInput then
		field:SetPropagateKeyboardInput(true)
	end
	Options.Refresh()
end

local function CloseMenu()
	if menu then
		menu.owner = nil
		menu:Hide()
	end
end

--------------------------------------------------------------------------
-- The picker list
--
-- One popup, reused by every picker row, with a pool of rows inside it. The
-- options are asked for when the list opens rather than held, because what a
-- picker offers is usually something that changes while the panel is open, the
-- way the weapons in your bags do.
--------------------------------------------------------------------------

local function MenuFrame()
	if menu then
		return menu
	end
	menu = CreateFrame("Frame", nil, panel)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	local bg = Fill(menu, "BACKGROUND", 0.06, 0.06, 0.08, 0.98)
	bg:SetAllPoints()
	Outline(menu, 0.40, 0.40, 0.48, 1)
	menu.rows = {}
	menu:Hide()
	return menu
end

local function MenuRow(index)
	local list = MenuFrame()
	if list.rows[index] then
		return list.rows[index]
	end

	local row = CreateFrame("Button", nil, list)
	row:SetHeight(MENU_ROW)
	row.bg = Fill(row, "BACKGROUND", 0.20, 0.20, 0.26, 1)
	row.bg:SetAllPoints()

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(MENU_ROW - 6, MENU_ROW - 6)
	row.icon:SetPoint("LEFT", 4, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", -6, 0)
	row.text:SetJustifyH("LEFT")
	if row.text.SetWordWrap then
		row.text:SetWordWrap(false)
	end

	row:SetScript("OnEnter", function(self)
		self.bg:SetAlpha(1)
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:SetAlpha(0)
	end)

	list.rows[index] = row
	return row
end

local function OpenMenu(owner, options, onPick)
	local list = MenuFrame()
	local width = math.max(owner:GetWidth(), MENU_W)
	local height = 3

	for index, option in ipairs(options) do
		local row = MenuRow(index)
		row:SetWidth(width - 2)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -height)
		row.text:SetText(option.text or option.value)
		if option.icon then
			row.icon:SetTexture(option.icon)
			row.icon:Show()
		else
			row.icon:Hide()
		end
		row.bg:SetAlpha(0)
		row:SetScript("OnClick", function()
			CloseMenu()
			onPick(option.value)
			Options.Refresh()
		end)
		row:Show()
		height = height + MENU_ROW
	end

	for index = #options + 1, #list.rows do
		list.rows[index]:Hide()
	end

	list:SetSize(width, height + 3)
	list:ClearAllPoints()
	-- Under the button, unless the button sits low enough on the screen that
	-- the list would hang off the bottom of it.
	local room = owner:GetBottom()
	if room and room < height + 20 then
		list:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 2)
	else
		list:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
	end
	list.owner = owner
	list:Show()
end

--------------------------------------------------------------------------
-- The kit
--
-- Handed to every feature's panel builder. Nothing in here knows what a charge
-- or a nameplate is.
--------------------------------------------------------------------------

local ui = {}

local function RowWidth()
	return PAGE_W - PAD * 2 - INDENT
end

function ui.Header(text)
	local block = CreateFrame("Frame", nil, page)
	block:SetSize(PAGE_W - PAD * 2, 28)
	Place(block, 28, 0)

	local line = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	line:SetPoint("TOPLEFT", 0, -6)
	line:SetText(text)

	local rule = Fill(block, "ARTWORK", 0.30, 0.30, 0.34, 1)
	rule:SetPoint("BOTTOMLEFT")
	rule:SetSize(PAGE_W - PAD * 2, 1)
	return block
end

-- Height comes off the text, because a note is the one row that does not know
-- how tall it is until it has been written. Measuring on every refresh rather
-- than once is what makes a note whose wording changes with the state safe to
-- put above another row.
function ui.Note(getText)
	local line = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	line:SetWidth(PAGE_W - PAD * 2 - INDENT)
	line:SetJustifyH("LEFT")
	line:SetSpacing(2)

	local row = Place(line, LINE_H + 6, INDENT)
	local owner = page

	return Register(line, function()
		line:SetText(getText() or "")
		local height = math.max(line:GetStringHeight() or 0, LINE_H) + 6
		if math.abs(height - row.height) > 0.5 then
			row.height = height
			Refit(owner)
		end
	end)
end

function ui.Check(label, get, set)
	local button = CreateFrame("Button", nil, page)
	button:SetSize(RowWidth(), 16)
	Place(button, ROW, INDENT)

	local box = Box(button, 14, 14)
	box:SetPoint("LEFT")
	button.tick = Fill(box, "ARTWORK", 0.30, 0.85, 0.35, 1)
	button.tick:SetPoint("TOPLEFT", 3, -3)
	button.tick:SetPoint("BOTTOMRIGHT", -3, 3)

	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.text:SetPoint("LEFT", box, "RIGHT", 6, 0)
	button.text:SetText(label)

	button:SetScript("OnClick", function()
		set(not get())
		Options.Refresh()
	end)

	return Register(button, function()
		button.tick:SetShown(get() and true or false)
		local enabled = button.IsAvailable == nil or button:IsAvailable()
		button:SetAlpha(enabled and 1 or 0.4)
		button:EnableMouse(enabled)
	end)
end

function ui.Stepper(label, low, high, step, get, set)
	local row = CreateFrame("Frame", nil, page)
	row:SetSize(RowWidth(), 18)
	Place(row, ROW, INDENT)

	local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT")
	text:SetText(label)

	local value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	value:SetPoint("RIGHT", row, "RIGHT", -56, 0)

	local function nudge(delta)
		local current = get() + delta * step
		if current < low then
			current = low
		elseif current > high then
			current = high
		end
		set(current)
		Options.Refresh()
	end

	local minus = PushButton(row, "-", 22, function() nudge(-1) end)
	minus:SetPoint("RIGHT", row, "RIGHT", -26, 0)
	local plus = PushButton(row, "+", 22, function() nudge(1) end)
	plus:SetPoint("RIGHT", row, "RIGHT", 0, 0)

	return Register(row, function()
		value:SetText(tostring(get()))
	end)
end

function ui.Cycle(label, values, get, set)
	local row = CreateFrame("Frame", nil, page)
	row:SetSize(RowWidth(), 20)
	Place(row, ROW + 2, INDENT)

	local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT")
	text:SetText(label)

	local button = PushButton(row, "", 96, function()
		local current = get()
		for index, candidate in ipairs(values) do
			if candidate == current then
				set(values[index % #values + 1])
				Options.Refresh()
				return
			end
		end
		set(values[1])
		Options.Refresh()
	end)
	button:SetPoint("RIGHT")

	return Register(row, function()
		button.text:SetText(get())
	end)
end

-- A value chosen off a list. getOptions returns an array of
-- { value, text, icon } and is asked both when the list opens and on every
-- refresh, so the caller is free to build it out of something live. The row
-- shows whichever option carries the current value, so a caller holding a
-- value it cannot offer, a weapon sitting in the bank, has to put that entry in
-- the list itself and say on the row what is odd about it.
function ui.Picker(label, get, set, getOptions)
	local row = CreateFrame("Frame", nil, page)
	row:SetSize(RowWidth(), 22)
	Place(row, ROW + 4, INDENT)

	local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT")
	text:SetText(label)

	local button = CreateFrame("Button", nil, row)
	button:SetSize(MENU_W, 20)
	button:SetPoint("RIGHT")
	button.bg = Fill(button, "BACKGROUND", 0.08, 0.08, 0.10, 0.95)
	button.bg:SetAllPoints()
	Outline(button, 0.30, 0.30, 0.34, 1)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	icon:SetPoint("LEFT", 3, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	local arrow = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	arrow:SetPoint("RIGHT", -5, 0)
	arrow:SetText("v")

	local value = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	value:SetPoint("LEFT", icon, "RIGHT", 5, 0)
	value:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
	value:SetJustifyH("LEFT")
	if value.SetWordWrap then
		value:SetWordWrap(false)
	end

	button:SetScript("OnEnter", function(self)
		self.bg:SetColorTexture(0.16, 0.16, 0.20, 1)
	end)
	button:SetScript("OnLeave", function(self)
		self.bg:SetColorTexture(0.08, 0.08, 0.10, 0.95)
	end)
	button:SetScript("OnClick", function(self)
		StopCapture(capturing)
		if menu and menu:IsShown() and menu.owner == self then
			CloseMenu()
			return
		end
		OpenMenu(self, getOptions(), set)
	end)
	button:SetScript("OnHide", function(self)
		if menu and menu.owner == self then
			CloseMenu()
		end
	end)

	return Register(row, function()
		local current = get()
		local shown, texture = current, nil
		for _, option in ipairs(getOptions()) do
			if option.value == current then
				shown = option.text or option.value
				texture = option.icon
				break
			end
		end
		value:SetText(shown or "")
		icon:SetTexture(texture)
		icon:SetShown(texture and true or false)
	end)
end

-- A full width action button. label is a function so it can say what pressing
-- it will do right now, and available gates the click the way Check does.
function ui.Action(getLabel, onClick, isAvailable)
	local button = PushButton(page, "", RowWidth(), onClick)
	Place(button, ROW + 4, INDENT)
	return Register(button, function()
		button.text:SetText(getLabel())
		local enabled = isAvailable == nil or isAvailable()
		button:SetAlpha(enabled and 1 or 0.4)
		button:EnableMouse(enabled)
	end)
end

-- Two buttons side by side, for a do-it and an undo-it that belong together.
function ui.ActionPair(leftLabel, leftClick, leftOk, rightLabel, rightClick, rightOk)
	local row = CreateFrame("Frame", nil, page)
	local width = (RowWidth() - 6) / 2
	row:SetSize(RowWidth(), 20)
	Place(row, ROW + 4, INDENT)

	local left = PushButton(row, "", width, leftClick)
	left:SetPoint("LEFT")
	local right = PushButton(row, "", width, rightClick)
	right:SetPoint("RIGHT")

	return Register(row, function()
		left.text:SetText(leftLabel())
		right.text:SetText(rightLabel())
		local leftEnabled = leftOk == nil or leftOk()
		local rightEnabled = rightOk == nil or rightOk()
		left:SetAlpha(leftEnabled and 1 or 0.4)
		left:EnableMouse(leftEnabled)
		right:SetAlpha(rightEnabled and 1 or 0.4)
		right:EnableMouse(rightEnabled)
	end)
end

function ui.Gap(height)
	Place(nil, height or 8, 0)
end

--------------------------------------------------------------------------
-- The key field
--
-- Click it, press the key you want. Modifiers come off IsShiftKeyDown and
-- friends rather than off the key event, because a modifier press arrives as
-- its own key and has to be ignored.
--
-- It is generic on purpose: it captures a key and hands it back. What that key
-- then binds to is the calling feature's business.
--------------------------------------------------------------------------

local MODIFIER_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
}

-- Left and right are here so a modified click can be captured, which is the
-- whole point of the marking keys. An unmodified one still cancels, because
-- clicking away from a field you opened by accident has to stay possible and
-- because a bare BUTTON1 binding would eat targeting anyway.
local MOUSE_KEYS = {
	LeftButton = "BUTTON1", RightButton = "BUTTON2",
	MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5",
}

local BARE_MOUSE = { BUTTON1 = true, BUTTON2 = true }

local function Combo(key)
	if not key or key == "UNKNOWN" or MODIFIER_KEYS[key] then
		return nil
	end
	local prefix = ""
	if IsAltKeyDown() then
		prefix = "ALT-"
	end
	if IsControlKeyDown() then
		prefix = prefix .. "CTRL-"
	end
	if IsShiftKeyDown() then
		prefix = prefix .. "SHIFT-"
	end
	return prefix .. key
end

function ui.KeyField(label, getText, onKey, onClear)
	local row = CreateFrame("Frame", nil, page)
	row:SetSize(RowWidth(), 24)
	Place(row, 28, INDENT)

	local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT")
	text:SetText(label)

	local clear = PushButton(row, "clear", 46, function()
		StopCapture(capturing)
		onClear()
		Options.Refresh()
	end)
	clear:SetPoint("RIGHT")

	local field = CreateFrame("Button", nil, row)
	field:SetSize(140, 22)
	field:SetPoint("RIGHT", clear, "LEFT", -6, 0)
	field.bg = Fill(field, "BACKGROUND", 0.08, 0.08, 0.10, 0.95)
	field.bg:SetAllPoints()
	Outline(field, 0.30, 0.30, 0.34, 1)
	field.text = field:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	field.text:SetPoint("CENTER")

	local function Take(key)
		local combo = Combo(key)
		if not combo then
			return
		end
		StopCapture(field)
		onKey(combo)
		Options.Refresh()
	end

	field:RegisterForClicks("AnyUp")
	field:SetScript("OnClick", function(self, button)
		if capturing == self then
			local mapped = MOUSE_KEYS[button]
			-- An unmodified left or right click while listening means cancel.
			-- Combo returns the bare name when no modifier is down, which is the
			-- same test the binding itself has to pass.
			if mapped and not BARE_MOUSE[Combo(mapped) or ""] then
				Take(mapped)
			else
				StopCapture(self)
			end
			return
		end
		CloseMenu()
		StopCapture(capturing)
		capturing = self
		self:EnableKeyboard(true)
		if self.SetPropagateKeyboardInput then
			-- Without this the key also fires whatever it is already bound to.
			self:SetPropagateKeyboardInput(false)
		end
		Options.Refresh()
	end)

	field:SetScript("OnKeyDown", function(self, key)
		if capturing ~= self then
			return
		end
		if key == "ESCAPE" then
			StopCapture(self)
			return
		end
		Take(key)
	end)

	field:SetScript("OnHide", function(self)
		if capturing == self then
			StopCapture(self)
		end
	end)

	return Register(field, function()
		if capturing == field then
			field.text:SetText("|cffffd100press a key|r")
		else
			field.text:SetText(getText())
		end
	end)
end

--------------------------------------------------------------------------
-- The tabs
--------------------------------------------------------------------------

local function PaintTab(button, hover)
	local shade = button.active and 0.22 or (hover and 0.16 or 0.10)
	button.bg:SetColorTexture(shade, shade, shade + 0.03, 1)
	button.mark:SetShown(button.active and true or false)
	if button.active then
		button.text:SetTextColor(1, 0.82, 0.20)
	else
		button.text:SetTextColor(0.70, 0.70, 0.76)
	end
end

local function TabButton(label, index)
	local button = CreateFrame("Button", nil, panel)
	button:SetSize(RAIL_W - PAD - 4, TAB_H)
	button:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD - 4,
		-TITLE_H - PAD + 6 - (index - 1) * (TAB_H + 2))

	button.bg = Fill(button, "BACKGROUND", 0.10, 0.10, 0.13, 1)
	button.bg:SetAllPoints()
	button.mark = Fill(button, "ARTWORK", 0.25, 0.70, 0.95, 1)
	button.mark:SetPoint("TOPLEFT")
	button.mark:SetPoint("BOTTOMLEFT")
	button.mark:SetWidth(2)

	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.text:SetPoint("LEFT", 9, 0)
	button.text:SetPoint("RIGHT", -4, 0)
	button.text:SetJustifyH("LEFT")
	if button.text.SetWordWrap then
		button.text:SetWordWrap(false)
	end
	button.text:SetText(label)

	button:SetScript("OnClick", function()
		Options.SelectTab(index)
	end)
	button:SetScript("OnEnter", function(self)
		PaintTab(self, true)
	end)
	button:SetScript("OnLeave", function(self)
		PaintTab(self, false)
	end)

	PaintTab(button, false)
	return button
end

-- The registry keeps a part's name lower case, because it is also the word its
-- slash help is filed under. A tab is a title, so it takes its capital here
-- rather than making every feature carry a second name.
local function TabLabel(name)
	return (name:gsub("^%l", string.upper))
end

function Options.SelectTab(index)
	if not panel or not pages[index] then
		return
	end
	CloseMenu()
	StopCapture(capturing)
	active = index
	for i, frame in ipairs(pages) do
		frame:SetShown(i == index)
		tabs[i].active = (i == index)
		PaintTab(tabs[i], false)
	end
	Options.Refresh()
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function Build()
	panel = CreateFrame("Frame", "WarriorKitOptions", UIParent)
	panel:SetWidth(PANEL_W)
	panel:SetPoint("CENTER")
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetClampedToScreen(true)
	panel:SetFrameStrata("DIALOG")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	-- A listening key field swallows the keyboard and an open picker covers
	-- whatever is under it, so clicking anywhere else on the panel has to be a
	-- way out of both. Each of them eats its own click, so this never cancels
	-- the click that opened it.
	panel:SetScript("OnMouseDown", function()
		StopCapture(capturing)
		CloseMenu()
	end)
	panel:Hide()

	local bg = Fill(panel, "BACKGROUND", 0.05, 0.05, 0.06, 0.96)
	bg:SetAllPoints()
	Outline(panel, 0.35, 0.35, 0.42, 1)

	local titleBar = Fill(panel, "ARTWORK", 0.12, 0.12, 0.15, 1)
	titleBar:SetPoint("TOPLEFT", 1, -1)
	titleBar:SetPoint("TOPRIGHT", -1, -1)
	titleBar:SetHeight(TITLE_H)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", PAD, -7)
	title:SetText("WarriorKit")

	local close = PushButton(panel, "X", 20, function()
		Options.Hide()
	end)
	close:SetPoint("TOPRIGHT", -3, -3)

	-- Each feature draws its own page, in registry order, and takes the tab
	-- that shows it. A part with no panel function takes no tab.
	local tallest = 0
	for _, feature in ipairs(ns.features) do
		if feature.panel then
			local index = #pages + 1
			page = CreateFrame("Frame", nil, panel)
			page:SetPoint("TOPLEFT", panel, "TOPLEFT", RAIL_W, -TITLE_H)
			page:SetWidth(PAGE_W)
			page:Hide()
			page.rows = {}

			feature.panel(ui)

			local height = Layout(page)
			if height > tallest then
				tallest = height
			end
			pages[index] = page
			tabs[index] = TabButton(TabLabel(feature.name), index)
		end
	end
	page = nil

	divider = Fill(panel, "ARTWORK", 0.24, 0.24, 0.30, 1)
	divider:SetPoint("TOPLEFT", panel, "TOPLEFT", RAIL_W - 1, -TITLE_H)
	divider:SetWidth(1)

	footerRule = Fill(panel, "ARTWORK", 0.30, 0.30, 0.34, 1)
	footerRule:SetSize(PANEL_W - PAD * 2, 1)

	local lock = PushButton(panel, "", 150, function()
		ns.db.locked = not ns.db.locked
		ns.Each("lock")
		Options.Refresh()
	end)
	lock:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, PAD - 4)
	Register(lock, function()
		lock.text:SetText(ns.db.locked and "unlock to drag frames" or "lock frames")
	end)

	local reset = PushButton(panel, "reset positions", 150, function()
		SlashCmdList.WARRIORKIT("reset")
	end)
	reset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, PAD - 4)

	-- The rail is a page of its own as far as the window is concerned: seven
	-- tabs are taller than a short page and the window has to hold them.
	SetContent(math.max(tallest, #tabs * (TAB_H + 2) + PAD * 2))
	Options.SelectTab(active)

	-- Escape closes it, the same as any Blizzard window.
	tinsert(UISpecialFrames, "WarriorKitOptions")
end

function Options.Refresh()
	if not panel then
		return
	end
	for _, widget in ipairs(widgets) do
		if widget.Refresh then
			widget.Refresh()
		end
	end
end

function Options.Show()
	if not panel then
		return
	end
	-- Shown before refreshed, because a note measures its own wrapped height
	-- and a hidden font string is not obliged to answer.
	panel:Show()
	Options.Refresh()
end

function Options.Hide()
	if panel then
		CloseMenu()
		panel:Hide()
	end
end

function Options.Toggle()
	if not panel then
		return
	end
	if panel:IsShown() then
		Options.Hide()
	else
		Options.Show()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	Build()
end)
