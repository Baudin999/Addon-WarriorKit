local ADDON, ns = ...

-- The tab. Feeds/Stream.lua is the frame, UI/Feed.lua is the column, and
-- Feeds/Loot.lua and Feeds/Combat.lua are the two things worth putting in one.
-- This file is the only one in the folder that knows the addon around it.

local LootFeed = ns.LootFeed
local CombatFeed = ns.CombatFeed

local LOW_ROWS, HIGH_ROWS = 3, 24
-- The floor moved up with the row layout. A combat row is an icon, a name, who
-- it was and a number, and 140 units is not a row, it is four things clipped to
-- two glyphs each. 200 is the narrowest that still leaves a name readable once
-- the fixed number column and half of what is left have been taken off it.
local LOW_WIDTH, HIGH_WIDTH = 200, 520
local LOW_QUALITY, HIGH_QUALITY = 0, 4
local LOW_FLOOR, HIGH_FLOOR = 0, 100000

-- The word for a quality is Feeds/Loot.lua's, because the chips over the loot
-- feed name one and so does this page, and two tables of five words is how one
-- of them ends up saying "Grey" while the other says "Poor".
local QualityWord = ns.QualityWord

-- The word a filter chip is turned on and off by, in the order the chips are
-- drawn. Typed in English rather than read off the client, because this is a
-- slash command and a command you have to type in German on a German client is
-- one nobody can write down.
local FILTERS = { "poor", "common", "uncommon", "rare", "epic" }

--------------------------------------------------------------------------
-- The two streams, said once
--
-- Everything below that takes a prefix is the half of a feed that is the same
-- for both: how many rows, how wide, how opaque, whether it takes the mouse.
-- What differs is a handful of options each, and those are the tables at the
-- bottom of this file.
--------------------------------------------------------------------------

local STREAMS = {
	loot = {
		stream = LootFeed.Stream(),
		prefix = "lootFeed",
		title = "Loot",
		describe = LootFeed.Describe,
		collects = "what drops",
		costs = "no loot message is read at all.",
		-- The same fact as `costs`, inside the hint cap. `costs` is a sentence
		-- the slash help prints and this is the clause a hover has room for.
		cheap = "no loot message is read at all",
	},
	combat = {
		stream = CombatFeed.Stream(),
		prefix = "combatFeed",
		title = "Combat",
		describe = CombatFeed.Describe,
		collects = "what happens to you",
		costs = "the addon is not on the combat log event at all, which in a raid"
			.. " is the difference between nothing a second and a few hundred rows"
			.. " a second.",
		cheap = "the addon is not on the combat log event at all",

		-- Off takes this stream off the combat log rather than turning every
		-- line away inside a handler the client is still calling, so the
		-- collecting switch has a second half to apply. The loot feed has no
		-- entry here because its own event is cheap and it reads it either way.
		applied = function() ns.CombatFeed.Apply() end,
	},
}

-- A stable order, because a table keyed by name has none and both the status
-- line and the panel have to read the same way every time.
local ORDER = { "loot", "combat" }

local function Describe()
	local lines = {}
	for _, key in ipairs(ORDER) do
		lines[#lines + 1] = ("%s %s"):format(key, STREAMS[key].describe())
	end
	return table.concat(lines, "; ")
end

--------------------------------------------------------------------------
-- The slash word
--
-- One word with the stream named first, `/wk feed loot rows 12`, rather than a
-- word each. `loot` is already Comfort/Loot.lua's and means fast looting, and a
-- second meaning for it would be the kind of collision Core/Command.lua cannot
-- see: two features registering the same word and the later one winning
-- silently.
--------------------------------------------------------------------------

local function Apply(entry)
	entry.stream:Apply()
	if entry.applied then
		entry.applied()
	end
end

-- On screen or hidden, which is not the same switch as collecting: a hidden
-- feed still records, and the sentence says so both ways round.
local function Shown(entry, on)
	ns.db[entry.prefix .. "Shown"] = on
	entry.stream:Show()
	ns.Print(("the %s feed is %s. It %s collecting."):format(entry.title:lower(),
		on and "on screen" or "hidden",
		ns.db[entry.prefix] and "is still" or "is not"))
end

-- The loot feed's chips redrawn, which is what every word about what gets a row
-- has to do and none of them has to apply.
--
-- Answered with nothing while the feed is off, because a stream that is not
-- collecting has no column: Feeds/Stream.lua builds one when the switch goes on
-- and the chips are drawn with it. Every caller of this goes through here for
-- that reason.
local function Chipped()
	local feed = STREAMS.loot.stream:Feed()
	if feed then
		feed:Chipped()
	end
end

-- What a feed is dressed in: how large the picture on a row is, whether there
-- is a word over the column, a line round the frame, a strip of chips. The
-- three switches are one entry each off the same line, because the key, the
-- word and the clause that says what it did are the only things that differ.
local function ChromeEntry(entry, word, said)
	local key = entry.prefix .. word:sub(1, 1):upper() .. word:sub(2)
	return { word, toggle = true, key = key,
		say = function(on)
			return ("the %s feed %s %s."):format(entry.title:lower(),
				on and "has" or "has no", said)
		end }
end

-- The half of a feed that is the same for both, as a table rather than as a
-- chain of ifs. It was two functions until it was one table: Shared had been
-- split from Chrome for no reason but its own branch count, and a table has no
-- branch count to split on.
local function SharedWords(entry)
	local prefix, lower = entry.prefix, entry.title:lower()

	return {
		{ "rows", number = { LOW_ROWS, HIGH_ROWS }, key = prefix .. "Rows",
		  say = function(rows)
			return ("the %s feed shows %d rows."):format(lower, rows)
		  end },

		{ "width", number = { LOW_WIDTH, HIGH_WIDTH }, key = prefix .. "Width",
		  say = function(width)
			return ("the %s feed is %d pixels wide."):format(lower, width)
		  end },

		{ "icon", key = prefix .. "Icon",
		  number = function()
			return ns.UI.FEED_ICON_LOW, ns.UI.FEED_ICON_HIGH
		  end,
		  say = function(icon)
			local drawn, sharp = ns.UI.FeedIcons(icon, ns.db[prefix .. "Zoom"])
			return ("the %s feed draws a %d pixel icon on a %d pixel row%s."):format(
				lower, drawn, drawn + 2,
				sharp and "" or ", which the client has to resample")
		  end },

		ChromeEntry(entry, "header", "a word over it"),
		ChromeEntry(entry, "edge", "a line round it"),
		ChromeEntry(entry, "filters",
			"filter chips, and draws everything it holds"),

		{ "zoom", key = prefix .. "Zoom",
		  number = function() return ns.UI.ZOOM_LOW, ns.UI.ZOOM_HIGH end,
		  say = function(zoom)
			return ("the %s feed at %dx."):format(lower, zoom)
		  end },

		{ "alpha", key = prefix .. "Alpha", what = entry.title .. " background",
		  step = function()
			return ns.UI.ALPHA_LOW, ns.UI.ALPHA_HIGH, ns.UI.ALPHA_STEP
		  end,
		  say = function(alpha)
			return ("the %s feed background at %d%%."):format(lower, alpha)
		  end },

		-- Not a switch taking a value: `show` puts a hidden feed back on the
		-- screen and `hide` takes it off, which is two words because that is
		-- what the help says and what a macro says.
		{ "show", run = function() Shown(entry, true) end },
		{ "hide", run = function() Shown(entry, false) end },

		{ "mouse", toggle = true, key = prefix .. "Mouse",
		  say = function(on)
			return ("the %s feed %s the mouse."):format(lower,
				on and "takes" or "ignores")
		  end },

		{ "clear", run = function()
			local feed = entry.stream:Feed()
			if feed then
				feed:Clear()
			end
			ns.Print(("the %s feed is empty."):format(lower))
		  end },

		{ "reset", run = function()
			entry.stream:Reset(ns.DefaultCopy(prefix .. "Point"))
			ns.Print(("the %s feed is back where it started."):format(lower))
		  end },
	}
end

-- The words only the loot feed answers to: who it counts, and which of the six
-- kinds of row it draws. The five quality chips are one entry each off the same
-- list the chips themselves are drawn from.
local function LootWords()
	local words = {
		{ "group", toggle = true, key = "lootFeedGroup", apply = false,
		  say = function(on)
			return "the loot feed " .. (on
				and "shows what the group picks up too."
				or "shows your own drops only.")
		  end },

		{ "quest", toggle = true, key = "lootFeedQuest", apply = Chipped,
		  say = function(on)
			return "quest items are " .. (on
				and "drawn whatever their own quality chip says."
				or "graded by their own quality like anything else.")
		  end },

		{ "money", toggle = true, key = "lootFeedMoney", apply = Chipped,
		  say = function(on)
			return "coin " .. (on
				and "gets a row in the column."
				or "stays out of the column and in the purse under it.")
		  end },

		{ "purse", toggle = true, key = "lootFeedPurse",
		  apply = function() STREAMS.loot.stream:Apply() end,
		  say = function(on)
			return "the purse " .. (on
				and "sits along the bottom of the feed."
				or "is off and the feed has the height back.")
		  end },
	}

	for level = LOW_QUALITY, HIGH_QUALITY do
		words[#words + 1] = { FILTERS[level + 1], run = function(value)
			ns.LootFeed.Light(level, ns.Command.Toggle(value))
			Chipped()
			ns.Print(("%s items are %s the column. The feed records them either"
				.. " way."):format(QualityWord(level),
				ns.LootFeed.Lit(level) and "on" or "off"))
		  end }
	end

	return words
end

-- The words only the combat feed answers to. None of them applies anything: the
-- frame has not moved and nothing on it has changed size, and the next event
-- through is filtered by what these wrote.
local function CombatWords()
	local function Direction(word, key, whose)
		return { word, toggle = true, key = key, apply = false,
			say = function(on)
				return ("%s is %s."):format(whose,
					on and "in the feed" or "out of the feed")
			end }
	end

	return {
		Direction("out", "combatFeedOut", "what you do"),
		Direction("in", "combatFeedIn", "what hits you"),

		{ "misses", toggle = true, key = "combatFeedMisses", apply = false,
		  say = function(on)
			return "misses and dodges " .. (on and "get a row." or "are ignored.")
		  end },

		{ "floor", number = { LOW_FLOOR, HIGH_FLOOR }, key = "combatFeedFloor",
		  what = "combat floor", apply = false,
		  say = function(floor)
			return floor > 0 and ("nothing under %d gets a row."):format(floor)
				or "every hit gets a row."
		  end },
	}
end

local EXTRA = { loot = LootWords, combat = CombatWords }

-- One table per stream, built once: the shared words, then that stream's own,
-- then the bare on|off. Built here rather than at each command, because the
-- words a feed answers to cannot change after the streams exist.
local function StreamWords(which, entry)
	local spec = {
		name = entry.title,
		apply = function() Apply(entry) end,

		-- Anything left is the on/off switch, which is what a bare word means
		-- everywhere else in this addon. On this feature it is the collecting
		-- switch rather than the visibility one: off records nothing, and
		-- `hide` above is the word for taking a working feed off the screen.
		otherwise = { toggle = true, key = entry.prefix,
		  say = function(on)
			return ("the %s feed is %s."):format(which,
				on and "collecting" or "off, and recording nothing")
		  end },
	}

	for _, list in ipairs({ SharedWords(entry), EXTRA[which]() }) do
		for _, word in ipairs(list) do
			spec[#spec + 1] = word
		end
	end

	return ns.Command.Word(spec)
end

local WORDS = {}
for which, entry in pairs(STREAMS) do
	WORDS[which] = StreamWords(which, entry)
end

local function FeedWord(arg)
	local which, rest = arg:match("^(%S*)%s*(.-)$")

	if which == "" or which == "show" then
		ns.Print("feeds: " .. Describe() .. ".")
		return
	end

	local entry = STREAMS[which]
	if not entry then
		ns.Print("there is no " .. which .. " feed. Try loot or combat.")
		return
	end

	-- A bare `/wk feed combat` and nothing else. `show` is not a synonym for it
	-- any more: it is the word that puts a hidden feed back on the screen, and
	-- one word cannot be both a question and an instruction.
	if rest:match("^(%S*)") == "" then
		ns.Print(("the %s feed is %s."):format(which, entry.describe()))
		return
	end

	WORDS[which](rest)
end

--------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------

-- The six rows every stream has, built from its prefix so neither tab is a copy
-- of the other with two words changed.
local function SharedPage(ui, entry)
	local prefix = entry.prefix
	local lower = entry.title:lower()

	ui.Check("collect " .. entry.collects, function() return ns.db[prefix] end,
		function(on)
			ns.db[prefix] = on
			entry.stream:Show()
			if entry.applied then
				entry.applied()
			end
		end)
	ui.Hint("Reach for this to make the feed cost nothing: off, " .. entry.cheap .. ".")

	ui.Check("show the " .. lower .. " feed", function() return ns.db[prefix .. "Shown"] end,
		function(on)
			ns.db[prefix .. "Shown"] = on
			entry.stream:Show()
		end)
	ui.Hint("Hidden and still collecting is close to free: drawing the column is the expensive half, and the history comes back with it.")

	ui.Count("rows", LOW_ROWS, HIGH_ROWS,
		function() return ns.db[prefix .. "Rows"] end,
		function(value)
			ns.db[prefix .. "Rows"] = value
			Apply(entry)
		end)

	ui.Size("width", LOW_WIDTH, HIGH_WIDTH, 10,
		function() return ns.db[prefix .. "Width"] end,
		function(value)
			ns.db[prefix .. "Width"] = value
			Apply(entry)
		end)

	ui.Size("icon", ns.UI.FEED_ICON_LOW, ns.UI.FEED_ICON_HIGH, 1,
		function() return ns.db[prefix .. "Icon"] end,
		function(value)
			ns.db[prefix .. "Icon"] = value
			Apply(entry)
		end)
	ui.Reading("the picture on a row", function()
		local drawn, sharp = ns.UI.FeedIcons(ns.db[prefix .. "Icon"],
			ns.db[prefix .. "Zoom"])
		return ("%d px, %s"):format(drawn,
			sharp and "one stored texel per pixel" or "resampled by the client")
	end)
	ui.Hint("The row is the icon plus two pixels, so this sets the line height too. Only 27 draws the client's art sharp.")

	ui.Check("a word over the column", function() return ns.db[prefix .. "Header"] end,
		function(on)
			ns.db[prefix .. "Header"] = on
			Apply(entry)
		end)

	ui.Check("a line round the frame", function() return ns.db[prefix .. "Edge"] end,
		function(on)
			ns.db[prefix .. "Edge"] = on
			Apply(entry)
		end)

	ui.Opacity("background",
		function() return ns.db[prefix .. "Alpha"] end,
		function(value)
			ns.db[prefix .. "Alpha"] = value
			Apply(entry)
		end)
	ui.Hint("The text is outlined either way and the line above goes with it, so at zero the feed is rows of text over the world.")

	ui.Check("rows answer the mouse", function() return ns.db[prefix .. "Mouse"] end,
		function(on)
			ns.db[prefix .. "Mouse"] = on
			Apply(entry)
		end)
	ui.Hint("On, a hover opens the row's tooltip and the wheel scrolls back. Off, the wheel goes past it to the camera.")

	ui.Action(function() return "put the " .. lower .. " feed back" end, function()
		entry.stream:Reset(ns.DefaultCopy(entry.prefix .. "Point"))
	end)
end

--------------------------------------------------------------------------
-- The float's own rows
--
-- Every number a floating message is made of, on the page under the switch
-- that turns it on. They were literals in Feeds/Floats.lua and none of them was
-- a fact: where the eye sits on a screen, how long a caption has to be up to be
-- read and how much of the middle a message may cross are answers about a
-- monitor and a person.
--
-- The two sides both work, and the second offset is why that took saying. A
-- message is pinned by the corner nearest the edge it came from, so the entry
-- offset is a distance to that corner and needs no width; the rest offset is
-- measured to the far edge and has the row's width taken off it, which is what
-- stops the message crossing the centre rather than stopping at it. Both are
-- resolved inside ns.Ck.Float at the moment of a push, so the numbers below
-- mean the same thing on either side and on any monitor.
--
-- The ranges are here rather than beside the defaults for the same reason the
-- feed's are: the file that draws the thing owns what it starts at, and the
-- page that offers the row owns what it will offer.
--------------------------------------------------------------------------

-- One key, as the pair of closures every row on this page wants.
--
-- Every one of them throws the lane away, because a lane resolves its spec when
-- it is built and then owns slots and a stagger clock worked out from those
-- numbers; the next drop builds one that has heard about the change. Four of
-- the rows would survive without it, since a row is dressed and measured on
-- every drop, but a page where one row applies and the next silently does not
-- is a page where the next number added lands in the wrong half.
local function Knob(key)
	return function()
		return ns.db[key]
	end, function(value)
		ns.db[key] = value
		ns.Floats.Apply()
	end
end

-- Two decimals and a unit, because these are the three settings on the page
-- measured in time and a bare 0.08 beside a bare 380 reads as the same kind of
-- number.
local function Seconds(value)
	return ("%.2fs"):format(value)
end

local SIDES = {
	{ value = "RIGHT", text = "right to left" },
	{ value = "LEFT", text = "left to right" },
}

local function FloatPage(ui)
	local function Time(label, low, high, step, key)
		local get, set = Knob(key)
		ui.Slider(label, low, high, step, get, set, Seconds)
	end

	ui.Check("float a drop across the screen", function() return ns.db.lootFloat end,
		function(on) ns.db.lootFloat = on end)
	ui.Hint("In from an edge, a moment beside the middle of the screen, then gone. Your own drops only, and it answers to nothing above: an item the chips have filtered out of the column still floats past.")

	local side, setSide = Knob("lootFloatSide")
	ui.Picker("crosses", side, setSide, function() return SIDES end)

	ui.Size("in from that edge", 0, 300, 5, Knob("lootFloatEdge"))

	ui.Size("stops short of the centre", 0, 500, 5, Knob("lootFloatRest"))
	ui.Hint("Measured to the far edge, so it is the gap left beside the middle rather than where the message's own corner lands.")

	ui.Size("down from the top", 0, 700, 10, Knob("lootFloatTop"))
	ui.Size("between messages", 0, 40, 1, Knob("lootFloatGap"))

	ui.Opacity("arrives at", Knob("lootFloatEnter"))
	ui.Opacity("rests at", Knob("lootFloatAlpha"))
	ui.Hint("It fades from the first to the second on the way in, and from the second to nothing when its time is up. Equal numbers slide without fading.")

	Time("travel and fade", 0.1, 2, 0.05, "lootFloatSeconds")
	Time("time on screen", 0.25, 10, 0.25, "lootFloatHold")
	Time("between arrivals", 0, 0.5, 0.02, "lootFloatStagger")
	ui.Hint("Nothing waits longer than it takes the column to fill, however many drop at once.")

	ui.Count("most at once", 1, 12, Knob("lootFloatMost"))
	ui.Hint("Past this the oldest message goes early to make room.")

	ui.Size("message width", 120, 700, 10, Knob("lootFloatWidth"))
	ui.Hint("A name too long for it is cut rather than wrapped.")

	ui.Size("picture", 16, 96, 2, Knob("lootFloatIcon"))

	ui.Opacity("colour back in", Knob("lootFloatLift"))
	ui.Hint("Adding the picture takes its black square off and drains the colour; this puts it back.")

	ui.Size("name", 8, 36, 1, Knob("lootFloatName"))
	ui.Size("count", 8, 36, 1, Knob("lootFloatCount"))
	ui.Hint("A row is as tall as the tallest of the three and the column is laid out by summing the rows.")
end

local function Panel(ui)
	ui.Section("Loot feed", "Feeds and meters")
	ui.Lede("What dropped, newest at the top, in the item's own quality colour, filtered by the chips over it.")

	SharedPage(ui, STREAMS.loot)

	ui.Divider()

	ui.Check("the filter chips over the column",
		function() return ns.db.lootFeedFilters end,
		function(on)
			ns.db.lootFeedFilters = on
			STREAMS.loot.stream:Apply()
		end)
	ui.Hint("Six squares in the quality colours, plus one for quest items. Off, the strip goes and the column draws everything it holds.")

	for level = LOW_QUALITY, HIGH_QUALITY do
		ui.Check(QualityWord(level):lower(),
			function() return ns.LootFeed.Lit(level) end,
			function(on)
				ns.LootFeed.Light(level, on)
				Chipped()
			end)
	end
	ui.Hint("The same switches as the chips. The feed records everything either way, so turning one back on brings its history with it.")

	ui.Check("quest items whatever their quality",
		function() return ns.db.lootFeedQuest end,
		function(on)
			ns.db.lootFeedQuest = on
			Chipped()
		end)
	ui.Hint("A quest item is white, the same white as linen. It gets a ring round its icon, and this keeps it on screen once the whites are off.")

	ui.Check("the group's drops too", function() return ns.db.lootFeedGroup end,
		function(on) ns.db.lootFeedGroup = on end)
	ui.Hint("Off by default. Everyone else's loot is what makes the client's own chat unreadable in a raid.")

	ui.Check("coin", function() return ns.db.lootFeedMoney end,
		function(on)
			ns.db.lootFeedMoney = on
			Chipped()
		end)

	ui.Check("the purse along the bottom", function() return ns.db.lootFeedPurse end,
		function(on)
			ns.db.lootFeedPurse = on
			STREAMS.loot.stream:Apply()
		end)
	ui.Hint("What you carry, what the account carries between it, and gold an hour since you logged in. Hover it for the list.")

	ui.Divider()

	FloatPage(ui)

	ui.Reading("rows so far", function()
		return tostring(ns.LootFeed.Counts())
	end)
	ui.Reading("loot messages this client carries", function()
		local live, total = ns.LootFeed.Rules()
		return ("%d of %d"):format(live, total)
	end)
	ui.Reading("what an item goes for", ns.Auction.Describe)

	ui.Section("Combat feed", "Feeds and meters")
	ui.Lede("The same column fed by the combat log: one row per thing that landed on you or on something.")

	SharedPage(ui, STREAMS.combat)

	ui.Divider()

	ui.Check("what you do", function() return ns.db.combatFeedOut end,
		function(on) ns.db.combatFeedOut = on end)

	ui.Check("what hits you", function() return ns.db.combatFeedIn end,
		function(on) ns.db.combatFeedIn = on end)

	ui.Check("misses and dodges", function() return ns.db.combatFeedMisses end,
		function(on) ns.db.combatFeedMisses = on end)
	ui.Hint("A miss is a row with no number and it earns one: four dodges in a row is why your rotation stalled.")

	ui.Stepper("smallest hit", LOW_FLOOR, 2000, 25,
		function() return ns.db.combatFeedFloor end,
		function(value) ns.db.combatFeedFloor = value end)
	ui.Hint("At zero this is every tick of every bleed on every mob in the pack, which scrolls faster than it can be read.")

	ui.Reading("rows so far", function()
		if not ns.CombatFeed.Ready() then
			return "this client has no combat log API, so the feed stays empty"
		end
		local seen, ignored = ns.CombatFeed.Counts()
		return ("%d, and %d under the floor"):format(seen, ignored)
	end)
end

--------------------------------------------------------------------------

local defaults = {}
for key, value in pairs(LootFeed.Defaults()) do
	defaults[key] = value
end
for key, value in pairs(CombatFeed.Defaults()) do
	defaults[key] = value
end
for key, value in pairs(ns.Floats.Defaults()) do
	defaults[key] = value
end

ns.Register({
	name = "feeds",
	order = 14,

	defaults = defaults,

	words = {
		feed = FeedWord,
	},

	help = {
		"feed loot on|off, and feed combat on|off, which is whether it collects",
		"feed <which> show|hide takes the column off the screen and leaves it collecting",
		"feed <which> rows 3 to 24, width 200 to 520, icon 16 to 40, zoom 1 to 3",
		"feed <which> alpha 0 to 100, mouse|header|edge|filters on|off",
		"feed loot poor|common|uncommon|rare|epic|quest|money on|off, which is what the column draws",
		"feed loot group on|off, purse on|off",
		"feed combat out|in|misses on|off, floor 0",
		"feed <which> clear empties it, reset puts it back where it started",
	},

	status = Describe,

	lock = function()
		ns.Stream.Each("Lock")
	end,

	reset = function()
		for _, key in ipairs(ORDER) do
			local entry = STREAMS[key]
			-- Shown is in the list and the switch beside it is not. A feed hidden
			-- and forgotten is exactly the "why can I not see this" that brings
			-- somebody to a reset button; a feed switched off is a decision about
			-- what the addon records, which is not this button's business.
			for _, word in ipairs({ "Rows", "Width", "Icon", "Zoom", "Alpha", "Mouse",
				"Shown", "Header", "Edge", "Filters" }) do
				ns.db[entry.prefix .. word] = ns.DefaultCopy(entry.prefix .. word)
			end
			entry.stream:Reset(ns.DefaultCopy(entry.prefix .. "Point"))
		end

		-- The chips go back with them, for the reason Shown is in the list
		-- above: a quality you turned off an hour ago and forgot is exactly the
		-- "why can I not see this" that brings somebody to a reset button, and
		-- unlike the switch beside it, it is not a decision about what the
		-- addon records.
		for _, key in ipairs({ "lootFeedShow", "lootFeedQuest", "lootFeedMoney" }) do
			ns.db[key] = ns.DefaultCopy(key)
		end
		Chipped()

		-- And the float's numbers, every one of them, minus the switch that
		-- turns it on for the reason the feed's own switch is not here either.
		-- A message that comes in from the wrong side or rests off the edge of
		-- the screen is unreadable rather than merely unwanted, and this is the
		-- button somebody reaches for when it is.
		for key in pairs(ns.Floats.Defaults()) do
			if key ~= "lootFloat" then
				ns.db[key] = ns.DefaultCopy(key)
			end
		end
		ns.Floats.Apply()
	end,

	panel = Panel,
})
