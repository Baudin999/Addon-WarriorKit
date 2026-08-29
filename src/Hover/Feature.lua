local ADDON, ns = ...

-- Everything Core and the panel need to know about mouseover casting.
-- Hover.lua holds the model, Cast.lua owns the button and the keys, Sheet.lua
-- draws the list over the world, Panel.lua draws the page, and none of them
-- names anything outside this folder.
--
-- Not gated on class and not gated on anything else. A binding is a key and a
-- spell name, and every class has both.

local function ListWord()
	local list = ns.Hover.List()
	if #list == 0 then
		ns.Print("nothing is bound. Drop a spell on the slot in /wk and press a key.")
		return
	end
	for index, bind in ipairs(list) do
		ns.Print(("  %-12s %s"):format(
			ns.HoverCast.Holding(index) and bind.key or (bind.key .. " *"),
			ns.HoverCast.Macro(index) or ns.Hover.Macro(bind)))
	end
	ns.Print("* is a key this client did not take.")
end

local function RemoveWord(value)
	local key = value:upper()
	for index, bind in ipairs(ns.Hover.List()) do
		if bind.key == key then
			ns.Print(ns.Hover.Remove(index) .. " is no longer on " .. key .. ".")
			return
		end
	end
	ns.Print(("nothing is bound to %s."):format(key ~= "" and key or "that"))
end

local function HoverWord(arg)
	local option, value = arg:match("^(%S*)%s*(.-)$")

	if option == "" or option == "show" then
		ListWord()
		return
	end

	if option == "remove" then
		RemoveWord(value)
		return
	end

	if option == "clear" then
		ns.Print(("%d keys cleared."):format(ns.Hover.Clear()))
		return
	end

	if option == "list" then
		ns.db.hoverSheet = ns.Command.Toggle(value)
		ns.HoverSheet.Rebuild()
		ns.Print("the list on screen is " .. (ns.db.hoverSheet and "up" or "off") .. ".")
		return
	end

	if option == "target" then
		ns.db.hoverFallback = ns.Command.Toggle(value)
		ns.Hover.Changed()
		ns.Print(ns.db.hoverFallback
			and "a key with nothing under the cursor falls back to your target."
			or "a key with nothing under the cursor does nothing.")
		return
	end

	ns.db.hover = ns.Command.Toggle(option)
	ns.Hover.Changed()
	ns.Print("mouseover casting " .. (ns.db.hover and "on" or "off") .. ".")
end

ns.Register({
	name = "hover",

	switch = {
		key = "hover",
		label = "casting on what the mouse is over",
		apply = function() ns.Hover.Changed() end,
	},

	-- Straight after marking, which is the other part built on a modified key
	-- and the thing under the cursor. The seventeen parts below it moved down
	-- one to make the room, because the registry takes whole numbers only.
	order = 3,

	defaults = {
		hover = true,

		-- Enemy first, because the picker offers it first and because a warrior
		-- binds the enemy key before anything else. It is only the value a new
		-- binding is made with; every binding keeps its own.
		hoverWho = "enemy",

		-- Off. A key that quietly hits your target when you meant to hover
		-- something is worse than a key that does nothing, and the list on
		-- screen has no way to draw the difference.
		hoverFallback = false,

		hoverSheet = true,
		-- Clear of the middle of the screen and clear of the cooldown row at
		-- 200 and the buff nag under it. To the right, because the left of the
		-- screen is where the party blocks are.
		hoverSheetPoint = { "CENTER", "UIParent", "CENTER", 320, 0 },
		hoverSheetZoom = 1,
		-- Dark enough to read a name against grass and light enough not to be a
		-- panel. It is a caption, not a window.
		hoverSheetAlpha = 55,
	},

	-- Per character, because a binding names a spell and a spell is something
	-- one character knows. A druid's Rejuvenation key written account-wide is a
	-- key that casts nothing at all on the warrior next door, and the list on
	-- screen would still be showing it.
	charDefaults = {
		hoverBinds = {},
	},

	words = {
		hover = HoverWord,
	},

	help = {
		"hover on|off, a key casts on whatever the mouse is over",
		"hover show, every key and the macro it presses",
		"hover remove <key>, hover clear",
		"hover list on|off, the list drawn over the world",
		"hover target on|off, fall back to your target when hovering nothing",
	},

	status = function()
		return ns.Hover.Describe()
	end,

	lock = function()
		ns.HoverSheet.Lock()
	end,

	reset = function()
		ns.HoverSheet.Reset()
	end,

	panel = function(ui)
		ns.HoverPanel.Build(ui)
	end,
})
