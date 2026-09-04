local ADDON, ns = ...

-- Everything Core and the panel need to know about the talent window.
-- Read.lua, Cost.lua, Board.lua, Window.lua and Blizzard.lua hold the
-- behaviour, and this is the only file in the folder that names anything
-- outside it.

local function SetTalents(value)
	ns.db.talents = value
	if value then
		ns.TalentWindow.Build()
	else
		ns.TalentWindow.Hide()
	end
	ns.TalentBlizzard.Apply()
end

--------------------------------------------------------------------------
-- The slash word
--------------------------------------------------------------------------

local function TalentWord(arg, rawArg)
	local word, rest = arg:match("^(%S*)%s*(.-)$")

	if word == "hide" then
		ns.db.hideBlizzTalents = ns.Command.Toggle(rest)
		ns.BlizzHide.Apply()
		ns.Print("Blizzard's talent window is " .. ns.TalentBlizzard.Describe() .. ".")
	elseif word == "trees" then
		ns.Print(ns.TalentWindow.Trees() .. ".")
	elseif word == "cost" then
		ns.Print(ns.TalentCost.Describe() .. ".")
	elseif word == "on" or word == "off" then
		SetTalents(word == "on")
		ns.Print("the talent window is " .. (ns.db.talents and "on" or "off") .. ".")
	elseif word == "" then
		if not ns.db.talents then
			ns.Print("the talent window is off. Type /wk talents on.")
			return
		end
		ns.TalentWindow.Toggle()
	else
		ns.Print("talents takes on, off, hide, trees or cost.")
	end
	-- rawArg is the untouched line, which this word has no use for: every
	-- sub-word above takes a switch rather than a name. Named so the signature
	-- matches every other word in the addon.
	return rawArg
end

--------------------------------------------------------------------------

ns.Register({
	name = "talents",
	order = 33,

	switch = {
		key = "talents",
		label = "the talent window",
		says = "Three trees side by side, nothing to scroll, and what unlearning costs along the foot.",
		apply = function(value) SetTalents(value) end,
	},

	zooms = {
		{ key = "talentsZoom", label = "Talent window", window = true },
	},

	defaults = {
		-- 1.3, the size every window in the addon opens at. The window is sized
		-- to the tallest tree at that zoom and the screen height doubles it
		-- where a panel is tall enough to need it.
		talentsZoom = 1.3,

		-- On. The client's own frame shows one tree behind three tabs and hides
		-- the last tiers of the wider ones under a scroll bar, and everything
		-- this replaces it with is reversible in one press.
		talents = true,

		-- Blizzard's own is never loaded, and N opens this one.
		--
		-- The switch itself is drawn on the Blizzard page with the others,
		-- because there is one place in this addon where a frame of the
		-- client's is switched off. The default lives here because a default
		-- belongs to the part that owns the frame replacing it.
		hideBlizzTalents = true,
	},

	charDefaults = {
		-- The trainer's last quote for unlearning everything, in copper, and
		-- the moment it was given. Written when the client's own dialog goes up
		-- and read back on the foot of the window. Per character because the
		-- price is: Talents/Cost.lua carries the argument.
		respecQuote = false,
		respecQuoteAt = false,
		-- How many times this character has paid to unlearn, which is what the
		-- schedule's estimate is read off. A record rather than a preference,
		-- so it stays out of the reset.
		respecCount = 0,
	},

	words = {
		talents = TalentWord,
	},

	help = {
		"talents, open the talent window",
		"talents on|off, the addon's talent window instead of the client's",
		"talents hide on|off, keep Blizzard's own from loading and take the N key",
		"talents trees, how many points are in each of your three trees",
		"talents cost, what your trainer last quoted to unlearn them, and what the schedule says",
	},

	status = function()
		return ("%s; %s; Blizzard's %s"):format(
			ns.TalentWindow.Describe(), ns.TalentWindow.Trees(), ns.TalentBlizzard.Describe())
	end,

	panel = function(ui)
		ui.Section("Talents", "Windows")
		ui.Lede("Your three trees side by side, every talent on the screen at once, on the window N opens.")
		ui.Reading("your trees", ns.TalentWindow.Trees)
		ui.Reading("points to spend", function()
			return tostring(ns.TalentRead.Unspent(select(2, ns.TalentRead.Groups())))
		end)
		ui.Reading("unlearning", ns.TalentCost.Brief)
		ui.Reading("Blizzard's window", ns.TalentBlizzard.Describe)
	end,
})
