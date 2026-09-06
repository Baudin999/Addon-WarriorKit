local ADDON, ns = ...

-- Everything Core and the panel need to know about the character sheet.
-- Worn.lua, Stats.lua, Skills.lua, Reputation.lua, Readout.lua, Paperdoll.lua,
-- Window.lua, RepWindow.lua and Blizzard.lua hold the behaviour, and this is
-- the only file in the folder that names anything outside it.

local function SetDim(value)
	ns.db.characterDim = value
	ns.CharWindow.Darken()
end

local function SetCharacter(value)
	ns.db.character = value
	if value then
		ns.CharWindow.Build()
	else
		ns.CharWindow.Hide()
		-- The standings window goes down with the sheet it came off. One switch
		-- says whether this addon draws your character or the client does, and a
		-- reputation list left on the screen after it is turned off would be half
		-- an answer.
		ns.CharRepWindow.Hide()
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

-- A word of its own, because the standings are a window of their own.
--
-- They were a tab on the sheet and the sheet is one page now. Everything about
-- them that is not the window is still in Character/Reputation.lua, and this is
-- the only route to it a player types.
local function ReputationWord(arg, rawArg)
	local word = arg:match("^(%S*)")

	if word == "" then
		if not ns.db.character then
			ns.Print("the character sheet is off. Type /wk character on.")
			return rawArg
		end
		ns.CharRepWindow.Toggle()
	elseif word == "list" then
		ns.Print(ns.CharRep.Describe() .. ".")
	else
		ns.Print("reputation opens the standings window, and takes list.")
	end
	return rawArg
end

--------------------------------------------------------------------------

ns.Register({
	name = "character",
	order = 27,

	switch = {
		key = "character",
		label = "the character sheet",
		says = "Whether Blizzard's own sheet is hidden is on the Blizzard's own frames page with the other nine.",
		apply = function(value) SetCharacter(value) end,
	},

	zooms = {
		{ key = "characterZoom", label = "Character sheet", window = true },
	},

	defaults = {
		-- 1.3, and it was 1.25 when every window in the addon shared one number.
		-- A tenth is the step now and 1.25 is not on one, so a default that
		-- stayed there would be a value the page cannot reach and the reset
		-- cannot restore.
		--
		-- It means something different here than on the other eleven windows,
		-- and the slider is the same slider. The sheet is the size of the screen
		-- whatever this is set to, so turning it up does not make the sheet
		-- bigger: it makes the type, the discs and the figure bigger and leaves
		-- less room round them, because the units the page is laid out in shrink
		-- by exactly this factor. At 1 the sheet is the monitor in pixels, which
		-- is a lot of very small writing on the panel most people are playing on.
		characterZoom = 1.3,

		-- On. The client's own sheet spends its largest area on a picture of
		-- your back and answers none of the three questions anybody opens it
		-- for, and everything this replaces it with is reversible in one press.
		character = true,

		-- On, and the sheet is barely a sheet without it. It has no ground by
		-- design, so what nineteen item names and a column of numbers are read
		-- against is whatever the player happens to be standing on, and a page
		-- with no edge and no ground reads as text scattered over scenery rather
		-- than as one thing. The wash is what makes it a page.
		--
		-- Off is for the player who wants to watch what is behind it, and it costs
		-- them nothing else: the sheet is see-through and click-through either way.
		characterDim = true,

		-- Blizzard's own goes in the attic, and C opens this one.
		--
		-- The switch itself is drawn on the Blizzard page with the other nine,
		-- because there is one place in this addon where a frame of the
		-- client's is switched off. The default lives here because a default
		-- belongs to the part that owns the frame replacing it.
		hideBlizzCharacter = true,
	},

	-- How the figure on the gear page is standing when you open the sheet.
	--
	-- Per character because a pose is. The angle that reads on a tauren warrior
	-- is not the angle that reads on a gnome, and the weapons you want in his
	-- hands are the ones this character is carrying. Nothing here is worded
	-- anywhere: the drag, the wheel and the mark in the corner of the figure are
	-- the whole of the interface, and Character/Paperdoll.lua says what each
	-- number does to the model.
	charDefaults = {
		-- Three quarters on, which is how the client poses the model on its own
		-- sheet and is the angle a shoulder actually reads at. Dead ahead is a
		-- chest and two arms.
		figureFacing = 0.5,
		-- As far back as the wheel goes, which is where the client frames him.
		figureNear = 0,
		-- Weapons away, which is how he stands in the world.
		figureSheathed = true,
	},

	words = {
		character = CharacterWord,
		reputation = ReputationWord,
	},

	help = {
		"character, open the character sheet",
		"reputation, open your standings in a window of their own",
		"reputation list, how many factions you know and how many are exalted",
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
		ui.Lede("Your gear, what it adds up to and your skills, on one page the C key opens. Your standings are on /wk reputation.")
		ui.Check("darken the world behind the sheet",
			function() return ns.db.characterDim end,
			SetDim)
		ui.Reading("what you are wearing", ns.Worn.Describe)
		ui.Reading("hit and miss", ns.CharStats.Describe)
		ui.Reading("weapon skills", ns.CharSkills.Describe)
		ui.Reading("standings", ns.CharRep.Describe)
		ui.Reading("Blizzard's window", ns.CharBlizzard.Describe)
	end,
})
