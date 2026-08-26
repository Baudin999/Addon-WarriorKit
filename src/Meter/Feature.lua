local ADDON, ns = ...

-- The tab. The four files above hold the roster, the spec icons, the combat log
-- totals and the threat samples, and none of them knows the name of anything
-- outside this folder; this file is the only one that knows both those parts
-- and the addon around them, which is the seam every other part draws too.

local Meter = ns.Meter
local MeterWindow = ns.MeterWindow

local MODES = { "dps", "hps" }

local LOW_ROWS, HIGH_ROWS = 3, 10
local LOW_WIDTH, HIGH_WIDTH = 120, 400
local LOW_ZOOM, HIGH_ZOOM = 1, 3

-- The bar opacity, in whole percent. Zero is a stop rather than an accident: a
-- meter with no bars at all is three columns of text over the world, which is a
-- thing somebody will want and is otherwise a second setting to reach it. The
-- top is a solid bar, because the row it sits behind is outlined text and stays
-- readable on one, and a player on a bright floor asking for a solid bar has
-- already decided.
--
-- Fives, so the panel's stops and a macro's are the same twenty one values.
-- Command.Step refuses anything off them rather than rounding it, for the
-- reason it refuses a fractional zoom.
local LOW_ALPHA, HIGH_ALPHA, ALPHA_STEP = 0, 100, 5

--------------------------------------------------------------------------

local function Describe()
	if not ns.db.meter then
		return "off"
	end
	local line = ns.db.meterMode == "hps" and "healing" or "damage"
	if ns.db.meterThreat then
		line = line .. " and threat"
	end
	if not ns.MeterThreat.Ready() then
		line = line .. ", no threat api on this client"
	end
	if Meter.Running() then
		line = line .. (", in a fight, %ds so far"):format(Meter.Elapsed())
	end
	return line
end

local function MeterWord(arg)
	local option, value = arg:match("^(%S*)%s*(.-)$")

	if option == "" or option == "show" then
		ns.Print("meters " .. Describe() .. ".")
		return
	end

	if option == "dps" or option == "hps" then
		ns.db.meterMode = option
		MeterWindow.Update()
		ns.Print("meters showing " .. option:upper() .. ".")
		return
	end

	if option == "threat" then
		ns.db.meterThreat = ns.Command.Toggle(value)
		MeterWindow.Apply()
		ns.Print("threat pane " .. (ns.db.meterThreat and "on" or "off") .. ".")
		return
	end

	if option == "rows" then
		local rows = ns.Command.Number(value, LOW_ROWS, HIGH_ROWS, "meter rows")
		if rows then
			ns.db.meterRows = rows
			MeterWindow.Apply()
			ns.Print(("meters showing %d rows."):format(rows))
		end
		return
	end

	if option == "width" then
		local width = ns.Command.Number(value, LOW_WIDTH, HIGH_WIDTH, "meter width")
		if width then
			ns.db.meterWidth = width
			MeterWindow.Apply()
			ns.Print(("each meter is %d pixels wide."):format(width))
		end
		return
	end

	if option == "alpha" then
		local alpha = ns.Command.Step(value, LOW_ALPHA, HIGH_ALPHA, ALPHA_STEP,
			"meter bar opacity")
		if alpha then
			ns.db.meterBarAlpha = alpha
			MeterWindow.Apply()
			ns.Print(("meter bars at %d%% opacity."):format(alpha))
		end
		return
	end

	if option == "zoom" then
		local zoom = ns.Command.Number(value, LOW_ZOOM, HIGH_ZOOM, "meter zoom")
		if zoom then
			ns.db.meterZoom = zoom
			MeterWindow.Apply()
			ns.Print(("meters at %dx."):format(zoom))
		end
		return
	end

	ns.db.meter = ns.Command.Toggle(option)
	MeterWindow.Show()
	ns.Print("meters " .. (ns.db.meter and "on" or "off") .. ".")
end

--------------------------------------------------------------------------

ns.Register({
	name = "meters",
	order = 7,

	defaults = {
		meter = true,

		-- Which of the two numbers the damage pane is showing. One setting
		-- rather than two panes, because a warrior wants damage nine fights in
		-- ten and healing in the tenth, and two panes would cost the width of
		-- the one that is wrong every time.
		meterMode = "dps",
		meterThreat = true,

		-- Six rows is a full party and one pet, which is the group this addon
		-- is actually used in. A raid needs more and the setting goes to ten.
		meterRows = 6,
		-- Wide enough for a 27 pixel icon, a name and a number without the name
		-- being clipped to three letters. The enemy bars default to 180 for one
		-- bar; a meter row carries one more column than a bar does.
		meterWidth = 200,
		meterZoom = 1,

		-- What the note in Meter/Window.lua argues for: a tint you can rank four
		-- players by, not a wash you read the meter through.
		meterBarAlpha = 15,

		-- Left of centre and above the middle, which on a 16:9 screen is clear
		-- of the action bars, clear of the unit frames this addon skins, and
		-- inside the part of the screen you are already looking at.
		meterPoint = { "CENTER", "UIParent", "CENTER", -320, 120 },
	},

	words = {
		meter = MeterWord,
	},

	help = {
		"meter on|off, and meter dps|hps to swap what the left pane counts",
		"meter threat on|off, rows 3 to 10, width 120 to 400, zoom 1 to 3",
		"meter alpha 15, the bar opacity, 0 to 100 in fives",
	},

	status = Describe,

	lock = function()
		MeterWindow.Lock()
	end,

	reset = function()
		ns.db.meterRows = ns.DefaultFor("meterRows")
		ns.db.meterWidth = ns.DefaultFor("meterWidth")
		ns.db.meterZoom = ns.DefaultFor("meterZoom")
		ns.db.meterBarAlpha = ns.DefaultFor("meterBarAlpha")
		MeterWindow.Reset()
	end,

	panel = function(ui)
		ui.Header("Meters")

		ui.Check("Show the meters", function() return ns.db.meter end,
			function(on)
				ns.db.meter = on
				MeterWindow.Show()
			end)

		ui.Note(function()
			return "Two columns with no window round them: who is doing damage, and"
				.. " who is about to take the mob off you. A row is a spec icon, a"
				.. " name and a number, and the class coloured bar behind it is that"
				.. " player's share of the top row. There is no breakdown to open,"
				.. " because there is nothing behind a row to open."
		end)

		ui.Cycle("left pane counts", MODES,
			function() return ns.db.meterMode end,
			function(mode)
				ns.db.meterMode = mode
				MeterWindow.Update()
			end)

		ui.Note(function()
			return "Clicking the header on the meter itself does the same thing, which"
				.. " is the way you will actually do it. The header takes the mouse"
				.. " even while the frames are locked, because a control you cannot"
				.. " click is not a control. The rest of the meter never does, so the"
				.. " rows cannot swallow the right button drag that turns the camera."
				.. " The header can: a drag begun on that one strip, fourteen pixels"
				.. " tall, will not turn it. That is the whole price and it is why the"
				.. " strip is the only part that takes the mouse."
		end)

		ui.Check("Threat pane", function() return ns.db.meterThreat end,
			function(on)
				ns.db.meterThreat = on
				MeterWindow.Apply()
			end)

		ui.Note(function()
			if not ns.MeterThreat.Ready() then
				return "|cffd08040This client has no threat API|r, so the pane says so and"
					.. " stays empty. Vanilla computes no threat at all, which is why"
					.. " every Classic threat meter is a combat log simulation with a"
					.. " table of coefficients in it. That is a different addon, and a"
					.. " made up number here would be worse than a blank."
			end
			return "The percentage is the client's own: 100 means that player takes the"
				.. " mob, thresholds and talents already folded in. The seconds beside"
				.. " it are this addon's, worked out from how fast the percentage is"
				.. " climbing, and they appear only while someone is actually"
				.. " converging on you inside the next minute."
		end)

		ui.Stepper("rows", LOW_ROWS, HIGH_ROWS, 1,
			function() return ns.db.meterRows end,
			function(value)
				ns.db.meterRows = value
				MeterWindow.Apply()
			end)

		ui.Stepper("width", LOW_WIDTH, HIGH_WIDTH, 10,
			function() return ns.db.meterWidth end,
			function(value)
				ns.db.meterWidth = value
				MeterWindow.Apply()
			end)

		ui.Slider("bar opacity", LOW_ALPHA, HIGH_ALPHA, ALPHA_STEP,
			function() return ns.db.meterBarAlpha end,
			function(value)
				ns.db.meterBarAlpha = value
				MeterWindow.Apply()
			end,
			function(value) return value .. "%" end)

		ui.Note(function()
			return "How much of the floor the bars cover. The top row's bar is the full"
				.. " width of the pane every tick, by definition, so this is really"
				.. " asking how bright a rectangle you want lying across that part of"
				.. " the screen during a pull. 15 is a tint you can rank four players"
				.. " by over a dark floor, and over a bright one it is nothing at all,"
				.. " which is why it is a slider and not the number this addon picked."
				.. " At 0 there are no bars and the meter is columns of outlined text"
				.. " over the world."
		end)

		ui.Stepper("zoom", LOW_ZOOM, HIGH_ZOOM, 1,
			function() return ns.db.meterZoom end,
			function(value)
				ns.db.meterZoom = value
				MeterWindow.Apply()
			end)

		ui.Note(function()
			local drawn, exact = ns.MeterWindow.IconAdvice()
			if exact then
				return ("A row icon draws %d screen pixels of art, one stored texel per"
					.. " pixel, which is as sharp as a spell icon gets."):format(drawn)
			end
			return ("|cffd08040A row icon draws %d screen pixels of art|r, blended from"
				.. " two stored copies. The client keeps each icon at half the size of"
				.. " the one above, the crop leaves 54 texels, and only 54 and 27 land"
				.. " one texel on one pixel. Zoom 1 and zoom 2 are both exact; this"
				.. " zoom is not."):format(drawn)
		end)

		ui.Note(function()
			local guid = UnitGUID("player")
			if not ns.MeterSpec.Ready() then
				return "|cffd08040No talent API on this client|r, so every row draws a"
					.. " class icon."
			end
			if not ns.MeterSpec.Known(guid) then
				return "Your own spec icon comes from whichever talent tree has the most"
					.. " points in it, and you have not spent enough for that to mean"
					.. " anything yet, so your row draws a class icon."
			end
			return "Spec icons come from talent trees, because these clients have no"
				.. " specs to ask about. Yours is read directly. Everyone else's needs"
				.. " an inspect, which needs them inside about 28 yards and you out of"
				.. " combat, so their icons sharpen from class to spec over the first"
				.. " minute in a group and never block anything while they do."
		end)

		ui.Action(function() return "put the meters back" end, function()
			MeterWindow.Reset()
		end)
	end,
})
