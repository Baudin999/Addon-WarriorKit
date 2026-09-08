local ADDON, ns = ...

-- Everything Core and the panel need to know about the two things targeting
-- does: the switch key, and the client's own aim token. Switch.lua owns the
-- button and the override binding, Aim.lua owns the CVar, and neither talks to
-- Core or to the panel.

local function AimWord(sub)
	local want = ns.Command.Toggle(sub)
	if want == ns.db.softAuto then
		ns.Print("action targeting is already " .. (want and "automatic" or "yours") .. ".")
		return
	end
	ns.db.softAuto = want
	if want then
		ns.Aim.Apply()
		ns.Print("action targeting is the addon's now: on out of combat, off in it.")
	else
		-- Hand the CVar back at the value it had before the addon took it,
		-- rather than leaving it wherever the last combat transition put it.
		ns.Aim.Restore()
		ns.Print("action targeting is yours again, back at what it was.")
	end
end

ns.Register({
	name = "targeting",
	order = 4,

	defaults = {
		switchKey = "TAB",       -- the key that takes the next enemy and swings at it
		-- Empty, always. What the key was bound to before this took it is a
		-- fact about the keybinding set in front of us, not a preference, and
		-- it is written the first time the bind lands.
		switchKeyDisplaced = "",
		-- Action targeting, driven off combat, on every class. It aims the
		-- approach by camera and gets out of the way once a fight is on.
		softAuto = true,
	},

	-- SoftTargetEnemy is a character scoped CVar, so what it was before the
	-- addon took it over is character scoped memory. Empty means not yet taken.
	charDefaults = {
		softPrior = "",
	},

	words = {
		switch = function(_, rawArg)
			local key = rawArg:upper()
			if key == "NONE" then
				key = ""
			end
			local displaced, why = ns.Switch.Bind(key)
			if not displaced then
				ns.Print(why)
			elseif key == "" then
				ns.Print("switch key cleared.")
			elseif displaced ~= "" then
				ns.Print(("%s takes the next enemy and swings at it. It shadows %s, and your saved bindings are untouched.")
					:format(key, displaced))
			else
				ns.Print(("%s takes the next enemy and swings at it. Nothing else was bound to it."):format(key))
			end
		end,

		aim = function(arg)
			AimWord((arg:match("^(%S*)")))
		end,
	},

	help = {
		"switch <key|none>, one key for the next enemy and the swing at it",
		"aim on|off, action targeting driven off combat",
	},

	status = function()
		return ("switch key %s, action targeting %s")
			:format(ns.Switch.Describe(), ns.Aim.Describe())
	end,

	panel = function(ui)
		ui.Section("Switch target", "Fighting")
		ui.Lede("One key takes the next enemy and starts swinging at it.")
		ui.KeyField("key",
			function()
				if ns.db.switchKey ~= "" then
					return ns.db.switchKey
				end
				return "|cff808080not bound|r"
			end,
			function(combo)
				local ok, why = ns.Switch.Bind(combo)
				if not ok then
					ns.Print(why)
				end
			end,
			function() ns.Switch.Bind("") end)
		ui.Hint("TAB is the key worth putting it on: TAB already cycles and the only thing it is missing is the attack. Or put /click WarriorKitSwitchButton in a macro.")

		ui.Reading("this key", function()
			if ns.db.switchKey == "" then
				return "not bound"
			end
			if ns.db.switchKeyDisplaced ~= "" then
				return "shadows " .. ns.db.switchKeyDisplaced
			end
			return "nothing else wanted it"
		end)

		ui.Section("Action targeting", "Fighting")
		ui.Lede("The client's own aim token, turned on out of combat and handed back the moment a fight starts.")
		ui.Check("on out of combat, off in combat",
			function() return ns.db.softAuto end,
			function(value)
				ns.db.softAuto = value
				if value then
					ns.Aim.Apply()
				else
					ns.Aim.Restore()
				end
			end)
		ui.Hint("The camera aims what you walk up to, and nothing re-aims you mid-fight. Off, the client is yours again at whatever value it had before the addon took it.")
		ui.Reading("the CVar", function() return ns.Aim.Describe() end)
	end,
})
