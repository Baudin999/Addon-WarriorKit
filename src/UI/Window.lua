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

	window.close = UI.Button(frame, { label = "x", width = M.title - 8, height = M.title - 8,
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
-- A column of choices down the left edge, one selected at a time. It sits in a
-- scroll view of its own rather than assuming its entries fit, because the
-- number of them is the number of parts the addon has and that number only goes
-- up. The view hides its bar while they do fit, so today it costs nothing but
-- the reserved column.
--------------------------------------------------------------------------

local Rail = {}
Rail.__index = Rail

local function PaintRail(button)
	local shade = button.selected and C.selected or (button.hovered and C.hover or C.rail)
	UI.Tint(button.bg, shade)
	button.mark:SetShown(button.selected and true or false)
	if button.selected then
		button.text:SetTextColor(C.heading[1], C.heading[2], C.heading[3])
	else
		button.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
	end
end

function UI.Rail(parent, opts)
	local rail = setmetatable({ buttons = {}, onSelect = opts and opts.onSelect }, Rail)
	rail.frame = CreateFrame("Frame", nil, parent)
	local bg = ns.Fill(rail.frame, "BACKGROUND", C.rail[1], C.rail[2], C.rail[3], 1)
	bg:SetAllPoints()

	rail.view = UI.ScrollView(rail.frame)
	rail.view.frame:SetPoint("TOPLEFT", M.rowGap, -M.rowGap)
	rail.stack = UI.Stack(rail.view.canvas)
	return rail
end

function Rail:Add(label)
	local index = #self.buttons + 1
	local button = CreateFrame("Button", nil, self.stack.frame)
	button.bg = ns.Fill(button, "BACKGROUND", C.rail[1], C.rail[2], C.rail[3], 1)
	button.bg:SetAllPoints()
	button.mark = ns.Fill(button, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
	button.mark:SetPoint("TOPLEFT")
	button.mark:SetPoint("BOTTOMLEFT")
	button.mark:SetWidth(2)

	button.text = UI.Label(button, M.font, C.dim, "LEFT", UI.FLAT)
	button.text:SetPoint("LEFT", M.gutter, 0)
	button.text:SetPoint("RIGHT", -M.rowGap, 0)
	UI.Wrap(button.text, false)
	button.text:SetText(label)

	button:SetScript("OnClick", function()
		self:Select(index)
	end)
	button:SetScript("OnEnter", function(this)
		this.hovered = true
		PaintRail(this)
	end)
	button:SetScript("OnLeave", function(this)
		this.hovered = nil
		PaintRail(this)
	end)

	PaintRail(button)
	self.buttons[index] = button
	self.stack:Add(button, { height = M.railRow, gap = 1 })
	return index
end

function Rail:Resize(width, height)
	self.frame:SetSize(width, height)
	self.view:Resize(width - M.rowGap * 2, height - M.rowGap * 2)
	self.stack:SetWidth(self.view.width)
	self.view:Update(self.stack:Reflow())
end

function Rail:Select(index)
	if not self.buttons[index] then
		return false
	end
	self.selected = index
	for i = 1, #self.buttons do
		self.buttons[i].selected = (i == index)
		PaintRail(self.buttons[i])
	end
	if self.onSelect then
		self.onSelect(index)
	end
	return true
end

--------------------------------------------------------------------------
-- The tab strip
--
-- A row of choices across the top of whatever the rail chose, one per section
-- of the page. Each tab is as wide as its own title, because a title is what a
-- tab is for and cutting it in half to make the row tidy loses the only
-- information on it. A row that runs out of width wraps onto the next one and
-- the strip grows by a whole tab, so a part with eight sections is a taller
-- strip rather than eight unreadable stubs.
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

