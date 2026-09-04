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
	order = 16,

	switch = {
		key = "minimapSquare",
		label = "the square minimap",
		apply = function(value) SetSquare(value) end,
	},

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
		ui.Section("Minimap", "The screen")
		ui.Lede("Takes the mask, the ring, the north tag and the zoom buttons off, and squares the map.")

		ui.Size("width", 120, 300, 10,
			function() return ns.db.minimapSize end,
			SetSize)
		ui.Hint("The width only applies while the square is on. Round, the map is left at whatever this client draws it at.")

		ui.Reading("minimap", ns.MinimapShape.Describe)
		ui.Reading("the clock", function()
			return ns.MinimapClock.Describe() or "not drawn until the square is on"
		end)

		ui.Section("Addon buttons", "The screen")
		ui.Lede("Collects the round icons other addons hang on the minimap edge into one tray.")
		ui.Check("collect them behind one square",
			function() return ns.db.minimapCorral end,
			SetCorral)
		ui.Hint("Each button is borrowed rather than taken: its parent, its position and its own SetPoint are handed back the moment this goes off.")

		ui.Action(function()
			return ("look for new buttons (%d held)"):format(ns.Corral.Count())
		end,
			function()
				ns.Corral.Scan()
				ns.Options.Refresh()
			end,
			function() return ns.db.minimapCorral end)
		ui.Hint("The scan runs at login, whenever an addon finishes loading and whenever you open the tray. Nothing polls, so a button put up on a timer is found next time you open it.")

		ui.Action(function() return "put the square back under the map" end,
			function()
				ns.Corral.Reset()
				ns.Options.Refresh()
			end,
			function() return ns.Corral.Moved() end)
		ui.Hint("Unlock the frames with /wk unlock and the square can be dragged anywhere. It starts under the bottom left corner of the map rather than on it.")

		ui.Reading("addon buttons", ns.Corral.Describe)
		ui.Reading("left alone", function()
			local pooled, refused = ns.Corral.Skipped()
			if pooled == 0 and refused == 0 then
				return "nothing on this map looked like a map pin"
			end
			if refused > 0 then
				return ("%d map pins, and %d refused because the tray was full"):format(pooled, refused)
			end
			return ("%d map pins rather than buttons"):format(pooled)
		end)
	end,
})
