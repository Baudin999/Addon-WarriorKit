local ADDON, ns = ...

-- Everything Core and the panel need to know about the charge button. The
-- three Charge files hold the behaviour and never talk to either.

-- Both displays now skip a pass where nothing they read has moved, and a
-- setting is not something they read. chargeMode decides whether the square is
-- drawn at all and the switch that writes it is right here, so both are told to
-- forget what they last drew before either is asked to draw again.
local function ApplyChargeChange()
	ns.ChargeIcon.ApplySecure()
	ns.ChargeIcon.SyncMacro()
	ns.ChargeIcon.Forget()
	ns.ChargeMarker.Forget()
	ns.ChargeIcon.Update()
	ns.ChargeMarker.Update()
end

-- Every word this part answers to runs through here first. On another class
-- none of them has anything to act on: no button and no marker. Saying so once
-- beats four settings that take a value and then do nothing with it.
local function Refuse()
	if ns.Charge.Available() then
		return false
	end
	ns.Print(ns.Charge.Refusal() .. ", so nothing here is running on this character.")
	return true
end

local MarkerWord = ns.Command.Word({
	name = "charge marker",
	apply = function() ns.ChargeMarker.ApplyLayout() end,

	{ "size", number = { 16, 96 }, key = "chargeMarkerSize",
	  say = function(size)
		return "charge marker size " .. size .. "."
	  end },

	{ "offset", number = { -60, 60 }, key = "chargeMarkerOffset",
	  say = function(offset)
		return "charge marker offset " .. offset .. "."
	  end },

	-- No layout: the marker is drawn or not, and its geometry has not moved.
	otherwise = { toggle = true, key = "chargeMarker", apply = false,
	  say = function(on)
		return "charge marker " .. (on and "on" or "off") .. "."
	  end },
})

local ChargeWord = ns.Command.Word({
	name = "charge",
	finally = function() ApplyChargeChange() end,

	{ "always", run = function()
		ns.db.chargeMode = "always"
		ns.Print("charge icon and marker show at all times.")
	  end },

	{ "ready", run = function()
		ns.db.chargeMode = "ready"
		ns.Print("charge icon and marker show only when usable.")
	  end },

	-- Off the raw line rather than the lowered one, because a weapon is named
	-- the way it is engraved and the client matches it that way.
	{ "weapon", run = function(_, rawValue)
		local weapon = rawValue or ""
		ns.db.chargeWeapon = (weapon == "" or weapon:lower() == "none") and "" or weapon
		ns.Print(ns.db.chargeWeapon == "" and "the charge button no longer swaps weapons."
			or ("the charge button equips " .. ns.db.chargeWeapon .. " into slot 16."))
	  end },

	{ "marker", run = function(value) MarkerWord(value) end },

	otherwise = { toggle = true, key = "charge",
	  say = function(on)
		return "charge icon " .. (on and "on" or "off") .. "."
	  end },
})

ns.Register({
	name = "charge",
	order = 1,

	switch = {
		key = "charge",
		label = "the charge button",
		apply = function() ns.ChargeIcon.ApplySecure() end,
		-- Nothing here is built on a class whose file names no charge
		-- abilities, so the row is left out rather than drawn and refusing.
		-- It used to refuse, on the argument that a switch which vanishes
		-- reads as a switch you have lost. What it points at is the argument
		-- that won: there is no page in the rail to be a shortcut to and no
		-- lede to sit under, so the row would be a switch pointing at nothing
		-- with no sentence saying why. BuildStart in Core\Panel.lua drops it.
		available = function() return ns.Charge.Available() end,
	},

	defaults = {
		charge = true,
		chargeMode = "always", -- "always" keeps the icon on screen, "ready" only shows it when Charge can be used
		chargeMarker = true,   -- the icon in the world over the mob the Charge macro would pick
		chargeMarkerSize = 30,
		chargeMarkerOffset = 10, -- nudge the marker up or down the nameplate, -60 to 60
		-- A name here builds an /equipslot line into the macro, and a weapon
		-- nobody on this account owns builds a line that silently does
		-- nothing, which is what a fresh character gets and what it costs.
		-- Set it from the Charge tab's picker, which only offers what you are
		-- carrying.
		chargeWeapon = "Whirlwind Axe",
		chargeKey = "CTRL-2",  -- key the charge button takes over, set in the UI or with /wk bind
		chargeKeyRelease = false, -- hand the key back during combat instead of casting Intervene
		-- Empty, always. This is what the key was bound to before the button
		-- took it, which is a fact about the keybinding set in front of us and
		-- not a preference. It is written the first time the bind lands.
		chargeKeyDisplaced = "",
		size = 52,
		point = { "CENTER", "UIParent", "CENTER", 3, -190 },
	},

	words = {
		charge = function(arg, rawArg)
			if Refuse() then
				return
			end
			ChargeWord(arg, rawArg)
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
		"charge weapon <name|none>, size <16-128>, bind <key|none>",
	},

	status = function()
		if not ns.Charge.Available() then
			return "off, " .. ns.Charge.Refusal()
		end
		return ("icon %s (%s), marker %s, key %s, token %s")
			:format(ns.db.charge and "on" or "off", ns.db.chargeMode,
				ns.db.chargeMarker and "on" or "off",
				ns.db.chargeKey == "" and "unbound" or ns.db.chargeKey,
				ns.Charge.SoftTargetState())
	end,

	lock = function()
		ns.ChargeIcon.ApplyLock()
		ns.ChargeMarker.ApplyLock()
	end,

	reset = function()
		ns.db.point = ns.DefaultCopy("point")
		ns.db.size = ns.DefaultCopy("size")
		ns.db.chargeMarkerSize = ns.DefaultCopy("chargeMarkerSize")
		ns.db.chargeMarkerOffset = ns.DefaultCopy("chargeMarkerOffset")
		ns.ChargeIcon.ApplyLayout()
		ns.ChargeMarker.ApplyLayout()
	end,

	panel = function(ui)
		-- No page at all on a class the button was not built for, rather than
		-- tabs of controls that write a setting nothing reads. The rest of this
		-- function builds live widgets
		-- against a button and a marker that were never created on this class,
		-- and a check box you can tick that changes nothing on screen is worse
		-- than nothing at all. The part keeps its slash words, which say why, and
		-- its line in /wk status, which says the same.
		if not ns.Charge.Available() then
			return
		end

		ui.Section("Charge key", ns.Options.CLASS)
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

		ui.Section("Charge", ns.Options.CLASS)
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

		ui.Section("The icon over the mob", ns.Options.CLASS)
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
		ui.Hint("Height nudges the icon up or down its nameplate, for a UI where something else is already sitting there. Which mob it sits on is action targeting's, under Fighting.")
		ui.Reading("the token", function()
			local state = ns.Charge.SoftTargetState()
			if state == "on" then
				return "answers on this client"
			end
			return "has not answered yet"
		end)

		ui.Section("Weapon", ns.Options.CLASS)
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
