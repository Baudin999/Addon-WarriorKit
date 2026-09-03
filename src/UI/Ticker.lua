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

-- The frame a tick that never stops hangs off.
--
-- A frame has one OnUpdate, and the client makes one Lua call per frame for
-- every frame that carries one. Eighteen parts of the addon armed a tick at
-- login on a private frame of their own that nothing ever hides, so twenty
-- ticks cost eighteen calls a frame before the first comparison against an
-- interval, about eleven hundred a second at 60 Hz. They hang off this one now
-- and the client makes one call.
--
-- Which frame a tick hangs off stays the caller's word rather than something
-- this file works out, because the question this file could ask is not the
-- question that matters. The probe that suggests itself is parentage: a frame
-- built with no parent is nobody's child and looks permanent. Two in the addon
-- are not. UI/Tooltip.lua and World/World.lua each build a parentless frame for
-- a tick and then Hide and Show it to gate that tick, which is the cheapest
-- gate there is and is the whole reason the frame is an argument. A rule
-- reading parentage would have turned both into ticks that run all session, and
-- it would have read nothing at all in the harness, where every frame is
-- parented to UIParent.
--
-- A word at a call site can be forgotten, so it is gated rather than trusted.
-- check.sh holds every ns.UI.Ticker whose frame is not this one in a list with
-- a reason per file, so a tick armed on a private frame fails the gate until
-- somebody writes down why that frame can hide. Forgetting the word costs an
-- entry on that list, not a tick nobody can see.
UI.Forever = CreateFrame("Frame")

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

local Ticker = {}
Ticker.__index = Ticker

-- One tick advanced by one frame's worth of time, which is the whole of what a
-- tick is. Drive below is the loop around it, and the harness drives a single
-- tick through it rather than through the frame: since every permanent tick
-- hangs off one frame, calling that frame's OnUpdate would run twenty parts of
-- the addon when a section means to run one.
function Ticker:Beat(delta)
	if not self.running then
		return
	end
	self.elapsed = self.elapsed + delta
	if self.elapsed < self.interval then
		return
	end
	-- The remainder, not zero. See the head of this file.
	local since = self.elapsed
	self.elapsed = self.elapsed - self.interval
	if self.elapsed >= self.interval then
		-- A frame longer than the interval, which is a load spike rather than a
		-- rate. Catching up would run the body twice in the frame after a
		-- stall, so the debt is dropped.
		self.elapsed = 0
	end
	ns.Perf.Start(self.name)
	self.fn(since, self.frame)
	ns.Perf.Stop(self.name)
end

local function Drive(frame, delta)
	local list = lists[frame]
	if not list then
		return
	end
	for index = 1, #list do
		-- Read here as well as inside Beat, because the list on UI.Forever holds
		-- every part that has ever armed a tick and several of them spend the
		-- session stopped. A field read is cheaper than the call it saves.
		local tick = list[index]
		if tick.running then
			tick:Beat(delta)
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

-- frame     what the tick hangs off, which decides when it stops. UI.Forever
--           above ticks for the session; a frame that goes with a window stops
--           when the window closes and there is nothing to switch off. Both are
--           wanted and neither is the default, so it is an argument.
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
	--
	-- On UI.Forever this reads the whole addon rather than one part of it,
	-- because every permanent tick is on that one list. Two parts arming a tick
	-- under the same name is two parts writing into one Perf slot, so the frame
	-- they share is the right place to catch it.
	for index = 1, #list do
		local other = list[index]
		assert(not (other.running and other.name == name),
			"a ticker named " .. name .. " is already running on this frame")
	end

	local tick = setmetatable({ -- allocates: one object per tick a part arms, built where the tick is created and never on the tick it then runs
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

-- The running tick on a frame under a name, or nil.
--
-- The frame defaults to UI.Forever, where the name is unique across the addon
-- by the assert above. It is here for the harness: a section used to reach its
-- own tick by finding the frame that part had to itself and calling the
-- OnUpdate on it, and the permanent ticks no longer have a frame each. The slot
-- they are timed under is the name they already had.
function UI.Ticking(name, frame)
	local list = lists[frame or UI.Forever]
	for index = 1, list and #list or 0 do
		local tick = list[index]
		if tick.running and tick.name == name then
			return tick
		end
	end
	return nil
end
