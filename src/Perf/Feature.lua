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

local ROWS = {
	{ key = "marker", label = "charge marker", hz = 20 },
	{ key = "icon", label = "charge icon", hz = 10 },
	{ key = "action", label = "action bars", hz = 10 },
	{ key = "bars", label = "enemy bars", hz = 5 },
	{ key = "skin", label = "unit frames", hz = 5 },
	{ key = "meter", label = "meters", hz = 5 },
}

local lines = {}   -- every font string the sampler writes, and what writes it
local watchers = {} -- the rows that turn sampling on when they are on screen

local function Track(text, read)
	lines[#lines + 1] = { text = text, read = read }
end

-- Written straight onto the string, guarded on what is already there, which is
-- the same rule every ticker in this addon follows. A settings page redrawing
-- itself once a second is still a ticker.
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
	order = 11,

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
		ui.Header("Performance")

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

		local function Readout(label, read)
			ui.Custom(function(row)
				local name = ns.UI.Label(row, ns.UI.Metric.small, ns.UI.Color.dim, "LEFT")
				name:SetPoint("LEFT", row, "LEFT", 0, 0)
				name:SetText(label)
				local value = ns.UI.Label(row, ns.UI.Metric.small, ns.UI.Color.text, "RIGHT")
				value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
				value:SetPoint("LEFT", name, "RIGHT", ns.UI.Metric.gutter, 0)
				Track(value, read)
				return nil
			end)
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

		ui.Note(function()
			return "The client attributes Lua allocation to an addon and nothing else."
				.. " Frames and textures live on the C side and never appear in that"
				.. " figure, and for a UI addon they are most of the real footprint, so"
				.. " read this as the churn rather than the size. A fall is the"
				.. " collector running, which is why the rate counts rises only."
		end)

		ui.Header("What each ticker costs")
		for index = 1, #ROWS do
			local entry = ROWS[index]
			Readout(("%s, %d Hz"):format(entry.label, entry.hz), function()
				return SlotLine(entry)
			end)
		end
		Readout("all five", Total)
		Readout("this tab, sampling", function()
			return Milliseconds(ns.Perf.SelfCost()) .. " per second while open"
		end)

		ui.Note(function()
			local cpu = ns.Perf.ClientCPU()
			if cpu then
				return ("The client's own profiler is on and puts the addon at %.0f ms since"):format(cpu)
					.. " it started counting. Per tick timing above is this addon's own"
					.. " clock and does not need it."
			end
			return "Per addon CPU through the client's profiler needs the scriptProfile"
				.. " CVar and a reload, and it slows the whole client while it is on."
				.. " TitanPerformance owns that setting in this install, so nothing here"
				.. " turns it on. The timings above are the addon's own clock and need"
				.. " none of it."
		end)

		local gaugeOrder, gauges = ns.Perf.Gauges()
		if #gaugeOrder > 0 then
			ui.Header("What is on screen")
			for index = 1, #gaugeOrder do
				local label = gaugeOrder[index]
				Readout(label, function()
					return tostring(gauges[label]() or 0)
				end)
			end
		end

		ui.Header("Timing")
		ui.Check("time each ticker",
			function() return ns.db.perf end,
			function(value)
				ns.db.perf = value
				if not value then
					ns.Perf.Reset()
				end
				Paint()
			end)
		ui.Note(function()
			if not ns.Perf.Ready() then
				return "This client has no debugprofilestop, so there is no clock to time"
					.. " with and the figures above will stay empty. The memory half still"
					.. " works."
			end
			return "Two clock reads per tick, about forty a second across the whole addon."
				.. " The cost of the measurement is on the line above, measured the same"
				.. " way as everything else here."
		end)
		ui.Action(function() return "clear the counters" end, function()
			ns.Perf.Reset()
			Paint()
		end)
	end,
})

-- The sampler writes the rows rather than the panel refreshing them, so this is
-- the hook that connects the two. Registered after the part, because Perf.lua
-- must not know that a panel exists.
ns.Perf.OnSample = Paint
