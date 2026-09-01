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

-- Where the box goes, how long it stays and how big it reads, under one word.
--
-- Named answers rather than an on/off, because "tips off" would read as turning
-- the tooltips off and there is no such setting. Typing the word on its own
-- reports all three, which is the shape every other status line in the addon
-- has: a player who has forgotten what they set does not have to guess at the
-- name of the thing they set it to.
local function TipsReading()
	ns.Print("a hover opens " .. Settings.DescribePlace() .. ".")
	ns.Print("it " .. Settings.DescribeLinger() .. ".")
	ns.Print("it is drawn at " .. Settings.DescribeTipFont() .. ".")
end

local function TipsWord(arg)
	local value, rest = arg:match("^(%S*)%s*(.-)$")
	value = value:lower()

	if value == "" then
		TipsReading()
		return
	end

	if value == "linger" then
		local low, high = ns.UI.Tooltip.LingerRange()
		local seconds = ns.Command.Step(rest, low, high, Settings.LINGER_STEP,
			"tips linger")
		if not seconds then
			return
		end
		Settings.SetLinger(seconds)
	elseif value == "font" then
		local low, high = ns.UI.Tooltip.FontRange()
		local size = ns.Command.Step(rest, low, high, 1, "tips font")
		if not size then
			return
		end
		Settings.SetTipFont(size)
	elseif value == "docked" or value == "dock" then
		Settings.SetPlace(ns.UI.Tooltip.DOCK)
	elseif value == "beside" then
		Settings.SetPlace(ns.UI.Tooltip.BESIDE)
	elseif value == "anchor" then
		Settings.SetPlace(ns.UI.Tooltip.ANCHOR)
		ns.Print("unlock the frames to drag the marker where you want the box.")
	else
		ns.Print("tips takes docked, beside, anchor, linger <seconds> or font <pixels>.")
		return
	end

	TipsReading()
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
		tipPlace = "dock",

		-- Where the marker sits until somebody drags it. Right of centre and a
		-- little below, which is clear of the middle of the screen where every
		-- piece of this addon's HUD lives and clear of the bar block along the
		-- bottom. It is not where anybody's box should end up; it is somewhere
		-- you can see the rim the first time you unlock the frames.
		tipPoint = { "CENTER", "UIParent", "CENTER", 220, -140 },

		-- One second. Long enough to finish a sentence you were half way
		-- through when the pointer moved, short enough that a box you have
		-- stopped caring about is gone before you notice it. Zero is a real
		-- answer and is the client's own behaviour.
		tipLinger = 1,

		-- The addon's body size, which is what every tooltip in it was drawn at
		-- before this was a number anybody could move.
		tipFont = ns.UI.Metric.font,

		-- On. Shift to compare gear is what this game has done since the day it
		-- shipped, and the addon drawing its own tooltip is the only reason it
		-- ever stopped. A default of off would be shipping the bug.
		tipCompare = true,
	},

	words = {
		uisize = SizeWord,
		tips = TipsWord,
	},

	help = {
		"uisize 0.5 to 3 in quarters, how big the addon's own windows are",
		"tips docked|beside|anchor, where a hover's box opens",
		"tips linger <seconds>, font <pixels>, how long it stays and how big it reads",
	},

	status = function()
		return Settings.Describe()
	end,

	lock = function()
		Settings.LockAnchor()
	end,

	reset = function()
		Settings.Set(ns.DefaultFor("uiSize"))
		Settings.SetPlace(ns.DefaultFor("tipPlace"))
		Settings.SetLinger(ns.DefaultFor("tipLinger"))
		Settings.SetTipFont(ns.DefaultFor("tipFont"))
		Settings.SetCompare(ns.DefaultFor("tipCompare"))
		Settings.ResetAnchor()
	end,

	-- A window that has been shut is a button nobody is looking at, and an
	-- armed one is a press away from throwing every setting out.
	showing = function(open)
		if not open then
			armed = false
		end
	end,

	panel = function(ui)
		local low, high = ns.UI.Tooltip.LingerRange()
		local fontLow, fontHigh = ns.UI.Tooltip.FontRange()

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

		ui.Cycle("where it opens", Settings.PLACES,
			Settings.Place, Settings.SetPlace)
		ui.Hint("Dock is the corner the client keeps its own in, read off the client rather than guessed, so it moves when the bags do. Anchor is a marker you drag with the frames unlocked.")

		ui.Reading("a hover opens", Settings.DescribePlace)

		ui.Slider("stays for", low, high, Settings.LINGER_STEP,
			Settings.Linger, Settings.SetLinger, Settings.LingerLabel)
		ui.Hint("How long the box holds after you look away. Hovering anything else replaces it at once, whatever is left of this.")

		ui.Size("text", fontLow, fontHigh, 1, Settings.TipFont, Settings.SetTipFont)
		ui.Hint("The body size. The title takes a pixel more, so the two stay a pair at every setting.")

		ui.Check("compare gear on shift", Settings.Compare, Settings.SetCompare)
		ui.Hint("Every item hover, not the bags alone: a quest reward, a dungeon drop, a mail attachment and a link pasted in chat all open the same box. The client's own alwaysCompareItems does it without the key.")

		ui.Reading("holding shift over gear", ns.Compare.Describe)

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
