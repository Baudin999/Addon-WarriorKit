local ADDON, ns = ...

-- The tab. Feeds/Stream.lua is the frame, UI/Feed.lua is the column, and
-- Feeds/Loot.lua and Feeds/Combat.lua are the two things worth putting in one.
-- This file is the only one in the folder that knows the addon around it.

local LootFeed = ns.LootFeed
local CombatFeed = ns.CombatFeed

local LOW_ROWS, HIGH_ROWS = 3, 24
local LOW_WIDTH, HIGH_WIDTH = 140, 420
local LOW_ZOOM, HIGH_ZOOM = 1, 3
local LOW_ALPHA, HIGH_ALPHA, ALPHA_STEP = 0, 100, 5
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
	},
	combat = {
		stream = CombatFeed.Stream(),
		prefix = "combatFeed",
		title = "Combat",
		point = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 20, 180 },
		describe = CombatFeed.Describe,
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
		local zoom = ns.Command.Number(value, LOW_ZOOM, HIGH_ZOOM, entry.title .. " zoom")
		if zoom then
			db[prefix .. "Zoom"] = zoom
			Apply(entry)
			ns.Print(("the %s feed at %dx."):format(entry.title:lower(), zoom))
		end
		return true
	end

	if option == "alpha" then
		local alpha = ns.Command.Step(value, LOW_ALPHA, HIGH_ALPHA, ALPHA_STEP,
			entry.title .. " background")
		if alpha then
			db[prefix .. "Alpha"] = alpha
			Apply(entry)
			ns.Print(("the %s feed background at %d%%."):format(entry.title:lower(), alpha))
		end
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

	if option == "" or option == "show" then
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
	-- everywhere else in this addon.
	ns.db[entry.prefix] = ns.Command.Toggle(option)
	Apply(entry)
	ns.Print(("the %s feed is %s."):format(which, ns.db[entry.prefix] and "on" or "off"))
end

--------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------

-- The six rows every stream has, built from its prefix so neither tab is a copy
-- of the other with two words changed.
local function SharedPage(ui, entry)
	local prefix = entry.prefix
	local lower = entry.title:lower()

	ui.Check("Show the " .. lower .. " feed", function() return ns.db[prefix] end,
		function(on)
			ns.db[prefix] = on
			entry.stream:Show()
		end)

	ui.Stepper("rows", LOW_ROWS, HIGH_ROWS, 1,
		function() return ns.db[prefix .. "Rows"] end,
		function(value)
			ns.db[prefix .. "Rows"] = value
			Apply(entry)
		end)

	ui.Stepper("width", LOW_WIDTH, HIGH_WIDTH, 10,
		function() return ns.db[prefix .. "Width"] end,
		function(value)
			ns.db[prefix .. "Width"] = value
			Apply(entry)
		end)

	ui.Slider("background", LOW_ALPHA, HIGH_ALPHA, ALPHA_STEP,
		function() return ns.db[prefix .. "Alpha"] end,
		function(value)
			ns.db[prefix .. "Alpha"] = value
			Apply(entry)
		end,
		function(value) return value .. "%" end)

	ui.Note(function()
		if ns.db[prefix .. "Alpha"] > 0 then
			return "How solid the panel behind the rows is. The text is outlined either"
				.. " way, so it stays readable all the way down to nothing, and at zero"
				.. " the edge goes with the background: a hairline rectangle round bare"
				.. " world is a window frame with no window in it."
		end
		return "No background, so this is rows of outlined text over the world, the way"
			.. " the meters are drawn. The scrollbar goes with it in everything but the"
			.. " thumb, which is the only thing left saying there is more above and"
			.. " below what you can see."
	end)

	ui.Stepper("zoom", LOW_ZOOM, HIGH_ZOOM, 1,
		function() return ns.db[prefix .. "Zoom"] end,
		function(value)
			ns.db[prefix .. "Zoom"] = value
			Apply(entry)
		end)

	ui.Note(function()
		local drawn, exact = ns.UI.FeedIcons(ns.db[prefix .. "Zoom"])
		if exact then
			return ("A row icon draws %d screen pixels of art, one stored texel per"
				.. " pixel, which is as sharp as an icon gets."):format(drawn)
		end
		return ("|cffd08040A row icon draws %d screen pixels of art|r, blended from two"
			.. " stored copies. The crop in UI/Draw.lua leaves 54 texels and only 54"
			.. " and 27 land one texel on one pixel, so zoom 1 and zoom 2 are exact"
			.. " and this one is not."):format(drawn)
	end)

	ui.Check("Rows answer the mouse", function() return ns.db[prefix .. "Mouse"] end,
		function(on)
			ns.db[prefix .. "Mouse"] = on
			Apply(entry)
		end)

	ui.Note(function()
		if not ns.db[prefix .. "Mouse"] then
			return "Off, so the feed is a picture. Nothing on it can be hovered and the"
				.. " wheel goes past it to the camera, which means there is no way to"
				.. " see the older rows but to make the feed taller."
		end
		return "Hovering a row opens the addon's own tooltip beside it, and the wheel"
			.. " scrolls back through what has already happened. The price is that a"
			.. " mouse enabled frame swallows every button that lands on it: the right"
			.. " and middle buttons are handed back where this client has"
			.. " SetPassThroughButtons, and where it does not, a right drag begun on"
			.. " the feed will not turn the camera. |cffd08040" .. ns.UI.Tooltip.Describe()
			.. "|r"
	end)

	ui.Action(function() return "put the " .. lower .. " feed back" end, function()
		entry.stream:Reset({ entry.point[1], entry.point[2], entry.point[3],
			entry.point[4], entry.point[5] })
	end)
end

local function Panel(ui)
	ui.Header("Loot feed")

	ui.Note(function()
		return "What dropped, newest at the top, older underneath it. A row is the"
			.. " item's icon, its name in its own quality colour and how many there"
			.. " were, with a stripe down the left in that same colour so a run of"
			.. " drops reads as a ribbon before you read a word of it. Hover one for"
			.. " the item's own tooltip, drawn in this interface rather than in"
			.. " Blizzard's parchment."
	end)

	ui.Note(function()
		local seen, dropped = ns.LootFeed.Counts()
		local live, total = ns.LootFeed.Rules()
		if live < total then
			return ("|cffd08040This client carries %d of the %d loot messages|r, so some"
				.. " of what drops will not be recognised. %d rows so far, %d under the"
				.. " quality floor."):format(live, total, seen, dropped)
		end
		return ("%d rows so far, %d under the quality floor."):format(seen, dropped)
	end)

	SharedPage(ui, STREAMS.loot)

	ui.Divider()

	ui.Cycle("show", QUALITY_LIST,
		function() return QualityWord(ns.db.lootFeedQuality) end,
		function(word)
			ns.db.lootFeedQuality = QualityLevel(word)
		end)

	ui.Note(function()
		if ns.db.lootFeedQuality == 0 then
			return "Everything, grey vendor trash included. That is the default because"
				.. " this addon sells that trash for you at the next merchant, so the"
				.. " feed is the only place you will ever see what it was."
		end
		return ("%s and better. Anything under it is picked up as before and simply"
			.. " does not get a row."):format(QualityWord(ns.db.lootFeedQuality))
	end)

	ui.Check("The group's drops too", function() return ns.db.lootFeedGroup end,
		function(on) ns.db.lootFeedGroup = on end)

	ui.Note(function()
		return "Off by default. Everyone else's loot is what makes the client's own"
			.. " chat unreadable in a raid, and a feed that reproduced it would have"
			.. " replaced one unreadable column with a prettier one."
	end)

	ui.Check("Coin", function() return ns.db.lootFeedMoney end,
		function(on) ns.db.lootFeedMoney = on end)

	--------------------------------------------------------------------

	ui.Header("Combat feed")

	ui.Note(function()
		return "The same column, fed by the combat log: one row per thing that landed"
			.. " on you or that you landed on something. The stripe says which way it"
			.. " went, white out, red in, green healed and grey missed, and a critical"
			.. " draws its number in gold. Hover a row for the whole event."
	end)

	ui.Note(function()
		if not ns.CombatFeed.Ready() then
			return "|cffd08040This client has no combat log API|r, so the feed stays"
				.. " empty. Nothing here can be made to work without it and a made up"
				.. " row would be worse than a blank."
		end
		local seen, ignored = ns.CombatFeed.Counts()
		return ("%d rows so far, %d under the floor. This is not the meters: they"
			.. " total a fight and this is a list of moments, and the two share"
			.. " nothing."):format(seen, ignored)
	end)

	SharedPage(ui, STREAMS.combat)

	ui.Divider()

	ui.Check("What you do", function() return ns.db.combatFeedOut end,
		function(on) ns.db.combatFeedOut = on end)

	ui.Check("What hits you", function() return ns.db.combatFeedIn end,
		function(on) ns.db.combatFeedIn = on end)

	ui.Check("Misses and dodges", function() return ns.db.combatFeedMisses end,
		function(on) ns.db.combatFeedMisses = on end)

	ui.Note(function()
		return "A miss is a row with no number on it and it earns one: four dodges in a"
			.. " row is the reason your rotation stalled, and nothing else on the"
			.. " screen says so."
	end)

	ui.Stepper("smallest hit", LOW_FLOOR, 2000, 25,
		function() return ns.db.combatFeedFloor end,
		function(value) ns.db.combatFeedFloor = value end)

	ui.Note(function()
		if ns.db.combatFeedFloor == 0 then
			return "Every hit, including every tick of every bleed on every mob in the"
				.. " pack. In a fury pull that is a feed which scrolls faster than it"
				.. " can be read, and this is the number that fixes it."
		end
		return ("Nothing under %d gets a row. The right floor at level 20 and the right"
			.. " floor in a raid differ by an order of magnitude, which is why this is"
			.. " a setting rather than a number the addon picked.")
			:format(ns.db.combatFeedFloor)
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
	order = 7.7,

	defaults = defaults,

	words = {
		feed = FeedWord,
	},

	help = {
		"feed loot on|off, and feed combat on|off",
		"feed <which> rows 10, width 220, zoom 1 to 3, alpha 70, mouse on|off",
		"feed loot quality 0 to 4, group on|off, money on|off",
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
			for _, word in ipairs({ "Rows", "Width", "Zoom", "Alpha", "Mouse" }) do
				ns.db[entry.prefix .. word] = ns.DefaultFor(entry.prefix .. word)
			end
			entry.stream:Reset({ entry.point[1], entry.point[2], entry.point[3],
				entry.point[4], entry.point[5] })
		end
	end,

	panel = Panel,
})
