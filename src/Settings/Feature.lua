local ADDON, ns = ...

-- The tab. Settings.lua holds the size and knows the name of no part; this file
-- is the only one that knows both, which is the seam every other part draws
-- between its behaviour and its Feature.
--
-- One rail entry for the settings that are the addon's own rather than any
-- feature's. There is one of them today. It is a part rather than a row bolted
-- onto an existing page because "how big is the window" belongs to no feature,
-- and the alternative was filing it under Interface, which is the Edit Mode
-- part and is about Blizzard's layout rather than ours.

local Settings = ns.Settings

local function SizeWord(arg)
	local value = arg:match("^(%S*)")

	if value == "" then
		ns.Print("UI size " .. Settings.Describe() .. ".")
		return
	end

	local scale = ns.Command.Step(value, Settings.LOW, Settings.HIGH, Settings.STEP, "UI size")
	if not scale then
		return
	end

	Settings.Set(scale)
	ns.Print("UI size " .. Settings.Describe() .. ".")
end

-- Two words rather than one on/off, because "tips off" would read as turning
-- the tooltips off and there is no such setting. Both answers have a name and
-- typing neither reports where the box goes.
local function TipsWord(arg)
	local value = arg:match("^(%S*)"):lower()

	if value == "docked" then
		Settings.SetDocked(true)
	elseif value == "beside" then
		Settings.SetDocked(false)
	elseif value ~= "" then
		ns.Print("tips takes docked or beside.")
		return
	end

	ns.Print("a hover opens " .. Settings.DescribeDock() .. ".")
end

--------------------------------------------------------------------------
-- Back to the shipped answers
--
-- The panel's half of ns.RestoreDefaults, which is where the argument for the
-- whole thing is written down. This end is only the two presses.
--
-- Armed rather than confirmed in a popup, the same shape the mail window's
-- send-anyway button has: the label says what the next press does, and the
-- press that does it is a press you aimed at a button that was already saying
-- so. The arm is dropped when the window closes, so it cannot be left standing
-- for a cursor that comes back an hour later.
--------------------------------------------------------------------------

local armed = false

local function DefaultsReading()
	local moved = ns.DefaultsMoved()
	if moved == 0 then
		return "nothing, every setting is what it ships as"
	end
	return ("%d setting%s"):format(moved, moved == 1 and "" or "s")
end

local function DefaultsLabel()
	if ns.DefaultsMoved() == 0 then
		return "already at the shipped answers"
	end
	if armed then
		return "press again to put them back and reload"
	end
	return "back to the shipped answers"
end

local function DefaultsPress()
	if ns.DefaultsMoved() == 0 then
		return
	end
	if not armed then
		armed = true
		ns.Options.Refresh()
		return
	end
	armed = false
	local moved = ns.RestoreDefaults()
	ns.Print(("%d setting%s back to the shipped answer. Reloading.")
		:format(moved, moved == 1 and "" or "s"))
	ReloadUI()
end

ns.Register({
	name = "settings",
	order = 19,

	defaults = {
		-- 1.25. Everything in this addon was drawn at 1, and 1 is a size you
		-- lean in to read on the panel most people are playing on. The screen
		-- height already doubles it where a panel is tall enough to need that,
		-- so this is a quarter more on top of whatever the screen decided.
		uiSize = 1.25,

		-- Docked. It is where this game has put a tooltip since the day it
		-- shipped, and a box beside the row under the cursor covers the row you
		-- were about to click.
		tipDock = true,
	},

	words = {
		uisize = SizeWord,
		tips = TipsWord,
	},

	help = {
		"uisize 0.5 to 3 in quarters, how big the addon's own windows are",
		"tips docked|beside, where a hover's box opens",
	},

	status = function()
		return Settings.Describe()
	end,

	reset = function()
		Settings.Set(ns.DefaultFor("uiSize"))
		Settings.SetDocked(ns.DefaultFor("tipDock"))
	end,

	-- A window that has been shut is a button nobody is looking at, and an
	-- armed one is a press away from throwing every setting out.
	showing = function(open)
		if not open then
			armed = false
		end
	end,

	panel = function(ui)
		ui.Section("UI size", "The screen")
		ui.Lede("How big this window and the Clutter window are drawn. Nothing on the game screen moves.")

		ui.Slider("size", Settings.LOW, Settings.HIGH, Settings.STEP,
			function() return Settings.Snap(ns.db.uiSize) end,
			function(value) Settings.Set(value) end,
			Settings.Label)
		ui.Hint("The number follows the thumb while you drag and the window takes the size when you let go, because a window that resized under the cursor would fight you for it.")

		ui.Reading("now", Settings.Describe)
		ui.Reading("exact on this screen at", Settings.Grid)

		ui.Action(function()
			return "back to " .. Settings.Label(ns.DefaultFor("uiSize"))
		end, function()
			Settings.Set(ns.DefaultFor("uiSize"))
		end, function()
			return Settings.Snap(ns.db.uiSize) ~= ns.DefaultFor("uiSize")
		end)

		-- Here rather than on the feeds page, where the first of these two used
		-- to live. It was a per-feed reading of an addon-wide fact, printed
		-- twice, and it stopped being about feeds the moment every hover in the
		-- addon started going through the same box.
		ui.Section("Hovers", "The screen")
		ui.Lede("Every hover in the addon opens the same box, in this window's palette.")

		ui.Check("dock it where the client keeps its own",
			Settings.Docked,
			Settings.SetDocked)
		ui.Hint("The corner is read off the client rather than guessed, so it moves when the bags do.")

		ui.Reading("a hover opens", Settings.DescribeDock)
		ui.Reading("the client's own text", ns.UI.Scan.Describe)
		ui.Reading("hooked into a hover", ns.Tip.Describe)

		-- Here rather than beside the lock and the reset in the footer. Those
		-- two are about the frames on your screen and are one press each; this
		-- one throws away every number in the account file, and a control that
		-- destructive belongs on a page you had to open, under a sentence
		-- saying what it spares.
		ui.Section("Shipped defaults", "Under the hood")
		ui.Lede("Every setting back to the answer the addon ships with. It is how a default that moved in an update reaches an account file that already had a number for it.")

		ui.Reading("moved off the shipped answer", DefaultsReading)

		ui.Action(DefaultsLabel, DefaultsPress, function()
			return ns.DefaultsMoved() > 0
		end)
		ui.Hint("Two presses, and the second reloads the interface: a part reads its settings once, when it is built, so the honest way to apply two dozen parts' worth at once is to build them again.")

		ui.Reading("left alone", function()
			return "your groups, your mail favourites, your muted errors, the flasks you track and the gold ledger"
		end)
	end,
})
