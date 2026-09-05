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

local SwingWord = ns.Command.Word({
	name = "swing",
	apply = function() Gauges.Apply() end,
	show = function()
		return "swing timer " .. Gauges.Describe() .. "."
	end,

	{ "width", number = { LOW_WIDTH, HIGH_WIDTH }, key = "swingWidth",
	  say = function(width)
		return ("the swing bars are %d pixels wide."):format(width)
	  end },

	{ "height", number = { LOW_HEIGHT, HIGH_HEIGHT }, key = "swingHeight",
	  say = function(height)
		return ("each swing bar is %d pixels tall."):format(height)
	  end },

	ns.Command.Zoom("swingZoom", "the swing bars draw at %dx."),

	otherwise = { toggle = true, key = "swing",
	  say = function(on)
		return "swing timer " .. (on and "on" or "off") .. "."
	  end },
})

--------------------------------------------------------------------------

ns.Register({
	name = "swing",
	order = 9,

	switch = {
		key = "swing",
		label = "the swing bars",
		-- Both halves, because off means off. Gauges takes the bars away and
		-- Swing.Apply takes the clock off the combat log, which is the half
		-- that costs something when there is nothing on the screen.
		apply = function()
			Swing.Apply()
			Gauges.Apply()
		end,
	},

	zooms = {
		{ key = "swingZoom", label = "Swing bars", fight = true, apply = function() ns.SwingGauges.Apply() end },
	},

	defaults = {
		-- Off. Every other readout in this addon is something you cannot get
		-- anywhere else; a swing bar is a rhythm you already feel through the
		-- animation, and a second pair of bars under the character is the
		-- first thing to go when the screen gets busy. `/wk swing on` is one
		-- line for the fury warrior who wants it.
		swing = false,

		-- 330 is wide enough to see a two hundredth of a swing move across it
		-- from the middle of the screen, which is the only distance this bar
		-- is ever read from. 14 is tall enough to hold that width without
		-- reading as a wire.
		swingWidth = 330,
		swingHeight = 14,
		swingZoom = 2,

		-- Under the character and above the charge icon at -190. Close enough
		-- that two bars and a 52 pixel icon share a few rows of pixels, which
		-- is the trade for keeping the whole column inside one glance and is
		-- why the part ships off: turn it on and this is the number to move.
		-- Both are whole, because half of an odd number is half a pixel and
		-- this frame is on the grid.
		swingPoint = { "CENTER", "UIParent", "CENTER", 3, -157 },
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
		ns.db.swingWidth = ns.DefaultCopy("swingWidth")
		ns.db.swingHeight = ns.DefaultCopy("swingHeight")
		ns.db.swingZoom = ns.DefaultCopy("swingZoom")
		Gauges.Reset()
	end,

	panel = function(ui)
		ui.Section("Swing timer", "Fighting")
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
