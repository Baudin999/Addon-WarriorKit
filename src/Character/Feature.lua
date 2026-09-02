local ADDON, ns = ...

-- Everything Core and the panel need to know about the character sheet.
-- Worn.lua, Stats.lua, Skills.lua, Reputation.lua, Readout.lua, Paperdoll.lua,
-- Window.lua and Blizzard.lua hold the behaviour, and this is the only file in
-- the folder that names anything outside it.

local function SetCharacter(value)
	ns.db.character = value
	if value then
		ns.CharWindow.Build()
	else
		ns.CharWindow.Hide()
	end
	ns.CharBlizzard.Apply()
end

--------------------------------------------------------------------------
-- The slash word
--------------------------------------------------------------------------

local function CharacterWord(arg, rawArg)
	local word, rest = arg:match("^(%S*)%s*(.-)$")

	if word == "hide" then
		ns.db.hideBlizzCharacter = ns.Command.Toggle(rest)
		ns.BlizzHide.Apply()
		ns.Print("Blizzard's character sheet is " .. ns.CharBlizzard.Describe() .. ".")
	elseif word == "stats" then
		ns.Print(ns.CharStats.Describe() .. ".")
	elseif word == "skills" then
		ns.Print(ns.CharSkills.Describe() .. ".")
	elseif word == "gear" then
		ns.Print(ns.Worn.Describe() .. ".")
	elseif word == "trace" then
		ns.CharTrace.Set(ns.Command.Toggle(rest))
		ns.Print("the gear trace is " .. ns.CharTrace.Describe() .. ".")
	elseif word == "on" or word == "off" then
		SetCharacter(word == "on")
		ns.Print("the character sheet is " .. (ns.db.character and "on" or "off") .. ".")
	elseif word == "" then
		if not ns.db.character then
			ns.Print("the character sheet is off. Type /wk character on.")
			return
		end
		ns.CharWindow.Toggle()
	else
		ns.Print("character takes on, off, hide, gear, stats, skills or trace.")
	end
	-- rawArg is the untouched line, which this word has no use for: every
	-- sub-word above takes a switch rather than a name. Named so the signature
	-- matches every other word in the addon.
	return rawArg
end

--------------------------------------------------------------------------

ns.Register({
	name = "character",
	order = 26,

	switch = {
		key = "character",
		label = "the character sheet",
		says = "Loadouts are a tab on it, so turning this off leaves them to /wk loadout. Whether Blizzard's own sheet is hidden is on the Blizzard's own frames page with the other nine.",
		apply = function(value) SetCharacter(value) end,
	},

	zooms = {
		{ key = "characterZoom", label = "Character sheet", window = true },
	},

	defaults = {
		-- 1.3, and it was 1.25 when every window in the addon shared one number.
		-- A tenth is the step now and 1.25 is not on one, so a default that
		-- stayed there would be a value the page cannot reach and the reset
		-- cannot restore. A window at 1 is a window you lean in to read on the
		-- panel most people are playing on, and the screen height already
		-- doubles this where a panel is tall enough to need it.
		characterZoom = 1.3,

		-- On. The client's own sheet spends its largest area on a picture of
		-- your back and answers none of the three questions anybody opens it
		-- for, and everything this replaces it with is reversible in one press.
		character = true,

		-- Blizzard's own goes in the attic, and C opens this one.
		--
		-- The switch itself is drawn on the Blizzard page with the other nine,
		-- because there is one place in this addon where a frame of the
		-- client's is switched off. The default lives here because a default
		-- belongs to the part that owns the frame replacing it.
		hideBlizzCharacter = true,
	},

	words = {
		character = CharacterWord,
	},

	help = {
		"character, open the character sheet",
		"character on|off, the addon's character sheet instead of the client's",
		"character hide on|off, put Blizzard's own sheet in the attic and take the C key",
		"character gear, what you are wearing and how worn it is",
		"character stats, your hit and what you still miss with it",
		"character skills, which weapon skills are behind the cap for your level",
		"character trace on|off, say in chat what each click on a gear square did",
	},

	status = function()
		return ("%s; %s; Blizzard's %s"):format(
			ns.CharWindow.Describe(), ns.Worn.Describe(), ns.CharBlizzard.Describe())
	end,

	panel = function(ui)
		ui.Section("Character", "Windows")
		ui.Lede("Your gear, what it adds up to, your skills, your standings and your loadouts, on one window the C key opens.")
		ui.Reading("what you are wearing", ns.Worn.Describe)
		ui.Reading("hit and miss", ns.CharStats.Describe)
		ui.Reading("weapon skills", ns.CharSkills.Describe)
		ui.Reading("standings", ns.CharRep.Describe)
		ui.Reading("Blizzard's window", ns.CharBlizzard.Describe)
	end,
})
