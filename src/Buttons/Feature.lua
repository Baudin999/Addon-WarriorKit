local ADDON, ns = ...

-- Everything Core and the panel need to know about the loadout. Layout.lua
-- holds the behaviour and never talks to either.

local function Report(report)
	ns.Print(("filled %d slots."):format(report.placed))
	if #report.skipped > 0 then
		local seen, list = {}, {}
		for _, name in ipairs(report.skipped) do
			if not seen[name] then
				seen[name] = true
				list[#list + 1] = name
			end
		end
		ns.Print("not yet learned, left empty: " .. table.concat(list, ", ") .. ".")
	end
	if report.macroFail then
		ns.Print(("%d macros could not be created."):format(report.macroFail))
	end
	if report.note then
		ns.Print(report.note .. ".")
	end
	ns.Print("your old bars are saved. /reload now to make that backup survive a crash.")
end

local function Apply()
	local ok, result = ns.Layout.Apply()
	if not ok then
		ns.Print("cannot fill the bars: " .. result .. ".")
		return
	end
	Report(result)
	ns.Options.Refresh()
end

local function RefreshRanks()
	local ok, result = ns.Ranks.Apply()
	if not ok then
		ns.Print("cannot refresh spell ranks: " .. result .. ".")
		return
	end
	if result.moved == 0 then
		ns.Print("every spell on your bars is already the best rank you know.")
	else
		ns.Print(("moved %d slot%s up to your best rank."):format(
			result.moved, result.moved == 1 and "" or "s"))
	end
	if #result.failed > 0 then
		ns.Print("could not place: " .. table.concat(result.failed, ", ") .. ".")
	end
	ns.Options.Refresh()
end

local function Restore()
	local ok, result = ns.Layout.Restore()
	if not ok then
		ns.Print("cannot put your bars back: " .. result .. ".")
		return
	end
	ns.Print(("put back %d slots%s."):format(result.restored,
		result.failed > 0 and (", %d could not be placed"):format(result.failed) or ""))
	ns.Options.Refresh()
end

ns.Register({
	name = "buttons",
	order = 5,

	-- Per character, all three of them. These describe one character's action
	-- bars and one character's macros. Held account-wide, the first character to
	-- apply the loadout would own the only backup, the second would overwrite
	-- its bars without taking one, and restoring on the second would write the
	-- first one's bars into its slots.
	charDefaults = {
		-- What was in every slot the loadout touches, taken the first time it
		-- is applied and kept until it is put back.
		layoutBackup = {},
		layoutStamp = "",
		-- Macros this feature created, so restore deletes exactly those.
		layoutMacros = {},
	},

	words = {
		ranks = function(arg)
			if arg == "refresh" or arg == "apply" then
				RefreshRanks()
			else
				ns.Print("ranks: " .. ns.Ranks.Describe() .. ".")
				ns.Print("ranks refresh moves every bar slot up to your best rank. Macros are left alone.")
			end
		end,

		buttons = function(arg)
			if arg == "apply" or arg == "fill" then
				Apply()
			elseif arg == "restore" or arg == "undo" then
				Restore()
			else
				ns.Print("buttons: " .. ns.Layout.Describe() .. ".")
				ns.Print(ns.Layout.HasBackup()
					and ("your old bars are backed up from " .. ns.Layout.BackupStamp() .. ".")
					or "no backup held, so applying will take one first.")
				ns.Print("buttons apply fills the bars, buttons restore puts yours back.")
			end
		end,
	},

	help = {
		"buttons apply, buttons restore, buttons status",
		"ranks, ranks refresh",
	},

	status = function()
		local ranks = ("%d slots holding an older rank"):format(#ns.Ranks.Stale())
		if not ns.Layout.HasBackup() then
			return "not applied, " .. ns.Layout.Describe() .. " | " .. ranks
		end
		return "applied, backup from " .. ns.Layout.BackupStamp() .. " | " .. ranks
	end,

	panel = function(ui)
		ui.Header("Buttons")
		ui.Note(function()
			return "Fills bar 1 with a role per key in all three stances, and the shift layer above it. Your keybindings are never touched."
		end)
		ui.ActionPair(
			function() return ns.Layout.HasBackup() and "re-fill the bars" or "fill the bars" end,
			Apply,
			function() return (ns.Layout.CanApply()) end,
			function() return "put mine back" end,
			Restore,
			function() return ns.Layout.HasBackup() and (ns.Layout.CanApply()) end)
		ui.Note(function()
			local can, why = ns.Layout.CanApply()
			if not can then
				return "|cffd08040" .. why .. "|r"
			end
			if ns.Layout.HasBackup() then
				return "Your old bars are held from " .. ns.Layout.BackupStamp() .. ". " .. ns.Layout.Describe() .. "."
			end
			return ns.Layout.Describe() .. ". Nothing is overwritten until you press it."
		end)

		ui.Gap()
		ui.Header("Spell ranks")
		ui.Note(function()
			return "Walks every action slot and moves any spell holding an old rank up to the best one you know. Macros, items and empty slots are left alone."
		end)
		ui.Action(
			function()
				local count = #ns.Ranks.Stale()
				return count > 0 and ("refresh spells (%d)"):format(count) or "refresh spells"
			end,
			RefreshRanks,
			function() return (ns.Ranks.CanApply()) and #ns.Ranks.Stale() > 0 end)
		ui.Note(function()
			local can, why = ns.Ranks.CanApply()
			if not can then
				return "|cffd08040" .. why .. "|r"
			end
			return ns.Ranks.Describe() .. "."
		end)
	end,
})
