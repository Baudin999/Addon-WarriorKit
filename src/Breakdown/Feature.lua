local ADDON, ns = ...

-- The tab. Breakdown.lua counts and Window.lua draws; this is the only file in
-- the folder that knows the addon around it.

local Breakdown = ns.Breakdown
local Window = ns.BreakdownWindow

-- What a row can be ranked on, as the word shown on the control and the field
-- it reads off the row. Two lists rather than one table, because UI.Kit's Cycle
-- matches on the word it was given and hands the same word back.
local SORTS = { "damage", "casts", "hits" }
local SORT_FIELD = { damage = "damage", casts = "casts", hits = "landed" }

-- The band control, with "every band" first. The four words after it come from
-- Breakdown.lua rather than being typed here, so the pane and the slash word
-- cannot describe the same band differently.
local EVERY = "every band"

local BAND_LIST = { EVERY }
for _, band in ipairs(Breakdown.Bands()) do
	BAND_LIST[#BAND_LIST + 1] = Breakdown.BandWord(band)
end

local function BandWord()
	local band = Breakdown.Band()
	return band and Breakdown.BandWord(band) or EVERY
end

local function BandFor(word)
	for _, band in ipairs(Breakdown.Bands()) do
		if Breakdown.BandWord(band) == word then
			return band
		end
	end
	return 0
end

--------------------------------------------------------------------------
-- The slash word
--------------------------------------------------------------------------

local function BreakdownWord(arg)
	local option, value = arg:match("^(%S*)%s*(.-)$")

	if option == "" or option == "show" then
		Window.Print(10)
		return
	end

	if option == "top" then
		local count = ns.Command.Number(value, 1, 40, "breakdown rows")
		if count then
			Window.Print(count)
		end
		return
	end

	if option == "sort" then
		if not SORT_FIELD[value] then
			ns.Print("sort by damage, casts or hits.")
			return
		end
		ns.db.breakdownSort = SORT_FIELD[value]
		ns.Options.Refresh()
		ns.Print("ranked by " .. value .. ".")
		return
	end

	if option == "band" then
		if value == "" or value == "all" then
			ns.db.breakdownBand = 0
			ns.Options.Refresh()
			ns.Print("counting every band together.")
			return
		end
		local band = BandFor(value)
		if band == 0 then
			ns.Print("band all, or one of: " .. table.concat(BAND_LIST, ", ", 2) .. ".")
			return
		end
		ns.db.breakdownBand = band
		ns.Options.Refresh()
		ns.Print("showing targets " .. Breakdown.BandWord(band) .. ".")
		return
	end

	-- Throwing away a month of counting is not something a mistyped word should
	-- be able to do, so the word alone says what it would do and only `reset
	-- yes` does it. The panel asks the same question by making you press twice.
	if option == "reset" then
		if value ~= "yes" then
			ns.Print(("this would throw away %d abilities counted since %s. Type /wk breakdown reset yes.")
				:format(Breakdown.Count(), date("%d %b", Breakdown.Since())))
			return
		end
		Breakdown.Reset()
		ns.Options.Refresh()
		ns.Print("the count starts again from now.")
		return
	end

	ns.db.breakdown = ns.Command.Toggle(option)
	ns.Print("the breakdown is " .. (ns.db.breakdown and "counting." or "not counting."))
end

--------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------

-- Whether the reset button is one press from doing it. Not saved and not reset
-- when the page closes, which is deliberate on both counts: it is a fact about
-- the last thing you clicked, and a player who armed it, went to another tab
-- and came back has still armed it.
local armed = false

local function Panel(ui)
	ui.Header("Breakdown")

	ui.Note(function()
		return "What this character actually does, counted out of the combat log and"
			.. " kept between sessions. One row per ability: how much of your damage"
			.. " it is, how often it lands, how often it crits, and what stopped it"
			.. " when it did not land. It is not the meters, which total the pull you"
			.. " are in and forget it; this is the month."
	end)

	ui.Check("Count what this character does", function() return ns.db.breakdown end,
		function(on)
			ns.db.breakdown = on
		end)

	ui.Note(function()
		if not Breakdown.Ready() then
			return "|cffd08040This client has no combat log API|r, so nothing can be"
				.. " counted and the table stays empty."
		end
		return ("%s. Only your own hits are counted, which is what keeps this small:"
			.. " counting the group would grow the table by every stranger you have"
			.. " ever been in a party with."):format(Breakdown.Describe())
	end)

	ui.Cycle("rank by", SORTS,
		function()
			for word, field in pairs(SORT_FIELD) do
				if field == ns.db.breakdownSort then
					return word
				end
			end
			return SORTS[1]
		end,
		function(word)
			ns.db.breakdownSort = SORT_FIELD[word] or "damage"
		end)

	ui.Cycle("targets", BAND_LIST, BandWord,
		function(word)
			ns.db.breakdownBand = (word == EVERY) and 0 or BandFor(word)
		end)

	ui.Note(function()
		if Breakdown.Band() then
			return "One band on its own. Worth doing before you believe a crit or a miss"
				.. " rate: in this era the target's level drives both of them hard, and"
				.. " a number pooled across grey trash and an elite is the average of"
				.. " two unrelated things."
		end
		return "Every band added together. The four bands are the target's level"
			.. " against yours, and the fourth is the honest one: the combat log does"
			.. " not carry a target's level, so a mob you never targeted and never saw"
			.. " a nameplate for lands in |cffd08040level not seen|r rather than being"
			.. " quietly counted as your own level."
	end)

	Window.Build(ui)

	ui.Note(function()
		return "Ranks are added up under one name. A rate pools across ranks correctly,"
			.. " because it is per attempt either way, and an average hit does not: for"
			.. " an ability you have used at several ranks the average is a blend of the"
			.. " rank you outgrew and the one you use now."
	end)

	ui.Action(function()
		if armed then
			return "press again to throw it away"
		end
		return ("start again, throwing away %d abilities"):format(Breakdown.Count())
	end, function()
		if not armed then
			armed = true
			return
		end
		armed = false
		Breakdown.Reset()
	end)
end

--------------------------------------------------------------------------

ns.Register({
	name = "breakdown",
	order = 7.8,

	defaults = {
		-- The switch and the two view settings are the account's, because they
		-- are preferences about the addon rather than facts about a character.
		breakdown = true,
		breakdownSort = "damage",
		breakdownBand = 0,
	},

	charDefaults = {
		-- The record itself. A flat key holding a flat table, because
		-- ApplyDefaults copies a default one level deep and a nested table
		-- inside a default would be handed to every character by reference.
		breakdownSpells = {},
		breakdownSince = 0,
	},

	words = {
		breakdown = BreakdownWord,
	},

	help = {
		"breakdown on|off, and breakdown to print the top ten",
		"breakdown top 20, sort damage|casts|hits, band all or a level band",
		"breakdown reset yes throws away everything counted so far",
	},

	status = Breakdown.Describe,

	panel = Panel,
})
