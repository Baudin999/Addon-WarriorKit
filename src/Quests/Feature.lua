local ADDON, ns = ...

-- Everything Core and the panel need to know about the quest log. Client.lua,
-- Log.lua, Where.lua, Window.lua and Blizzard.lua hold the behaviour, and this
-- is the only file in the folder that names anything outside it.

local function SetQuests(value)
	ns.db.quests = value
	if value then
		ns.QuestWindow.Build()
	else
		ns.QuestWindow.Hide()
	end
	ns.QuestBlizzard.Apply()
end

local function SetHide(value)
	ns.db.questsHideBlizz = value
	ns.QuestBlizzard.Apply()
end

--------------------------------------------------------------------------
-- The slash word
--------------------------------------------------------------------------

local function QuestWord(arg, rawArg)
	local word, rest = arg:match("^(%S*)%s*(.-)$")

	if word == "hide" then
		SetHide(ns.Command.Toggle(rest))
		ns.Print("Blizzard's quest log is " .. ns.QuestBlizzard.Describe() .. ".")
	elseif word == "where" then
		ns.Print(ns.QuestWhere.Describe() .. ".")
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
		ns.Print("quests takes on, off, hide or where.")
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
	order = 23,

	switch = {
		key = "quests",
		label = "the quest log",
		apply = function(value) SetQuests(value) end,
	},

	defaults = {
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
	},

	words = {
		quests = QuestWord,
	},

	help = {
		"quests, open the quest log",
		"quests on|off, the addon's quest log instead of the client's",
		"quests hide on|off, put Blizzard's own log in the attic and take the L key",
		"quests where, whether Questie is answering for the where column",
	},

	status = function()
		return ("%s; %s; Blizzard's %s"):format(
			ns.QuestWindow.Describe(), ns.QuestLog.Describe(),
			ns.QuestBlizzard.Describe())
	end,

	panel = function(ui)
		ui.Section("Quests", "Chores")
		ui.Lede("A quest log three columns wide: every quest you are on down the left, grouped by zone, what this one wants in the middle, and what it pays on the right.")
		ui.Check("the addon's quest log",
			function() return ns.db.quests end,
			SetQuests)
		ui.Hint("The client's own log draws six of your quests through a slot and pushes the list off the window to show you one of them. This one draws the whole log at once and never moves it.")
		ui.Check("put Blizzard's quest log in the attic",
			function() return ns.db.questsHideBlizz end,
			SetHide)
		ui.Hint("The L key opens this window while that is ticked. Untick it and both windows work, with the key opening Blizzard's.")
		ui.Reading("your log", ns.QuestLog.Describe)
		ui.Reading("the where column", ns.QuestWhere.Describe)
		ui.Reading("Blizzard's window", ns.QuestBlizzard.Describe)
	end,
})
