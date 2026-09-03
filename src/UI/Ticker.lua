local ADDON, ns = ...

local UI = ns.UI

--------------------------------------------------------------------------
-- The ticker
--
-- Twelve files wrote the same five lines: accumulate the frame's delta, compare
-- it to an interval, put the accumulator back, call the work, and in most of
-- them bracket the call in ns.Perf.Start and ns.Perf.Stop. Five lines is small
-- enough that nobody minded writing it again, and that is exactly how one of
-- them ends up subtly different from the other eleven.
--
-- One of them was. Zeroing the accumulator throws away however far past the
-- interval the frame landed, so a tick asking for a fifth of a second gets one
-- every fourth frame at 60 Hz and every twelfth at 144, which is 4.6 and 4.8
-- times a second rather than 5. Three files carry a comment saying so and
-- subtract the interval instead; the other nine zero it. That is the bug that
-- made the swing bar step, found once and fixed in one place, and it is the
-- argument for this file on its own.
--
-- The larger argument is scripts/hot.lua. The guard scan needs the set of
-- functions a frame handler can reach, and it derives that set by walking out
-- from the handlers. A handler it can name is a root it can walk. Every ticker
-- registered here is named by construction, which is what turns a hand-written
-- transitive closure into a computed one.
--
-- An interval of zero runs the body every frame, which is what the cast fills
-- and the drag follows want, and it is the same call so they are found by the
-- same walk.
--
-- The name is a ns.Perf slot key. A name that file does not list is not timed
-- and costs a table lookup that misses, so adding a ticker to the performance
-- tab is one entry in Perf's ORDER and nothing here.
--------------------------------------------------------------------------

-- Every ticker on one frame, because a frame has one OnUpdate and two parts of
-- the addon may want a tick off the same never-hidden frame at two rates. The
-- list is built when a ticker is added and only walked afterwards, so the
-- handler itself allocates nothing.
local lists = setmetatable({}, { __mode = "k" })

-- Whether the frame still has work. A frame whose tickers are all stopped gives
-- its OnUpdate back, so a dormant part costs the client nothing at all rather
-- than a call and a comparison every frame forever.
local function Wanted(list)
	for index = 1, #list do
		if list[index].running then
			return true
		end
	end
	return false
end

local function Drive(frame, delta)
	local list = lists[frame]
	if not list then
		return
	end
	for index = 1, #list do
		local tick = list[index]
		if tick.running then
			tick.elapsed = tick.elapsed + delta
			if tick.elapsed >= tick.interval then
				-- The remainder, not zero. See the head of this file.
				local since = tick.elapsed
				tick.elapsed = tick.elapsed - tick.interval
				if tick.elapsed >= tick.interval then
					-- A frame longer than the interval, which is a load spike
					-- rather than a rate. Catching up would run the body twice
					-- in the frame after a stall, so the debt is dropped.
					tick.elapsed = 0
				end
				ns.Perf.Start(tick.name)
				tick.fn(since, frame)
				ns.Perf.Stop(tick.name)
			end
		end
	end
end

local function Attach(frame)
	local list = lists[frame]
	if Wanted(list) then
		frame:SetScript("OnUpdate", Drive)
	else
		frame:SetScript("OnUpdate", nil)
	end
end

local Ticker = {}
Ticker.__index = Ticker

function Ticker:Start()
	self.running = true
	self.elapsed = self.interval -- so the first frame after a start does the work
	Attach(self.frame)
end

function Ticker:Stop()
	self.running = false
	Attach(self.frame)
end

function Ticker:Running()
	return self.running
end

-- frame     what the tick hangs off, which decides when it stops. A frame that
--           is never hidden ticks for the session; a frame that goes with a
--           window stops when the window closes and there is nothing to switch
--           off. Both are wanted and neither is the default, so it is an
--           argument rather than a frame this file owns.
-- interval  seconds between calls, or 0 for every frame.
-- name      the ns.Perf slot the body is timed under.
-- fn        called with the seconds since it last ran and the frame it hangs
--           off. Named rather than a closure, because scripts/hot.lua walks out
--           from this argument, and the frame is the second argument so that a
--           tick belonging to one instance of a widget can find that instance
--           on its own frame rather than closing over it.
function UI.Ticker(frame, interval, name, fn)
	assert(type(frame) == "table", "a ticker hangs off a frame")
	assert(type(interval) == "number" and interval >= 0, "a ticker has an interval")
	assert(type(name) == "string" and name ~= "", "a ticker is named")
	assert(type(fn) == "function", "a ticker runs a function")

	local list = lists[frame]
	if not list then
		list = {}
		lists[frame] = list
	end

	-- One running tick of a name per frame, and the second one fails here.
	--
	-- Nothing below dedupes. The list is appended to and then walked, so a
	-- second ticker of the same name on the same frame is the same body called
	-- twice at the same rate, and the only trace it leaves is the frame budget.
	-- Buttons/Bars.lua armed its ticker inside a branch that runs on every
	-- loading screen and had four of them after three zone loads, which reads as
	-- a bar that gets heavier the longer the session runs. This is the call that
	-- would have said so.
	--
	-- A stopped tick of the same name is left alone: that is a part switching
	-- itself back on, which is what Perf/Perf.lua does with its sampler, and it
	-- goes through Start rather than through here.
	for index = 1, #list do
		local other = list[index]
		assert(not (other.running and other.name == name),
			"a ticker named " .. name .. " is already running on this frame")
	end

	local tick = setmetatable({
		frame = frame,
		interval = interval,
		name = name,
		fn = fn,
		elapsed = interval,
		running = true,
	}, Ticker)
	list[#list + 1] = tick
	Attach(frame)
	return tick
end
