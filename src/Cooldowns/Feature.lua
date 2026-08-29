local ADDON, ns = ...

-- Everything Core and the panel need to know about the cooldown row.
-- Cooldowns.lua says what is on it, Row.lua draws it, and neither of them names
-- anything outside this folder.
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

local function CooldownWord(arg)
	local option, value = arg:match("^(%S*)%s*(.-)$")

	if option == "" or option == "show" then
		ns.Print("cooldown row " .. ns.Cooldowns.Describe() .. ".")
		return
	end

	if option == "idle" then
		ns.db.cooldownIdle = ns.Command.Toggle(value)
		ns.CooldownRow.Apply()
		ns.Print(ns.db.cooldownIdle and "the row stays up out of combat."
			or "out of combat the row is up only while something is recovering.")
		return
	end

	if option == "zoom" then
		local zoom = ns.Command.Number(value, ns.UI.ZOOM_LOW, ns.UI.ZOOM_HIGH, "cooldown zoom")
		if zoom then
			ns.db.cooldownZoom = zoom
			ns.CooldownRow.Apply()
			ns.Print(("the cooldown row draws at %dx."):format(zoom))
		end
		return
	end

	if option == "list" then
		local list = ns.Cooldowns.All()
		if #list == 0 then
			ns.Print("nothing is listed for a " .. ns.Class.Label() .. " and no trinket answered.")
			return
		end
		for index = 1, #list do
			local entry = list[index]
			ns.Print(("  %-14s %s"):format(entry.key, entry.name
				or (entry.slot and "that slot holds nothing you can press"
					or "not learned on this character")))
		end
		return
	end

	-- One switch per entry, driven off the list itself so the words and the tick
	-- boxes cannot drift apart. Last of the named words and ahead of the bare
	-- on|off, because an unknown word has to reach the toggle the way it always
	-- did.
	local entry = ns.Cooldowns.ByWord(option)
	if entry then
		ns.Cooldowns.SetWatched(entry.key, ns.Command.Toggle(value))
		ns.CooldownRow.Apply()
		ns.Print((entry.name or entry.key) .. (ns.Cooldowns.Watched(entry.key)
			and " is watched again on this character."
			or " is switched off on this character."))
		return
	end

	-- A word another class puts on the row, said as such. Without this it would
	-- fall through to the toggle below, switch the whole row off and report that
	-- it had done something else entirely.
	local elsewhere = ns.Cooldowns.Elsewhere(option)
	if elsewhere then
		ns.Print(option .. " is on the row for a " .. elsewhere .. " and nowhere"
			.. " else, so there is nothing here to switch off.")
		return
	end

	SetRow(ns.Command.Toggle(option))
	ns.Print("cooldown row " .. (ns.db.cooldowns and "on" or "off") .. ".")
end

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

		-- Above the buff nag at 140 and clear of the charge icon at -160 and the
		-- swing bars at -220. Whole numbers, because half of an odd number is
		-- half a pixel and this frame is on the grid.
		cooldownPoint = { "CENTER", "UIParent", "CENTER", 0, 200 },
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
	},

	words = {
		cooldowns = CooldownWord,
	},

	help = {
		"cooldowns on|off, the row of long cooldowns over your character",
		"cooldowns list, what your class and your trinkets put on it",
		"cooldowns <name> on|off, one entry at a time, per character",
		"cooldowns idle on|off, zoom 1 to 3",
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
		ui.Section("Long cooldowns", "You")
		ui.Lede("A square per cooldown worth counting, up for the whole fight, with what is left of each one on it.")

		ui.Reading("the row", ns.Cooldowns.Describe)

		ui.Check("keep it up out of combat",
			function() return ns.db.cooldownIdle end,
			function(value)
				ns.db.cooldownIdle = value
				ns.CooldownRow.Apply()
			end)
		ui.Hint("Off, the row is there in a fight and afterwards while something is still recovering. On, it never leaves.")

		ui.Section("Which cooldowns", "You")
		ui.Lede("One switch per entry. Switched off is not watched, not drawn, not counted.")

		-- Built from the live list rather than from literals here, so an entry
		-- added to a class file arrives with its switch already on the page. The
		-- list is already this character's: Cooldowns.All merges in your class's
		-- entries and nobody else's, so a tick box that writes a setting nothing
		-- on this character reads cannot be drawn.
		local list = ns.Cooldowns.All()
		for index = 1, #list do
			local entry = list[index]
			ui.Check(entry.name or entry.key,
				function() return ns.Cooldowns.Watched(entry.key) end,
				function(value)
					ns.Cooldowns.SetWatched(entry.key, value)
					ns.CooldownRow.Apply()
				end)
		end
		ui.Hint("These are per character, because whether a cooldown is worth a square is a tank's answer and not the same warrior's levelling answer. Everything else here is the account's.")

		ui.Reading("switched off", function()
			local silent, names = ns.Cooldowns.Silent()
			return silent == 0 and "nothing, the row is watching all of it" or names
		end)

		ui.Section("Trinkets", "You")
		ui.Lede("Both trinket slots are on the row, and only while what is in them is something you press.")

		ui.Reading("trinket 1", function()
			return ns.Cooldowns.Worn(ns.Gear.TRINKET1)
		end)
		ui.Reading("trinket 2", function()
			return ns.Cooldowns.Worn(ns.Gear.TRINKET2)
		end)
		ui.Hint("A trinket with no use effect is worn rather than pressed, so it takes no square. The client is what decides that, not a list in the addon.")

		ui.Section("Where the row sits", "You")
		ui.Lede("Where the row sits and how big it is drawn. Unlock the frames to drag it.")

		ui.Zoom(function() return ns.db.cooldownZoom end,
			function(value)
				ns.db.cooldownZoom = value
				ns.CooldownRow.Apply()
			end)

		ui.Action(function() return "put the row back" end, function()
			ns.CooldownRow.Reset()
		end)
	end,
})

-- What the timing figure on the performance tab is a timing of. A row with
-- nothing on it costs one comparison; the number only means something beside a
-- count of squares.
ns.Perf.Gauge("cooldown squares on screen", function()
	return ns.CooldownRow.Shown()
end)
