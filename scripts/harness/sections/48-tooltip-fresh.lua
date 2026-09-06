-- Keeping an open box true
--
-- A tooltip in this addon was built once, at the moment the pointer arrived,
-- and never again. What that costs is invisible on any single hover: it is a
-- threat percentage that was right when you got there and wrong for the rest of
-- the pull, a quest count that does not move when you loot the thing. The
-- complaint it produces is that the addon's tooltips are slow, and they were
-- not slow. They were never redrawn.
--
-- Its own section rather than a block at the foot of 48-tooltips.lua, which is
-- the subject next door and full. What is asserted here is not what a box says
-- but when it is asked again, and the two halves of that are one claim:
--
--   A box is built again when something in it moved. Without this half there is
--   no feature.
--
--   A box is not built again when nothing in it did. Without this half there is
--   a feature that costs a rebuild sixty times a second for as long as anybody
--   reads anything, which is what rebuilding on a tick would have been and is
--   the reason the stamp exists at all.
--
-- The churn reading is the second half measured rather than asserted. A pass
-- that allocates is a pass the collector has to walk later, and the collector
-- runs in the middle of a frame.

local H = ...
local ns, check = H.ns, H.check

do
	local Tip, Box, Fresh = ns.Tip, ns.UI.Tooltip, ns.UI.Fresh
	local owner = CreateFrame("Frame", nil, _G.UIParent)
	owner:SetSize(30, 30)
	owner:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)

	-- What the stamped source below reports, moved by hand. A number the section
	-- owns rather than a client fixture, because what is under test is the
	-- mechanism and not any one part's idea of what makes its line stale.
	local moves = 0

	Tip.Source({
		name = "harness stamp",
		kind = "note",
		band = "extra",
		order = 9903,
		fill = function(subject)
			return subject.stamped and { { "Moved", tostring(moves) } } or nil
		end,
		-- Constant for every other note in the run. This source stays registered
		-- for the rest of the harness, so every note hovered after this line
		-- arms the tick and rebuilds nothing, which is exactly what a stamped
		-- source over a still subject is supposed to cost.
		stamp = function(subject)
			return subject.stamped and moves or 0
		end,
	})

	-- A subject nothing holds a stamp for arms no tick at all. Most hovers in
	-- the addon are that: a settings hint, a filter chip, a tab. A tick running
	-- behind every one of them is the cost the arm exists to refuse.
	Tip.Open(owner, { kind = "item", link = "|cffffffff|Hitem:1:0:0:0|h[Rock]|h|r" })
	check(not Fresh.Watching(), "a hover with no stamp anywhere in it armed the refresh")

	Tip.Open(owner, { kind = "note", title = "Watched", stamped = true })
	check(Fresh.Watching(), "a hover carrying a stamped source did not arm the refresh")
	check(Box.Text(2) == "Moved", "the stamped source's line did not land")
	Fresh.Rebuilds()

	------------------------------------------------------------------
	-- Nothing moved
	------------------------------------------------------------------

	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 50 do
		Fresh.Sweep()
	end
	local churned = collectgarbage("count") - before
	collectgarbage("restart")

	check(Fresh.Rebuilds() == 0,
		"fifty ticks over a box whose stamp never moved built it again anyway")
	check(churned < 0.05,
		("fifty ticks over a still box churned %.2f KB"):format(churned))
	local label, value = Box.Text(2)
	check(label == "Moved" and value == "0",
		"fifty ticks with nothing moving changed what the box says")

	------------------------------------------------------------------
	-- Something moved
	------------------------------------------------------------------

	moves = 7
	Fresh.Sweep()
	check(Fresh.Rebuilds() == 1,
		"the stamp moved and the box was not built again on that tick")
	local _, moved = Box.Text(2)
	check(moved == "7",
		"the box was built again and did not pick up the figure that moved")

	-- Once, not once per tick from here on. A stamp that moved and was not
	-- written back would rebuild for the rest of the hover, which reads as
	-- working and is the expensive failure this whole mechanism is against.
	for _ = 1, 10 do
		Fresh.Sweep()
	end
	check(Fresh.Rebuilds() == 0,
		"a stamp that moved once was still rebuilding ten ticks later")

	Tip.Close(true)
	check(not Fresh.Watching(), "closing the box left the refresh running")

	print(("fresh  %s; 50 ticks on a still box rebuilt it 0 times and churned %.2f KB")
		:format(Fresh.Describe(), churned))
end
