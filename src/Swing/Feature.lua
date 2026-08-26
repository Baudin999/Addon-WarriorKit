local ADDON, ns = ...

-- Everything Core and the panel need to know about the swing timer. The three
-- files above hold the clock, the Slam arithmetic and the drawing, and none of
-- them knows the name of anything outside this folder.

local Swing = ns.Swing
local Slam = ns.Slam
local Gauges = ns.SwingGauges

local LOW_WIDTH, HIGH_WIDTH = 80, 400
local LOW_HEIGHT, HIGH_HEIGHT = 4, 32
local LOW_ZOOM, HIGH_ZOOM = 1, 3

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
		local zoom = ns.Command.Number(value, LOW_ZOOM, HIGH_ZOOM, "swing zoom")
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

	-- Between the meters and the bar art. Not a whole number, because every
	-- one from 1 to 12 is already taken and renumbering five parts to insert
	-- one readout is a bigger change than a fraction is a wart.
	order = 7.5,

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
		ui.Header("Swing timer")

		ui.Check("Show the swing bars", function() return ns.db.swing end,
			function(on)
				ns.db.swing = on
				Gauges.Apply()
			end)

		ui.Note(function()
			if not Swing.Ready() then
				return "|cffd08040This client has no UnitAttackSpeed|r, so there is no swing"
					.. " length to draw and nothing here runs."
			end
			if not Swing.HasMainhand() then
				return "Nothing in your main hand, so there is no swing to time and the"
					.. " bars are not drawn. They come back the moment you equip a"
					.. " weapon."
			end
			return "One bar per hand, filling towards the next swing. The off hand bar is"
				.. " only there while you are holding something in that hand. The clock"
				.. " is the combat log: every swing that lands or misses is the same"
				.. " instant the next one starts, so a bar is empty until your first"
				.. " white hit of a fight and exact from then on."
		end)

		ui.Note(function()
			return "Haste moves the length of a swing already in flight, and what is left"
				.. " of it is scaled rather than restarted. Flurry landing halfway"
				.. " through leaves you halfway through a shorter swing. That is the"
				.. " single thing a warrior's swing timer has to get right, because"
				.. " Flurry is up for most of a fight."
		end)

		ui.Stepper("width", LOW_WIDTH, HIGH_WIDTH, 10,
			function() return ns.db.swingWidth end,
			function(value)
				ns.db.swingWidth = value
				Gauges.Apply()
			end)

		ui.Stepper("height", LOW_HEIGHT, HIGH_HEIGHT, 1,
			function() return ns.db.swingHeight end,
			function(value)
				ns.db.swingHeight = value
				Gauges.Apply()
			end)

		ui.Stepper("zoom", LOW_ZOOM, HIGH_ZOOM, 1,
			function() return ns.db.swingZoom end,
			function(value)
				ns.db.swingZoom = value
				Gauges.Apply()
			end)

		ui.Action(function() return "put the swing bars back" end, function()
			Gauges.Reset()
		end)

		-- The Slam window is the one part of this that is warrior only, so on
		-- anyone else it is one sentence rather than a tab of numbers about a
		-- spell they do not have.
		if not ns.IsWarrior() then
			ui.Note(function()
				return "The green press window is Slam's, so it is drawn on a warrior and"
					.. " nowhere else. The bars themselves are worth the same to anybody"
					.. " standing in melee and are drawn here."
			end)
			return
		end

		ui.Header("The Slam window")

		ui.Note(function()
			return "Slam has a cast time, it does not interrupt the swing while it casts,"
				.. " and finishing it restarts the swing. Press early and the restart"
				.. " throws away the charge you had. Press late and the swing is pushed"
				.. " out to the end of the cast. The one right press is where the cast"
				.. " ends as the swing ends, which is the moment the swing has exactly a"
				.. " cast time left to run."
		end)

		ui.Note(function()
			if not Slam.Known() then
				return "|cffd08040Slam is not on this character yet|r, so there is nothing to"
					.. " mark. The band appears the moment you learn it."
			end
			if Slam.Longer() then
				return ("|cffd08040Slam casts in %.2fs and your swing is %.2fs|r, so the cast"
					.. " does not fit inside the swing and there is no press that costs"
					.. " nothing. No band is drawn, because a mark there would be a lie.")
					:format(Slam.Cast(), Swing.Speed(Swing.MAIN))
			end
			local _, _, at = Slam.Window()
			return ("The band sits at %.0f%% of the main hand bar, which is a %.2fs cast"
				.. " against a %.2fs swing. It moves with your haste and with your"
				.. " weapon, so it is where it is now rather than where it was."):format(
					(at or 0) * 100, Slam.Cast(), Swing.Speed(Swing.MAIN))
		end)

		ui.Note(function()
			local rank = Slam.Rank()
			if Slam.Measured() then
				return ("The cast time is the client's own: %.2fs, taken off the last Slam"
					.. " you actually cast, with haste and talents already in it. Improved"
					.. " Slam reads as %d point%s and is no longer being guessed at.")
					:format(Slam.Measured(), rank, rank == 1 and "" or "s")
			end
			return ("No Slam cast yet this session, so the band is drawn from an estimate:"
				.. " the spell's own cast time less %.1fs for %d point%s of Improved Slam."
				.. " Cast one and the client's real number replaces it."):format(
					rank * 0.1, rank, rank == 1 and "" or "s")
		end)

		ui.Note(function()
			return "The band is two tenths of a second wide because a key press lands"
				.. " within about a tenth of where you aimed, and a mark with no width is"
				.. " one you can only hit by luck. The line down the middle is the exact"
				.. " press. The whole bar goes green while the fill is inside the band,"
				.. " because four percent of a bar is not enough to catch out of the"
				.. " corner of an eye and all of it is."
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
