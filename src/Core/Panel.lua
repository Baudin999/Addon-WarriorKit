local ADDON, ns = ...

local Options = {}
ns.Options = Options

local UI = ns.UI
local M = UI.Metric

-- The options window. It builds one page of its own, On and off, and gets the
-- rest at PLAYER_LOGIN by walking the registry, handing each feature the widget
-- kit from UI/Widgets.lua and letting it draw its own rows.
--
-- One piece of navigation, and it is not the registry.
--
-- The rail down the left is nine groups, declared below and owned by no
-- feature. A group is a thing you can see on the screen or a job you came to
-- do. It folds: the group you are in stands open with its sections listed
-- under it, and every `ui.Section(title, group)` a feature writes is one of
-- those lines.
--
-- The fold replaced a strip of tabs across the top of the page, and the reason
-- is that the strip could only ever show one group's sections. Forty five of
-- them behind eight rail entries meant the window showed an eighth of itself at
-- a time, and Fighting's eleven wrapped onto three lines of stubs that took a
-- fifth of the page's height. A column says the same thing in a column, and it
-- says it about the group you are in while the others stay one line each.
--
-- That is the whole of the change from one rail entry per part. A part is a
-- folder of code, and eighteen folder names down the left asked a new player to
-- guess that the camera distance was under Comfort and that the window's own
-- size was under Settings. It also forced a part's sections to live together
-- whether or not they belonged together: Chat opens a window and Comfort sells
-- your greys, and each of those files also has a section that is about the
-- screen. A section says where it goes, so a file can spread over two groups
-- without a line of code moving between files.
--
-- A part's `order` no longer decides where it sits in the rail, because the
-- rail is not made of parts. It decides where a part's sections sit inside
-- whichever group they named, and it is a whole unique number so that two parts
-- cannot land in the same place and leave the answer to table.sort.
--
-- One switch per part is drawn here rather than by the part. Eleven features
-- each wrote their own check box for "does this draw anything", no two of them
-- worded the same way, and none of them visible without opening the page it was
-- on. Declared under `switch` in the registry, it is drawn at the top of the
-- page the part names for it, it fills On and off, and the rail marks any
-- group holding a part that is on.
--
-- Everything else this file used to own lives a layer down. UI/Theme.lua has
-- the palette and the measurements, UI/Stack.lua lays a column out and lets each
-- row say how tall it is, UI/Scroll.lua clips and scrolls, UI/Widgets.lua is the
-- kit, and UI/Window.lua is the chrome. What is left here is which groups exist,
-- where each section goes and what the footer does.

local WINDOW_W = 608
local WINDOW_H = 452
local BODY_PAD = 8

-- The strip above the page: the title of the section you are on, and the
-- hairline that used to be the underside of the tab strip. The rail says where
-- you are in the list; this says it over the thing you are reading, which is
-- where you are looking while you change a number.
local HEADER_H = 22

-- The rail. Nine fixed entries in this order, and one more that is named after
-- you and sits third.
--
-- Every name is a thing you can point at on the screen or a job you came to
-- do. The first cut of this list had You, Them and Readouts in it, and Chores
-- holding every window the addon draws, because a bag window is a chore in the
-- sense that sorting is. Nobody looking for the bag window thinks that. They
-- think "windows", so that is the group, and the frames are under Frames, the
-- bars under Action bars, and the switches under a name that says switches.
-- All nine fit the rail folded shut with room over, which the eighteen never
-- did.
local GROUPS = {
	"On and off",
	"Fighting",
	"Action bars",
	"Frames",
	"Windows",
	"Feeds and meters",
	"Chores",
	"The screen",
	"Under the hood",
}

-- The one page this file draws itself, and the line its single section takes.
local START = GROUPS[1]
local START_SECTION = "Turn things on"

--------------------------------------------------------------------------
-- The group named after you
--
-- Every other group is what somebody was thinking about when they opened the
-- window. This one is what they are: it holds the pages that exist because of
-- your class and would say nothing on any other, which is the charge button
-- and the Slam window on a warrior. The bar loadout is gated on a class too
-- and sits under Action bars all the same, because filling the bars is what it
-- does and that is where somebody looks for it.
--
-- A feature names it with Options.CLASS rather than with a string, because the
-- string is the client's own word for your class and no feature may know it. A
-- class that opened no page on it has no such rail entry at all, and neither
-- does a class nobody has written a file for.
--
-- Third, under Fighting, because most of what lands here is about fighting and
-- the alternative was a ninth line at the bottom that reads as an afterthought.
--------------------------------------------------------------------------

Options.CLASS = "\0class"
local CLASS_UNDER = "Fighting"

local window, rail, view, divider, header
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
-- line in the rail is chosen, and when the grid moves under the addon. It is
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

	header.frame:ClearAllPoints()
	header.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT", left, -BODY_PAD)
	header.frame:SetSize(bodyWidth, HEADER_H)

	view.frame:ClearAllPoints()
	view.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT", left, -(BODY_PAD + HEADER_H + BODY_PAD))
	view:Resize(bodyWidth, bodyHeight - HEADER_H - BODY_PAD)

	-- The results take the title's room as well as the page's, because while a
	-- query is up there is no one section: what you are looking at spans every
	-- group and a title belonging to one of them would be lying about it.
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

-- Show one section of the group that is already selected. Every other section
-- in the window is hidden, not only the others in this group, because a rail
-- that folds can put you on a different group's section without the group you
-- came from being touched.
local function ShowSection(index)
	local group = groups[active]
	if not group or not group.sections[index] then
		return false
	end
	UI.CloseDropdown()
	UI.StopCapture()

	for _, other in ipairs(groups) do
		for at, section in ipairs(other.sections) do
			section.stack.frame:SetShown(other == group and at == index)
		end
	end
	group.current = index
	header.text:SetText(group.sections[index].title)
	-- Back to the top. Carrying the last section's scroll position into a
	-- section of a different length lands you somewhere arbitrary in it.
	view:ScrollTo(0)
	Reflow()
	return true
end

-- What the rail calls when a line in it is chosen. The rail owns which group is
-- open and which section is marked; this owns which page is up.
local function Choose(index, section)
	if not groups[index] then
		return false
	end
	active = index
	Relayout()
	return ShowSection(section or groups[index].current or 1)
end

--------------------------------------------------------------------------
-- Search
--
-- 131 controls behind 45 sections behind 8 groups, and until now no way to type
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
	rail:Select(entry.section.group.at, entry.section.at)
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
		header.frame:Show()
		local section = ActiveSection()
		if section then
			section.stack.frame:Show()
		end
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

	header.frame:Hide()
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

	-- The switch goes at the top of one page, before whatever the feature
	-- writes next, which is why it is drawn from here rather than after the
	-- builder has run. Which page is the part's to say, under `switch.page`,
	-- and the first it opens when it says nothing. The first was the only rule
	-- for a while, and it put the enemy bars switch at the top of the player
	-- frames page because that happened to be the section the file wrote
	-- first: a switch is the one row a person opens the window for, and it has
	-- to be on the page whose title they clicked to find it.
	if not host.opened then
		host.opened = section
	end
	local switch = host.feature.switch
	if switch and not host.switched
		and (switch.page == nil or switch.page == title) then
		host.switched = section
		section.switched = true
		Options.Switch(host.kit, host.feature)
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
	-- it, because On and off quotes the lede of the page a part's switch is on
	-- under that switch and has nowhere else to read it from.
	--
	-- One per section, and a second is a login error rather than the first one
	-- quietly overwritten. A page that wants two ledes wants two sections, which
	-- is most of what stops the notes growing back.
	host.Lede = function(text)
		assert(not host.section.lede,
			("%s wrote a second lede on the section %q: %s")
				:format(feature.name, host.section.title, text))
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
	-- A part that is not built on this character opens nothing, and that is the
	-- whole of how a page disappears: no rail line, no switch on On and off, and
	-- no tick box writing a setting nothing here reads. Anything else opening
	-- nothing is a panel that lost its sections and is still a login error.
	assert(host.opened or not Options.SwitchAvailable(feature),
		("%s has a panel and opened no section"):format(feature.name))
	-- A page named for the switch that the part never opened is a switch drawn
	-- nowhere, which is a part you cannot turn off from the window that exists
	-- to turn things off.
	assert(host.switched or not feature.switch or not host.opened,
		("%s named the page %q for its switch and opened no section by that title")
			:format(feature.name, tostring(feature.switch and feature.switch.page)))
end

-- Whether a group has anything on. Read by the rail, which marks the groups
-- holding a part that is drawing something, so what the addon is doing is
-- legible without opening a single group.
local function GroupIsOn(group)
	for _, section in ipairs(group.sections) do
		local switch = section.feature and section.feature.switch
		if switch and ns.db[switch.key] and Options.SwitchAvailable(section.feature) then
			return true
		end
	end
	return false
end

-- On and off.
--
-- One column of every part's switch, each under the lede of the page it belongs
-- to, and nothing else: no numbers, no ranges. Turn things on, look at your
-- screen, come back. It is what the button in the Escape menu opens onto the
-- first time, and it is the answer to "easier for new players" that a rail of
-- module names could not be. It was called Start here, which said where to
-- begin and not what was on it, and the one thing people asked for was a place
-- to turn features on and off. This was that place all along. Now it says so.
local function BuildStart()
	local host = { feature = { name = "on and off" } }
	host.Refresh = function() Options.Refresh() end
	host.Popup = function() return window.frame end
	host.Section = function(title, group)
		return AddSection(host, title, group)
	end
	-- On and off is the one page in the window that carries a lede per row rather
	-- than one at the top, so it takes no section lede at all: the sentences on
	-- it belong to the parts they were read off, not to this page.
	host.Lede = function() end
	-- On and off is not indexed. Every switch on it is the same switch as the
	-- one at the top of that part's own page, and a search that answered twice
	-- with the same control would be teaching you the wrong place to find it.
	host.kit = UI.Kit(host)
	kits[#kits + 1] = host.kit

	local ui = host.kit
	ui.Section(START_SECTION, START)
	ui.Lede("Every part of the addon, on or off. The same switch sits at the top of that part's own page, with its numbers under it.")

	-- The one page in the window that carries a lede per row rather than one at
	-- the top. That is what this page is: a switch and the sentence saying what
	-- turning it on puts on your screen, eleven times over. The sentence is the
	-- lede of that part's own first page, read back rather than written twice.
	for _, feature in ipairs(ns.features) do
		-- A part that is not built on this character is left off entirely rather
		-- than drawn greyed. It has no page in the rail to be a shortcut to and
		-- no lede to sit under, so a greyed row here would be a switch pointing
		-- at nothing with no sentence saying so.
		if feature.switch and feature.panel and Options.SwitchAvailable(feature) then
			Options.Switch(ui, feature)
			local lede = Options.LedeOf(feature)
			if lede then
				ui.Lede(lede)
			end
		end
	end
end

-- The groups, made before any section is opened, because a section names the
-- group it belongs in and the group has to be there to be named. The rail's own
-- lines are not added here: the group named after you is dropped where nothing
-- opened a page on it, and the entries after it would then be numbered wrong.
local function OpenGroups()
	local function Open(name, key)
		local at = #groups + 1
		groups[at] = { name = name, sections = {}, current = 1, at = at }
		byName[key] = groups[at]
	end

	for _, name in ipairs(GROUPS) do
		Open(name, name)
		if name == CLASS_UNDER and ns.Class.Mine() then
			Open(ns.Class.Name() or ns.Class.Label(), Options.CLASS)
		end
	end
end

-- The rail's own lines, added once every section exists and the numbering has
-- settled.
--
-- The group named after you is the one that may legitimately come out empty: a
-- class can bring facts that open no page of their own, such as one more entry
-- on the buff row. It is dropped rather than folded open onto nothing. A fixed
-- group with none is a section that lost its group in a refactor, which is a
-- rail entry that does not work and an empty page rather than a mistake anybody
-- would see, so that one is a login error.
local function FillRail()
	local mine = byName[Options.CLASS]
	if mine and #mine.sections == 0 then
		for at = #groups, 1, -1 do
			if groups[at] == mine then
				table.remove(groups, at)
			end
		end
		byName[Options.CLASS] = nil
	end

	for at, group in ipairs(groups) do
		group.at = at
		assert(#group.sections > 0, ("the group %q has no sections"):format(group.name))
		rail:Add(group.name)
	end
	for at, group in ipairs(groups) do
		for _, section in ipairs(group.sections) do
			rail:AddChild(at, section.title)
		end
	end
end

local function Build()
	window = UI.Window({
		name = "WarriorKitOptions",
		title = "WarriorKit",
		width = WINDOW_W,
		height = WINDOW_H,
		zoom = function() return ns.Zoom("panelZoom") end,
		-- The grid moves when the resolution changes, when the UI scale does, or
		-- when this window's own zoom is dragged, which is a thing you can now do
		-- from inside the window you are dragging it in. The window takes itself
		-- back onto the grid and the layout follows, because every number below
		-- is in the window's own units and those units are what just changed.
		rescale = function(apply)
			apply()
			window:Resize(WINDOW_W, WINDOW_H)
			Relayout()
			-- Every row, not only the section showing. Relayout reflows the one
			-- section on screen, and a row that snapped a measurement to the
			-- pixel of the old zoom keeps it until something asks it again. The
			-- tab strip inside the Loadouts page is the one that shows: its
			-- buttons are rounded to whole pixels when they are laid out, so
			-- after a size change they sat on thirds of a pixel until you
			-- clicked onto that page. This costs one walk of the rows on a size
			-- change and nothing at all otherwise, which is the right price for
			-- a settings window.
			Options.Refresh()
		end,
	})
	ns.Remember(window)

	-- The window opening and closing, told to whichever part wants to answer it.
	--
	-- Hung on the frame rather than written into Options.Show and Options.Hide,
	-- because Escape closes the window through UISpecialFrames, which calls Hide
	-- on the frame and never comes past this file. UI/Window.lua hangs its own
	-- cleanup there for the same reason, so this chains rather than replaces.
	--
	-- One part answers it today: the bars mark whichever of them the page is
	-- showing, and a mark has to come off when the window that explains it goes.
	local closing = window.frame:GetScript("OnHide")
	window.frame:SetScript("OnHide", function(self, ...)
		if closing then
			closing(self, ...)
		end
		ns.Each("showing", false)
	end)
	window.frame:SetScript("OnShow", function()
		ns.Each("showing", true)
	end)

	rail = UI.Rail(window.content, { onSelect = Choose })
	divider = UI.Rule(window.content, UI.Color.hairline, true)

	-- The title of the page you are on, and the hairline under it. Both were the
	-- tab strip's, and the strip is gone.
	header = { frame = CreateFrame("Frame", nil, window.content) }
	header.text = UI.Label(header.frame, M.heading, UI.Color.heading, "LEFT", UI.FLAT)
	header.text:SetPoint("LEFT")
	header.text:SetPoint("RIGHT")
	UI.Wrap(header.text, false)
	header.rule = UI.Rule(header.frame, UI.Color.hairline)
	header.rule:SetPoint("BOTTOMLEFT")
	header.rule:SetPoint("BOTTOMRIGHT")

	-- The scroll view has to exist before any page is built, because a page's
	-- sections parent to its canvas and take their width from it. This size is
	-- provisional: Relayout works out the real one once the window knows its own
	-- pixel, and every section is re-widened from the view before it is measured.
	view = UI.ScrollView(window.content)
	view:Resize(WINDOW_W - M.rail - ns.Pixel(window.frame) - M.pad * 2,
		WINDOW_H - M.title - M.footer - BODY_PAD * 2 - HEADER_H)

	-- The results list. A second view over the same rectangle rather than rows
	-- pushed onto the page's own stack, because a result is a link to somewhere
	-- else and the page it would be sitting on is one of the places it links to.
	finder = UI.ScrollView(window.content)
	finder:Resize(view.width, view.height)
	finderStack = UI.Stack(finder.canvas, finder.width)
	finder.frame:Hide()

	OpenGroups()

	-- The registry is already in order, and a group's sections are appended as
	-- they are opened, so a group's list comes out in part order and then in the
	-- order that part wrote its sections. Nothing is sorted here.
	for _, feature in ipairs(ns.features) do
		if feature.panel then
			BuildFeature(feature)
		end
	end
	BuildStart()

	FillRail()

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
	-- it. The harness walks it to open every group and every section under it and
	-- then measure what came out, which is a seam worth having: the alternative
	-- is a hook cut into this file for the test's benefit and nothing else.
	window.rail, window.view, window.groups, window.kits = rail, view, groups, kits
	window.finder, window.indexed, window.header = finder, indexed, header

	rail:Select(1)
	Options.Refresh()

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
	-- The one sentence the switch needs, hung on it the way a hint hangs on
	-- any other row. Seven parts used to draw a second check box on the same
	-- key for no reason but to have a row to put this sentence on. It is
	-- `says` rather than `hint` because check.sh reads a `hint` field on any
	-- table as the tooltip band that no longer exists.
	if switch.says then
		ui.Hint(switch.says)
	end
	return row
end

-- The lede of the page a part's switch is on, which is the sentence On and off
-- puts under that switch. Read off the section rather than out of the
-- registry, so there is one place a sentence about a page is written.
function Options.LedeOf(feature)
	for _, group in ipairs(groups) do
		for _, section in ipairs(group.sections) do
			if section.feature == feature and section.switched then
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

-- One section of the group already selected, chosen through the rail rather
-- than by showing the page directly, so the line that is marked in the rail is
-- always the page that is up.
function Options.SelectSection(index)
	if not window then
		return
	end
	if rail:Select(active, index) then
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
	-- Emptied on the way in and not focused. The search takes the keyboard when
	-- you click it and at no other time: a field that grabs it on open eats the
	-- next press whatever it was for, and the press it ate most often was the
	-- one meant for a key field.
	window.search:SetText("")
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
