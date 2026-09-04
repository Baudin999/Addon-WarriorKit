local ADDON, ns = ...

local Hud = {}
ns.PerfHud = Hud

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The window Ctrl-R opens
--
-- The client's own Ctrl-R draws a number in a corner. This draws the last four
-- seconds of frames as a strip, what the last second went on underneath it, and
-- a log of the frames that went wrong with a sentence each saying why.
--
-- **The strip is the point and the number is not.** A frame rate is an average
-- over a second, and the thing you felt was one frame inside that second. Sixty
-- frames with a 200 ms stall in them still read as 55 fps, which is why the
-- client's own display can be up while the game stutters and say nothing at
-- all. One column per frame cannot hide a stall: the column is as tall as the
-- frame was.
--
-- **It is drawn as a ring, not a scroll.** The oldest column is overwritten by
-- the newest and a cursor marks where the writing head is, the way an
-- oscilloscope sweeps. Scrolling would mean rewriting two hundred and forty
-- heights on every repaint to move a picture sideways; this rewrites the
-- handful that changed. The cost of a window about performance is not a detail.
--
-- **Every string is built behind a comparison.** The two fillers below carry a
-- cold marker because that is exactly what they are: the tick compares the
-- numbers, and the functions that turn numbers into words run on the tick where
-- one of them moved. A window that rebuilt thirty strings ten times a second
-- would be the most expensive thing on its own list.
--------------------------------------------------------------------------

local COLUMNS = ns.Trace.Window()

-- Two units a column, which is 480 across and sets the window's width. One unit
-- would be a hairline on a 4K panel and a column you cannot see is a frame you
-- cannot see.
local COLUMN = 2
local STRIP_H = 76

-- Where the strip is cut in half. Under the line is 0 to 33 ms, which is every
-- frame that arrived on time and most of the ones that did not; over it is 33
-- to 200, which is the whole range of a stall. A single linear scale wastes
-- nine tenths of the height on frames nobody is looking at.
local BREAK_MS = 33.4
local CEILING_MS = 200

-- The two rules across the strip: one frame at 60 a second, one at 30.
local SIXTY_MS = 16.7

local ROWS = 5   -- what the last second went on
local DIP_ROWS = 8

local WIDTH = COLUMNS * COLUMN + M.pad * 2
local HEAD_Y = 10
local SUB_Y = 32
local STRIP_Y = 50
local LEGEND_Y = STRIP_Y + STRIP_H + 5
local COST_HEAD_Y = LEGEND_Y + 20
local COST_Y = COST_HEAD_Y + 18
local COST_ROW = 15
local DIP_HEAD_Y = COST_Y + ROWS * COST_ROW + 12
local DIP_Y = DIP_HEAD_Y + 18
local DIP_ROW = 24
local HEIGHT = DIP_Y + DIP_ROWS * DIP_ROW + M.pad + M.title + M.footer

local BIG = 17

-- What a column is drawn in. Green is a frame that arrived inside a sixtieth of
-- a second, gold is one that did not and still made thirty, red is the rest.
-- Three bands rather than a gradient, because the question a strip answers at a
-- glance is how many columns are red.
local GOOD = C.tick
local WARN = C.heading
local BAD = C.loss

local window, columns, cursor, ticker
local head, sub, legend
local cost, dipRows = {}, {}
local shown = { fps = nil, worst = nil, total = nil, dip = nil }

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

local function Line(parent, size, color, justify)
	return UI.Label(parent, size, color, justify, UI.FLAT)
end

local function BuildHead(body)
	head = Line(body, BIG, C.text, "LEFT")
	head:SetPoint("TOPLEFT", M.pad, -HEAD_Y)

	sub = Line(body, M.small, C.dim, "LEFT")
	sub:SetPoint("TOPLEFT", M.pad, -SUB_Y)
	sub:SetPoint("RIGHT", body, "RIGHT", -M.pad, 0)
end

-- The strip: a sunken box, one texture per column standing on its floor, two
-- rules across it, and the cursor that says where the newest frame is.
local function BuildStrip(body)
	local box = UI.Box(body, C.sunken, C.hairline)
	box:SetPoint("TOPLEFT", M.pad, -STRIP_Y)
	box:SetSize(COLUMNS * COLUMN, STRIP_H)

	columns = {}
	for index = 1, COLUMNS do
		local bar = ns.Fill(box, "ARTWORK", GOOD[1], GOOD[2], GOOD[3], 0.85)
		bar:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", (index - 1) * COLUMN, 0)
		bar:SetSize(COLUMN, 1)
		bar:Hide()
		columns[index] = bar
	end

	local thirty = UI.Rule(box, C.hairline)
	thirty:SetPoint("LEFT")
	thirty:SetPoint("RIGHT")
	thirty:SetPoint("BOTTOM", box, "BOTTOM", 0, STRIP_H / 2)

	local sixty = UI.Rule(box, C.hairline)
	sixty:SetPoint("LEFT")
	sixty:SetPoint("RIGHT")
	sixty:SetPoint("BOTTOM", box, "BOTTOM", 0, STRIP_H / 4)

	cursor = ns.Fill(box, "OVERLAY", C.quiet[1], C.quiet[2], C.quiet[3], 0.5)
	cursor:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
	cursor:SetSize(COLUMN, STRIP_H)

	legend = Line(body, M.small, C.quiet, "LEFT")
	legend:SetPoint("TOPLEFT", M.pad, -LEGEND_Y)
	legend:SetPoint("RIGHT", body, "RIGHT", -M.pad, 0)
end

local function Heading(body, text, y)
	local label = Line(body, M.small, C.heading, "LEFT")
	label:SetPoint("TOPLEFT", M.pad, -y)
	label:SetText(text)
	return label
end

local function BuildCost(body)
	Heading(body, "WHAT THE LAST SECOND WENT ON", COST_HEAD_Y)
	for index = 1, ROWS do
		local y = COST_Y + (index - 1) * COST_ROW
		local row = { label = Line(body, M.font, C.text, "LEFT"),
			value = Line(body, M.font, C.dim, "RIGHT") }
		row.label:SetPoint("TOPLEFT", M.pad, -y)
		row.value:SetPoint("TOPRIGHT", -M.pad, -y)
		row.label:SetPoint("RIGHT", row.value, "LEFT", -M.gutter, 0)
		cost[index] = row
	end
end

local function BuildDips(body)
	Heading(body, "FRAMES THAT WENT WRONG", DIP_HEAD_Y)
	for index = 1, DIP_ROWS do
		local y = DIP_Y + (index - 1) * DIP_ROW
		local row = { when = Line(body, M.font, C.text, "LEFT"),
			took = Line(body, M.font, C.loss, "RIGHT"),
			why = Line(body, M.small, C.dim, "LEFT") }
		row.when:SetPoint("TOPLEFT", M.pad, -y)
		row.took:SetPoint("TOPRIGHT", -M.pad, -y)
		row.why:SetPoint("TOPLEFT", M.pad, -(y + 12))
		row.why:SetPoint("RIGHT", body, "RIGHT", -M.pad, 0)
		dipRows[index] = row
	end
end

local function BuildFooter()
	local hint = Line(window.footer, M.small, C.quiet, "LEFT")
	hint:SetPoint("LEFT")
	hint:SetText("Escape closes this. /wk perf dips prints the same log to chat.")

	local close = UI.Button(window.footer, { label = "close", width = 90,
		height = M.row, onClick = Hud.Close })
	close:SetPoint("RIGHT")

	local profiler = UI.Button(window.footer, { label = "the client's profiler",
		width = 150, height = M.row, onClick = Hud.AskProfiler })
	profiler:SetPoint("RIGHT", close, "LEFT", -M.gutter, 0)
end

local function Build()
	window = UI.Window({
		name = "WarriorKitPerf",
		title = "Performance",
		width = WIDTH,
		height = HEIGHT,
		zoom = function() return ns.Zoom("perfZoom") end,
	})
	ns.Remember(window)

	-- Escape closes a window through UISpecialFrames, which calls Hide on the
	-- frame and knows nothing about this file. Every way out has to reach the
	-- same two lines, or the trace goes on watching for a window nobody can see
	-- and the setting that governs it stops meaning anything. Hooked rather than
	-- set, because UI/Window.lua's own cleanup is already on this script.
	window.frame:HookScript("OnHide", Hud.Stopped)

	local body = window.content
	BuildHead(body)
	BuildStrip(body)
	BuildCost(body)
	BuildDips(body)
	BuildFooter()
end

--------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------

local function Say(text, value)
	if text.shown ~= value then
		text.shown = value
		text:SetText(value)
	end
end

-- Where the top of a column stands, in units, for a frame that took this long.
local function Height(took)
	local half = STRIP_H / 2
	if took <= BREAK_MS then
		return math.max(1, half * (took / BREAK_MS))
	end
	local over = (took - BREAK_MS) / (CEILING_MS - BREAK_MS)
	if over > 1 then
		over = 1
	end
	return half + half * over
end

local function Band(took)
	if took <= SIXTY_MS then
		return GOOD
	end
	if took <= BREAK_MS then
		return WARN
	end
	return BAD
end

-- cold: FillNow turns the second's numbers into words, on the tick one of them
-- moved. Paint below does the comparing, which is what a cold marker means.
local function FillNow(last, fps)
	Say(head, ("%d fps"):format(fps))

	-- The line under the strip. The only thing in it that moves is the dip
	-- threshold, which is a setting, and a legend still quoting the old number
	-- after the stepper moved is a lie about what the red columns mean.
	Say(legend, ("%d frames, one column each. The lines are 60 and 30 a second; a dip is %d ms.")
		:format(COLUMNS, ns.db.perfDip))

	-- Every addon's Lua, not this one's. The figure that matters on a window
	-- about stalls is the heap the collector is going to walk, and the collector
	-- does not care whose objects they are.
	local held = ns.Trace.Heap() / 1024
	if ns.Cause.Profiling() then
		Say(sub, ("%.0f ms average, %.0f ms worst, %.0f ms of Lua, %.1f MB held")
			:format(last.average, last.worst, last.lua, held))
	else
		Say(sub, ("%.0f ms average, %.0f ms worst, %.1f MB held, no Lua timing")
			:format(last.average, last.worst, held))
	end
end

-- cold: FillCost writes the five rows under the strip, on the second the
-- ranking moved. Paint compares the ranking's total before calling it.
local function FillCost(last)
	local filled = ns.Cause.Ranking()
	for index = 1, ROWS do
		Say(cost[index].label, "")
		Say(cost[index].value, "")
	end

	if not ns.Cause.Profiling() then
		Say(cost[1].label, "this addon's own tickers")
		Say(cost[1].value, ("%.1f ms"):format(last.ours))
		Say(cost[2].label, "events the client sent")
		Say(cost[2].value, ("%d"):format(last.events))
		Say(cost[3].label, "every other addon")
		Say(cost[3].value, "not measured")
		Say(cost[4].label, "the client's own profiler is off")
		Say(cost[4].value, "nothing else can be named")
		return
	end

	-- The frame exact figure rather than the sum of the ranking, so this row and
	-- the last one add up to the second. The difference between the two is the
	-- client's own Lua and whatever the ranking did not have room for, and a
	-- window that quietly dropped it would be the kind of arithmetic that makes
	-- somebody chase an addon for milliseconds Blizzard spent.
	Say(cost[1].label, "Lua, all of it")
	Say(cost[1].value, ("%.0f ms"):format(last.lua))
	for index = 1, filled do
		local name, spent = ns.Cause.Ranked(index)
		if name then
			Say(cost[index + 1].label, "   " .. name)
			Say(cost[index + 1].value, ("%.0f ms"):format(spent))
		end
	end
	Say(cost[ROWS].label, "the client: drawing, the world, waiting for the screen")
	Say(cost[ROWS].value, ("%.0f ms"):format(math.max(0, last.span - last.lua)))
end

-- How long ago, in the words a person uses. "0 seconds ago" is what rounding a
-- dip four tenths of a second old gives you, and it reads as a clock that has
-- stopped rather than as a stall you just felt.
local function Ago(age)
	if age < 1 then
		return "just now"
	end
	if age < 90 then
		return ("%.0f seconds ago"):format(age)
	end
	return ("%.0f minutes ago"):format(age / 60)
end

-- cold: FillDips writes the log, on the tick a dip arrived or one of the ages
-- rolled over a second. Paint compares both before calling it.
local function FillDips()
	for index = 1, DIP_ROWS do
		local row = dipRows[index]
		local age, took, why = ns.Trace.Dip(index)
		if not age then
			Say(row.when, "")
			Say(row.took, "")
			Say(row.why, (index == 1) and "Nothing has gone wrong yet." or "")
		else
			Say(row.when, Ago(age))
			Say(row.took, ("%.0f ms"):format(took))
			Say(row.why, why or "")
		end
	end
end

-- The strip. Two hundred and forty comparisons and, on a normal repaint, six
-- writes: one per frame the client has drawn since the last one.
local function FillStrip()
	for index = 1, COLUMNS do
		local bar = columns[index]
		local took = ns.Trace.Column(index)
		if not took then
			if bar.drawn then
				bar.drawn = nil
				bar:Hide()
			end
		else
			local want = Height(took)
			if bar.drawn ~= want then
				bar.drawn = want
				bar:SetHeight(want)
				bar:Show()
			end
			local band = Band(took)
			if bar.band ~= band then
				bar.band = band
				bar:SetColorTexture(band[1], band[2], band[3], 0.85)
			end
		end
	end
end

function Hud.Paint()
	local last = ns.Trace.Second()
	local fps = (last.span > 0) and math.floor(last.frames / last.span * 1000 + 0.5) or 0
	if shown.fps ~= fps or shown.worst ~= last.worst then
		shown.fps, shown.worst = fps, last.worst
		FillNow(last, fps)
	end

	FillStrip()
	local at = ns.Trace.Head()
	if cursor.at ~= at then
		cursor.at = at
		-- Cleared first. A second SetPoint on a region that already has one is
		-- a second anchor on some client builds rather than a move, and a
		-- texture pinned by both ends stretches instead of sliding.
		cursor:ClearAllPoints()
		cursor:SetPoint("BOTTOMLEFT", (at % COLUMNS) * COLUMN, 0)
	end

	-- The cost rows move when the ranking does, and with the profiler off there
	-- is no ranking at all, so the two numbers those rows are made of stand in
	-- for it.
	local _, total = ns.Cause.Ranking()
	local moved = total + last.events + math.floor(last.ours * 100)
	if shown.total ~= moved then
		shown.total = moved
		FillCost(last)
	end

	local age, took = ns.Trace.Dip(1)
	local stamp = took and (math.floor(age) * 1000 + took) or 0
	if shown.dip ~= stamp then
		shown.dip = stamp
		FillDips()
	end
end

--------------------------------------------------------------------------

function Hud.Open()
	if not window then
		Build()
	end
	ns.Trace.Watch(true)
	shown.fps = nil -- so the first paint writes every string rather than the ones that moved
	window:Show()
	Hud.Paint()
	if ticker then
		ticker:Start()
	else
		-- On the window's own frame, so the repaint stops when the window is
		-- shut and there is nothing to switch off.
		ticker = ns.UI.Ticker(window.frame, 0.1, "hud", Hud.Paint)
	end
	return true
end

-- The window has gone, however it went. The recorder keeps going if the setting
-- says so, which is the whole argument for the setting: the dip you want
-- explained happens while you are playing, not while you are looking at a
-- window about frame times.
function Hud.Stopped()
	if ticker then
		ticker:Stop()
	end
	ns.Trace.Watch(ns.db.perfWatch and true or false)
end

function Hud.Close()
	if window then
		window:Hide()
	end
	Hud.Stopped()
end

-- The window's own frame, for scripts/harness.lua. The repaint hangs off it
-- rather than off ns.UI.Forever, so a section that means to drive one tick has
-- to be able to name the frame it is on.
function Hud.Frame()
	return window and window.frame or nil
end

function Hud.IsShown()
	return window ~= nil and window:IsShown()
end

function Hud.Toggle()
	if Hud.IsShown() then
		Hud.Close()
		return false
	end
	Hud.Open()
	return true
end

-- The one control that changes a client setting rather than one of ours, so it
-- asks first and says what it costs.
function Hud.AskProfiler()
	local on = not ns.Cause.Profiling()
	UI.Ask({
		title = "The client's profiler",
		question = on
			and "Counting Lua names the addon behind a dip, which is the only way this window can say more than what happened. It slows the whole client while it is on, and it starts at the next load of the interface. Reload now?"
			or "Dips are still timed and explained without it, but nothing can name the addon that spent the time. It stops at the next load of the interface. Reload now?",
		accept = "reload",
		onAccept = function()
			ns.Cause.Turn(on)
			if type(ReloadUI) == "function" then
				ReloadUI()
			end
		end,
	})
end

-- What the window is doing, as the line the page reads.
function Hud.Describe()
	if not window then
		return "never opened this session"
	end
	return Hud.IsShown() and "open" or "shut"
end
