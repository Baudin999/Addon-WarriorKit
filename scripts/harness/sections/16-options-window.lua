-- The options window
--
-- Opened, then walked: every entry in the rail, every tab under every entry,
-- and every row on every tab. What is asserted here is what reading the source
-- cannot settle, and all of it is a complaint the rewrite was for.
--
-- The window is on the grid and sized in whole pixels, so a hairline is a
-- hairline and a row is not half a pixel tall.
--
-- No row is fractional and no row is shorter than the text inside it. That is
-- the overflow bug, and the only way to see it is to set the real strings the
-- features write, wrap them to the real width the layout hands out, and compare.
--
-- A lede that wraps produces a row that grew. A page whose rows come to more
-- than the viewport turns the scrollbar on, and one whose rows do not turns it
-- off, with no stub of a bar left behind.
--
-- Then the rules the redesign is made of, measured on the strings the features
-- actually produced rather than on the source: every section names a group that
-- exists, no group holds two sections with one title, no title repeats its
-- group's name, every lede and hint is inside its cap, no label ends in
-- whitespace or is empty, every reading fits one line, and every part with a
-- boolean in its defaults declares a switch or is allow-listed with a reason.

local H = ...
local state = H.state
local plain, ns, check = H.plain, H.ns, H.check
local wrapped = H.carry.wrapped

local window = ns.UI.Windows[1]
check(window ~= nil, "no window was built")

local function whole(value)
	return math.abs(value - math.floor(value + 0.5)) < 1e-6
end

-- Parts that legitimately have no switch, and why. The gate below is that every
-- part whose defaults hold a boolean declares one; an entry here is the written
-- reason for an exception, the same shape as every other allow-list in the
-- repo.
local NO_SWITCH = {
	targeting = "its only setting is a key binding, and a key nobody bound is already off",
	loadouts = "a loadout is a row in a list, and an empty list draws nothing",
	feeds = "two feeds, each with its own collect and its own show; one switch would name whichever came first and lie about the other",
	artwork = "its boolean turns Blizzard's art on rather than this part's own drawing, so a lit rail dot would mean the opposite of what it means everywhere else",
	comfort = "five unrelated chores, each with a switch of its own and no sixth boolean over them",
	interface = "its boolean is whether a layout is imported once at login, not whether anything is on screen",
	settings = "one slider and no boolean at all",
}

if window then
	ns.Options.Show()

	check(math.abs(ns.UI.Pixel(window.frame) - 1) < 1e-9,
		("the window is not on the grid: one pixel is %.4f units"):format(ns.UI.Pixel(window.frame)))
	check(whole(window.width) and whole(window.height),
		("the window is %.2f x %.2f, not a whole number of pixels"):format(window.width, window.height))
	check(window.height * window.zoom <= state.SCREEN_H,
		("the window is %.0f pixels tall on a %d pixel screen"):format(window.height * window.zoom, state.SCREEN_H))
	check(window.view.mechanism ~= "none",
		"neither SetClipsChildren nor the ScrollFrame type came up, so nothing clips")

	-- The rail fits without scrolling, which is the number the eighteen entries
	-- could not make. Three of them sat below the fold and nothing said so.
	local railHeight = #window.groups * (ns.UI.Metric.railRow + 1)
	check(railHeight <= window.rail.view.height,
		("the rail is %d pixels of entries in a %.0f pixel view")
			:format(railHeight, window.rail.view.height))

	local rows, tabs, wrapped, tallest, shortest = 0, 0, 0, 0, math.huge
	local titles, ledes, hints, readings, labels = {}, 0, 0, 0, {}
	local prose = 0

	for index = 1, #window.groups do
		local group = window.groups[index]
		check(window.rail:Select(index), ("rail entry %d refused to select"):format(index))
		check(#group.sections >= 1, ("%s has no section"):format(group.name))
		check(group.tabs.frame:IsShown(),
			("%s is selected in the rail and its tab strip is hidden"):format(group.name))
		check(whole(group.tabs.frame:GetHeight()),
			("%s has a tab strip %.2f pixels tall"):format(group.name, group.tabs.frame:GetHeight()))
		tabs = tabs + #group.sections

		titles[group.name] = {}

		for section = 1, #group.sections do
			ns.Options.SelectSection(section)
			local page = group.sections[section]
			local stack = page.stack
			local where = ("%s / %s"):format(group.name, page.title)

			-- A title says something the group has not already said, and says it
			-- once. Both of these were live: the rail entry Charge opened a tab
			-- strip whose second tab was also called Charge.
			check(page.title ~= group.name,
				("%s: a section is called after its own group"):format(where))
			check(not titles[group.name][page.title],
				("%s: two sections under one group carry the same title"):format(where))
			titles[group.name][page.title] = true

			check(stack.frame:IsShown(), where .. " did not show when its tab was chosen")
			for other = 1, #group.sections do
				if other ~= section then
					check(not group.sections[other].stack.frame:IsShown(),
						where .. " is showing while another section of the same page is too")
				end
			end

			if page.lede then
				ledes = ledes + 1
				prose = prose + #page.lede
				check(#page.lede <= 160,
					("%s: its lede is %d characters"):format(where, #page.lede))
			end

			for _, cell in ipairs(stack.cells) do
				rows = rows + 1
				check(whole(cell.height),
					("%s: a row is %.3f pixels tall, not a whole pixel"):format(where, cell.height))
				if cell.frame then
					check(cell.frame:GetWidth() + cell.indent <= stack.width + 1e-6,
						("%s: a row is %.1f wide inside a %.1f column"):format(where,
							cell.frame:GetWidth() + cell.indent, stack.width))

					if cell.frame.hint then
						hints = hints + 1
						prose = prose + #cell.frame.hint
						check(#cell.frame.hint <= 200,
							("%s: a hint is %d characters"):format(where, #cell.frame.hint))
					end

					-- A reading is a number on the right of its own row and it
					-- never wraps, so the row it is in has to be able to hold it
					-- on one line at the width the layout gave it.
					if cell.frame.reading then
						readings = readings + 1
						check(cell.frame.reading:StringLines() <= 1,
							("%s: the reading %q wrapped onto %d lines"):format(where,
								plain(cell.frame.reading.text),
								cell.frame.reading:StringLines()))
					end

					-- Every string on the row, measured at the width the layout
					-- gave it. A row shorter than its own text is text drawn over
					-- whatever comes next, which is the whole complaint.
					for _, text in ipairs(cell.frame.regions) do
						if text.kind == "fontstring" and plain(text.text) ~= "" then
							local lines = text:StringLines()
							if lines > 1 then
								wrapped = wrapped + 1
							end
							check(cell.height + 1e-6 >= text:GetStringHeight(),
								("%s: a %d line string is %.1f tall in a %.1f row")
									:format(where, lines, text:GetStringHeight(), cell.height))
						end
					end
				end
			end

			-- The stack's own answer rather than the sum of the rows, because the
			-- air between them is height the viewport has to find too.
			if stack.height > tallest then
				tallest = stack.height
			end
			if stack.height < shortest then
				shortest = stack.height
			end

			-- Scrolling, both ways round. A section past the viewport has a bar
			-- that is showing and has somewhere to go; one that fits has none and
			-- is pinned at the top.
			local view = window.view
			if view.extent > view.height then
				check(view.scrollable, where .. " is taller than the viewport and does not scroll")
				check(view.bar == nil or view.bar:IsShown(),
					where .. " scrolls and shows no bar")
				view:ScrollTo(1e6)
				check(view.offset == view.extent - view.height,
					("%s: scrolling to the end landed at %.1f, not %.1f")
						:format(where, view.offset, view.extent - view.height))
				view:ScrollTo(0)
			else
				check(not view.scrollable, where .. " fits the viewport and still thinks it scrolls")
				check(view.bar == nil or not view.bar:IsShown(),
					where .. " fits the viewport and left a stub of a scrollbar behind")
				check(view.offset == 0, where .. " fits the viewport and is scrolled off the top")
			end
		end
	end

	-- Every label the window drew, taken off the kits rather than off the
	-- source, so a label built by concatenation is measured as the player reads
	-- it. `"Collect " .. entry.collects` was the one that made this necessary:
	-- the string in the file ends in a space and only reads correctly once the
	-- feed's name is glued on.
	local controls = 0
	for _, kit in ipairs(window.kits) do
		for _, widget in ipairs(kit.widgets) do
			local label = widget.text and widget.text.text
			if label then
				controls = controls + 1
				label = plain(label)
				check(label ~= "", "a control was drawn with an empty label")
				check(label == label:gsub("%s+$", ""),
					("the label %q ends in whitespace"):format(label))
				labels[#labels + 1] = label
			end
		end
	end

	-- Every part with a boolean in its defaults declares a switch, or is on the
	-- list above with a reason.
	local switches = 0
	for _, feature in ipairs(ns.features) do
		if feature.panel then
			local boolean = false
			for _, value in pairs(feature.defaults or {}) do
				if type(value) == "boolean" then
					boolean = true
				end
			end
			if feature.switch then
				switches = switches + 1
			else
				check(not boolean or NO_SWITCH[feature.name] ~= nil,
					("%s has a boolean in its defaults, declares no switch and gives no reason")
						:format(feature.name))
			end
		end
	end
	for name, why in pairs(NO_SWITCH) do
		check(why ~= "", ("%s is allow-listed for having no switch with no reason given"):format(name))
	end

	check(wrapped > 0, "not one string in the whole panel wrapped, so nothing was measured")
	check(tallest > window.view.height,
		("the tallest section is %.0f pixels in a %.0f viewport, so scrolling was never exercised")
			:format(tallest, window.view.height))
	check(shortest <= window.view.height,
		("every section overflows, so the bar was never asked to hide"))
	check(prose < 16000,
		("the window holds %d characters of prose and the budget is 16,000"):format(prose))

	print(("panel  %.0f x %.0f px at zoom %d, %d groups, %d tabs, %d rows, %d wrapped strings")
		:format(window.width, window.height, window.zoom, #window.groups, tabs, rows, wrapped))
	print(("panel  %d controls, %d switches, %d ledes, %d hints, %d readings, %d characters of prose")
		:format(controls, switches, ledes, hints, readings, prose))
	print(("panel  viewport %.0f x %.0f, tallest section %.0f, rail %d px in %.0f, clipping by %s")
		:format(window.view.width, window.view.height, tallest, railHeight,
			window.rail.view.height, window.view.mechanism))

	ns.Options.Hide()
end

-- Left for the sections below.
H.carry.whole, H.carry.window, H.carry.wrapped = whole, window, wrapped
