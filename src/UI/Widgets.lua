local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The widgets
--
-- Everything the interface is made of that is not a rectangle. A push button, a
-- tick box, a stepper, a cycling value, a value picked off a list, a key
-- capture field, a slot you drop an item into, and a paragraph of prose that
-- sizes itself.
--
-- Two rules run through all of them and they are the two the panel this
-- replaced broke.
--
-- Every row measures itself. A widget that carries text hands the stack a
-- measure function, the stack sets the row's width before it asks, and the
-- answer is the wrapped height of the text plus whatever the control next to it
-- needs. Nothing here is given a height by whoever wrote the call site, so no
-- string can be longer than the room the layout guessed for it.
--
-- Nothing here knows what a setting is. A widget takes a getter and a setter
-- and reports what it did to its host. That is what lets the same kit build the
-- options panel today and an aura tracker or a loot window later without this
-- file learning either of their names.
--
-- Built out of CreateFrame and coloured textures, the way the rest of the addon
-- is. Every Blizzard widget template is one more thing that has to exist on
-- 2.5.6, and this file leans on none of them.
--------------------------------------------------------------------------

-- At most one of each in the whole interface, which is the behaviour you want
-- and also the reason they are module state rather than per kit. Two open
-- dropdowns is a bug, and two fields listening for the same keypress is worse.
local dropdown
local capturing

local function Enable(frame, enabled)
	frame:SetAlpha(enabled and 1 or 0.4)
	frame:EnableMouse(enabled and true or false)
end

--------------------------------------------------------------------------
-- A push button
--
-- Public, because the window chrome needs one for its close box and anything
-- built on this layer later will need one before it needs anything else here.
--------------------------------------------------------------------------

function UI.Button(parent, opts)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(opts.width or 60, opts.height or M.control)

	button.bg = ns.Fill(button, "BACKGROUND", C.control[1], C.control[2], C.control[3], 1)
	button.bg:SetAllPoints()
	button.edges = ns.Outline(button, C.edge[1], C.edge[2], C.edge[3], 1)
	ns.EdgeSize(button.edges, ns.Pixel(button))

	button.text = UI.Label(button, opts.size or M.small, C.text, "CENTER", UI.FLAT)
	button.text:SetPoint("CENTER")
	button.text:SetText(opts.label or "")

	button:SetScript("OnEnter", function(self)
		UI.Tint(self.bg, C.hover)
	end)
	button:SetScript("OnLeave", function(self)
		UI.Tint(self.bg, C.control)
	end)
	if opts.onClick then
		button:SetScript("OnClick", opts.onClick)
	end
	return button
end

--------------------------------------------------------------------------
-- The dropdown list
--
-- One popup shared by every picker, with a pool of rows inside it. The options
-- are asked for when the list opens rather than held, because what a picker
-- offers is usually something that moves while the window is open, the way the
-- weapons in your bags do.
--------------------------------------------------------------------------

local function DropdownFrame(parent)
	if dropdown then
		if dropdown:GetParent() ~= parent then
			dropdown:SetParent(parent)
		end
		return dropdown
	end
	dropdown = CreateFrame("Frame", nil, parent)
	dropdown:SetFrameStrata("FULLSCREEN_DIALOG")
	dropdown:SetClampedToScreen(true)
	dropdown:EnableMouse(true)
	local bg = ns.Fill(dropdown, "BACKGROUND", C.sunken[1], C.sunken[2], C.sunken[3], 0.98)
	bg:SetAllPoints()
	dropdown.edges = ns.Outline(dropdown, C.edge[1], C.edge[2], C.edge[3], 1)
	ns.EdgeSize(dropdown.edges, ns.Pixel(dropdown))
	dropdown.rows = {}
	dropdown:Hide()
	return dropdown
end

local function DropdownRow(list, index)
	if list.rows[index] then
		return list.rows[index]
	end

	local row = CreateFrame("Button", nil, list)
	row:SetHeight(M.row)
	row.bg = ns.Fill(row, "BACKGROUND", C.hover[1], C.hover[2], C.hover[3], 1)
	row.bg:SetAllPoints()

	row.icon = UI.Icon(row, "ARTWORK")
	row.icon:SetSize(M.check, M.check)
	row.icon:SetPoint("LEFT", M.rowGap, 0)

	row.text = UI.Label(row, M.font, C.text, "LEFT", UI.FLAT)
	row.text:SetPoint("LEFT", row.icon, "RIGHT", M.gutter, 0)
	row.text:SetPoint("RIGHT", -M.gutter, 0)
	UI.Wrap(row.text, false)

	row:SetScript("OnEnter", function(self)
		self.bg:SetAlpha(1)
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:SetAlpha(0)
	end)

	list.rows[index] = row
	return row
end

function UI.CloseDropdown()
	if dropdown then
		dropdown.owner = nil
		dropdown:Hide()
	end
end

function UI.OpenDropdown(parent, owner, options, onPick, after)
	local list = DropdownFrame(parent)
	local width = math.max(owner:GetWidth() or 0, 160)
	local edge = ns.Pixel(list)
	local height = edge

	for index, option in ipairs(options) do
		local row = DropdownRow(list, index)
		row:SetWidth(width - edge * 2)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", list, "TOPLEFT", edge, -height)
		row.text:SetText(option.text or option.value)
		if option.icon then
			row.icon:SetTexture(option.icon)
			row.icon:Show()
		else
			row.icon:Hide()
		end
		row.bg:SetAlpha(0)
		row:SetScript("OnClick", function()
			UI.CloseDropdown()
			onPick(option.value)
			if after then
				after()
			end
		end)
		row:Show()
		height = height + M.row
	end

	for index = #options + 1, #list.rows do
		list.rows[index]:Hide()
	end

	list:SetSize(width, height + edge)
	list:ClearAllPoints()
	-- Under the button, unless the button sits low enough on the screen that the
	-- list would hang off the bottom of it. GetBottom answers in the frame's own
	-- units and can be nil before the first layout pass, so a nil reads as room.
	local room = owner:GetBottom()
	if room and room < height + M.title then
		list:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, M.hairline * 2)
	else
		list:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -M.hairline * 2)
	end
	list.owner = owner
	list:Show()
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

function UI.StopCapture()
	local field = capturing
	if not field then
		return false
	end
	capturing = nil
	field:EnableKeyboard(false)
	-- Behind a method check because nothing installed here proves the options
	-- panel's SetPropagateKeyboardInput is on 2.5.6, and the cost of missing it
	-- is one stray keypress reaching whatever it was already bound to.
	if field.SetPropagateKeyboardInput then
		field:SetPropagateKeyboardInput(true)
	end
	if field.afterCapture then
		field.afterCapture()
	end
	return true
end

function UI.Capturing()
	return capturing
end

--------------------------------------------------------------------------
-- The kit
--
-- One kit per page. The host is whatever is holding the page and answers four
-- questions:
--
--   host.stack        the stack rows are added to right now
--   host.Section(t)   open a section titled t and return the stack for it,
--                     optional, and without it a section is a heading row
--   host.Refresh()    put the whole host back in step after a widget changed
--                     something, optional, and without it the kit refreshes
--                     only its own rows
--   host.Popup()      the frame a dropdown should parent to, optional
--
-- That is the entire contract. A future window builds a page by making a stack,
-- making a kit over it, and calling the same functions the seven feature parts
-- already call.
--------------------------------------------------------------------------

function UI.Kit(host)
	local kit = { host = host, widgets = {} }

	local function Stack()
		return host.stack
	end

	local function Parent()
		return host.stack.frame
	end

	local function Popup()
		return (host.Popup and host.Popup()) or UIParent
	end

	-- Every row registers what puts it back in step with whatever it is showing,
	-- so one refresh after any change covers the lot, no matter whether the
	-- change came from a click here or from a slash command. Rows on a section
	-- nobody is looking at refresh too: they cost nothing, and it means opening a
	-- section never shows a stale value.
	local function Remember(frame, refresh)
		frame.Refresh = refresh
		kit.widgets[#kit.widgets + 1] = frame
		if refresh then
			refresh()
		end
		return frame
	end

	function kit.Refresh()
		for index = 1, #kit.widgets do
			local widget = kit.widgets[index]
			if widget.Refresh then
				widget.Refresh()
			end
		end
	end

	local function Changed()
		if host.Refresh then
			host.Refresh()
		else
			kit.Refresh()
		end
	end

	local function Prose(parent, size, color)
		local text = UI.Label(parent, size, color, "LEFT", UI.FLAT)
		UI.Wrap(text, true)
		text:SetSpacing(2)
		text:SetPoint("TOPLEFT")
		return text
	end

	-- The width a wrapping label gets: its own stack, less the row's indent, less
	-- whatever sits to the right of the label on the same row. The stack is
	-- captured by each widget when it is built rather than read from the host at
	-- measure time, because by then the host is pointing at whichever section was
	-- opened last and a row would be measuring itself against a column it is not
	-- in.
	local function TextWidth(stack, cell, reserved)
		return math.max(1, stack.width - cell.indent - (reserved or 0))
	end

	----------------------------------------------------------------------
	-- Sections and prose
	----------------------------------------------------------------------

	-- Opens a section. Where the host has somewhere to put sections, which is
	-- what the options window's tab strip is, the title becomes a tab and the
	-- rows after it go on that tab's own stack. Where it has not, the title is a
	-- heading rule in the same column, which is what this used to be.
	function kit.Header(title)
		if host.Section then
			return host.Section(title)
		end

		local row = CreateFrame("Frame", nil, Parent())
		local text = UI.Label(row, M.heading, C.heading, "LEFT", UI.FLAT)
		text:SetPoint("BOTTOMLEFT", 0, M.rowGap)
		text:SetText(title)
		local rule = UI.Rule(row, C.hairline)
		rule:SetPoint("BOTTOMLEFT")
		rule:SetPoint("BOTTOMRIGHT")
		Stack():Add(row, { height = M.heading + M.gutter })
		return Stack()
	end

	kit.Section = kit.Header

	-- A paragraph of quiet explanatory prose. getText is a function rather than a
	-- string because most of these report live state, and it is called on every
	-- refresh so the row is re-measured when the wording changes under it.
	function kit.Note(getText)
		local stack = Stack()
		local row = CreateFrame("Frame", nil, Parent())
		local line = Prose(row, M.small, C.dim)

		local cell = stack:Add(row, {
			indent = M.indent,
			-- A note belongs to the control above it and is followed by the next
			-- group, so it carries the wider gap. Even air between every row reads
			-- as one undifferentiated list however carefully it is measured.
			gap = M.gutter,
			measure = function(this)
				line:SetWidth(TextWidth(stack, this))
				return UI.TextHeight(line, M.small + 3)
			end,
		})

		return Remember(row, function()
			line:SetText(getText() or "")
			line:SetWidth(TextWidth(stack, cell))
		end)
	end

	-- The same shape in the reading colour rather than the quiet one, for a line
	-- that is instruction rather than footnote. Nothing calls it yet; it is here
	-- because Note is not the only kind of prose a page will want and the second
	-- one should not be a copy of the first.
	function kit.Text(getText)
		local stack = Stack()
		local row = CreateFrame("Frame", nil, Parent())
		local line = Prose(row, M.font, C.text)

		local cell = stack:Add(row, {
			indent = M.indent,
			measure = function(this)
				line:SetWidth(TextWidth(stack, this))
				return UI.TextHeight(line, M.font + 3)
			end,
		})

		return Remember(row, function()
			line:SetText(getText() or "")
			line:SetWidth(TextWidth(stack, cell))
		end)
	end

	function kit.Gap(height)
		return Stack():Space(height or M.gutter)
	end

	function kit.Divider()
		local row = CreateFrame("Frame", nil, Parent())
		local rule = UI.Rule(row, C.hairline)
		rule:SetPoint("LEFT")
		rule:SetPoint("RIGHT")
		return Stack():Add(row, { height = M.gutter, indent = M.indent })
	end

	----------------------------------------------------------------------
	-- Controls
	----------------------------------------------------------------------

	function kit.Check(label, get, set)
		local button = CreateFrame("Button", nil, Parent())

		local box = UI.Box(button, C.sunken, C.edge)
		box:SetSize(M.check, M.check)
		-- Dropped by half the difference between a control row and a tick box, so
		-- a tick sits level with the first line of its own label and stays there
		-- when the label wraps onto a second.
		box:SetPoint("TOPLEFT", 0, -math.floor((M.control - M.check) / 2))
		button.tick = ns.Fill(box, "ARTWORK", C.tick[1], C.tick[2], C.tick[3], 1)
		button.tick:SetPoint("TOPLEFT", 3, -3)
		button.tick:SetPoint("BOTTOMRIGHT", -3, 3)

		button.text = UI.Label(button, M.font, C.text, "LEFT", UI.FLAT)
		UI.Wrap(button.text, true)
		button.text:SetSpacing(2)
		button.text:SetPoint("TOPLEFT", box, "TOPRIGHT", M.gutter, 0)

		local stack = Stack()
		local reserved = M.check + M.gutter
		stack:Add(button, {
			indent = M.indent,
			measure = function(this)
				button.text:SetWidth(TextWidth(stack, this, reserved))
				return math.max(M.control, UI.TextHeight(button.text, M.check) + M.rowGap)
			end,
		})

		button:SetScript("OnClick", function()
			set(not get())
			Changed()
		end)
		button:SetScript("OnEnter", function(self)
			self.text:SetTextColor(1, 1, 1)
		end)
		button:SetScript("OnLeave", function(self)
			self.text:SetTextColor(C.text[1], C.text[2], C.text[3])
		end)

		button.text:SetText(label)
		return Remember(button, function()
			button.tick:SetShown(get() and true or false)
			-- IsAvailable is set on the returned widget by the caller, after the
			-- fact, so it is read here rather than taken as an argument.
			Enable(button, button.IsAvailable == nil or button:IsAvailable())
		end)
	end

	-- Shared by every row that is a label on the left and a control on the right.
	-- The label wraps and the row is as tall as the taller of the two, so a long
	-- label pushes the row down rather than running under its own control.
	local function Paired(reserved, controlHeight)
		local stack = Stack()
		local row = CreateFrame("Frame", nil, Parent())
		local text = UI.Label(row, M.font, C.text, "LEFT", UI.FLAT)
		UI.Wrap(text, true)
		text:SetSpacing(2)
		text:SetPoint("TOPLEFT", 0, -math.floor((controlHeight - M.font) / 2))

		stack:Add(row, {
			indent = M.indent,
			measure = function(this)
				text:SetWidth(TextWidth(stack, this, reserved + M.gutter))
				return math.max(controlHeight, UI.TextHeight(text, controlHeight))
			end,
		})
		return row, text
	end

	function kit.Stepper(label, low, high, step, get, set)
		local valueWidth = 34
		local reserved = M.control * 2 + valueWidth + M.rowGap * 2
		local row, text = Paired(reserved, M.control)
		text:SetText(label)

		local function Nudge(delta)
			local current = get() + delta * step
			if current < low then
				current = low
			elseif current > high then
				current = high
			end
			set(current)
			Changed()
		end

		local minus = UI.Button(row, { label = "-", width = M.control,
			onClick = function() Nudge(-1) end })
		minus:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(M.control + valueWidth + M.rowGap * 2), 0)
		local plus = UI.Button(row, { label = "+", width = M.control,
			onClick = function() Nudge(1) end })
		plus:SetPoint("TOPRIGHT")

		local value = UI.Label(row, M.font, C.heading, "CENTER", UI.FLAT)
		value:SetPoint("TOP", 0, -math.floor((M.control - M.font) / 2))
		value:SetPoint("LEFT", minus, "RIGHT", M.rowGap, 0)
		value:SetPoint("RIGHT", plus, "LEFT", -M.rowGap, 0)

		return Remember(row, function()
			value:SetText(tostring(get()))
		end)
	end

	function kit.Cycle(label, values, get, set)
		local width = 104
		local row, text = Paired(width, M.control)
		text:SetText(label)

		local button = UI.Button(row, { width = width, onClick = function()
			local current = get()
			for index, candidate in ipairs(values) do
				if candidate == current then
					set(values[index % #values + 1])
					Changed()
					return
				end
			end
			set(values[1])
			Changed()
		end })
		button:SetPoint("TOPRIGHT")

		return Remember(row, function()
			button.text:SetText(get())
		end)
	end

	-- A value chosen off a list. getOptions returns an array of
	-- { value, text, icon } and is asked both when the list opens and on every
	-- refresh, so the caller is free to build it out of something live. The row
	-- shows whichever option carries the current value, so a caller holding a
	-- value it cannot offer, a weapon sitting in the bank, has to put that entry
	-- in the list itself and say on the row what is odd about it.
	function kit.Picker(label, get, set, getOptions)
		local width = 168
		local row, text = Paired(width, M.control)
		text:SetText(label)

		local button = CreateFrame("Button", nil, row)
		button:SetSize(width, M.control)
		button:SetPoint("TOPRIGHT")
		button.bg = ns.Fill(button, "BACKGROUND", C.sunken[1], C.sunken[2], C.sunken[3], 1)
		button.bg:SetAllPoints()
		button.edges = ns.Outline(button, C.edge[1], C.edge[2], C.edge[3], 1)
		ns.EdgeSize(button.edges, ns.Pixel(button))

		local icon = UI.Icon(button, "ARTWORK")
		icon:SetSize(M.check, M.check)
		icon:SetPoint("LEFT", 3, 0)

		local arrow = UI.Label(button, M.small, C.dim, "RIGHT", UI.FLAT)
		arrow:SetPoint("RIGHT", -M.rowGap, 0)
		arrow:SetText("v")

		local value = UI.Label(button, M.font, C.text, "LEFT", UI.FLAT)
		value:SetPoint("LEFT", icon, "RIGHT", M.rowGap, 0)
		value:SetPoint("RIGHT", arrow, "LEFT", -M.rowGap, 0)
		UI.Wrap(value, false)

		button:SetScript("OnEnter", function(self)
			UI.Tint(self.bg, C.control)
		end)
		button:SetScript("OnLeave", function(self)
			UI.Tint(self.bg, C.sunken)
		end)
		button:SetScript("OnClick", function(self)
			UI.StopCapture()
			if dropdown and dropdown:IsShown() and dropdown.owner == self then
				UI.CloseDropdown()
				return
			end
			UI.OpenDropdown(Popup(), self, getOptions(), set, Changed)
		end)
		button:SetScript("OnHide", function(self)
			if dropdown and dropdown.owner == self then
				UI.CloseDropdown()
			end
		end)

		return Remember(row, function()
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

	-- A full width action button. getLabel is a function so it can say what
	-- pressing it will do right now, and isAvailable gates the click the way
	-- Check's IsAvailable does.
	function kit.Action(getLabel, onClick, isAvailable)
		local button = UI.Button(Parent(), { width = 1, height = M.row, onClick = onClick })
		Stack():Add(button, { indent = M.indent, height = M.row })

		return Remember(button, function()
			button.text:SetText(getLabel())
			Enable(button, isAvailable == nil or isAvailable())
		end)
	end

	-- Two buttons side by side, for a do-it and an undo-it that belong together.
	function kit.ActionPair(leftLabel, leftClick, leftOk, rightLabel, rightClick, rightOk)
		local stack = Stack()
		local row = CreateFrame("Frame", nil, Parent())
		local cell = stack:Add(row, { indent = M.indent, height = M.row })

		local left = UI.Button(row, { width = 1, height = M.row, onClick = leftClick })
		left:SetPoint("TOPLEFT")
		local right = UI.Button(row, { width = 1, height = M.row, onClick = rightClick })
		right:SetPoint("TOPRIGHT")

		return Remember(row, function()
			-- Half the row each, less the gutter between them, worked out on every
			-- refresh because the stack's width is not known when the row is built.
			local half = math.floor((TextWidth(stack, cell) - M.gutter) / 2)
			left:SetWidth(math.max(half, 1))
			right:SetWidth(math.max(half, 1))
			left.text:SetText(leftLabel())
			right.text:SetText(rightLabel())
			Enable(left, leftOk == nil or leftOk())
			Enable(right, rightOk == nil or rightOk())
		end)
	end

	function kit.KeyField(label, getText, onKey, onClear)
		local fieldWidth, clearWidth = 120, 44
		local reserved = fieldWidth + clearWidth + M.rowGap
		local row, text = Paired(reserved, M.control)
		text:SetText(label)

		local clear = UI.Button(row, { label = "clear", width = clearWidth, onClick = function()
			UI.StopCapture()
			onClear()
			Changed()
		end })
		clear:SetPoint("TOPRIGHT")

		local field = CreateFrame("Button", nil, row)
		field:SetSize(fieldWidth, M.control)
		field:SetPoint("TOPRIGHT", clear, "TOPLEFT", -M.rowGap, 0)
		field.bg = ns.Fill(field, "BACKGROUND", C.sunken[1], C.sunken[2], C.sunken[3], 1)
		field.bg:SetAllPoints()
		field.edges = ns.Outline(field, C.edge[1], C.edge[2], C.edge[3], 1)
		ns.EdgeSize(field.edges, ns.Pixel(field))
		field.text = UI.Label(field, M.font, C.text, "CENTER", UI.FLAT)
		field.text:SetPoint("CENTER")
		field.afterCapture = Changed

		local function Take(key)
			local combo = Combo(key)
			if not combo then
				return
			end
			UI.StopCapture()
			onKey(combo)
			Changed()
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
					UI.StopCapture()
				end
				return
			end
			UI.CloseDropdown()
			UI.StopCapture()
			capturing = self
			self:EnableKeyboard(true)
			if self.SetPropagateKeyboardInput then
				-- Without this the key also fires whatever it is already bound to.
				self:SetPropagateKeyboardInput(false)
			end
			Changed()
		end)

		field:SetScript("OnKeyDown", function(self, key)
			if capturing ~= self then
				return
			end
			if key == "ESCAPE" then
				UI.StopCapture()
				return
			end
			Take(key)
		end)

		field:SetScript("OnHide", function(self)
			if capturing == self then
				UI.StopCapture()
			end
		end)

		return Remember(field, function()
			if capturing == field then
				field.text:SetText("|cffffd100press a key|r")
				UI.Tint(field.bg, C.selected)
			else
				field.text:SetText(getText())
				UI.Tint(field.bg, C.sunken)
			end
		end)
	end

	-- An item slot you drop something into
	--
	-- get() returns the icon to draw and the text beside it, and either may be
	-- nil: no icon draws the empty-slot art opts.empty hands over, no text
	-- leaves the line blank. set(link) is given the item link the cursor was
	-- carrying and returns whether it took it, which is where the rule that a
	-- shield does not go in a main hand lives. This file knows about neither
	-- inventory slots nor shields, the same as it knows nothing about settings.
	--
	-- A drop arrives two ways because neither is reliable on its own.
	-- OnReceiveDrag does not fire when the drop replaced something already on
	-- the cursor, and OnMouseUp does not fire when the press that started the
	-- drag happened somewhere else. OPie's ring editor registers both and then
	-- polls on top; the poll is an OnUpdate, which this layer is not allowed to
	-- add, so the two handlers are where it stops.
	--
	-- The highlight asks CursorHasItem rather than watching the cursor, for the
	-- same reason. A slot lights up when the mouse arrives carrying something,
	-- not the moment the item is picked up across the screen.
	function kit.ItemSlot(label, get, set, opts)
		opts = opts or {}
		local size, nameWidth = 32, 150
		local row, text = Paired(size + M.gutter + nameWidth, size)
		text:SetText(label)

		local slot = UI.Box(row, C.sunken, C.edge)
		slot:SetSize(size, size)
		slot:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(nameWidth + M.gutter), 0)

		-- Two textures rather than one. An item icon is a 64 texel square and
		-- wants the crop and the snapping fix UI.Icon applies; the empty-slot art
		-- is Blizzard's own frame for that hand and is already the shape it draws
		-- at, so cropping it eats its border.
		local icon = UI.Icon(slot, "ARTWORK")
		icon:SetPoint("TOPLEFT", 2, -2)
		icon:SetPoint("BOTTOMRIGHT", -2, 2)
		local empty = slot:CreateTexture(nil, "ARTWORK")
		empty:SetPoint("TOPLEFT", 2, -2)
		empty:SetPoint("BOTTOMRIGHT", -2, 2)
		empty:SetVertexColor(1, 1, 1, 0.35)

		local value = UI.Label(row, M.font, C.text, "LEFT", UI.FLAT)
		UI.Wrap(value, false)
		value:SetPoint("LEFT", slot, "RIGHT", M.gutter, 0)
		value:SetPoint("RIGHT", row, "RIGHT")

		local function Drop()
			local kind, _, link = GetCursorInfo()
			if kind ~= "item" or type(link) ~= "string" then
				return
			end
			if set(link) then
				ClearCursor()
			end
			Changed()
		end

		local button = CreateFrame("Button", nil, row)
		button:SetAllPoints(slot)
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnReceiveDrag", Drop)
		button:SetScript("OnClick", function(_, which)
			UI.CloseDropdown()
			UI.StopCapture()
			if which == "RightButton" then
				set(nil)
				Changed()
				return
			end
			Drop()
		end)
		button:SetScript("OnEnter", function()
			-- CursorHasItem rather than the accepts test alone, so a slot lights
			-- up only while something is being carried into it.
			local carrying = CursorHasItem and CursorHasItem()
			UI.Tint(slot.bg, carrying and C.selected or C.control)
		end)
		button:SetScript("OnLeave", function()
			UI.Tint(slot.bg, C.sunken)
		end)

		return Remember(row, function()
			local texture, shown = get()
			icon:SetTexture(texture)
			icon:SetShown(texture and true or false)
			local fallback = (not texture) and opts.empty and opts.empty() or nil
			empty:SetTexture(fallback)
			empty:SetShown(fallback and true or false)
			value:SetText(shown or "")
			local usable = (opts.enabled == nil) or opts.enabled()
			Enable(button, usable)
			slot:SetAlpha(usable and 1 or 0.4)
		end)
	end

	-- The escape hatch. Hands the caller a bare row of the width the stack is
	-- laying out, so a page can carry something this file has never heard of
	-- without this file growing a function for it. build is given the row and
	-- returns nothing, or a measure function when the row sizes to its contents.
	function kit.Custom(build, opts)
		opts = opts or {}
		local row = CreateFrame("Frame", nil, Parent())
		local measure = build(row)
		local cell = Stack():Add(row, {
			indent = opts.indent or M.indent,
			height = opts.height or M.row,
			measure = measure,
		})
		if opts.refresh then
			Remember(row, opts.refresh)
		end
		return row, cell
	end

	return kit
end
