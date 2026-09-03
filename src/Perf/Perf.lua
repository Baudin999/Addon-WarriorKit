local ADDON, ns = ...

local Perf = {}
ns.Perf = Perf

--------------------------------------------------------------------------
-- What the addon costs
--
-- GetAddOnMemoryUsage answers one number for the whole addon, and one number
-- for the whole addon is close to useless: "WarriorKit, 341 KB" names nothing
-- you can switch off. What is worth measuring is the four tickers, because each
-- one maps to a setting on the page next to this one.
--
-- So the tickers time themselves. debugprofilestop is a millisecond clock with
-- a fractional part, two calls per tick bracket a tick body, and forty ticks a
-- second across the whole addon makes that free by any measure that matters.
-- The tab reports what it costs anyway, because a performance tab that will not
-- account for itself is asking to be believed rather than read.
--
-- Memory is the other half and it is not free. UpdateAddOnMemoryUsage walks
-- every addon the client has loaded, so it runs at 1 Hz and only while the tab
-- is actually on screen. Nothing samples memory when you are not looking at it.
--
-- Two things this cannot see, both written into the tab rather than only here.
-- The client attributes Lua allocation to an addon and nothing else, so frames
-- and textures, which live on the C side and are most of what a UI addon really
-- costs, never appear in the figure. And per-addon CPU through GetAddOnCPUUsage
-- needs the scriptProfile CVar and a reload, and it slows the whole client while
-- it is on. TitanPerformance owns that CVar in this install. This file reads the
-- number when someone else has turned it on and never turns it on itself.
--------------------------------------------------------------------------

-- Ring of recent samples per slot, so a spike is visible rather than averaged
-- away. Sized once at load and written in place forever after: an allocation on
-- a measuring path would be measuring itself.
local WINDOW = 64
local SAMPLE_RATE = 1.0

-- Declared here, in the order they are shown, because a table built per frame is
-- the thing this file exists to catch.
-- "cast" and "playercast" are the two that run on every frame beside the swing
-- bars. The first of them was named by UnitFrames/EnemyBars.lua and by the
-- performance tab and was missing from this list, so the row for it read as
-- unavailable for the whole life of the enemy cast row: Perf.Start finds no
-- slot for a key that is not here and returns without doing anything.
-- "castsweep" is the other half of "playercast". The two were one handler timed
-- as one number, and splitting the poll from the per-frame fill split the
-- measurement with it rather than reporting a fifth-of-a-second poll as
-- something that happens sixty times a second.
-- "feed" is the third that runs on every frame, and it is the cheapest of the
-- three by design: it reads one field and draws only on the frames a line
-- arrived on. Named here so the tab can say what that costs during a pull,
-- which is the question the change that put it on a tick was answering.
--
-- "skinread" and "partyread" are the other halves of "skin" and "party". Both
-- parts were one number when both were a poll; each is now a fast pass over
-- what the client said moved and a slower reading of everything, and timing the
-- pair as one would report a once-a-second reading as something that happens
-- five times a second.
--
-- Ten more of them were missing the same way, and two of those run on every
-- frame: the tooltip's own sweep and the chart's drift. A ticker whose name is
-- not here is not timed at all and its row on the tab reads as unavailable, so
-- the two most expensive shapes a tick can have were invisible on the tab
-- written to find them. scripts/check.sh compares this list against every
-- ns.UI.Ticker call in the addon now, in both directions.
local ORDER = { "marker", "swing", "icon", "action", "bars", "cast", "playercast",
	"castsweep", "tip", "chart", "skin", "skinread", "party", "partyread", "meter",
	"buffs", "cooldowns", "stream", "world", "trace", "hide", "clock", "bagstack",
	"vendor", "thanks", "sampler", "feed" }
local slots = {}
local gauges, gaugeOrder = {}, {}

local watching = false   -- the tab is on screen
local ticker             -- the sampler's own tick, kept so the tab can stop it
local lastMemory, memoryRate, memoryNow = nil, 0, 0
local selfCost = 0       -- what the bracketing itself costs, in ms per second
local clock                -- debugprofilestop, or nil where the client has none

for index = 1, #ORDER do
	local slot = {
		key = ORDER[index],
		ring = {},
		at = 0,
		count = 0,
		total = 0,
		peak = 0,
		ticks = 0,
		started = nil,
	}
	for i = 1, WINDOW do
		slot.ring[i] = 0
	end
	slots[ORDER[index]] = slot
end

--------------------------------------------------------------------------

-- Probed rather than assumed, though four addons in this install call it
-- unguarded. Absent, every timing figure reads as unavailable and the memory
-- half still works.
function Perf.Ready()
	if clock == nil then
		clock = (type(debugprofilestop) == "function") and debugprofilestop or false
	end
	return clock ~= false
end

-- Bracketed around a tick body, outside the functions HOT names, because what
-- is being measured is the whole tick and not one function inside it.
--
-- Off costs a table index and a comparison. On costs that plus two clock reads
-- and a handful of arithmetic, and no allocation in either case.
function Perf.Start(key)
	if not ns.db or not ns.db.perf or not Perf.Ready() then
		return
	end
	local slot = slots[key]
	if slot then
		slot.started = clock()
	end
end

function Perf.Stop(key)
	local slot = slots[key]
	if not slot or not slot.started then
		return
	end
	local taken = clock() - slot.started
	slot.started = nil
	if taken < 0 then
		return -- the clock wrapped, which it does on a long session
	end

	slot.at = slot.at % WINDOW + 1
	slot.total = slot.total - slot.ring[slot.at] + taken
	slot.ring[slot.at] = taken
	if slot.count < WINDOW then
		slot.count = slot.count + 1
	end
	if taken > slot.peak then
		slot.peak = taken
	end
	slot.ticks = slot.ticks + 1
end

-- A count a part wants shown beside its timing, because 0.31 ms means one thing
-- at two nameplates and another at fifteen. Registered from a Feature.lua, so
-- this file still names no part.
function Perf.Gauge(label, read)
	if gauges[label] then
		gauges[label] = read
		return
	end
	gauges[label] = read
	gaugeOrder[#gaugeOrder + 1] = label
end

--------------------------------------------------------------------------
-- Reading it back
--------------------------------------------------------------------------

-- Average over the window and the worst single tick since the last reset, both
-- in milliseconds, plus what that works out to per second of wall clock at the
-- rate this ticker actually ran.
function Perf.Slot(key)
	local slot = slots[key]
	if not slot or slot.count == 0 then
		return nil
	end
	return slot.total / slot.count, slot.peak, slot.ticks
end

function Perf.Memory()
	return memoryNow, memoryRate
end

function Perf.SelfCost()
	return selfCost
end

function Perf.Gauges()
	return gaugeOrder, gauges
end

function Perf.Reset()
	for index = 1, #ORDER do
		local slot = slots[ORDER[index]]
		slot.at, slot.count, slot.total, slot.peak, slot.ticks = 0, 0, 0, 0, 0
		for i = 1, WINDOW do
			slot.ring[i] = 0
		end
	end
	lastMemory, memoryRate = nil, 0
end

-- Only when scriptProfile is already on, which is a client wide setting with a
-- client wide cost. Answering nil is the normal case and the tab says why.
function Perf.ClientCPU()
	if type(GetAddOnCPUUsage) ~= "function" or type(UpdateAddOnCPUUsage) ~= "function" then
		return nil
	end
	if not (type(GetCVarBool) == "function" and GetCVarBool("scriptProfile")) then
		return nil
	end
	local ok = pcall(UpdateAddOnCPUUsage)
	if not ok then
		return nil
	end
	local read, used = pcall(GetAddOnCPUUsage, ADDON)
	return (read and type(used) == "number") and used or nil
end

--------------------------------------------------------------------------
-- The sampler
--
-- Runs only while the tab is on screen. This is the expensive half and it is
-- the reason there is a Watch at all: UpdateAddOnMemoryUsage walks every addon
-- the client has loaded, and doing that on a ticker that never stops would make
-- this file the most expensive thing it measures.
--------------------------------------------------------------------------

-- The allocation figure counts rises only. Lua's collector runs whenever it
-- likes and a fall in the resident number is that happening, not memory being
-- handed back by anything the addon did, so averaging the two together reports
-- a quiet addon as a busy one that gets collected often.
function Perf.Sample()
	if type(UpdateAddOnMemoryUsage) ~= "function" or type(GetAddOnMemoryUsage) ~= "function" then
		return
	end

	local before = Perf.Ready() and clock() or nil
	UpdateAddOnMemoryUsage()
	local kb = GetAddOnMemoryUsage(ADDON)
	if type(kb) ~= "number" then
		return
	end

	memoryNow = kb
	if lastMemory then
		local risen = kb - lastMemory
		memoryRate = (risen > 0) and (risen / SAMPLE_RATE) or 0
	end
	lastMemory = kb

	if before then
		-- Charged against the addon honestly: this walk is work the tab causes.
		selfCost = clock() - before
	end

	-- Set by whoever is displaying the numbers. Perf.lua does not know that a
	-- panel exists and must not: it is measured by three tickers that were here
	-- before the tab was and will outlive it.
	if Perf.OnSample then
		Perf.OnSample()
	end
end

function Perf.Watch(on)
	if watching == on then
		return false
	end
	watching = on
	if on then
		lastMemory = nil
		Perf.Sample()
		if ticker then
			ticker:Start()
		else
			-- Not timed under a slot of its own: a sampler that measured
			-- itself would be reporting the cost of the measurement.
			ticker = ns.UI.Ticker(ns.UI.Forever, SAMPLE_RATE, "sampler", Perf.Sample)
		end
	elseif ticker then
		ticker:Stop()
	end
	return true
end

function Perf.Watching()
	return watching
end
