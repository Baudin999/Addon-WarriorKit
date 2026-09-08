-- The options window
--
-- Opened, then walked: every group in the rail, every section folded out under
-- it, and every row on every section. What is asserted here is what reading the
-- source cannot settle, and all of it is a complaint the rewrite was for.
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
--
-- Then the fold. One group open at a time, one line under it per section, every
-- line short enough to be read whole in the column it sits in, and the page
-- staying up when the group it belongs to is folded shut over it.

local H = ...
local state = H.state
local plain, ns, check = H.plain, H.ns, H.check
local wrapped = H.carry.wrapped

-- Nothing has opened it, so nothing has built it. That is the whole of the
-- deferral and it is the one part of it no amount of reading the source
-- settles: fifteen sections of login and play have run above this line, and if
-- any of them reached a getter on a page the window would already be here.
check(ns.Options.Window() == nil,
	"the options window was built before anything asked to see it")
ns.Options.Show()
local window = ns.Options.Window()
check(window ~= nil, "showing the options window built no window")

local function whole(value)
	return math.abs(value - math.floor(value + 0.5)) < 1e-6
end

-- Parts that legitimately have no switch, and why. The gate below is that every
-- part whose defaults hold a boolean declares one; an entry here is the written
-- reason for an exception, the same shape as every other allow-list in the
-- repo.
local NO_SWITCH = {
	targeting = "its only setting is a key binding, and a key nobody bound is already off",
	feeds = "two feeds, each with its own collect and its own show; one switch would name whichever came first and lie about the other",
	artwork = "its boolean turns Blizzard's art on rather than this part's own drawing, so a lit rail dot would mean the opposite of what it means everywhere else",
	comfort = "six unrelated chores, each with a switch of its own and no seventh boolean over them",
	interface = "its boolean is whether a layout is imported once at login, not whether anything is on screen",
	settings = "one slider and no boolean at all",
	["other addons"] = "its boolean is a note that the notice has been shown, not whether anything is on screen, and a switch on it would read as turning the addon list off",
}

if window then
	check(math.abs(ns.UI.Pixel(window.frame) - 1) < 1e-9,
		("the window is not on the grid: one pixel is %.4f units"):format(ns.UI.Pixel(window.frame)))
	check(whole(window.width) and whole(window.height),
		("the window is %.2f x %.2f, not a whole number of pixels"):format(window.width, window.height))
	check(window.height * window.zoom <= state.SCREEN_H,
		("the window is %.0f pixels tall on a %d pixel screen"):format(window.height * window.zoom, state.SCREEN_H))
	check(window.view.mechanism ~= "none",
		"neither SetClipsChildren nor the ScrollFrame type came up, so nothing clips")

	-- The rail fits folded shut, which is the number the eighteen entries could
	-- not make: three of them sat below the fold and nothing said so. Open is
	-- allowed to be taller than the view, because the longest group is eleven
	-- sections and the rail scrolls; what is not allowed is the chosen line
	-- ending up outside the viewport, which is checked on every group below.
	local railHeight = #window.groups * (ns.UI.Metric.railRow + 1)
	check(railHeight <= window.rail.view.height,
		("the rail folded shut is %d pixels of entries in a %.0f pixel view")
			:format(railHeight, window.rail.view.height))

	local rows, tabs, wrapped, tallest, shortest = 0, 0, 0, 0, math.huge
	local titles, ledes, hints, readings, labels = {}, 0, 0, 0, {}

	for index = 1, #window.groups do
		local group = window.groups[index]
		check(window.rail:Select(index), ("rail entry %d refused to select"):format(index))
		check(#group.sections >= 1, ("%s has no section"):format(group.name))
		tabs = tabs + #group.sections

		-- The fold. The group you chose is open and holds one line per section,
		-- and it is the only one open: seven groups folded out at once is the
		-- eighteen entry rail again with more steps.
		local folder = window.rail.groups[index]
		check(folder.open, ("%s was chosen in the rail and did not fold open"):format(group.name))
		check(folder.button.text:GetStringWidth() + folder.button.room
			<= folder.button:GetWidth() + 1e-6,
			("%s is %.0f pixels of text in %.0f pixels of rail"):format(group.name,
				folder.button.text:GetStringWidth(), folder.button:GetWidth() - folder.button.room))
		check(#folder.children == #group.sections,
			("%s has %d sections and %d lines under it in the rail")
				:format(group.name, #group.sections, #folder.children))
		for other = 1, #window.groups do
			check(other == index or not window.rail.groups[other].open,
				("%s is open in the rail while %s is"):format(window.groups[other].name, group.name))
		end

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

			check(stack.frame:IsShown(), where .. " did not show when its line was chosen")
			for other = 1, #group.sections do
				if other ~= section then
					check(not group.sections[other].stack.frame:IsShown(),
						where .. " is showing while another section of the same page is too")
				end
			end

			-- The line in the rail and the title over the page both say which
			-- section this is. With the tab strip gone these are the only two
			-- things that do, and one of them has to survive a fold.
			check(folder.children[section].selected,
				where .. " is showing and its line in the rail is not marked")
			check(plain(window.header.text.text) == page.title,
				("%s: the title over the page reads %q")
					:format(where, plain(window.header.text.text)))

			-- Every line in the rail fits the column it is in. A title too long
			-- for the rail is a title cut off mid word, and the rail is now the
			-- only place a section is named before you open it.
			local line = folder.children[section]
			check(line.text:GetStringWidth() + line.room <= line:GetWidth() + 1e-6,
				("%s: the rail line is %.0f pixels of text in %.0f pixels of room")
					:format(where, line.text:GetStringWidth(), line:GetWidth() - line.room))

			if page.lede then
				ledes = ledes + 1
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

					-- A hint is a string, or a function returning one for a
					-- sentence that is different every time it is read. The live
					-- ones are asked here rather than skipped: a zoom row's hint
					-- is only ever seen at the length the current setting makes
					-- it, so the cap is worth measuring at a real one.
					if cell.frame.hint then
						hints = hints + 1
						local said = cell.frame.hint
						if type(said) == "function" then
							said = said()
						end
						check(type(said) == "string" and said ~= "",
							("%s: a hint answered %s"):format(where, tostring(said)))
						if type(said) == "string" then
							check(#said <= 200,
								("%s: a hint is %d characters: %s"):format(where, #said, said))
						end
					end

					-- The `?` in the corner, and the room it was given. A hint
					-- nothing marks is a hint nobody finds, which is what every
					-- one of them was before the marker existed.
					if cell.frame.hint and cell.frame.MakeRoom then
						check(cell.frame.mark ~= nil,
							("%s: a row carries a hint and draws no ? to say so"):format(where))
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

	-- The glyph face.
	--
	-- Five marks of Font Awesome subset onto the five letters they replace, so
	-- what is asserted is not that a chevron came out. It is that the strings
	-- carrying those letters are in the other font and every other string in the
	-- window is not, because the whole trick is that a caller writes `v` either
	-- way and only the font object says which of the two it gets.
	local GLYPHS = "Interface\\AddOns\\WarriorKit\\Media\\Glyphs.ttf"
	local glyphed, lettered = 0, 0

	local function Faces(frame)
		for _, region in ipairs(frame.regions or {}) do
			if region.kind == "fontstring" then
				local path, size = region:GetFont()
				if path == GLYPHS then
					glyphed = glyphed + 1
					check(size == ns.UI.Metric.glyph,
						("a glyph is drawn at %s and the metric is %d")
							:format(tostring(size), ns.UI.Metric.glyph))
					check(#plain(region.text or "") <= 1,
						("the glyph face was given %q, which is not one mark")
							:format(plain(region.text or "")))
				elseif path then
					lettered = lettered + 1
				end
			end
		end
		for _, child in ipairs(frame.children or {}) do
			Faces(child)
		end
	end
	Faces(window.frame)

	check(glyphed > 0, "not one string in the window is drawn in the glyph face")
	check(lettered > glyphed, "more marks than words in a window made of sentences")
	check(window.close.text:GetFont() == GLYPHS, "the close cross is a letter x")
	check(window.rail.groups[1].button.fold:GetFont() == GLYPHS, "the fold mark is a letter v")

	-- The letters underneath, which is the branch that runs on a client that
	-- will not take the file. It is worth driving because it is the branch
	-- nobody sees: the window still works, and it works by drawing exactly what
	-- it drew before the font existed.
	do
		local real = _G.CreateFont
		_G.CreateFont = function(...)
			local font = real(...)
			local set = font.SetFont
			font.SetFont = function(self, path, ...)
				if path == GLYPHS then
					return false
				end
				return set(self, path, ...)
			end
			return font
		end
		-- A size nothing else asks for, because the objects are cached and a size
		-- already made would hand back the one that loaded.
		local refused = ns.UI.GlyphFont(97)
		_G.CreateFont = real
		check(refused:GetFont() == "Fonts\\ARIALN.TTF",
			("a client that refused the glyph file left the font at %s")
				:format(tostring(refused:GetFont())))
	end

	-- Folding, which is the one thing the rail does that a strip of tabs could
	-- not. Shutting the group you are in leaves its page up and moves the mark
	-- onto the group's own line, so the rail can be folded flat to eight lines
	-- without the window going blank. Opening it again comes back to the section
	-- you were reading rather than to the first one.
	ns.Options.SelectGroup(2)
	ns.Options.SelectSection(3)
	local held = window.groups[2].sections[3]
	check(window.rail:Toggle(2), "the open group refused to fold shut")
	check(not window.rail.groups[2].open, "the open group is still open after folding it shut")
	check(held.stack.frame:IsShown(), "folding the rail shut took the page down with it")
	check(window.rail.groups[2].button.selected,
		"the group is folded shut over the page that is showing and nothing in the rail is marked")
	check(window.rail:Toggle(2), "the shut group refused to fold open")
	check(window.groups[2].current == 3,
		("opening the group again landed on section %d, not the third")
			:format(window.groups[2].current))
	check(window.rail.groups[2].children[3].selected,
		"opening the group again did not mark the section it was left on")

	-- Every label the window drew, taken off the index rather than off the
	-- source, so a label built by concatenation is measured as the player reads
	-- it. `"collect " .. entry.collects` is the one that made this necessary:
	-- the string in the file ends in a space and only reads correctly once the
	-- feed's name is glued on.
	--
	-- And no page carries two controls with one label. The dungeon page did:
	-- the panel drew the part's switch and the part drew its own check box on
	-- the same key under the same words, so the page opened on two ticks that
	-- were one setting. Seven pages had the pair under two wordings, which is
	-- worse, because nothing on the page said they were the same.
	local controls = 0
	local seen = {}
	for _, entry in ipairs(window.indexed) do
		local label = plain(type(entry.label) == "function" and entry.label() or entry.label)
		controls = controls + 1
		check(label ~= "", ("a control on %s / %s was drawn with an empty label")
			:format(entry.section.group.name, entry.section.title))
		check(label == label:gsub("%s+$", ""),
			("the label %q ends in whitespace"):format(label))
		labels[#labels + 1] = label
		seen[entry.section] = seen[entry.section] or {}
		check(not seen[entry.section][label],
			("%s / %s carries two controls called %q")
				:format(entry.section.group.name, entry.section.title, label))
		seen[entry.section][label] = true
	end

	-- Every switch is on the page its part named for it, or on the first page
	-- the part opened when it named none, and On and off quotes that page's
	-- lede under it. The enemy bars switch sat at the top of the player frames
	-- page for a while, because that was the section the file wrote first.
	for _, group in ipairs(window.groups) do
		for _, section in ipairs(group.sections) do
			local switch = section.feature and section.feature.switch
			if section.switched then
				check(switch ~= nil, ("%s / %s carries a switch and its part declares none")
					:format(group.name, section.title))
				check(switch == nil or switch.page == nil or switch.page == section.title,
					("%s / %s carries the switch its part asked to have on %q")
						:format(group.name, section.title, tostring(switch and switch.page)))
				check(section.lede ~= nil, ("%s / %s carries a switch and has no lede for On and off to quote")
					:format(group.name, section.title))
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

	-- Search finds every row.
	--
	-- Each control's own label, typed in full, has to come back with at least
	-- that control's row. This is what stops a control being added to a page and
	-- left out of the index: it would build, draw and work, and be unreachable
	-- by any route except knowing which of forty five tabs it was on.
	local searched, missed = 0, 0
	for _, entry in ipairs(window.indexed) do
		local label = plain(type(entry.label) == "function" and entry.label() or entry.label)
		searched = searched + 1
		local hits = ns.Options.Find(label)
		if hits == 0 then
			missed = missed + 1
			check(false, ("search for %q found nothing, and it is a label in the index")
				:format(label))
		end
	end
	ns.Options.Find("")
	check(missed == 0, ("%d of %d labels are not findable"):format(missed, searched))

	-- What a query does to the page behind it, both ways round. The page and its
	-- title go down while results are up, because a result is a link to one of
	-- them, and both come back when the field is emptied. Coming back is the half
	-- that was broken: the strip returned and the section under it did not, so
	-- clearing the field left the window blank until you clicked a tab.
	ns.Options.SelectGroup(2)
	ns.Options.SelectSection(1)
	local behind = window.groups[2].sections[1]
	ns.Options.Find("swing")
	check(not behind.stack.frame:IsShown(), "results are up and the page behind them is drawn")
	check(not window.header.frame:IsShown(), "results are up and the page title behind them is drawn")
	ns.Options.Find("")
	check(behind.stack.frame:IsShown(), "clearing the field left the window empty")
	check(window.header.frame:IsShown(), "clearing the field left the page with no title")

	-- And the three other things a query is matched against: a group name, a
	-- section title and a part's slash word. The last one is the reason search
	-- exists in the shape it does, because `skin` is what somebody who already
	-- knows the addon types and it is not the label on any control.
	check(ns.Options.Find("Windows") > 0, "no row matched the group name Windows")
	check(ns.Options.Find("Swing timer") > 0, "no row matched the section title Swing timer")
	check(ns.Options.Find("skin") > 0, "no row matched the slash word skin")
	ns.Options.Find("")

	-- What a refresh reaches, and what it leaves alone.
	--
	-- Forty nine places in the addon call Options.Refresh, and every one of them
	-- used to run every getter on every page: the bag walk behind what clear
	-- would find, the spellbook walk behind the spell ranks, Questie's three
	-- menus behind the places, the faction list behind your standings. A row is
	-- asked when the page it is on is showing and at no other time, and nothing
	-- about the shape of the code says so, which is why it is counted here.
	local function firstRow(section)
		for _, cell in ipairs(section.stack.cells) do
			if cell.frame and cell.frame.Refresh then
				return cell.frame
			end
		end
		return nil
	end

	local here, away, awayGroup, awaySection
	for at, group in ipairs(window.groups) do
		for index, section in ipairs(group.sections) do
			local row = firstRow(section)
			if row and section.stack.frame:IsShown() then
				here = here or row
			elseif row and not away then
				away, awayGroup, awaySection = row, at, index
			end
		end
	end
	check(here ~= nil and away ~= nil, "no pair of rows to count a refresh over")

	if here and away then
		local ranHere, ranAway = 0, 0
		local wasHere, wasAway = here.Refresh, away.Refresh
		here.Refresh = function() ranHere = ranHere + 1 return wasHere() end
		away.Refresh = function() ranAway = ranAway + 1 return wasAway() end

		ns.Options.Refresh()
		check(ranHere == 1,
			("a refresh asked the row on the page that is up %d times"):format(ranHere))
		check(ranAway == 0,
			("a refresh asked a row on a page nobody is looking at %d times"):format(ranAway))

		-- And the other half, which is what makes the first half safe: the page
		-- that was skipped is put back in step on its way up, so nothing anybody
		-- can read is ever stale.
		ns.Options.SelectGroup(awayGroup)
		ns.Options.SelectSection(awaySection)
		check(ranAway > 0, "the page came up and the rows on it were never asked")

		here.Refresh, away.Refresh = wasHere, wasAway
	end

	check(wrapped > 0, "not one string in the whole panel wrapped, so nothing was measured")
	check(tallest > window.view.height,
		("the tallest section is %.0f pixels in a %.0f viewport, so scrolling was never exercised")
			:format(tallest, window.view.height))
	check(shortest <= window.view.height,
		("every section overflows, so the bar was never asked to hide"))

	print(("panel  %.0f x %.0f px at zoom %d, %d groups, %d sections, %d rows, %d wrapped strings")
		:format(window.width, window.height, window.zoom, #window.groups, tabs, rows, wrapped))
	print(("panel  %d controls, %d switches, %d ledes, %d hints, %d readings")
		:format(controls, switches, ledes, hints, readings))
	print(("panel  every one of the %d findable by its own label"):format(searched))
	print(("panel  %s at %d px, %d marks against %d words")
		:format(ns.UI.GlyphName(), ns.UI.Metric.glyph, glyphed, lettered))
	print(("panel  viewport %.0f x %.0f, tallest section %.0f, rail %d px shut in %.0f, clipping by %s")
		:format(window.view.width, window.view.height, tallest, railHeight,
			window.rail.view.height, window.view.mechanism))

	ns.Options.Hide()
end

-- Left for the sections below.
H.carry.whole, H.carry.window, H.carry.wrapped = whole, window, wrapped
