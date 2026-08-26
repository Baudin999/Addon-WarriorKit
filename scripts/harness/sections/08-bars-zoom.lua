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
