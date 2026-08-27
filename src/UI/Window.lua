local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- Windows, rails and tab strips
--
-- The chrome, and the two pieces of navigation that go in it. A window is a
-- titled, draggable, escape-closing rectangle with a content area and a footer.
-- A rail is a column of choices down the left. A tab strip is a row of choices
-- across the top of whatever the rail chose.
--
-- All three are here rather than in the options panel because none of them
-- knows what a setting is, and the next window this addon grows, an aura list,
-- a loot log, a profile browser, wants the same three and should not be
-- copying them out of a file called Panel.lua.
--
-- **A window is adopted onto the pixel grid.** It is a frame the addon owns
-- outright, anchored to UIParent, so unlike a nameplate it can be exact in both
-- size and position, and every number in UI.Metric is then a count of physical
-- pixels. The cost is the cost the enemy bars already pay: a window 540 pixels
-- wide is 540 pixels on a laptop and 540 on a 4K panel, which on the 4K panel
-- is small. Zoom is the answer there, and it comes from two places that
-- multiply: UI.ScreenZoom, a whole step the screen height picks on its own, and
-- UI.Size, the slider the player drags in the settings panel. A screen that
-- doubles everything and a player who halves it land back on the design size,
-- which is the arithmetic you want and the reason they are one number by the
-- time a window sees them.
--
-- **The size is deliberate and the window does not resize.** The old panel grew
-- to whatever its tallest page needed, which on this screen was 773 physical
-- pixels of a 1440 pixel monitor for a settings window, and then scaled itself
-- down when that overflowed, which shrank the text to buy room for settings
-- nobody was reading. This one is a fixed rectangle: a section that does not fit
-- scrolls. A drag handle to resize it would mean a saved size, a minimum, a
-- maximum, and a reflow of every section on every mouse move, to buy what the
-- scrollbar already gives.
--------------------------------------------------------------------------

-- Every window the library has made, in creation order. Nothing in the addon
-- reads it yet. It exists because a UI layer that means to own the screen has
-- to be able to answer "what is open", and because the harness drives the
-- options panel through it rather than through a hook cut into the panel for
-- the harness's benefit.
UI.Windows = {}

-- What the screen asks for, before the player has said anything. Whole steps
-- only: below a 1600 pixel tall screen the pixel metrics are already
-- comfortable, above 2000 they are half the size they should be, and a
-- fractional step chosen on the player's behalf would put every edge in the
-- window onto a half pixel to buy a size nobody asked for.
function UI.ScreenZoom()
	local height = UI.ScreenHeight()
	if height >= 2000 then
		return 2
	end
	return 1
end

-- What the player asked for on top of that, which is the UI size slider in the
-- settings panel. It is held here rather than read out of ns.db, because this
-- layer is not allowed to know the name of a setting: Settings/Settings.lua
-- reads the saved value and pushes it in, the same way a widget takes a getter
-- rather than a key.
--
-- The two multiply. On a 4K panel the screen has already doubled everything, so
-- half size lands back on the design size and is exact; on a 1080p panel the
-- screen contributes 1 and half size is genuinely half. That is the behaviour
-- you want from a control called "UI size": it says how big this looks to you,
-- not how many pixels went into it.
local chosen = 1

function UI.Size()
	return chosen
end

-- Every window on the grid is re-zoomed by its own rescale listener, which is
-- the same path a monitor swap takes, so this only has to say that the ground
-- moved. Returns whether it did: an unchanged size relays out nothing.
function UI.SetSize(scale)
	scale = tonumber(scale) or 1
	if scale == chosen then
		return false
	end
	chosen = scale
	UI.Notify()
	return true
end

function UI.WindowZoom()
	return UI.ScreenZoom() * chosen
end

-- Whether one unit is a whole number of physical pixels at the zoom in force.
-- The window is exact only when the product is, which is why the screen's own
-- step is whole and why the panel says out loud which stops of the slider are
-- and which are not.
function UI.Exact(zoom)
	zoom = zoom or UI.WindowZoom()
	return math.abs(zoom - math.floor(zoom + 0.5)) < 1e-6
end

local Window = {}
Window.__index = Window

function UI.Window(opts)
	local window = setmetatable({}, Window)
	local zoom = opts.zoom or UI.WindowZoom()

	local frame = CreateFrame("Frame", opts.name, UIParent)
	window.frame = frame
	window.zoom = zoom
	UI.Adopt(frame, zoom)

	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetClampedToScreen(true)
	-- DIALOG unless the caller says otherwise. A settings window is something
	-- you open over the game and close again, and DIALOG is where that belongs.
	-- A window that is up while you play, which is what the chat window is, has
	-- to sit under the tooltip and under anything the client puts over the
	-- world, so it asks for a lower one.
	frame:SetFrameStrata(opts.strata or "DIALOG")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	-- A listening key field has the keyboard and an open dropdown covers
	-- whatever is under it, so a click anywhere else in the window has to be a
	-- way out of both. Each of them eats its own click, so this never cancels the
	-- click that opened it.
	frame:SetScript("OnMouseDown", function()
		UI.StopCapture()
		UI.CloseDropdown()
	end)
	-- Escape closes the window through UISpecialFrames, which calls Hide on the
	-- frame and knows nothing about the dropdown that is open over it or the key
	-- field that has the keyboard. So the cleanup hangs off the frame rather than
	-- off the Hide method, and every route out of the window goes through it.
	frame:SetScript("OnHide", function()
		UI.StopCapture()
		UI.CloseDropdown()
	end)
	frame:Hide()

	-- Kept on the window rather than left local, because how opaque a window is
	-- is a property of that window. The panel wants to be read and takes the
	-- palette's own alpha; a chat window sits over the world all night and the
	-- player decides how much of the world comes through it.
	window.bg = ns.Fill(frame, "BACKGROUND", C.window[1], C.window[2], C.window[3], C.window[4])
	window.bg:SetAllPoints()
	window.edges = ns.Outline(frame, C.edge[1], C.edge[2], C.edge[3], 1)
	local px = ns.Pixel(frame)
	ns.EdgeSize(window.edges, px)

	local bar = ns.Fill(frame, "ARTWORK", C.chrome[1], C.chrome[2], C.chrome[3], 1)
	bar:SetPoint("TOPLEFT", px, -px)
	bar:SetPoint("TOPRIGHT", -px, -px)
	bar:SetHeight(M.title)

	window.title = UI.Label(frame, M.heading, C.heading, "LEFT", UI.FLAT)
	window.title:SetPoint("TOPLEFT", M.pad, -math.floor((M.title - M.heading) / 2) - px)
	window.title:SetText(opts.title or "")

	window.close = UI.Button(frame, { label = "x", glyph = true,
		width = M.title - 8, height = M.title - 8,
		onClick = function() window:Hide() end })
	window.close:SetPoint("TOPRIGHT", -4, -4)

	-- Everything between the title bar and the footer. Content parents to this,
	-- so nothing below has to know how tall the chrome is.
	window.content = CreateFrame("Frame", nil, frame)
	window.content:SetPoint("TOPLEFT", 0, -M.title)

	window.footer = CreateFrame("Frame", nil, frame)
	window.footer:SetPoint("BOTTOMLEFT", M.pad, 0)
	window.footer:SetPoint("BOTTOMRIGHT", -M.pad, 0)
	window.footer:SetHeight(M.footer)
	window.footerRule = UI.Rule(frame, C.hairline)
	window.footerRule:SetPoint("BOTTOMLEFT", M.pad, M.footer)
	window.footerRule:SetPoint("BOTTOMRIGHT", -M.pad, M.footer)

	window:Resize(opts.width or 540, opts.height or 450)

	-- Escape closes it, the same as any Blizzard window. The name is what
	-- UISpecialFrames holds, so a window that wants the behaviour has to have one.
	--
	-- opts.escape = false opts out, and the chat window is why. Escape is the
	-- key that clears a targeting cursor and steps out of a text field, and a
	-- window you have up all evening must not be what it closes instead.
	if opts.name and opts.escape ~= false then
		tinsert(UISpecialFrames, opts.name)
	end

	UI.Windows[#UI.Windows + 1] = window
	return window
end

-- The requested size, clamped to what the screen can hold. Both numbers are in
-- the window's own units, which after adoption are physical pixels divided by
-- the zoom, so the screen has to be converted into them before they can be
-- compared.
function Window:Resize(width, height)
	-- On the grid the window's units are pixels over the zoom, so the screen has
	-- to be converted into them. Off it, on a client with no
	-- SetIgnoreParentScale, the window is in UIParent's units and UIParent is
	-- what to ask. Getting this the wrong way round on the second client puts a
	-- window taller than the screen on it and nothing here would say so.
	local room = UI.Supported() and (UI.ScreenHeight() / self.zoom) or UIParent:GetHeight()
	local budget = math.floor((room or UI.ScreenHeight()) * 0.86)
	if height > budget then
		height = budget
	end

	self.width, self.height = width, height
	self.frame:SetSize(width, height)
	self.content:SetSize(width, height - M.title - M.footer)
	return width, height
end

-- A search field in the title bar.
--
-- Chrome rather than a widget, because it belongs to the window and not to any
-- page in it: what it searches is everything the window holds, and a control
-- that lives on one page cannot say anything about the other forty four.
--
-- opts.onType is called on every keystroke with the whole field. Filtering as
-- you type rather than on enter, because a settings window is something you
-- rummage in: you type two letters, see whether it is there, and type two more.
function Window:Search(opts)
	local width = opts.width or 150
	local height = M.title - 8

	local box = UI.Box(self.frame, C.sunken, C.edge)
	box:SetSize(width, height)
	box:SetPoint("TOPRIGHT", self.close, "TOPLEFT", -M.rowGap, 0)

	local ghost = UI.Label(box, M.small, C.quiet, "LEFT", UI.FLAT)
	ghost:SetPoint("LEFT", 4, 0)
	ghost:SetText(opts.placeholder or "search")

	local edit = CreateFrame("EditBox", nil, box)
	edit:SetPoint("TOPLEFT", 4, 0)
	edit:SetPoint("BOTTOMRIGHT", -4, 0)
	edit:SetFontObject(UI.Font(M.small, UI.FLAT))
	edit:SetTextColor(C.text[1], C.text[2], C.text[3])
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(40)

	edit:SetScript("OnTextChanged", function(field)
		ghost:SetShown(field:GetText() == "")
		opts.onType(field:GetText())
	end)
	-- Escape empties the field before it closes the window, so the first press
	-- puts the page back and the second is the one that leaves.
	edit:SetScript("OnEscapePressed", function(field)
		if field:GetText() ~= "" then
			field:SetText("")
			return
		end
		field:ClearFocus()
	end)
	edit:SetScript("OnEnterPressed", function(field)
		if opts.onEnter then
			opts.onEnter(field:GetText())
		end
	end)
	edit:SetScript("OnEditFocusGained", function()
		UI.CloseDropdown()
		UI.StopCapture()
		UI.Tint(box.bg, C.selected)
	end)
	edit:SetScript("OnEditFocusLost", function()
		UI.Tint(box.bg, C.sunken)
	end)

	self.search = edit
	return edit
end

function Window:SetTitle(text)
	self.title:SetText(text)
end

-- How much of the world comes through the window, as a fraction of the
-- palette's own alpha rather than instead of it. A window at 1 is the window
-- the theme describes; below that it is the same colour, thinner.
function Window:SetOpacity(fraction)
	local alpha = (C.window[4] or 1) * math.max(0, math.min(fraction or 1, 1))
	self.bg:SetColorTexture(C.window[1], C.window[2], C.window[3], alpha)
end

function Window:Show()
	self.frame:Show()
end

function Window:Hide()
	UI.CloseDropdown()
	UI.StopCapture()
	self.frame:Hide()
end

function Window:IsShown()
	return self.frame:IsShown()
end

--------------------------------------------------------------------------
-- The rail
--
-- A column down the left edge that folds. Eight groups, and the one you are in
-- stands open with its sections listed under it, indented. Choosing a section
-- is one click on the thing you came for rather than a click on the rail and a
-- second one on a strip of tabs across the top of the page.
--
-- The strip was the thing this replaced and it had two faults a fold does not.
-- It could only show the sections of the group you were already on, so the
-- window never showed more than an eighth of itself at once. And a group with
-- eleven of them wrapped onto three lines of stubs, which took a fifth of the
-- page's height to say what a column says in a column.
--
-- One group is open at a time. Clicking a shut one opens it onto whichever
-- section you were last reading there; clicking the open one shuts it, and the
-- page stays up with the group's own row carrying the mark instead. So the rail
-- can be folded flat to eight lines without the window going blank.
--
-- It sits in a scroll view of its own, because open is taller than shut: eight
-- groups fit the rail with room over, and eight plus the eleven sections of
-- Fighting do not. Reveal keeps whatever is selected inside the viewport, so
-- opening a long group never scrolls the chosen row off the bottom.
--------------------------------------------------------------------------

local Rail = {}
Rail.__index = Rail

-- The fold mark. A chevron down when the group is open and a chevron right when
-- it is shut, drawn out of Media/Glyphs.ttf by UI.Glyph. The letters here are
-- the letters that face cuts the two chevrons onto, and they are also what you
-- see if the file does not load, which is the whole reason it is done this way.
local OPEN, SHUT = "v", ">"

-- The column the fold mark sits in, and the step a section hangs under its
-- group. One number for both, because the two have to agree: a chevron is
-- nearly a full em wide where the letter it replaced was a third of one, and
-- the first version of this put the mark and the group's own name in the same
-- four pixels.
local FOLD = M.rowGap + M.glyph + M.rowGap

local function PaintRail(button)
	local shade = button.selected and C.selected or (button.hovered and C.hover or C.rail)
	UI.Tint(button.bg, shade)
	button.mark:SetShown(button.selected and true or false)
	if button.dot then
		button.dot:SetShown(button.dot.lit and true or false)
	end
	if button.fold then
		button.fold:SetText(button.open and OPEN or SHUT)
	end

	-- Three shades rather than two. A section that is showing is the heading
	-- colour, an open group is the body colour because it is the heading of a
	-- list you are reading, and everything shut is dim.
	local color = C.dim
	if button.selected then
		color = C.heading
	elseif button.open then
		color = C.text
	end
	button.text:SetTextColor(color[1], color[2], color[3])
end

function UI.Rail(parent, opts)
	local rail = setmetatable({ groups = {}, onSelect = opts and opts.onSelect }, Rail)
	rail.frame = CreateFrame("Frame", nil, parent)
	local bg = ns.Fill(rail.frame, "BACKGROUND", C.rail[1], C.rail[2], C.rail[3], 1)
	bg:SetAllPoints()

	rail.view = UI.ScrollView(rail.frame)
	rail.view.frame:SetPoint("TOPLEFT", M.rowGap, -M.rowGap)
	rail.stack = UI.Stack(rail.view.canvas)
	return rail
end

-- The half of a row that is the same whichever kind it is. A row is built once
-- and kept: a frame cannot be destroyed on this client, so folding hides rows
-- and rebuilds the column's cell list rather than unmaking anything.
local function RailRow(rail, left)
	local button = CreateFrame("Button", nil, rail.stack.frame)
	button.bg = ns.Fill(button, "BACKGROUND", C.rail[1], C.rail[2], C.rail[3], 1)
	button.bg:SetAllPoints()
	button.mark = ns.Fill(button, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
	button.mark:SetPoint("TOPLEFT")
	button.mark:SetPoint("BOTTOMLEFT")
	button.mark:SetWidth(2)

	button.text = UI.Label(button, M.font, C.dim, "LEFT", UI.FLAT)
	button.text:SetPoint("LEFT", left, 0)
	UI.Wrap(button.text, false)

	button:SetScript("OnEnter", function(this)
		this.hovered = true
		PaintRail(this)
	end)
	button:SetScript("OnLeave", function(this)
		this.hovered = nil
		PaintRail(this)
	end)
	return button
end

function Rail:Add(label)
	local at = #self.groups + 1
	local group = { at = at, children = {}, current = 1 }
	local button = RailRow(self, FOLD)

	-- The fold, in the margin the indent leaves free on the rows below it, so a
	-- group's own letters and its sections' letters do not start in the same
	-- column and the shape of the list is legible with the words unread.
	button.fold = UI.Glyph(button, M.glyph, C.quiet, "LEFT")
	button.fold:SetPoint("LEFT", M.rowGap, 0)
	UI.Wrap(button.fold, false)

	-- Whether anything filed under this group is drawing on your screen. Three
	-- pixels in the accent colour against the right edge, which is the one part
	-- of a rail row nothing else uses. It is the single question the window
	-- could never answer without opening forty five tabs.
	button.dot = ns.Fill(button, "OVERLAY", C.accent[1], C.accent[2], C.accent[3], 1)
	button.dot:SetSize(3, 3)
	button.dot:SetPoint("RIGHT", -M.rowGap, 0)
	button.dot:Hide()
	button.text:SetPoint("RIGHT", button.dot, "LEFT", -M.rowGap, 0)
	button.text:SetText(label)

	-- What the label has to fit in: the row less the fold on the left, the dot on
	-- the right and the air round both. Recorded rather than worked out again,
	-- because the gate that refuses a rail line too long to read has to measure
	-- against the same number the anchors above use.
	button.room = FOLD + 3 + M.rowGap * 2

	button:SetScript("OnClick", function()
		self:Toggle(at)
	end)

	group.button = button
	PaintRail(button)
	self.groups[at] = group
	return at
end

function Rail:AddChild(at, label)
	local group = self.groups[at]
	if not group then
		return nil
	end
	local index = #group.children + 1
	local button = RailRow(self, M.gutter)
	button.text:SetPoint("RIGHT", -M.rowGap, 0)
	button.text:SetText(label)
	button.room = M.gutter + M.rowGap
	button:SetScript("OnClick", function()
		self:Select(at, index)
	end)
	PaintRail(button)
	group.children[index] = button
	return index
end

-- The column, rebuilt from what is open. Cells are thrown away and re-added
-- rather than shown and hidden in place, because a hidden frame still holds its
-- cell's height and the fold would cost nothing at all.
function Rail:Layout()
	self.stack.cells = {}
	for _, group in ipairs(self.groups) do
		self.stack:Add(group.button, { height = M.railRow, gap = 1 })
		for _, child in ipairs(group.children) do
			child:SetShown(group.open and true or false)
			if group.open then
				self.stack:Add(child, { height = M.railRow, gap = 1, indent = FOLD })
			end
		end
	end
	-- Nothing has said how big the rail is until Resize runs, and the window
	-- chooses its first line before that. So the column is laid out and the
	-- viewport is told about it only once there is a viewport to tell.
	self.stack:SetWidth(self.view.width or 0)
	local extent = self.stack:Reflow()
	if self.view.height then
		self.view:Update(extent)
	end
end

function Rail:Paint()
	for at, group in ipairs(self.groups) do
		local holds = (at == self.selected)
		group.button.open = group.open
		group.button.selected = holds and not group.open
		PaintRail(group.button)
		for index, child in ipairs(group.children) do
			child.selected = holds and group.open and index == self.section
			PaintRail(child)
		end
	end
end

-- Keep a row inside the viewport. Opening the longest group puts its last
-- sections below the fold, and a selection you cannot see is a rail that has
-- stopped saying where you are.
function Rail:Reveal(button)
	if not self.view.height then
		return false
	end
	local top = 0
	for _, cell in ipairs(self.stack.cells) do
		if cell.frame == button then
			if top < self.view.offset then
				self.view:ScrollTo(top)
			elseif top + cell.height > self.view.offset + self.view.height then
				self.view:ScrollTo(top + cell.height - self.view.height)
			end
			return true
		end
		top = top + cell.height + cell.gap
	end
	return false
end

function Rail:Resize(width, height)
	self.frame:SetSize(width, height)
	self.view:Resize(width - M.rowGap * 2, height - M.rowGap * 2)
	self:Layout()
end

-- Whether this group holds something that is on. Returns whether it changed, so
-- a caller refreshing every group does not repaint the eight of them every time
-- anything anywhere in the window is clicked.
function Rail:SetDot(at, lit)
	local group = self.groups[at]
	if not group or (group.button.dot.lit and true or false) == (lit and true or false) then
		return false
	end
	group.button.dot.lit = lit and true or false
	PaintRail(group.button)
	return true
end

-- A section, named by its group and its place in it. The section is optional
-- and defaults to whichever one that group was last left on, which is what a
-- click on a folded group means.
function Rail:Select(at, index)
	local group = self.groups[at]
	if not group then
		return false
	end
	index = index or group.current or 1
	if not group.children[index] then
		return false
	end

	for _, other in ipairs(self.groups) do
		other.open = (other == group)
	end
	group.current = index
	self.selected, self.section = at, index

	self:Layout()
	self:Paint()
	-- Told first, revealed second. What the window does with the choice is lay
	-- itself out again, and that hands the rail its size, so a scroll worked out
	-- before it would be worked out against the last one.
	if self.onSelect then
		self.onSelect(at, index)
	end
	self:Reveal(group.children[index])
	return true
end

-- What a click on a group row does. Open it onto where you left it, or shut the
-- one that is already open and leave its page up.
function Rail:Toggle(at)
	local group = self.groups[at]
	if not group then
		return false
	end
	if not group.open then
		return self:Select(at, group.current)
	end
	group.open = false
	self:Layout()
	self:Paint()
	return true
end

--------------------------------------------------------------------------
-- The tab strip
--
-- A row of choices across the top of a window or a page, one per thing behind
-- it. The options window used to navigate with one and now folds its rail
-- instead; what is left are the two places a strip is the right shape: the chat
-- window's channels, and the list of loadouts inside one page of the panel.
-- Both are short, both are one word each, and neither is the top level of
-- anything.
--
-- Each tab is as wide as its own title, because a title is what a tab is for
-- and cutting it in half to make the row tidy loses the only information on it.
-- A row that runs out of width wraps onto the next one and the strip grows by a
-- whole tab, so eight of them is a taller strip rather than eight unreadable
-- stubs.
--------------------------------------------------------------------------

local TABPAD = 10

local Tabs = {}
Tabs.__index = Tabs

local function PaintTab(button)
	if button.selected then
		UI.Tint(button.bg, C.selected)
		button.text:SetTextColor(C.heading[1], C.heading[2], C.heading[3])
	elseif button.hovered then
		UI.Tint(button.bg, C.hover)
		button.text:SetTextColor(C.text[1], C.text[2], C.text[3])
	elseif button.unread then
		-- A tab you are not on with something on it reads as the selected tab
		-- reads, minus the accent bar under it. Anything louder is a chat window
		-- that flashes at you all night; anything quieter is a tab you never
		-- notice, which is the whole reason the mark exists.
		UI.Tint(button.bg, C.chrome)
		button.text:SetTextColor(C.text[1], C.text[2], C.text[3])
	else
		UI.Tint(button.bg, C.chrome)
		button.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
	end
	button.mark:SetShown(button.selected and true or false)
	button.dot:SetShown(button.unread and not button.selected)
end

function UI.TabStrip(parent, opts)
	local tabs = setmetatable({ buttons = {}, onSelect = opts and opts.onSelect }, Tabs)
	tabs.frame = CreateFrame("Frame", nil, parent)
	tabs.rule = UI.Rule(tabs.frame, C.hairline)
	tabs.rule:SetPoint("BOTTOMLEFT")
	tabs.rule:SetPoint("BOTTOMRIGHT")
	return tabs
end

function Tabs:Add(label)
	local index = #self.buttons + 1
	local button = CreateFrame("Button", nil, self.frame)
	button:SetHeight(M.tab)
	button.bg = ns.Fill(button, "BACKGROUND", C.chrome[1], C.chrome[2], C.chrome[3], 1)
	button.bg:SetAllPoints()
	button.mark = ns.Fill(button, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
	button.mark:SetPoint("BOTTOMLEFT")
	button.mark:SetPoint("BOTTOMRIGHT")
	button.mark:SetHeight(2)

	-- What says a tab has something on it. Two pixels in the accent colour in
	-- the top right corner of the tab, which is a corner nothing else uses.
	button.dot = ns.Fill(button, "OVERLAY", C.accent[1], C.accent[2], C.accent[3], 1)
	button.dot:SetSize(3, 3)
	button.dot:SetPoint("TOPRIGHT", -3, -3)
	button.dot:Hide()

	button.text = UI.Label(button, M.font, C.dim, "CENTER", UI.FLAT)
	button.text:SetPoint("CENTER")
	UI.Wrap(button.text, false)
	button.text:SetText(label)

	button:SetScript("OnClick", function()
		self:Select(index)
	end)
	button:SetScript("OnEnter", function(this)
		this.hovered = true
		PaintTab(this)
	end)
	button:SetScript("OnLeave", function(this)
		this.hovered = nil
		PaintTab(this)
	end)

	PaintTab(button)
	self.buttons[index] = button
	return index
end

-- Lays the row out and returns how tall the strip ended up, which is one tab
-- per line of them. The caller has to take that answer and give the rest of the
-- height to the content, because a strip that wrapped and was not asked would
-- draw over the first row of the page.
function Tabs:Resize(width)
	local x, y, lines = 0, 0, 1
	local shown = 0

	for index = 1, #self.buttons do
		local button = self.buttons[index]
		if button.hidden then
			button:Hide()
		else
			shown = shown + 1
			local text = button.text:GetStringWidth() or 0
			local size = UI.Round(self.frame, text + TABPAD * 2)
			if size > width then
				size = width
			end
			if x > 0 and x + size > width then
				x = 0
				y = y + M.tab
				lines = lines + 1
			end
			button:SetWidth(size)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
			button:Show()
			x = x + size
		end
	end

	local height = lines * M.tab + M.hairline
	self.frame:SetSize(width, height)
	self.shown = shown
	return height
end

-- A tab can be renamed after it exists, because a page's first section is made
-- before the page's builder has said what it is called.
function Tabs:SetLabel(index, label)
	if self.buttons[index] then
		self.buttons[index].text:SetText(label)
	end
end

-- A tab that is not there yet.
--
-- The strip is built once, because a frame cannot be destroyed on this client
-- and rebuilding one would leak a button every time the strip changed. So a tab
-- whose contents do not exist is hidden rather than unmade, and Resize skips it
-- so the tabs after it close the gap. The chat window's people tab is the only
-- caller: it is not drawn until there is somebody on the list.
function Tabs:SetShown(index, shown)
	local button = self.buttons[index]
	if not button then
		return false
	end
	button.hidden = not shown
	return true
end

function Tabs:IsShown(index)
	local button = self.buttons[index]
	return button ~= nil and not button.hidden
end

-- Whether a tab has something on it you have not looked at. Selecting a tab
-- clears its own mark, because looking at it is what unread means.
function Tabs:SetUnread(index, unread)
	local button = self.buttons[index]
	if not button or (button.unread and true or false) == (unread and true or false) then
		return false
	end
	button.unread = unread and true or false
	PaintTab(button)
	return true
end

function Tabs:Select(index)
	if not self.buttons[index] then
		return false
	end
	self.selected = index
	for i = 1, #self.buttons do
		self.buttons[i].selected = (i == index)
		if i == index then
			self.buttons[i].unread = false
		end
		PaintTab(self.buttons[i])
	end
	if self.onSelect then
		self.onSelect(index)
	end
	return true
end


--------------------------------------------------------------------------
-- The list
--
-- A column of rows down the left of a window, where the rows change while the
-- window is open. That is the whole difference between this and the rail above
-- it, and it is why there are two of them rather than one with a flag.
--
-- The rail is the options window's: forty five sections that are known at load,
-- built once, folded and unfolded. The list is the chat window's: a room per
-- conversation, and the set of conversations changes every time you join a
-- party, leave a guild, or get a whisper from somebody you have never spoken to.
-- Folding is not the question there. What is drawn at all is.
--
-- So a caller hands over the rows it wants and gets them, and this file works
-- out which frames to reuse. A frame cannot be destroyed on this client, so
-- rows are pooled and the ones past the end are hidden rather than unmade,
-- which is the same trick the loadout tabs use and for the same reason.
--
-- A row is one of two things. A header is a dim word with no background and no
-- click, there to say what the rows under it are. An entry is a button with a
-- label, an accent mark down its left edge when it is the one you are reading,
-- and a count on the right when it holds something you have not read.
--
-- Rows are addressed by a string id rather than by position, because the
-- position of a whisper moves every time somebody else whispers you and the
-- selection has to survive that.
--------------------------------------------------------------------------

local List = {}
List.__index = List

local function PaintListRow(button)
	if button.header then
		UI.Tint(button.bg, C.rail)
		button.text:SetTextColor(C.quiet[1], C.quiet[2], C.quiet[3])
		button.mark:Hide()
		button.badge:Hide()
		return
	end

	local shade = button.selected and C.selected or (button.hovered and C.hover or C.rail)
	UI.Tint(button.bg, shade)
	button.mark:SetShown(button.selected and true or false)

	-- Three shades, the same three the rail uses. The room you are reading is
	-- the heading colour, a room with something in it is the body colour, and a
	-- quiet room is dim. The count on the right is what says how much; the
	-- colour is what you see without reading it.
	local color = C.dim
	if button.selected then
		color = C.heading
	elseif button.unread and button.unread > 0 then
		color = C.text
	end
	button.text:SetTextColor(color[1], color[2], color[3])

	if button.unread and button.unread > 0 and not button.selected then
		button.badge:SetText(button.unread > 99 and "99+" or tostring(button.unread))
		button.badge:Show()
	else
		button.badge:Hide()
	end
end

function UI.List(parent, opts)
	local list = setmetatable({ pool = {}, rows = {}, onSelect = opts and opts.onSelect }, List)
	-- Named if the caller asks, for the reason the aura rows and the meter are:
	-- a column that has laid itself out wrongly has to be measurable from a
	-- macro and from scripts/harness.lua, and the alternative is the file that
	-- owns it handing out a reference to its own tables.
	list.frame = CreateFrame("Frame", opts and opts.name, parent)
	local bg = ns.Fill(list.frame, "BACKGROUND", C.rail[1], C.rail[2], C.rail[3], 1)
	bg:SetAllPoints()

	list.view = UI.ScrollView(list.frame)
	list.view.frame:SetPoint("TOPLEFT", M.rowGap, -M.rowGap)
	list.stack = UI.Stack(list.view.canvas)
	return list
end

-- One row's frame, made once and reused for whatever row lands on it next. It
-- carries every part either kind of row can want, because a header that became
-- an entry on the next refresh would otherwise need a frame of its own.
local function ListRow(list, index)
	local button = CreateFrame("Button", nil, list.stack.frame)
	button.bg = ns.Fill(button, "BACKGROUND", C.rail[1], C.rail[2], C.rail[3], 1)
	button.bg:SetAllPoints()
	button.mark = ns.Fill(button, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
	button.mark:SetPoint("TOPLEFT")
	button.mark:SetPoint("BOTTOMLEFT")
	button.mark:SetWidth(2)

	button.badge = UI.Label(button, M.small, C.accent, "RIGHT", UI.FLAT)
	button.badge:SetPoint("RIGHT", -M.rowGap, 0)
	UI.Wrap(button.badge, false)

	button.text = UI.Label(button, M.font, C.dim, "LEFT", UI.FLAT)
	button.text:SetPoint("LEFT", M.gutter, 0)
	button.text:SetPoint("RIGHT", button.badge, "LEFT", -M.rowGap, 0)
	UI.Wrap(button.text, false)

	button:SetScript("OnClick", function(this)
		if this.id then
			list:Select(this.id)
		end
	end)
	button:SetScript("OnEnter", function(this)
		this.hovered = true
		PaintListRow(this)
	end)
	button:SetScript("OnLeave", function(this)
		this.hovered = nil
		PaintListRow(this)
	end)

	list.pool[index] = button
	return button
end

-- What the column holds now.
--
--   row.header  the word above a run of rooms, drawn dim and not clickable
--   row.id      what Select and the caller's onSelect name this row by
--   row.label   what it says
--   row.unread  how many lines arrived here while you were somewhere else
--
-- The selection is kept by id across a refresh, so a whisper arriving while you
-- are reading the guild does not move you.
function List:Set(rows)
	self.rows = rows
	self.stack.cells = {}

	for index = 1, #rows do
		local row = rows[index]
		local button = self.pool[index] or ListRow(self, index)
		button.header = row.header and true or false
		button.id = row.id
		button.unread = row.unread or 0
		button.selected = (row.id ~= nil and row.id == self.selected)
		button.text:SetText(row.header or row.label or "")
		button.text:SetFontObject(UI.Font(row.header and M.small or M.font,
			UI.FLAT))
		-- A header is a caption rather than a control, so it must not take the
		-- click meant for the room under it or light up on the way past.
		button:EnableMouse(not button.header)
		button:Show()
		PaintListRow(button)

		-- Air above a header and none above anything else, which is what makes
		-- the runs read as runs. It is put on the row before rather than on the
		-- header itself, because a stack spaces rows by what sits under them,
		-- and the first header has no row before it to widen.
		local previous = self.stack.cells[#self.stack.cells]
		if button.header and previous then
			previous.gap = M.rowGap
		end
		self.stack:Add(button, { height = M.railRow, gap = 1 })
	end

	for index = #rows + 1, #self.pool do
		self.pool[index]:Hide()
	end

	self.stack:SetWidth(self.view.width or 0)
	local extent = self.stack:Reflow()
	if self.view.height then
		self.view:Update(extent)
	end
	return #rows
end

function List:Resize(width, height)
	self.frame:SetSize(width, height)
	self.view:Resize(width - M.rowGap * 2, height - M.rowGap * 2)
	self:Set(self.rows)
end

-- The row with this id, if it is drawn. Selecting one that is not there keeps
-- the id anyway, because the caller's own state is what decides which rooms
-- exist and this widget is not the place to argue with it.
function List:Select(id)
	if self.selected == id then
		return false
	end
	self.selected = id
	for index = 1, #self.pool do
		local button = self.pool[index]
		button.selected = (button.id ~= nil and button.id == id)
		PaintListRow(button)
	end
	if self.onSelect then
		self.onSelect(id)
	end
	return true
end

function List:Selected()
	return self.selected
end

-- One row's count, without rebuilding the column.
--
-- This is the whole reason the count is not just another field of Set. A line
-- of chat changes exactly one number on one row, and rebuilding thirteen rows
-- to draw it would be thirteen SetText calls per message on a raid night.
-- Returns false when there is no such row, which is how the caller knows a
-- rebuild is the thing it actually wanted.
function List:Mark(id, unread)
	for index = 1, #self.pool do
		local button = self.pool[index]
		if button.id ~= nil and button.id == id then
			if button.unread ~= unread then
				button.unread = unread
				PaintListRow(button)
			end
			return true
		end
	end
	return false
end

-- Which way to step through the rooms from where you are, skipping the headers.
-- Tab in the chat window is what calls this, so it has to wrap and it has to
-- answer something on a column that is all headers and one room.
function List:Step(delta)
	local rows, at = self.rows, nil
	for index = 1, #rows do
		if rows[index].id ~= nil and rows[index].id == self.selected then
			at = index
		end
	end
	if not at then
		at = delta > 0 and #rows or 1
	end
	for offset = 1, #rows do
		local index = ((at - 1 + delta * offset) % #rows) + 1
		if rows[index].id ~= nil then
			return rows[index].id
		end
	end
	return nil
end
