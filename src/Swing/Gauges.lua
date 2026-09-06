local ADDON, ns = ...

local SwingGauges = {}
ns.SwingGauges = SwingGauges

--------------------------------------------------------------------------
-- Two bars and a mark
--
-- One gauge per hand, drawn with ns.UI.Gauge on the pixel grid, and the Slam
-- band drawn over the main hand one. No window round them, no text on them and
-- no chrome at all, for the reason Meter/Window.lua carries: this is read out
-- of the corner of your eye during a pull and every pixel of frame around it
-- is a pixel of the fight it stands on.
--
-- The bar counts in pixels rather than in a fraction from zero to one, so the
-- band, the mark and the fill are all measured in the same units. That is what
-- makes "press on the mark" mean anything: a band at 70.4 percent of a 180
-- pixel bar and a mark at 70.6 percent of it are the same pixel and the eye
-- cannot tell which side of the line it is on.
--
-- The band and the mark land on whole pixels. The fill does not, and this file
-- is where the addon's two pixel rules first disagree. Both are in
-- docs/README.md and both are gated in scripts/harness.lua.
--
-- A static edge lands on a whole pixel. A border, an icon crop or a band drawn
-- across two rows of pixels reads as blurry, and blurry is what the grid exists
-- to stop. The band and the mark move only when your weapon speed does, which
-- is a few times a fight, so they are static edges.
--
-- A moving fill is not quantised. What the eye reads on a moving edge is its
-- velocity, and velocity lives in where the edge sits between two pixels as
-- much as in which pixel it is on. Rounding throws that away to buy a sharpness
-- nobody can see on something in motion, and rounding is also a throttle: the
-- fill crosses 180 units in a 3.4 second swing, so a rounded fill changes value
-- 53 times a second and no oftener, whatever rate the tick runs at. It stands
-- still on 7 of the 60 frames a 60 Hz screen draws and on 91 of the 144 a fast
-- one draws, and each move is a whole unit, which is three screen pixels at
-- swing zoom 3. Deleting the 20 Hz ticker raised the drawn rate from 20 to 53
-- and left that second throttle standing, which is why the bar still stepped
-- after the first repair.
--
-- So the fill is written as a fraction, on every frame a hand is swinging, with
-- no comparison in front of it except the one that catches a hand that is not.
-- What that costs was measured rather than argued: the harness reads 0.03 KB
-- per fifty ticks rounded and guarded, and 0.03 unguarded.
--
-- Every other part of this addon draws on a ticker, because every other part is
-- a readout and a readout fifty milliseconds stale is one nobody can fault.
-- This one is an animation, and an animation is drawn on the frame the screen
-- is drawn on or it is drawn in steps.
--
-- Mouse only while unlocked, the same as the meters and the charge icon, and
-- for the same reason: a mouse enabled frame swallows the right button drag
-- that turns the camera, and this sits under the middle of the screen where
-- that drag starts.
--------------------------------------------------------------------------

local Gauge = ns.UI.Gauge

local FRAME_NAME = "WarriorKitSwing"

-- One bar to the next. One pixel would put two hairlines against each other
-- and read as a single thick line between the bars.
local GAP = 2

-- Gold for the hand that carries the abilities, steel for the one that does
-- not, so the two are told apart by colour rather than by position. Both sit
-- where a health bar does not, because a bar under the middle of the screen in
-- red or green would read as somebody's health.
local MAIN_FILL = { 0.86, 0.72, 0.30 }
local OFF_FILL = { 0.42, 0.60, 0.86 }

-- What the main hand gauge becomes while the press is on. A colour flip on the
-- whole bar rather than only a band, because the band is four percent of the
-- screen area of the bar and the flip is all of it, and this is the one moment
-- the feature exists for.
local NOW_FILL = { 0.34, 0.86, 0.44 }

local BAND = { 0.34, 0.86, 0.44, 0.40 }
local MARK = { 1, 1, 1, 0.85 }

local EDGE_QUIET = { 0.10, 0.10, 0.12, 1 }
local EDGE_NOW = { 0.40, 0.94, 0.52, 1 }

local frame, main, off, place
local built = false
local dual = false

-- The frame the events and the tick hang off, and the tick itself. Declared
-- here rather than at the foot of the file because SwingGauges.Apply is what
-- arms and stops the tick and is written above where they are made.
local events, tick

-- One pixel of the design in this frame's units, which is exactly 1 once
-- ns.UI.Adopt has taken the frame onto the grid. Read again in every layout
-- pass rather than only at login: on a client with no SetIgnoreParentScale the
-- answer is a fraction of the screen height, and a monitor swap moves it under
-- a value read once.
local unit = 1

local Whole = ns.UI.Whole

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

local function BuildBar(parent, fill, banded)
	local bar = Gauge.New(parent)
	Gauge.Paint(bar, bar.track, fill)
	bar.color = fill

	-- No width until the layout has given it one. Not 1: a bar counting to one
	-- pixel draws a whole swing in two positions, empty and full, which reads
	-- as a bar that teleports rather than as a bar that has not been laid out.
	bar.pixels = 0

	-- The band and the press line are the main hand's alone, drawn on OVERLAY
	-- so they sit over the fill rather than under it. The fill is ARTWORK and a
	-- band on the same layer would be covered by whatever the status bar drew
	-- last.
	if banded then
		bar.band = ns.Fill(bar, "OVERLAY", BAND[1], BAND[2], BAND[3], BAND[4])
		bar.band:Hide()
		bar.mark = ns.Fill(bar, "OVERLAY", MARK[1], MARK[2], MARK[3], MARK[4])
		bar.mark:Hide()
	end

	-- The border is made last, because within one draw layer the order is the
	-- order the textures were made and the band runs the full height of the
	-- bar. Built first, the edge would vanish behind the band for exactly the
	-- span of screen the band exists to draw attention to.
	bar.edges = ns.Outline(bar, EDGE_QUIET[1], EDGE_QUIET[2], EDGE_QUIET[3], 1, "OVERLAY")
	return bar
end

--------------------------------------------------------------------------
-- Layout
--
-- Everything a setting can move. Called at login, whenever a number in the
-- panel changes, and whenever the client says a hand has changed. Never from
-- the tick.
--------------------------------------------------------------------------

local function SizeBar(bar, width, height)
	bar.pixels = width
	bar:SetSize(width * unit, height * unit)
	bar:SetMinMaxValues(0, width)
	bar:SetValue(0)
	bar.shownValue = 0
	-- The hairline is one screen pixel and stays one when the zoom grows, which
	-- is what ns.Pixel answers and ns.UI.Unit does not. The mark inside the
	-- band is the other kind: it is a design pixel and grows with the bar,
	-- because a press mark you cannot see is not a mark.
	ns.EdgeSize(bar.edges, ns.Pixel(bar))
end

-- The frame and the two bars, made the first time the swing timer is switched
-- on.
--
-- The part ships off. It was built at login anyway, and its ticker was armed at
-- interval zero, so a feature nobody had turned on ran a function on every frame
-- the client drew for the whole session to find out it had nothing to draw.
local function Build()
	frame = CreateFrame("Frame", FRAME_NAME, UIParent)
	ns.UI.Adopt(frame, ns.db.swingZoom)
	-- And it stands down while a screen window is up. UI/Hush.lua carries the
	-- whole of what that means; what it means here is that the character sheet
	-- is read against the world rather than against this row.
	ns.UI.Hushable(frame)
	unit = ns.UI.Unit(frame)
	place = ns.UI.Placeable(frame, {
		name = "WarriorKit swing",
		moved = function(anchor)
			ns.db.swingPoint = anchor
			SwingGauges.Apply()
		end,
	})

	main = BuildBar(frame, MAIN_FILL, true)
	main:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	off = BuildBar(frame, OFF_FILL)
	-- Anchored after both bars exist, because the off hand hangs off the main
	-- hand's bottom edge and the gap between them is a design number rather than
	-- a share of anything.
	off:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, -GAP * unit)
	built = true
end

-- The tick, armed by the switch going on and stopped by it going off.
--
-- It lives on the events frame, which is never hidden. On the gauges it would
-- stop the moment the bars hid and never come back, which is the trap
-- Charge/Icon.lua already carries a note about, and Update's first line is what
-- makes a hidden pair of bars free.
--
-- ns.UI.Ticker refuses a second running tick of one name on one frame, so the
-- tick is kept here and started again rather than made again.
local function Beat()
	if ns.db.swing then
		if not tick then
			tick = ns.UI.Ticker(ns.UI.Forever, 0, "swing", SwingGauges.Update)
		elseif not tick:Running() then
			tick:Start()
		end
	elseif tick then
		tick:Stop()
	end
end

function SwingGauges.Apply()
	if not built then
		if not ns.db.swing then
			return
		end
		Build()
	end

	local db = ns.db
	local point = db.swingPoint
	frame:ClearAllPoints()
	frame:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	ns.UI.Rezoom(frame, db.swingZoom)
	unit = ns.UI.Unit(frame)

	local width, height = db.swingWidth, db.swingHeight
	dual = ns.Swing.HasOffhand()

	SizeBar(main, width, height)
	SizeBar(off, width, height)
	off:SetShown(dual)
	main.shownOpen, main.shownClose, main.shownMark, main.shownNow = nil, nil, nil, nil

	local total = dual and (height * 2 + GAP) or height
	frame:SetSize(width * unit, total * unit)

	Beat()
	SwingGauges.Lock()
	SwingGauges.Show()
end

-- Whether there is a swing worth drawing on this character right now. The bars
-- are gated on a weapon rather than on a class, so a hunter in melee gets
-- them; the Slam band on top of them is gated on Slam, which is warrior only.
function SwingGauges.Applicable()
	return ns.Swing.Ready() and ns.Swing.HasMainhand()
end

function SwingGauges.Show()
	if not built then
		return
	end
	if ns.db.swing and (SwingGauges.Applicable() or not ns.db.locked) then
		frame:Show()
	else
		frame:Hide()
	end
end

-- Locked is the normal state. Unlocked draws an outline and a name, because
-- two thin bars with nothing in them are a piece of empty screen you would
-- otherwise have to find by memory.
function SwingGauges.Lock()
	if not built then
		return
	end
	place:Lock(not ns.db.locked)
	SwingGauges.Show()
end

function SwingGauges.Reset()
	ns.db.swingPoint = ns.DefaultCopy("swingPoint")
	SwingGauges.Apply()
end

-- The two bars, for scripts/harness.lua and for a macro. Handed out rather
-- than kept private for the reason MeterWindow.Pane is: the harness has to
-- measure what was drawn, and measuring it any other way would mean this file
-- publishing its own frame.
function SwingGauges.Bar(which)
	return (which == ns.Swing.OFF) and off or main
end

--------------------------------------------------------------------------
-- Painting
--
-- Everything below runs on every frame and nothing below allocates. Every
-- write to the band, the mark and the colours is guarded on what is already on
-- the widget, because those are static edges that change a few times a swing.
-- The fill is guarded on the one value it repeats, which is the empty bar
-- between two swings.
--------------------------------------------------------------------------

-- Fraction returns zero for a hand with no swing running, so a bar between
-- swings draws empty without a branch here.
--
-- The one comparison is the empty bar. A hand that is not swinging answers zero
-- on every frame for as long as you stand there, and writing zero onto a bar
-- already at zero is a measure and a relayout for a bar nobody can see moving.
-- A hand that is swinging fails the test on its first frame and is written on
-- every frame after it, which is what the header above argues for: the velocity
-- of the edge is read out of where it sits between two pixels, and a frame it
-- does not write is a frame it does not move on.
local function DrawHand(bar, which)
	local value = ns.Swing.Fraction(which) * bar.pixels
	if value ~= 0 or bar.shownValue ~= 0 then
		bar.shownValue = value
		bar:SetValue(value)
	end
end

-- The band, the line down the middle of it, and the colour of the whole gauge
-- while the fill is inside. All three come off one call, because two calls
-- could disagree about where the window is and the disagreement would be a bar
-- that flips colour a pixel away from its own mark.
local function DrawWindow(bar)
	local open, close, at = ns.Slam.Window()
	if not open then
		if bar.shownOpen ~= false then
			bar.shownOpen, bar.shownMark = false, nil
			bar.band:Hide()
			bar.mark:Hide()
		end
		if bar.shownNow ~= false then
			bar.shownNow = false
			ns.Recolor(bar.edges, EDGE_QUIET)
			Gauge.Paint(bar, bar.track, bar.color)
		end
		return
	end

	local width = bar.pixels
	local left = Whole(open * width)
	local right = Whole(close * width)
	if right <= left then
		right = left + 1
	end

	-- The line is compared as well as the two edges. Two windows a hair apart
	-- round to the same pair of edges and to two different lines, and guarded on
	-- the edges alone the band would be right and the line inside it stale.
	local line = Whole(at * width)
	if line < left then
		line = left
	end
	if line > right then
		line = right
	end

	if bar.shownOpen ~= left or bar.shownClose ~= right or bar.shownMark ~= line then
		bar.shownOpen, bar.shownClose, bar.shownMark = left, right, line
		bar.band:ClearAllPoints()
		bar.band:SetPoint("TOPLEFT", bar, "TOPLEFT", left * unit, 0)
		bar.band:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", left * unit, 0)
		bar.band:SetWidth((right - left) * unit)
		bar.band:Show()
		bar.mark:ClearAllPoints()
		bar.mark:SetPoint("TOPLEFT", bar, "TOPLEFT", line * unit, 0)
		bar.mark:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", line * unit, 0)
		bar.mark:SetWidth(unit)
		bar.mark:Show()
	end

	-- Inside the band, measured against the band's own drawn edges rather than
	-- against the fractions they were rounded from. The bar flips the instant
	-- the fill reaches the green the player is aiming at, which is the only
	-- reading of "inside" that matches what is on the screen.
	local now = bar.shownValue >= left and bar.shownValue <= right
		and ns.Swing.Armed(ns.Swing.MAIN)
	if bar.shownNow ~= now then
		bar.shownNow = now
		ns.Recolor(bar.edges, now and EDGE_NOW or EDGE_QUIET)
		Gauge.Paint(bar, bar.track, now and NOW_FILL or bar.color)
	end
end

function SwingGauges.Update()
	if not built or not frame:IsShown() then
		return
	end
	DrawHand(main, ns.Swing.MAIN)
	if dual then
		DrawHand(off, ns.Swing.OFF)
	end
	DrawWindow(main)
end

--------------------------------------------------------------------------
-- Status
--------------------------------------------------------------------------

function SwingGauges.Describe()
	if not ns.db.swing then
		return "off"
	end
	if not ns.Swing.Ready() then
		return "|cffd08040this client has no UnitAttackSpeed|r, so nothing is drawn"
	end
	if not ns.Swing.HasMainhand() then
		return "on, and nothing in your main hand to time"
	end

	local line = ("main hand %.2fs"):format(ns.Swing.Speed(ns.Swing.MAIN))
	if dual then
		line = line .. (", off hand %.2fs"):format(ns.Swing.Speed(ns.Swing.OFF))
	end
	if not ns.Slam.Known() then
		return line
	end
	if ns.Slam.Longer() then
		return line .. (", Slam casts in %.2fs and does not fit the swing"):format(ns.Slam.Cast())
	end
	local _, _, at = ns.Slam.Window()
	return line .. (", Slam at %.0f%% of it, %s %.2fs cast"):format((at or 0) * 100,
		ns.Slam.Measured() and "measured" or "estimated", ns.Slam.Cast())
end

--------------------------------------------------------------------------

events = CreateFrame("Frame")

-- No accumulator, because there is no rate to keep. See the header: this is the
-- one thing in the addon that draws motion, and motion is drawn on the frame
-- the screen is drawn on or it is drawn in steps.

events:RegisterEvent("PLAYER_LOGIN")
-- A weapon swap changes how many bars there are and how long each of them is,
-- and this addon swaps weapons itself out of the charge macro. Both events are
-- taken because one of them is the client telling you the item moved and the
-- other is it telling you the speed did, and neither implies the other on
-- these clients.
--
-- Filtered to the player where the client can filter, for the reason
-- Swing/Swing.lua filters the same two.
ns.RegisterUnitEvent(events, "UNIT_INVENTORY_CHANGED", "player")
ns.RegisterUnitEvent(events, "UNIT_ATTACK_SPEED", "player")
events:SetScript("OnEvent", function(_, event, token)
	if event == "PLAYER_LOGIN" then
		-- Apply is the only way in. It builds nothing while the part is off, and
		-- the switch going on is what calls it next.
		SwingGauges.Apply()
		return
	end

	if token == "player" then
		SwingGauges.Apply()
	end
end)

-- A resolution change moves every size in this file at once, the same way it
-- moves the meters.
ns.UI.OnRescale(function()
	SwingGauges.Apply()
end)
