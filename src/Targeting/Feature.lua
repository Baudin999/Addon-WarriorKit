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
		ns.Print("action targeting is the addon's now: the camera picks the enemy and the enemy it picks is your target.")
	else
		-- Hand both CVars back at the values they had before the addon took
		-- them, rather than leaving them wherever this file last put them.
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
		-- Action targeting: the camera picks the enemy and the enemy it picks
		-- becomes your target. On every class, and held whether or not you are
		-- in a fight, because the client's own MatchLocked is what stops the
		-- camera choosing again once you hold something.
		softAuto = true,
	},

	-- Both CVars Aim.lua owns are character scoped, so what they held before
	-- the addon took them is character scoped memory too. Keyed by CVar name,
	-- and a name absent from it is one not taken yet. It was a bare string
	-- while there was one CVar; softPrior is retired in Core/Core.lua.
	charDefaults = {
		aimPrior = {},
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
		"aim on|off, the camera picks the enemy and it becomes your target",
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
		ui.Lede("The camera picks the enemy in front of you, and the enemy it picks becomes the one you are targeting.")
		ui.Check("aim with the camera, and take what it finds",
			function() return ns.db.softAuto end,
			function(value)
				ns.db.softAuto = value
				if value then
					ns.Aim.Apply()
				else
					ns.Aim.Restore()
				end
			end)
		ui.Hint("Two settings and both are needed: one aims, the other makes what it aimed at your target. Aiming alone casts at a mob you never selected. Holding a target stops the camera choosing again.")
		ui.Reading("the client", function() return ns.Aim.Describe() end)
	end,
})
