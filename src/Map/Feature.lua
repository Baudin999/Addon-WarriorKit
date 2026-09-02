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
--
-- A word after it names one quest instead, matched on any part of its title and
-- printed whether the client calls it finished or not. That is the half the
-- ready-to-hand-in sweep cannot reach: a quest the log draws as complete and
-- the client does not flag is a quest the sweep walks straight past, and "it is
-- not in the list" is the one answer that tells you nothing.
--
-- Client.Open first, for the reason Quests/Log.lua gives. A collapsed header
-- hides its quests from the client's own row count, so a sweep that does not
-- open them reports on the zones you happen to have unfolded and calls that
-- your quest log.
local function TurnIns(want)
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
	Client.Open()
	local needle = want ~= "" and want:lower() or nil
	local entries = Client.Count()
	local found = 0
	for index = 1, entries do
		local row = Client.Entry(index)
		if row and not row.header and row.id then
			local wanted = needle and row.title:lower():find(needle, 1, true) ~= nil
				or (not needle and row.complete)
			if wanted then
				found = found + 1
				ns.Print(('"%s" (%d), %s: %s.'):format(row.title, row.id,
					row.complete and "the client calls it finished"
						or "the client does not call it finished",
					ns.MapPins.Chase(row.id, map)))
			end
		end
	end
	if found == 0 then
		ns.Print(needle
			and ("nothing in your quest log is called %q."):format(want)
			or "nothing in your quest log is ready to hand in.")
	end
end

--------------------------------------------------------------------------
-- The places, as a page of tick boxes and as a word
--------------------------------------------------------------------------

-- One kind of place switched, and the map painted again if it is open.
-- Map/Places.lua carries the reason the state is Questie's and not this
-- addon's.
--
-- Painted now rather than a moment later, and that is a known short fall.
-- Questie spawns a kind of NPC over a few ticks, thirty two a hundredth of a
-- second, so a repaint on the click has the mailboxes, which Questie draws in
-- one go, and not yet the flight masters. They are on the map the next time
-- it is painted, which is when it opens and on every quest log event, and in
-- play that is the next few seconds. A repaint booked half a second out would
-- be the whole chart on a tick path, which is what the hot path scan in
-- scripts/hot.lua refuses, and it is right to.
local function SetPlace(label, on)
	local changed = ns.MapPlaces.Set(label, on)
	if changed then
		ns.MapWindow.Refresh()
	end
	return changed
end

-- The page. One tick box per kind of place Questie offers this character, in
-- Questie's own order and under Questie's own labels, with a hairline between
-- the townsfolk, the vendors and the trainers, which is where Questie's own
-- dropdown breaks into its two submenus.
--
-- Built out of the list at the panel's build, which is login, and Questie's
-- lists are saved variables it fills on its first ever login, so on every
-- login after that the rows are there. On the first they are not, and the
-- page says so instead of drawing an empty checklist that looks like a bug.
local function PlacesPage(ui)
	ui.Section("Places", "Windows")
	ui.Lede("The flight masters, innkeepers, mailboxes, trainers and vendors Questie can draw, ticked on here rather than in the dropdown behind its minimap button.")
	local rows = ns.MapPlaces.List()
	local group
	for index = 1, #rows do
		local row = rows[index]
		if group and row.group ~= group then
			ui.Divider()
		end
		group = row.group
		local label = row.label
		ui.Check(label,
			function() return ns.MapPlaces.On(label) end,
			function(on) SetPlace(label, on) end)
	end
	if #rows == 0 then
		ui.Hint("Questie fills this list on its first login and keeps it, so on a fresh install the boxes are here after the next reload.")
	end
	ui.Reading("the places", ns.MapPlaces.Describe)
	ui.Hint("A tick here is a tick in Questie's own menu, and both maps draw the same places.")
end

-- The word: the whole list with no argument, or one kind switched.
--
-- The kind is every word before the last, because Questie's labels have
-- spaces in them: "Flight Master" is two words and "Class Trainer" is two, and
-- a word that took only the first would find neither.
local function PlacesWord(rest)
	if rest == "" then
		local lines = ns.MapPlaces.Lines()
		if #lines == 0 then
			ns.Print(ns.MapPlaces.Describe() .. ".")
			return
		end
		for index = 1, #lines do
			ns.Print(lines[index] .. ".")
		end
		return
	end
	local label, switch = rest:match("^(.-)%s+(%S+)$")
	if not label or (switch ~= "on" and switch ~= "off") then
		ns.Print("map places takes a kind of place and then on or off.")
		return
	end
	local changed = SetPlace(label, switch == "on")
	if changed == nil then
		ns.Print(("Questie offers no kind of place called %q."):format(label))
		return
	end
	ns.Print(("%s is %s%s."):format(label, switch,
		changed and "" or ", and it already was"))
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
		TurnIns(rest)
	elseif word == "group" then
		ns.Print(ns.MapMates.Describe() .. ".")
	elseif word == "places" then
		-- The untouched line rather than the lowered one, because the word
		-- prints the kind back and "flight master" is not what Questie calls it.
		PlacesWord((select(2, rawArg:match("^(%S*)%s*(.-)$"))))
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
		ns.Print("map takes on, off, hide, zones, markers, turnins, group or places.")
	end
	-- rawArg is the untouched line, and places is the one sub-word above with
	-- a use for it: every other takes a switch rather than a name.
	return rawArg
end

--------------------------------------------------------------------------

ns.Register({
	name = "map",
	order = 27,

	switch = {
		key = "worldMap",
		label = "the world map",
		says = "A column of zone names answers 'show me Desolace' in one click. On the picture, left steps into what is under it and right steps out to the continent, which is a row at the top of its group.",
		apply = function(value) SetMap(value) end,
	},

	zooms = {
		{ key = "mapZoom", label = "Map", window = true },
	},

	defaults = {
		-- 1.3, and it was 1.25 when every window in the addon shared one number.
		-- A tenth is the step now and 1.25 is not on one, so a default that
		-- stayed there would be a value the page cannot reach and the reset
		-- cannot restore. A window at 1 is a window you lean in to read on the
		-- panel most people are playing on, and the screen height already
		-- doubles this where a panel is tall enough to need it.
		mapZoom = 1.3,

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
		"map turnins <name>, the same for one quest, finished or not",
		"map group, whether the client will say where the people you are with are",
		"map places, every kind of place Questie can draw, and which are on",
		"map places <kind> on|off, one of them switched, in Questie and on both maps",
	},

	status = function()
		return ("%s; %s; %s; Blizzard's %s"):format(
			ns.MapWindow.Describe(), ns.MapZones.Describe(),
			ns.MapPlaces.Describe(), ns.MapBlizzard.Describe())
	end,

	panel = function(ui)
		ui.Section("World map", "Windows")
		ui.Lede("Every zone in the game down the left, the one you picked beside it with Questie's markers and your group on top, and a line under it saying who it is for.")
		ui.Check("put Blizzard's world map in the attic",
			function() return ns.db.worldMapHideBlizz end,
			SetHide)
		ui.Hint("The M key opens this window while that is ticked. Untick it and both maps work, with the key opening Blizzard's.")
		ui.Reading("the zone list", ns.MapZones.Describe)
		ui.Reading("the markers", ns.MapPins.Describe)
		ui.Reading("your group", ns.MapMates.Describe)
		ui.Reading("this window", ns.MapWindow.Describe)
		ui.Reading("Blizzard's window", ns.MapBlizzard.Describe)

		PlacesPage(ui)
	end,
})
