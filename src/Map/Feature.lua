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
-- Where a finished quest's question mark went
--------------------------------------------------------------------------

-- One line per quest the client says is ready to hand in.
--
-- Written because "the question mark is missing" is not a question the map can
-- answer from the picture. The picture is the markers that survived, and every
-- interesting case is a marker that did not: Questie never drew one, Questie
-- drew one and hid it, or it drew one on a zone other than the one you are
-- standing in, which is what a quest you pick up in one place and hand in
-- another looks like from here.
--
-- Asked against the zone you are standing in rather than the zone on the board,
-- because you can read the board and you are typing this about the zone you are
-- in. Map/Pins.lua does the looking; this walks the log and prints.
local function TurnIns()
	local Client = ns.QuestClient
	if not Client.Ready() then
		ns.Print("this client will not answer for the quest log.")
		return
	end
	local map = ns.UI.Chart.Here()
	if not map then
		ns.Print("this client will not say which map you are on.")
		return
	end
	local entries = Client.Count()
	local found = 0
	for index = 1, entries do
		local row = Client.Entry(index)
		if row and not row.header and row.complete and row.id then
			found = found + 1
			ns.Print(('"%s": %s.'):format(row.title, ns.MapPins.Chase(row.id, map)))
		end
	end
	if found == 0 then
		ns.Print("nothing in your log is ready to hand in.")
	end
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
	elseif word == "turnins" then
		TurnIns()
	elseif word == "group" then
		ns.Print(ns.MapMates.Describe() .. ".")
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
		ns.Print("map takes on, off, hide, zones, markers, turnins or group.")
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
		"map turnins, where the question mark went for every quest you have finished",
		"map group, whether the client will say where the people you are with are",
	},

	status = function()
		return ("%s; %s; Blizzard's %s"):format(
			ns.MapWindow.Describe(), ns.MapZones.Describe(),
			ns.MapBlizzard.Describe())
	end,

	panel = function(ui)
		ui.Section("World map", "Chores")
		ui.Lede("Every zone in the game down the left, the one you picked beside it with Questie's markers and your group on top, and a line under it saying who it is for.")
		ui.Check("the addon's world map",
			function() return ns.db.worldMap end,
			SetMap)
		ui.Hint("A column of zone names answers 'show me Desolace' in one click. On the picture, left steps into what is under it and right steps out to the continent, which is a row at the top of its group.")
		ui.Check("put Blizzard's world map in the attic",
			function() return ns.db.worldMapHideBlizz end,
			SetHide)
		ui.Hint("The M key opens this window while that is ticked. Untick it and both maps work, with the key opening Blizzard's.")
		ui.Reading("the zone list", ns.MapZones.Describe)
		ui.Reading("the markers", ns.MapPins.Describe)
		ui.Reading("your group", ns.MapMates.Describe)
		ui.Reading("this window", ns.MapWindow.Describe)
		ui.Reading("Blizzard's window", ns.MapBlizzard.Describe)
	end,
})
