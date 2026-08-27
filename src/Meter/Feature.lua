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
		local alpha = ns.Command.Step(value, ns.UI.ALPHA_LOW, ns.UI.ALPHA_HIGH, ns.UI.ALPHA_STEP,
			"meter bar opacity")
		if alpha then
			ns.db.meterBarAlpha = alpha
			MeterWindow.Apply()
			ns.Print(("meter bars at %d%% opacity."):format(alpha))
		end
		return
	end

	if option == "zoom" then
		local zoom = ns.Command.Number(value, ns.UI.ZOOM_LOW, ns.UI.ZOOM_HIGH, "meter zoom")
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

	switch = {
		key = "meter",
		label = "the meters",
		apply = function() MeterWindow.Show() end,
	},

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
		ui.Section("Meters", "Readouts")
		ui.Lede("Two columns with no window round them: who is doing damage, and who is about to take the mob.")

		ui.Cycle("left pane counts", MODES,
			function() return ns.db.meterMode end,
			function(mode)
				ns.db.meterMode = mode
				MeterWindow.Update()
			end)
		ui.Hint("Clicking the header on the meter itself does the same thing. That strip is the only part of the meter that takes the mouse, so the rows cannot swallow a camera drag.")

		ui.Check("Threat pane", function() return ns.db.meterThreat end,
			function(on)
				ns.db.meterThreat = on
				MeterWindow.Apply()
			end)
		ui.Hint("The percentage is the client's own: 100 means that player takes the mob. The seconds beside it are ours, and only appear while somebody is converging on you.")

		ui.Count("rows", LOW_ROWS, HIGH_ROWS,
			function() return ns.db.meterRows end,
			function(value)
				ns.db.meterRows = value
				MeterWindow.Apply()
			end)

		ui.Size("width", LOW_WIDTH, HIGH_WIDTH, 10,
			function() return ns.db.meterWidth end,
			function(value)
				ns.db.meterWidth = value
				MeterWindow.Apply()
			end)

		ui.Opacity("background",
			function() return ns.db.meterBarAlpha end,
			function(value)
				ns.db.meterBarAlpha = value
				MeterWindow.Apply()
			end)
		ui.Hint("How much of the floor the bars cover. At 0 there are no bars and the meter is columns of outlined text over the world.")

		ui.Reading("threat", function()
			return ns.MeterThreat.Ready() and "the client's own numbers"
				or "this client has no threat API, so the pane stays empty"
		end)
		ui.Reading("row icons", function()
			local guid = UnitGUID("player")
			if not ns.MeterSpec.Ready() then
				return "class icons: no talent API on this client"
			end
			if not ns.MeterSpec.Known(guid) then
				return "class icons until you have spent enough points to have a tree"
			end
			return "spec icons, sharpening from class as each inspect lands"
		end)

		ui.Action(function() return "put the meters back" end, function()
			MeterWindow.Reset()
		end)
	end,
})
