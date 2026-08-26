local ADDON, ns = ...

-- Everything Core and the panel need to know about the Edit Mode layout.
-- EditMode.lua holds the behaviour and never talks to either.

local function Save()
	local layout, why = ns.EditMode.Capture()
	if not layout then
		ns.Print("cannot read the active layout: " .. why .. ".")
		return
	end
	ns.db.uiLayout = layout
	ns.db.uiLayoutName = layout.layoutName or "?"
	ns.db.uiLayoutStamp = date("%Y-%m-%d %H:%M")
	ns.Print(("captured the %s layout."):format(ns.db.uiLayoutName))
	ns.Print("now /reload so the game writes it out, then run ./bake-ui.sh in the addon folder to bake it in.")
	ns.Options.Refresh()
end

local function Apply()
	local ok, result = ns.EditMode.Apply()
	if not ok then
		ns.Print("cannot apply the baked layout: " .. tostring(result) .. ".")
		return
	end
	local _, name = ns.EditMode.Saved()
	ns.Print(result and ("imported %s and made it active."):format(name)
		or ("%s was already here, so it is just active now."):format(name))
	ns.Options.Refresh()
end

local function Describe()
	local _, name, stamp = ns.EditMode.Saved()
	if not name then
		return "nothing is baked into the addon yet"
	end
	return ("%s is baked in%s"):format(name, stamp and (", captured " .. stamp) or "")
end

ns.Register({
	name = "interface",
	order = 12,

	defaults = {
		uiAuto = true, -- import the baked layout on a client that does not have it
		-- The staging area for ./bake-ui.sh. /wk ui save fills it, the game
		-- writes it to WTF on reload, and the script reads it from there.
		uiLayout = {},
		uiLayoutName = "",
		uiLayoutStamp = "",
	},

	words = {
		ui = function(arg)
			local option, value = arg:match("^(%S*)%s*(.-)$")
			if option == "save" or option == "capture" then
				Save()
			elseif option == "apply" or option == "import" then
				Apply()
			elseif option == "auto" then
				ns.db.uiAuto = ns.Command.Toggle(value)
				ns.Print("automatic import " .. (ns.db.uiAuto and "on" or "off") .. ".")
			else
				ns.Print("interface: " .. Describe() .. ".")
				local can, why = ns.EditMode.CanApply()
				ns.Print(can and "Edit Mode answers on this client."
					or ("Edit Mode does not answer: " .. why .. "."))
				ns.Print("ui save captures the active layout, ui apply imports the baked one.")
			end
		end,
	},

	help = {
		"ui save, ui apply, ui auto on|off",
	},

	status = function()
		local _, name = ns.EditMode.Saved()
		local can, why = ns.EditMode.CanApply()
		if not can then
			return Describe() .. ", " .. why
		end
		-- The present/absent clause is about the baked layout, so with nothing
		-- baked there is nothing for it to be about and it reads as a claim about
		-- Edit Mode itself, which had just answered fine.
		if not name then
			return ("%s, auto import %s"):format(Describe(),
				ns.db.uiAuto and "on" or "off")
		end
		return ("%s, %s on this client, auto import %s"):format(Describe(),
			ns.EditMode.IndexOf(name) and "present" or "absent",
			ns.db.uiAuto and "on" or "off")
	end,

	panel = function(ui)
		ui.Header("Interface")
		ui.Note(function()
			return "Carries one Edit Mode layout inside the addon folder, so a computer that has the addon and none of your WTF gets the same UI."
		end)
		ui.Check("import the baked layout on a client that lacks it",
			function() return ns.db.uiAuto end,
			function(value) ns.db.uiAuto = value end)
		ui.ActionPair(
			function() return "capture the active layout" end,
			Save,
			function() return (ns.EditMode.CanApply()) end,
			function() return "apply the baked layout" end,
			Apply,
			function() return ns.EditMode.Saved() ~= nil and (ns.EditMode.CanApply()) end)
		ui.Note(function()
			local can, why = ns.EditMode.CanApply()
			if not can then
				return "|cffd08040" .. why .. "|r"
			end
			local _, name = ns.EditMode.Saved()
			if not name then
				return "Nothing baked yet. Capture, /reload, then run ./bake-ui.sh in the addon folder."
			end
			return ("%s. It is %s on this client."):format(Describe(),
				ns.EditMode.IndexOf(name) and "already present" or "not here yet")
		end)
	end,
})
