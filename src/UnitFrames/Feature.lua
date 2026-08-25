local ADDON, ns = ...

-- Everything Core and the panel need to know about the two halves of this
-- part: the enemy bars on the mobs, and the skin on the player, target and
-- target of target frames. EnemyBars.lua and Skin.lua hold the behaviour and
-- neither talks to Core or to the panel.

local function BarsWord(option, value)
	if option == "mode" then
		if value == "auto" or value == "plates" or value == "list" then
			ns.db.barsMode = value
			ns.EnemyBars.Rebuild()
			ns.Print("bars mode " .. value .. ", running as " .. ns.EnemyBars.Mode() .. ".")
		else
			ns.Print("bars mode takes auto, plates or list.")
		end
	elseif option == "style" then
		if value == "replace" or value == "attach" then
			ns.db.barsStyle = value
			ns.EnemyBars.Rebuild()
			ns.Print(value == "replace" and "our bars replace the Blizzard nameplate."
				or "our bars ride above the Blizzard nameplate.")
		else
			ns.Print("bars style takes replace or attach.")
		end
	elseif option == "offset" then
		local offset = ns.Command.Number(value, -60, 60, "bars offset")
		if offset then
			ns.db.barsOffset = offset
			ns.EnemyBars.Rebuild()
			ns.Print("plate offset " .. offset .. ".")
		end
	elseif option == "camera" then
		if value == "right" or value == "left" or value == "both" or value == "off" then
			ns.db.barsCamera = value
			ns.EnemyBars.Rebuild()
			if value == "off" then
				ns.Print("plates keep every button. The camera will not turn over a bar.")
			else
				ns.Print(("plates hand the %s button back to the world, so the camera turns over a bar. %s")
					:format(value == "both" and "left and right" or value,
						value == "right"
							and "Click targeting and ctrl-click marking still work."
							or "Click targeting on a plate is gone with it."))
			end
			ns.Print("camera pass-through: " .. ns.EnemyBars.CameraState() .. ".")
		else
			ns.Print("bars camera takes right, left, both or off.")
		end
	elseif option == "clickthrough" then
		ns.db.barsClickThrough = ns.Command.Toggle(value)
		ns.EnemyBars.Rebuild()
		ns.Print(ns.db.barsClickThrough
			and "plates pass the mouse through. The camera turns over a bar again, and clicking a plate no longer targets or marks."
			or "plates take the mouse. Click targeting and ctrl-click marking work, and the camera will not turn over a bar.")
	elseif option == "level" then
		ns.db.barsLevel = ns.Command.Toggle(value)
		ns.EnemyBars.ApplyLayout()
		ns.EnemyBars.Rebuild()
		ns.Print("mob tag " .. (ns.db.barsLevel and "on" or "off")
			.. ": the level coloured by what the kill is worth, grey pays no XP and red is five levels"
			.. " up, and a stripe beside it, bright amber when the mob is neutral and will not start it.")
	elseif option == "marker" then
		ns.db.barsMarker = ns.Command.Toggle(value)
		ns.EnemyBars.Rebuild()
		ns.Print("raid marker on the bars " .. (ns.db.barsMarker and "on" or "off")
			.. ", Blizzard's marker takes over when ours is off.")
	elseif option == "max" then
		local count = ns.Command.Number(value, 1, 15, "bars max")
		if count then
			ns.db.barsMax = count
			ns.Print("showing up to " .. count .. " bars in list mode.")
		end
	elseif option == "width" then
		local width = ns.Command.Number(value, 120, 400, "bars width")
		if width then
			ns.db.barsWidth = width
			ns.EnemyBars.ApplyLayout()
			ns.Print("bar width " .. width .. " pixels, on a plate and in the list.")
		end
	elseif option == "zoom" then
		local zoom = ns.Command.Number(value, 1, 3, "bars zoom")
		if zoom then
			ns.db.barsZoom = zoom
			ns.EnemyBars.ApplyLayout()
			ns.EnemyBars.Rebuild()
			ns.Print("bars zoom " .. zoom .. ", so one pixel of the design is "
				.. zoom .. " on screen. " .. ns.UI.Describe() .. ".")
		end
	elseif option == "stack" then
		ns.db.barsStack = ns.Command.Toggle(value)
		ns.Plates.Apply()
		ns.Print(ns.db.barsStack
			and "asking the client to stack nameplates and sizing a plate to the bar on it, so two mobs standing together get two bars that do not cover each other."
			or "nameplate motion and plate size handed back to the client.")
		ns.Print("plates: " .. ns.Plates.Describe() .. ".")
	else
		ns.db.bars = ns.Command.Toggle(option)
		ns.EnemyBars.Rebuild()
		ns.Print("enemy bars " .. (ns.db.bars and "on" or "off") .. ".")
	end
	ns.EnemyBars.Update()
end

local FRAME_WORDS = { player = "player frame", target = "target frame",
	tot = "target of target" }

local function SkinWord(arg)
	local option, value = arg:match("^(%S*)%s*(.-)$")

	if option == "probe" then
		ns.FrameSkin.Probe()
		return
	end

	if option == "height" or option == "width" then
		-- Pixels, not units, since the block went on the grid. The old ceiling
		-- was written when the numbers were UI units, which on a screen taller
		-- than 768 buy more than one pixel each, so the same setting draws a
		-- smaller square now and the range has to reach further to put it back.
		local low, high = 18, 72
		if option == "width" then
			low, high = 90, 360
		end
		local size = ns.Command.Number(value, low, high, "skin " .. option)
		if size then
			ns.db[option == "height" and "skinHeight" or "skinWidth"] = size
			ns.FrameSkin.Relayout()
			ns.Print("skin " .. option .. " " .. size .. ".")
		end
		return
	end

	if FRAME_WORDS[option] then
		ns.db.skinFrames[option] = ns.Command.Toggle(value)
		ns.FrameSkin.Apply()
		ns.Print(FRAME_WORDS[option] .. " skin "
			.. (ns.db.skinFrames[option] and "on" or "off") .. ".")
		return
	end

	ns.db.skin = ns.Command.Toggle(option)
	ns.FrameSkin.Apply()
	ns.Print("unit frame skin " .. (ns.db.skin and "on" or "off")
		.. ", " .. ns.FrameSkin.Describe() .. ".")
end

-- What the bars cost is one number and what they cost per mob is another, and
-- the performance tab cannot tell them apart without being told how many are
-- up. Registered from here rather than from EnemyBars, because a behaviour file
-- names nothing outside its own folder.
if ns.Perf then
	ns.Perf.Gauge("enemy bars on screen", function()
		return ns.EnemyBars.Count()
	end)
end

ns.Register({
	name = "unit frames",
	order = 6,

	defaults = {
		bars = true,
		barsMode = "auto",     -- "auto" follows the nameplate cvar, or force "plates" / "list"
		barsStyle = "replace", -- "replace" takes over the nameplate look, "attach" rides above Blizzard's
		barsOffset = 0,
		barsMarker = true,
		barsLevel = true, -- the mob tag: level coloured by XP value, plus the reaction stripe
		barsClickThrough = false, -- the camera, at the price of click targeting and marking on a plate
		-- Which buttons a plate hands back to the world while keeping the
		-- rest. "right" is the default because it buys the camera drag and
		-- costs only right-click-to-interact and ctrl-right-click cross
		-- marking on a plate, both of which have somewhere else to happen.
		-- "left" or "both" give up click targeting, which is what
		-- barsClickThrough already does more plainly. "off" is the old
		-- all-or-nothing behaviour.
		barsCamera = "right",
		barsMax = 8,
		-- Pixels, like every other size in the bars, and one figure for both
		-- modes. A bar on a plate used to take the plate's own width, which
		-- was a number nobody chose and one that moved every time the driver
		-- was told how much room a bar wants.
		barsWidth = 180,

		-- A whole number, because the bars are drawn on a pixel grid and a
		-- fractional zoom would put every edge back on a half pixel. 1 is the
		-- design size, which is the same physical size on every monitor and is
		-- small on a 4K one.
		barsZoom = 1,

		-- Whether the addon owns nameplateMotion, nameplateOverlapV and the
		-- enemy plate size, which between them are what stops two bars landing
		-- on top of each other. Off means the client's own, untouched.
		barsStack = true,

		-- What those two CVars were before the addon first wrote to them, so
		-- turning the setting off puts back what was actually there. Empty is
		-- the sentinel for "not remembered yet". Account scoped, because the
		-- CVars are.
		platesMotionPrior = "",
		platesOverlapPrior = "",
		barsPoint = { "CENTER", "UIParent", "CENTER", 280, 120 },

		-- The square skin on the player, target and target of target frames.
		-- On by default for the reason the bar art strip is: it is the point
		-- of the part, and one word turns it off without a reload.
		skin = true,

		-- One switch per frame under that one, because they do not fail
		-- together. Target of target is the one to reach for: Blizzard parks
		-- it across the target's aura row, so ours lands there too.
		skinFrames = { player = true, target = true, tot = true },

		-- The block's shape, as a setting rather than a constant, because the
		-- first shipped guess was a square as tall as Blizzard's portrait and
		-- that was far too tall in both directions that matter: it crowded the
		-- text and it dropped target of target onto the target's aura row.
		-- Target of target takes a fixed fraction of both.
		--
		-- Pixels, like every size in the enemy bars, because the block sits on
		-- the same grid. 34 is 34 pixels on a laptop and 34 on a 4K panel, which
		-- is the point of the grid and also the whole of what it costs.
		skinHeight = 34,
		skinWidth = 168,
	},

	words = {
		bars = function(arg)
			BarsWord(arg:match("^(%S*)%s*(.-)$"))
		end,

		skin = SkinWord,
	},

	help = {
		"bars on|off, bars mode auto|plates|list, bars style replace|attach",
		"bars offset <-60-60>, bars marker on|off, bars level on|off",
		"bars clickthrough on|off, bars camera right|left|both|off",
		"bars max <1-15>, bars width <120-400>, bars zoom <1-3>",
		"bars stack on|off, whether the client spaces plates by the size of our bar",
		"skin on|off, the square player, target and target of target frames",
		"skin player|target|tot on|off, one frame at a time",
		"skin height <18-72>, skin width <90-360>, both in screen pixels",
		"skin probe, what this client answered for each frame",
	},

	status = function()
		return ("bars %s, mode %s (%s), style %s, up to %d, plates %s, camera %s%s; screen %s; %s; font %s; skin %s")
			:format(ns.db.bars and "on" or "off", ns.db.barsMode,
				ns.EnemyBars.Mode(), ns.db.barsStyle, ns.db.barsMax,
				ns.db.barsClickThrough and "click through" or "clickable",
				ns.EnemyBars.CameraState(),
				ns.HasThreat() and "" or ", no threat api so colour is who each mob is hitting",
				ns.UI.Describe(), ns.Plates.Describe(), ns.UI.FontName(),
				ns.FrameSkin.Describe())
	end,

	lock = function()
		ns.EnemyBars.ApplyLock()
	end,

	reset = function()
		-- A fresh table, not ns.DefaultFor: dragging mutates the anchor in place.
		ns.db.barsPoint = { "CENTER", "UIParent", "CENTER", 280, 120 }
		ns.db.barsWidth = ns.DefaultFor("barsWidth")
		ns.db.barsOffset = ns.DefaultFor("barsOffset")
		ns.db.barsCamera = ns.DefaultFor("barsCamera")
		ns.db.barsZoom = ns.DefaultFor("barsZoom")
		ns.db.barsStack = ns.DefaultFor("barsStack")
		ns.EnemyBars.ApplyLayout()
		ns.EnemyBars.Rebuild()
		ns.db.skin = ns.DefaultFor("skin")
		-- A fresh table, not ns.DefaultFor: the default is handed out by
		-- reference and every toggle since has been writing into it.
		ns.db.skinFrames = { player = true, target = true, tot = true }
		ns.db.skinHeight = ns.DefaultFor("skinHeight")
		ns.db.skinWidth = ns.DefaultFor("skinWidth")
		ns.FrameSkin.Apply()
	end,

	panel = function(ui)
		ui.Header("Enemy bars")
		ui.Check("show enemy bars",
			function() return ns.db.bars end,
			function(value)
				ns.db.bars = value
				ns.EnemyBars.Rebuild()
			end)
		ui.Cycle("mode", { "auto", "plates", "list" },
			function() return ns.db.barsMode end,
			function(value)
				ns.db.barsMode = value
				ns.EnemyBars.Rebuild()
			end)
		ui.Cycle("style", { "replace", "attach" },
			function() return ns.db.barsStyle end,
			function(value)
				ns.db.barsStyle = value
				ns.EnemyBars.Rebuild()
			end)
		ui.Cycle("button a plate hands back to the camera", { "right", "left", "both", "off" },
			function() return ns.db.barsCamera end,
			function(value)
				ns.db.barsCamera = value
				ns.EnemyBars.Rebuild()
			end)
		ui.Note(function()
			local state = ns.EnemyBars.CameraState()
			if state == "moot" then
				return "clickthrough is on below, so the plate has no mouse and every button already reaches the camera."
			elseif state == "unavailable" then
				return "this client has no SetPassThroughButtons, so it is the whole plate or none of it. Use clickthrough below."
			elseif state == "off" then
				return "the plate keeps every button, so a drag that starts on a bar will not turn the camera."
			elseif state == "unproven" then
				return "nothing has come up yet. This answers once a nameplate appears."
			elseif state == "right" then
				return "right button turns the camera, left still targets and ctrl-left still marks. Ctrl-right-click cross marking on a plate is the cost."
			end
			return "click targeting on a plate is gone with the button you handed back."
		end)
		ui.Check("plates pass the mouse through (camera turns, no click targeting)",
			function() return ns.db.barsClickThrough end,
			function(value)
				ns.db.barsClickThrough = value
				ns.EnemyBars.Rebuild()
			end)
		ui.Note(function()
			if ns.db.locked then
				return "unlock the frames to outline what each plate actually takes the mouse over."
			end
			return "the red outline on each plate is the region that takes the mouse. Our bar is anchored to it, so the two should agree."
		end)
		ui.Check("mob tag: level by XP value, stripe by hostile or neutral",
			function() return ns.db.barsLevel end,
			function(value)
				ns.db.barsLevel = value
				ns.EnemyBars.ApplyLayout()
				ns.EnemyBars.Rebuild()
			end)
		ui.Check("draw our own raid marker",
			function() return ns.db.barsMarker end,
			function(value)
				ns.db.barsMarker = value
				ns.EnemyBars.Rebuild()
			end)
		ui.Stepper("bar height on the plate", -60, 60, 2,
			function() return ns.db.barsOffset end,
			function(value)
				ns.db.barsOffset = value
				ns.EnemyBars.Rebuild()
			end)
		ui.Stepper("list bars", 1, 15, 1,
			function() return ns.db.barsMax end,
			function(value) ns.db.barsMax = value end)
		ui.Stepper("bar width, in pixels", 120, 400, 10,
			function() return ns.db.barsWidth end,
			function(value)
				ns.db.barsWidth = value
				ns.EnemyBars.ApplyLayout()
			end)
		ui.Stepper("zoom, whole steps only", 1, 3, 1,
			function() return ns.db.barsZoom end,
			function(value)
				ns.db.barsZoom = value
				ns.EnemyBars.ApplyLayout()
				ns.EnemyBars.Rebuild()
			end)
		ui.Note(function()
			return "Every size in the bars is a count of screen pixels, so a bar is the"
				.. " same physical size on any monitor and its edges are exactly one pixel."
				.. " Zoom multiplies that by a whole number, which is the only way to make"
				.. " a pixel grid bigger without leaving it. " .. ns.UI.Describe() .. "."
		end)
		ui.Check("let the client space nameplates by the size of our bar",
			function() return ns.db.barsStack end,
			function(value)
				ns.db.barsStack = value
				ns.Plates.Apply()
			end)
		ui.Note(function()
			if not ns.db.barsStack then
				return "Off, so nameplate motion, nameplate overlap and plate size are the"
					.. " client's own. Two mobs standing together will put two bars on top"
					.. " of each other, because the client is spacing Blizzard's nameplate"
					.. " and ours is twice the height of it."
			end
			return "Blizzard's driver decides where a plate goes, and it spaces them by how"
				.. " big it thinks a plate is. This tells it the real figure and asks it to"
				.. " stack rather than overlap. The cost is that a plate takes the mouse over"
				.. " the whole bar, which is more to click and more of a camera drag swallowed."
				.. " Turning it off puts all three back. Now: " .. ns.Plates.Describe() .. "."
		end)

		ui.Header("Player, target and target of target")
		ui.Check("square frames in your class colour",
			function() return ns.db.skin end,
			function(value)
				ns.db.skin = value
				ns.FrameSkin.Apply()
			end)
		ui.Stepper("frame height, in pixels", 18, 72, 2,
			function() return ns.db.skinHeight end,
			function(value)
				ns.db.skinHeight = value
				ns.FrameSkin.Relayout()
			end)
		ui.Stepper("frame width, in pixels", 90, 360, 6,
			function() return ns.db.skinWidth end,
			function(value)
				ns.db.skinWidth = value
				ns.FrameSkin.Relayout()
			end)
		for _, frame in ipairs({ { "player", "the player frame" },
			{ "target", "the target frame" },
			{ "tot", "target of target, which sits on the target's auras" } }) do
			ui.Check("skin " .. frame[2],
				function() return ns.db.skinFrames[frame[1]] end,
				function(value)
					ns.db.skinFrames[frame[1]] = value
					ns.FrameSkin.Apply()
				end)
		end
		ui.Note(function()
			if not ns.db.skin then
				return "Blizzard's own frames, exactly as they shipped. "
					.. ns.FrameSkin.Describe() .. "."
			end
			return "The ring and the banner are hidden, the portrait is square, and the"
				.. " gauge and its edge take the class colour, or the reaction colour on"
				.. " anything without a class. The raid marker stays. Nothing is rebuilt:"
				.. " clicking, the dropdown, auras and the cast bar are still Blizzard's,"
				.. " and turning this off puts every piece back without a reload. "
				.. ns.FrameSkin.Describe() .. "."
		end)
	end,
})
