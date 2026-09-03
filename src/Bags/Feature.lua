local ADDON, ns = ...

-- Everything Core and the panel need to know about the bag window. Bags.lua,
-- Stack.lua, Session.lua, Grid.lua, Merchant.lua, Window.lua and Blizzard.lua
-- hold the behaviour, and this and Window.lua are the only two files in the
-- folder that name anything outside it. Window.lua's one reach is the clutter
-- window, which its clear button opens and which it says why at.

local LOW_COLUMNS, HIGH_COLUMNS = 6, 16

-- How long the pointer holds still on a square before its box opens, in
-- milliseconds. Nought is the box on the way in, which is what every other
-- hover in the addon does; half a second is a box you have to wait for.
local LOW_HOVER, HIGH_HOVER, HOVER_STEP = 0, 500, 10

local function SetBags(value)
	ns.db.bags = value
	if not value then
		ns.BagsWindow.Hide()
	end
	ns.BagsBlizzard.Apply()
	ns.BagsMerchant.Apply()
end

local function SetHide(value)
	ns.db.bagsHideBlizz = value
	ns.BagsBlizzard.Apply()
end

local function SetColumns(value)
	ns.db.bagColumns = value
	ns.BagsWindow.Refit()
end

-- Nothing is redrawn. The square reads the number on the next hover.
local function SetHover(value)
	ns.db.bagHover = value
end

-- "50ms", "off". The unit goes after the number the way every duration on the
-- panel wears one, and nought is a word rather than a number because nought
-- milliseconds is not a short wait, it is no wait.
local function HoverLabel(value)
	value = tonumber(value) or 0
	if value <= 0 then
		return "off"
	end
	return value .. "ms"
end

-- What the record button on the settings page says, and what a press does.
--
-- Both are functions for the reason the stack pair below are: the kit asks on
-- every refresh, so the word on the page is the state the session is actually
-- in rather than the state it was in when the page was built.
local function SessionLabel()
	if ns.BagsSession.Running() then
		return "stop recording " .. (ns.BagsSession.Name() or "this session")
	end
	return "record what you pick up"
end

-- The second press, which says how much it is about to throw away. A function
-- for the same reason as the one above it.
local function ForgetLabel()
	local kinds = ns.BagsSession.Held()
	if kinds == 0 then
		return "forget the last session"
	end
	return ("forget the last session, %d item%s"):format(kinds, kinds == 1 and "" or "s")
end

-- What the button says. A function because the kit asks on every refresh, which
-- is how the label reads as the state it is in while the ticker is running.
local function StackLabel()
	if ns.BagsStack.Running() then
		return "putting your half stacks together"
	end
	return "put your half stacks together"
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
	elseif word == "hover" then
		-- The panel's own ruler, so a number typed here is a stop the panel
		-- can show and the reset can restore.
		local wait = ns.Command.Step(rest, LOW_HOVER, HIGH_HOVER, HOVER_STEP, "bag hover")
		if wait then
			SetHover(wait)
			ns.Options.Refresh()
			ns.Print(("a square's box opens after the pointer holds still for %s.")
				:format(HoverLabel(wait)))
		end
	elseif word == "count" then
		ns.Print(ns.Bags.Describe() .. ".")
	elseif word == "stack" then
		ns.BagsStack.Press()
	elseif word == "clear" then
		-- The same window the clear button in the title bar opens. Comfort's
		-- own `destroy` word opens it too, and both are kept: you type the one
		-- for the window you are thinking about, and this is the bag window.
		ns.Destroy.Show()
	elseif word == "session" then
		-- The rest of the line is a name, untouched, because a session called
		-- "second BRD run" is three words and every other sub-word in this
		-- feature takes a switch or a number. `clear` is the one reserved word,
		-- which costs a player who wanted to call a session that exactly
		-- nothing they will notice.
		if rest == "clear" then
			ns.BagsSession.Clear()
			ns.BagsWindow.Refresh()
			ns.Print("the session pile is empty.")
		elseif rest ~= "" and not ns.BagsSession.Running() then
			ns.BagsSession.Start(rest)
			ns.BagsWindow.Refresh()
			ns.Print(("recording what you pick up in %s.")
				:format(ns.BagsSession.Name()))
		else
			ns.BagsSession.Press()
		end
		ns.Options.Refresh()
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
		ns.Print("bags takes on, off, hide, columns, hover, count, stack, clear or session.")
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
		says = "The piles are the client's own item classes, so they are right on the first frame after a login and in your own language. Junk is the exception: a grey goes to the bottom whatever class it is.",
		apply = function(value) SetBags(value) end,
	},

	zooms = {
		{ key = "bagsZoom", label = "Bags", window = true },
	},

	-- This character's, not the account's. What one character carried out of
	-- Scholomance is a record of an hour rather than a preference, and putting
	-- it account-wide would have the second character open their bags to a pile
	-- headed with a dungeon they were not in.
	--
	-- An empty table rather than the shape underneath it, because ns.DefaultCopy
	-- copies a default one level deep: a nested table registered here would be
	-- handed out shared, and every character would write into the same one.
	-- Bags/Session.lua fills in the two maps on first use.
	charDefaults = {
		bagSession = {},
	},

	defaults = {
		-- 1.3, and it was 1.25 when every window in the addon shared one number.
		-- A tenth is the step now and 1.25 is not on one, so a default that
		-- stayed there would be a value the page cannot reach and the reset
		-- cannot restore. A window at 1 is a window you lean in to read on the
		-- panel most people are playing on, and the screen height already
		-- doubles this where a panel is tall enough to need it.
		bagsZoom = 1.3,

		-- On. Everything it replaces is one tick box away.
		bags = true,

		-- The client's own nine bag calls, taken, so B opens this window.
		bagsHideBlizz = true,

		-- Ten across. Wide enough that the piles most people carry sit on one
		-- line each and narrow enough that the window is not half the screen.
		bagColumns = 10,

		-- Fifty milliseconds. Three frames of a hand at rest, and under what a
		-- hand crossing the window spends on any one square on the way.
		bagHover = 50,
	},

	words = {
		bags = BagsWord,
	},

	help = {
		"bags, open the bag window",
		"bags on|off, one window with your bags grouped instead of five of the client's",
		"bags hide on|off, take the client's own bag calls so B opens this one",
		"bags columns <6-16>, how many squares across",
		"bags hover <0-500>, how long the pointer holds still on a square before its box opens, in milliseconds",
		"bags count, how many slots you have and how many are free",
		"bags stack, put your half stacks together and free the slots under them",
		"bags clear, review what your bags are finished with, one at a time",
		"bags session [name], start or stop recording what reaches your bags",
		"bags session clear, forget what the last session recorded",
	},

	status = function()
		return ("%s; the client's %s"):format(
			ns.BagsWindow.Describe(), ns.BagsBlizzard.Describe())
	end,

	panel = function(ui)
		ui.Section("Bags", "Windows")
		ui.Lede("One window instead of five, with what you carry sorted into the piles the client already files it under and the free slots counted along the bottom.")
		ui.Check("take the client's bag calls",
			function() return ns.db.bagsHideBlizz end,
			SetHide)
		ui.Hint("All nine, so B opens this window and a merchant no longer puts five of Blizzard's bags beside it. Another bag addon takes the same nine, so run one or the other.")
		ui.Count("columns", LOW_COLUMNS, HIGH_COLUMNS,
			function() return ns.db.bagColumns end,
			SetColumns)
		ui.Stepper("hover wait", LOW_HOVER, HIGH_HOVER, HOVER_STEP,
			function() return ns.db.bagHover end,
			SetHover, HoverLabel)
		ui.Hint("How long the pointer holds still on a square before its box opens. Crossing the window to reach a square opens nothing on the way.")
		ui.Action(StackLabel, ns.BagsStack.Press)
		ui.Hint("Twelve cloth in one slot and eighteen in another come out twenty and ten, and the slot under them is yours again. Nothing else moves. The same press is on the window's own footer.")
		ui.Action(function() return "clear what you are finished with" end,
			function() ns.Destroy.Show() end)
		ui.Hint("The clear button in the title bar. One card at a time, skip or destroy: spent quest items, then greys not worth the slot, then gear you outgrew. The two thresholds are on the Clutter tab.")
		ui.Action(SessionLabel, ns.BagsSession.Press)
		ui.Hint("Everything reaching your bags until you press it again goes in one pile at the top of the window, headed with where you were. Stopping leaves it there to sell later.")
		ui.Action(ForgetLabel, ns.BagsSession.Clear)
		ui.Reading("what you are carrying", ns.Bags.Describe)
		ui.Reading("the session", ns.BagsSession.Describe)
		ui.Reading("stacking", ns.BagsStack.Describe)
		ui.Reading("this window", ns.BagsWindow.Describe)
		ui.Reading("the client's bags", ns.BagsBlizzard.Describe)
		ui.Reading("the squares", ns.BagsGrid.Describe)

		ui.Section("Bags at a merchant", "Windows")
		ui.Lede("While a vendor is open the window grows a row that sells your greys and pays for your mending, marks what the sale will take and dims what it will not.")
		ui.Reading("the row", ns.BagsMerchant.Describe)
		ui.Reading("selling", ns.Vendor.Describe)
		ui.Reading("repairing", ns.Repair.Describe)
	end,
})
