local ADDON, ns = ...

-- Everything Core and the panel need to know about the chores. Loot.lua,
-- Vendor.lua, Repair.lua, Camera.lua, Clutter.lua and Destroy.lua hold the
-- behaviour and none of them names anything outside this folder.
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

ns.Register({
	name = "comfort",
	order = 9,

	defaults = {
		-- All four on. Every one of them is a thing you would otherwise do by
		-- hand every few minutes, so off is not a state anyone would choose to
		-- start in, and the part exists because doing them by hand is the
		-- complaint.
		fastLoot = true,
		sellTrash = true,
		autoRepair = true,
		maxZoom = true,
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
		"destroy, review quest items you are finished with, one at a time",
	},

	status = function()
		return ("loot %s; vendor %s; repair %s; camera %s; clutter %s")
			:format(ns.Loot.Describe(), ns.Vendor.Describe(), ns.Repair.Describe(),
				ns.Camera.Describe(), ns.Destroy.Describe())
	end,

	panel = function(ui)
		ui.Header("Loot")
		ui.Check("empty a corpse in one go",
			function() return ns.db.fastLoot end,
			SetLoot)
		ui.Note(function()
			if not ns.db.fastLoot then
				return "The client opens the loot window and takes one slot per frame, which is where the pause over each corpse comes from."
			end
			return "The corpse is emptied the moment the server says what is on it, so the loot window never draws. It only runs when auto loot is what your click asked for, so a shift-click to open the window still opens it."
		end)
		ui.Note(function()
			return "Under master loot only the slots below the threshold are taken. Everything at or above it is the master looter's to assign, and taking one of those yourself is not something an addon should do quietly."
		end)

		ui.Header("Vendor")
		ui.Check("sell grey items at every merchant",
			function() return ns.db.sellTrash end,
			SetVendor)
		ui.Note(function()
			if not ns.db.sellTrash then
				return "Greys stay in your bags."
			end
			return "Grey quality only, and only what a vendor will pay something for. Hold shift as you open a merchant to skip it for that one visit."
		end)
		ui.Note(function()
			if not ns.db.sellTrash then
				return "Nothing is sold while this is off, and a sale already in flight stops the moment you turn it off."
			end
			return "An item this client has not cached yet is left alone rather than sold on a guess, and the sweep asks again a fifth of a second later."
		end)

		ui.Header("Repair")
		ui.Check("repair at every merchant who will",
			function() return ns.db.autoRepair end,
			SetRepair)
		ui.Note(function()
			if not ns.db.autoRepair then
				return "Nothing is repaired for you. Your gear wears down until you press the anvil yourself, and a weapon at zero durability does no damage at all."
			end
			return "Every damaged piece at once, the moment the window opens, on any merchant the client says can mend. Hold shift as you open him to skip it for that one visit."
		end)
		ui.Note(function()
			if not ns.db.autoRepair then
				return "Repair " .. ns.Repair.Describe() .. "."
			end
			return "Guild funds first, and only as far as your rank's own withdraw allowance goes. Past that, or with no guild bank on this client, it comes out of your purse, and a purse that cannot cover it is left alone rather than half spent."
		end)
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
		ui.Note(function()
			local worst, counted = ns.Repair.Durability()
			if not worst then
				return "This client is not quoting durability, so there is no wear to report. The merchant's own price is what the repair is decided on either way."
			end
			return ("Worst piece at %d%% across %d that wear."):format(worst, counted)
		end)

		ui.Header("Camera")
		ui.Check("pull the camera back further",
			function() return ns.db.maxZoom end,
			SetZoom)
		ui.Note(function()
			return "Camera " .. ns.Camera.Describe() .. "."
		end)
		ui.Note(function()
			return "This is the client's own cameraDistanceMaxZoomFactor, not a frame this addon draws, so it survives a logout and it is written again at every entry to the world in case something else put it back."
		end)

		ui.Header("Clutter")
		ui.Note(function()
			return "Quest items for quests you have finished sit in your bags forever. Most of them cannot be sold, so a vendor is no help and the only way out is to destroy them."
		end)
		ui.Action(function() return "review them one at a time" end,
			function() ns.Destroy.Show() end,
			function() return ns.Clutter.Ready() end)
		ui.Note(function()
			if not ns.Clutter.Ready() then
				return "Questie is not answering. The client will tell you an item is a quest item and will not tell you which quest, so without Questie's database there is nothing to trace and the window stays empty."
			end
			return "One card at a time, with the quest it came from written on it, and a destroy and a skip. Nothing is destroyed without a press, nothing runs in the background, and an item that starts a quest you have not done is never offered at all."
		end)
		ui.Note(function()
			return "Read the card before you press. Repeatable quests never flag as completed, so their turn-in items read as finished with when they are not, and a chain can drop part three's item while you are still on part one."
		end)
	end,
})
