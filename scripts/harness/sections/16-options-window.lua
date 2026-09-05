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
	loadouts = "a loadout is a row in a list, and an empty list draws nothing",
	feeds = "two feeds, each with its own collect and its own show; one switch would name whichever came first and lie about the other",
	artwork = "its boolean turns Blizzard's art on rather than this part's own drawing, so a lit rail dot would mean the opposite of what it means everywhere else",
	comfort = "six unrelated chores, each with a switch of its own and no seventh boolean over them",
	interface = "its boolean is whether a layout is imported once at login, not whether anything is on screen",
	settings = "one slider and no boolean at all",
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
	local prose = 0
	-- Each sentence once. A switch's hint is drawn on the part's own page and
	-- again under the same switch on On and off, and that is one sentence to
	-- read wherever you happen to read it.
	local counted = {}
	local function Prose(said)
		if not counted[said] then
			counted[said] = true
			prose = prose + #said
		end
	end

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
				Prose(page.lede)
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
							Prose(said)
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
	-- How much reading the whole window asks for, in characters of lede and
	-- hint. It is a budget rather than a ratchet, because the two things that
	-- move it are not the same: a page that explains itself twice should come
	-- back under, and a part that did not exist last week is entitled to a lede
	-- and a hint per control it puts up.
	--
	-- So the number moves when a page arrives and never when one is edited. It
	-- was 16,000 with forty-two sections. The cloned bars page arrived under it
	-- and left it alone, at 15,908 across forty-eight. The party and raid page
	-- costs 1,166 characters and took the window to 17,101 across forty-nine.
	-- The cooldown row's four sections cost 793 and take it to 17,894 across
	-- fifty-three, none of its strings longer than the ones already here. The
	-- mouseover casting page costs 897 across three sections and takes it to
	-- 18,685 across fifty-six. The mail page costs 683 across three controls and
	-- took it to 19,147 across fifty-seven. The quest log page costs 444 across
	-- two controls and takes it to 19,591 across fifty-eight. 19,750 is that
	-- measurement plus a hint's worth of room, checked on the warrior run, which
	-- is the class with the most sections. The world hover page arrived under it
	-- and left it alone, at 19,733 across fifty-nine: one section, one switch
	-- worded by the panel, one lede and one reading. The experience and
	-- reputation page costs 495 across two checks and two sliders and takes it
	-- to 20,228 across sixty. 20,400 is that measurement plus a hint's worth of
	-- room again. The thanks page costs 505 across a check and a field and takes
	-- it to 20,733 across sixty-one. 20,900 is that measurement plus a hint's
	-- worth of room once more. The level up page costs 260 across one check and
	-- takes it to 20,993 across sixty-two. 21,160 is that measurement plus a
	-- hint's worth of room again. The shipped defaults section costs 338 across
	-- one button and two readings and takes it to 21,331 across sixty-three,
	-- which is the most any one section on the Settings page has cost and is
	-- the right price for the one control that throws every setting away.
	-- 21,500 is that measurement plus a hint's worth of room again. The hover
	-- section grew by two controls, a linger slider and a text size, and their
	-- two hints take it to 21,617 across sixty-three: no new page, but a section
	-- that went from one switch to three controls and now has to say what each
	-- of them costs. 21,800 is that measurement plus a hint's worth of room
	-- again. The world map page costs 472 across two checks and four readings
	-- and takes it to 22,102 across sixty-three: a new page, and the two hints
	-- on it are the two sentences that say what the client's own map does
	-- instead. 22,300 is that measurement plus a hint's worth of room again. The
	-- bag page costs 501 across two checks, a count and four readings and takes
	-- it to 22,603 across sixty-four: a new page, and the longer of its two
	-- hints is the sentence that says what the piles are made of, which is the
	-- one thing about the window nobody can work out by looking at it. 22,800 is
	-- that measurement plus a hint's worth of room again. The dungeon page costs
	-- 459 across a check, a key field, a button and six readings and takes it to
	-- 23,062 across sixty-five: a new page, and the longest of its three hints
	-- is the sentence saying the marks on the map are where you looted each
	-- boss, which is the one thing about that window nobody can work out by
	-- looking at it either. 23,300 is that measurement plus a hint's worth of
	-- room again. The merchant page costs 635 across two checks and four
	-- readings and takes it to 23,697 across sixty-six: a new page, and the
	-- longer of its two hints is the sentence saying the client's own merchant
	-- window is moved rather than hidden, which is the one thing about that
	-- switch nobody can work out by looking at it. 23,900 is that measurement
	-- plus a hint's worth of room again. The quest badge on the enemy bars costs
	-- 196 across one check and takes it to 23,893 across sixty-six: no new page,
	-- one more control on a section that already had six, and its hint is the
	-- sentence saying Questie is what answers it, which is the one thing about
	-- that switch nobody can work out by looking at a bar with no badge on it.
	-- 24,100 is that measurement plus a hint's worth of room again. The party
	-- preview costs 212 across one hint and one rewritten one and takes it to
	-- 24,105 across sixty-six: no new page, no new control, and the hint is the
	-- sentence saying the list stands a party and then a raid while it is
	-- unlocked, which is the one thing about a frame that is empty out of a
	-- group nobody can work out by looking at it. 24,300 is that measurement
	-- plus a hint's worth of room again. Splitting the raid off the party costs
	-- 960 across a page of its own and takes it to 25,065 across sixty-seven: a
	-- new page, six controls, and the longest of its hints is the sentence
	-- saying the grid shows in a raid and the line shows in a party, which is
	-- the one thing about two frames that never appear together nobody can work
	-- out by looking at either of them. 25,300 is that measurement plus a hint's
	-- worth of room again. Setting your own cooldowns costs 471 across a
	-- rewritten lede, a rewritten hint and two new ones, and takes it to 25,536
	-- across sixty-seven: no new page, a section whose one control per entry
	-- became five, and the longest of its hints is the sentence saying a spell id
	-- is the last part of a Wowhead address, which is the one thing about a field
	-- that takes a number nobody can work out by looking at it. 25,700 is that
	-- measurement plus a hint's worth of room again. Dragging the squares around
	-- instead gives 235 of it back and takes it to 25,301 across the same
	-- sixty-seven: the five controls per entry are one picture of the row, two
	-- hints and a reading went with them, and what a square does is on the square
	-- rather than in a paragraph about it. 25,500 is that measurement plus a
	-- hint's worth of room again, and it is a smaller number than the line above
	-- it because prose that came out is prose that has to stay out. Splitting the
	-- zoom onto every screen costs 1,285 across twenty three hints and takes it
	-- to 26,785 across sixty-nine: two new pages, twenty three controls, and each
	-- hint is the sentence saying which stop that screen is on and whether the
	-- stop keeps a hairline sharp, which is the one thing about a zoom nobody can
	-- work out by looking at the number. 27,000 is that measurement plus a hint's
	-- worth of room again. Stacking your bags costs 179 across one hint and takes
	-- it to 27,129 across the same sixty-nine: no new page, one more control on a
	-- section that already had three, and the hint is the sentence saying twelve
	-- cloth and eighteen come out twenty and ten, which is the one thing about a
	-- button marked stack nobody can work out by pressing it once. 27,300 is that
	-- measurement plus a hint's worth of room again.
	--
	-- That raise is the largest on this list and it is worth saying what it does
	-- not measure. Those twenty three sentences replaced twenty three readings
	-- that were on the page permanently, so the prose you actually see went down
	-- while the number counted here went up: a hint is read one at a time, on the
	-- row you hovered, and a reading is read whether you wanted it or not. This
	-- counter does not tell those apart. Separating them is a change to what the
	-- budget means and it is not being made in the commit that would benefit from
	-- it, which is the only honest order to make it in.
	--
	-- Clearing your bags costs 508 across a rewritten lede, three hints and a
	-- press, and takes it to 27,808 across the same sixty-nine: no new page, two
	-- new controls on a section that had one, and the three hints are the three
	-- sentences nobody can work out by pressing the button. Two of them are the
	-- thresholds: what a bag slot has to be worth before a grey is offered, and
	-- how far behind you a piece of gear has to be. A stepper reading 5 says
	-- neither of those on its own, and both of them decide whether an item is
	-- destroyed. 28,000 is that measurement plus a hint's worth of room again.
	--
	-- The places on the map cost 276 across a lede, a hint and a reading, and
	-- take it to 28,084 across seventy: one new page, and its controls are not
	-- counted because their labels are Questie's own words rather than this
	-- addon's prose. The hint is the one sentence nobody can work out from a
	-- row of tick boxes: that a tick here is a tick in Questie's menu, and not a
	-- second setting that could disagree with it. 28,300 is that measurement
	-- plus a hint's worth of room again.
	--
	-- Regrouping the window gave 2,085 back and takes it to 25,999 across
	-- sixty-seven: seven pages lost the second check box they drew on their own
	-- switch's key, and the hint each had hung on it moved onto the switch. The
	-- two pages that held nothing but where a row sits folded into the page
	-- that turns the row on, and the two bar pages became one. Three hints
	-- arrived with the merges, saying what clone, match and put back do now
	-- that they share a page with the rows they act on. The counter also
	-- stopped counting a sentence twice when the switch that carries it is
	-- drawn on On and off as well as on its own page. 26,200 is that
	-- measurement plus a hint's worth of room again, and it is the smallest
	-- number on this list since the forty-two section window, because prose
	-- that came out is prose that has to stay out.
	--
	-- The missing-buff row's four sections became one and it is 25,727 across
	-- sixty-five: two ledes and three hints went, the row is drawn instead of
	-- listed, and the racial's page folded into the row's. 25,900 is that plus
	-- the same room again.
	--
	-- The talent window arrived and it is 25,984 across sixty-six: a switch
	-- sentence, a lede, four readings and one line on the Blizzard page, and
	-- nothing else, because the window itself is where the talents are
	-- explained. 26,100 is that plus the same room again.
	--
	-- The spell book arrived and it is 26,525 across sixty-eight: a switch
	-- sentence, a lede, two readings and a line with a hint on the Blizzard
	-- page, plus a lede for the zoom page's third list, which is the windows
	-- list split in two because a thirteenth window no longer fit the view.
	-- 26,700 is that plus the same room again.
	--
	-- The loot filter arrived and it is 27,244 across the same sixty-eight:
	-- four hints on the page fast loot already had, and nothing else. It is
	-- twelve new controls and none of them needed a sentence, because a colour,
	-- seven kinds of trade good, what your professions use and a destroy are
	-- their own labels. The four say what pressing a control cannot: that money
	-- and a quest item come home whatever the rules below say and that none of
	-- it runs unless the click asked for auto loot, that a corpse you left
	-- something on keeps sparkling until it despawns, that the reagent list
	-- writes itself the first time each profession window is open, and what the
	-- destroy switch refuses to destroy. 27,450 is that plus a hint's worth of
	-- room again.
	--
	-- The wait before a bag square's box arrived and it is 27,576 across the
	-- same sixty-eight: one stepper and one hint on the bag page, and nothing
	-- else. The hint is the half the stepper cannot say: not that the box waits,
	-- which a number in milliseconds already says, but that crossing the window
	-- opens nothing on the way. The hold at a merchant that landed with it
	-- cost no prose at all, because a square that stays where it was when its
	-- item sold is a thing you watch happen. 27,750 is that plus a hint's worth
	-- of room again.
	--
	-- The price rule arrived and it is 27,762 across the same sixty-eight: one
	-- field and one hint on the loot page, and one sentence more on its lede.
	-- The hint is what the field cannot say, that the floor is read against the
	-- whole slot and that nought is off. The lede's sentence is the one link
	-- the page needs to the bag window, whose filter button throws this switch
	-- and the leftovers one together; the button's own hover says the same
	-- thing the other way round. 27,950 is that plus a hint's worth of room.
	-- The frame trace arrived and it is 28,609 across the same sixty-eight: two
	-- sections on the performance page, two ledes, four hints and six readings.
	-- It is the largest single addition this budget has taken and every sentence
	-- is one a control cannot say. The key hint says the binding is an override,
	-- which is the difference between shadowing the client's own frame rate
	-- display and overwriting it. The watch hint says why the trace runs with
	-- the window shut, which is the whole feature: a stutter is over before you
	-- can reach for a key. The dip hint gives the number fifty a reason. The
	-- profiler hint says what turning a client wide setting on buys and what it
	-- costs, which is the one control in the addon that reloads the interface.
	-- 28,750 is that plus a hint's worth of room.
	-- The game menu arrived and it is 28,897 across sixty-nine: one section on
	-- The screen, one lede, one switch sentence and one reading. It is the
	-- cheapest page this budget has taken, because the part has one control.
	-- The switch sentence is the one thing the label cannot say and the one
	-- thing somebody would want to know before throwing it: the paint does not
	-- touch Blizzard's own buttons, so the two that log you out are still the
	-- client's and still work in a fight. 29,100 is that plus a hint's worth
	-- of room.
	check(prose < 29100,
		("the window holds %d characters of prose and the budget is 29,100"):format(prose))

	print(("panel  %.0f x %.0f px at zoom %d, %d groups, %d sections, %d rows, %d wrapped strings")
		:format(window.width, window.height, window.zoom, #window.groups, tabs, rows, wrapped))
	print(("panel  %d controls, %d switches, %d ledes, %d hints, %d readings, %d characters of prose")
		:format(controls, switches, ledes, hints, readings, prose))
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
