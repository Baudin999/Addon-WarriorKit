local ADDON, ns = ...

-- Everything Core and the panel need to know about loadouts. Loadouts.lua owns
-- the secure buttons, their macros and their bindings, and talks to neither.

local NO_STANCE = 0 -- the picker's value for "no stance", since nil is not one

local function Shown()
	return ns.Loadouts.Shown()
end

local function Current()
	return ns.Loadouts.Get(Shown())
end

-- What one slot draws: the icon and the text beside it. A name this character
-- is not carrying keeps its place and goes orange, the same answer the charge
-- weapon picker gives, because a weapon in the bank is set and simply will not
-- fire until it is in a bag.
local function Slot(slot, field)
	return function()
		local loadout = Current()
		if not loadout then
			return nil, ""
		end
		local name = loadout[field]
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

local function Drop(slot)
	return function(link)
		local index = Shown()
		if index == 0 then
			return false
		end
		if link == nil then
			ns.Loadouts.SetItem(index, slot, nil)
			return true
		end
		local name, why = ns.Loadouts.SetItem(index, slot, link)
		if not name then
			ns.Print(why)
			return false
		end
		return true
	end
end

local function BindWord(index, key)
	local loadout = ns.Loadouts.Get(index)
	local displaced, why = ns.Loadouts.Bind(index, key)
	if not displaced then
		ns.Print(why)
	elseif key == "" then
		ns.Print(loadout.name .. " is unbound.")
	elseif displaced ~= "" then
		ns.Print(("%s switches to %s. It shadows %s, and your saved bindings are untouched.")
			:format(key, loadout.name, displaced))
	else
		ns.Print(("%s switches to %s. Nothing else was bound to it."):format(key, loadout.name))
	end
end

--------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------

local function Page(ui)
	ui.Section("Loadouts", "Fighting")
	ui.Lede("A named pair of weapons and a stance, on one key. Drag a weapon onto a hand.")

	ui.Paperdoll({
		slots = {
			{
				label = "main hand",
				get = Slot(ns.Gear.MAINHAND, "main"),
				set = Drop(ns.Gear.MAINHAND),
				empty = function() return ns.Gear.Art(ns.Gear.MAINHAND) end,
			},
			{
				label = "off hand",
				get = Slot(ns.Gear.OFFHAND, "off"),
				set = Drop(ns.Gear.OFFHAND),
				empty = function() return ns.Gear.Art(ns.Gear.OFFHAND) end,
				-- Greyed while the main hand holds a two hander, because the off
				-- hand line is dropped from the macro in that state and a slot
				-- that looks live and does nothing is worse than one that says so.
				enabled = function() return ns.Loadouts.TwoHanded(Shown()) ~= true end,
			},
		},
	})

	-- The strip under the character, the way the client's own sheet puts its
	-- tabs under the paperdoll. The three stances are rows in it like anything
	-- else, and + adds one.
	ui.Tabs(
		function()
			local labels = {}
			for index, loadout in ipairs(ns.Loadouts.All()) do
				labels[index] = loadout.name
			end
			return labels
		end,
		Shown,
		function(index) ns.Loadouts.Show(index) end,
		{
			onAdd = function()
				local index, why = ns.Loadouts.Add()
				if not index then
					ns.Print(why)
				end
			end,
		})

	ui.Hint("Right click a hand to clear it. An empty hand means leave it alone: there is no macro line for taking something off.")

	ui.Reading("this pair", function()
		local loadout = Current()
		if not loadout then
			return "none yet, press +"
		end
		if ns.Loadouts.TwoHanded(Shown()) == true then
			return loadout.main .. " is a two hander, no off hand line"
		end
		local missing = {}
		if loadout.main ~= "" and not ns.Gear.Held(ns.Gear.MAINHAND, loadout.main) then
			missing[#missing + 1] = loadout.main
		end
		if loadout.off ~= "" and not ns.Gear.Held(ns.Gear.OFFHAND, loadout.off) then
			missing[#missing + 1] = loadout.off
		end
		if #missing > 0 then
			return table.concat(missing, " and ") .. ": not on this character"
		end
		return "ready"
	end)

	ui.Gap()

	ui.TextField("name",
		function()
			local loadout = Current()
			return loadout and loadout.name or ""
		end,
		function(value) ns.Loadouts.Rename(Shown(), value) end)

	ui.Picker("stance",
		function()
			local loadout = Current()
			return (loadout and loadout.stance) or NO_STANCE
		end,
		function(value)
			ns.Loadouts.SetStance(Shown(), value ~= NO_STANCE and value or nil)
		end,
		function()
			local list = { { value = NO_STANCE, text = "|cff909090no stance change|r" } }
			for index = 1, ns.Stance.COUNT do
				list[index + 1] = {
					value = index,
					text = ns.Stance.Name(index) or ("stance " .. index),
				}
			end
			return list
		end)

	ui.KeyField("key",
		function()
			local loadout = Current()
			if loadout and loadout.key ~= "" then
				return loadout.key
			end
			return "|cff808080not bound|r"
		end,
		function(combo)
			local ok, why = ns.Loadouts.Bind(Shown(), combo)
			if not ok then
				ns.Print(why)
			end
		end,
		function() ns.Loadouts.Bind(Shown(), "") end)
	ui.Hint("Your saved bindings are untouched, so clearing this key hands it straight back. Or put the button's /click line in a macro on a bar.")

	ui.Reading("this key", function()
		local loadout = Current()
		if not loadout or loadout.key == "" then
			return "not bound"
		end
		if loadout.displaced ~= "" then
			return "shadows " .. loadout.displaced
		end
		return "nothing else wanted it"
	end)

	ui.Reading("the button carries", function()
		local macro = ns.Loadouts.Macro(Shown())
		if macro == "" then
			return "nothing yet"
		end
		return (macro:gsub("%s*\n%s*", " "))
	end)

	ui.Gap()
	ui.Action(
		function()
			local loadout = Current()
			return loadout and ("delete " .. loadout.name) or "delete"
		end,
		function() ns.Loadouts.Remove(Shown()) end,
		function() return Current() ~= nil end)
end

ns.Register({
	name = "loadouts",
	order = 4,

	-- A loadout is the gear of the character carrying it, so all of this is
	-- character scoped. Account scope here would be the layoutBackup trap
	-- again: one character's weapon names written into another's macros.
	--
	-- The list starts empty and is seeded on first read rather than carrying
	-- three loadouts here, because ApplyDefaults copies a default one level
	-- deep and a list of tables would hand every character the same rows.
	charDefaults = {
		loadouts = {},             -- { name, stance, main, off, key, displaced }
		loadoutsSeeded = false,    -- the three stances are made once, not every login
		loadoutShown = 1,          -- which one the panel is showing
		loadoutSwapCombat = true,  -- let the swap fire mid fight, swing timer and all
	},

	words = {
		loadout = function(arg, rawArg)
			local which, rest = arg:match("^(%S*)%s*(.-)$")

			if which == "combat" then
				ns.dbc.loadoutSwapCombat = ns.Command.Toggle(rest)
				ns.Loadouts.Apply()
				ns.Print("loadout keys swap weapons "
					.. (ns.dbc.loadoutSwapCombat and "in combat too." or "out of combat only."))
				return
			end

			if which == "add" then
				local name = rawArg:match("^%S*%s*(.-)%s*$")
				local index, why = ns.Loadouts.Add(name)
				ns.Print(index and ("added " .. ns.Loadouts.Get(index).name .. ".") or why)
				return
			end

			local index = tonumber(which)
			if not index or not ns.Loadouts.Get(index) then
				for at, loadout in ipairs(ns.Loadouts.All()) do
					ns.Print(("%d %s: %s, %s / %s"):format(at, loadout.name,
						ns.Loadouts.Describe(at),
						loadout.main == "" and "-" or loadout.main,
						loadout.off == "" and "-" or loadout.off))
				end
				return
			end

			local key = rest:upper()
			if key == "NONE" then
				key = ""
			end
			BindWord(index, key)
		end,
	},

	help = {
		"loadout, every loadout, its key and the pair it draws",
		"loadout <number> <key|none>, the key for that loadout",
		"loadout add <name>, a new one",
		"loadout combat <on|off>, whether the weapon swap fires mid fight",
	},

	status = function()
		local parts = {}
		for index, loadout in ipairs(ns.Loadouts.All()) do
			parts[#parts + 1] = loadout.name .. " " .. ns.Loadouts.Describe(index)
		end
		if #parts == 0 then
			return "none"
		end
		return table.concat(parts, ", ")
	end,

	panel = function(ui)
		Page(ui)

		ui.Section("Swapping", "Fighting")
		ui.Lede("Whether a loadout key changes your weapons mid fight or waits until the fight is over.")
		ui.Check("swap weapons in combat too", function()
			return ns.dbc.loadoutSwapCombat
		end, function(value)
			ns.dbc.loadoutSwapCombat = value
			ns.Loadouts.Apply()
		end)
		ui.Hint("A swap mid fight resets your swing timer, which is the price of dancing. Off, every /equipslot line takes a nocombat conditional and the stance still changes.")

		ui.Reading("the macros", function()
			if InCombatLockdown() then
				return "held: a macro cannot be rewritten in combat"
			end
			return ("%d loadouts is the cap, one secure button each"):format(ns.Loadouts.MAX)
		end)
	end,
})
