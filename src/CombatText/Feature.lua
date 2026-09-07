local ADDON, ns = ...

-- Everything Core and the panel need to know about the floating numbers. The
-- three files above hold the anchors, the drawing and the announcements, and
-- none of them knows the name of anything outside this folder.

local Numbers = ns.CombatTextNumbers
local Anchors = ns.CombatTextAnchors
local Calls = ns.CombatTextCalls

-- The ranges, written once and read by both the panel and the slash words, so
-- the stops a macro can reach and the stops the page offers are one set.
-- The size is in pixels of the addon's own grid now, multiplied by the zoom on
-- the size page, so both ends of it mean something on the screen rather than
-- meaning whatever the player's UI scale slider makes of them.
local SIZE_LOW, SIZE_HIGH = 14, 72
local FALL_LOW, FALL_HIGH = 20, 240
local ARC_LOW, ARC_HIGH = 0, 90
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

	{ "quiet", toggle = true, key = "hitsQuiet",
	  say = function(on)
		if on then
			return "the client's own damage numbers are off while these are on."
		end
		return "the client draws its own damage numbers again."
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

	zooms = {
		{ key = "hitsZoom", label = "Floating numbers", fight = true, apply = Restyle },
	},

	defaults = {
		-- On. Every other readout in this addon that ships off is one you can
		-- get somewhere else; this replaces the client's own floating combat
		-- text rather than adding to it, and a part that ships off is a part
		-- somebody has to be told how to find. It puts the client's own away
		-- while it runs, which is the `quiet` setting below.
		hits = true,

		-- Thirty at a zoom of two, which is sixty physical pixels.
		--
		-- It shipped at 22, then at 36, and both were reported too small. Both
		-- were also wrong in a way no number could fix: the frames were off the
		-- addon's pixel grid, so 36 meant 36 of UIParent's units and what
		-- reached the screen depended on the player's UI scale, and the glyphs
		-- were rasterised at fourteen pixels and stretched. They are adopted
		-- now, the size is physical pixels times the zoom, and the face is
		-- thirty-two, so what you set is what is drawn and it is drawn sharp.
		--
		-- A panel draws its controls at twelve and the loot captions at twenty,
		-- and both of those are read while standing still. This is read out of
		-- the corner of an eye in the second before it goes, over a mob, while
		-- you are pressing something.
		hitsSize = 30,
		hitsZoom = 2,

		-- Ninety pixels over one and three tenths of a second. Far enough that
		-- a number has visibly travelled and short enough that six of them are
		-- not on the screen at once.
		hitsDrop = 90,
		hitsLife = 1.3,

		-- Forty-four pixels of bow at the halfway point, against the eighteen
		-- that shipped. Eighteen was chosen when a number was drawn at less
		-- than half this height, and around a sixty pixel glyph a bow of
		-- eighteen is inside the glyph: two blows a tenth of a second apart
		-- still meshed. Forty-four is a little over the width of a three digit
		-- number at the shipped size, which is the width two of them have to be
		-- apart to be two of them. The stream gives every number a height off
		-- the row and a side to start on as well, and the three together are
		-- what stops a burst being one pile.
		hitsArc = 44,

		-- On. Four ticks of a bleed in six seconds is four numbers drawn on top
		-- of each other, each one unreadable because of the next, and one
		-- number that grows is the same information legibly.
		hitsMerge = true,
		hitsCalls = true,

		-- On. Two parts drawing the same hit is worse than either alone, and a
		-- part that replaces the client's readout and leaves it running has
		-- replaced nothing. Only what this part redraws: the four over your
		-- target, and the hits and heals the client scrolls beside you, which
		-- have no setting of their own and were the half that was still doubled.
		-- Your dodges, combo points and energy are still its own.
		hitsQuiet = true,

		-- A hundred and fifty pixels either side of you and forty above, which
		-- is chest height on the character rather than knee height. They began
		-- thirty below and every number spent its whole fall in the grass; a
		-- number falls ninety pixels from where it is born, so starting under
		-- the character is starting at the end.
		--
		-- Dealt on the left. What you are doing is what is read most, and what
		-- is read most goes where a left-to-right reader looks first. The calls
		-- sit above your head, clear of both columns and of the nameplate over
		-- whatever you are hitting.
		--
		-- Healing starts on the character and rises, so it begins where the two
		-- columns begin their fall and travels the other way. That is the one
		-- placing here that is a reading rather than a taste: three streams over
		-- one character are told apart by direction before they are told apart
		-- by colour, and a heal is the only one going up.
		hitsDealtPoint = { "CENTER", "UIParent", "CENTER", -150, 40 },
		hitsTakenPoint = { "CENTER", "UIParent", "CENTER", 150, 40 },
		hitsHealsPoint = { "CENTER", "UIParent", "CENTER", 0, 0 },
		hitsCallsPoint = { "CENTER", "UIParent", "CENTER", 0, 140 },
	},

	words = {
		hits = HitsWord,
	},

	help = {
		"hits on|off, damage floating off your character and healing rising over it",
		"hits size 30, fall 90, curve 44, time 1.3",
		"hits merge on|off, calls on|off, quiet on|off",
	},

	status = function()
		return Numbers.Describe()
	end,

	lock = function(unlocked)
		Anchors.Lock(unlocked)
	end,

	charDefaults = {
		-- What the client's own damage number settings were before this addon
		-- first touched them, so switching it off puts back what this character
		-- chose rather than the default. Per character because the CVars are.
		hitsPrior = {},
	},

	reset = function()
		ns.db.hitsSize = ns.DefaultCopy("hitsSize")
		ns.db.hitsZoom = ns.DefaultCopy("hitsZoom")
		ns.db.hitsDrop = ns.DefaultCopy("hitsDrop")
		ns.db.hitsArc = ns.DefaultCopy("hitsArc")
		ns.db.hitsLife = ns.DefaultCopy("hitsLife")
		Anchors.Reset()
		Restyle()
	end,

	panel = function(ui)
		ui.Section("Floating numbers", "Fighting")
		ui.Lede("What you land falls left, what an enemy lands on you falls right, healing rises over your character. Damage is white, healing green, a big hit gold.")

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
		ui.Hint("Each column bows outwards, away from your character. Healing rises straight whatever this says.")
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

		ui.Check("turn the client's own damage numbers off",
			function() return ns.db.hitsQuiet end,
			function(on)
				ns.db.hitsQuiet = on
				Restyle()
			end)
		ui.Hint("The four over your target and the hits and heals it scrolls beside you. Your dodges, combo points and energy stay the client's, and it gets them all back when this goes off.")

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

		ui.Action(function() return "put the four spawn points back" end, function()
			Anchors.Reset()
		end)
		ui.Hint("Four of them: what you land, what lands on you, healing, and the calls. Unlock the frames to drag them.")

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
