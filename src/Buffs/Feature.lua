local ADDON, ns = ...

-- Everything Core and the panel need to know about the buff nag. Upkeep.lua
-- says what should be up and is not and which line each entry stands on,
-- Racials.lua says which cooldown you own and whether it is worth a square,
-- Nag.lua draws the row, Panel.lua draws it again on the options page so you
-- can drag it about, and none of the four names anything outside this folder.
--
-- Not gated on class. A lapsed sharpening stone costs a hunter's melee weapon
-- exactly what it costs a warrior's, and a troll rogue forgets Berserking the
-- same way. What your class adds to the row is written in Class/<yours>.lua and
-- merged in by Upkeep.Fixed, so this part runs for everybody and knows the name
-- of nobody's spell.


local function SetBuffs(value)
	ns.db.buffs = value
	ns.BuffNag.Apply()
end

-- Which lines an entry is on, in the words the page uses.
local function LineSaid(word)
	if word == ns.Upkeep.BOTH then
		return "in and out of a fight"
	end
	return word == ns.Upkeep.IN and "in a fight" or "out of a fight"
end

-- The words the nag answers to, and the two lists an unknown word is looked up
-- in before it is read as the on|off value. The lookups are in `otherwise`
-- rather than as entries because neither is a word this file knows: one is
-- whatever your class put on the row, and the other is whatever somebody
-- else's class did. The racial is one of those words now, because it is an
-- entry on the row like the others, so `buffs racial off` goes the way
-- `buffs food off` does.
local BuffWord = ns.Command.Word({
	name = "buff",
	apply = function() ns.BuffNag.Apply() end,
	show = function()
		return "buff nag " .. ns.BuffNag.Describe() .. "."
	end,

	-- No apply: nothing is laid out again for a square that pulses or does not.
	{ "pulse", toggle = true, key = "buffPulse", apply = false,
	  say = function(on)
		return "the racial square " .. (on and "pulses" or "sits still") .. "."
	  end },

	{ "resting", toggle = true, key = "buffResting",
	  say = function(on)
		return on and "the row nags in inns and cities too."
			or "the row is quiet while you are resting."
	  end },

	ns.Command.Zoom("buffZoom", "the buff row draws at %dx."),

	{ "list", run = function()
		local extra = ns.Upkeep.Extra()
		if #extra == 0 then
			ns.Print("nothing of your own on the row. buffs add <spell id>, or drag one onto the page.")
			return
		end
		for index = 1, #extra do
			local id = extra[index]
			local entry = ns.Upkeep.Owner(id)
			ns.Print(("  %d  %-24s %s"):format(id,
				ns.SpellName(id) or "this client cannot name it",
				entry and LineSaid(ns.Upkeep.Lines(entry)) or ""))
		end
	  end },

	{ "add", run = function(value)
		local ok, message = ns.Upkeep.Add(value)
		ns.Print(ok and (message .. " is on the row.") or message)
		ns.BuffNag.Apply()
	  end },

	{ "remove", run = function(value)
		if ns.Upkeep.Remove(value) then
			ns.Print("off the row.")
			ns.BuffNag.Apply()
		else
			ns.Print("nothing on the row has that id. buffs list shows them.")
		end
	  end },

	-- The drag, typed. `buffs line shield both` puts the shield square on both
	-- lines; `in` and `out` put it on that line alone.
	{ "line", run = function(value)
		local word, where = value:match("^(%S+)%s*(%S*)$")
		local entry = word and (ns.Upkeep.ByWord(word) or ns.Upkeep.Owner(tonumber(word) or 0))
		if not entry then
			ns.Print("nothing on the row answers to " .. tostring(word) .. ".")
			return
		end
		if where ~= ns.Upkeep.IN and where ~= ns.Upkeep.OUT and where ~= ns.Upkeep.BOTH then
			ns.Print("buffs line <name> in|out|both. " .. (entry.label or entry.key)
				.. " is checked " .. LineSaid(ns.Upkeep.Lines(entry)) .. ".")
			return
		end
		-- Said as a whole rather than added to, because the word names where
		-- the square ends up and not a line to put it on as well.
		local ok, why = ns.Upkeep.Place(entry.key, where, true)
		ns.Print(ok and ((entry.label or entry.key) .. " is checked " .. LineSaid(where) .. ".")
			or why)
		ns.BuffNag.Apply()
	  end },

	otherwise = function(option, value)
		-- One switch per watched entry, driven off the list itself so the words
		-- and the tick boxes on the panel cannot drift apart.
		local entry = ns.Upkeep.ByWord(option)
		if entry then
			ns.Upkeep.SetWatched(entry.key, ns.Command.Toggle(value))
			ns.BuffNag.Apply()
			ns.Print((entry.fixed or entry.word) .. (ns.Upkeep.Watched(entry.key)
				and " is watched again on this character."
				or " is switched off on this character."))
			return
		end

		-- A word another class puts on the row, said as such. Without this it
		-- would fall through to the toggle below, switch the whole nag off and
		-- report that it had done something else entirely.
		local elsewhere = ns.Upkeep.Elsewhere(option)
		if elsewhere then
			ns.Print(option .. " is on the row for a " .. elsewhere .. " and nowhere"
				.. " else, so there is nothing here to switch off.")
			return
		end

		SetBuffs(ns.Command.Toggle(option))
		ns.Print("buff nag " .. (ns.db.buffs and "on" or "off") .. ".")
	end,
})

--------------------------------------------------------------------------
-- The pages
--
-- One section in three functions, because the one function it was sat at the
-- shape gate's ceiling before the row was drawn on it.
--------------------------------------------------------------------------

-- The switch, the numbers and the placing, and under them what the row
-- watches, drawn as its two lines. One page, which is the rule every part
-- follows now: the row and what is on it were two sections for a day and the
-- split put the tick boxes a page away from the switch.
local function RowPage(ui)
	ui.Section("Missing buffs", "Fighting")
	ui.Lede("A row of squares over your character, only while something you keep up is missing: what you put on before a pull, and in a fight what lapses mid swing.")

	ui.Check("nag in inns and cities too",
		function() return ns.db.buffResting end,
		function(value)
			ns.db.buffResting = value
			ns.BuffNag.Apply()
		end)

	ui.Zoom(function() return ns.db.buffZoom end,
		function(value)
			ns.db.buffZoom = value
			ns.BuffNag.Apply()
		end)

	ui.Action(function() return "put the row back" end, function()
		ns.BuffNag.Reset()
	end)

	ui.Hint("Unlock the frames to drag the row. Click a square on it to come back here.")
end

-- The racial's own two rows, on the same page, because it is one entry on
-- the row and a page of its own said otherwise.
local function RacialRows(ui)
	ui.Check("make the racial square pulse",
		function() return ns.db.buffPulse end,
		function(value) ns.db.buffPulse = value end)
	ui.Hint("The square breathes over about a second and a half. There is no sound: a chime competes with the sounds you are listening for.")

	-- The reading says which racial and whether it is one worth a square; a
	-- situational one says so in its own words, which is the hint that used to
	-- hang here.
	ui.Reading("your racial", ns.Racials.Describe)
end

-- What the row watches, drawn as the two lines it will draw and then said as a
-- list of switches. The same section as the row, continued.
local function WatchPage(ui)
	ns.BuffPanel.Rows(ui)
	ns.BuffPanel.Tray(ui)

	ui.TextField("or add a buff by id",
		function() return "" end,
		function(text)
			if text:match("^%s*$") then
				return
			end
			local ok, message = ns.Upkeep.Add(text)
			ns.Print(ok and (message .. " is on the row.") or message)
			ns.BuffNag.Apply()
			ns.Options.Refresh()
		end)
	-- One hint for the two rows above it as well, because a custom row takes
	-- none and the sentence about the drag has to hang somewhere.
	ui.Hint("Drag a spell off your spellbook onto either line or both, and a square off a line to stop. The id is for what you cannot drag: the aura a flask leaves on you.")

	ui.Reading("your own", function()
		return ("%d of %d"):format(#ns.Upkeep.Extra(), ns.Upkeep.MaxExtra())
	end)

	-- One switch per shipped entry, built from Upkeep's own list rather than
	-- from literals here, so an entry added to the shipped four, or by your
	-- class, arrives with its switch already on the page. The list is already
	-- this character's: Upkeep.Fixed merges in your class's entries and nobody
	-- else's, so a tick box that writes a setting nothing on this character
	-- reads cannot be drawn.
	--
	-- The same fact as dragging a square off, said as a sentence. A low level
	-- character has no buff food and no stones, and a tick box is the shortest
	-- way to say so.
	local watched = ns.Upkeep.Fixed()
	for index = 1, #watched do
		local entry = watched[index]
		ui.Check(entry.switch,
			function() return ns.Upkeep.Watched(entry.key) end,
			function(value)
				ns.Upkeep.SetWatched(entry.key, value)
				ns.BuffNag.Apply()
			end)
	end
	ui.Hint("Per character, because whether a bare weapon is worth a square is a raiding main's answer and not a bank alt's.")

	ui.Reading("switched off", function()
		local silent, names = ns.Upkeep.Silent()
		return silent == 0 and "nothing, the row is watching all of it" or names
	end)
	RacialRows(ui)

	ui.Reading("your main hand", function()
		if not ns.Upkeep.EnchantShape() then
			return "this client has no GetWeaponEnchantInfo"
		end
		if not GetInventoryItemLink("player", ns.Gear.MAINHAND) then
			return "empty, so there is nothing to put a stone on"
		end
		local hand = ns.Upkeep.Left(ns.Gear.MAINHAND)
		if hand == nil then
			return "bare"
		end
		return ("enchanted, %d minutes left"):format(math.floor(hand / 60))
	end)
	ui.Reading("the row", ns.BuffNag.Describe)
end

ns.Register({
	name = "buffs",

	switch = {
		key = "buffs",
		label = "the missing-buff row",
		apply = function(value) SetBuffs(value) end,
	},

	-- Beside the swing timer and the cooldown row, which are the other two
	-- things on screen that say what to press next. Whole, like every other
	-- order: the registry refuses a fraction, so making room in the middle of
	-- the rail renumbers what comes after it, which is what putting the
	-- cooldown row at 10 did to the nine parts below it.
	order = 10,

	zooms = {
		{ key = "buffZoom", label = "Missing buff row", apply = function() ns.BuffNag.Apply() end },
	},

	defaults = {
		buffs = true,

		-- On. A still square in the middle of the screen is a thing you learn
		-- to look past in a week, and the request was for something you cannot
		-- ignore. Off is a real preference and this is where it lives.
		buffPulse = true,

		-- Off, meaning quiet while you are resting. An inn or a capital is
		-- where you have not put a stone on yet on purpose, and a row that
		-- stayed up through an hour at the auction house would be furniture by
		-- the time it mattered. On for anyone who buffs in the bank.
		buffResting = false,

		-- 2, and this is the one readout in the addon that ships at twice the
		-- size of the others. Its whole job is to be impossible to miss, and 27
		-- design pixels at 2x is 54 physical ones, which is also the other size
		-- a 64 texel icon resamples onto exactly. Bigger is not sharper: 3x
		-- draws 81 from a 54 texel source and blends.
		buffZoom = 2,

		-- Above the middle of the screen, over your character's head and clear
		-- of the charge icon at -190 and the swing bars at -157. Both numbers
		-- whole, because half of an odd number is half a pixel and this frame
		-- is on the grid.
		buffPoint = { "CENTER", "UIParent", "CENTER", -1, 157 },
	},

	-- Per character, all three, and the argument is the one that put the first
	-- of them here.
	--
	-- Everything in `defaults` above is a preference about the row itself: how
	-- big it is, whether it breathes, whether it draws in an inn. Those are the
	-- same answer on every character you own and they belong to the account.
	--
	-- Whether a missing sharpening stone is worth telling you about is not a
	-- preference. It is a fact about the character, and it differs between two
	-- characters on the same account more sharply than almost anything else this
	-- addon stores. A raiding main carries a stack of stones and wants the
	-- square. A bank alt has never bought one, is never going to, and is shown a
	-- red square over its head every time it leaves combat for a thing it cannot
	-- fix. That is the exact failure `buffWatch` exists to end.
	--
	-- The other two followed it the day a spell could be dragged on. A shield
	-- dragged onto the in line by a shaman is a shield the same account's
	-- warrior can never put up, and an account-wide list would have nagged the
	-- warrior about it in every fight for the rest of its life. Core moves a key
	-- that changes scope out of the account table once at ADDON_LOADED, so a
	-- flask list that was the account's is the first character's to log in.
	charDefaults = {
		-- Which entries this character still watches, keyed by the entry's own
		-- key and holding false for each one you switched off. Absent means
		-- watched, so a fresh character carries an empty table.
		buffWatch = {},

		-- The spells you put on the row yourself, as ids, in the order you added
		-- them. Empty, because these clients will not say an aura came from an
		-- elixir and there is nothing to ship a default for.
		buffExtra = {},

		-- Which line you moved an entry to, keyed by the entry's own key and
		-- holding only the ones you moved. Absent means the line it shipped on,
		-- so a class file that changes its mind is followed rather than
		-- overridden by a setting you never knowingly wrote.
		buffLine = {},
	},

	words = {
		buffs = BuffWord,
	},

	help = {
		"buffs on|off, the row of what is missing",
		"buffs weapon|offhand|shout|food|racial on|off, one entry at a time",
		"buffs line <name or id> in|out|both, which line its square is on",
		"buffs pulse on|off, resting on|off, zoom 1 to 3",
		"buffs list, buffs add|remove <spell id>, your own flask and elixirs",
	},

	status = function()
		return ns.BuffNag.Describe()
	end,

	lock = function()
		ns.BuffNag.Lock()
	end,

	reset = function()
		ns.BuffNag.Reset()
	end,

	panel = function(ui)
		RowPage(ui)
		WatchPage(ui)
	end,
})

-- What the timing figure on the performance tab is a timing of. A row with
-- nothing on it costs one comparison; the number only means something beside a
-- count of squares.
ns.Perf.Gauge("buff squares on screen", function()
	return ns.BuffNag.Shown()
end)
