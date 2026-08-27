local ADDON, ns = ...

local Options = {}
ns.Options = Options

local UI = ns.UI
local M = UI.Metric

-- The options window. It builds one page of its own, Start here, and gets the
-- rest at PLAYER_LOGIN by walking the registry, handing each feature the widget
-- kit from UI/Widgets.lua and letting it draw its own rows.
--
-- Two levels of navigation, and the top one is not the registry.
--
-- The rail down the left is eight groups, declared below and owned by no
-- feature. A group is what somebody was thinking about when they opened the
-- window. Choosing one puts up its tab strip, and the tabs are the sections
-- filed under it: every `ui.Section(title, group)` a feature writes opens one.
--
-- That is the whole of the change from one rail entry per part. A part is a
-- folder of code, and eighteen folder names down the left asked a new player to
-- guess that the camera distance was under Comfort and that the window's own
-- size was under Settings. It also forced a part's sections to live together
-- whether or not they belonged together: UnitFrames has three, and two of them
-- are about your own frames while the third is about enemy nameplates. Those
-- three now sit in You and in Them without a line of code moving between files.
--
-- A part's `order` no longer decides where it sits in the rail, because the
-- rail is not made of parts. It decides where its tabs sit inside whichever
-- group they named, and it is a whole unique number so that two parts cannot
-- land in the same place and leave the answer to table.sort.
--
-- One switch per part is drawn here rather than by the part. Eleven features
-- each wrote their own check box for "does this draw anything", no two of them
-- worded the same way, and none of them visible without opening the page it was
-- on. Declared under `switch` in the registry, it is drawn at the top of the
-- part's first page, it fills Start here, and the rail marks any group holding
-- a part that is on.
--
-- Everything else this file used to own lives a layer down. UI/Theme.lua has
-- the palette and the measurements, UI/Stack.lua lays a column out and lets each
-- row say how tall it is, UI/Scroll.lua clips and scrolls, UI/Widgets.lua is the
-- kit, and UI/Window.lua is the chrome. What is left here is which groups exist,
-- where each section goes and what the footer does.

local WINDOW_W = 544
local WINDOW_H = 452
local BODY_PAD = 8

-- The rail, in full. Eight entries, fixed, in this order.
--
-- Eight rather than the six this started as, because Chores and Under the hood
-- were the two that would otherwise have been folded into The screen. Selling
-- grey items is not a screen setting and neither is what a ticker costs, and
-- either fold would have rebuilt the junk drawer the groups exist to take
-- apart. Nothing here holds more than eleven tabs, and all eight fit the rail
-- without scrolling, which the eighteen never did.
local GROUPS = {
	"Start here",
	"Fighting",
	"You",
	"Them",
	"Readouts",
	"The screen",
	"Chores",
	"Under the hood",
}

-- The one page this file draws itself, and the tab its single section takes.
local START = GROUPS[1]
local START_SECTION = "Turn things on"

local window, rail, view, divider
local groups, byName, kits = {}, {}, {}
local active = 1
local chrome = {}

-- Every control in the window, in build order, each carrying what it is called
-- and which section and group it is on. Filled by the kit as the pages are
-- built. See the search block near the foot of this file.
local indexed = {}
local finder, finderStack, finderRows = nil, nil, {}
local marked

--------------------------------------------------------------------------
-- Layout
--
-- One function that places everything, run when the window is built, when a
-- rail entry or a tab is chosen, and when the grid moves under the addon. It is
-- cheap and it is never on a ticker, so it recomputes rather than caches: a
-- cached rectangle that is wrong once is a window that is wrong until a reload.
--------------------------------------------------------------------------

local function ActiveSection()
	local group = groups[active]
	if not group then
		return nil
	end
	return group.sections[group.current or 1]
end

-- Measure the section that is showing and tell the view how tall it came out.
-- Only the showing one, because a font string on a hidden frame is not obliged
-- to report its wrapped height on this client, and a section measured while
-- hidden would lay out one line per lede.
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
	for index = 1, #groups do
		local group = groups[index]
		group.tabs.frame:ClearAllPoints()
		group.tabs.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT", left, -BODY_PAD)
		local own = group.tabs:Resize(bodyWidth)
		if index == active then
			strip = own
		end
		group.tabs.frame:SetShown(index == active)
	end

	view.frame:ClearAllPoints()
	view.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT", left, -(BODY_PAD + strip + BODY_PAD))
	view:Resize(bodyWidth, bodyHeight - strip - BODY_PAD)

	-- The results take the tab strip's room as well as the page's, because while
	-- a query is up there is no tab strip: what you are looking at spans every
	-- group and a strip belonging to one of them would be lying about it.
	if finder then
		finder.frame:ClearAllPoints()
		finder.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT", left, -BODY_PAD)
		finder:Resize(bodyWidth, bodyHeight)
	end

	Reflow()
end

--------------------------------------------------------------------------
-- Choosing
--------------------------------------------------------------------------

local function ShowSection(index)
	local group = groups[active]
	if not group or not group.sections[index] then
		return false
	end
	UI.CloseDropdown()
	UI.StopCapture()

	for i = 1, #group.sections do
		group.sections[i].stack.frame:SetShown(i == index)
	end
	group.current = index
	if group.tabs.selected ~= index then
		group.tabs:Select(index)
	end
	-- Back to the top. Carrying the last section's scroll position into a
	-- section of a different length lands you somewhere arbitrary in it.
	view:ScrollTo(0)
	Reflow()
	return true
end

local function ShowGroup(index)
	if not groups[index] then
		return false
	end
	UI.CloseDropdown()
	UI.StopCapture()

	for i = 1, #groups do
		local group = groups[i]
		group.tabs.frame:SetShown(i == index)
		for _, section in ipairs(group.sections) do
			section.stack.frame:SetShown(false)
		end
	end
	active = index
	Relayout()
	ShowSection(groups[index].current or 1)
	return true
end

--------------------------------------------------------------------------
-- Search
--
-- 131 controls behind 45 tabs behind 8 groups, and until now no way to type
-- "swing" and be shown the three that mention it.
--
-- The results are links rather than the live controls. A control is built into
-- one section's stack and cannot be in two places at once, and a link is the
-- honest answer anyway: it teaches you where the thing lives, so the second time
-- you go straight there.
--
-- A match is against the label, the section title, the group name, the part's
-- own name and every slash word it answers to. That last one is what makes
-- typing `skin` find the frame controls, because `/wk skin` is what drives them
-- and it is the word somebody who already knows the addon will reach for.
--------------------------------------------------------------------------

local function LabelOf(entry)
	local label = entry.label
	if type(label) == "function" then
		label = label()
	end
	return tostring(label or "")
end

local function Haystack(entry)
	local words = ""
	for word in pairs(entry.feature.words or {}) do
		words = words .. " " .. word
	end
	return (LabelOf(entry) .. " " .. entry.section.title .. " "
		.. entry.section.group.name .. " " .. entry.feature.name .. words):lower()
end

-- The mark stays until the next result is chosen or the query changes, rather
-- than fading on a timer. A fade is a ticker, and a settings window earns one of
-- those the day it has something to animate that is not a highlight nobody is
-- looking at any more.
local function Mark(widget)
	if marked then
		marked:Hide()
		marked = nil
	end
	if not widget then
		return
	end
	local mark = widget.searchMark
	if not mark then
		mark = ns.Fill(widget, "OVERLAY", UI.Color.accent[1], UI.Color.accent[2],
			UI.Color.accent[3], 1)
		mark:SetPoint("TOPLEFT", -M.rowGap, 0)
		mark:SetPoint("BOTTOMLEFT", -M.rowGap, 0)
		mark:SetWidth(2)
		widget.searchMark = mark
	end
	mark:Show()
	marked = mark
end

local function Reveal(entry)
	window.search:SetText("")
	rail:Select(entry.section.group.at)
	ShowSection(entry.section.at)
	Options.Refresh()
	Mark(entry.widget)
end

local function FinderRow(at)
	if finderRows[at] then
		return finderRows[at]
	end
	local button = UI.Button(finderStack.frame, { width = 1, height = M.row })
	button.text:ClearAllPoints()
	button.text:SetPoint("LEFT", M.rowGap, 0)
	button.text:SetJustifyH("LEFT")
	UI.Wrap(button.text, false)
	button:SetScript("OnClick", function(self)
		if self.entry then
			Reveal(self.entry)
		end
	end)
	finderRows[at] = button
	return button
end

-- What the field does on every keystroke. An empty field puts the page back.
local function Find(query)
	query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	Mark(nil)

	if query == "" then
		finder.frame:Hide()
		Relayout()
		return 0
	end

	-- The cell list is rebuilt rather than added to, because a cell for a row
	-- that this query did not match still takes its height and the column would
	-- keep the high-water mark of every query before it.
	local hits = 0
	finderStack.cells = {}
	for at = 1, #indexed do
		local entry = indexed[at]
		if Haystack(entry):find(query, 1, true) then
			hits = hits + 1
			local row = FinderRow(hits)
			row.entry = entry
			row.text:SetText(("%s / %s / %s"):format(entry.section.group.name,
				entry.section.title, LabelOf(entry)))
			row:Show()
			finderStack:Add(row, { indent = M.indent, height = M.row })
		end
	end
	for at = hits + 1, #finderRows do
		finderRows[at]:Hide()
		finderRows[at].entry = nil
	end

	for _, group in ipairs(groups) do
		group.tabs.frame:Hide()
	end
	local section = ActiveSection()
	if section then
		section.stack.frame:Hide()
	end

	finder.frame:Show()
	finderStack:SetWidth(finder.width)
	finder:Update(finderStack:Reflow())
	return hits
end

-- Handed out for the harness, which types every one of the 131 labels in full
-- and checks that each comes back with at least its own row.
function Options.Find(query)
	if not window then
		return 0
	end
	return Find(query)
end

function Options.Indexed()
	return indexed
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

-- A section, filed under the group it named. A group that does not exist is a
-- login error rather than a section that quietly lands in a default, because a
-- default is how the junk drawers got filled in the first place.
local function AddSection(host, title, group)
	local into = byName[group]
	assert(into, ("%s opened the section %q under the group %q, and there is no such group")
		:format(host.feature.name, tostring(title), tostring(group)))

	local section = {
		title = title,
		group = into,
		feature = host.feature,
		stack = UI.Stack(view.canvas, view.width),
	}
	section.stack.frame:Hide()
	into.sections[#into.sections + 1] = section
	section.at = #into.sections
	host.stack = section.stack
	host.section = section

	-- The switch goes on the part's first page, before whatever the feature
	-- writes next, which is why it is drawn from here rather than after the
	-- builder has run.
	if not host.opened then
		host.opened = section
		if host.feature.switch then
			Options.Switch(host.kit, host.feature)
		end
	end
	return section.stack
end

local function BuildFeature(feature)
	local host = { feature = feature }
	host.Refresh = function() Options.Refresh() end
	host.Popup = function() return window.frame end
	host.Section = function(title, group)
		return AddSection(host, title, group)
	end
	-- A lede belongs to the section it opened rather than to the row that drew
	-- it, because Start here quotes the lede of a part's first page under that
	-- part's switch and has nowhere else to read it from.
	host.Lede = function(text)
		host.section.lede = text
	end
	host.Index = function(widget, label)
		indexed[#indexed + 1] = {
			widget = widget,
			label = label,
			section = host.section,
			feature = feature,
		}
	end

	host.kit = UI.Kit(host)
	kits[#kits + 1] = host.kit
	feature.panel(host.kit)
	assert(host.opened, ("%s has a panel and opened no section"):format(feature.name))
end

-- Whether a group has anything on. Read by the rail, which marks the groups
-- holding a part that is drawing something, so what the addon is doing is
-- legible without opening a single tab.
local function GroupIsOn(group)
	for _, section in ipairs(group.sections) do
		local switch = section.feature and section.feature.switch
		if switch and ns.db[switch.key] and Options.SwitchAvailable(section.feature) then
			return true
		end
	end
	return false
end

-- Start here.
--
-- One column of every part's switch, each under the lede of the page it belongs
-- to, and nothing else: no numbers, no ranges. Turn things on, look at your
-- screen, come back. It is what the button in the Escape menu opens onto the
-- first time, and it is the answer to "easier for new players" that a rail of
-- module names could not be.
local function BuildStart()
	local host = { feature = { name = "start here" } }
	host.Refresh = function() Options.Refresh() end
	host.Popup = function() return window.frame end
	host.Section = function(title, group)
		return AddSection(host, title, group)
	end
	host.Lede = function() end
	-- Start here is not indexed. Every switch on it is the same switch as the
	-- one at the top of that part's own page, and a search that answered twice
	-- with the same control would be teaching you the wrong place to find it.
	host.kit = UI.Kit(host)
	kits[#kits + 1] = host.kit

	local ui = host.kit
	ui.Section(START_SECTION, START)
	ui.Lede("Every part of the addon, on or off. Everything with a number in it is in the groups below.")

	-- The one page in the window that carries a lede per row rather than one at
	-- the top. That is what this page is: a switch and the sentence saying what
	-- turning it on puts on your screen, eleven times over. The sentence is the
	-- lede of that part's own first page, read back rather than written twice.
	for _, feature in ipairs(ns.features) do
		if feature.switch and feature.panel then
			Options.Switch(ui, feature)
			local lede = Options.LedeOf(feature)
			if lede then
				ui.Lede(lede)
			end
		end
	end
end

local function Build()
	window = UI.Window({
		name = "WarriorKitOptions",
		title = "WarriorKit",
		width = WINDOW_W,
		height = WINDOW_H,
	})

	rail = UI.Rail(window.content, { onSelect = ShowGroup })
	divider = UI.Rule(window.content, UI.Color.hairline, true)

	-- The scroll view has to exist before any page is built, because a page's
	-- sections parent to its canvas and take their width from it. This size is
	-- provisional: Relayout works out the real one once it knows how tall the
	-- selected page's tab strip came out, and every section is re-widened from
	-- the view before it is measured.
	view = UI.ScrollView(window.content)
	view:Resize(WINDOW_W - M.rail - ns.Pixel(window.frame) - M.pad * 2,
		WINDOW_H - M.title - M.footer - BODY_PAD * 2)

	-- The results list. A second view over the same rectangle rather than rows
	-- pushed onto the page's own stack, because a result is a link to somewhere
	-- else and the page it would be sitting on is one of the places it links to.
	finder = UI.ScrollView(window.content)
	finder:Resize(view.width, view.height)
	finderStack = UI.Stack(finder.canvas, finder.width)
	finder.frame:Hide()

	for at, name in ipairs(GROUPS) do
		local group = { name = name, sections = {}, current = 1 }
		group.tabs = UI.TabStrip(window.content, {
			onSelect = function(section)
				if active == at then
					ShowSection(section)
				end
			end,
		})
		group.tabs.frame:Hide()
		group.at = at
		groups[at] = group
		byName[name] = group
		rail:Add(name)
	end

	-- The registry is already in order, and a group's sections are appended as
	-- they are opened, so a tab strip comes out in part order and then in the
	-- order that part wrote its sections. Nothing is sorted here.
	for _, feature in ipairs(ns.features) do
		if feature.panel then
			BuildFeature(feature)
		end
	end
	BuildStart()

	for _, group in ipairs(groups) do
		assert(#group.sections > 0, ("the group %q has no sections"):format(group.name))
		for _, section in ipairs(group.sections) do
			group.tabs:Add(section.title)
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

	window:Search({ onType = Find, onEnter = function()
		if finderRows[1] and finderRows[1].entry then
			Reveal(finderRows[1].entry)
		end
	end })

	-- What is in this window, recorded on the window. Nothing in the addon reads
	-- it. The harness walks it to drive every rail entry and every tab and then
	-- measure what came out, which is a seam worth having: the alternative is a
	-- hook cut into this file for the test's benefit and nothing else.
	window.rail, window.view, window.groups, window.kits = rail, view, groups, kits
	window.finder, window.indexed = finder, indexed

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
		-- Every row, not only the section showing. Relayout reflows the one
		-- section on screen, and a row that snapped a measurement to the pixel
		-- of the old zoom keeps it until something asks it again. The tab strip
		-- inside the Loadouts page is the one that shows: its buttons are
		-- rounded to whole pixels when they are laid out, so after a size change
		-- they sat on thirds of a pixel until you clicked onto that page. This
		-- costs one walk of the rows on a size change and nothing at all
		-- otherwise, which is the right price for a settings window.
		Options.Refresh()
	end)
end

--------------------------------------------------------------------------
-- The switch
--
-- One check box per part, worded by the panel and placed by the panel. A part
-- says which boolean it is and what to call the thing it draws; everything
-- about how that reads and where it sits is settled here, once, for all of
-- them.
--------------------------------------------------------------------------

function Options.SwitchAvailable(feature)
	local switch = feature.switch
	if not switch or not switch.available then
		return true
	end
	return switch.available() and true or false
end

function Options.Switch(ui, feature)
	local switch = feature.switch
	local row = ui.Check(switch.label,
		function() return ns.db[switch.key] end,
		function(value)
			ns.db[switch.key] = value
			if switch.apply then
				switch.apply(value)
			end
		end)
	row.IsAvailable = function() return Options.SwitchAvailable(feature) end
	return row
end

-- The lede of the first page a part opened, which is the sentence Start here
-- puts under that part's switch. Read off the section rather than out of the
-- registry, so there is one place a sentence about a page is written.
function Options.LedeOf(feature)
	for _, group in ipairs(groups) do
		for _, section in ipairs(group.sections) do
			if section.feature == feature then
				return section.lede
			end
		end
	end
	return nil
end

--------------------------------------------------------------------------
-- The public surface
--
-- Refresh is what anything that changes a setting outside the window calls, and
-- the slash handler already does. SelectGroup shows one rail entry's page.
--------------------------------------------------------------------------

function Options.Refresh()
	if not window then
		return
	end
	for index = 1, #kits do
		kits[index].Refresh()
	end
	for index = 1, #chrome do
		chrome[index].Refresh()
	end
	for index = 1, #groups do
		rail:SetDot(index, GroupIsOn(groups[index]))
	end
	Reflow()
end

function Options.SelectGroup(index)
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
	-- Shown before refreshed, because a lede measures its own wrapped height and
	-- a hidden font string is not obliged to answer.
	window:Show()
	Options.Refresh()
	-- Focused on the way in, because rummaging is what the window is for and a
	-- field you have to click first is a field you forget is there.
	window.search:SetText("")
	window.search:SetFocus()
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
