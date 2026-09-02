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

-- A screen is named by its label with the spaces taken out and the case
-- dropped, so "Quest log" is `quest log` or `questlog` and both are the same
-- word. Matched rather than listed, because the list is ns.Zooms() and a word
-- table written here would be the thing that goes stale when a part registers a
-- screen.
local function ZoomNamed(word)
	word = word:lower():gsub("%s+", "")
	for _, zoom in ipairs(ns.Zooms()) do
		if zoom.label:lower():gsub("%s+", "") == word then
			return zoom
		end
	end
	return nil
end

-- `scale` on its own lists every screen and what it is drawn at.
-- `scale <screen>` reports one, `scale <screen> <number>` sets it. The screen comes first because
-- that is the order you think in: you know which thing is the wrong size before
-- you know what to make it.
--
-- Called scale because the two better words are taken and mean something else:
-- Comfort answers `zoom` and means the camera, Charge answers `size` and means
-- the charge button in pixels. The page in the options window is called Zoom,
-- which is the word for the thing; this is the word still free to type.
local function ZoomWord(arg)
	local name, value = arg:match("^(.-)%s*(%S*)$")
	if tonumber(value) == nil and value ~= "" then
		name, value = arg:match("^(.-)%s*$"), ""
	end

	if name == "" and value == "" then
		for _, zoom in ipairs(ns.Zooms()) do
			ns.Print(("  %-18s %s"):format(zoom.label:lower(), Settings.Describe(zoom.key)))
		end
		return
	end

	local zoom = ZoomNamed(name)
	if not zoom then
		ns.Print(("no screen called %q. scale on its own lists them."):format(name))
		return
	end

	if value == "" then
		ns.Print(("%s %s."):format(zoom.label:lower(), Settings.Describe(zoom.key)))
		return
	end

	local scale = ns.Command.Step(value, Settings.LOW, Settings.HIGH, Settings.STEP,
		zoom.label:lower())
	if not scale then
		return
	end

	ns.db[zoom.key] = Settings.Snap(scale)
	if zoom.apply then
		zoom.apply()
	end
	ns.UI.Notify()
	ns.Print(("%s %s."):format(zoom.label:lower(), Settings.Describe(zoom.key)))
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

	-- The three screens that belong to no feature. The options panel is one of
	-- them because a settings window is nobody's feature, and the two boxes the
	-- UI layer draws are the other two: a hover opens over anything in the addon
	-- and a confirm box is asked by whoever is about to do something you cannot
	-- undo, so neither has a part to be owned by.
	zooms = {
		{ key = "panelZoom", label = "Options panel", window = true },
		{ key = "tipZoom", label = "Tooltips",
		  apply = function() Settings.SetTipZoom(ns.db.tipZoom) end },
		{ key = "dialogZoom", label = "Confirm box", window = true,
		  apply = function() Settings.Set(ns.db.dialogZoom) end },
	},

	defaults = {
		-- 1.25 for both, which is what every window in the addon was drawn at
		-- when they shared one number called uiSize. A window at 1 is a window
		-- you lean in to read on the panel most people are playing on, and the
		-- screen height already doubles this where a panel is tall enough to
		-- need it.
		panelZoom = 1.3,
		dialogZoom = 1.3,

		-- 1, not 1.25. A hover box is small, opens over what you are reading and
		-- goes again, and how big its text is is already a setting of its own
		-- two lines down. This is the box, air and all.
		tipZoom = 1,

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
		scale = ZoomWord,
		tips = TipsWord,
	},

	help = {
		"scale, list every screen and what it is drawn at",
		"scale <screen> <0.5 to 3>, how big one screen is drawn, in tenths",
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
		Settings.Set(ns.DefaultFor("dialogZoom"))
		Settings.SetTipZoom(ns.DefaultFor("tipZoom"))
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

		-- Two lists, and the split is what makes the page usable rather than
		-- complete. Twenty three rows with a sentence under each came to forty
		-- nine cells and a thousand units of stack in a view that holds three
		-- hundred and fifty, so the row you opened the page for was three
		-- screens down. The windows and the things drawn over the world are the
		-- two halves anybody thinks in, and each fits without scrolling.
		--
		-- The sentence under every row is gone with it. It said which stop that
		-- screen was on and whether the stop kept a hairline sharp, twenty three
		-- times, and the reading at the foot of each list answers that for every
		-- row at once: the stops that stay exact are a fact about the monitor,
		-- not about the screen being sized.
		local function Rows(want, title, lede)
			ui.Section(title, "The screen")
			ui.Lede(lede)
			for _, zoom in ipairs(ns.Zooms()) do
				if (zoom.window == true) == want then
					ui.Zoom(
						function() return Settings.Snap(ns.db[zoom.key]) end,
						function(value)
							ns.db[zoom.key] = Settings.Snap(value)
							if zoom.apply then
								zoom.apply()
							end
							-- Every window keeps itself on the grid off this,
							-- including the one you are reading the row in. A
							-- part with an apply of its own has already run it;
							-- this is what reaches the ones whose whole answer
							-- is the rezoom.
							ns.UI.Notify()
						end,
						zoom.label)
				end
			end
			ui.Reading("exact on this screen at", Settings.Grid)
			ui.Action(function()
				return "this list back to its defaults"
			end, function()
				for _, zoom in ipairs(ns.Zooms()) do
					if (zoom.window == true) == want then
						ns.db[zoom.key] = ns.DefaultFor(zoom.key)
						if zoom.apply then
							zoom.apply()
						end
					end
				end
				ns.UI.Notify()
			end, function()
				for _, zoom in ipairs(ns.Zooms()) do
					if (zoom.window == true) == want
						and Settings.Snap(ns.db[zoom.key]) ~= ns.DefaultFor(zoom.key) then
						return true
					end
				end
				return false
			end)
		end

		-- The rows themselves are not named here. A part that draws something
		-- sizeable says so in its own ns.Register call and turns up on the list
		-- its flag puts it on; a part that stops drawing it takes its row away.
		-- The alternative was every screen in the addon written out in this
		-- file, which is the list that goes stale the first time somebody adds
		-- a window.
		Rows(true, "Zoom: windows",
			"Every window this addon opens, each on its own number. Shrink the map without shrinking the quest log beside it.")
		Rows(false, "Zoom: on screen",
			"Everything the addon draws over the world, each on its own number. A stop off the exact list draws a hairline soft, which is a price you are allowed to choose.")

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
