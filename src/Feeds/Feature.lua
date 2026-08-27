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

-- The word for each quality the floor can be set to, in the client's own
-- language where it has one. ITEM_QUALITY0_DESC and its siblings are what the
-- client calls them in its own tooltips, so a player reading "Uncommon" here
-- reads the same word the item does.
local QUALITY_WORDS = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic" }

local function QualityWord(level)
	local named = _G["ITEM_QUALITY" .. level .. "_DESC"]
	return (type(named) == "string" and named) or QUALITY_WORDS[level] or tostring(level)
end

-- The words the quality control cycles through, in level order, built out of
-- the same function that reads one back. UI.Kit's Cycle matches what get()
-- returns against the list it was given, so a list typed in English beside a
-- reader that answers the client's own word would never match on a German
-- client and every click would jump back to Poor.
local QUALITY_LIST = {}
for level = LOW_QUALITY, HIGH_QUALITY do
	QUALITY_LIST[level - LOW_QUALITY + 1] = QualityWord(level)
end

local function QualityLevel(word)
	for index, candidate in ipairs(QUALITY_LIST) do
		if candidate == word then
			return index - 1 + LOW_QUALITY
		end
	end
	return LOW_QUALITY
end

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
		point = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -20, 180 },
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
		point = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 20, 180 },
		describe = CombatFeed.Describe,
		collects = "what happens to you",
		costs = "a combat log event is turned away on one table lookup, which in a raid"
			.. " is the difference between a few hundred lookups a second and a few"
			.. " hundred rows a second.",
		cheap = "a combat log event is turned away on one table lookup",
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
end

-- The options every stream answers to. Returns true when it dealt with the
-- word, so the caller can fall through to the ones that are specific to it.
local function Shared(entry, option, value)
	local db, prefix = ns.db, entry.prefix

	if option == "rows" then
		local rows = ns.Command.Number(value, LOW_ROWS, HIGH_ROWS, entry.title .. " rows")
		if rows then
			db[prefix .. "Rows"] = rows
			Apply(entry)
			ns.Print(("the %s feed shows %d rows."):format(entry.title:lower(), rows))
		end
		return true
	end

	if option == "width" then
		local width = ns.Command.Number(value, LOW_WIDTH, HIGH_WIDTH, entry.title .. " width")
		if width then
			db[prefix .. "Width"] = width
			Apply(entry)
			ns.Print(("the %s feed is %d pixels wide."):format(entry.title:lower(), width))
		end
		return true
	end

	if option == "zoom" then
		local zoom = ns.Command.Number(value, ns.UI.ZOOM_LOW, ns.UI.ZOOM_HIGH, entry.title .. " zoom")
		if zoom then
			db[prefix .. "Zoom"] = zoom
			Apply(entry)
			ns.Print(("the %s feed at %dx."):format(entry.title:lower(), zoom))
		end
		return true
	end

	if option == "alpha" then
		local alpha = ns.Command.Step(value, ns.UI.ALPHA_LOW, ns.UI.ALPHA_HIGH, ns.UI.ALPHA_STEP,
			entry.title .. " background")
		if alpha then
			db[prefix .. "Alpha"] = alpha
			Apply(entry)
			ns.Print(("the %s feed background at %d%%."):format(entry.title:lower(), alpha))
		end
		return true
	end

	if option == "show" or option == "hide" then
		db[prefix .. "Shown"] = (option == "show")
		entry.stream:Show()
		ns.Print(("the %s feed is %s. It %s collecting."):format(entry.title:lower(),
			(option == "show") and "on screen" or "hidden",
			db[prefix] and "is still" or "is not"))
		return true
	end

	if option == "mouse" then
		db[prefix .. "Mouse"] = ns.Command.Toggle(value)
		Apply(entry)
		ns.Print(("the %s feed %s the mouse."):format(entry.title:lower(),
			db[prefix .. "Mouse"] and "takes" or "ignores"))
		return true
	end

	if option == "clear" then
		entry.stream:Feed():Clear()
		ns.Print(("the %s feed is empty."):format(entry.title:lower()))
		return true
	end

	if option == "reset" then
		entry.stream:Reset({ entry.point[1], entry.point[2], entry.point[3],
			entry.point[4], entry.point[5] })
		ns.Print(("the %s feed is back where it started."):format(entry.title:lower()))
		return true
	end

	return false
end

local function LootOption(_, option, value)
	if option == "group" then
		ns.db.lootFeedGroup = ns.Command.Toggle(value)
		ns.Print("the loot feed " .. (ns.db.lootFeedGroup
			and "shows what the group picks up too." or "shows your own drops only."))
		return true
	end

	if option == "quality" then
		local level = ns.Command.Number(value, LOW_QUALITY, HIGH_QUALITY, "loot quality")
		if level then
			ns.db.lootFeedQuality = level
			ns.Print(("the loot feed shows %s and better."):format(QualityWord(level)))
		end
		return true
	end

	if option == "money" then
		ns.db.lootFeedMoney = ns.Command.Toggle(value)
		ns.Print("coin " .. (ns.db.lootFeedMoney and "goes in the feed." or "stays out of the feed."))
		return true
	end

	if option == "purse" then
		ns.db.lootFeedPurse = ns.Command.Toggle(value)
		STREAMS.loot.stream:Apply()
		ns.Print("the purse " .. (ns.db.lootFeedPurse
			and "sits along the bottom of the feed."
			or "is off and the feed has the height back."))
		return true
	end

	return false
end

local function CombatOption(_, option, value)
	if option == "out" or option == "in" then
		local key = (option == "out") and "combatFeedOut" or "combatFeedIn"
		ns.db[key] = ns.Command.Toggle(value)
		ns.Print(("%s is %s."):format(
			(option == "out") and "what you do" or "what hits you",
			ns.db[key] and "in the feed" or "out of the feed"))
		return true
	end

	if option == "misses" then
		ns.db.combatFeedMisses = ns.Command.Toggle(value)
		ns.Print("misses and dodges " .. (ns.db.combatFeedMisses and "get a row." or "are ignored."))
		return true
	end

	if option == "floor" then
		local floor = ns.Command.Number(value, LOW_FLOOR, HIGH_FLOOR, "combat floor")
		if floor then
			ns.db.combatFeedFloor = floor
			ns.Print((floor > 0)
				and ("nothing under %d gets a row."):format(floor)
				or "every hit gets a row.")
		end
		return true
	end

	return false
end

local EXTRA = { loot = LootOption, combat = CombatOption }

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

	local option, value = rest:match("^(%S*)%s*(.-)$")

	-- A bare `/wk feed combat` and nothing else. `show` is not a synonym for it
	-- any more: it is the word that puts a hidden feed back on the screen, and
	-- one word cannot be both a question and an instruction.
	if option == "" then
		ns.Print(("the %s feed is %s."):format(which, entry.describe()))
		return
	end

	if Shared(entry, option, value) then
		return
	end
	if EXTRA[which](entry, option, value) then
		return
	end

	-- Anything left is the on/off switch, which is what a bare word means
	-- everywhere else in this addon. On this feature it is the collecting
	-- switch rather than the visibility one: off records nothing, and `hide`
	-- above is the word for taking a working feed off the screen.
	ns.db[entry.prefix] = ns.Command.Toggle(option)
	Apply(entry)
	ns.Print(("the %s feed is %s."):format(which,
		ns.db[entry.prefix] and "collecting" or "off, and recording nothing"))
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
		end)
	ui.Hint("This is the switch to reach for if you want the feed to cost nothing: off, " .. entry.cheap .. ".")

	ui.Check("show the " .. lower .. " feed", function() return ns.db[prefix .. "Shown"] end,
		function(on)
			ns.db[prefix .. "Shown"] = on
			entry.stream:Show()
		end)
	ui.Hint("Hidden and still collecting is close to free, because drawing the column is the expensive half. Show it again and the last few hundred rows come back with it.")

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

	ui.Opacity("background",
		function() return ns.db[prefix .. "Alpha"] end,
		function(value)
			ns.db[prefix .. "Alpha"] = value
			Apply(entry)
		end)
	ui.Hint("The text is outlined either way, so it reads all the way down to nothing. At zero the edge goes with the background and the feed is rows of text over the world.")

	ui.Check("rows answer the mouse", function() return ns.db[prefix .. "Mouse"] end,
		function(on)
			ns.db[prefix .. "Mouse"] = on
			Apply(entry)
		end)
	ui.Hint("On, hovering a row opens its tooltip and the wheel scrolls back. Off, the feed is a picture and the wheel goes past it to the camera.")

	ui.Reading("the mouse", ns.UI.Tooltip.Describe)

	ui.Action(function() return "put the " .. lower .. " feed back" end, function()
		entry.stream:Reset({ entry.point[1], entry.point[2], entry.point[3],
			entry.point[4], entry.point[5] })
	end)
end

local function Panel(ui)
	ui.Section("Loot feed", "Readouts")
	ui.Lede("A column of what dropped, newest at the top, each row in the item's own quality colour.")

	SharedPage(ui, STREAMS.loot)

	ui.Divider()

	ui.Cycle("show", QUALITY_LIST,
		function() return QualityWord(ns.db.lootFeedQuality) end,
		function(word)
			ns.db.lootFeedQuality = QualityLevel(word)
		end)
	ui.Hint("Everything is the default, grey vendor trash included, because the addon sells that trash for you and the feed is the only place you will see what it was.")

	ui.Check("the group's drops too", function() return ns.db.lootFeedGroup end,
		function(on) ns.db.lootFeedGroup = on end)
	ui.Hint("Off by default. Everyone else's loot is what makes the client's own chat unreadable in a raid.")

	ui.Check("coin", function() return ns.db.lootFeedMoney end,
		function(on) ns.db.lootFeedMoney = on end)

	ui.Check("the purse along the bottom", function() return ns.db.lootFeedPurse end,
		function(on)
			ns.db.lootFeedPurse = on
			STREAMS.loot.stream:Apply()
		end)
	ui.Hint("What you are carrying, what every character on the account is carrying between them, and gold an hour since you logged in. Hover it for the list. Off, the feed gives the height back.")

	ui.Reading("rows so far", function()
		local seen, dropped = ns.LootFeed.Counts()
		return ("%d, and %d under the quality floor"):format(seen, dropped)
	end)
	ui.Reading("loot messages this client carries", function()
		local live, total = ns.LootFeed.Rules()
		return ("%d of %d"):format(live, total)
	end)

	ui.Section("Combat feed", "Readouts")
	ui.Lede("The same column fed by the combat log: one row per thing that landed on you or on something.")

	SharedPage(ui, STREAMS.combat)

	ui.Divider()

	ui.Check("what you do", function() return ns.db.combatFeedOut end,
		function(on) ns.db.combatFeedOut = on end)

	ui.Check("what hits you", function() return ns.db.combatFeedIn end,
		function(on) ns.db.combatFeedIn = on end)

	ui.Check("misses and dodges", function() return ns.db.combatFeedMisses end,
		function(on) ns.db.combatFeedMisses = on end)
	ui.Hint("A miss is a row with no number on it and it earns one: four dodges in a row is why your rotation stalled, and nothing else on screen says so.")

	ui.Stepper("smallest hit", LOW_FLOOR, 2000, 25,
		function() return ns.db.combatFeedFloor end,
		function(value) ns.db.combatFeedFloor = value end)
	ui.Hint("At zero this is every tick of every bleed on every mob in the pack, which in a fury pull scrolls faster than it can be read. This is the number that fixes it.")

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

ns.Register({
	name = "feeds",
	order = 11,

	defaults = defaults,

	words = {
		feed = FeedWord,
	},

	help = {
		"feed loot on|off, and feed combat on|off, which is whether it collects",
		"feed <which> show|hide takes the column off the screen and leaves it collecting",
		"feed <which> rows 3 to 24, width 200 to 520, zoom 1 to 3, alpha 0 to 100, mouse on|off",
		"feed loot quality 0 to 4, group on|off, money on|off, purse on|off",
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
			for _, word in ipairs({ "Rows", "Width", "Zoom", "Alpha", "Mouse", "Shown" }) do
				ns.db[entry.prefix .. word] = ns.DefaultFor(entry.prefix .. word)
			end
			entry.stream:Reset({ entry.point[1], entry.point[2], entry.point[3],
				entry.point[4], entry.point[5] })
		end
	end,

	panel = Panel,
})
