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
		return
	end

	if ListWord(option, value) then
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

-- One row of the list: the tick that watches an entry, its picture and name,
-- the two buttons that walk it along its line, the one that sends it to the
-- other line, and, for one you added yourself, the one that takes it off.
--
-- ui.Custom is the seam, the same one UnitFrames\Panel.lua uses for the debuff
-- list and for the same reason: UI\Widgets.lua has no list widget and should
-- not grow one for two callers. What it has is a bare row of the width the page
-- is laying out, which measures itself, and an unused slot measures to nothing.
--
-- One row per square the row could ever draw, built once at login, because the
-- panel is built once and the list is not: a row that appears when you add a
-- spell has to already exist. `indexed` is whether there was an entry in this
-- slot when the page was built, and it decides whether the row is put in the
-- search index: a row for a spell nobody has added yet has no name to be found
-- by.
local function EntryRow(ui, slot, indexed)
	local M = ns.UI.Metric
	local stepWidth, lineWidth, dropWidth = 34, 58, 20
	local row, box, art, name, line, drop

	local function Entry()
		return ns.Cooldowns.All()[slot]
	end

	-- Every button on the row acts on whatever entry is in this slot at the
	-- moment it is pressed and then puts the page back in step, so what each one
	-- is handed is the act and nothing else. A slot with nothing in it does
	-- nothing rather than raising, which is the state every row below the end of
	-- the list is in.
	local function Does(act)
		return function()
			local entry = Entry()
			if entry then
				act(entry)
				ns.Options.Refresh()
			end
		end
	end

	ui.Custom(function(frame)
		row = frame

		box = ns.UI.TickBox(frame)
		box:SetPoint("TOPLEFT", 0, -math.floor((M.control - M.check) / 2))
		local toggle = CreateFrame("Button", nil, frame)
		toggle:SetAllPoints(box)
		toggle:SetScript("OnClick", Does(function(entry)
			ns.Cooldowns.SetWatched(entry.key, not ns.Cooldowns.Watched(entry.key))
			ns.CooldownRow.Apply()
		end))

		drop = ns.UI.Button(frame, { label = "x", glyph = true, width = dropWidth,
			onClick = Does(function(entry)
				ns.Cooldowns.Drop(entry.spells and entry.spells[1])
			end) })
		drop:SetPoint("TOPRIGHT")

		line = ns.UI.Button(frame, { width = lineWidth,
			onClick = Does(function(entry)
				ns.Cooldowns.SetLine(entry.key,
					entry.layer == ns.Cooldowns.ROTATION and ns.Cooldowns.LONG
						or ns.Cooldowns.ROTATION)
			end) })
		line:SetPoint("TOPRIGHT", drop, "TOPLEFT", -M.rowGap, 0)

		local right = ns.UI.Button(frame, { label = "right", width = stepWidth,
			onClick = Does(function(entry) ns.Cooldowns.Move(entry.key, 1) end) })
		right:SetPoint("TOPRIGHT", line, "TOPLEFT", -M.rowGap, 0)

		local left = ns.UI.Button(frame, { label = "left", width = stepWidth,
			onClick = Does(function(entry) ns.Cooldowns.Move(entry.key, -1) end) })
		left:SetPoint("TOPRIGHT", right, "TOPLEFT", -M.rowGap, 0)

		art = ns.UI.Icon(frame, "ARTWORK")
		art:SetSize(M.control, M.control)
		art:SetPoint("TOPLEFT", M.check + M.gutter, 0)

		name = ns.UI.Label(frame, M.font, ns.UI.Color.text, "LEFT", ns.UI.FLAT)
		name:SetPoint("LEFT", art, "RIGHT", M.gutter, 0)
		name:SetPoint("RIGHT", left, "LEFT", -M.gutter, 0)

		-- An empty slot is not a short row, it is no row: zero height and no gap
		-- under it, or the six squares nobody has claimed would leave a hand's
		-- width of air between the list and the controls below it.
		return function(cell)
			local used = Entry() ~= nil
			cell.gap = used and M.rowGap or 0
			return used and M.control or 0
		end
	end, {
		height = M.control,
		label = indexed and function()
			local entry = Entry()
			return entry and (entry.name or entry.key) or "a square on the cooldown row"
		end or nil,
		refresh = function()
			local entry = Entry()
			row:SetShown(entry ~= nil)
			if not entry then
				return
			end
			box.tick:SetShown(ns.Cooldowns.Watched(entry.key))
			art:SetTexture(entry.texture)
			art:SetShown(entry.texture ~= nil)
			name:SetText(entry.name or entry.key)
			line.text:SetText(entry.layer == ns.Cooldowns.ROTATION
				and "to docked" or "to top")
			drop:SetShown(ns.Cooldowns.IsMine(entry.key))
		end,
	})
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
		ui.Section("Cooldowns", "You")
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

		ui.Section("Which cooldowns", "You")
		ui.Lede("One row per square, in the order the row draws them: the tick watches it, left and right walk it along its line, the next button swaps lines.")

		-- Built off the live list rather than off literals here, so an entry added
		-- to a class file arrives with its row already on the page. The list is
		-- already this character's: Cooldowns.All merges in your class's entries
		-- and nobody else's, so a control that writes a setting nothing on this
		-- character reads cannot be drawn.
		--
		-- Every slot, not every entry, because the ones past the end of the list
		-- today are the ones the picker below fills in.
		local list = ns.Cooldowns.All()
		for slot = 1, ns.Cooldowns.Ceiling() do
			EntryRow(ui, slot, slot <= #list)
		end
		ui.Hint("All of this is per character: whether a cooldown is worth a square, and where the square goes, is a tank's answer and not the same warrior's levelling answer.")

		ui.Picker("add one your class knows",
			function() return "pick one" end,
			function(spellID)
				if type(spellID) ~= "number" then
					return
				end
				local ok, message = ns.Cooldowns.Add(spellID)
				if not ok then
					ns.Print(message)
				end
				ns.Options.Refresh()
			end,
			function()
				local options = {}
				for _, spellID in ipairs(ns.Cooldowns.Suggestions()) do
					options[#options + 1] = { value = spellID, text = ns.SpellName(spellID),
						icon = ns.SpellTexture(spellID) }
				end
				if #options == 0 then
					options[1] = { text = "your class lists nothing this row is missing" }
				end
				return options
			end)
		ui.Hint("What your class lists for any of its specs, that you have learned, and that the row is not already counting.")

		ui.TextField("or add any spell by id",
			function() return "" end,
			function(text)
				if text:match("^%s*$") then
					return
				end
				local ok, message = ns.Cooldowns.Add(text)
				ns.Print(ok and (message .. " is on the row.") or message)
				ns.Options.Refresh()
			end)
		ui.Hint("The id is the last part of the spell's Wowhead address, and it is the spell you press rather than anything it applies.")

		ui.Action(function() return "back to the row your class ships" end, function()
			ns.Cooldowns.ResetRow()
			ns.Options.Refresh()
		end)

		ui.Reading("your own", ns.Cooldowns.Own)
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
