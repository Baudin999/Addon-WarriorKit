local ADDON, ns = ...

-- Everything Core and the panel need to know about the quest log. Client.lua,
-- Log.lua, Party.lua, Where.lua, Window.lua, Blizzard.lua, Tracker.lua and
-- TrackerOff.lua hold the behaviour, and this is the only file in the folder
-- that names anything outside it.

local function SetQuests(value)
	ns.db.quests = value
	if value then
		ns.QuestWindow.Build()
	else
		ns.QuestWindow.Hide()
	end
	ns.QuestBlizzard.Apply()
	ns.QuestTracker.Apply()
	ns.QuestTrackerOff.Apply()
	ns.QuestColumn.Apply()
end

local function SetHide(value)
	ns.db.questsHideBlizz = value
	ns.QuestBlizzard.Apply()
	ns.QuestTracker.Apply()
end

-- One switch and one tracker. Questie's goes off through Questie's own call and
-- this addon's goes up in its place, so the box is thrown once and the screen
-- never holds both.
local function SetTrackerOff(value)
	ns.db.questsTrackerOff = value
	ns.QuestTrackerOff.Apply()
	ns.QuestColumn.Apply()
end

--------------------------------------------------------------------------
-- The slash word
--------------------------------------------------------------------------

local function QuestWord(arg, rawArg)
	local word, rest = arg:match("^(%S*)%s*(.-)$")

	if word == "hide" then
		SetHide(ns.Command.Toggle(rest))
		ns.Print("Blizzard's quest log is " .. ns.QuestBlizzard.Describe() .. ".")
	elseif word == "tracker" then
		SetTrackerOff(ns.Command.Toggle(rest))
		ns.Print("Questie's tracker is " .. ns.QuestTrackerOff.Describe() .. ".")
	elseif word == "where" then
		ns.Print(ns.QuestWhere.Describe() .. ".")
	elseif word == "drops" then
		ns.Print("a creature's hover says " .. ns.QuestDrops.Describe() .. ".")
	elseif word == "party" then
		ns.Print(ns.QuestParty.Describe() .. ".")
	elseif word == "on" or word == "off" then
		SetQuests(word == "on")
		ns.Print("the quest log is " .. (ns.db.quests and "on" or "off") .. ".")
	elseif word == "" then
		if not ns.db.quests then
			ns.Print("the quest log is off. Type /wk quests on.")
			return
		end
		ns.QuestWindow.Toggle()
	else
		ns.Print("quests takes on, off, hide, tracker, where, drops or party.")
	end
	-- rawArg is the untouched line, which this word has no use for: every
	-- sub-word above takes a switch rather than a name. Named so the signature
	-- matches every other word in the addon and so the next one that needs it
	-- does not have to change the registration.
	return rawArg
end

--------------------------------------------------------------------------

ns.Register({
	name = "quests",
	order = 24,

	switch = {
		key = "quests",
		label = "the quest log",
		says = "The client's own log draws six of your quests through a slot and pushes the list off the window to show you one of them. This one draws the whole log at once and never moves it.",
		apply = function(value) SetQuests(value) end,
	},

	zooms = {
		{ key = "questsZoom", label = "Quest log", window = true },
	},

	defaults = {
		-- 1.3, and it was 1.25 when every window in the addon shared one number.
		-- A tenth is the step now and 1.25 is not on one, so a default that
		-- stayed there would be a value the page cannot reach and the reset
		-- cannot restore. A window at 1 is a window you lean in to read on the
		-- panel most people are playing on, and the screen height already
		-- doubles this where a panel is tall enough to need it.
		questsZoom = 1.3,

		-- On. The client's own log shows six of your twenty quests through a
		-- slot and pushes the list off the window to show you one of them, and
		-- everything this replaces it with is reversible in one press.
		quests = true,

		-- Blizzard's own goes in the attic, and L opens this one.
		--
		-- Caged rather than parked, unlike the mail window: nothing about the
		-- quest log is a live server session, so hiding the frame costs nothing.
		-- Quests/Blizzard.lua carries the argument in full.
		questsHideBlizz = true,

		-- Questie's own tracker, left alone.
		--
		-- Off, unlike the switch above it, and the difference is whose setting
		-- moves. Caging Blizzard's window is this addon's business and undoing
		-- it is one tick box; switching Questie's tracker off writes that
		-- addon's saved variable and reloads the interface doing it, which is
		-- not a thing to ship as a default and find out about afterwards.
		-- Quests/TrackerOff.lua carries the argument in full.
		questsTrackerOff = false,

		-- Where this addon's own tracker sits, which is the one setting it has.
		-- The top left corner, fifteen pixels in from both edges. The right of
		-- the screen is where this game has put a quest tracker since 2004 and
		-- it is also where this addon already puts the loot feed, the cooldown
		-- row and the player's own frame, so a column dropped there lands on top
		-- of something on most screens. The top left is empty on all of them.
		questsColumnPoint = { "TOPLEFT", "UIParent", "TOPLEFT", 15, -15 },

		-- Whether this addon is the one holding that tracker off. A record and
		-- not a preference, so Core/Core.lua keeps it out of the reset: it is
		-- the only note of whether Questie's setting is ours to put back.
		questsTrackerTook = false,

		-- The drop ledger, empty. One row per creature Questie has said carries
		-- a quest item, filled in as you loot. Registered here rather than in
		-- Quests/Drops.lua because that file has no rail entry of its own and a
		-- setting has to belong to a registered part; kept out of the reset in
		-- Core/Core.lua, because it is a record and not a preference.
		questDrops = {},
	},

	charDefaults = {
		-- The quests you pinned, as Log.Key gives them, oldest pin first.
		--
		-- This character's, because a quest log is: a pin the account shared
		-- would be a note about a quest most of your characters cannot see. Empty
		-- and uncapped, and Quests/Log.lua argues on disk why it is this list
		-- rather than the client's five watch slots.
		questPins = {},
	},

	words = {
		quests = QuestWord,
	},

	help = {
		"quests, open the quest log",
		"quests on|off, the addon's quest log instead of the client's",
		"quests hide on|off, put Blizzard's own log in the attic and take the L key",
		"quests tracker on|off, switch Questie's own tracker off through Questie",
		"quests where, whether Questie is answering for the where column and the map",
		"quests drops, what a hover over a creature says about the quest items it carries",
		"quests party, what can say how many of your group are on a quest",
	},

	lock = function()
		ns.QuestColumn.Lock()
	end,

	status = function()
		-- Questie's tracker is named here because this is the one setting the
		-- addon moves that belongs to somebody else. A player who cannot see
		-- which way it is and who put it there reads a missing tracker as
		-- Questie having broken.
		return ("%s; %s; Blizzard's %s; Questie's tracker is %s"):format(
			ns.QuestWindow.Describe(), ns.QuestLog.Describe(),
			ns.QuestBlizzard.Describe(), ns.QuestTrackerOff.Describe())
	end,

	panel = function(ui)
		ui.Section("Quests", "Windows")
		ui.Lede("Every quest you are on down the left, grouped by zone. In the middle, what this one wants, or a map of where it wants it. On the right, what it pays.")
		ui.Check("put Blizzard's quest log in the attic",
			function() return ns.db.questsHideBlizz end,
			SetHide)
		ui.Hint("The L key opens this window while that is ticked. Untick it and both windows work, with the key opening Blizzard's.")
		ui.Check("switch Questie's own tracker off",
			function() return ns.db.questsTrackerOff end,
			SetTrackerOff)
		ui.Hint("This is Questie's own Enable Tracker switch, so it reloads the interface both ways, and this addon's own tracker takes the screen it leaves.")
		ui.Reading("your log", ns.QuestLog.Describe)
		-- The pin's cost, said where the pin count is read. Questie's icons are
		-- the only place the client's watch list is worth anything to this
		-- addon's player, and a pin never reaches it.
		ui.Hint("Shift click a quest to pin it, or press pin under it. Pins are this character's and uncapped. The cost is Questie: its map icons can be filtered to tracked quests and a pin is not one.")
		ui.Reading("this addon's own tracker", ns.QuestColumn.Describe)
		ui.Reading("a creature's quest drops", ns.QuestDrops.Describe)
		ui.Reading("the where column and the map", ns.QuestWhere.Describe)
		ui.Reading("who else in your group is on a quest", ns.QuestParty.Describe)
		ui.Reading("clicking Questie's tracker", ns.QuestTracker.Describe)
		ui.Reading("Questie's tracker itself", ns.QuestTrackerOff.Describe)
		ui.Reading("Blizzard's window", ns.QuestBlizzard.Describe)
	end,
})
