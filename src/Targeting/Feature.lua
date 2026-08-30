local ADDON, ns = ...

-- Everything Core and the panel need to know about the switch key. Switch.lua
-- owns the button and the override binding and talks to neither.

ns.Register({
	name = "targeting",
	order = 4,

	defaults = {
		switchKey = "TAB",       -- the key that takes the next enemy and swings at it
		-- Empty, always. What the key was bound to before this took it is a
		-- fact about the keybinding set in front of us, not a preference, and
		-- it is written the first time the bind lands.
		switchKeyDisplaced = "",
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
	},

	help = {
		"switch <key|none>, one key for the next enemy and the swing at it",
	},

	status = function()
		return "switch key " .. ns.Switch.Describe()
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
	end,
})
