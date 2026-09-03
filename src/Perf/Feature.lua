local ADDON, ns = ...

-- The tab. Perf.lua holds the numbers and knows the name of no part; this file
-- is the only one that knows both, which is the same seam every other part
-- draws between its behaviour and its Feature.
--
-- The rows do not go through ns.Options.Refresh. That walks every row on every
-- page and re-measures the ones that wrap, which is the right thing when a
-- setting changed and the wrong thing once a second forever. These rows are
-- fixed height and single line by construction, so the sampler writes their
-- strings directly and nothing is laid out again.

-- hz is what the row's ticker runs at, and it is what turns a per tick figure
-- into the share of a second the part actually takes. The swing timer has no
-- rate of its own: it draws on every frame, because motion is drawn on the
-- frame the screen is drawn on or it is drawn in steps. The enemy cast fills
-- are the second thing in the addon to say so and the second row with no hertz.
-- Both are costed against 60 frames a second, which is the same budget Total
-- below measures everything against, and `rate` is what the heading says
-- instead of a number of hertz.
local ROWS = {
	{ key = "marker", label = "charge marker", hz = 20 },
	{ key = "swing", label = "swing timer", hz = 60, rate = "every frame" },
	{ key = "icon", label = "charge icon", hz = 10 },
	{ key = "action", label = "action bars", hz = 10 },
	{ key = "bars", label = "enemy bars", hz = 5 },
	{ key = "cast", label = "enemy cast fills", hz = 60, rate = "every frame" },
	{ key = "playercast", label = "your cast bar", hz = 60, rate = "every frame" },
	{ key = "skin", label = "unit frames", hz = 5 },
	{ key = "party", label = "party and raid", hz = 5 },
	{ key = "meter", label = "meters", hz = 5 },
	{ key = "buffs", label = "buff nag", hz = 10 },
	{ key = "cooldowns", label = "cooldown row", hz = 10 },
	{ key = "hide", label = "Blizzard frames held down", hz = 1 },
	{ key = "feed", label = "feeds", hz = 60, rate = "every frame" },
}

local lines = {}   -- every font string the sampler writes, and what writes it
local watchers = {} -- the rows that turn sampling on when they are on screen

local function Track(text, read)
	lines[#lines + 1] = { text = text, read = read }
end

-- Written straight onto the string, guarded on what is already there, which is
-- the same rule every ticker in this addon follows. A settings page redrawing
-- itself once a second is still a ticker.
-- hot: assigned to ns.Perf.OnSample below and called back through that field by
-- the sampler's tick, which is an edge scripts/hot.lua cannot see.
local function Paint()
	for index = 1, #lines do
		local row = lines[index]
		local value = row.read()
		if row.shown ~= value then
			row.shown = value
			row.text:SetText(value)
		end
	end
end

local function Milliseconds(ms)
	if not ms then
		return "not measured yet"
	end
	if ms < 0.01 then
		return "under 0.01 ms"
	end
	return ("%.2f ms"):format(ms)
end

local function SlotLine(entry)
	local average, peak, ticks = ns.Perf.Slot(entry.key)
	if not average then
		if not ns.db.perf then
			return "off"
		end
		return ns.Perf.Ready() and "idle" or "no clock on this client"
	end
	-- Per tick is the spike you feel, per second is the share of the frame
	-- budget it actually takes. Neither one alone answers "is this expensive".
	return ("%s per tick, %.2f ms/s, worst %s, %d ticks")
		:format(Milliseconds(average), average * entry.hz, Milliseconds(peak), ticks)
end

local function Total()
	local perSecond = 0
	local measured = false
	for index = 1, #ROWS do
		local average = ns.Perf.Slot(ROWS[index].key)
		if average then
			measured = true
			perSecond = perSecond + average * ROWS[index].hz
		end
	end
	if not measured then
		return "nothing measured yet"
	end
	-- Against a 60 fps budget, because that is the frame the work has to fit
	-- inside rather than the frame rate you happen to be getting.
	return ("%.2f ms per second, %.2f%% of one 60 fps frame's worth")
		:format(perSecond, perSecond / 16.67 * 100)
end

--------------------------------------------------------------------------

local function PerfWord(arg)
	-- One word, no value. Every other part splits the argument in two because
	-- it has settings that take a number; this one has a switch and two verbs.
	local option = arg:match("^(%S*)")

	if option == "reset" then
		ns.Perf.Reset()
		ns.Print("performance counters cleared.")
		return
	end

	if option == "" or option == "show" then
		ns.Perf.Sample()
		local memory, rate = ns.Perf.Memory()
		ns.Print(("lua memory %.0f KB, allocating %.1f KB/s"):format(memory, rate))
		for index = 1, #ROWS do
			ns.Print(("%s: %s"):format(ROWS[index].label, SlotLine(ROWS[index])))
		end
		ns.Print("total " .. Total())
		return
	end

	ns.db.perf = ns.Command.Toggle(option)
	if not ns.db.perf then
		ns.Perf.Reset()
	end
	ns.Print("tick timing " .. (ns.db.perf and "on" or "off")
		.. ", which is two clock reads per tick and about "
		.. (ns.db.perf and "forty a second across the addon." or "nothing, because it is off."))
end

ns.Register({
	name = "performance",
	order = 20,

	switch = {
		key = "perf",
		label = "timing each ticker",
		apply = function(value)
			if not value then
				ns.Perf.Reset()
			end
			Paint()
		end,
	},

	defaults = {
		-- On, because two clock reads on forty ticks a second is not a cost
		-- worth a decision, and a tab that opens empty is a tab nobody trusts.
		-- The expensive half, the memory walk, is not gated by this: it runs
		-- only while the tab is on screen and never otherwise.
		perf = true,
	},

	words = {
		perf = PerfWord,
	},

	help = {
		"perf, what each ticker costs and what the addon is holding",
		"perf on|off, tick timing. perf reset, clear the counters",
	},

	status = function()
		local memory = ns.Perf.Memory()
		return ("timing %s, %.0f KB held, %s")
			:format(ns.db.perf and "on" or "off", memory, Total())
	end,

	panel = function(ui)
		ui.Section("Performance", "Under the hood")
		ui.Lede("What the addon costs: how much Lua it holds, and how long each ticker takes.")

		-- One row that owns the sampler. It is a child of this section, so the
		-- client shows it when the tab is chosen and hides it when the window
		-- closes or another tab is, and that is exactly the window in which
		-- walking every addon's memory is worth doing.
		ui.Custom(function(row)
			row:SetScript("OnShow", function()
				ns.Perf.Watch(true)
				Paint()
			end)
			row:SetScript("OnHide", function()
				ns.Perf.Watch(false)
			end)
			watchers[#watchers + 1] = row
			return nil
		end, { height = 1 })

		-- ui.Reading draws the row and the sampler writes it, which is why the
		-- string is taken back off the row rather than left to kit.Refresh. That
		-- walks every row on every page and re-measures the ones that wrap, which
		-- is the right thing when a setting changed and the wrong thing once a
		-- second forever.
		local function Readout(label, read)
			Track(ui.Reading(label, read).reading, read)
		end

		Readout("lua memory held", function()
			local memory = ns.Perf.Memory()
			return ("%.0f KB"):format(memory)
		end)
		Readout("allocating", function()
			local _, rate = ns.Perf.Memory()
			return (rate > 0) and ("%.1f KB/s"):format(rate) or "nothing measurable"
		end)
		Readout("frame rate", function()
			local fps = GetFramerate and GetFramerate()
			return fps and ("%.0f fps"):format(fps) or "unknown"
		end)
		Readout("the client's own profiler", function()
			local cpu = ns.Perf.ClientCPU()
			return cpu and ("%.0f ms since it started counting"):format(cpu)
				or "off, and nothing here turns it on"
		end)

		ui.Section("What each ticker costs", "Under the hood")
		ui.Lede("One line per ticker in the addon, timed on its own clock, at the rate it runs at.")
		for index = 1, #ROWS do
			local entry = ROWS[index]
			Readout(("%s, %s"):format(entry.label, entry.rate or ("%d Hz"):format(entry.hz)), function()
				return SlotLine(entry)
			end)
		end
		Readout("all five", Total)
		Readout("this tab, sampling", function()
			return Milliseconds(ns.Perf.SelfCost()) .. " per second while open"
		end)

		local gaugeOrder, gauges = ns.Perf.Gauges()
		if #gaugeOrder > 0 then
			ui.Section("What is on screen", "Under the hood")
			ui.Lede("How many of each thing the addon is drawing right now, which is what the timings are of.")
			for index = 1, #gaugeOrder do
				local label = gaugeOrder[index]
				Readout(label, function()
					return tostring(gauges[label]() or 0)
				end)
			end
		end

		ui.Section("Timing", "Under the hood")
		ui.Lede("The clock the figures above are taken on, and the button that clears what it has counted.")
		ui.Action(function() return "clear the counters" end, function()
			ns.Perf.Reset()
			Paint()
		end)
		ui.Hint("Two clock reads per tick, about forty a second across the whole addon. What that costs is one of the lines it measures.")
		ui.Reading("the clock", function()
			return ns.Perf.Ready() and "debugprofilestop, this client has one"
				or "this client has no debugprofilestop, so there is nothing to time with"
		end)
	end,
})

-- The sampler writes the rows rather than the panel refreshing them, so this is
-- the hook that connects the two. Registered after the part, because Perf.lua
-- must not know that a panel exists.
ns.Perf.OnSample = Paint
