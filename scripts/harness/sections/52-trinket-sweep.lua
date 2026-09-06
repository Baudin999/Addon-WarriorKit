-- The wait on a slot you press
--
-- Two trinkets, an engineering helm and a weapon with a use on it are the slots
-- the gear page answers this for, and the sheet is where a player checks whether
-- the trinket they are about to pull with is off cooldown. The page reads it
-- through ns.InventoryCooldown, which had been written and probed and called by
-- nothing here, and draws it as an arc of the disc's own ring.
--
-- **The arc is the thing this section exists for and it is invisible to a frame
-- reading.** A wedge is two half discs and two masks that turn, and every one of
-- those is a call the client answers nothing about. Four ways of getting it
-- wrong draw a shape and measure perfectly: two whole discs rather than two
-- halves, a mask turning about its own middle, which is a band across the disc
-- rather than a wedge out of it, both masks moving at once, which is two edges
-- sweeping in opposite directions, and an arc on the wrong draw layer, which is
-- either under the colour it is meant to cover or over the picture. So the
-- texture coordinates, the pivot, the pair of rotations and the layer are read
-- back one at a time.
--
-- **Only a slot with something you press in it.** A passive trinket carries a
-- cooldown of its own for its proc, and a ring going dark on a trinket nobody
-- can spend is the page saying wait about nothing. The neck is the control: a
-- worn item, no use effect, no arc ever built for it.
--
-- **The tick has two switches and both are checked.** It hangs off
-- ns.UI.Forever, the way the oil count on the same page does and for the reason
-- that file gives, so nothing hides it for us. What is in a slot is the first
-- switch and it is thrown by the repaint: a character wearing nothing with a
-- use on it arms no tick at all. Whether anybody is looking is the second and
-- it is a comparison at the top of the tick, because the page's own frame is
-- shown from the moment it is built and never taken down again.
--
-- What this cannot prove: that a dark band round a disc reads as a wait. The
-- pixels are a vertex colour and a mask, and the stub answers about both without
-- drawing either.

local H = ...
local ns, check = H.ns, H.check
local own, worn, advance = H.own, H.worn, H.advance
local itemLink, CHURN = H.itemLink, H.CHURN

local Window = ns.CharWindow

-- The wait this section runs down, long enough that a quarter of it is a
-- rotation nobody has to squint at and short enough to spend in four steps.
local WAIT = 120
local TAU = math.pi * 2

-- The sweep's own tick, by the ns.Perf slot it is timed under, the same way
-- 42-cooldown-row.lua reaches the row's.
local function ticker()
	return ns.UI.Ticking("trinket")
end

local function beat()
	local running = ticker()
	if running then
		running:Beat(0.25)
	end
end

local function square(slot)
	for _, box in ipairs(Window.Pane().squares) do
		if box.entry.slot == slot then
			return box
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Which slots get one
----------------------------------------------------------------------

Window.Show()

local brooch = square(13)
local neck = square(2)
check(brooch ~= nil and neck ~= nil,
	"the page drew no trinket slot or no neck slot, so nothing below is measured")
check(ns.ItemSpell(worn[13]) ~= nil,
	("the trinket fixture answers %q for a use effect, so it is not a thing you press")
		:format(tostring(ns.ItemSpell(worn[13]))))

check(brooch.use and brooch.arc ~= nil,
	"the trinket you press carries no arc, so the page still says nothing about its cooldown")
check(not neck.use and neck.arc == nil,
	"a worn item with no use effect was given an arc, so the page says wait about a thing nobody can spend")

----------------------------------------------------------------------
-- What an arc is made of
--
-- Every check here is one that draws a shape and passes a frame reading. The
-- head of this file lists the four.
----------------------------------------------------------------------

do
	local arc = brooch.arc
	check(arc[1] ~= nil and arc[2] ~= nil and arc.masks ~= nil,
		"the arc came out with fewer than two halves or no masks at all, so it can only ever be a whole disc")

	-- Two halves of one disc, not two discs. The first is the right hand half of
	-- the file and the second the left, which is what puts their straight edges
	-- together down the middle of the ring.
	check(arc[1].texcoord and arc[1].texcoord[1] == 0.5 and arc[1].texcoord[2] == 1,
		"the first half of the arc is the whole disc rather than its right hand side")
	check(arc[2].texcoord and arc[2].texcoord[1] == 0 and arc[2].texcoord[2] == 0.5,
		"the second half of the arc is the whole disc rather than its left hand side")

	-- Between the ring and the icon. Under the icon or the arc covers the
	-- picture; over the ring or the quality colour it is meant to hide shows
	-- through it.
	check(arc[1].layer == "BORDER" and brooch.ring.layer == "BACKGROUND"
		and brooch.icon.layer == "ARTWORK",
		("the arc draws on %s between a ring on %s and an icon on %s")
			:format(tostring(arc[1].layer), tostring(brooch.ring.layer),
				tostring(brooch.icon.layer)))

	-- Each half is cut by a mask of its own, and both are the same rectangle.
	for index = 1, 2 do
		local half, mask = arc[index], arc.masks[index]
		check(half.masks and #half.masks == 1 and half.masks[1] == mask,
			("half %d of the arc is not cut by its own mask, so it draws whole for the whole wait")
				:format(index))
	end
end

----------------------------------------------------------------------
-- The wait running down
--
-- The pivot and the pair of rotations, which between them are the whole of
-- whether this is a wedge. A mask turning about its own middle sweeps a band
-- across the disc and both ends of it move, which is a shape nothing here would
-- otherwise notice.
----------------------------------------------------------------------

local arc = brooch.arc
local started = _G.GetTime()

do
	own.worn[13] = { started, WAIT }
	beat()

	check(arc.at == 1 and arc[1]:IsShown() and arc[2]:IsShown(),
		("the wait had just begun and the arc reads %s of the ring")
			:format(tostring(arc.at)))

	local pivot = arc.masks[1].pivot
	check(pivot ~= nil and pivot.x == 0 and pivot.y == 0.5,
		"a mask turns about its own middle rather than the middle of the disc, so the sweep is a band across the ring")

	-- The first half holds the moving edge through the first half of the wait
	-- and the second sits at half a turn, which is what keeps one edge on the
	-- ring rather than two.
	local parked = arc.masks[2].rotation
	advance(WAIT / 4)
	beat()
	check(math.abs(arc.at - 0.75) < 0.01,
		("a quarter of the wait went by and the arc reads %.3f"):format(arc.at))
	check(math.abs(arc.masks[1].rotation - 0.75 * TAU) < 0.01,
		("the first mask turned to %.3f and a quarter spent is three quarters of a turn")
			:format(arc.masks[1].rotation))
	check(arc.masks[2].rotation == parked,
		"both masks moved through the first half of the wait, so the ring has two edges sweeping at once")

	-- Half spent, and the boundary is exactly on the middle: the first half of
	-- the disc is gone and the second is whole.
	advance(WAIT / 4)
	beat()
	check(math.abs(arc.masks[1].rotation - arc.masks[2].rotation) < 0.01,
		"half the wait went by and the two masks are not on the same line, so the wedge has a step in it")

	-- And the second half of the wait is the second mask's, which is the half
	-- that was never exercised while the first one was doing all the work.
	advance(WAIT / 4)
	beat()
	check(math.abs(arc.masks[2].rotation - 0.25 * TAU) < 0.01,
		("the second mask turned to %.3f and three quarters spent is a quarter of a turn")
			:format(arc.masks[2].rotation))
end

----------------------------------------------------------------------
-- The end of it, and the passes with nothing to say
----------------------------------------------------------------------

do
	advance(WAIT / 4)
	beat()
	check(arc.at == 0 and not arc[1]:IsShown() and not arc[2]:IsShown(),
		("the wait ended and the arc still draws %s of the ring"):format(tostring(arc.at)))

	-- A pass that has not moved the boundary a pixel writes nothing, which is
	-- most of them: four a second against a two minute wait is a quarter of a
	-- pixel a pass. Read off UI.Sweep rather than off the mask, because a
	-- redundant SetRotation lands on the same number and no reading of the mask
	-- afterwards can tell the two apart.
	--
	-- Pinned from both sides. A gate that only asks whether a small move is
	-- dropped passes just as well on an arc that never moves at all.
	own.worn[13] = { _G.GetTime(), WAIT }
	beat()
	check(ns.UI.Sweep(arc, arc.at) == false,
		"the arc rewrote itself for a wait that had not moved at all")
	check(ns.UI.Sweep(arc, arc.at - 1 / 512) == false,
		"a quarter of a pixel of movement was written, so the tick redraws the same picture four times a second")
	check(ns.UI.Sweep(arc, arc.at - 1 / 128) == true,
		"a whole pixel of movement was dropped, so the arc sticks rather than sweeps")
end

----------------------------------------------------------------------
-- What the tick costs
----------------------------------------------------------------------

local churned, swept
do
	local tick = H.tick("trinket")
	collectgarbage("collect")
	collectgarbage("stop")
	local start = collectgarbage("count")
	for _ = 1, 50 do
		tick:Beat(0.25)
	end
	churned = collectgarbage("count") - start
	collectgarbage("restart")
	check(churned < CHURN.trinket,
		("the sweep churned %.2f KB over 50 ticks, gate is %.2f")
			:format(churned, CHURN.trinket))
end

----------------------------------------------------------------------
-- When it stops
--
-- Nothing hides ns.UI.Forever, so both switches are the page's own and neither
-- covers the other: gear decides whether the tick is armed at all and the
-- window decides whether an armed one writes anything.
----------------------------------------------------------------------

do
	check(ticker() ~= nil,
		"the sheet is open over a trinket you press and the sweep is not running")

	own.worn[13] = nil
	worn[13] = nil
	Window.Pane():Paint()
	check(ticker() == nil,
		"the last thing you can press came off and the sweep is still running four times a second")

	-- Back on, so the last check is about the window rather than about the slot,
	-- and so the scene the section after this one finds is the one it was handed.
	worn[13] = itemLink("Bloodlust Brooch")
	Window.Pane():Paint()
	check(ticker() ~= nil, "the trinket went back on and the sweep did not start again")
	swept = Window.Pane():Cooling()

	-- And nothing at all while the sheet is shut, which is a different claim
	-- from the one above it: the tick stays armed and has to find out for itself
	-- that nobody is looking. The page's own frame is shown from the moment it
	-- is built and never taken down again, because it holds nineteen secure
	-- buttons and hiding one of those in a fight is a protected act, so a tick
	-- reading that flag would sweep all session on a page nobody can see. The
	-- arc is poked to a value it can never hold and the tick is given something
	-- to draw, which is the only way to tell a pass that wrote nothing from one
	-- that wrote the same thing.
	Window.Hide()
	own.worn[13] = { _G.GetTime(), WAIT }
	arc.at = -1
	beat()
	check(arc.at == -1,
		"the tick wrote on a disc nobody can see, so it is reading the page's own flag rather than the window's")
	own.worn[13] = nil
end

print(("trinket %d slot of %d sweeps, an arc of two halves turning about the middle of the disc; %.2f KB per 50 ticks, gate is %.2f")
	:format(swept, #Window.Pane().squares, churned, CHURN.trinket))
