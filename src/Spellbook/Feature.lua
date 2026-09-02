local ADDON, ns = ...

-- Everything Core and the panel need to know about the spell book. Read.lua,
-- Window.lua and Blizzard.lua hold the behaviour, and this is the only file
-- in the folder that names anything outside it.

local function SetSpellbook(value)
	ns.db.spellbook = value
	if value then
		ns.SpellWindow.Build()
	else
		ns.SpellWindow.Hide()
	end
	ns.BookBlizzard.Apply()
end

--------------------------------------------------------------------------
-- The slash word
--------------------------------------------------------------------------

local function SpellbookWord(arg, rawArg)
	local word, rest = arg:match("^(%S*)%s*(.-)$")

	if word == "hide" then
		ns.db.hideBlizzSpellbook = ns.Command.Toggle(rest)
		ns.BlizzHide.Apply()
		ns.Print("Blizzard's spell book is " .. ns.BookBlizzard.Describe() .. ".")
	elseif word == "ranks" then
		ns.SpellWindow.Build()
		ns.SpellWindow.Read()
		ns.Print(ns.SpellWindow.Ranks() .. ".")
	elseif word == "on" or word == "off" then
		SetSpellbook(word == "on")
		ns.Print("the spell book is " .. (ns.db.spellbook and "on" or "off") .. ".")
	elseif word == "" then
		if not ns.db.spellbook then
			ns.Print("the spell book is off. Type /wk spellbook on.")
			return
		end
		ns.SpellWindow.Toggle()
	else
		ns.Print("spellbook takes on, off, hide or ranks.")
	end
	-- rawArg is the untouched line, which this word has no use for: every
	-- sub-word above takes a switch rather than a name. Named so the signature
	-- matches every other word in the addon.
	return rawArg
end

--------------------------------------------------------------------------

ns.Register({
	name = "spellbook",
	order = 33,

	switch = {
		key = "spellbook",
		label = "the spell book",
		says = "One row per spell with every rank you know folded behind a button beside it, and the rank you pick is what the square casts and what a drag puts on a bar.",
		apply = function(value) SetSpellbook(value) end,
	},

	zooms = {
		{ key = "spellbookZoom", label = "Spell book", window = true },
	},

	defaults = {
		-- 1.3, the size every window in the addon opens at.
		spellbookZoom = 1.3,

		-- On. The client's own book lists every rank as its own entry twelve
		-- to a page, and everything this replaces it with is reversible in one
		-- press.
		spellbook = true,

		-- Blizzard's own goes in the attic, and P opens this one.
		--
		-- The switch itself is drawn on the Blizzard page with the others,
		-- because there is one place in this addon where a frame of the
		-- client's is switched off. The default lives here because a default
		-- belongs to the part that owns the frame replacing it.
		hideBlizzSpellbook = true,
	},

	charDefaults = {
		-- Which rank each square holds, by the spell's name, where it is not
		-- the best one you know. Per character because the book is: a mage's
		-- Frostbolt at rank three is one mage's choice.
		spellRanks = {},
	},

	words = {
		spellbook = SpellbookWord,
	},

	help = {
		"spellbook, open the spell book",
		"spellbook on|off, the addon's spell book instead of the client's",
		"spellbook hide on|off, put Blizzard's own book in the attic and take the P key",
		"spellbook ranks, how many squares are set below the best rank you know",
	},

	status = function()
		return ("%s; %s; Blizzard's %s"):format(
			ns.SpellWindow.Describe(), ns.SpellWindow.Ranks(), ns.BookBlizzard.Describe())
	end,

	panel = function(ui)
		ui.Section("Spell book", "Windows")
		ui.Lede("Every spell you know, one row each, on the window P opens. The button beside the rank folds out the ranks you know, and your pick is what the square holds.")
		ui.Reading("your book", ns.SpellWindow.Ranks)
		ui.Reading("Blizzard's window", ns.BookBlizzard.Describe)
	end,
})
