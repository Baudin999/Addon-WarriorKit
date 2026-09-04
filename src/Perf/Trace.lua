local ADDON, ns = ...

local Trace = {}
ns.Trace = Trace

--------------------------------------------------------------------------
-- Every frame, timed
--
-- The client's own Ctrl-R draws a frame rate, which is an average, and an
-- average is the one number that cannot show you a stutter: sixty frames where
-- one of them took 200 ms still reads as 55 fps. What you felt was the 200.
--
-- So this keeps the frames themselves. One tick at an interval of zero runs on
-- every frame the client draws, writes how long that frame took into a ring of
-- four seconds, and asks Perf/Cause.lua to explain the ones that went wrong.
-- The window next door draws the ring as a strip and the explanations as a log.
--
-- **Nothing here allocates.** The ring is eight arrays sized once at load and
-- written in place forever after, because a table per frame on the one tick in
-- the addon that runs every frame is exactly the fault this part exists to
-- find. The one string built is the sentence under a dip, and a dip is a frame
-- that already went wrong.
--
-- **It costs about as much as it can see.** Six client calls a frame, one of
-- which is a table read. The tick brackets itself under the "frame" slot like
-- every other tick in the addon, so the performance tab reports what watching
-- costs on the same page as everything it is watching. A measurement that will
-- not account for itself is asking to be believed rather than read.
--
-- **The recorder runs while the window is shut.** That is the whole point of
-- it. A dip you can reproduce on demand is not the dip anybody is asking about,
-- and a tool you have to have open before the thing happens is a tool for the
-- second time it happens. Perf/Feature.lua carries the switch.
--------------------------------------------------------------------------

-- Frames kept. Four seconds at 60 and rather less at 144, which is the right
-- trade: the strip is for the shape of the last few seconds, and the dip log
-- below it is what remembers further back.
local WINDOW = 240

-- Dips kept, newest first. Eight is what the window has room for, and a ninth
-- dip on screen is a list you scroll rather than a thing you read.
local DIPS = 8

-- A frame under this is not a dip whatever the setting says. Below 20 ms every
-- frame at 60 Hz that misses vsync once is a dip, the log fills with noise, and
-- the one 300 ms stall you were looking for is off the end of it.
local DIP_FLOOR = 20

-- How long after a loading screen a frame is still the loading screen. The
-- client draws one enormous frame on the way back into the world and it is not
-- a stall, so a second of them are marked rather than counted.
local AFTER_LOADING = 1.0

local ms, lua, ours, events = {}, {}, {}, {}
local at, filled = 0, 0
for index = 1, WINDOW do
	ms[index], lua[index], ours[index], events[index] = 0, nil, 0, 0
end

local dipMs, dipAt, dipCause = {}, {}, {}
local dips = 0

-- The one record a dip is described by, filled in place and handed to
-- Perf/Cause.lua. One table for the session rather than one per dip.
local dip = {
	ms = 0, lua = nil, ours = 0, ourKey = nil,
	events = 0, event = nil, eventCount = 0,
	freed = 0, loading = false,
}

-- The last second, filled by Trace.Second and handed out rather than built.
-- One table for the session: the window asks ten times a second.
local second = {
	frames = 0, worst = 0, average = 0,
	lua = 0, ours = 0, events = 0, span = 0,
}

local watching = false
local ticker
local lastHeap = nil
local lastLines = 0     -- combat log lines at the last frame
local sinceMark = 0     -- seconds since Perf/Cause.lua took its baseline
local loadingUntil = 0  -- the client's clock, up to which frames are a load

--------------------------------------------------------------------------

-- What counts as a dip on this machine, in milliseconds. The setting, floored
-- at a number below which every reading is noise.
local function Threshold()
	local want = ns.db and ns.db.perfDip or 50
	return (want > DIP_FLOOR) and want or DIP_FLOOR
end

-- cold: Record writes one dip down, on the frames that already went wrong,
-- which is not the tick that reached it. Everything under it, the ranking of
-- addons and the sentence built out of it, belongs to that frame and not to the
-- sixty a second either side.
local function Record(took, ourMs, ourKey, count, event, most, freed)
	dip.ms = took
	-- The column Beat has just written, which is this frame. Read back rather
	-- than passed, because a dip is described by eight numbers and a function
	-- taking eight arguments is a function whose call site nobody can read.
	dip.lua = lua[at]
	dip.ours = ourMs
	dip.ourKey = ourKey
	dip.events = count
	dip.event = event
	dip.eventCount = most
	dip.freed = freed
	dip.loading = false

	for index = DIPS, 2, -1 do
		dipMs[index], dipAt[index], dipCause[index] =
			dipMs[index - 1], dipAt[index - 1], dipCause[index - 1]
	end
	dipMs[1] = took
	dipAt[1] = GetTime and GetTime() or 0
	dipCause[1] = ns.Cause.Explain(dip)
	if dips < DIPS then
		dips = dips + 1
	end
end

-- One frame. Everything above is what this function is allowed to cost.
local function Beat(since)
	local took = since * 1000
	local ourMs, _, ourKey = ns.Perf.FrameCost()
	local luaMs = ns.Cause.LuaSince()
	local count, event, most = ns.Census.Take()

	-- The combat log, folded in from the one place this addon reads it. See the
	-- header of Perf/Census.lua for why it is not counted with the rest.
	local lines = ns.CombatLog.Lines()
	local said = lines - lastLines
	lastLines = lines
	count = count + said
	if said > most then
		most = said
		event = "COMBAT_LOG_EVENT_UNFILTERED"
	end

	local heap = collectgarbage("count")
	local freed = lastHeap and (lastHeap - heap) or 0
	lastHeap = heap

	at = at % WINDOW + 1
	ms[at], lua[at], ours[at], events[at] = took, luaMs, ourMs, count
	if filled < WINDOW then
		filled = filled + 1
	end

	-- The baseline every per addon figure is measured against, moved on once a
	-- second. It walks every addon the client has loaded, which is why it is not
	-- on the frame.
	sinceMark = sinceMark + since
	if sinceMark >= 1 then
		sinceMark = 0
		-- Ranked before the baseline moves, so the ranking is the second that
		-- has just gone rather than the one starting now.
		ns.Cause.Rank()
		ns.Cause.Mark()
	end

	local loading = (GetTime and GetTime() or 0) < loadingUntil
	if took >= Threshold() and not loading then
		Record(took, ourMs, ourKey, count, event, most, freed)
	end
end

--------------------------------------------------------------------------
-- Reading it back
--------------------------------------------------------------------------

function Trace.Window()
	return WINDOW
end

-- Where the newest frame was written. The strip is drawn as a ring rather than
-- scrolled, so one column changes per frame instead of two hundred and forty.
function Trace.Head()
	return at
end

-- One column: how long that frame took, and how much of it was Lua. Nothing at
-- all for a column nothing has been written to yet.
function Trace.Column(index)
	if index > filled then
		return nil
	end
	return ms[index], lua[index], ours[index], events[index]
end

-- The last second, as one record: how many frames, the longest one, the
-- average, the milliseconds of Lua in them, what this addon's own tickers took,
-- how many events landed, and how much wall clock the lot covers.
--
-- Walked backwards from the newest frame until a second is accounted for, so
-- the answer is a second of wall clock rather than a fixed number of frames.
-- The last frame counted takes the total past the second rather than stopping
-- short of it, because a stop-short on a machine drawing one frame a second
-- answers with nothing at all, which is the reading that matters most.
--
-- Filled in place and handed back, because the window asks for it ten times a
-- second and seven return values at that call site is a line nobody can read.
function Trace.Second()
	local total, worst, count = 0, 0, 0
	second.lua, second.ours, second.events = 0, 0, 0

	local index = at
	for _ = 1, filled do
		local took = ms[index]
		total = total + took
		count = count + 1
		if took > worst then
			worst = took
		end
		second.lua = second.lua + (lua[index] or 0)
		second.ours = second.ours + ours[index]
		second.events = second.events + events[index]
		index = (index == 1) and WINDOW or (index - 1)
		if total >= 1000 then
			break
		end
	end

	second.frames = count
	second.worst = worst
	second.span = total
	second.average = (count > 0) and (total / count) or 0
	return second
end

-- Every addon's Lua heap in kilobytes, as the last frame read it. The client's
-- own number rather than a walk over the addon list: the collector does not
-- care whose objects they are, and this is what it is going to walk.
function Trace.Heap()
	return lastHeap or 0
end

function Trace.Dips()
	return dips
end

-- One dip, newest first: how long ago, how long it was, and why.
function Trace.Dip(index)
	if index > dips then
		return nil
	end
	local now = GetTime and GetTime() or 0
	return now - (dipAt[index] or now), dipMs[index], dipCause[index]
end

function Trace.Forget()
	for index = 1, WINDOW do
		ms[index], lua[index], ours[index], events[index] = 0, nil, 0, 0
	end
	at, filled, dips = 0, 0, 0
	lastHeap = nil
	ns.Cause.Forget()
	ns.Census.Forget()
end

--------------------------------------------------------------------------

-- Two events and one frame.
--
-- The frames the client draws on the way back into the world are not stalls,
-- and the first of them can be several seconds long. Marked rather than
-- counted, so the log holds what went wrong while you were playing.
--
-- Login is where the recorder starts, if the setting says it should. It is the
-- one part of this feature that costs anything with nothing on screen, so it is
-- the one part that asks.
local loads = CreateFrame("Frame")
loads:RegisterEvent("PLAYER_ENTERING_WORLD")
loads:RegisterEvent("PLAYER_LOGIN")
loads:SetScript("OnEvent", function(_, event)
	loadingUntil = (GetTime and GetTime() or 0) + AFTER_LOADING
	if event == "PLAYER_LOGIN" and ns.db.perfWatch then
		Trace.Watch(true)
	end
end)

function Trace.Watch(on)
	if watching == on then
		return watching
	end
	watching = on

	if on then
		lastHeap = nil
		lastLines = ns.CombatLog.Lines()
		sinceMark = 0
		ns.Cause.Forget()
		ns.Cause.Mark()
		ns.Census.Watch(true)
		if ticker then
			ticker:Start()
		else
			ticker = ns.UI.Ticker(ns.UI.Forever, 0, "frame", Beat)
		end
	else
		ns.Census.Watch(false)
		if ticker then
			ticker:Stop()
		end
	end
	return watching
end

function Trace.Watching()
	return watching
end

-- What the recorder is doing, as the line the page reads.
function Trace.Describe()
	if not watching then
		return "not watching"
	end
	local last = Trace.Second()
	if last.frames == 0 then
		return "watching, nothing timed yet"
	end
	return ("watching, %d frames in the last second, worst %.0f ms, %d dip%s kept")
		:format(last.frames, last.worst, dips, dips == 1 and "" or "s")
end
