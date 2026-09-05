local ADDON, ns = ...

-- Everything Core and the panel need to know about the cooldown row.
-- Cooldowns.lua says what is on it, Row.lua draws it on your screen, Panel.lua
-- draws it on the options page so you can arrange it, and none of the three
-- names anything outside this folder.
--
-- Not gated on class, and that is the same decision Buffs\Feature.lua made. A
-- class with no `cooldowns` field still has two trinket slots, and a trinket
-- you press is the same fact about the same slot whoever is wearing it. What
-- your class adds is written in Class\<yours>.lua and merged in by
-- Cooldowns.All, so this part runs for everybody and knows the name of nobody's
-- spell.

local function SetRow(value)
	ns.db.cooldowns = value
	ns.CooldownRow.Apply()
end

-- The words that change what is on the row and where, rather than what the row
-- itself does. Their own function because CooldownWord is a dispatcher already
-- near the branch gate, and because these five are one subject.
--
-- Returns whether the word was one of them, so anything else still falls
-- through to the per entry switch and then to the bare on|off toggle the way it
-- always did.
local function ListWord(option, value)
	if option == "add" then
		local ok, message = ns.Cooldowns.Add(value)
		ns.Print(ok and (message .. " is on the row.") or message)
		return true
	end

	if option == "drop" then
		local ok, name = ns.Cooldowns.Drop(value)
		ns.Print(ok and (name .. " is off the row.")
			or "that is not one of the ones you added, and the rest of the row"
				.. " switches off rather than coming off.")
		return true
	end

	if option == "left" or option == "right" then
		local entry = ns.Cooldowns.ByWord(value)
		if not entry then
			ns.Print("nothing on the row answers to " .. value .. ".")
		elseif ns.Cooldowns.Move(entry.key, option == "left" and -1 or 1) then
			ns.Print((entry.name or entry.key) .. " moved " .. option .. ".")
		else
			ns.Print((entry.name or entry.key) .. " is already at the " .. option
				.. " end of its line.")
		end
		return true
	end

	if option == "line" then
		local entry = ns.Cooldowns.ByWord(value)
		if not entry then
			ns.Print("nothing on the row answers to " .. value .. ".")
			return true
		end
		local top = entry.layer ~= ns.Cooldowns.ROTATION
		ns.Cooldowns.SetLine(entry.key,
			top and ns.Cooldowns.ROTATION or ns.Cooldowns.LONG)
		ns.Print((entry.name or entry.key) .. " is on the "
			.. (top and "top line, at the size of a press you are waiting for now"
				or "docked line, at the size of a press you are waiting for this fight")
			.. ".")
		return true
	end

	return false
end

-- The words the row answers to, and the two lists an unknown word is looked up
-- in before it is read as the on|off value. The lookups are in `otherwise`
-- rather than as entries because neither is a word this file knows: one is
-- whatever your class put on the row, and the other is whatever somebody
-- else's class did.
local CooldownWord = ns.Command.Word({
	name = "cooldown",
	apply = function() ns.CooldownRow.Apply() end,
	show = function()
		return "cooldown row " .. ns.Cooldowns.Describe() .. "."
	end,

	{ "idle", toggle = true, key = "cooldownIdle",
	  say = function(idle)
		return idle and "the row stays up out of combat."
			or "out of combat the row is up only while something is recovering."
	  end },

	ns.Command.Zoom("cooldownZoom", "the cooldown row draws at %dx."),

	{ "list", run = function()
		local list = ns.Cooldowns.All()
		if #list == 0 then
			ns.Print("nothing is listed for a " .. ns.Class.Spec.Says()
				.. " and no trinket answered.")
			return
		end
		-- The spec is named first, because the list is the spec's and a row that
		-- looks wrong is nearly always the addon having read you as the other
		-- tree. Saying which one it read is the difference between a bug you can
		-- report and a row you distrust.
		ns.Print(("the addon reads you as a %s."):format(ns.Class.Spec.Says()))
		for index = 1, #list do
			local entry = list[index]
			ns.Print(("  %-14s %-8s %s"):format(entry.key,
				entry.layer or ns.Cooldowns.LONG, entry.name
				or (entry.slot and "that slot holds nothing you can press"
					or "not learned on this character")))
		end
	  end },

	otherwise = function(option, value)
		if ListWord(option, value) then
			return
		end

		-- One switch per entry, driven off the list itself so the words and the
		-- tick boxes cannot drift apart.
		local entry = ns.Cooldowns.ByWord(option)
		if entry then
			ns.Cooldowns.SetWatched(entry.key, ns.Command.Toggle(value))
			ns.CooldownRow.Apply()
			ns.Print((entry.name or entry.key) .. (ns.Cooldowns.Watched(entry.key)
				and " is watched again on this character."
				or " is switched off on this character."))
			return
		end

		-- A word another class puts on the row, said as such. Without this it
		-- would fall through to the toggle below, switch the whole row off and
		-- report that it had done something else entirely.
		local elsewhere = ns.Cooldowns.Elsewhere(option)
		if elsewhere then
			ns.Print(option .. " is on the row for a " .. elsewhere .. " and nowhere"
				.. " else, so there is nothing here to switch off.")
			return
		end

		SetRow(ns.Command.Toggle(option))
		ns.Print("cooldown row " .. (ns.db.cooldowns and "on" or "off") .. ".")
	end,
})

ns.Register({
	name = "cooldowns",

	switch = {
		key = "cooldowns",
		label = "the long-cooldown row",
		apply = function(value) SetRow(value) end,
	},

	-- Straight after the buff nag, which is the other row over your character
	-- that answers what to press. The nine parts below it moved down one to make
	-- the room, because the registry takes whole numbers only.
	order = 11,

	zooms = {
		{ key = "cooldownZoom", label = "Cooldown row", fight = true, apply = function() ns.CooldownRow.Apply() end },
	},

	defaults = {
		cooldowns = true,

		-- 1, and this is the one place it differs from the buff nag, which ships
		-- at 2. That row exists to be impossible to miss and this one exists to
		-- be read: it is up for the whole fight, it carries a number per square,
		-- and a row of double sized squares over your character for three
		-- minutes at a time is in the way rather than in view.
		cooldownZoom = 1,

		-- Off, meaning the row goes away between fights once everything is
		-- ready. On for anyone who would rather always know where it is.
		cooldownIdle = false,

		-- Below the character rather than above. The buff nag owns the space
		-- over your head at 157, and this row is the one you glance at between
		-- swings, so it sits under the charge icon at -190 where the eye
		-- already is. Whole numbers, because half of an odd number is half a
		-- pixel and this frame is on the grid.
		cooldownPoint = { "CENTER", "UIParent", "CENTER", 1, -317 },
	},

	-- Which entries this character still watches, keyed by the entry's own key
	-- and holding false for each one you switched off. Absent means watched, so
	-- a fresh character carries an empty table.
	--
	-- Per character for the reason buffWatch is: whether Shield Wall is worth a
	-- square is a fact about the character rather than a preference about the
	-- row, and two warriors on one account answer it differently.
	charDefaults = {
		cooldownWatch = {},

		-- The spells you put on the row yourself, as ids. Per character for the
		-- reason above and for one more: the id you add is nearly always for the
		-- character you are on, and an alt of the same class inheriting it would
		-- get a square for a spell nobody on that character presses.
		cooldownMine = {},

		-- Which line you moved an entry to, keyed by the entry's own key, holding
		-- only the ones you moved. Absent means the line its class file gave it,
		-- so a file that changes its mind is followed rather than overridden by a
		-- setting you never knowingly wrote.
		cooldownLine = {},

		-- The row as you arranged it, as a list of keys in drawn order. A list
		-- rather than a number per entry, because the order is the fact and a set
		-- of ranks is a set of numbers somebody has to keep in step.
		cooldownOrder = {},
	},

	words = {
		cooldowns = CooldownWord,
	},

	help = {
		"cooldowns on|off, the row of long cooldowns over your character",
		"cooldowns list, what your class and your trinkets put on it",
		"cooldowns <name> on|off, one entry at a time, per character",
		"cooldowns idle on|off, zoom 1 to 3",
		"cooldowns add|drop <spell id>, a cooldown of your own",
		"cooldowns left|right|line <name>, where its square sits",
	},

	status = function()
		return ns.Cooldowns.Describe()
	end,

	lock = function()
		ns.CooldownRow.Lock()
	end,

	reset = function()
		ns.CooldownRow.Reset()
	end,

	panel = function(ui)
		ui.Section("Cooldowns", "Fighting")
		ui.Lede("Two lines, up for the whole fight. The big squares on top are the seconds the fight is made of; the small ones docked under them are the minutes.")

		ui.Reading("the row", ns.Cooldowns.Describe)

		-- Which spec the addon read you as, because everything on this row is
		-- read off it and a row that looks wrong is nearly always the addon
		-- having decided you are the other tree. It is not a setting: there is
		-- nothing to correct it with and there should not be, because the answer
		-- comes off your own spellbook and your own talent trees.
		ui.Reading("read as", function()
			return ns.Class.Spec.Says()
		end)

		ui.Check("keep it up out of combat",
			function() return ns.db.cooldownIdle end,
			function(value)
				ns.db.cooldownIdle = value
				ns.CooldownRow.Apply()
			end)
		ui.Hint("Off, the row is there in a fight and afterwards while something is still recovering. On, it never leaves.")

		ui.Zoom(function() return ns.db.cooldownZoom end,
			function(value)
				ns.db.cooldownZoom = value
				ns.CooldownRow.Apply()
			end)

		ui.Action(function() return "put the row back" end, function()
			ns.CooldownRow.Reset()
		end)
		ui.Hint("Unlock the frames to drag the row somewhere else. This puts it back where the addon ships it.")

		ui.Section("Which cooldowns", "Fighting")
		ui.Lede("The row as it will look. Drag a spell off your spellbook onto either line, drag a square from one line to the other, drag one off to stop counting it.")

		-- The row itself, and the squares that are off it. Both are drawn in
		-- Panel.lua, which is a page of this addon's own the way Hover/Panel.lua
		-- and UnitFrames/Panel.lua are: what is left here is this part's contract
		-- with Core, and a hundred and fifty lines of drag handling is not that.
		ns.CooldownPanel.Rows(ui)
		ns.CooldownPanel.Tray(ui)

		ui.TextField("or add a spell by id",
			function() return "" end,
			function(text)
				if text:match("^%s*$") then
					return
				end
				local ok, message = ns.Cooldowns.Add(text)
				ns.Print(ok and (message .. " is on the row.") or message)
				ns.Options.Refresh()
			end)
		ui.Hint("For the ones you cannot drag: a rank you have not trained, or a spell an item casts. The id is the last part of the spell's Wowhead address.")

		ui.Action(function() return "back to the row your class ships" end, function()
			ns.Cooldowns.ResetRow()
			ns.Options.Refresh()
		end)

		ui.Reading("your own", ns.Cooldowns.Own)

		ui.Section("Trinkets", "Fighting")
		ui.Lede("Both trinket slots are on the row, and only while what is in them is something you press.")

		ui.Reading("trinket 1", function()
			return ns.Cooldowns.Worn(ns.Gear.TRINKET1)
		end)
		ui.Reading("trinket 2", function()
			return ns.Cooldowns.Worn(ns.Gear.TRINKET2)
		end)
		ui.Hint("A trinket with no use effect is worn rather than pressed, so it takes no square. The client is what decides that, not a list in the addon.")
	end,
})

-- What the timing figure on the performance tab is a timing of. A row with
-- nothing on it costs one comparison; the number only means something beside a
-- count of squares.
ns.Perf.Gauge("cooldown squares on screen", function()
	return ns.CooldownRow.Shown()
end)
