local ADDON, ns = ...

-- Everything Core and the panel need to know about the experience and
-- reputation rails. Progress.lua holds the readings and Rails.lua holds the
-- picture, and neither of them knows the name of anything outside this folder.

local Progress = ns.Progress
local Rails = ns.ProgressRails

--------------------------------------------------------------------------

-- The words the rails answer to. Both sizes read their range off the file that
-- owns the rails rather than having it typed here a second time.
local XPWord = ns.Command.Word({
	name = "xp",
	apply = function() Rails.Apply() end,
	show = function()
		return "the experience rails are " .. Rails.Describe() .. ".",
			"  " .. Progress.Describe() .. "."
	end,

	{ "width", key = "progressWidth",
	  number = function()
		local low, high = Rails.SizeRange()
		return low, high
	  end,
	  say = function(size)
		return ("the rails are %d pixels wide."):format(size)
	  end },

	{ "height", key = "progressHeight",
	  number = function()
		local _, _, low, high = Rails.SizeRange()
		return low, high
	  end,
	  say = function(size)
		return ("the rails are %d pixels tall."):format(size)
	  end },

	ns.Command.Zoom("progressZoom", "the rails draw at %dx."),

	{ "faction", toggle = true, key = "progressFaction",
	  say = function(on)
		return "the reputation rail " .. (on and "on" or "off")
			.. ": " .. Rails.Describe() .. "."
	  end },

	{ "bubbles", toggle = true, key = "progressBubbles",
	  say = function(on)
		return "the twenty segment marks " .. (on and "on" or "off") .. "."
	  end },

	{ "reset", run = function()
		Rails.Reset()
		ns.Print("the rails back along the bottom of the screen.")
	  end },

	otherwise = { toggle = true, key = "progress",
	  say = function(on)
		return "the experience and reputation rails " .. (on and "on" or "off")
				.. ": " .. Rails.Describe() .. ".",
			(not on and ns.db.hideBlizzXP) and "Blizzard's own are hidden by"
				.. " `/wk hide xp`, so nothing is drawing your experience at all."
				or nil
	  end },
})

--------------------------------------------------------------------------

ns.Register({
	name = "progress",
	order = 26,

	switch = {
		key = "progress",
		label = "the experience and reputation rails",
		apply = function() Rails.Apply() end,
	},

	zooms = {
		{ key = "progressZoom", label = "Experience rail", apply = function() ns.ProgressRails.Apply() end },
	},

	defaults = {
		progress = true,

		-- The reputation rail, which is drawn only when you are watching a
		-- faction. On, because a rail that is not there costs nothing and the
		-- one time it matters is the grind you are in the middle of.
		progressFaction = true,

		progressBubbles = true,

		-- 460 is twenty three screen pixels a segment, which is a bubble wide
		-- enough to read as a division rather than as hatching, times the
		-- twenty the client has always drawn. 14 is tall enough for the level
		-- and the count beside it at a size worth reading.
		progressWidth = 460,
		progressHeight = 14,

		-- A whole number, like every other zoom in the addon, because a
		-- fractional one puts every edge back on a half pixel. 2, because this
		-- rail is read from the bottom edge of the screen while something else
		-- has your attention.
		progressZoom = 2,

		-- The bottom edge of the screen, which is where this game has drawn
		-- these two bars since it shipped and is under every action bar rather
		-- than over one. Four pixels up, so the rim is not the screen edge.
		progressPoint = { "BOTTOM", "UIParent", "BOTTOM", 0, 4 },

		-- The client's own experience and reputation bars. On for the reason
		-- every other switch in Core/BlizzHide.lua's list ships on: this
		-- addon draws them now, and two copies of one reading is what that page
		-- exists to answer. The frames it takes down are named there.
		hideBlizzXP = true,
	},

	charDefaults = {
		-- The time to level, which is worked out from what this character has
		-- earned at the level it is on and how long it has been earning it. Per
		-- character rather than account wide for the reason Breakdown's record
		-- is: a figure averaged over a level 70 and an alt still in the starting
		-- zone is a figure about neither of them.
		--
		-- Three flat keys rather than one table, because ApplyDefaults copies a
		-- default one level deep and a table inside a table would be handed to
		-- every character by reference.
		--
		-- The level is here so the tally knows which one it is about. A
		-- character that dinged, logged out and came back would otherwise divide
		-- the new level's remainder by the old level's rate, and the old level
		-- was the cheaper one.
		progressLevel = 0,
		progressEarned = 0,
		progressSeconds = 0,
	},

	words = {
		xp = XPWord,
	},

	help = {
		"xp on|off, the experience and reputation rails along the bottom",
		"xp faction on|off, the reputation rail under the experience one",
		"xp bubbles on|off, the twenty segment marks",
		"xp width <120-900>, xp height <6-32>, xp zoom <1-3>",
		"xp reset, the rails back along the bottom of the screen",
	},

	status = function()
		return ("experience rails %s; %s"):format(Rails.Describe(), Progress.Describe())
	end,

	lock = function()
		Rails.Lock()
	end,

	reset = function()
		for _, key in ipairs({ "progress", "progressFaction", "progressBubbles",
			"progressWidth", "progressHeight", "progressZoom", "hideBlizzXP" }) do
			ns.db[key] = ns.DefaultCopy(key)
		end
		-- Rails.Reset puts the point back and lays both rails out again, so the
		-- seven above it land in the same pass.
		Rails.Reset()
		ns.BlizzHide.Apply()
	end,

	panel = function(ui)
		local wideLow, wideHigh, tallLow, tallHigh = Rails.SizeRange()

		ui.Section("Experience and reputation", "Feeds and meters")
		ui.Lede("Two rails along the bottom of the screen: how far into the level you"
			.. " are, and the faction you are watching under it.")

		ui.Check("the reputation rail",
			function() return ns.db.progressFaction end,
			function(value)
				ns.db.progressFaction = value
				Rails.Apply()
			end)
		ui.Hint("It is drawn only while you are watching a faction, so on a character watching none there is nothing to see either way.")

		ui.Check("the twenty segment marks",
			function() return ns.db.progressBubbles end,
			function(value)
				ns.db.progressBubbles = value
				Rails.Apply()
			end)
		ui.Hint("The client's own bubbles. They come off on their own under 160 pixels of width, where twenty of anything reads as hatching.")

		ui.Size("width", wideLow, wideHigh, 20,
			function() return ns.db.progressWidth end,
			function(value)
				ns.db.progressWidth = value
				Rails.Apply()
			end)

		ui.Size("height", tallLow, tallHigh, 1,
			function() return ns.db.progressHeight end,
			function(value)
				ns.db.progressHeight = value
				Rails.Apply()
			end)

		ui.Zoom(
			function() return ns.db.progressZoom end,
			function(value)
				ns.db.progressZoom = value
				Rails.Apply()
			end)

		ui.Reading("the rails", Rails.Describe)
		ui.Reading("this character", Progress.Describe)

		ui.Action(function() return "put the rails back" end, function()
			Rails.Reset()
		end)
	end,
})
