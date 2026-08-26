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

ns.Register({
	name = "settings",
	order = 13,

	defaults = {
		-- 1, which is the size everything in this addon was drawn at. The screen
		-- height already doubles it on a panel tall enough to need that, so the
		-- default is a preference of "leave it alone" rather than a number that
		-- happens to suit one monitor.
		uiSize = 1,
	},

	words = {
		uisize = SizeWord,
	},

	help = {
		"uisize 0.5 to 3 in quarters, how big the addon's own windows are",
	},

	status = function()
		return Settings.Describe()
	end,

	reset = function()
		Settings.Set(ns.DefaultFor("uiSize"))
	end,

	panel = function(ui)
		ui.Header("Settings")

		ui.Slider("UI size", Settings.LOW, Settings.HIGH, Settings.STEP,
			function() return Settings.Snap(ns.db.uiSize) end,
			function(value) Settings.Set(value) end,
			Settings.Label)

		ui.Note(function()
			return "How big this window and the Clutter window are drawn. The number"
				.. " next to the slider follows the thumb while you drag and the window"
				.. " takes the size when you let go. It cannot resize under your hand."
				.. " Moving the track out from under the cursor is how a slider ends up"
				.. " fighting you for it."
		end)

		ui.Note(function()
			return "|cffd08040Now:|r " .. Settings.Describe() .. "."
		end)

		ui.Note(function()
			return "A stop keeps the pixel grid when one unit of the design lands on a"
				.. " whole number of screen pixels, which on this screen means "
				.. Settings.Grid() .. ". Every other stop draws a hairline a fraction"
				.. " of a pixel wide, and it comes out soft. That is the whole cost,"
				.. " and it is worth paying when one of the soft stops is the size you"
				.. " actually want to read. The line above says which you are on."
		end)

		ui.Action(function() return "back to 1x" end, function()
			Settings.Set(ns.DefaultFor("uiSize"))
		end, function()
			return Settings.Snap(ns.db.uiSize) ~= ns.DefaultFor("uiSize")
		end)

		ui.Note(function()
			return "This covers the windows the addon draws and nothing else. The enemy"
				.. " bars have their own zoom under Unit frames, in whole steps only,"
				.. " because a bar you read at a glance in a fight is worth keeping"
				.. " exact. The skinned unit frames and the charge button are sized in"
				.. " pixels where they sit, for the same reason."
		end)
	end,
})
