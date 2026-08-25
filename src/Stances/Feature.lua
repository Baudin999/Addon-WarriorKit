local ADDON, ns = ...

-- Everything Core and the panel need to know about stance dancing.
-- Stances.lua owns the three secure buttons, their macros and their bindings,
-- and talks to neither.

local function Pair(entry)
	return ns.Stances.Gear(entry.key)
end

-- What one slot draws: the icon and the text beside it. A name this character
-- is not carrying keeps its place and goes orange, the same answer the charge
-- weapon picker gives, because a weapon in the bank is set and simply will not
-- fire until it is in a bag.
local function Slot(entry, slot, field)
	return function()
		local name = Pair(entry)[field]
		if name == "" then
			return nil, "|cff707076empty|r"
		end
		local item = ns.Gear.Find(slot, name)
		if not item then
			return nil, ("|cffd08040%s|r"):format(name)
		end
		return item.icon, item.text
	end
end

local function Drop(entry, slot)
	return function(link)
		if link == nil then
			ns.Stances.SetItem(entry.key, slot, nil)
			return true
		end
		local name, why = ns.Stances.SetItem(entry.key, slot, link)
		if not name then
			ns.Print(why)
			return false
		end
		return true
	end
end

local function KeyWord(stanceKey, key)
	local displaced, why = ns.Stances.Bind(stanceKey, key)
	if not displaced then
		ns.Print(why)
	elseif key == "" then
		ns.Print(stanceKey .. " stance key cleared.")
	elseif displaced ~= "" then
		ns.Print(("%s switches to %s stance. It shadows %s, and your saved bindings are untouched.")
			:format(key, stanceKey, displaced))
	else
		ns.Print(("%s switches to %s stance. Nothing else was bound to it."):format(key, stanceKey))
	end
end

local function Page(ui, entry)
	ui.Header(entry.label)

	ui.ItemSlot("main hand",
		Slot(entry, ns.Gear.MAINHAND, "main"),
		Drop(entry, ns.Gear.MAINHAND),
		{ empty = function() return ns.Gear.Art(ns.Gear.MAINHAND) end })

	ui.ItemSlot("off hand",
		Slot(entry, ns.Gear.OFFHAND, "off"),
		Drop(entry, ns.Gear.OFFHAND),
		{
			empty = function() return ns.Gear.Art(ns.Gear.OFFHAND) end,
			-- Greyed while the main hand holds a two hander, because the off
			-- hand line is dropped from the macro in that state and a slot that
			-- looks live and does nothing is worse than one that says so.
			enabled = function() return ns.Stances.TwoHanded(entry.key) ~= true end,
		})

	ui.Note(function()
		local pair = Pair(entry)
		if ns.Stances.TwoHanded(entry.key) == true then
			return ("|cffd08040%s is a two hander, so the off hand line is left out of the macro.|r")
				:format(pair.main)
		end
		if pair.main == "" and pair.off == "" then
			return "Drag a weapon or a shield onto a slot. Right click a slot to clear it. An empty slot means leave that hand alone: there is no macro line for taking something off."
		end
		local missing = {}
		if pair.main ~= "" and not ns.Gear.Held(ns.Gear.MAINHAND, pair.main) then
			missing[#missing + 1] = pair.main
		end
		if pair.off ~= "" and not ns.Gear.Held(ns.Gear.OFFHAND, pair.off) then
			missing[#missing + 1] = pair.off
		end
		if #missing > 0 then
			return ("|cffd08040%s is not on this character, so that half of the swap does nothing until it is.|r")
				:format(table.concat(missing, " and "))
		end
		return "Drag a weapon or a shield onto a slot. Right click a slot to clear it. An empty slot means leave that hand alone."
	end)

	ui.Gap()
	ui.KeyField("key",
		function()
			local key = ns.Stances.Key(entry.key)
			if key ~= "" then
				return key
			end
			return "|cff808080not bound|r"
		end,
		function(combo)
			local ok, why = ns.Stances.Bind(entry.key, combo)
			if not ok then
				ns.Print(why)
			end
		end,
		function() ns.Stances.Bind(entry.key, "") end)

	ui.Note(function()
		local key = ns.Stances.Key(entry.key)
		if key == "" then
			return ("One press puts you in %s Stance and draws that pair. Or put /click %s in a macro on a bar.")
				:format(entry.label, entry.button)
		end
		local displaced = ns.dbc.stanceKeysDisplaced[entry.key] or ""
		if displaced ~= "" then
			return "Shadows " .. displaced .. ". Your saved bindings are untouched, so clearing this key hands it straight back."
		end
		return "Nothing else was bound to it."
	end)

	ui.Gap()
	ui.Note(function()
		local macro = ns.Stances.Macro(entry.key)
		if macro == "" then
			return "The button carries nothing yet."
		end
		return "The button carries:\n" .. macro
	end)
end

ns.Register({
	name = "stances",
	order = 4,

	-- A loadout is the gear of the character carrying it, so all of this is
	-- character scoped. Account scope here would be the layoutBackup trap
	-- again: one character's weapon names written into another's macros.
	--
	-- The three tables start empty and fill on first touch rather than carrying
	-- a stance each here, because ApplyDefaults copies a default one level deep
	-- and a table of tables would hand every character the same inner tables.
	charDefaults = {
		stanceGear = {},          -- [stance] = { main = name, off = name }
		stanceKeys = {},          -- [stance] = the key that switches to it
		stanceKeysDisplaced = {}, -- [stance] = what that key was bound to
		stanceSwapCombat = true,  -- let the swap fire mid fight, swing timer and all
	},

	words = {
		stance = function(arg)
			local which, rest = arg:match("^(%S*)%s*(.-)$")

			if which == "combat" then
				ns.dbc.stanceSwapCombat = ns.Command.Toggle(rest)
				ns.Stances.Apply()
				ns.Print("stance keys swap weapons "
					.. (ns.dbc.stanceSwapCombat and "in combat too." or "out of combat only."))
				return
			end

			local entry = ns.Stances.Entry(which)
			if not entry then
				for _, each in ipairs(ns.Stances.LIST) do
					local pair = ns.Stances.Gear(each.key)
					ns.Print(("%s: %s, %s / %s"):format(each.key, ns.Stances.Describe(each.key),
						pair.main == "" and "-" or pair.main,
						pair.off == "" and "-" or pair.off))
				end
				return
			end

			local key = rest:upper()
			if key == "NONE" then
				key = ""
			end
			KeyWord(entry.key, key)
		end,
	},

	help = {
		"stance, what each stance is bound to and what it draws",
		"stance <battle|defensive|berserker> <key|none>, the key for that stance",
		"stance combat <on|off>, whether the weapon swap fires mid fight",
	},

	status = function()
		local parts = {}
		for _, entry in ipairs(ns.Stances.LIST) do
			parts[#parts + 1] = entry.key .. " " .. ns.Stances.Describe(entry.key)
		end
		return table.concat(parts, ", ")
	end,

	panel = function(ui)
		for _, entry in ipairs(ns.Stances.LIST) do
			Page(ui, entry)
		end

		ui.Header("Swapping")
		ui.Check("swap weapons in combat too", function()
			return ns.dbc.stanceSwapCombat
		end, function(value)
			ns.dbc.stanceSwapCombat = value
			ns.Stances.Apply()
		end)
		ui.Note(function()
			if ns.dbc.stanceSwapCombat then
				return "A swap mid fight resets your swing timer, which is the price of dancing and usually worth paying. Turn this off and every /equipslot line takes a nocombat conditional, so a key pressed in a fight changes stance and leaves your hands alone."
			end
			return "Every /equipslot line carries nocombat, so a key pressed in a fight changes stance and nothing else. The weapons follow when you drop combat and press it again."
		end)

		ui.Gap()
		ui.Note(function()
			if InCombatLockdown() then
				return "|cffd08040A macro cannot be rewritten in combat, so anything changed here lands when the fight ends.|r"
			end
			return "Each key is an override binding, so it sits on top of your saved bindings rather than in them and clearing it hands the key straight back. The main hand line is written before the off hand line, which is what lets a two hander come off in time for a shield to go on."
		end)
	end,
})
