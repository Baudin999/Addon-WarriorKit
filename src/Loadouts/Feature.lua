local ADDON, ns = ...

-- Everything Core needs to know about loadouts. Loadouts.lua owns the secure
-- buttons, their macros and their bindings, Page.lua draws the page, and the
-- character window is what hosts it. This file is the registration and the
-- slash word, and it draws nothing.
--
-- There is no `panel` here any more. The loadout page was a section of the
-- options window, between the chat opacity and the minimap shape, and it is a
-- tab of the character window now: a loadout is your gear on a key, so it
-- belongs on the page with your gear on it.

-- What `/wk loadout <n> <key>` says back. Three sentences rather than one,
-- because the interesting case is the middle one: a key this addon takes is a
-- key something else was using, and saying which is what stops somebody
-- wondering all evening why their jump is gone.
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
		ns.Print(("%s switches to %s. Nothing else wanted it."):format(key, loadout.name))
	end
end

ns.Register({
	name = "loadouts",
	order = 5,

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
})
