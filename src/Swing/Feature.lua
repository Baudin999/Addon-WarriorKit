local ADDON, ns = ...

-- Everything Core and the panel need to know about the swing timer. The three
-- files above hold the clock, the Slam arithmetic and the drawing, and none of
-- them knows the name of anything outside this folder.

local Swing = ns.Swing
local Slam = ns.Slam
local Gauges = ns.SwingGauges

local LOW_WIDTH, HIGH_WIDTH = 80, 400
local LOW_HEIGHT, HIGH_HEIGHT = 4, 32

--------------------------------------------------------------------------

local function SwingWord(arg)
	local option, value = arg:match("^(%S*)%s*(.-)$")

	if option == "" or option == "show" then
		ns.Print("swing timer " .. Gauges.Describe() .. ".")
		return
	end

	if option == "width" then
		local width = ns.Command.Number(value, LOW_WIDTH, HIGH_WIDTH, "swing width")
		if width then
			ns.db.swingWidth = width
			Gauges.Apply()
			ns.Print(("the swing bars are %d pixels wide."):format(width))
		end
		return
	end

	if option == "height" then
		local height = ns.Command.Number(value, LOW_HEIGHT, HIGH_HEIGHT, "swing height")
		if height then
			ns.db.swingHeight = height
			Gauges.Apply()
			ns.Print(("each swing bar is %d pixels tall."):format(height))
		end
		return
	end

	if option == "zoom" then
		local zoom = ns.Command.Number(value, ns.UI.ZOOM_LOW, ns.UI.ZOOM_HIGH, "swing zoom")
		if zoom then
			ns.db.swingZoom = zoom
			Gauges.Apply()
			ns.Print(("the swing bars draw at %dx."):format(zoom))
		end
		return
	end

	ns.db.swing = ns.Command.Toggle(option)
	Gauges.Apply()
	ns.Print("swing timer " .. (ns.db.swing and "on" or "off") .. ".")
end

--------------------------------------------------------------------------

ns.Register({
	name = "swing",
	order = 9,

	switch = {
		key = "swing",
		label = "the swing bars",
		apply = function() Gauges.Apply() end,
	},

	defaults = {
		swing = true,

		-- 180 is the enemy bars' own default width and the two are read the
		-- same way, at a glance, from the same distance. 10 is tall enough to
		-- see a two hundredth of a swing move across it and short enough that
		-- two of them under the character are a line rather than a block.
		swingWidth = 180,
		swingHeight = 10,
		swingZoom = 1,

		-- Under the character and above where the charge icon sits at -160, so
		-- the two do not overlap at any width either of them takes. Both
		-- numbers are whole, because half of an odd number is half a pixel and
		-- this frame is on the grid.
		swingPoint = { "CENTER", "UIParent", "CENTER", 0, -220 },
	},

	words = {
		swing = SwingWord,
	},

	help = {
		"swing on|off, the main hand and off hand swing bars",
		"swing width 180, height 10, zoom 1 to 3",
	},

	status = function()
		return Gauges.Describe()
	end,

	lock = function()
		Gauges.Lock()
	end,

	reset = function()
		ns.db.swingWidth = ns.DefaultFor("swingWidth")
		ns.db.swingHeight = ns.DefaultFor("swingHeight")
		ns.db.swingZoom = ns.DefaultFor("swingZoom")
		Gauges.Reset()
	end,

	panel = function(ui)
		ui.Section("Swing timer", "You")
		ui.Lede("One bar per hand under your character, filling towards the next white swing.")

		ui.Size("width", LOW_WIDTH, HIGH_WIDTH, 10,
			function() return ns.db.swingWidth end,
			function(value)
				ns.db.swingWidth = value
				Gauges.Apply()
			end)

		ui.Size("height", LOW_HEIGHT, HIGH_HEIGHT, 1,
			function() return ns.db.swingHeight end,
			function(value)
				ns.db.swingHeight = value
				Gauges.Apply()
			end)

		ui.Zoom(
			function() return ns.db.swingZoom end,
			function(value)
				ns.db.swingZoom = value
				Gauges.Apply()
			end)
		ui.Hint("Its own zoom rather than the UI size slider, because a bar you read mid swing is worth keeping exact at the size you chose.")

		ui.Reading("the bars", function()
			if not Swing.Ready() then
				return "this client has no UnitAttackSpeed, so nothing here runs"
			end
			if not Swing.HasMainhand() then
				return "nothing in your main hand, so there is no swing to time"
			end
			return ("main hand %.2fs"):format(Swing.Speed(Swing.MAIN))
		end)

		ui.Action(function() return "put the swing bars back" end, function()
			Gauges.Reset()
		end)

		-- The window is the one part of this that belongs to a class rather than
		-- to a swing, so on anyone whose class named no such cast there is no tab
		-- of numbers about a spell they do not have. The spell names the page,
		-- because a page called "the cast window" says nothing on any character.
		if not Slam.Available() then
			return
		end
		local cast = Slam.Name() or "the cast"

		ui.Section(("The %s window"):format(cast), ns.Options.CLASS)
		ui.Lede(("A green band on the main hand bar marking the one press of %s that costs no swing.")
			:format(cast))

		ui.Reading(cast, function()
			if not Slam.Known() then
				return "not on this character yet"
			end
			if Slam.Longer() then
				return ("%.2fs cast against a %.2fs swing: no band, it does not fit")
					:format(Slam.Cast(), Swing.Speed(Swing.MAIN))
			end
			local _, _, at = Slam.Window()
			return ("band at %.0f%% of the bar, %.2fs cast"):format((at or 0) * 100, Slam.Cast())
		end)

		ui.Reading("the cast time", function()
			local rank = Slam.Rank()
			if Slam.Measured() then
				return ("%.2fs measured, Improved Slam reads as %d point%s")
					:format(Slam.Measured(), rank, rank == 1 and "" or "s")
			end
			return ("estimated, less %.1fs for %d point%s: cast one to measure it")
				:format(rank * 0.1, rank, rank == 1 and "" or "s")
		end)
	end,
})

-- What the timing figure on the performance tab is a timing of. Two bars is
-- twice the work of one, and the tab's milliseconds mean nothing without it.
ns.Perf.Gauge("swing bars on screen", function()
	if not ns.db.swing or not Gauges.Applicable() then
		return 0
	end
	return Swing.HasOffhand() and 2 or 1
end)
