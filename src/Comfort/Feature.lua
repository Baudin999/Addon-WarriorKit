local ADDON, ns = ...

-- Everything Core and the panel need to know about the chores. Loot.lua,
-- Vendor.lua, Repair.lua, Camera.lua, Errors.lua, Clutter.lua and Destroy.lua
-- hold the behaviour and none of them names anything outside this folder.
--
-- Settings that have nothing to do with each other sharing one part, because
-- the alternative is a rail entry carrying one tick box each. The panel already
-- has a second level: an ui.Header opens a tab, so the part is one entry in the
-- rail with a tab per chore.
--
-- Clutter is the odd one and has no setting at all. It is a window you open, it
-- runs nothing in the background, and the tab exists to explain it and to open
-- it. A thing that destroys items does not get to happen while you are not
-- looking.
--
-- No reset. The registry's reset means "put this part's frames back where they
-- started" and this part has no frames, so registering one would make /wk reset,
-- which is what you type when a window has wandered off screen, quietly turn
-- selling back on for someone who had deliberately turned it off.

local function SetLoot(value)
	ns.db.fastLoot = value
	ns.Loot.Apply()
end

local function SetVendor(value)
	ns.db.sellTrash = value
	ns.Vendor.Apply()
end

local function SetRepair(value)
	ns.db.autoRepair = value
	ns.Repair.Apply()
end

local function SetZoom(value)
	ns.db.maxZoom = value
	ns.Camera.Apply()
end

local function SetErrors(value)
	ns.db.errorFilter = value
	ns.Errors.Apply()
end

-- One row of the muted-message list: a tick box and the message it silences.
-- Built once at login and shown only while the list is that long, the same
-- shape the debuff list on the enemy bars has and for the same reason. The
-- panel is built once and the list is not.
--
-- The rows are the whole interface to the filter. There is no field to type a
-- message into, because a message you typed is a message that does not match:
-- the client's wording is the client's, and the only reliable way to name one
-- is to have seen it come past. Errors.Rows() puts what you have muted at the
-- top and what has come past this session under it.
local function ErrorRow(ui, slot)
	local M, C = ns.UI.Metric, ns.UI.Color
	local row, tick, label

	local function Entry()
		return ns.Errors.Rows()[slot]
	end

	ui.Custom(function(frame)
		row = frame

		local button = CreateFrame("Button", nil, frame)
		button:SetAllPoints()

		local box = ns.UI.Box(button, C.sunken, C.edge)
		box:SetSize(M.check, M.check)
		box:SetPoint("TOPLEFT", 0, -math.floor((M.control - M.check) / 2))
		tick = ns.Fill(box, "ARTWORK", C.tick[1], C.tick[2], C.tick[3], 1)
		tick:SetPoint("TOPLEFT", 3, -3)
		tick:SetPoint("BOTTOMRIGHT", -3, 3)

		label = ns.UI.Label(button, M.font, C.text, "LEFT", ns.UI.FLAT)
		ns.UI.Wrap(label, true)
		label:SetSpacing(2)
		label:SetPoint("TOPLEFT", box, "TOPRIGHT", M.gutter, 0)
		label:SetPoint("RIGHT", button, "RIGHT", 0, 0)

		button:SetScript("OnClick", function()
			local entry = Entry()
			if not entry then
				return
			end
			if ns.Errors.Muted(entry.key) then
				ns.Errors.Unmute(entry.key)
			else
				ns.Errors.Mute(entry.key, entry.text)
			end
			ns.Options.Refresh()
		end)
		button:SetScript("OnEnter", function()
			label:SetTextColor(1, 1, 1)
		end)
		button:SetScript("OnLeave", function()
			label:SetTextColor(C.text[1], C.text[2], C.text[3])
		end)

		-- An unused slot is not a short row, it is no row. Ten of them left at
		-- a control's height would put a hand's width of air under the list.
		return function(cell)
			local used = Entry() ~= nil
			cell.gap = used and M.rowGap or 0
			if not used then
				return 0
			end
			return math.max(M.control, ns.UI.TextHeight(label, M.check))
		end
	end, { height = M.control, refresh = function()
		local entry = Entry()
		row:SetShown(entry ~= nil)
		if entry then
			tick:SetShown(ns.Errors.Muted(entry.key))
			label:SetText(entry.text)
		end
	end })
end

ns.Register({
	name = "comfort",
	order = 16,

	defaults = {
		-- All four on. Every one of them is a thing you would otherwise do by
		-- hand every few minutes, so off is not a state anyone would choose to
		-- start in, and the part exists because doing them by hand is the
		-- complaint.
		fastLoot = true,
		sellTrash = true,
		autoRepair = true,
		maxZoom = true,

		-- On, and it mutes nothing, because the list beside it ships empty.
		-- The switch decides whether the list is consulted; the list decides
		-- what goes. Shipping the switch off would mean a list you had ticked
		-- and a screen that still shouted at you until you found a second
		-- setting.
		errorFilter = true,

		-- Account-wide on purpose. Which errors you can live without is a fact
		-- about you and not about the character you are standing in, and this
		-- is the setting that would be most annoying to make twice. Keyed by
		-- the name of the global holding the message, valued by the text it
		-- had when you ticked it, which is only what the panel prints.
		errorMuted = {},
	},

	words = {
		loot = function(arg)
			SetLoot(ns.Command.Toggle(arg))
			ns.Print("fast loot " .. ns.Loot.Describe() .. ".")
		end,

		sell = function(arg)
			SetVendor(ns.Command.Toggle(arg))
			ns.Print("selling trash " .. ns.Vendor.Describe() .. ".")
		end,

		-- No argument repairs now, on the merchant already in front of you.
		-- An on or an off sets the setting instead. Selling has no such word
		-- because a sweep already runs itself the moment the window opens and
		-- there is nothing a press would add; a repair you are refused is worth
		-- asking for on purpose, because the refusal is the answer.
		repair = function(arg)
			if arg == "on" or arg == "off" then
				SetRepair(arg == "on")
				ns.Print("auto repair " .. ns.Repair.Describe() .. ".")
				return
			end
			local cost, why = ns.Repair.Run()
			if not cost then
				ns.Print(why .. ".")
			elseif cost == 0 then
				ns.Print("nothing on you is damaged.")
			else
				ns.Print(("repaired for %s, %s."):format(GetCoinText(cost),
					why == "guild" and "on the guild" or "out of your own purse"))
			end
		end,

		zoom = function(arg)
			SetZoom(ns.Command.Toggle(arg))
			ns.Print("camera " .. ns.Camera.Describe() .. ".")
		end,

		-- One word with four answers, the way `ui` already works. `list` and
		-- `clear` are here because a list you cannot read from chat is a list
		-- you have to open a window to audit, and `charge` is the one press
		-- worth having without the window.
		errors = function(arg)
			if arg == "list" then
				local rows = ns.Errors.Rows()
				if #rows == 0 then
					ns.Print("no errors muted and none seen yet this session.")
					return
				end
				for _, entry in ipairs(rows) do
					ns.Print(("  %s %s"):format(
						ns.Errors.Muted(entry.key) and "muted  " or "heard  ", entry.text))
				end
				return
			end
			if arg == "clear" then
				ns.Print(("%d unmuted, every error reaches the screen again.")
					:format(ns.Errors.Clear()))
				return
			end
			if arg == "charge" then
				ns.Print(("%d positional messages muted, %s.")
					:format(ns.Errors.SilencePositional(), ns.Errors.Describe()))
				return
			end
			SetErrors(ns.Command.Toggle(arg))
			ns.Print("error filter " .. ns.Errors.Describe() .. ".")
		end,

		-- No on and off. It opens a window, and a window is the only place this
		-- one is allowed to do anything.
		destroy = function()
			ns.Destroy.Show()
		end,
	},

	help = {
		"loot on|off, empty a corpse in one go",
		"sell on|off, grey items at every merchant",
		"repair, pay the merchant in front of you now",
		"repair on|off, pay every merchant who mends, guild funds first",
		"zoom on|off, how far the camera pulls back",
		"errors on|off, filter the red text through your muted list",
		"errors list|clear, what is muted and what has come past, or empty it",
		"errors charge, mute what a missed charge shouts at you",
		"destroy, review quest items you are finished with, one at a time",
	},

	status = function()
		return ("loot %s; vendor %s; repair %s; camera %s; errors %s; clutter %s")
			:format(ns.Loot.Describe(), ns.Vendor.Describe(), ns.Repair.Describe(),
				ns.Camera.Describe(), ns.Errors.Describe(), ns.Destroy.Describe())
	end,

	panel = function(ui)
		ui.Section("Loot", "Chores")
		ui.Lede("Empties a corpse the moment the server says what is on it, so the loot window never draws.")
		ui.Check("empty a corpse in one go",
			function() return ns.db.fastLoot end,
			SetLoot)
		ui.Hint("Only when auto loot is what your click asked for, so a shift-click still opens the window. Under master loot only the slots below the threshold are taken.")
		ui.Reading("looting", ns.Loot.Describe)

		ui.Section("Vendor", "Chores")
		ui.Lede("Sells your grey items at every merchant you open, and nothing else.")
		ui.Check("sell grey items at every merchant",
			function() return ns.db.sellTrash end,
			SetVendor)
		ui.Hint("Hold shift as you open a merchant to skip it for that one visit. An item this client has not cached yet is left alone rather than sold on a guess.")
		ui.Reading("selling", ns.Vendor.Describe)

		ui.Section("Repair", "Chores")
		ui.Lede("Mends every damaged piece the moment a merchant who can mend opens.")
		ui.Check("repair at every merchant who will",
			function() return ns.db.autoRepair end,
			SetRepair)
		ui.Hint("Guild funds first, as far as your rank's withdraw allowance goes, then your purse. A purse that cannot cover it is left alone rather than half spent.")
		ui.Action(function()
			local cost = ns.Repair.Cost()
			if cost == nil then
				return "open a merchant who repairs"
			end
			if cost == 0 then
				return "nothing is damaged"
			end
			return "repair now for " .. GetCoinText(cost)
		end,
			function()
				local cost, why = ns.Repair.Run()
				if not cost then
					ns.Print(why .. ".")
				elseif cost > 0 then
					ns.Print(("repaired for %s, %s."):format(GetCoinText(cost),
						why == "guild" and "on the guild" or "out of your own purse"))
				end
			end,
			function() return (ns.Repair.Cost() or 0) > 0 end)
		ui.Reading("repairing", ns.Repair.Describe)
		ui.Reading("worst piece", function()
			local worst, counted = ns.Repair.Durability()
			if not worst then
				return "this client is not quoting durability"
			end
			return ("%d%% of %d that wear"):format(worst, counted)
		end)

		ui.Section("Clutter", "The screen")
		ui.Lede("A window for the finished quest items that sit in your bags and cannot be sold.")
		ui.Action(function() return "review them one at a time" end,
			function() ns.Destroy.Show() end,
			function() return ns.Clutter.Ready() end)
		ui.Hint("One card at a time, the quest written on it, a destroy and a skip. Read the card first: a repeatable quest never flags as completed, so its turn-in reads as finished with.")
		ui.Reading("Questie", function()
			return ns.Clutter.Ready() and "answering" or "not answering, so the window stays empty"
		end)

		ui.Section("Camera", "The screen")
		ui.Lede("Pulls the camera further back than the client's own options slider will go.")
		ui.Check("pull the camera back further",
			function() return ns.db.maxZoom end,
			SetZoom)
		ui.Hint("This is the client's own cameraDistanceMaxZoomFactor rather than a frame, so it survives a logout and is written again at every entry to the world.")
		ui.Reading("camera", ns.Camera.Describe)

		ui.Section("Errors", "The screen")
		ui.Lede("Drops the red messages you have ticked before they reach the middle of the screen.")
		ui.Check("filter the red text in the middle of the screen",
			function() return ns.db.errorFilter end,
			SetErrors)
		ui.Hint("Nothing is hidden that you have not ticked, and the sound and the flash are untouched, so a refusal you did not mute still reads exactly as it did.")
		ui.ActionPair(
			function() return "mute a missed charge" end, function()
				ns.Errors.SilencePositional()
				ns.Options.Refresh()
			end, function() return true end,
			function()
				local count = ns.Errors.Count()
				return count > 0 and ("unmute all %d"):format(count) or "nothing muted"
			end, function()
				ns.Errors.Clear()
				ns.Options.Refresh()
			end, function() return ns.Errors.Count() > 0 end)
		ui.Hint("The left button mutes what a positional ability shouts when it misses: too far, facing the wrong way, out of range. It is the only preset here.")

		for slot = 1, ns.Errors.RowLimit() do
			ErrorRow(ui, slot)
		end

		ui.Reading("filtering", function()
			if not ns.Errors.Installed() then
				return "this client has no UIErrorsFrame to stand in front of"
			end
			return ns.Errors.Describe()
		end)
		ui.Reading("the list", function()
			local rows = ns.Errors.Rows()
			if #rows == 0 then
				return "nothing has come past yet"
			end
			return ("%d muted of %d listed"):format(ns.Errors.Count(), #rows)
		end)
	end,
})
