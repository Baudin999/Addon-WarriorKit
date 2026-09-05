local ADDON, ns = ...

-- Everything Core and the panel need to know about the floating numbers. The
-- three files above hold the anchors, the drawing and the announcements, and
-- none of them knows the name of anything outside this folder.

local Numbers = ns.CombatTextNumbers
local Anchors = ns.CombatTextAnchors
local Calls = ns.CombatTextCalls

-- The ranges, written once and read by both the panel and the slash words, so
-- the stops a macro can reach and the stops the page offers are one set.
-- The low end is the outline floor and not a taste: an outlined glyph under it
-- closes up its own counters buying an edge it cannot do without.
local SIZE_LOW, SIZE_HIGH = 14, 48
local FALL_LOW, FALL_HIGH = 20, 240
local ARC_LOW, ARC_HIGH = 0, 60
local LIFE_LOW, LIFE_HIGH, LIFE_STEP = 0.6, 3, 0.1

local function Restyle()
	Numbers.Apply()
	Calls.Apply()
end

--------------------------------------------------------------------------

local HitsWord = ns.Command.Word({
	name = "hits",
	apply = Restyle,
	show = function()
		return "floating numbers " .. Numbers.Describe() .. "."
	end,

	{ "size", number = { SIZE_LOW, SIZE_HIGH }, key = "hitsSize",
	  say = function(size)
		return ("the numbers are drawn at %d."):format(size)
	  end },

	{ "fall", number = { FALL_LOW, FALL_HIGH }, key = "hitsDrop",
	  say = function(drop)
		return ("a number falls %d pixels."):format(drop)
	  end },

	{ "curve", number = { ARC_LOW, ARC_HIGH }, key = "hitsArc",
	  say = function(arc)
		if arc == 0 then
			return "the numbers fall straight."
		end
		return ("a number bows %d pixels out of its fall."):format(arc)
	  end },

	{ "time", step = { LIFE_LOW, LIFE_HIGH, LIFE_STEP }, key = "hitsLife",
	  say = function(life)
		return ("a number is on screen for %.1f seconds."):format(life)
	  end },

	{ "merge", toggle = true, key = "hitsMerge",
	  say = function(on)
		if on then
			return "the same blow twice is one number that grows."
		end
		return "every blow is its own number."
	  end },

	{ "calls", toggle = true, key = "hitsCalls",
	  say = function(on)
		return "combat calls " .. (on and "on" or "off") .. ": " .. Calls.Describe() .. "."
	  end },

	otherwise = { toggle = true, key = "hits",
	  say = function(on)
		return "floating numbers " .. (on and "on" or "off") .. "."
	  end },
})

--------------------------------------------------------------------------

ns.Register({
	name = "hits",
	order = 36,

	switch = {
		key = "hits",
		label = "the floating numbers",
		apply = Restyle,
	},

	defaults = {
		-- On. Every other readout in this addon that ships off is one you can
		-- get somewhere else; this replaces the client's own floating combat
		-- text rather than adding to it, and a part that ships off is a part
		-- somebody has to be told how to find. Turn the client's own damage
		-- numbers off in its Interface options or you will read every hit
		-- twice.
		hits = true,

		-- 22 is what a number over the world reads at from the middle of the
		-- screen. Well above the twelve every panel in the addon draws at,
		-- because that number is the size of a control in a window and this is
		-- a caption on the fight.
		hitsSize = 22,

		-- Ninety pixels over one and three tenths of a second. Far enough that
		-- a number has visibly travelled and short enough that six of them are
		-- not on the screen at once.
		hitsDrop = 90,
		hitsLife = 1.3,

		-- Eighteen pixels of bow at the halfway point. Enough that two numbers
		-- born in the same frame separate, and little enough that the column
		-- still reads as a column.
		hitsArc = 18,

		-- On. Four ticks of a bleed in six seconds is four numbers drawn on top
		-- of each other, each one unreadable because of the next, and one
		-- number that grows is the same information legibly.
		hitsMerge = true,
		hitsCalls = true,

		-- A hundred and fifty pixels either side of you and a little below,
		-- which is where the two health bars this is about already are. The
		-- calls sit above your head, clear of both columns and of the nameplate
		-- over whatever you are hitting.
		hitsMinePoint = { "CENTER", "UIParent", "CENTER", -150, -30 },
		hitsTheirsPoint = { "CENTER", "UIParent", "CENTER", 150, -30 },
		hitsCallsPoint = { "CENTER", "UIParent", "CENTER", 0, 140 },
	},

	words = {
		hits = HitsWord,
	},

	help = {
		"hits on|off, damage and healing floating off your character",
		"hits size 22, fall 90, curve 18, time 1.3",
		"hits merge on|off, calls on|off",
	},

	status = function()
		return Numbers.Describe()
	end,

	lock = function(unlocked)
		Anchors.Lock(unlocked)
	end,

	reset = function()
		ns.db.hitsSize = ns.DefaultCopy("hitsSize")
		ns.db.hitsDrop = ns.DefaultCopy("hitsDrop")
		ns.db.hitsArc = ns.DefaultCopy("hitsArc")
		ns.db.hitsLife = ns.DefaultCopy("hitsLife")
		Anchors.Reset()
		Restyle()
	end,

	panel = function(ui)
		ui.Section("Floating numbers", "Fighting")
		ui.Lede("What lands on you falls away on your left, what you land on the right. Damage is white, healing is green, and more than a hit is gold.")

		ui.Size("size", SIZE_LOW, SIZE_HIGH, 1,
			function() return ns.db.hitsSize end,
			function(value)
				ns.db.hitsSize = value
				Restyle()
			end)
		ui.Hint("A big hit is drawn bigger than a small one on top of this, against the biggest of the fight so far. It resets when you leave combat.")

		ui.Size("fall", FALL_LOW, FALL_HIGH, 5,
			function() return ns.db.hitsDrop end,
			function(value)
				ns.db.hitsDrop = value
				Restyle()
			end)

		ui.Size("curve", ARC_LOW, ARC_HIGH, 2,
			function() return ns.db.hitsArc end,
			function(value)
				ns.db.hitsArc = value
				Restyle()
			end)
		-- A stepper and not a slider, which is the argument the zoom rows already
		-- won: a tenth of a second is a step you click rather than a length you
		-- aim at, and a slider four tenths wide is a control you overshoot.
		ui.Stepper("time on screen", LIFE_LOW, LIFE_HIGH, LIFE_STEP,
			function() return ns.db.hitsLife end,
			function(value)
				ns.db.hitsLife = value
				Restyle()
			end,
			function(value) return ("%.1fs"):format(value) end)
		ui.Hint("A critical outlives this by a third and fades later inside its own life, which is what makes it the one you read.")

		ui.Check("add up the same blow",
			function() return ns.db.hitsMerge end,
			function(on)
				ns.db.hitsMerge = on
				Restyle()
			end)
		ui.Hint("Four ticks of a bleed in six seconds are one number that grows rather than four drawn over each other.")

		ui.Reading("the numbers", function()
			if not ns.CombatLog.Ready() then
				return "this client has no combat log, so nothing here runs"
			end
			local biggest = Numbers.Biggest()
			if biggest <= 0 then
				return ("%d in the air, nothing hit yet this fight"):format(Numbers.Count())
			end
			return ("%d in the air, biggest this fight %d"):format(Numbers.Count(), biggest)
		end)

		ui.Action(function() return "put the three spawn points back" end, function()
			Anchors.Reset()
		end)
		ui.Hint("Three of them: what lands on you, what you land, and the calls. Unlock the frames to drag them.")

		ui.Section("Combat calls", "Fighting")
		ui.Lede("A word above your head the moment an ability comes up, once.")

		ui.Check("call an ability out when it comes up",
			function() return ns.db.hitsCalls end,
			function(on)
				ns.db.hitsCalls = on
				Calls.Apply()
			end)
		ui.Hint("Execute as the target drops under a fifth, and a reaction window as the fight opens one. The client says yes to both all fight.")

		ui.Reading("the calls", function()
			return Calls.Describe()
		end)
	end,
})

-- What the timing figure on the performance tab is a timing of. A number in the
-- air is a frame being moved, scaled and faded, and the milliseconds mean
-- nothing without knowing how many there were.
ns.Perf.Gauge("numbers in the air", function()
	if not ns.db.hits then
		return 0
	end
	return Numbers.Count()
end)
