local ADDON, ns = ...

-- Everything Core and the panel need to know about the switch key. Switch.lua
-- owns the button and the override binding and talks to neither.

ns.Register({
	name = "targeting",
	order = 3,

	defaults = {
		switchKey = "",          -- the key that takes the next enemy and swings at it
		switchKeyDisplaced = "", -- what that key was bound to, kept so the UI can show it
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
		ui.Header("Switch target")
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

		ui.Note(function()
			if ns.db.switchKey == "" then
				return "One press takes the next enemy and starts swinging at it. TAB is the key worth putting it on, because TAB already cycles and the only thing it is missing is the attack. Or put /click WarriorKitSwitchButton in a macro on a bar."
			end
			if ns.db.switchKeyDisplaced ~= "" then
				return "Shadows " .. ns.db.switchKeyDisplaced .. ". Your saved bindings are untouched, so clearing this key hands it straight back."
			end
			return "Nothing else was bound to it."
		end)
	end,
})
