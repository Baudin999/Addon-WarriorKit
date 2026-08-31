local ADDON, ns = ...

-- Everything Core and the panel need to know about the bag window. Bags.lua,
-- Grid.lua, Window.lua and Blizzard.lua hold the behaviour, and this is the
-- only file in the folder that names anything outside it.

local LOW_COLUMNS, HIGH_COLUMNS = 6, 16

local function SetBags(value)
	ns.db.bags = value
	if not value then
		ns.BagsWindow.Hide()
	end
	ns.BagsBlizzard.Apply()
end

local function SetHide(value)
	ns.db.bagsHideBlizz = value
	ns.BagsBlizzard.Apply()
end

local function SetColumns(value)
	ns.db.bagColumns = value
	ns.BagsWindow.Refit()
end

--------------------------------------------------------------------------
-- The slash word
--------------------------------------------------------------------------

local function BagsWord(arg, rawArg)
	local word, rest = arg:match("^(%S*)%s*(.-)$")

	if word == "hide" then
		SetHide(ns.Command.Toggle(rest))
		ns.Print("the client's bags are " .. ns.BagsBlizzard.Describe() .. ".")
	elseif word == "columns" then
		local count = ns.Command.Number(rest, LOW_COLUMNS, HIGH_COLUMNS, "bag columns")
		if count then
			SetColumns(count)
			ns.Options.Refresh()
			ns.Print(("the bag window is %d squares across."):format(count))
		end
	elseif word == "count" then
		ns.Print(ns.Bags.Describe() .. ".")
	elseif word == "on" or word == "off" then
		SetBags(word == "on")
		ns.Options.Refresh()
		ns.Print("the bag window is " .. (ns.db.bags and "on" or "off") .. ".")
	elseif word == "" then
		if not ns.db.bags then
			ns.Print("the bag window is off. Type /wk bags on.")
			return
		end
		ns.BagsWindow.Toggle()
	else
		ns.Print("bags takes on, off, hide, columns or count.")
	end
	-- rawArg is the untouched line, which this word has no use for: every
	-- sub-word above takes a switch or a number rather than a name. Named so the
	-- signature matches every other word in the addon.
	return rawArg
end

--------------------------------------------------------------------------

ns.Register({
	name = "bags",
	order = 28,

	switch = {
		key = "bags",
		label = "the bag window",
		apply = function(value) SetBags(value) end,
	},

	defaults = {
		-- On. Everything it replaces is one tick box away.
		bags = true,

		-- The client's own nine bag calls, taken, so B opens this window.
		bagsHideBlizz = true,

		-- Ten across. Wide enough that the piles most people carry sit on one
		-- line each and narrow enough that the window is not half the screen.
		bagColumns = 10,
	},

	words = {
		bags = BagsWord,
	},

	help = {
		"bags, open the bag window",
		"bags on|off, one window with your bags grouped instead of five of the client's",
		"bags hide on|off, take the client's own bag calls so B opens this one",
		"bags columns <6-16>, how many squares across",
		"bags count, how many slots you have and how many are free",
	},

	status = function()
		return ("%s; the client's %s"):format(
			ns.BagsWindow.Describe(), ns.BagsBlizzard.Describe())
	end,

	panel = function(ui)
		ui.Section("Bags", "Chores")
		ui.Lede("One window instead of five, with what you carry sorted into the piles the client already files it under and the free slots counted along the bottom.")
		ui.Check("the addon's bag window",
			function() return ns.db.bags end,
			SetBags)
		ui.Hint("The piles are the client's own item classes, so they are right on the first frame after a login and in your own language. Junk is the exception: a grey goes to the bottom whatever class it is.")
		ui.Check("take the client's bag calls",
			function() return ns.db.bagsHideBlizz end,
			SetHide)
		ui.Hint("All nine, so B opens this window and a merchant no longer puts five of Blizzard's bags beside it. Another bag addon takes the same nine, so run one or the other.")
		ui.Count("columns", LOW_COLUMNS, HIGH_COLUMNS,
			function() return ns.db.bagColumns end,
			SetColumns)
		ui.Reading("what you are carrying", ns.Bags.Describe)
		ui.Reading("this window", ns.BagsWindow.Describe)
		ui.Reading("the client's bags", ns.BagsBlizzard.Describe)
		ui.Reading("the squares", ns.BagsGrid.Describe)
	end,
})
