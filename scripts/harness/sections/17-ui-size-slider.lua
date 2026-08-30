-- The UI size slider
--
-- The one control in the addon that resizes the thing you are looking at while
-- you hold it, which is also the one that can put a window off the bottom of the
-- screen if the clamp in Window:Resize is ever lost. So it is driven here the
-- way a player drives it: through the client's own Slider, at every stop, with
-- the geometry measured after each one.
--
-- Three questions, and none of them is answerable by reading the source.
--
-- Does the window survive the top of the range. At 3x the panel wants 452 units
-- of a screen that has 480 of them left after the zoom, so the clamp has to fire
-- and the result still has to be a whole number of units and still has to fit.
--
-- Do the design metrics stay whole. Zoom multiplies the scale, not the numbers,
-- so every row must still be an integer count of units at 1.25x. A row that came
-- back fractional would mean the size had leaked into the layout, which is the
-- bug this arithmetic exists to avoid.
--
-- Does the addon tell the truth about the cost. A quarter stop puts a hairline
-- on a fraction of a pixel and the panel says so; a whole stop does not and the
-- panel says that instead. Both sentences are read off UI.Exact, so asserting on
-- them is asserting the panel cannot claim a grid it does not have.

local H = ...
local state = H.state
local ns, check = H.ns, H.check
local whole, widget, window = H.carry.whole, H.carry.widget, H.carry.window

if window then
	ns.Options.Show()

	local Settings = ns.Settings
	local screen = ns.UI.ScreenZoom()

	-- At the design size, which is where the runner put it and where the stop
	-- walk below has to start: every figure it asserts is one step off 1.
	check(ns.db.uiSize == 1, ("the size starts at %s, not 1"):format(tostring(ns.db.uiSize)))
	check(window.zoom == screen,
		("the panel opened at zoom %s on a screen that asks for %d")
			:format(tostring(window.zoom), screen))

	-- The row the player actually drags, found the way the panel finds anything:
	-- through the index every control registers itself in. Nothing reaches into
	-- the feature for it.
	-- Named, not "the last slider on any page". The debuff icon row is a slider
	-- now too, and picking whichever came last would silently test the wrong
	-- control the next time a part gains one.
	local size, sliders = nil, 0
	for _, entry in ipairs(window.indexed) do
		if entry.widget.slider then
			sliders = sliders + 1
			if entry.section.title == "UI size" then
				size = entry.widget.slider
			end
		end
	end
	check(size ~= nil, "no UI size slider was built, so the client refused the Slider type")
	check(sliders == 9,
		("%d sliders in the panel, expected the UI size, the debuff icon, six"
			.. " backgrounds (the meters, the chat window, one per feed, the"
			.. " mouseover list and the bar the buttons page is showing) and"
			.. " that bar's square")
			:format(sliders))

	if size then
		local low, high = size:GetMinMaxValues()
		check(low == Settings.LOW and high == Settings.HIGH,
			("the slider runs %s to %s, the setting runs %s to %s")
				:format(tostring(low), tostring(high),
					tostring(Settings.LOW), tostring(Settings.HIGH)))
		check(size:GetValueStep() == Settings.STEP,
			("the slider steps by %s, the setting steps by %s")
				:format(tostring(size:GetValueStep()), tostring(Settings.STEP)))

		local stops, widest, tallest = 0, 0, 0
		local stop = Settings.LOW
		while stop <= Settings.HIGH + 1e-6 do
			stops = stops + 1
			size:SetValue(stop)

			local where = Settings.Label(stop)
			check(ns.db.uiSize == stop,
				("%s on the slider saved %s"):format(where, tostring(ns.db.uiSize)))
			check(window.zoom == screen * stop,
				("%s left the window at zoom %s, not %s")
					:format(where, tostring(window.zoom), tostring(screen * stop)))
			check(whole(window.width) and whole(window.height),
				("%s left the window %.2f x %.2f, not a whole number of units")
					:format(where, window.width, window.height))
			check(window.height * window.zoom <= state.SCREEN_H,
				("%s put %.0f pixels of window on a %d pixel screen")
					:format(where, window.height * window.zoom, state.SCREEN_H))

			-- The zoom multiplies the scale and must not reach the layout, so
			-- every row on the section showing is still whole units.
			local group = window.groups[1]
			for _, cell in ipairs(group.sections[group.current or 1].stack.cells) do
				check(whole(cell.height),
					("%s made a row %.3f units tall"):format(where, cell.height))
			end

			local said = Settings.Describe()
			if ns.UI.Exact(screen * stop) then
				check(said:find("exact", 1, true) ~= nil,
					("%s is on the grid and the panel does not say so: %s"):format(where, said))
			else
				check(said:find("soft", 1, true) ~= nil,
					("%s is off the grid and the panel does not say so: %s"):format(where, said))
			end
			check(said:find(where, 1, true) ~= nil,
				("%s is set and the panel reads %s"):format(where, said))

			local wide, tall = Settings.Pixels()
			if wide > widest then
				widest, tallest = wide, tall
			end
			stop = stop + Settings.STEP
		end

		check(stops == 11, ("%d stops between %s and %s, not 11")
			:format(stops, tostring(Settings.LOW), tostring(Settings.HIGH)))

		-- Which stops stay on the grid is a property of the monitor, not a
		-- constant, so the note that names them is generated and asserted rather
		-- than typed. This screen contributes a whole step of 1, so the exact
		-- stops are the three whole sizes and nothing else.
		local grid = Settings.Grid()
		local named = 0
		local at = Settings.LOW
		while at <= Settings.HIGH + 1e-6 do
			local listed = grid:find(Settings.Label(at), 1, true) ~= nil
			check(listed == ns.UI.Exact(screen * at),
				("%s is %s the grid and the note %s it: %s"):format(Settings.Label(at),
					ns.UI.Exact(screen * at) and "on" or "off",
					listed and "names" or "leaves out", grid))
			if listed then
				named = named + 1
			end
			at = at + Settings.STEP
		end
		check(named == 3, ("%d stops are exact at screen zoom %d, not 3"):format(named, screen))

		-- A drag, which is the case the widget is shaped around. The setting has
		-- to sit still while the button is down, because the window this slider
		-- is sitting in is the window the setting resizes, and a track that
		-- moves out from under the cursor mid-drag makes the client read the
		-- next value off geometry that has already changed.
		Settings.Set(1)
		size:GetScript("OnMouseDown")(size)
		size:SetValue(2.75)
		check(ns.db.uiSize == 1,
			("a held drag committed %s before the button came up"):format(tostring(ns.db.uiSize)))
		check(window.zoom == screen,
			("a held drag resized the window to zoom %s under the cursor")
				:format(tostring(window.zoom)))
		size:GetScript("OnMouseUp")(size)
		check(ns.db.uiSize == 2.75,
			("letting go saved %s, not the 2.75 the thumb was on"):format(tostring(ns.db.uiSize)))
		check(window.zoom == screen * 2.75,
			("letting go left the window at zoom %s"):format(tostring(window.zoom)))

		-- Shut with the button still down, by escape or by a reload. The drag
		-- never ends and the value would otherwise be dropped.
		Settings.Set(1)
		size:GetScript("OnMouseDown")(size)
		size:SetValue(1.75)
		size:GetScript("OnHide")(size)
		check(ns.db.uiSize == 1.75,
			("a drag interrupted by the window closing saved %s"):format(tostring(ns.db.uiSize)))

		-- Past the end. The client clamps its own slider and Settings.Snap
		-- clamps everything that never went through one, which is what a saved
		-- variable edited by hand meets.
		size:SetValue(Settings.HIGH + 5)
		check(ns.db.uiSize == Settings.HIGH,
			("dragging past the end saved %s"):format(tostring(ns.db.uiSize)))
		check(Settings.Snap(99) == Settings.HIGH and Settings.Snap(-1) == Settings.LOW,
			"Snap let a value outside the range through")
		check(Settings.Snap(1.3) == 1.25,
			("Snap put 1.3 on %s"):format(tostring(Settings.Snap(1.3))))

		-- The macro path refuses what the slider cannot reach, rather than
		-- rounding it into something that nearly works.
		check(ns.Command.Step("1.3", Settings.LOW, Settings.HIGH, Settings.STEP, "UI size") == nil,
			"the slash word rounded an off-step value instead of refusing it")
		check(ns.Command.Step("2.25", Settings.LOW, Settings.HIGH, Settings.STEP, "UI size") == 2.25,
			"the slash word refused a value that is on a step")

		-- Every window on the grid, not only the one this section measures. The
		-- Clutter window is built on first use and inherits the size then.
		--
		-- The chat window is the exception and it is a deliberate one. It is the
		-- only window in the addon that is up while you play, so how big you want
		-- it beside the game is a different question from how big you want a
		-- panel you open for a minute, and it has a size of its own. The screen's
		-- own whole step is still underneath it, which is why this asserts on
		-- that step times the chat setting rather than skipping the window: a
		-- chat window that had come off the grid entirely would still fail here.
		Settings.Set(2)
		for index = 1, #ns.UI.Windows do
			local held = ns.UI.Windows[index]
			local named = held.frame:GetName()
			local want = named == "WarriorKitChat" and screen * ns.db.chatScale or screen * 2
			check(held.zoom == want,
				("window %d (%s) is at zoom %s, expected %s")
					:format(index, tostring(named), tostring(held.zoom), tostring(want)))
		end

		-- And the chat window's own control moves it and nothing else.
		local was = ns.db.chatScale
		ns.db.chatScale = 1.5
		ns.ChatWindow.Apply()
		check(ns.ChatWindow.Zoom() == screen * 1.5,
			("the chat size went to 1.5x and the window reports zoom %s")
				:format(tostring(ns.ChatWindow.Zoom())))
		check(window.zoom == screen * 2,
			("sizing the chat window moved the settings window to zoom %s")
				:format(tostring(window.zoom)))
		ns.db.chatScale = was
		ns.ChatWindow.Apply()

		Settings.Set(1)
		check(window.zoom == screen and window.height == 452,
			("back at 1x the window is %.0f units tall at zoom %s")
				:format(window.height, tostring(window.zoom)))

		-- The same row on a client that refuses the Slider frame type.
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
			row = kit.Slider("UI size", Settings.LOW, Settings.HIGH, Settings.STEP,
				function() return held end,
				function(value) held = value end,
				Settings.Label)
			host.stack:Reflow()
		end)
		_G.CreateFrame = realCreate

		check(ok, "the size row raised on a client with no Slider: " .. tostring(err))
		if ok and row then
			check(row.slider == nil, "the row kept a slider on a client that refused the type")

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
			check(down ~= nil and up ~= nil, "the fallback row has no nudge buttons")

			if down and up then
				down:GetScript("OnClick")(down)
				check(held == 1 - Settings.STEP,
					("the fallback minus button moved the value to %s"):format(tostring(held)))
				up:GetScript("OnClick")(up)
				up:GetScript("OnClick")(up)
				check(held == 1 + Settings.STEP,
					("the fallback plus button moved the value to %s"):format(tostring(held)))
				for _ = 1, 20 do
					down:GetScript("OnClick")(down)
				end
				check(held == Settings.LOW,
					("the fallback buttons ran past the low end to %s"):format(tostring(held)))
			end
		end

		print(("size   %d stops, %s to %s, biggest panel %.0f x %.0f px on a %d pixel screen")
			:format(stops, Settings.Label(Settings.LOW), Settings.Label(Settings.HIGH),
				widest, tallest, state.SCREEN_H))
		print(("size   exact at %s on this screen, soft on the rest"):format(Settings.Grid()))
		print("size   " .. Settings.Describe())
	end

	ns.Options.Hide()
end
