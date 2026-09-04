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
--
-- Three parts have two rows now, because three parts are told rather than
-- asked: a fast pass over what the client said moved, and a slower reading of
-- everything for what no event carries. The enemy bars are "enemy cast fills"
-- and "enemy bars"; the other two say which half they are. A row's hertz is the
-- ticker's own interval and has to be moved with it, or the tab reports a share
-- of a second that is five times what the part actually takes.
local ROWS = {
	{ key = "marker", label = "charge marker", hz = 20 },
	{ key = "swing", label = "swing timer", hz = 60, rate = "every frame" },
	{ key = "icon", label = "charge icon", hz = 10 },
	{ key = "action", label = "action bars", hz = 10 },
	{ key = "bars", label = "enemy bars", hz = 1 },
	{ key = "cast", label = "enemy cast fills", hz = 60, rate = "every frame" },
	{ key = "playercast", label = "your cast bar", hz = 60, rate = "every frame" },
	{ key = "skin", label = "unit frames", hz = 5 },
	{ key = "skinread", label = "unit frames, full read", hz = 1 },
	{ key = "party", label = "party and raid", hz = 5 },
	{ key = "partyread", label = "party and raid, full read", hz = 1 },
	{ key = "meter", label = "meters", hz = 5 },
	{ key = "buffs", label = "buff nag", hz = 10 },
	{ key = "cooldowns", label = "cooldown row", hz = 10 },
	{ key = "hide", label = "Blizzard frames held down", hz = 1 },
	{ key = "feed", label = "feeds", hz = 60, rate = "every frame" },

	-- The three the frame trace is made of, on the list they measure. A part
	-- that will not account for itself is asking to be believed rather than
	-- read, and this is the part whose whole subject is what things cost.
	--
	-- Two of them have no fixed rate. The recorder runs once per frame drawn,
	-- which is whatever this machine is managing, and the census runs once per
	-- event the client sends, which in a raid is a thousand a second and in an
	-- inn is none. A hertz typed in here would report both as a number somebody
	-- guessed, so each carries the reading that answers it instead.
	{ key = "frame", label = "the frame trace", hz = 60, rate = "every frame",
	  perSecond = function(average) return average * ns.Trace.Second().frames end },
	{ key = "census", label = "counting events", hz = 0, rate = "every event",
	  perSecond = function(average) return average * ns.Trace.Second().events end },
	{ key = "hud", label = "the performance window", hz = 10 },
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

-- What one ticker costs per second of wall clock. The row's own hertz for
-- everything with a fixed rate, and the row's own reading for the two that have
-- none.
local function PerSecond(entry, average)
	if entry.perSecond then
		return entry.perSecond(average)
	end
	return average * entry.hz
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
		:format(Milliseconds(average), PerSecond(entry, average), Milliseconds(peak), ticks)
end

local function Total()
	local perSecond = 0
	local measured = false
	for index = 1, #ROWS do
		local average = ns.Perf.Slot(ROWS[index].key)
		if average then
			measured = true
			perSecond = perSecond + PerSecond(ROWS[index], average)
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

-- What the recorder should be doing, given the setting and whether the window
-- is up. Both are reasons to watch and neither is a reason to stop while the
-- other holds.
local function Rewatch()
	ns.Trace.Watch((ns.db.perfWatch or ns.PerfHud.IsShown()) and true or false)
end

-- The dip log, printed. What the window draws as eight rows this says as eight
-- lines, because a slash word's answer is read in a chat frame and what you
-- want out of it is the list rather than the picture.
local function PrintDips()
	local count = ns.Trace.Dips()
	if count == 0 then
		ns.Print(ns.Trace.Watching()
			and "nothing has gone wrong yet."
			or "not watching. Type /wk perf watch on.")
		return
	end
	ns.Print(("the last %d frame%s that went wrong:"):format(count, count == 1 and "" or "s"))
	for index = 1, count do
		local age, took, why = ns.Trace.Dip(index)
		ns.Print(("  %.0fs ago, %.0f ms: %s"):format(age, took, why or "no reason recorded"))
	end
end

-- The verbs that take a value. Split from the word below because a dispatcher
-- and its arguments are two things, and the shape gate measures a function
-- rather than a file.
local function PerfValue(word, rest)
	if word == "key" then
		local key = rest:upper()
		if key == "NONE" then
			key = ""
		end
		local displaced, why = ns.PerfKey.Bind(key)
		if not displaced then
			ns.Print(why)
		elseif key == "" then
			ns.Print("the performance window has no key now.")
		elseif displaced ~= "" then
			ns.Print(("%s opens the performance window. It shadows %s, and your saved bindings are untouched.")
				:format(key, displaced))
		else
			ns.Print(("%s opens the performance window. Nothing else was bound to it."):format(key))
		end
		return true
	end

	if word == "dip" then
		local want = tonumber(rest)
		if not want then
			ns.Print(("a dip is a frame over %d ms. Give a number of milliseconds."):format(ns.db.perfDip))
			return true
		end
		ns.db.perfDip = math.max(20, math.min(500, math.floor(want)))
		ns.Print(("a frame over %d ms is a dip now."):format(ns.db.perfDip))
		return true
	end

	if word == "watch" then
		ns.db.perfWatch = ns.Command.Toggle(rest)
		Rewatch()
		ns.Print("the frame trace is " .. (ns.db.perfWatch and "on all session." or "on only while the window is open."))
		return true
	end

	return false
end

local function PerfWord(arg)
	local word, rest = arg:match("^(%S*)%s*(.-)$")

	if word == "" then
		ns.PerfHud.Toggle()
		return
	end

	if PerfValue(word, rest) then
		return
	end

	if word == "reset" then
		ns.Perf.Reset()
		ns.Trace.Forget()
		ns.Print("performance counters cleared.")
		return
	end

	if word == "dips" then
		PrintDips()
		return
	end

	if word == "show" then
		ns.Perf.Sample()
		local memory, rate = ns.Perf.Memory()
		ns.Print(("lua memory %.0f KB, allocating %.1f KB/s"):format(memory, rate))
		for index = 1, #ROWS do
			ns.Print(("%s: %s"):format(ROWS[index].label, SlotLine(ROWS[index])))
		end
		ns.Print("total " .. Total())
		ns.Print("frames: " .. ns.Trace.Describe())
		ns.Print("the client's profiler: " .. ns.Cause.Describe())
		return
	end

	ns.db.perf = ns.Command.Toggle(word)
	if not ns.db.perf then
		ns.Perf.Reset()
	end
	ns.Print("tick timing " .. (ns.db.perf and "on" or "off")
		.. ", which is two clock reads per tick and about "
		.. (ns.db.perf and "forty a second across the addon." or "nothing, because it is off."))
end

ns.Register({
	name = "performance",
	order = 21,

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

	zooms = {
		{ key = "perfZoom", label = "Performance", window = true, own = true },
	},

	defaults = {
		-- On, because two clock reads on forty ticks a second is not a cost
		-- worth a decision, and a tab that opens empty is a tab nobody trusts.
		-- The expensive half, the memory walk, is not gated by this: it runs
		-- only while the tab is on screen and never otherwise.
		perf = true,

		-- The frame trace, all session rather than only while the window is
		-- open. On, and this is the one setting in the part worth arguing.
		--
		-- It costs a tick on every frame and a Lua call on every event the
		-- client sends, which is the most expensive thing this addon does when
		-- nothing is on screen. It buys the only question anybody actually has:
		-- a stutter is over before you can reach for a key, so a recorder you
		-- have to start first can only ever explain the second time it happens.
		-- What it costs is on the tab, under "frame" and "census", measured the
		-- same way everything else is.
		perfWatch = true,

		-- A frame over this many milliseconds is written into the log. Fifty is
		-- three frames' worth at 60 a second, which is where a stall stops being
		-- a number and starts being something you felt.
		perfDip = 50,

		-- Ctrl-R, which is where the client puts its own frame rate. Held as an
		-- override, so TOGGLEFPS comes back the moment this is unbound.
		-- Perf/Key.lua carries the argument.
		perfKey = "CTRL-R",

		-- What that key was bound to before this took it, so the panel can say
		-- what is being shadowed rather than the player finding out.
		perfKeyDisplaced = "",

		-- 1.2. A window of numbers is read at a glance from where you are
		-- standing rather than leant into, and the screen's own step already
		-- doubles this on a panel tall enough to need it.
		perfZoom = 1.2,
	},

	words = {
		perf = PerfWord,
	},

	help = {
		"perf, the frame trace: what every frame cost and why the bad ones did",
		"perf key <key|none>, which key opens it. Ctrl-R out of the box",
		"perf dips, the frames that went wrong and what made each one",
		"perf watch on|off, whether the trace runs while the window is shut",
		"perf dip <ms>, how long a frame has to be to count as one",
		"perf show, what each ticker costs. perf on|off, tick timing",
		"perf reset, clear the counters and the log",
	},

	status = function()
		return ("%s; timing %s; opens on %s")
			:format(ns.Trace.Describe(), ns.db.perf and "on" or "off", ns.PerfKey.Describe())
	end,

	panel = function(ui)
		-- ui.Reading draws the row and the sampler writes it, which is why the
		-- string is taken back off the row rather than left to kit.Refresh. That
		-- walks every row on every page and re-measures the ones that wrap, which
		-- is the right thing when a setting changed and the wrong thing once a
		-- second forever.
		local function Readout(label, read)
			Track(ui.Reading(label, read).reading, read)
		end

		ui.Section("The frame trace", "Under the hood")
		ui.Lede("Every frame the client draws, timed, with the ones that went wrong kept and explained.")
		ui.Action(function() return "open the window" end, function()
			ns.PerfHud.Toggle()
		end)
		ui.KeyField("key",
			function()
				if (ns.db.perfKey or "") ~= "" then
					return ns.db.perfKey
				end
				return "|cff808080not bound|r"
			end,
			function(combo)
				local ok, why = ns.PerfKey.Bind(combo)
				if not ok and why then
					ns.Print(why)
				end
			end,
			function() ns.PerfKey.Bind("") end)
		ui.Hint("Ctrl-R out of the box, which is where the client draws its own frame rate. It is an override, so whatever you had on the key comes back the moment this is unbound.")
		ui.Check("watch all session", function() return ns.db.perfWatch end,
			function(value)
				ns.db.perfWatch = value
				Rewatch()
			end)
		ui.Hint("A stutter is over before you can reach for a key. Off, the trace runs only while the window is open, and the dip you wanted explained is the one it missed.")
		ui.Stepper("a dip is", 20, 500, 10,
			function() return ns.db.perfDip end,
			function(value) ns.db.perfDip = value end,
			function(value) return value .. " ms" end)
		ui.Hint("How long one frame has to take before it is written into the log. Fifty is three frames' worth at 60 a second.")
		Readout("the trace", function() return ns.Trace.Describe() end)
		Readout("the window", function() return ns.PerfHud.Describe() end)
		Readout("the key", function() return ns.PerfKey.Describe() end)

		ui.Section("Naming an addon", "Under the hood")
		ui.Lede("The client counts Lua time per addon only while its own profiler is on, which costs the whole client and needs the interface reloaded.")
		ui.Action(function()
			return ns.Cause.Profiling() and "turn the profiler off" or "turn the profiler on"
		end, function()
			ns.PerfHud.AskProfiler()
		end)
		ui.Hint("Off, a dip still says how long it was, whether the collector ran and how many events arrived. On, it names the addon that spent the milliseconds. Nothing here turns it on quietly.")
		Readout("the client's profiler", function() return ns.Cause.Describe() end)
		Readout("events counted", function()
			if not ns.Census.Watching() then
				return "not counting"
			end
			return ns.Census.Heard() and "counting every event the client sends"
				or "counting, nothing heard yet"
		end)

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

		Readout("lua memory held", function()
			local memory = ns.Perf.Memory()
			return ("%.0f KB"):format(memory)
		end)
		Readout("allocating", function()
			local _, rate = ns.Perf.Memory()
			return (rate > 0) and ("%.1f KB/s"):format(rate) or "nothing measurable"
		end)
		Readout("the client's own frame rate", function()
			local fps = GetFramerate and GetFramerate()
			return fps and ("%.0f fps"):format(fps) or "unknown"
		end)
		Readout("this addon, by the client's own count", function()
			local cpu = ns.Perf.ClientCPU()
			return cpu and ("%.0f ms since it started counting"):format(cpu)
				or "the profiler is off, so the client is not counting"
		end)

		ui.Section("What each ticker costs", "Under the hood")
		ui.Lede("One line per ticker in the addon, timed on its own clock, at the rate it runs at.")
		for index = 1, #ROWS do
			local entry = ROWS[index]
			Readout(("%s, %s"):format(entry.label, entry.rate or ("%d Hz"):format(entry.hz)), function()
				return SlotLine(entry)
			end)
		end
		Readout("all of them", Total)
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
