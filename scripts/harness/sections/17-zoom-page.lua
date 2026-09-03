-- The zoom page
--
-- Every screen the addon draws, each sized on its own, which is the change this
-- section exists to hold. There was one number for all of them; shrinking the
-- map to sit beside the quest log shrank the quest log with it.
--
-- Four questions, and none of them is answerable by reading the source.
--
-- Is the page the registry. A row per registered screen across the two lists,
-- no more and no fewer, so a part that registers a screen turns up here and a
-- part that stops drawing one takes its row away. A page with a list of screens
-- typed into it is a page that goes stale the first time somebody adds a window.
--
-- Does either list fit. The rows are split into windows and things drawn over
-- the world because twenty three of them with a sentence under each ran to a
-- thousand units of stack in a view that holds three hundred and fifty, and the
-- row you opened the page for was three screens down. A list taller than the
-- view is a control the page technically has, which is the same as not having
-- it, so the height is asserted rather than eyeballed.
--
-- Are they actually independent. Sizing one screen must move that screen and
-- nothing else, which is the whole of what was asked for and the one thing a
-- shared number could never do.
--
-- Does the window survive the top of the range. At 3x the panel wants 452 units
-- of a screen that has 480 of them left after the zoom, so the clamp has to fire
-- and the result still has to be a whole number of units and still has to fit.
--
-- Does the addon tell the truth about the cost. A tenth stop puts a hairline on
-- a fraction of a pixel and the page says so; a whole stop does not and the page
-- says that instead. Both sentences are read off UI.Exact, so asserting on them
-- is asserting the page cannot claim a grid it does not have.

local H = ...
local state = H.state
local ns, check = H.ns, H.check
local whole, widget, window = H.carry.whole, H.carry.widget, H.carry.window

-- The two nudge buttons on a stepper row, found by the label they draw rather
-- than by their place in the row, because where they sit is layout and what
-- they say is the contract.
local function Nudges(row)
	local down, up
	for _, kid in ipairs(row.children) do
		local label = kid.text and kid.text.text
		if kid:GetScript("OnClick") then
			if label == "-" then
				down = kid
			elseif label == "+" then
				up = kid
			end
		end
	end
	return down, up
end

if window then
	ns.Options.Show()

	local Settings = ns.Settings
	local screen = ns.UI.ScreenZoom()
	local zooms = ns.Zooms()

	-- At the design size, which is where the runner put every screen and where
	-- the stop walk below has to start: every figure it asserts is one step off 1.
	check(ns.db.panelZoom == 1,
		("the panel starts at %s, not 1"):format(tostring(ns.db.panelZoom)))
	check(window.zoom == screen,
		("the panel opened at zoom %s on a screen that asks for %d")
			:format(tostring(window.zoom), screen))

	----------------------------------------------------------------
	-- The page is the registry
	----------------------------------------------------------------

	-- Found the way the panel finds anything: through the index every control
	-- registers itself in. Nothing reaches into the feature for it. The rows are
	-- keyed by the label the registry gave them, which is the same string the
	-- slash word matches on, so a label nobody can find here is a label nobody
	-- can type either.
	-- Every registered label, so a row the page draws under a name no part
	-- registered is caught as surely as a registered screen with no row. The
	-- readings and the action button under them carry labels of their own and
	-- are not steppers, which is what `nudged` separates out.
	local wanted = {}
	for _, zoom in ipairs(zooms) do
		wanted[zoom.label] = true
	end

	local rows, sliders, nudged = {}, 0, 0
	for _, entry in ipairs(window.indexed) do
		if entry.widget.slider then
			sliders = sliders + 1
		end
		if entry.section.title:find("^Zoom") and entry.widget.children then
			local down, up = Nudges(entry.widget)
			if down and up then
				nudged = nudged + 1
				check(wanted[entry.widget.label] == true,
					("the zoom page draws a row called %s and no part registered it")
						:format(tostring(entry.widget.label)))
				rows[entry.widget.label] = entry.widget
			end
		end
	end

	for _, zoom in ipairs(zooms) do
		check(rows[zoom.label] ~= nil,
			("%s is registered and the zoom page draws no row for it"):format(zoom.label))
	end
	check(nudged == #zooms,
		("the zoom page draws %d rows for %d registered screens"):format(nudged, #zooms))

	-- The size slider is gone: every screen is a stepper now, because a tenth is
	-- a step you click rather than a length you aim at. What is left on this
	-- count is the rows that were always sliders.
	check(sliders == 9,
		("%d sliders in the panel, expected how long a hover's box lingers, the"
			.. " debuff icon, six backgrounds (the meters, the chat window, one"
			.. " per feed, the mouseover list and the bar the buttons page is"
			.. " showing) and that bar's square"):format(sliders))

	----------------------------------------------------------------
	-- Every stop on the panel's own row
	----------------------------------------------------------------

	----------------------------------------------------------------
	-- Both lists fit without scrolling
	----------------------------------------------------------------

	for _, group in ipairs(window.groups) do
		for _, section in ipairs(group.sections) do
			if section.title:find("^Zoom") then
				local tall = section.stack.frame:GetHeight() or 0
				local holds = window.view.frame:GetHeight() or 0
				check(tall <= holds,
					("%s is %.0f units of rows in a view that holds %.0f")
						:format(section.title, tall, holds))
			end
		end
	end

	local panel = rows["Options panel"]
	check(panel ~= nil, "no row for the options panel, so the walk below is skipped")

	if panel then
		local stops, widest, tallest = 0, 0, 0
		local stop = Settings.LOW
		while stop <= Settings.HIGH + 1e-6 do
			stops = stops + 1
			stop = Settings.Snap(stop)
			ns.db.panelZoom = stop
			ns.UI.Notify()

			local where = Settings.Label(stop)
			check(window.zoom == screen * stop,
				("%s left the window at zoom %s, not %s")
					:format(where, tostring(window.zoom), tostring(screen * stop)))
			check(whole(window.width) and whole(window.height),
				("%s left the window %.2f x %.2f, not a whole number of units")
					:format(where, window.width, window.height))
			check(window.height * window.zoom <= state.SCREEN_H,
				("%s put %.0f pixels of window on a %d pixel screen")
					:format(where, window.height * window.zoom, state.SCREEN_H))

			-- The zoom multiplies the scale and must not reach the layout. A row
			-- is measured in the window's own units and then snapped to the pixel
			-- grid, so at every stop a row is a whole number of physical pixels.
			-- It is not a whole number of units at a stop that is not exact and it
			-- must not be: three of the twenty six stops keep a unit on a pixel,
			-- the page says which three, and rounding a row to the unit at the
			-- other twenty three is how a hairline lands on two thirds of a pixel.
			--
			-- The section that is showing, found rather than assumed. This took
			-- the first group whatever was up, and the first group was not up: it
			-- was holding the heights it was last laid out at, which were the ones
			-- from zoom 1, so the walk asserted the same twenty numbers twenty six
			-- times and never measured a stop at all.
			local showing
			for _, other in ipairs(window.groups) do
				for _, section in ipairs(other.sections) do
					if section.stack.frame:IsShown() then
						showing = showing or section
					end
				end
			end
			check(showing ~= nil, ("%s left no section showing"):format(where))
			local px = showing and ns.UI.Pixel(showing.stack.frame) or 1
			for _, cell in ipairs(showing and showing.stack.cells or {}) do
				check(whole(cell.height / px),
					("%s made a row %.3f units tall, which is %.3f pixels")
						:format(where, cell.height, cell.height / px))
			end

			local said = Settings.Describe("panelZoom")
			if ns.UI.Exact(screen * stop) then
				check(said:find("exact", 1, true) ~= nil,
					("%s is on the grid and the page does not say so: %s"):format(where, said))
			else
				check(said:find("soft", 1, true) ~= nil,
					("%s is off the grid and the page does not say so: %s"):format(where, said))
			end
			check(said:find(where, 1, true) ~= nil,
				("%s is set and the page reads %s"):format(where, said))

			local wide, tall = Settings.Pixels()
			if wide > widest then
				widest, tallest = wide, tall
			end
			stop = stop + Settings.STEP
		end

		check(stops == 26, ("%d stops between %s and %s, not 26")
			:format(stops, tostring(Settings.LOW), tostring(Settings.HIGH)))

		-- Which stops stay on the grid is a property of the monitor, not a
		-- constant, so the note that names them is generated and asserted rather
		-- than typed. This screen contributes a whole step of 1, so the exact
		-- stops are the three whole sizes and nothing else.
		local grid = Settings.Grid()
		local named = 0
		local at = Settings.LOW
		while at <= Settings.HIGH + 1e-6 do
			at = Settings.Snap(at)
			local found = grid:find(Settings.Label(at), 1, true) ~= nil
			check(found == ns.UI.Exact(screen * at),
				("%s is %s the grid and the note %s it: %s"):format(Settings.Label(at),
					ns.UI.Exact(screen * at) and "on" or "off",
					found and "names" or "leaves out", grid))
			if found then
				named = named + 1
			end
			at = at + Settings.STEP
		end
		check(named == 3, ("%d stops are exact at screen zoom %d, not 3"):format(named, screen))

		----------------------------------------------------------------
		-- The buttons on the row
		----------------------------------------------------------------

		-- A tenth is small enough that float addition drifts: ten presses of the
		-- plus button from 1 lands on 1.9999999999999998 unless every write goes
		-- through the snap. A readout saying 2x over a frame that UI.Exact calls
		-- soft is the failure this catches, and it is invisible by inspection.
		ns.db.panelZoom = 1
		ns.UI.Notify()
		local down, up = Nudges(panel)
		check(down ~= nil and up ~= nil, "the panel's zoom row has no nudge buttons")

		if down and up then
			for _ = 1, 10 do
				up:GetScript("OnClick")(up)
			end
			check(ns.db.panelZoom == 2,
				("ten presses of + from 1 landed on %.17g, not 2")
					:format(ns.db.panelZoom))
			check(ns.UI.Exact(screen * ns.db.panelZoom),
				"ten presses of + left the panel off a stop the page calls exact")
			for _ = 1, 40 do
				down:GetScript("OnClick")(down)
			end
			check(ns.db.panelZoom == Settings.LOW,
				("the minus button ran past the low end to %s")
					:format(tostring(ns.db.panelZoom)))
		end

		----------------------------------------------------------------
		-- One screen at a time
		----------------------------------------------------------------

		-- The whole of what the split bought. Every screen is put somewhere
		-- different, and then every screen is asked what it is at: a page that
		-- had kept one number underneath would answer the same everywhere, and a
		-- row wired to the wrong key would answer for its neighbour.
		local want = {}
		local at = Settings.LOW
		for _, zoom in ipairs(zooms) do
			-- Snapped on the way in, the same as every real path. A tenth added
			-- to a double twenty times is not the tenth it started as, and a
			-- test comparing an unsnapped accumulation against a snapped read is
			-- a test that fails on arithmetic rather than on behaviour.
			want[zoom.key] = Settings.Snap(at)
			ns.db[zoom.key] = want[zoom.key]
			if zoom.apply then
				zoom.apply()
			end
			at = at + Settings.STEP
			if at > Settings.HIGH + 1e-6 then
				at = Settings.LOW
			end
		end
		ns.UI.Notify()

		for _, zoom in ipairs(zooms) do
			check(ns.db[zoom.key] == want[zoom.key],
				("%s was set to %s and reads %s")
					:format(zoom.label, tostring(want[zoom.key]), tostring(ns.db[zoom.key])))
			check(ns.Zoom(zoom.key) == screen * want[zoom.key],
				("%s is drawn at %s and its setting says %s")
					:format(zoom.label, tostring(ns.Zoom(zoom.key)),
						tostring(screen * want[zoom.key])))
		end

		-- And every window that was built is at its own number rather than at
		-- whichever one was written last. A window nobody has opened is not on
		-- this list: it is built on first use and picks its zoom up then.
		local byName = {}
		for _, zoom in ipairs(zooms) do
			byName[zoom.key] = want[zoom.key]
		end
		local KEYS = {
			WarriorKitOptions = "panelZoom", WarriorKitChat = "chatScale",
			WarriorKitClutter = "clutterZoom", WarriorKitBags = "bagsZoom",
			WarriorKitMail = "mailZoom", WarriorKitMap = "mapZoom",
			WarriorKitQuests = "questsZoom", WarriorKitMerchant = "merchantZoom",
			WarriorKitCharacter = "characterZoom", WarriorKitDungeons = "dungeonsZoom",
			WarriorKitBreakdown = "breakdownZoom",
		}
		for index = 1, #ns.UI.Windows do
			local held = ns.UI.Windows[index]
			local key = KEYS[held.frame:GetName() or ""]
			if key and byName[key] then
				check(held.zoom == screen * byName[key],
					("window %d (%s) is at zoom %s, expected %s")
						:format(index, tostring(held.frame:GetName()),
							tostring(held.zoom), tostring(screen * byName[key])))
			end
		end

		-- Back to the design size for everything below this section.
		for _, zoom in ipairs(zooms) do
			ns.db[zoom.key] = 1
			if zoom.apply then
				zoom.apply()
			end
		end
		ns.UI.Notify()
		check(window.zoom == screen and window.height == 452,
			("back at 1x the window is %.0f units tall at zoom %s")
				:format(window.height, tostring(window.zoom)))

		----------------------------------------------------------------
		-- What never goes through a control
		----------------------------------------------------------------

		check(Settings.Snap(99) == Settings.HIGH and Settings.Snap(-1) == Settings.LOW,
			"Snap let a value outside the range through")
		check(Settings.Snap(1.27) == 1.3,
			("Snap put 1.27 on %s"):format(tostring(Settings.Snap(1.27))))
		check(Settings.Snap(1.3) == 1.3,
			("Snap moved 1.3, which is on a stop, to %s"):format(tostring(Settings.Snap(1.3))))

		-- The macro path refuses what the page cannot reach, rather than
		-- rounding it into something that nearly works.
		check(ns.Command.Step("1.27", Settings.LOW, Settings.HIGH, Settings.STEP, "zoom") == nil,
			"the slash word rounded an off-step value instead of refusing it")
		check(ns.Command.Step("1.3", Settings.LOW, Settings.HIGH, Settings.STEP, "zoom") == 1.3,
			"the slash word refused a value that is on a step")

		----------------------------------------------------------------
		-- A client with no Slider frame type
		----------------------------------------------------------------

		-- No row on the zoom page is a slider any more, but nine rows elsewhere
		-- in the panel still are, so the fallback still has to work.
		--
		-- Nothing installed on 2.5.6 proves that type takes a thumb texture from
		-- a stranger, so UI/Widgets.lua probes it and falls back to a pair of
		-- nudge buttons, and a branch nothing ever runs is a branch that is
		-- wrong. This one was: pcall hands back the error message where the
		-- frame would be, and the fallback called Hide on a string.
		--
		-- Built as a kit of its own on a stack of its own, rather than by
		-- rebuilding the panel, because the panel is what every check above has
		-- been driving and it is not put back afterwards.
		local realCreate = _G.CreateFrame
		_G.CreateFrame = function(kind, ...)
			if kind == "Slider" then
				error("this client has no Slider frame type")
			end
			return realCreate(kind, ...)
		end

		local held, row = 1, nil
		local ok, err = pcall(function()
			local host = { stack = ns.UI.Stack(window.frame, 300) }
			local kit = ns.UI.Kit(host)
			row = kit.Slider("zoom", Settings.LOW, Settings.HIGH, Settings.STEP,
				function() return held end,
				function(value) held = value end,
				Settings.Label)
			host.stack:Reflow()
		end)
		_G.CreateFrame = realCreate

		check(ok, "the row raised on a client with no Slider: " .. tostring(err))
		if ok and row then
			check(row.slider == nil, "the row kept a slider on a client that refused the type")

			local fell, rose = Nudges(row)
			check(fell ~= nil and rose ~= nil, "the fallback row has no nudge buttons")

			if fell and rose then
				fell:GetScript("OnClick")(fell)
				check(math.abs(held - (1 - Settings.STEP)) < 1e-9,
					("the fallback minus button moved the value to %s"):format(tostring(held)))
				rose:GetScript("OnClick")(rose)
				rose:GetScript("OnClick")(rose)
				check(math.abs(held - (1 + Settings.STEP)) < 1e-9,
					("the fallback plus button moved the value to %s"):format(tostring(held)))
				for _ = 1, 40 do
					fell:GetScript("OnClick")(fell)
				end
				check(math.abs(held - Settings.LOW) < 1e-9,
					("the fallback buttons ran past the low end to %s"):format(tostring(held)))
			end
		end

		print(("zoom   %d screens, %d stops from %s to %s, biggest panel %.0f x %.0f px on a %d pixel screen")
			:format(#zooms, stops, Settings.Label(Settings.LOW), Settings.Label(Settings.HIGH),
				widest, tallest, state.SCREEN_H))
		print(("zoom   exact at %s on this screen, soft on the rest"):format(Settings.Grid()))
		print("zoom   " .. Settings.Describe("panelZoom"))
	end

	ns.Options.Hide()
end
