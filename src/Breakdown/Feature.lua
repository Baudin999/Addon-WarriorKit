local ADDON, ns = ...

-- The tab. Breakdown.lua counts and Window.lua draws; this is the only file in
-- the folder that knows the addon around it.

local Breakdown = ns.Breakdown
local Window = ns.BreakdownWindow

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

	if option == "open" or option == "window" then
		Window.Toggle()
		return
	end

	if option == "top" then
		local count = ns.Command.Number(value, 1, 40, "breakdown rows")
		if count then
			Window.Print(count)
		end
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
	ui.Section("Breakdown", "Readouts")
	ui.Lede("What this character actually does, counted out of the combat log and kept between sessions.")

	ui.Cycle("targets", BAND_LIST, BandWord,
		function(word)
			ns.db.breakdownBand = (word == EVERY) and 0 or BandFor(word)
		end)
	ui.Hint("Worth picking one band before you believe a crit or a miss rate: in this era the target's level drives both hard, and a pooled number averages two unrelated things.")

	ui.Action(function()
		return Window.IsShown() and "close the table" or "open the table"
	end, function()
		Window.Toggle()
	end)
	ui.Hint("A left click on the meter's header opens it too, which is where you are looking when the question occurs to you. Right click that header to swap damage and healing.")

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

	ui.Reading("the record", function()
		if not Breakdown.Ready() then
			return "this client has no combat log API, so nothing can be counted"
		end
		return Breakdown.Describe()
	end)
end

--------------------------------------------------------------------------

ns.Register({
	name = "breakdown",
	order = 10,

	switch = {
		key = "breakdown",
		label = "the breakdown record",
	},

	defaults = {
		-- The switch and the band are the account's, because they are preferences
		-- about the addon rather than facts about a character.
		breakdown = true,
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
		"breakdown on|off, breakdown open for the window, breakdown to print the top ten",
		"breakdown top 20, band all or a level band",
		"breakdown reset yes throws away everything counted so far",
	},

	status = Breakdown.Describe,

	panel = Panel,
})
