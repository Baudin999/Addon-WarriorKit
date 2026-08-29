local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The widgets
--
-- Everything the interface is made of that is not a rectangle. A push button, a
-- tick box, a stepper, a value you drag, a cycling value, a value picked off a
-- list, a key capture field, a line of text you type, a strip of buttons where
-- one is chosen, a slot you drop an item into, a character with those slots
-- under it, and a paragraph of prose that sizes itself.
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

-- The two ranges that are one range.
--
-- Zoom and background were declared at the top of four and three feature files
-- respectively, the same numbers written seven times. They are here so the kit
-- calls below can supply them, and public so the slash words that take the same
-- number can read them rather than keeping a private copy that drifts.
UI.ZOOM_LOW, UI.ZOOM_HIGH = 1, 3
UI.ALPHA_LOW, UI.ALPHA_HIGH, UI.ALPHA_STEP = 0, 100, 5

-- At most one of each in the whole interface, which is the behaviour you want
-- and also the reason they are module state rather than per kit. Two open
-- dropdowns is a bug, and two fields listening for the same keypress is worse.
--
-- `typing` is the third of them and the one that was missing. An edit box with
-- the keyboard takes every press before a frame's OnKeyDown ever sees it, so a
-- search field holding focus meant a key field captured nothing and the key you
-- pressed was typed into the search instead. Tracked here rather than in the
-- window, because the field that has to give the keyboard up is in the chrome
-- and the thing that needs it is a widget on a page, and neither knows the
-- other exists.
local dropdown
local capturing
local typing

-- What an optional callback defaults to, so a widget can call one without
-- asking every time whether it was given.
local function Nothing() end

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

	-- opts.glyph says the label is a mark rather than a word, which is the close
	-- cross and both ends of every stepper. The letter passed is the same letter
	-- either way; see UI/Text.lua.
	if opts.glyph then
		button.text = UI.Glyph(button, opts.size or M.glyph, C.text, "CENTER")
	else
		button.text = UI.Label(button, opts.size or M.small, C.text, "CENTER", UI.FLAT)
	end
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

-- Said by a field on the way in, so anything that wants the keyboard can take
-- it back without naming the field or the window it sits in.
function UI.Typing(field)
	typing = field
end

-- Returns whether there was one, the same as UI.StopCapture. Cleared before the
-- focus is dropped, so the OnEditFocusLost that follows finds nothing to do
-- rather than coming back round through here.
function UI.StopTyping()
	local field = typing
	if not field then
		return false
	end
	typing = nil
	field:ClearFocus()
	return true
end

----------------------------------------------------------------------------
-- The box a key is pressed into
--
-- Click it, press what you want, and it hands the combination back. Everything
-- about which key that was is above; everything about what the key then does
-- belongs to whoever asked for one.
--
-- Module scope for the reason UI.DropSquare is: a page laying out its own row
-- wants the box and not the labelled row around it, and the mouseover casting
-- page puts one on every row it draws.
--
-- opts.getText says what the box reads while it is not listening, opts.onKey
-- takes the combination, and opts.after puts the page back in step. The box
-- refreshes itself through field.Update, which the caller registers wherever
-- its own refreshes are kept.
--------------------------------------------------------------------------

function UI.KeyBox(parent, opts)
	local after = opts.after or Nothing
	local field = CreateFrame("Button", nil, parent)
	field:SetSize(opts.width or 120, opts.height or M.control)
	field.bg = ns.Fill(field, "BACKGROUND", C.sunken[1], C.sunken[2], C.sunken[3], 1)
	field.bg:SetAllPoints()
	field.edges = ns.Outline(field, C.edge[1], C.edge[2], C.edge[3], 1)
	ns.EdgeSize(field.edges, ns.Pixel(field))
	field.text = UI.Label(field, M.font, C.text, "CENTER", UI.FLAT)
	field.text:SetPoint("CENTER")
	field.afterCapture = after

	local function Take(key)
		local combo = Combo(key)
		if not combo then
			return
		end
		UI.StopCapture()
		opts.onKey(combo)
		after()
	end

	local function Listen(self)
		UI.CloseDropdown()
		UI.StopCapture()
		-- Before the capture is armed, not after. A field still holding the
		-- keyboard would eat the very next press, which is the press this
		-- control exists to read.
		UI.StopTyping()
		capturing = self
		self:EnableKeyboard(true)
		if self.SetPropagateKeyboardInput then
			-- Without this the key also fires whatever it is already bound to.
			self:SetPropagateKeyboardInput(false)
		end
		after()
	end

	field:RegisterForClicks("AnyUp")
	field:SetScript("OnClick", function(self, button)
		if capturing ~= self then
			Listen(self)
			return
		end
		-- An unmodified left or right click while listening means cancel.
		-- Combo returns the bare name when no modifier is down, which is the
		-- same test the binding itself has to pass.
		local mapped = MOUSE_KEYS[button]
		if mapped and not BARE_MOUSE[Combo(mapped) or ""] then
			Take(mapped)
		else
			UI.StopCapture()
		end
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

	field.Update = function()
		if capturing == field then
			field.text:SetText("|cffffd100press a key|r")
			UI.Tint(field.bg, C.selected)
		else
			field.text:SetText(opts.getText())
			UI.Tint(field.bg, C.sunken)
		end
	end
	return field
end

------------------------------------------------------------------------
-- Slots
--
-- One square you drop something onto, and the two things built out of it: a
-- labelled row, and a character with its hands under it.
--
-- get() returns the icon to draw and the text to say about it, and either
-- may be nil: no icon draws the empty-slot art opts.empty hands over, no
-- text leaves the line blank. opts.take is handed the whole of GetCursorInfo
-- and answers the one value set() gets, or nil to refuse the drop; with none
-- named a square takes an item and hands over its link. set() returns whether
-- it took it, which is where the rule that a shield does not go in a main
-- hand lives, because this file knows about neither shields nor spells.
--
-- A drop arrives two ways because neither is reliable on its own.
-- OnReceiveDrag does not fire when the drop replaced something already on
-- the cursor, and OnMouseUp does not fire when the press that started the
-- drag happened somewhere else. OPie's ring editor registers both and then
-- polls on top; the poll is an OnUpdate, which this layer is not allowed to
-- add, so the two handlers are where it stops.
--
-- The highlight asks opts.take rather than watching the cursor, for the same
-- reason. It was CursorHasItem, which never answers for a spell.
--
-- Module scope rather than inside the kit, because a page that lays out its own
-- row wants the square without the label and the stack cell around it. opts.after
-- is what the kit passes its own refresh in; a caller outside the kit passes
-- whatever puts its page back in step.
--------------------------------------------------------------------------

-- Blizzard's own item slot ring, over the addon's own box. It is the one
-- borrowed thing in the widget layer and it is borrowed on purpose: a slot
-- you drag a weapon into should look like the slot the weapon came out of.
-- 64 texels of art around a 36 pixel slot is the ratio the client draws it
-- at, so the ring is that much larger than the square it rings.
local RING = "Interface\\Buttons\\UI-Quickslot2"
local RING_SCALE = 64 / 36

function UI.DropSquare(parent, size, get, set, opts)
	opts = opts or {}
	local after = opts.after or Nothing
	local square = UI.Box(parent, C.sunken, C.edge)
	square:SetSize(size, size)

	-- Two textures rather than one. An item icon is a 64 texel square and
	-- wants the crop and the snapping fix UI.Icon applies; the empty-slot art
	-- is Blizzard's own frame for that hand and is already the shape it draws
	-- at, so cropping it eats its border.
	local icon = UI.Icon(square, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", -2, 2)
	local empty = square:CreateTexture(nil, "ARTWORK")
	empty:SetPoint("TOPLEFT", 2, -2)
	empty:SetPoint("BOTTOMRIGHT", -2, 2)
	empty:SetVertexColor(1, 1, 1, 0.35)

	if opts.ring then
		local ring = square:CreateTexture(nil, "OVERLAY")
		ring:SetTexture(RING)
		ring:SetPoint("CENTER")
		ring:SetSize(UI.Round(square, size * RING_SCALE), UI.Round(square, size * RING_SCALE))
	end

	local function Carried()
		local kind, a, b, c = GetCursorInfo()
		if opts.take then
			return opts.take(kind, a, b, c)
		end
		if kind ~= "item" or type(b) ~= "string" then
			return nil
		end
		return b
	end

	local function Drop()
		local carried = Carried()
		if carried == nil then
			return
		end
		if set(carried) then
			ClearCursor()
		end
		after()
	end

	local button = CreateFrame("Button", nil, parent)
	button:SetAllPoints(square)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnReceiveDrag", Drop)
	button:SetScript("OnClick", function(_, which)
		UI.CloseDropdown()
		UI.StopCapture()
		if which == "RightButton" then
			set(nil)
			after()
			return
		end
		Drop()
	end)
	button:SetScript("OnEnter", function()
		UI.Tint(square.bg, Carried() ~= nil and C.selected or C.control)
	end)
	button:SetScript("OnLeave", function()
		UI.Tint(square.bg, C.sunken)
	end)

	square.button = button
	square.Refresh = function()
		local texture, shown = get()
		icon:SetTexture(texture)
		icon:SetShown(texture and true or false)
		local fallback = (not texture) and opts.empty and opts.empty() or nil
		empty:SetTexture(fallback)
		empty:SetShown(fallback and true or false)
		local usable = (opts.enabled == nil) or opts.enabled()
		Enable(button, usable)
		square:SetAlpha(usable and 1 or 0.4)
		return shown
	end
	return square
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

--------------------------------------------------------------------------
-- Refreshing
--
-- Every row registers what puts it back in step with whatever it is showing, so
-- one refresh after any change covers the lot, no matter whether the change came
-- from a click here or from a slash command. Rows on a section nobody is looking
-- at refresh too: they cost nothing, and it means opening a section never shows
-- a stale value.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- The index
--
-- Every control records what it is called as it is built, and the host says
-- where that is: which section, and which group that section named. Nothing in
-- this file reads the index back. It is what the options window's search field
-- walks and what the harness counts labels out of, and a control that forgot to
-- register is a control search cannot find.
--
-- So it is one call at the end of each constructor rather than a walk over the
-- frames afterwards, which would have to guess which font string on a row was
-- the label. A label is a string, or a function for the rows whose label says
-- what pressing them would do right now.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Sections and the groups they name
--
-- kit.Section opens a section and says which group of the options window it
-- belongs in. Both are the caller's to choose, which is the point: a group is
-- what somebody was thinking about when they opened the window, and a feature
-- is a folder of code. UnitFrames is the case that settles it. Its three
-- sections are two about your own frames and one about enemy nameplates, and
-- until a section could name its own group those three had to share a rail
-- entry called after the folder they happen to live in.
--
-- Where the host has somewhere to put sections, which is what the options
-- window's rail and tab strip are, the rows after the call go on that tab's own
-- stack. Where it has not, the title is a heading rule in the same column and
-- the group is not used, because there is nothing to file it under.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Prose, in three capped kinds
--
-- There used to be one call, Note, and one note per control: a hundred and
-- thirty four of them holding forty thousand characters, about fifteen pages of
-- writing with switches embedded in it. They did three different jobs and the
-- window drew all three the same way, so the one sentence a control actually
-- needed was buried in four paragraphs about why the pixel grid prefers whole
-- stops.
--
-- So there are three calls now and each of them is capped, because a cap is the
-- only thing that has ever stopped this growing back. What the caps push out
-- goes to docs/README.md, which is where explaining the addon belongs and which
-- can be read on a second monitor while the game runs.
--
-- Installed onto a kit rather than written inside UI.Kit, because these three
-- are one subject and the kit's body is a list of controls. `ctx` is the handful
-- of closures every row in this file is built out of: the stack a row lands on,
-- the frame it parents to, a wrapping label, the width that label gets, and the
-- register-for-refresh call.
--------------------------------------------------------------------------

local LEDE_MAX, HINT_MAX = 160, 200

local function Capped(kind, text, limit)
	assert(type(text) == "string" and text ~= "",
		("a %s was given no text"):format(kind))
	assert(#text <= limit,
		("a %s is %d characters and the cap is %d: %s"):format(kind, #text, limit, text))
	return text
end

local function InstallProse(kit, ctx)
	-- One line under a section title, saying what this section changes on
	-- screen. Present tense, one sentence, and one per section: a page that
	-- wants a second one wants a second section.
	--
	-- A plain string rather than a function, unlike everything below it. A lede
	-- describes what a page is for, and what a page is for does not change while
	-- you are looking at it. Live state is Reading's job.
	function kit.Lede(text)
		text = Capped("lede", text, LEDE_MAX)
		if ctx.host.Lede then
			ctx.host.Lede(text)
		end

		local stack = ctx.Stack()
		local row = CreateFrame("Frame", nil, ctx.Parent())
		local line = ctx.Prose(row, M.small, C.dim)
		line:SetText(text)

		local cell = stack:Add(row, {
			indent = M.indent,
			-- A lede introduces the group under it, so it carries the wider gap.
			-- Even air between every row reads as one undifferentiated list
			-- however carefully it is measured.
			gap = M.gutter,
			measure = function(this)
				line:SetWidth(ctx.TextWidth(stack, this))
				return UI.TextHeight(line, M.small + 3)
			end,
		})

		return ctx.Remember(row, function()
			line:SetWidth(ctx.TextWidth(stack, cell))
		end)
	end

	-- The sentence one control needs, drawn in the addon's own tooltip on hover
	-- rather than in the column. It attaches to the row above it, which is the
	-- row the caller wrote last, so a hint reads at the call site exactly where a
	-- note used to and costs the page no vertical space at all.
	--
	-- Two hundred characters, and most controls do not need one. A control that
	-- cannot be explained in two hundred characters is a control whose label is
	-- wrong.
	function kit.Hint(text)
		text = Capped("hint", text, HINT_MAX)
		local owner = kit.widgets[#kit.widgets]
		assert(owner, "a hint was written before the control it belongs to")
		assert(not owner.hint, ("two hints on one control: %s"):format(text))
		owner.hint = text

		-- Hung over whatever the widget already does on the way in and out,
		-- because a check box repaints its own label there and a picker its own
		-- background.
		local enter, leave = owner:GetScript("OnEnter"), owner:GetScript("OnLeave")
		owner:SetScript("OnEnter", function(self, ...)
			if enter then
				enter(self, ...)
			end
			ns.Tip.Open(self, { kind = "note", lines = { self.hint } })
		end)
		owner:SetScript("OnLeave", function(self, ...)
			if leave then
				leave(self, ...)
			end
			ns.Tip.Close()
		end)
		UI.PassCamera(owner)
		return owner
	end

	-- A live number or a short state, in the accent colour, on the right of a row
	-- of its own. This is what the feed counters, the performance counters and
	-- the "Now:" lines under the size slider become.
	--
	-- It is not prose and it is not capped by character count. It is capped by
	-- the column: it never wraps, so it has to fit one line at the narrowest
	-- width the window is ever laid out at, and the harness measures that rather
	-- than trusting it.
	function kit.Reading(label, getText)
		local stack = ctx.Stack()
		local row = CreateFrame("Frame", nil, ctx.Parent())

		local name = UI.Label(row, M.small, C.dim, "LEFT", UI.FLAT)
		UI.Wrap(name, false)
		name:SetPoint("TOPLEFT")
		name:SetText(label)

		local value = UI.Label(row, M.small, C.accent, "RIGHT", UI.FLAT)
		UI.Wrap(value, false)
		value:SetPoint("TOPRIGHT")
		value:SetPoint("LEFT", name, "RIGHT", M.gutter, 0)

		stack:Add(row, {
			indent = M.indent,
			height = M.small + M.rowGap,
		})

		row.reading = value
		return ctx.Remember(row, function()
			value:SetText(getText() or "")
		end)
	end
end

--------------------------------------------------------------------------
-- The four knobs every part reinvented
--
-- Zoom, background, width and rows. Each of them had been written once per
-- part, with the range declared at the top of that part's own file, and the
-- copies had drifted: four separate `LOW_ZOOM, HIGH_ZOOM = 1, 3` pairs, three
-- separate 0-to-100-in-fives, and the same idea called `bar opacity` on one
-- page, `background` on two others and `list bars` where every other page says
-- `rows`.
--
-- So the range lives here where the range is genuinely one range, and the label
-- lives here where the label is genuinely one label. Where the range really does
-- differ per caller, which is every pixel measurement, the caller keeps it and
-- this file supplies the unit.
--
-- Every one of these is a composition of Stepper or Slider and nothing else, so
-- they are installed rather than written inside the kit for the same reason the
-- prose is.
--------------------------------------------------------------------------

local function InstallKnobs(kit)
	-- Whole steps, one to three. No label and no range, because there is one of
	-- each: a widget you read mid swing is worth keeping exact, and exact means a
	-- whole number of source texels per screen pixel.
	function kit.Zoom(get, set)
		return kit.Stepper("zoom", UI.ZOOM_LOW, UI.ZOOM_HIGH, 1, get, set,
			function(value) return value .. "x" end)
	end

	-- Nought to a hundred in fives, which is the only range this has ever had.
	function kit.Opacity(label, get, set)
		return kit.Slider(label, UI.ALPHA_LOW, UI.ALPHA_HIGH, UI.ALPHA_STEP, get, set,
			function(value) return value .. "%" end)
	end

	-- Any pixel measurement. The range stays with the caller, because a feed is
	-- 200 to 520 wide and a minimap is 120 to 300 and those differ for real
	-- reasons. The unit does not stay with the caller: it goes after the number
	-- where it belongs, so a label can be `width` on all four pages instead of
	-- `width in pixels` on one and nothing at all on the other three.
	function kit.Size(label, low, high, step, get, set)
		return kit.Stepper(label, low, high, step, get, set,
			function(value) return value .. "px" end)
	end

	-- How many of something. Whole numbers, one at a time.
	function kit.Count(label, low, high, get, set)
		return kit.Stepper(label, low, high, 1, get, set)
	end
end

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

	local function Index(widget, label)
		widget.label = label
		if host.Index then
			host.Index(widget, label)
		end
		return widget
	end

	local ctx = { host = host, Stack = Stack, Parent = Parent,
		Prose = Prose, TextWidth = TextWidth, Remember = Remember }

	function kit.Section(title, group)
		if host.Section then
			return host.Section(title, group)
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

	InstallProse(kit, ctx)

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
		Index(button, label)
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

	-- format turns the value into what the readout says, the same as the
	-- slider's, so a caller can put a unit after the number without this file
	-- learning what the unit means. Left out, the number speaks for itself.
	function kit.Stepper(label, low, high, step, get, set, format)
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

		local minus = UI.Button(row, { label = "-", glyph = true, width = M.control,
			onClick = function() Nudge(-1) end })
		minus:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(M.control + valueWidth + M.rowGap * 2), 0)
		local plus = UI.Button(row, { label = "+", glyph = true, width = M.control,
			onClick = function() Nudge(1) end })
		plus:SetPoint("TOPRIGHT")

		local value = UI.Label(row, M.font, C.heading, "CENTER", UI.FLAT)
		value:SetPoint("TOP", 0, -math.floor((M.control - M.font) / 2))
		value:SetPoint("LEFT", minus, "RIGHT", M.rowGap, 0)
		value:SetPoint("RIGHT", plus, "LEFT", -M.rowGap, 0)

		Index(row, label)
		return Remember(row, function()
			value:SetText(format and format(get()) or tostring(get()))
		end)
	end

	InstallKnobs(kit)

	-- A value you drag
	--
	-- The stepper's sibling, for a setting where the range matters more than the
	-- number: you want it bigger, so you pull it right. A stepper answers "make
	-- it one more"; this answers "make it about that big", and the readout says
	-- where you are while you are still deciding.
	--
	-- Built on the client's own Slider frame type, for the reason UI/Scroll.lua
	-- builds the scrollbar on one: following a cursor means an OnUpdate, and an
	-- OnUpdate is a ticker this addon would then have to defend forever. The
	-- client already tracks the drag and reports it once per step. Slider is a
	-- frame type rather than a template, so it needs no Blizzard XML, but nothing
	-- installed on 2.5.6 proves it takes a thumb texture from a stranger, so it is
	-- probed exactly the way the scrollbar probes it and the row falls back to a
	-- pair of nudge buttons when it refuses. A settings row that cannot be dragged
	-- is worse than one you have to click; a settings row that raises is worse
	-- than both.
	--
	-- format turns the value into what the readout says, so a caller can write
	-- "1.25x" or "18 px" without this file learning what either means. Left out,
	-- the number speaks for itself.
	function kit.Slider(label, low, high, step, get, set, format)
		local trackWidth, valueWidth = 116, 40
		local reserved = trackWidth + valueWidth + M.gutter
		local row, text = Paired(reserved, M.control)
		text:SetText(label)

		local value = UI.Label(row, M.font, C.heading, "RIGHT", UI.FLAT)
		value:SetPoint("TOPRIGHT", 0, -math.floor((M.control - M.font) / 2))
		value:SetWidth(valueWidth)

		local function Show(current)
			value:SetText(format and format(current) or tostring(current))
		end

		local function Commit(current)
			if current < low then
				current = low
			elseif current > high then
				current = high
			end
			-- Snapped here as well as by the client, because the fallback path
			-- has no client to snap it and because a step the slider reports
			-- back is one the saved variable has to be able to hold exactly.
			current = low + math.floor((current - low) / step + 0.5) * step
			if current == get() then
				return
			end
			set(current)
			Changed()
		end

		local track = UI.Box(row, C.sunken, C.edge)
		track:SetSize(trackWidth, M.control)
		track:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(valueWidth + M.gutter), 0)

		-- Everything past the frame itself in one pcall rather than probed method
		-- by method, for the reason UI/Scroll.lua does the same: the thumb is the
		-- one call nothing here can check by asking.
		local function Dress(slider)
			slider:SetOrientation("HORIZONTAL")
			slider:SetPoint("TOPLEFT", track, "TOPLEFT", M.rowGap, 0)
			slider:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", -M.rowGap, 0)
			slider:SetMinMaxValues(low, high)
			slider:SetValueStep(step)
			-- Without this a drag reports every fraction between two stops and
			-- the step applies only to a click, so a slider that is meant to
			-- have eleven positions has as many as the track has pixels.
			if slider.SetObeyStepOnDrag then
				slider:SetObeyStepOnDrag(true)
			end
			slider.thumb = ns.Fill(slider, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
			slider.thumb:SetSize(M.rowGap + 2, M.control - 2)
			slider:SetThumbTexture(slider.thumb)
			slider:SetValue(get())
		end

		-- A refusal puts the error message in the second slot, not a frame, so
		-- the failure is cleared before anything below can mistake a string for
		-- something with a Hide method.
		local made, slider = pcall(CreateFrame, "Slider", nil, track)
		if not made then
			slider = nil
		end
		if slider and type(slider.SetOrientation) == "function"
			and type(slider.SetThumbTexture) == "function" and pcall(Dress, slider) then
			-- Held, and why the setter does not run until it is let go.
			--
			-- The client works a slider's value out from where the cursor is
			-- against where the track is, every frame of the drag. A setter that
			-- resizes the window this row is sitting in therefore moves the
			-- track out from under the cursor, and the next frame reads a value
			-- off the new geometry: the window is centred, so growing it walks
			-- the track sideways by a good fraction of its own width and the
			-- reading collapses or saturates. The two then feed each other and
			-- the thumb slams between the ends of the range for as long as the
			-- button is down. That is not a hypothetical. The UI size row is the
			-- first caller and it is exactly that setter.
			--
			-- So a drag shows and does not commit. The readout follows the thumb
			-- the whole way, and the setting takes the value when the button
			-- comes up, by which point the cursor is no longer arguing with it.
			-- A click on the track and a keyboard nudge are not drags and commit
			-- straight away, because nothing is holding the geometry still.
			slider:SetScript("OnMouseDown", function()
				row.held = true
			end)
			local function Release()
				if not row.held then
					return
				end
				row.held = nil
				Commit(slider:GetValue())
			end
			slider:SetScript("OnMouseUp", Release)
			-- The window can be shut with the button still down, by escape or by
			-- a reload, and the drag then never ends. Committing on the way out
			-- keeps what the player had chosen rather than silently dropping it.
			slider:SetScript("OnHide", Release)
			slider:SetScript("OnValueChanged", function(_, current)
				-- Refresh writes the saved value back onto the slider and that
				-- write fires this. Without the latch the two chase each other
				-- for a frame every time anything else on the page changes.
				if row.syncing then
					return
				end
				if row.held then
					Show(current)
					return
				end
				Commit(current)
			end)
			row.slider = slider
		else
			if slider then
				slider:Hide()
			end
			track:Hide()
			local minus = UI.Button(row, { label = "-", glyph = true, width = M.control,
				onClick = function() Commit(get() - step) end })
			minus:SetPoint("TOPRIGHT", row, "TOPRIGHT",
				-(M.control + valueWidth + M.gutter + M.rowGap), 0)
			local plus = UI.Button(row, { label = "+", glyph = true, width = M.control,
				onClick = function() Commit(get() + step) end })
			plus:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(valueWidth + M.gutter), 0)
		end

		Index(row, label)
		return Remember(row, function()
			local current = get()
			if row.slider then
				row.syncing = true
				row.slider:SetValue(current)
				row.syncing = nil
			end
			Show(current)
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

		Index(row, label)
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

		local arrow = UI.Glyph(button, M.glyph, C.dim, "RIGHT")
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

		Index(row, label)
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

		Index(button, getLabel)
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

		-- Two entries on one row, because a pair is two things you can do and
		-- searching for either has to land you here.
		Index(row, leftLabel)
		Index(row, rightLabel)

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

		local field = UI.KeyBox(row, { width = fieldWidth, getText = getText,
			onKey = onKey, after = Changed })
		field:SetPoint("TOPRIGHT", clear, "TOPLEFT", -M.rowGap, 0)

		Index(field, label)
		return Remember(field, field.Update)
	end

	-- The kit's own squares refresh the page they sit on. Everything else about
	-- one is in UI.DropSquare.
	local function GearSquare(parent, size, get, set, opts)
		opts = opts or {}
		opts.after = Changed
		return UI.DropSquare(parent, size, get, set, opts)
	end

	-- The character, and the hands under it
	--
	-- Blizzard's own model of the player, framed in the addon's own box, with a
	-- gear square per hand below it wearing Blizzard's slot art and slot ring.
	-- This is the paperdoll and it is meant to read as one: a weapon set is
	-- something you look at rather than a pair of names in a list.
	--
	-- PlayerModel is a frame type rather than a template, so it costs nothing
	-- to exist on 2.5.6, and SetUnit is probed anyway. A client that will not
	-- draw a model leaves an empty box and the slots underneath still work,
	-- which is the honest degradation.
	--
	-- SetUnit is called once and again when the model is shown, never on a
	-- refresh, because it reloads the model and a refresh is every click
	-- anywhere in the window.
	function kit.Paperdoll(opts)
		opts = opts or {}
		local slots = opts.slots or {}
		local modelW, modelH, size = 132, 156, 40
		local caption = M.small + 3
		local height = modelH + M.gutter + size + caption

		local row = CreateFrame("Frame", nil, Parent())
		local stack = Stack()

		local frame = UI.Box(row, C.sunken, C.edge)
		frame:SetSize(modelW, modelH)
		frame:SetPoint("TOP")

		local model = CreateFrame("PlayerModel", nil, frame)
		model:SetPoint("TOPLEFT", 2, -2)
		model:SetPoint("BOTTOMRIGHT", -2, 2)
		local function Dress()
			if model.SetUnit then
				pcall(model.SetUnit, model, "player")
			end
		end
		model:SetScript("OnShow", Dress)
		Dress()

		-- Laid out from the middle out, so two slots straddle the model's centre
		-- line the way the client's own hand row does.
		local squares = {}
		local span = #slots * size + math.max(#slots - 1, 0) * M.gutter
		for index, slot in ipairs(slots) do
			local square = GearSquare(row, size, slot.get, slot.set,
				{ empty = slot.empty, enabled = slot.enabled, ring = true })
			square:SetPoint("TOP", frame, "BOTTOM", -span / 2 + (index - 1) * (size + M.gutter) + size / 2, -M.gutter)

			local label = UI.Label(row, M.small, C.dim, "CENTER", UI.FLAT)
			UI.Wrap(label, false)
			label:SetPoint("TOP", square, "BOTTOM", 0, -2)
			label:SetWidth(size + M.gutter * 2)
			label:SetText(slot.label or "")
			squares[index] = square
		end

		stack:Add(row, { indent = M.indent, height = height, stretch = true })

		return Remember(row, function()
			for index = 1, #squares do
				squares[index].Refresh()
			end
		end)
	end

	-- A strip of buttons where one is chosen
	--
	-- The window's own tab strip is chrome: it is built once at login out of
	-- the headers a feature writes, and it cannot grow. This one is a control.
	-- The list it shows is a setting, so it grows and shrinks while the window
	-- is open, and it lays out from a pool rather than making a button per
	-- refresh. Blizzard's character sheet puts the same strip along the foot of
	-- the paperdoll, which is where this one is meant to sit.
	--
	-- getOptions returns the labels, get returns the chosen index, set takes
	-- one. opts.onAdd puts a + at the end and calls back when it is pressed.
	function kit.Tabs(getOptions, get, set, opts)
		opts = opts or {}
		local row = CreateFrame("Frame", nil, Parent())
		local stack = Stack()
		local pool, add, width = {}, nil, 0

		local function Paint(button, chosen)
			button.mark:SetShown(chosen)
			UI.Tint(button.bg, chosen and C.selected or C.chrome)
			local color = chosen and C.text or C.dim
			button.text:SetTextColor(color[1], color[2], color[3])
		end

		-- One tab. The last one is the plus that makes a new loadout and it is a
		-- mark rather than a word, which is the only thing the flag decides.
		local function Make(onClick, glyph)
			local button = CreateFrame("Button", nil, row)
			button:SetHeight(M.tab)
			button.bg = ns.Fill(button, "BACKGROUND", C.chrome[1], C.chrome[2], C.chrome[3], 1)
			button.bg:SetAllPoints()
			button.mark = ns.Fill(button, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
			button.mark:SetPoint("TOPLEFT")
			button.mark:SetPoint("TOPRIGHT")
			button.mark:SetHeight(2)
			if glyph then
				button.text = UI.Glyph(button, M.glyph, C.dim, "CENTER")
			else
				button.text = UI.Label(button, M.small, C.dim, "CENTER", UI.FLAT)
			end
			button.text:SetPoint("CENTER")
			UI.Wrap(button.text, false)
			button:SetScript("OnClick", onClick)
			return button
		end

		-- Every button is placed on every layout rather than only the ones that
		-- moved, because one label getting longer moves every button after it.
		local function Layout(room)
			width = room
			local options = getOptions()
			local chosen = get()
			local x, lines = 0, 1

			local function Place(button)
				local size = UI.Round(row, (button.text:GetStringWidth() or 0) + M.gutter * 2)
				if size > room then
					size = room
				end
				if x > 0 and x + size > room then
					x = 0
					lines = lines + 1
				end
				button:SetWidth(math.max(size, 1))
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", row, "TOPLEFT", x, -((lines - 1) * (M.tab + M.rowGap)))
				button:Show()
				x = x + size + M.rowGap
			end

			for index = 1, #options do
				local button = pool[index]
				if not button then
					button = Make(function(this)
						set(this.index)
						Changed()
					end)
					pool[index] = button
				end
				button.index = index
				button.text:SetText(options[index])
				Paint(button, index == chosen)
				Place(button)
			end
			for index = #options + 1, #pool do
				pool[index]:Hide()
			end

			if opts.onAdd then
				if not add then
					add = Make(function()
						opts.onAdd()
						Changed()
					end, true)
					add.text:SetText("+")
				end
				Paint(add, false)
				Place(add)
			end

			return lines * M.tab + (lines - 1) * M.rowGap
		end

		stack:Add(row, {
			indent = M.indent,
			measure = function(this)
				return Layout(math.max(1, stack.width - this.indent))
			end,
		})

		return Remember(row, function()
			if width > 0 then
				Layout(width)
			end
		end)
	end

	-- A line of text you type
	--
	-- An EditBox with no template, the way everything else here is a frame with
	-- no template. It commits on enter and on losing focus rather than on every
	-- keystroke, because the setter is a saved variable and a half typed name is
	-- not one.
	function kit.TextField(label, get, set)
		local fieldWidth = 168
		local row, text = Paired(fieldWidth, M.control)
		text:SetText(label)

		local box = UI.Box(row, C.sunken, C.edge)
		box:SetSize(fieldWidth, M.control)
		box:SetPoint("TOPRIGHT")

		local edit = CreateFrame("EditBox", nil, box)
		edit:SetPoint("TOPLEFT", 4, 0)
		edit:SetPoint("BOTTOMRIGHT", -4, 0)
		edit:SetFontObject(UI.Font(M.font, UI.FLAT))
		edit:SetTextColor(C.text[1], C.text[2], C.text[3])
		edit:SetAutoFocus(false)
		edit:SetMaxLetters(24)

		local function Commit(self)
			set(self:GetText())
			Changed()
		end
		edit:SetScript("OnEnterPressed", function(self)
			self:ClearFocus()
			Commit(self)
		end)
		edit:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
			Changed()
		end)
		edit:SetScript("OnEditFocusLost", function(self)
			UI.StopTyping()
			Commit(self)
		end)
		edit:SetScript("OnEditFocusGained", function(self)
			UI.CloseDropdown()
			UI.StopCapture()
			UI.Typing(self)
			UI.Tint(box.bg, C.selected)
		end)
		edit:SetScript("OnHide", function(self)
			self:ClearFocus()
		end)

		Index(row, label)
		return Remember(row, function()
			-- Never while it is being typed into, or every refresh would put the
			-- saved value back under the cursor.
			if not edit:HasFocus() then
				edit:SetText(get() or "")
				UI.Tint(box.bg, C.sunken)
			end
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
		-- A custom row that carries controls says what it is called, the same as
		-- every other control does, or search cannot reach it. Rows that are
		-- rows of data rather than controls pass no label and stay out of the
		-- index, which is what every caller before this one did.
		if opts.label then
			Index(row, opts.label)
		end
		if opts.refresh then
			Remember(row, opts.refresh)
		end
		return row, cell
	end

	return kit
end
