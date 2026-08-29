-- bars zoom actually scales the bar
--
-- It did not, for the whole life of the setting. Every design number in
-- LayoutWidget was multiplied by ns.Pixel(widget), which on the grid is 1/zoom,
-- and the scale the zoom put on the frame multiplied it straight back. The bar
-- measured 180 by 62 screen pixels at zoom 1, 2 and 3 alike, fonts included.
--
-- Nothing caught it because every assertion in this file was written in the
-- widget's own units, and in those units the bar really does change: it is half
-- as many units at 2x on twice the scale, which is the same picture. The only
-- way to see it is to convert to screen pixels and compare against what the
-- design asked for, which is what this does.
--
-- The hairline is deliberately not scaled. An edge is one screen pixel at every
-- zoom, the rule UI/Window.lua already follows for every rule in the options
-- window, so the box is the gauge plus two pixels rather than the gauge times
-- the zoom.

local H = ...
local frames, cvars, plateSize = H.frames, H.cvars, H.plateSize
local ns, check = H.ns, H.check
local widget = H.carry.widget

do
	local shipped = ns.db.barsZoom
	local function screen(frame, units)
		return units / ns.UI.Pixel(frame)
	end
	local function at(zoom)
		ns.db.barsZoom = zoom
		ns.EnemyBars.ApplyLayout()
		ns.EnemyBars.Rebuild()
	end

	local widthAtOne
	for _, zoom in ipairs{1, 2, 3} do
		at(zoom)

		local wide = screen(widget, widget:GetWidth())
		local gauge = screen(widget, widget.box:GetHeight())
		local icon = screen(widget, widget.icons[1]:GetWidth())
		local hair = screen(widget, widget.box.edges[1].height)
		if zoom == 1 then
			widthAtOne = wide
		end

		check(math.abs(wide - ns.db.barsWidth * zoom) < 1e-6,
			("at %dx the bar is %.1f screen pixels wide, the design asked for %d")
				:format(zoom, wide, ns.db.barsWidth * zoom))
		check(math.abs(gauge - (22 * zoom + 2)) < 1e-6,
			("at %dx the gauge box is %.1f screen pixels, expected %d")
				:format(zoom, gauge, 22 * zoom + 2))
		check(math.abs(icon - ns.db.barsIconSize * zoom) < 1e-6,
			("at %dx a debuff square is %.1f screen pixels, the design asked for %d")
				:format(zoom, icon, ns.db.barsIconSize * zoom))
		check(math.abs(hair - 1) < 1e-6,
			("at %dx the hairline is %.2f screen pixels, not one"):format(zoom, hair))

		for _, measure in ipairs{wide, gauge, icon} do
			check(math.abs(measure - math.floor(measure + 0.5)) < 1e-6,
				("at %dx something came out %.3f screen pixels"):format(zoom, measure))
		end

		-- The assertion the old code would have failed, stated on its own so the
		-- failure reads as "the zoom does nothing" rather than as a size being
		-- off by a bit.
		if zoom == 3 then
			check(math.abs(wide - widthAtOne) > 1e-6,
				("the bar is %.1f screen pixels wide at both 1x and 3x, so the zoom does nothing")
					:format(wide))
		end
	end

	at(3)
	print(("zoom   bar %.0f px wide at 1x and %.0f at 3x, icon %.0f px, hairline stays 1 px")
		:format(widthAtOne, screen(widget, widget:GetWidth()),
			screen(widget, widget.icons[1]:GetWidth())))
	at(shipped)
end

-- Rebuilt several times by the section above, so the reference the checks below
-- use is taken again rather than assumed to have survived.
widget = ns.EnemyBars.WidgetFor("nameplate1")
check(widget ~= nil, "no bar on nameplate1 after the zoom sweep")

-- The driver has been told how much room a bar wants.
check(cvars.nameplateMotion == "1", "nameplates were not asked to stack")
check(plateSize[1] ~= nil, "the plate size was never set")

-- How far out a plate goes up, which is how far out a bar can be seen at all.
check(cvars.nameplateMaxDistance == tostring(ns.db.barsDistance),
	("the range was asked for as %s and the client holds %s")
		:format(tostring(ns.db.barsDistance), tostring(cvars.nameplateMaxDistance)))
check(ns.Plates.Distance() == ns.db.barsDistance,
	"Plates.Distance does not read back what was written")

-- The range the setting offers is the range the client will hold.
--
-- It was not. The stepper went to 60 on a client that stops at 41, and 41 is
-- also where that client starts, so every press of "+" from the shipped figure
-- moved the number in the panel and nothing in the world: SetCVar clamps and
-- answers true. The cap is asked for rather than written down, so the check
-- asks the same way.
do
	local shipped = ns.db.barsDistance
	local low, high = ns.Plates.DistanceRange()

	check(low < high, ("the range came back as %s to %s"):format(tostring(low), tostring(high)))
	check(high == 41, ("this client stops at 41 yards and the setting offers %s")
		:format(tostring(high)))

	ns.db.barsDistance = 60
	ns.Plates.Apply()
	check(ns.db.barsDistance == high,
		("asked for 60 yards on a client that stops at %d and the setting kept %s")
			:format(high, tostring(ns.db.barsDistance)))
	check(ns.Plates.Distance() == high,
		("the client holds %s after being asked for 60"):format(tostring(ns.Plates.Distance())))
	check(ns.Plates.DescribeDistance():find("as far as this client goes", 1, true) ~= nil,
		"at the ceiling the readout does not say it is the ceiling: "
			.. ns.Plates.DescribeDistance())

	-- Downwards still moves, which is the half of the setting that works.
	ns.db.barsDistance = 25
	ns.Plates.Apply()
	check(ns.Plates.Distance() == 25,
		("asked for 25 yards and the client holds %s"):format(tostring(ns.Plates.Distance())))

	ns.db.barsDistance = shipped
	ns.Plates.Apply()
	print(("plates  range %d to %d yards, the top asked of the client rather than assumed")
		:format(low, high))
end

-- The plate is the frame the game hit-tests, so it has to hold the whole bar
-- and not merely be as tall as one. The bar hangs off the plate's centre by the
-- gauge, which puts more of it above that centre than below, and a plate sized
-- to the bar's own height would leave the debuff row hanging over nothing: a
-- click there would target the ground.
--
-- Measured in UIParent's units on both sides, because that is what the driver
-- was told in.
do
	local half = ns.UI.Convert(widget.gaugeMid, widget, _G.UIParent)
	local rest = ns.UI.Convert(widget:GetHeight() - widget.gaugeMid, widget, _G.UIParent)
	check(plateSize[2] >= half * 2 - 1e-6,
		("the plate is %.1f tall and the bar reaches %.1f above the point it hangs from")
			:format(plateSize[2], half))
	check(plateSize[2] >= rest * 2 - 1e-6,
		("the plate is %.1f tall and the bar reaches %.1f below the point it hangs from")
			:format(plateSize[2], rest))
	check(plateSize[1] >= ns.UI.Convert(widget:GetWidth(), widget, _G.UIParent) - 1e-6,
		"the plate is narrower than the bar on it, so a click near either end misses")
end

-- Allocation. Every ticker but the bars' is somebody else's measurement.
local barTicker
for _, f in ipairs(frames) do
	if f.scripts.OnUpdate and f.origin:match("EnemyBars") then
		barTicker = f
	end
end
check(barTicker ~= nil, "the enemy bars registered no ticker")

local function churn(n)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, n do
		barTicker.scripts.OnUpdate(barTicker, 0.05)
	end
	local after = collectgarbage("count")
	collectgarbage("restart")
	return after - before
end

-- Cold first, because the first pass interns every label the bars will ever
-- show and that is a one time cost, not a per tick one.
churn(200)
local plateChurn = churn(200)

-- Left for the sections below.
H.carry.barTicker, H.carry.churn, H.carry.plateChurn = barTicker, churn, plateChurn
H.carry.widget = widget
