-- The gauge
--
-- ns.UI.Gauge, on its own, before either of the parts that draw one. A health
-- or power gauge in this addon is a status bar with a flat fill and the spent
-- part of it behind, and it was built two ways in two files that both ended
-- with the same pair of writes.
--
-- Four things are asserted and not one of them is visible in a screenshot. The
-- fill answers no file path, which is the whole of what flat means. The spent
-- part is a fifth of the fill's colour at nine tenths alpha, which is the pair
-- that was typed out twice and is the reason the file exists. An underlay sits
-- under the fill by draw layer rather than by frame level, which is the bug
-- that drew a full target's gauge at 28 percent of its colour. And painting is
-- free, because both callers reach it from a ticker.

local H = ...
local region, ns, check = H.region, H.ns, H.check

local Gauge = ns.UI.Gauge

-- The palette, restated rather than reached for, the same way the skin
-- section below restates it. A test that asks the file under test what the
-- answer is has not asked anything.
local TRACK, TRACK_ALPHA = ns.Unit.Color.track, 0.9

local function near(got, want)
	return got ~= nil and math.abs(got - want) < 1e-9
end
local function paints(texture, r, g, b, a)
	return texture and near(texture.r, r) and near(texture.g, g)
		and near(texture.b, b) and near(texture.a, a)
end

local bar = Gauge.New(region("frame", _G.UIParent))
local fill, track = bar:GetStatusBarTexture(), bar.track

-- A colour texture answers no file path. That readback is what the flatten
-- guard turns on, and it is also the only way to tell a flat gauge from
-- UI-StatusBar with a colour laid over it, which is what the first version
-- of this drew.
check(fill ~= nil and fill.texture == nil,
	"the gauge's fill still carries a file path, so it is not flat")
check(fill ~= nil and fill.layer == "ARTWORK",
	("the gauge's fill is on %s, and every underlay is measured against"
		.. " ARTWORK"):format(tostring(fill and fill.layer)))

local low, high = bar:GetMinMaxValues()
check(low == 0 and high == 1,
	("a fresh gauge runs %s to %s, expected 0 to 1 until a caller knows the"
		.. " unit's maximum"):format(tostring(low), tostring(high)))

check(track ~= nil and track.allPoints == bar,
	"the spent part of the gauge does not fill the bar it belongs to")
check(track ~= nil and track.layer == "BACKGROUND",
	("the spent part is on %s, which is not under the fill on any client")
		:format(tostring(track and track.layer)))

-- Nothing has painted it yet, and it carries no colour. A gauge built with
-- one would draw that colour for every frame between the build and the
-- first tick, which on a pooled widget is a black bar where a mob's health
-- is about to be.
check(track ~= nil and track.r == nil,
	"the spent part was coloured at build time, before anything painted it")

-- The pair. The fill at the colour it was handed and the spent part at a
-- fifth of it on nine tenths alpha, which is what both callers wrote by
-- hand and what one of them would have drifted on.
local safe = ns.Unit.Color.threat.safe
Gauge.Paint(bar, track, safe)
check(near(bar.barR, safe[1]) and near(bar.barG, safe[2])
	and near(bar.barB, safe[3]) and near(bar.barA, 1),
	("the fill is painted %s,%s,%s and not the %.2f,%.2f,%.2f it was handed")
		:format(tostring(bar.barR), tostring(bar.barG), tostring(bar.barB),
			safe[1], safe[2], safe[3]))
check(paints(track, safe[1] * TRACK, safe[2] * TRACK, safe[3] * TRACK, TRACK_ALPHA),
	"the spent part of the gauge is not its own colour at ns.Unit.Color.track on nine tenths alpha")

-- Through the setter the skin puts aside rather than through the no-op it
-- leaves in its place. The skin freezes SetStatusBarColor because Blizzard
-- repaints a health bar on every unit change, and a painter that did not
-- know about the freeze would write into the no-op and change nothing at
-- all. Modelled here rather than left to the unit frames below, because the
-- freeze is the half of the contract that has no picture.
bar.wkSetStatusBarColor = bar.SetStatusBarColor
bar.SetStatusBarColor = function() end
local off = ns.Unit.Color.threat.off
Gauge.Paint(bar, track, off)
check(near(bar.barR, off[1]) and near(bar.barB, off[3]),
	"a frozen bar was painted through its own no-op, so the gauge kept the last colour")
bar.SetStatusBarColor, bar.wkSetStatusBarColor = nil, nil

-- Flattening is on the skin's tick, because Blizzard's code puts
-- UI-StatusBar back and ours has to be the last word. Being the last word
-- is not the same as writing every tick: a bar that is already flat costs
-- one comparison and no write, and the write comes back the moment a file
-- path does.
local writes = fill.colorWrites
Gauge.Flatten(bar)
check(fill.colorWrites == writes,
	("flattening an already flat bar wrote %d times, expected none")
		:format(fill.colorWrites - writes))
fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
Gauge.Flatten(bar)
check(fill.texture == nil and fill.colorWrites == writes + 1,
	"the client put its own bar texture back and the gauge stayed on it")

-- Two underlays in one bar, ordered the way the skin orders its spent track
-- and its incoming heal. Inside one frame the layer settles it and no frame
-- level can argue, which is the whole reason both of them are regions of
-- the bar rather than of a rail behind it.
local under = Gauge.Underlay(bar, -8)
local over = Gauge.Underlay(bar, -7, ns.Unit.Color.heal)
check(under.layer == "BACKGROUND" and over.layer == "BACKGROUND",
	"an underlay came out on a layer a status bar's fill can be built on")
check(under.sublevel < over.sublevel,
	("the two underlays came out on sublevels %s and %s, in the wrong order")
		:format(tostring(under.sublevel), tostring(over.sublevel)))
local heal = ns.Unit.Color.heal
check(paints(over, heal[1], heal[2], heal[3], heal[4]),
	"an underlay handed a colour did not take it")

-- Painting is on a ticker in both callers, against every mob on the screen
-- and every unit frame on it. The gate is 0.05 KB rather than zero for the
-- reason the three gates at the top of this file are.
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 200 do
	Gauge.Paint(bar, track, safe)
end
local churned = collectgarbage("count") - before
collectgarbage("restart")
check(churned < 0.05,
	("painting a gauge 200 times allocated %.2f KB"):format(churned))

print(("gauge  flat fill, spent part at %.2f on %.1f alpha, layered under the"
	.. " fill, %.2f KB per 200 paints"):format(TRACK, TRACK_ALPHA, churned))
