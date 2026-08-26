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

-- The clone, which is the other half of this part: Layout writes the slots and
-- Bars draws them. One feature rather than two, because they are one job seen
-- from two ends and a panel that split them would ask the same question twice.
local function SetBars(value)
	ns.db.actionBars = value and true or false
	local complete = ns.Bars.Apply()
	ns.Print("action bars " .. (ns.db.actionBars and "cloned" or "handed back")
		.. ": " .. ns.Bars.Describe() .. ".")
	if not complete then
		ns.Print("part of that needs combat to end first, and will run then.")
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

-- What the millisecond figure on the performance tab is per. 0.4 ms means one
-- thing at twelve squares and another at sixty. Registered from here rather
-- than from Bars.lua, because a behaviour file names nothing outside its folder.
if ns.Perf then
	ns.Perf.Gauge("bar squares on screen", function()
		return ns.Bars.Count()
	end)
end

-- Printed rather than written, because an addon cannot write its own source
-- and the plan in Buttons/Bars.lua is where a position belongs if it is to
-- survive a fresh clone. Drag it, print it, paste it, reset it.
local function Where()
	local lines = ns.Bars.Where()
	if #lines == 0 then
		ns.Print("no bars are up, so there is nothing to place. actionbars on first.")
		return
	end
	ns.Print("where the bars are, in the shape the plan in Buttons/Bars.lua wants:")
	for _, line in ipairs(lines) do
		ns.Print(line)
	end
	ns.Print("paste those over the geometry in that file, then actionbars reset.")
end

ns.Register({
	name = "buttons",
	order = 5,

	defaults = {
		-- Off, and it is the only default in this addon that is off because of
		-- what turning it on does rather than because of what it is worth. On
		-- means Blizzard's own buttons are hidden the moment you log in, and a
		-- feature that rearranges the bars of everyone who happens to update
		-- has to be asked for.
		actionBars = false,

		-- Where a bar has been dragged to, keyed by the plan's bar key. Empty
		-- is the normal state and means the plan in Buttons/Bars.lua decides,
		-- which is the one that travels with a clone of the addon. An entry
		-- here is a position you are still trying out: `actionbars where`
		-- prints it in the plan's own shape to paste in, and `actionbars reset`
		-- drops it again once you have.
		barPoints = {},
	},

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

	-- /wk unlock reaches the bars through here, the same way it reaches the
	-- charge icon and the meters. Without it the handles never show and the
	-- bars are the one part of the addon you cannot drag.
	lock = function()
		ns.Bars.ApplyLock()
	end,

	words = {
		-- Not "bars": the enemy bars part claimed that word years ago and Core
		-- asserts at login that no two features share one.
		actionbars = function(arg)
			if arg == "on" or arg == "off" then
				SetBars(ns.Command.Toggle(arg))
			elseif arg == "where" then
				Where()
			elseif arg == "reset" then
				local dropped = ns.Bars.ResetPlacing()
				ns.Print(dropped == 0 and "nothing was dragged, so the plan was already what you see."
					or ("dropped %d dragged position%s, back to the plan."):format(
						dropped, dropped == 1 and "" or "s"))
			else
				ns.Print("action bars: " .. ns.Bars.Describe() .. ".")
				ns.Print("actionbars on clones every bar you have, with its keys, and hides Blizzard's. actionbars off gives them back.")
				ns.Print("/wk unlock to drag them, actionbars where to print what you dragged, actionbars reset to undo it.")
			end
		end,

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
		"actionbars on|off, our own bars over Blizzard's, same slots and same keys",
		"actionbars where, actionbars reset, after dragging them with /wk unlock",
		"ranks, ranks refresh",
	},

	status = function()
		local ranks = ("%d slots holding an older rank"):format(#ns.Ranks.Stale())
		local bars = "bars " .. ns.Bars.Describe()
		if not ns.Layout.HasBackup() then
			return "not applied, " .. ns.Layout.Describe() .. " | " .. ranks .. " | " .. bars
		end
		return "applied, backup from " .. ns.Layout.BackupStamp()
			.. " | " .. ranks .. " | " .. bars
	end,

	-- No reset hook. /wk reset puts frames back where they started, and where
	-- the cloned bars sit is not a setting to start from: it is a table in
	-- Bars.lua. Turning the clone off is a decision, not a reset, so it stays on
	-- the switch that says so.

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
		ui.Header("Our own bars")
		ui.Note(function()
			return "Reads every action bar you have on, and stands up one of ours for each: the same action slots, the same keys, and Blizzard's buttons hidden behind it. Your keybindings are read, never written."
		end)
		ui.Check("clone my action bars",
			function() return ns.db.actionBars end,
			SetBars)
		ui.Note(function()
			if not ns.db.actionBars then
				return "Your bars are Blizzard's. Nothing is hidden and no key is taken."
			end
			return ns.Bars.Describe() .. "."
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
