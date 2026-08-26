local ADDON, ns = ...

-- Everything Core and the panel need to know about the minimap. Shape.lua
-- reshapes and resizes the frame, Corral.lua holds the other addons' buttons,
-- and neither names anything outside this folder.
--
-- Two tabs and one rail entry, the shape Comfort already has. They are one
-- part rather than two because they are one decision: a square map is where
-- the corral button gets a corner to sit on, and taking eight icons off the
-- ring is most of the reason a square is worth having.

local function SetSquare(value)
	ns.db.minimapSquare = value
	ns.MinimapShape.Apply()
	-- The corral's default position is a corner of the map, and the map just
	-- changed size, so it is placed again rather than left where the old edge
	-- was. A dragged position is saved and Place keeps it.
	ns.Corral.Apply()
end

local function SetSize(value)
	ns.db.minimapSize = value
	ns.MinimapShape.Apply()
	ns.Corral.Apply()
end

local function SetCorral(value)
	ns.db.minimapCorral = value
	ns.Corral.Apply()
end

ns.Register({
	name = "minimap",
	order = 8,

	defaults = {
		-- On, the way the stripped bar art is on and for the same reason. Both
		-- take furniture off a frame the addon does not own, both put every bit
		-- of it back in one call with no reload, and neither hides anything you
		-- could have read. This is not the action bars, where on means somebody
		-- else's buttons disappear and a key stops working until you notice.
		minimapSquare = true,

		-- The client draws it at 140. 180 is about a third more map for a
		-- corner of the screen that had nothing else in it, and it is a number
		-- rather than a scale because the map is the one frame in the interface
		-- whose contents are drawn by the client at whatever size you ask for.
		minimapSize = 180,

		minimapCorral = true,

		-- Where the corral's face has been dragged to. Empty is the normal
		-- state and means the corner under the map decides, which is the shape
		-- barPoints has and for the same reason: a default of nil is a key the
		-- defaults table never carries, so the setting could not be reset to
		-- anything and /wk reset would have nothing to put back.
		corralPoint = {},
	},

	words = {
		minimap = function(arg)
			local option, value = arg:match("^(%S*)%s*(.-)$")

			if option == "size" then
				local size = tonumber(value)
				if not size then
					ns.Print("minimap " .. ns.MinimapShape.Describe() .. ".")
					return
				end
				SetSize(math.max(120, math.min(300, math.floor(size))))
				ns.Print("minimap " .. ns.MinimapShape.Describe() .. ".")
				return
			end

			if option == "buttons" then
				SetCorral(ns.Command.Toggle(value))
				ns.Print("addon buttons " .. ns.Corral.Describe() .. ".")
				return
			end

			if option == "list" then
				local names = ns.Corral.Names()
				if #names == 0 then
					ns.Print("the corral is holding nothing. " .. ns.Corral.Describe() .. ".")
					return
				end
				for _, name in ipairs(names) do
					ns.Print("  " .. name)
				end
				local pooled, refused = ns.Corral.Skipped()
				ns.Print(("%d held, %d left as map pins, %d refused past the ceiling.")
					:format(#names, pooled, refused))
				return
			end

			if option == "scan" then
				local taken = ns.Corral.Scan()
				ns.Print(("%d new button%s collected, %s.")
					:format(taken, taken == 1 and "" or "s", ns.Corral.Describe()))
				return
			end

			SetSquare(ns.Command.Toggle(option))
			ns.Print("minimap " .. ns.MinimapShape.Describe() .. ".")
		end,
	},

	help = {
		"minimap on|off, square rather than round",
		"minimap size <120-300>, how wide the map is drawn",
		"minimap buttons on|off, collect the addon buttons behind one square",
		"minimap scan, look for addon buttons that have appeared since login",
		"minimap list, name every button the corral is holding",
	},

	status = function()
		return ("%s; buttons %s"):format(ns.MinimapShape.Describe(), ns.Corral.Describe())
	end,

	lock = function()
		ns.Corral.Lock()
	end,

	reset = function()
		ns.Corral.Reset()
	end,

	panel = function(ui)
		ui.Header("Minimap")
		ui.Check("square rather than round",
			function() return ns.db.minimapSquare end,
			SetSquare)
		ui.Note(function()
			return "Minimap " .. ns.MinimapShape.Describe() .. "."
		end)
		ui.Note(function()
			if not ns.db.minimapSquare then
				return "The round mask throws away the corners of a map the client has already drawn, and the ring round it spends about twenty pixels of every edge on rivets."
			end
			return "The mask, the ring, the north tag and the two zoom buttons come off, and the mousewheel zooms instead. Everything goes back in one call, so off is a state rather than a reload."
		end)
		ui.Stepper("width in pixels", 120, 300, 10,
			function() return ns.db.minimapSize end,
			SetSize)
		ui.Note(function()
			if not ns.db.minimapSquare then
				return "The width only applies while the square is on. Round, the map is left at whatever this client draws it at."
			end
			return "Blizzard's own mail, tracking and battleground icons are moved to the corners of the square, because they were anchored to points on the arc and a square has no arc to hang them on."
		end)
		ui.Note(function()
			if not ns.db.minimapSquare then
				return "The ring is the only thing ending the picture on a round map, which is why the sun, the clock and the black edge below all wait for the square."
			end
			local reading = ns.MinimapClock.Describe()
			return ("The ring ended the picture and nothing else on it did, so the square gets the same black edge and hairline the action bars are built on. The clock hangs off the bottom of that edge in the middle%s, and the realm's time is on its tooltip.")
				:format(reading and (", reading " .. reading) or "")
		end)
		ui.Note(function()
			return "The sun and moon and Blizzard's own clock come off with the ring. The sun says whether it is day in a game whose sky says the same thing, and the clock draws its numbers on a strip of the old stone minimap tile, which on a stripped square is the last piece of Blizzard's map left on the screen."
		end)

		ui.Header("Addon buttons")
		ui.Check("collect them behind one square",
			function() return ns.db.minimapCorral end,
			SetCorral)
		ui.Note(function()
			return "Addon buttons " .. ns.Corral.Describe() .. ". Press the square to open the tray."
		end)
		ui.Note(function()
			if not ns.db.minimapCorral then
				return "Every addon that wants to be reachable puts a round icon on the edge of the minimap. With eight installed the map is a ring of icons with a map in the middle."
			end
			return "Each button is borrowed rather than taken. Its parent, its position and its own SetPoint are handed back the moment this goes off, and nothing about the button itself is changed, so it does in the tray exactly what it did on the ring."
		end)
		ui.Action(function()
			return ("look for new buttons (%d held)"):format(ns.Corral.Count())
		end,
			function()
				ns.Corral.Scan()
				ns.Options.Refresh()
			end,
			function() return ns.db.minimapCorral end)
		ui.Note(function()
			return "The scan runs at login, whenever an addon finishes loading, and whenever you open the tray. Nothing polls, so an addon that puts its button up on a timer of its own is found the next time you open the tray rather than the second it appears."
		end)
		ui.Note(function()
			return "Blizzard's own icons are left alone. The mail, the tracking and the calendar are read at a glance without being pressed, and the square above has already put them on the corners."
		end)
		ui.Note(function()
			local pooled, refused = ns.Corral.Skipped()
			if pooled == 0 and refused == 0 then
				return "The minimap is also where every addon that draws a pin on the map hangs the pin, and a pin is not a button. Nothing on this map looked like one."
			end
			if refused > 0 then
				return ("%d frames were left where they were as map pins, and %d more were refused because the corral will not hold more than it can lay out. Nothing is taken quietly.")
					:format(pooled, refused)
			end
			return ("%d frames on this map are pins rather than buttons and were left alone. They come in pools with generated names, which is what tells them apart from a button.")
				:format(pooled)
		end)
		ui.Action(function() return "put the square back under the map" end,
			function()
				ns.Corral.Reset()
				ns.Options.Refresh()
			end,
			function() return ns.Corral.Moved() end)
		ui.Note(function()
			if not ns.Corral.Moved() then
				return "Unlock the frames with /wk unlock and the square can be dragged anywhere. It starts under the bottom left corner of the map, off the frame rather than on it, so it covers none of the world the square was widened to show."
			end
			return "Dragged. The button above puts it back under the corner of the map."
		end)
	end,
})
