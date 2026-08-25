local ADDON, ns = ...

-- Everything Core and the panel need to know about marking. Marking.lua holds
-- the behaviour and the list of marks, Keys.lua owns the override bindings;
-- neither talks to Core or the panel.

local function KeyText(id)
	local key = ns.db.markBinds[id]
	if key and key ~= "" then
		return key
	end
	return "|cff808080not bound|r"
end

ns.Register({
	name = "marking",
	order = 1,

	defaults = {
		marking = true,
		-- One key per mark, empty meaning unbound. Skull and cross take the two
		-- ctrl combinations because they are the two you place under pressure.
		-- Moon takes alt rather than a third ctrl combination, because
		-- CTRL-ALT-BUTTON1 is a chord and the point of these is that they are
		-- faster than opening a menu.
		markBinds = {
			skull = "CTRL-BUTTON1",
			cross = "CTRL-SHIFT-BUTTON1",
			moon = "ALT-BUTTON1",
		},
		targetMark = true, -- the fallback: mark what you target while holding ctrl, when no key is held
	},

	words = {
		mark = function(arg)
			ns.db.marking = ns.Command.Toggle(arg)
			ns.MarkKeys.Apply()
			ns.Print("marking " .. (ns.db.marking and "on" or "off") .. ".")
		end,

		-- /wk markkey skull CTRL-BUTTON1, /wk markkey moon none
		markkey = function(_, rawArg)
			local id, key = rawArg:match("^%s*(%S+)%s+(%S+)%s*$")
			id = id and id:lower()
			if not id or not ns.db.markBinds[id] then
				local names = {}
				for _, mark in ipairs(ns.Marking.MARKS) do
					names[#names + 1] = mark.id
				end
				ns.Print(("markkey takes %s and a key, or none."):format(table.concat(names, ", ")))
				return
			end

			key = key:upper()
			if key == "NONE" then
				key = ""
			end

			local ok, why = ns.MarkKeys.Bind(id, key)
			if not ok then
				ns.Print(why)
			elseif key == "" then
				ns.Print(("%s is no longer bound."):format(id))
			else
				ns.Print(("%s marks on %s."):format(id, key))
			end
		end,

		targetmark = function(arg)
			ns.db.targetMark = ns.Command.Toggle(arg)
			ns.Print("ctrl-targeting marks " .. (ns.db.targetMark and "on" or "off") .. ".")
		end,
	},

	help = {
		"mark on|off, markkey <skull|cross|moon> <key|none>, targetmark on|off",
	},

	status = function()
		return ("%s, %s, ctrl-target %s")
			:format(ns.db.marking and "on" or "off",
				ns.MarkKeys.Describe(),
				ns.db.targetMark and "on" or "off")
	end,

	panel = function(ui)
		ui.Header("Marking")
		ui.Check("mark by clicking with a modifier held",
			function() return ns.db.marking end,
			function(value)
				ns.db.marking = value
				ns.MarkKeys.Apply()
			end)

		for _, mark in ipairs(ns.Marking.MARKS) do
			local id = mark.id
			ui.KeyField(mark.label,
				function() return KeyText(id) end,
				function(combo)
					local ok, why = ns.MarkKeys.Bind(id, combo)
					if not ok then
						ns.Print(why)
					end
				end,
				function() ns.MarkKeys.Bind(id, "") end)
		end

		ui.Note(function()
			return "Click the field and press the combination you want, mouse buttons included. A modified left click is the one worth having: it marks whatever is under the cursor out in the world, on a nameplate and on a unit frame, all the same way. Plain left and right click are refused, because they belong to targeting and the camera."
		end)

		ui.Gap()
		ui.Check("fall back to ctrl-targeting",
			function() return ns.db.targetMark end,
			function(value) ns.db.targetMark = value end)
		ui.Note(function()
			if ns.MarkKeys.Active() then
				return "Not in use: the keys above are doing the job. This only runs on a client that refuses them."
			end
			return "No marking key is held, so out in the world ctrl to target marks skull and ctrl-shift marks cross."
		end)
	end,
})
