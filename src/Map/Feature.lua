local ADDON, ns = ...

-- Everything Core and the panel need to know about the world map. Zones.lua,
-- Pins.lua, Window.lua and Blizzard.lua hold the behaviour, and this is the
-- only file in the folder that names anything outside it.

local function SetMap(value)
	ns.db.worldMap = value
	if value then
		ns.MapWindow.Build()
	else
		ns.MapWindow.Hide()
	end
	ns.MapBlizzard.Apply()
end

local function SetHide(value)
	ns.db.worldMapHideBlizz = value
	ns.MapBlizzard.Apply()
end

--------------------------------------------------------------------------
-- The slash word
--------------------------------------------------------------------------

local function MapWord(arg, rawArg)
	local word, rest = arg:match("^(%S*)%s*(.-)$")

	if word == "hide" then
		SetHide(ns.Command.Toggle(rest))
		ns.Print("Blizzard's world map is " .. ns.MapBlizzard.Describe() .. ".")
	elseif word == "zones" then
		ns.Print(ns.MapZones.Describe() .. ".")
	elseif word == "markers" then
		ns.Print(ns.MapPins.Describe() .. ".")
	elseif word == "on" or word == "off" then
		SetMap(word == "on")
		ns.Print("the world map is " .. (ns.db.worldMap and "on" or "off") .. ".")
	elseif word == "" then
		if not ns.db.worldMap then
			ns.Print("the world map is off. Type /wk map on.")
			return
		end
		ns.MapWindow.Toggle()
	else
		ns.Print("map takes on, off, hide, zones or markers.")
	end
	-- rawArg is the untouched line, which this word has no use for: every
	-- sub-word above takes a switch rather than a name. Named so the signature
	-- matches every other word in the addon and so the next one that needs it
	-- does not have to change the registration.
	return rawArg
end

--------------------------------------------------------------------------

ns.Register({
	name = "map",
	order = 27,

	switch = {
		key = "worldMap",
		label = "the world map",
		apply = function(value) SetMap(value) end,
	},

	defaults = {
		-- On. Everything it replaces is one tick box away.
		worldMap = true,

		-- Blizzard's own goes in the attic, and M opens this one.
		--
		-- Caged rather than parked, the same as the quest log: nothing about
		-- the world map is a live server session, so hiding the frame costs
		-- nothing. Map/Blizzard.lua carries the argument in full.
		worldMapHideBlizz = true,
	},

	words = {
		map = MapWord,
	},

	help = {
		"map, open the world map",
		"map on|off, the addon's world map instead of the client's",
		"map hide on|off, put Blizzard's own map in the attic and take the M key",
		"map zones, how many zones the client will name and how many have a level range",
		"map markers, whether Questie is answering for the markers on the map",
	},

	status = function()
		return ("%s; %s; Blizzard's %s"):format(
			ns.MapWindow.Describe(), ns.MapZones.Describe(),
			ns.MapBlizzard.Describe())
	end,

	panel = function(ui)
		ui.Section("World map", "Chores")
		ui.Lede("Every zone in the game down the left, the one you picked drawn beside it with Questie's markers on top, and a line along the bottom saying who that zone is for.")
		ui.Check("the addon's world map",
			function() return ns.db.worldMap end,
			SetMap)
		ui.Hint("The client's map navigates by clicking a continent and then the piece of coastline you think is the place you meant. This one has a column of zone names, which answers 'show me Desolace' in one click.")
		ui.Check("put Blizzard's world map in the attic",
			function() return ns.db.worldMapHideBlizz end,
			SetHide)
		ui.Hint("The M key opens this window while that is ticked. Untick it and both maps work, with the key opening Blizzard's.")
		ui.Reading("the zone list", ns.MapZones.Describe)
		ui.Reading("the markers", ns.MapPins.Describe)
		ui.Reading("this window", ns.MapWindow.Describe)
		ui.Reading("Blizzard's window", ns.MapBlizzard.Describe)
	end,
})
