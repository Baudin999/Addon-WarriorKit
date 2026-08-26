-- What the addon costs
--
-- The measurement has to be free or it is not a measurement. Every churn figure
-- above was taken with the brackets live, because the clock is stubbed before
-- the addon loads, so those numbers already carry the instrumentation. This
-- section proves the rest: that the counters actually move, that switching
-- timing off stops them, and that the expensive half only runs while the tab
-- is on screen.

local H = ...
local ns, check = H.ns, H.check
local barTicker = H.carry.barTicker

ns.db.perf = true
ns.Perf.Reset()
check(ns.Perf.Ready(), "the harness clock is not reaching Perf")

for _ = 1, 40 do
	barTicker.scripts.OnUpdate(barTicker, 0.05)
end
local average, peak, ticks = ns.Perf.Slot("bars")
check(ticks == 10, ("the bars ticker ran 10 times and Perf counted %s"):format(tostring(ticks)))
check(average and average > 0, "the bars ticker was timed at nothing")
check(peak and peak >= average, "the worst tick is faster than the average one")

-- Off has to mean off, not zero. A counter that keeps climbing with the
-- setting off is a cost the setting claims to have removed.
ns.db.perf = false
ns.Perf.Reset()
for _ = 1, 40 do
	barTicker.scripts.OnUpdate(barTicker, 0.05)
end
check(ns.Perf.Slot("bars") == nil, "timing kept accumulating with the setting off")
ns.db.perf = true

-- The memory walk runs on its own ticker and only while watched.
check(not ns.Perf.Watching(), "the sampler was already running with no tab on screen")
ns.Perf.Watch(true)
check(ns.Perf.Watching(), "the sampler did not start")
local held = ns.Perf.Memory()
check(held > 0, "the sampler read no memory")
ns.Perf.Watch(false)
check(not ns.Perf.Watching(), "the sampler did not stop when the tab went away")

-- And the gauge a part registered, which is what makes a millisecond figure
-- readable: 0.31 ms means one thing at two bars and another at fifteen.
local order, gauges = ns.Perf.Gauges()
check(#order > 0, "no part registered a gauge, so the timings have no denominator")
check(gauges[order[1]] ~= nil, "a gauge was ordered but never given a reader")

print(("perf   bars %.3f ms per tick over %d ticks, %.0f KB held, %d gauge%s")
	:format(average or 0, ticks or 0, held, #order, #order == 1 and "" or "s"))
