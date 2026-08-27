local ADDON, ns = ...

-- Everything Core and the panel need to know about the charge button. The
-- three Charge files hold the behaviour and never talk to either.

local function ApplyChargeChange()
	ns.ChargeIcon.ApplySecure()
	ns.ChargeIcon.SyncMacro()
	ns.ChargeIcon.Update()
	ns.ChargeMarker.Update()
	ns.SoftTarget.Apply()
end

-- Every word this part answers to runs through here first. On another class
-- none of them has anything to act on: no button, no marker, and a CVar this
-- addon has deliberately left alone. Saying so once beats four settings that
-- take a value and then do nothing with it.
local function Refuse()
	if ns.IsWarrior() then
		return false
	end
	ns.Print(ns.Charge.NOT_WARRIOR .. ", so nothing here is running on this character.")
	return true
end

local function SoftWord(sub)
	local want = ns.Command.Toggle(sub)
	if want == ns.db.softAuto then
		ns.Print("action targeting is already " .. (want and "automatic" or "yours") .. ".")
		return
	end
	ns.db.softAuto = want
	if want then
		ns.SoftTarget.Apply()
		ns.Print("action targeting is the addon's now: on out of combat, off in it.")
	else
		-- Hand the CVar back at the value it had before the addon took it,
		-- rather than leaving it wherever the last combat transition put it.
		ns.SoftTarget.Restore()
		ns.Print("action targeting is yours again, back at what it was.")
	end
end

local function MarkerWord(sub, number)
	if sub == "size" then
		local size = ns.Command.Number(number, 16, 96, "charge marker size")
		if size then
			ns.db.chargeMarkerSize = size
			ns.ChargeMarker.ApplyLayout()
			ns.Print("charge marker size " .. size .. ".")
		end
	elseif sub == "offset" then
		local offset = ns.Command.Number(number, -60, 60, "charge marker offset")
		if offset then
			ns.db.chargeMarkerOffset = offset
			ns.ChargeMarker.ApplyLayout()
			ns.Print("charge marker offset " .. offset .. ".")
		end
	else
		ns.db.chargeMarker = ns.Command.Toggle(sub)
		ns.Print("charge marker " .. (ns.db.chargeMarker and "on" or "off") .. ".")
	end
end

ns.Register({
	name = "charge",
	order = 1,

	switch = {
		key = "charge",
		label = "the charge button",
		apply = function() ns.ChargeIcon.ApplySecure() end,
		-- Nothing here is built on anything but a warrior, so the row is drawn
		-- and refuses rather than being left out: a switch that vanishes on one
		-- class reads as a switch you have lost.
		available = function() return ns.IsWarrior() end,
	},

	defaults = {
		charge = true,
		chargeMode = "always", -- "always" keeps the icon on screen, "ready" only shows it when Charge can be used
		chargeMarker = true,   -- the icon in the world over the mob the Charge macro would pick
		chargeMarkerSize = 40,
		chargeMarkerOffset = 0, -- nudge the marker up or down the nameplate, -60 to 60
		-- Action targeting, driven off combat. Charge is an out of combat
		-- ability and Pick reads the cursor once combat is up, so the token
		-- earns its keep on the pull and gets in the way after it.
		softAuto = true,
		-- Empty by default. A name here builds an /equipslot line into the
		-- macro, and a weapon nobody on this account owns builds a line that
		-- silently does nothing. Set it from the Charge tab's picker, which
		-- only offers what you are carrying.
		chargeWeapon = "",
		chargeKey = "",        -- key the charge button takes over, set in the UI or with /wk bind
		chargeKeyRelease = false, -- hand the key back during combat instead of casting Intervene
		chargeKeyDisplaced = "",  -- what that key was bound to, kept so the UI can show it
		size = 44,
		point = { "CENTER", "UIParent", "CENTER", 0, -160 },
	},

	-- SoftTargetEnemy is a character scoped CVar, so what it was before the
	-- addon took it over is character scoped memory. Empty means not yet taken.
	charDefaults = {
		softPrior = "",
	},

	words = {
		charge = function(arg, rawArg)
			if Refuse() then
				return
			end
			local option, value = arg:match("^(%S*)%s*(.-)$")
			if option == "always" or option == "ready" then
				ns.db.chargeMode = option
				ns.Print("charge icon and marker show "
					.. (option == "ready" and "only when usable" or "at all times") .. ".")
			elseif option == "weapon" then
				local weapon = rawArg:match("^%S*%s*(.-)%s*$") or ""
				ns.db.chargeWeapon = (weapon == "" or weapon:lower() == "none") and "" or weapon
				ns.Print(ns.db.chargeWeapon == "" and "the charge button no longer swaps weapons."
					or ("the charge button equips " .. ns.db.chargeWeapon .. " into slot 16."))
			elseif option == "marker" then
				MarkerWord(value:match("^(%S*)%s*(.-)$"))
			elseif option == "soft" then
				SoftWord((value:match("^(%S*)")))
			else
				ns.db.charge = ns.Command.Toggle(option)
				ns.Print("charge icon " .. (ns.db.charge and "on" or "off") .. ".")
			end
			ApplyChargeChange()
		end,

		size = function(arg)
			if Refuse() then
				return
			end
			local size = ns.Command.Number(arg, 16, 128, "size")
			if size then
				ns.db.size = size
				ns.ChargeIcon.ApplyLayout()
				ns.Print("icon size " .. size .. ".")
			end
		end,

		bind = function(_, rawArg)
			if Refuse() then
				return
			end
			local key = rawArg:upper()
			if key == "NONE" then
				key = ""
			end
			local displaced, why = ns.ChargeIcon.Bind(key)
			if not displaced then
				ns.Print(why)
			elseif key == "" then
				ns.Print("charge key cleared, nothing is intercepted now.")
			elseif displaced ~= "" then
				ns.Print(("charge takes %s out of combat. %s keeps it in combat, and your saved bindings are untouched.")
					:format(key, displaced))
			else
				ns.Print(("charge takes %s out of combat. Nothing else was bound to it."):format(key))
			end
		end,
	},

	help = {
		"charge on|off, charge always|ready, charge marker on|off",
		"charge marker size <16-96>, charge marker offset <-60-60>",
		"charge soft on|off, action targeting driven off combat",
		"charge weapon <name|none>, size <16-128>, bind <key|none>",
	},

	status = function()
		if not ns.IsWarrior() then
			return "off, " .. ns.Charge.NOT_WARRIOR
		end
		return ("icon %s (%s), marker %s, key %s, action targeting %s, token %s")
			:format(ns.db.charge and "on" or "off", ns.db.chargeMode,
				ns.db.chargeMarker and "on" or "off",
				ns.db.chargeKey == "" and "unbound" or ns.db.chargeKey,
				ns.SoftTarget.Describe(),
				ns.Charge.SoftTargetState())
	end,

	lock = function()
		ns.ChargeIcon.ApplyLock()
		ns.ChargeMarker.ApplyLock()
	end,

	reset = function()
		-- A fresh table, not ns.DefaultFor: dragging mutates the anchor in place.
		ns.db.point = { "CENTER", "UIParent", "CENTER", 0, -160 }
		ns.db.size = ns.DefaultFor("size")
		ns.db.chargeMarkerSize = ns.DefaultFor("chargeMarkerSize")
		ns.db.chargeMarkerOffset = ns.DefaultFor("chargeMarkerOffset")
		ns.ChargeIcon.ApplyLayout()
		ns.ChargeMarker.ApplyLayout()
	end,

	panel = function(ui)
		-- One page saying why, rather than four tabs of controls that write a
		-- setting nothing reads. The rest of this function builds live widgets
		-- against a button and a marker that were never created on this class,
		-- and a check box you can tick that changes nothing on screen is worse
		-- than a sentence.
		if not ns.IsWarrior() then
			ui.Section("Charge", "Fighting")
			ui.Lede("Charge, Intercept and Intervene on one button, which is a warrior's three openers.")
			ui.Reading("on this character", function() return ns.Charge.NOT_WARRIOR end)
			return
		end

		ui.Section("Charge key", "Fighting")
		ui.Lede("The key that presses the charge button, taken from your bindings and handed back on clear.")
		ui.KeyField("key",
			function()
				if ns.db.chargeKey ~= "" then
					return ns.db.chargeKey
				end
				return "|cff808080not bound|r"
			end,
			function(combo)
				local ok, why = ns.ChargeIcon.Bind(combo)
				if not ok then
					ns.Print(why)
				end
			end,
			function() ns.ChargeIcon.Bind("") end)
		ui.Hint("Your saved bindings are never written, so clearing this hands the key straight back. Or put /click WarriorKitChargeButton in a macro on a bar.")
		ui.Reading("this key", function()
			if ns.db.chargeKey == "" then
				return "not bound"
			end
			if ns.db.chargeKeyDisplaced ~= "" then
				return "shadows " .. ns.db.chargeKeyDisplaced
			end
			return "nothing else wanted it"
		end)

		local release = ui.Check("hand the key back in combat",
			function() return ns.db.chargeKeyRelease end,
			function(value)
				ns.db.chargeKeyRelease = value
				ns.ChargeIcon.ApplyBinding()
			end)
		release.IsAvailable = function() return ns.ChargeIcon.CanRelease() end
		ui.Hint("Off means the key also casts Intervene and Intercept on your mouseover. A client with no state driver holds the key the whole time whatever this says.")

		ui.Section("Charge", "Fighting")
		ui.Lede("The button itself: a square over your character with the opener that fits right now on it.")
		ui.Check("only while it can be cast",
			function() return ns.db.chargeMode == "ready" end,
			function(value) ns.db.chargeMode = value and "ready" or "always" end)
		ui.Size("icon size", 16, 128, 2,
			function() return ns.db.size end,
			function(value)
				ns.db.size = value
				ns.ChargeIcon.ApplyLayout()
			end)

		ui.Section("The icon over the mob", "Fighting")
		ui.Lede("A copy of the icon out in the world, on the nameplate of whatever the macro would charge.")
		ui.Check("draw it",
			function() return ns.db.chargeMarker end,
			function(value) ns.db.chargeMarker = value end)
		ui.Size("size", 16, 96, 2,
			function() return ns.db.chargeMarkerSize end,
			function(value)
				ns.db.chargeMarkerSize = value
				ns.ChargeMarker.ApplyLayout()
			end)
		ui.Size("height", -60, 60, 2,
			function() return ns.db.chargeMarkerOffset end,
			function(value)
				ns.db.chargeMarkerOffset = value
				ns.ChargeMarker.ApplyLayout()
			end)
		ui.Hint("Height nudges the icon up or down its nameplate, for a UI where something else is already sitting there.")

		ui.Section("Action targeting", "Fighting")
		ui.Lede("The client's own aim token, turned on out of combat and handed back the moment a fight starts.")
		ui.Check("on out of combat, off in combat",
			function() return ns.db.softAuto end,
			function(value)
				ns.db.softAuto = value
				if value then
					ns.SoftTarget.Apply()
				else
					ns.SoftTarget.Restore()
				end
			end)
		ui.Hint("Charge is an out of combat ability, so the camera aims the pull and nothing re-aims you mid-fight. Off, the marker falls back to your target and your cursor.")
		ui.Reading("the CVar", function() return ns.SoftTarget.Describe() end)
		ui.Reading("the token", function()
			local state = ns.Charge.SoftTargetState()
			if state == "on" then
				return "answers on this client"
			end
			return "has not answered yet"
		end)

		ui.Section("Weapon", "Fighting")
		ui.Lede("A weapon the charge draws first, out of combat only, so a press mid-fight cannot reset your swing.")
		ui.Picker("main hand",
			function() return ns.db.chargeWeapon end,
			function(value)
				ns.db.chargeWeapon = value
				ApplyChargeChange()
			end,
			function() return ns.Gear.List(ns.Gear.MAINHAND, ns.db.chargeWeapon, "|cff909090no weapon swap|r") end)
		ui.Hint("An empty pick leaves the macro with no /equipslot line at all.")
		ui.Reading("the swap", function()
			if ns.db.chargeWeapon == "" then
				return "no weapon"
			end
			if not ns.Gear.Held(ns.Gear.MAINHAND, ns.db.chargeWeapon) then
				return ns.db.chargeWeapon .. ", not in your bags"
			end
			return ("%s into slot %d"):format(ns.db.chargeWeapon, ns.Gear.MAINHAND)
		end)
	end,
})
