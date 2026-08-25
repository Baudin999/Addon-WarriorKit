local ADDON, ns = ...

local Options = {}
ns.Options = Options

local UI = ns.UI
local M = UI.Metric

-- The options window. It builds no section of its own: at PLAYER_LOGIN it walks
-- the registry, gives each feature an entry in the rail, hands it the widget kit
-- from UI/Widgets.lua and lets the feature draw its own rows. Adding a part to
-- the addon adds an entry here without this file changing.
--
-- Two levels of navigation, because a part has more in it than a column.
--
-- The rail down the left is the seven parts. Choosing one puts up that part's
-- tab strip, and the tabs are the part's own sections: every `ui.Header` a
-- feature writes opens one. Charge alone has four of them, Charge key, Charge,
-- Action targeting and Weapon, and before this they were four rules stacked
-- down a single page that had to be as tall as all of them at once.
--
-- That is the fix for the complaint that picking something in the rail produced
-- no tabs. There was never a tab strip. What the old file called a tab was the
-- rail button itself: `TabButton` drew the rail, `SelectTab` swapped whole pages
-- and `PaintTab` recoloured a rail button, so choosing a part could not reveal
-- anything, because there was no second level for it to reveal. The naming hid
-- the absence rather than the code being broken.
--
-- Everything else this file used to own now lives a layer down. UI/Theme.lua has
-- the palette and the measurements, UI/Stack.lua lays a column out and lets each
-- row say how tall it is, UI/Scroll.lua clips and scrolls, UI/Widgets.lua is the
-- kit, and UI/Window.lua is the chrome. What is left here is which parts exist,
-- where their sections go and what the footer does.

local WINDOW_W = 544
local WINDOW_H = 452
local BODY_PAD = 8

local window, rail, view, divider
local parts, active = {}, 1
local chrome = {}

--------------------------------------------------------------------------
-- Layout
--
-- One function that places everything, run when the window is built, when a
-- rail entry or a tab is chosen, and when the grid moves under the addon. It is
-- cheap and it is never on a ticker, so it recomputes rather than caches: a
-- cached rectangle that is wrong once is a window that is wrong until a reload.
--------------------------------------------------------------------------

local function ActiveSection()
	local part = parts[active]
	if not part then
		return nil
	end
	return part.sections[part.current or 1]
end

-- Measure the section that is showing and tell the view how tall it came out.
-- Only the showing one, because a font string on a hidden frame is not obliged
-- to report its wrapped height on this client, and a section measured while
-- hidden would lay out one line per note.
local function Reflow()
	local section = ActiveSection()
	if not section then
		return 0
	end
	section.stack:SetWidth(view.width)
	local height = section.stack:Reflow()
	view:Update(height)
	return height
end

local function Relayout()
	if not window then
		return
	end

	local px = ns.Pixel(window.frame)
	local height = window.height - M.title - M.footer

	rail.frame:ClearAllPoints()
	rail.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, 0)
	rail:Resize(M.rail, height)

	divider:ClearAllPoints()
	divider:SetPoint("TOPLEFT", window.content, "TOPLEFT", M.rail, 0)
	divider:SetPoint("BOTTOMLEFT", window.content, "BOTTOMLEFT", M.rail, 0)

	local left = M.rail + px + M.pad
	local bodyWidth = window.width - left - M.pad
	local bodyHeight = height - BODY_PAD * 2

	local strip = 0
	for index = 1, #parts do
		local part = parts[index]
		part.tabs.frame:ClearAllPoints()
		part.tabs.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT", left, -BODY_PAD)
		local own = part.tabs:Resize(bodyWidth)
		if index == active then
			strip = own
		end
		part.tabs.frame:SetShown(index == active)
	end

	view.frame:ClearAllPoints()
	view.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT", left, -(BODY_PAD + strip + BODY_PAD))
	view:Resize(bodyWidth, bodyHeight - strip - BODY_PAD)
	Reflow()
end

--------------------------------------------------------------------------
-- Choosing
--------------------------------------------------------------------------

local function ShowSection(index)
	local part = parts[active]
	if not part or not part.sections[index] then
		return false
	end
	UI.CloseDropdown()
	UI.StopCapture()

	for i = 1, #part.sections do
		part.sections[i].stack.frame:SetShown(i == index)
	end
	part.current = index
	if part.tabs.selected ~= index then
		part.tabs:Select(index)
	end
	-- Back to the top. Carrying the last section's scroll position into a
	-- section of a different length lands you somewhere arbitrary in it.
	view:ScrollTo(0)
	Reflow()
	return true
end

local function ShowPart(index)
	if not parts[index] then
		return false
	end
	UI.CloseDropdown()
	UI.StopCapture()

	for i = 1, #parts do
		local part = parts[i]
		part.tabs.frame:SetShown(i == index)
		for _, section in ipairs(part.sections) do
			section.stack.frame:SetShown(false)
		end
	end
	active = index
	Relayout()
	ShowSection(parts[index].current or 1)
	return true
end

-- The registry keeps a part's name lower case, because it is also the word its
-- slash help is filed under. A rail entry is a title, so it takes its capital
-- here rather than making every feature carry a second name.
local function Title(name)
	return (name:gsub("^%l", string.upper))
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

local function AddSection(part, title)
	-- Every page opens with a header, and the first one names the same thing the
	-- rail entry does. So the first section is made before the builder runs and
	-- the builder's first header renames it, rather than the page carrying an
	-- empty section called after the part and a second one called the same.
	local first = part.sections[1]
	if first and #first.stack.cells == 0 then
		first.title = title
		part.tabs:SetLabel(1, title)
		part.host.stack = first.stack
		return first.stack
	end

	local section = { title = title, stack = UI.Stack(view.canvas, view.width) }
	section.stack.frame:Hide()
	part.sections[#part.sections + 1] = section
	part.tabs:Add(title)
	part.host.stack = section.stack
	return section.stack
end

local function BuildPart(feature, index)
	local part = { name = Title(feature.name), sections = {}, current = 1 }
	part.tabs = UI.TabStrip(window.content, {
		onSelect = function(section)
			if active == index then
				ShowSection(section)
			end
		end,
	})
	part.tabs.frame:Hide()

	part.host = {
		Refresh = function() Options.Refresh() end,
		Popup = function() return window.frame end,
	}
	part.host.Section = function(title)
		return AddSection(part, title)
	end

	AddSection(part, part.name)
	part.kit = UI.Kit(part.host)
	feature.panel(part.kit)
	return part
end

local function Build()
	window = UI.Window({
		name = "WarriorKitOptions",
		title = "WarriorKit",
		width = WINDOW_W,
		height = WINDOW_H,
	})

	rail = UI.Rail(window.content, { onSelect = ShowPart })
	divider = UI.Rule(window.content, UI.Color.hairline, true)

	-- The scroll view has to exist before any page is built, because a page's
	-- sections parent to its canvas and take their width from it. This size is
	-- provisional: Relayout works out the real one once it knows how tall the
	-- selected page's tab strip came out, and every section is re-widened from
	-- the view before it is measured.
	view = UI.ScrollView(window.content)
	view:Resize(WINDOW_W - M.rail - ns.Pixel(window.frame) - M.pad * 2,
		WINDOW_H - M.title - M.footer - BODY_PAD * 2)

	for _, feature in ipairs(ns.features) do
		if feature.panel then
			local index = #parts + 1
			rail:Add(Title(feature.name))
			parts[index] = BuildPart(feature, index)
		end
	end

	local lock = UI.Button(window.footer, { width = 160, height = M.row, onClick = function()
		ns.db.locked = not ns.db.locked
		ns.Each("lock")
		Options.Refresh()
	end })
	lock:SetPoint("LEFT")
	lock.Refresh = function()
		lock.text:SetText(ns.db.locked and "unlock to drag frames" or "lock frames")
	end

	local reset = UI.Button(window.footer, { label = "reset positions", width = 160, height = M.row,
		onClick = function() SlashCmdList.WARRIORKIT("reset") end })
	reset:SetPoint("RIGHT")

	chrome[#chrome + 1] = lock

	-- What is in this window, recorded on the window. Nothing in the addon reads
	-- it. The harness walks it to drive every rail entry and every tab and then
	-- measure what came out, which is a seam worth having: the alternative is a
	-- hook cut into this file for the test's benefit and nothing else.
	window.rail, window.view, window.parts = rail, view, parts

	rail:Select(1)
	Options.Refresh()

	-- The grid moves when the resolution changes or the UI scale does, and the
	-- window's own scale is put right by UI.Refresh before this runs. What is
	-- left is the zoom, which is chosen off the screen height, and the layout,
	-- which depends on both.
	UI.OnRescale(function()
		if not window then
			return
		end
		UI.Rezoom(window.frame, UI.WindowZoom())
		window.zoom = UI.WindowZoom()
		window:Resize(WINDOW_W, WINDOW_H)
		Relayout()
	end)
end

--------------------------------------------------------------------------
-- The public surface
--
-- Refresh is what anything that changes a setting outside the window calls, and
-- the slash handler already does. SelectTab shows one part's page, which is what
-- it has always meant.
--------------------------------------------------------------------------

function Options.Refresh()
	if not window then
		return
	end
	for index = 1, #parts do
		parts[index].kit.Refresh()
	end
	for index = 1, #chrome do
		chrome[index].Refresh()
	end
	Reflow()
end

function Options.SelectTab(index)
	if not window then
		return
	end
	if rail:Select(index) then
		Options.Refresh()
	end
end

function Options.SelectSection(index)
	if not window then
		return
	end
	if ShowSection(index) then
		Options.Refresh()
	end
end

function Options.Show()
	if not window then
		return
	end
	-- Shown before refreshed, because a note measures its own wrapped height and
	-- a hidden font string is not obliged to answer.
	window:Show()
	Options.Refresh()
end

function Options.Hide()
	if window then
		window:Hide()
	end
end

function Options.Toggle()
	if not window then
		return
	end
	if window:IsShown() then
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
