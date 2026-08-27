-- The swing timer
--
-- Five questions, and only the last of them is about drawing.
--
-- Does the log start the right hand. The off hand flag is the twenty-first
-- value of SWING_DAMAGE and the second of SWING_MISSED, and reading the wrong
-- slot gives an off hand bar that never runs and a main hand bar that runs at
-- twice the speed. That looks like a haste bug and is a parser bug, which is
-- why it is asserted from both subevents and from a stranger's swing as well
-- as from the player's.
--
-- Does the swing come off the weapon. UnitAttackSpeed is the only source and
-- a swap has to move it, so the speed is changed under a running timer and the
-- bar is measured again.
--
-- Does haste scale what is left rather than restart it. Flurry landing halfway
-- through a swing leaves you halfway through a shorter swing, and a timer that
-- kept the elapsed instead would jump backwards every time it landed. This is
-- the single thing a warrior's swing timer has to get right and it is one line
-- of arithmetic, which is exactly the kind of line that gets rewritten wrong.
--
-- Does the Slam band land where the arithmetic says. The band is the whole
-- feature: a cast of C seconds against a swing of D belongs at (D - C) over D
-- of the bar, in whole pixels, and a band drawn a pixel off is a press that
-- clips. It is asserted as pixels rather than as a fraction, because pixels
-- are what the eye is aiming at.
--
-- And does the tick stay free. This is the only thing in the addon that draws
-- on every frame, so what it allocates per tick is gated below and the fill's
-- unguarded write is measured rather than argued about.

local H = ...
local PLAYER_CLASS, WARRIOR, CHURN = H.PLAYER_CLASS, H.WARRIOR, H.CHURN
local frames, guids, advance = H.frames, H.guids, H.advance
local itemLink, swing, logArgs = H.itemLink, H.swing, H.logArgs
local ns, fire, check = H.ns, H.fire, H.check
local drawn, window = H.carry.drawn, H.carry.window

local swingTicker
for _, f in ipairs(frames) do
	if f.scripts.OnUpdate and f.origin:match("Swing/Gauges") then
		swingTicker = f
	end
end
check(swingTicker ~= nil, "the swing timer registered no ticker")

local ME = "Player-0-0000000f"
local SOMEBODY = "Player-0-0000001f"
local SLAM = 1464

guids.player = ME
swing.mainhand = itemLink("Arcanite Reaper")
swing.main, swing.off = 3.4, nil
fire("PLAYER_ENTERING_WORLD")
ns.SwingGauges.Apply()

local frame = _G.WarriorKitSwing
check(frame ~= nil, "no swing frame came up")
local mainBar = ns.SwingGauges.Bar(ns.Swing.MAIN)
local offBar = ns.SwingGauges.Bar(ns.Swing.OFF)
check(mainBar ~= nil and offBar ~= nil, "the swing timer built fewer than two bars")

----------------------------------------------------------------------
-- The shape
----------------------------------------------------------------------

check(math.abs(ns.UI.Pixel(frame) - 1) < 1e-9,
	("the swing bars are not on the grid: one pixel is %.4f units"):format(ns.UI.Pixel(frame)))
check(mainBar:GetWidth() == ns.db.swingWidth,
	("the main hand bar is %.1f px, the setting says %d")
		:format(mainBar:GetWidth(), ns.db.swingWidth))
check(mainBar:GetHeight() == ns.db.swingHeight,
	("the main hand bar is %.1f px tall, the setting says %d")
		:format(mainBar:GetHeight(), ns.db.swingHeight))
check(not offBar:IsShown(), "the off hand bar is drawn with nothing in the off hand")
check(frame:GetHeight() == ns.db.swingHeight,
	("one bar and the frame is %.1f px tall, the bar is %d")
		:format(frame:GetHeight(), ns.db.swingHeight))

-- The band and the press line sit over the fill, which is ARTWORK, and under
-- nothing. And the border is made after both, because within one draw layer
-- the order is the order the textures were made and the band runs the full
-- height of the bar: made the other way round, the edge disappears behind
-- the band for exactly the span of screen the band exists to point at.
check(mainBar.band.layer == "OVERLAY" and mainBar.mark.layer == "OVERLAY",
	("the band draws on %s and the line on %s, and both belong on OVERLAY")
		:format(tostring(mainBar.band.layer), tostring(mainBar.mark.layer)))
local bandAt, edgeAt
for index, drawn in ipairs(mainBar.regions) do
	if drawn == mainBar.band then
		bandAt = index
	end
	if drawn == mainBar.edges[1] then
		edgeAt = index
	end
end
check(bandAt ~= nil and edgeAt ~= nil and bandAt < edgeAt,
	("the band is region %s and the border region %s, and the border is made last")
		:format(tostring(bandAt), tostring(edgeAt)))

-- The scale is the bar's own width, which is what makes a fill a whole
-- number of pixels rather than a fraction of one.
local low, high = mainBar:GetMinMaxValues()
check(low == 0 and high == ns.db.swingWidth,
	("the bar counts %s to %s, and it should count pixels")
		:format(tostring(low), tostring(high)))

----------------------------------------------------------------------
-- The log
--
-- Twenty-one values, and the off hand flag is in a different slot on each
-- of the two subevents that carry one.
----------------------------------------------------------------------

local function white(subevent, source, offhand)
	for index = 1, 21 do
		logArgs[index] = nil
	end
	logArgs[1] = GetTime()
	logArgs[2] = subevent
	logArgs[4] = source
	if subevent == "SWING_MISSED" then
		logArgs[12] = "DODGE"
		logArgs[13] = offhand
	else
		logArgs[12] = 300
		logArgs[13] = -1
		logArgs[21] = offhand
	end
	fire("COMBAT_LOG_EVENT_UNFILTERED")
end

check(not ns.Swing.Armed(ns.Swing.MAIN),
	"a swing was running before anything had swung")

white("SWING_DAMAGE", SOMEBODY)
check(not ns.Swing.Armed(ns.Swing.MAIN),
	"somebody else's swing started your timer")

white("SWING_DAMAGE", ME)
check(ns.Swing.Armed(ns.Swing.MAIN), "your own swing did not start the timer")
check(math.abs(ns.Swing.Remaining(ns.Swing.MAIN) - 3.4) < 1e-6,
	("a 3.4s weapon left %.3fs to run"):format(ns.Swing.Remaining(ns.Swing.MAIN)))

-- A dodge is the server saying the swing happened and did nothing, so it
-- restarts the timer exactly as a landed hit does. A timer that only heard
-- damage would stop dead against a mob you cannot hit.
advance(1.0)
white("SWING_MISSED", ME)
check(math.abs(ns.Swing.Remaining(ns.Swing.MAIN) - 3.4) < 1e-6,
	("a dodged swing left %.3fs to run, and it restarts the timer")
		:format(ns.Swing.Remaining(ns.Swing.MAIN)))

-- The off hand, from both directions. With nothing in that hand there is no
-- speed to run and the flag does nothing at all.
white("SWING_DAMAGE", ME, true)
check(not ns.Swing.Armed(ns.Swing.OFF),
	"an off hand swing ran a timer for a hand holding nothing")

swing.off = 1.8
swing.offhand = itemLink("Bloodspiller")
fire("UNIT_INVENTORY_CHANGED", "player")
check(offBar:IsShown(), "a weapon went into the off hand and no bar came up")
check(frame:GetHeight() == ns.db.swingHeight * 2 + 2,
	("two bars and a two pixel gap is %d px, the frame is %.1f")
		:format(ns.db.swingHeight * 2 + 2, frame:GetHeight()))

white("SWING_DAMAGE", ME, true)
check(math.abs(ns.Swing.Remaining(ns.Swing.OFF) - 1.8) < 1e-6,
	("the off hand flag on SWING_DAMAGE left %.3fs, and the off hand is 1.8s")
		:format(ns.Swing.Remaining(ns.Swing.OFF)))
white("SWING_MISSED", ME, true)
check(math.abs(ns.Swing.Remaining(ns.Swing.OFF) - 1.8) < 1e-6,
	("the off hand flag on SWING_MISSED left %.3fs, and the off hand is 1.8s")
		:format(ns.Swing.Remaining(ns.Swing.OFF)))

-- And the main hand is untouched by either, which is the half that fails
-- when the two flags are read out of one slot.
advance(0.4)
local before = ns.Swing.Remaining(ns.Swing.MAIN)
white("SWING_DAMAGE", ME, true)
check(math.abs(ns.Swing.Remaining(ns.Swing.MAIN) - before) < 1e-6,
	"an off hand swing restarted the main hand timer")

----------------------------------------------------------------------
-- Haste, which is the line that has to be right
----------------------------------------------------------------------

white("SWING_DAMAGE", ME)
advance(1.7)
check(math.abs(ns.Swing.Fraction(ns.Swing.MAIN) - 0.5) < 1e-6,
	("halfway through a 3.4s swing reads as %.3f"):format(ns.Swing.Fraction(ns.Swing.MAIN)))

-- Flurry, as an aura rather than as an attack speed event, because the
-- attack speed event does not reliably follow one on these clients and
-- that is the whole reason UNIT_AURA is registered.
swing.main = 2.4
fire("UNIT_AURA", "player")
check(math.abs(ns.Swing.Remaining(ns.Swing.MAIN) - 1.7 * 2.4 / 3.4) < 1e-6,
	("1.7s left of a 3.4s swing hasted to 2.4s should leave %.3fs and left %.3fs")
		:format(1.7 * 2.4 / 3.4, ns.Swing.Remaining(ns.Swing.MAIN)))
check(math.abs(ns.Swing.Fraction(ns.Swing.MAIN) - 0.5) < 1e-6,
	("haste moved the fill to %.3f, and scaling what is left keeps it at half")
		:format(ns.Swing.Fraction(ns.Swing.MAIN)))

-- An aura for somebody else's buff, which is most of them, costs a
-- comparison and writes nothing.
local held = ns.Swing.Remaining(ns.Swing.MAIN)
fire("UNIT_AURA", "player")
check(math.abs(ns.Swing.Remaining(ns.Swing.MAIN) - held) < 1e-6,
	"an aura event that moved no speed still moved the swing")

-- A weapon swap is the same arithmetic arriving by another door, and it is
-- the one this addon causes itself off a loadout key.
swing.main = 3.4
fire("UNIT_ATTACK_SPEED", "player")
check(math.abs(ns.Swing.Speed(ns.Swing.MAIN) - 3.4) < 1e-6,
	("the weapon went back to 3.4s and the timer says %.3f")
		:format(ns.Swing.Speed(ns.Swing.MAIN)))

----------------------------------------------------------------------
-- The Slam window
----------------------------------------------------------------------

_G.WarriorKitSpellCast[SLAM] = 1500
swing.talent = 5
ns.Slam.Forget()

if not WARRIOR then
	check(ns.Slam.Window() == nil,
		("a %s was given a Slam window"):format(PLAYER_CLASS))
	check(not ns.Slam.Known(), ("a %s knows Slam"):format(PLAYER_CLASS))
else
	check(ns.Slam.Rank() == 5,
		("Improved Slam read as %d points, and the tree holds 5"):format(ns.Slam.Rank()))
	check(math.abs(ns.Slam.Estimate() - 1.0) < 1e-6,
		("a 1.5s cast less 5 points of Improved Slam should estimate 1.00s and estimates %.3f")
			:format(ns.Slam.Estimate()))
	check(ns.Slam.Measured() == nil, "a cast was measured before one was ever made")

	local open, close, at = ns.Slam.Window()
	check(math.abs(at - (3.4 - 1.0) / 3.4) < 1e-6,
		("the press sits at %.4f of the bar, and (3.4 - 1.0) / 3.4 is %.4f")
			:format(at, (3.4 - 1.0) / 3.4))
	check(math.abs(close - open - 0.2 / 3.4) < 1e-9,
		("the band is %.4f of the bar, and two tenths of a 3.4s swing is %.4f")
			:format(close - open, 0.2 / 3.4))
end

----------------------------------------------------------------------
-- What that draws
----------------------------------------------------------------------

white("SWING_DAMAGE", ME)
advance(1.7)
swingTicker.scripts.OnUpdate(swingTicker, 0.05)

-- Read off the widget rather than off the bookkeeping field beside it, so a
-- tick that worked out the right number and never wrote it fails here.
local width = ns.db.swingWidth
check(math.abs(mainBar:GetValue() - 0.5 * width) < 1e-9,
	("half of a %d pixel bar is %.1f and the fill drew %s")
		:format(width, 0.5 * width, tostring(mainBar:GetValue())))

if WARRIOR then
	local open, close, at = ns.Slam.Window()
	local left = math.floor(open * width + 0.5)
	local right = math.floor(close * width + 0.5)
	check(mainBar.band:IsShown(), "the Slam band is not drawn")
	check(mainBar.band:GetWidth() == right - left,
		("the band drew %.1f px, and %d to %d is %d")
			:format(mainBar.band:GetWidth(), left, right, right - left))
	local point = mainBar.band.points and mainBar.band.points[1]
	check(point and point[4] == left,
		("the band starts at %s px, and %.4f of a %d pixel bar is %d")
			:format(tostring(point and point[4]), open, width, left))
	check(mainBar.mark:IsShown(), "the press line inside the band is not drawn")
	local markAt = mainBar.mark.points and mainBar.mark.points[1]
	check(markAt and markAt[4] == math.floor(at * width + 0.5),
		("the press line is at %s px and the arithmetic says %d")
			:format(tostring(markAt and markAt[4]), math.floor(at * width + 0.5)))

	-- Outside the band at half a swing, because a 1.0s cast against a 3.4s
	-- swing belongs at 70 percent of the bar and not at 50.
	check(not mainBar.shownNow,
		"the gauge flipped colour halfway through a swing, nowhere near the window")

	-- And inside it. The press is at 2.4 seconds spent of 3.4, so another
	-- seven tenths puts the fill on the mark.
	advance(0.7)
	swingTicker.scripts.OnUpdate(swingTicker, 0.05)
	check(mainBar.shownNow, "the fill reached the press mark and the gauge did not flip")
	check(mainBar.edges.r > 0.3 and mainBar.edges.g > 0.9,
		("the border did not go green while the window was open: %.2f, %.2f, %.2f")
			:format(mainBar.edges.r, mainBar.edges.g, mainBar.edges.b))

	-- Out the other side.
	advance(0.6)
	swingTicker.scripts.OnUpdate(swingTicker, 0.05)
	check(not mainBar.shownNow, "the window never closed")

	----------------------------------------------------------------
	-- A finished Slam restarts the swing
	----------------------------------------------------------------

	white("SWING_DAMAGE", ME)
	advance(2.0)
	fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", SLAM)
	check(math.abs(ns.Swing.Remaining(ns.Swing.MAIN) - 3.4) < 1e-6,
		("a finished Slam left %.3fs of swing, and it restarts the whole 3.4")
			:format(ns.Swing.Remaining(ns.Swing.MAIN)))

	-- Somebody else's cast, and one of yours that is not Slam, both leave
	-- it alone.
	advance(1.0)
	local running = ns.Swing.Remaining(ns.Swing.MAIN)
	fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-2", SLAM)
	fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 772)
	check(math.abs(ns.Swing.Remaining(ns.Swing.MAIN) - running) < 1e-6,
		"a cast that was not your Slam restarted your swing")

	----------------------------------------------------------------
	-- And the client's own number replaces the estimate
	--
	-- The estimate is a guess about whether this client folds a talent into
	-- the spell's cast time. UNIT_SPELLCAST_START carries what the server
	-- actually started, so from the first Slam of a session there is
	-- nothing left to guess.
	----------------------------------------------------------------

	swing.cast = { name = ns.Slam.Name(), start = 5000, stop = 6200 }
	fire("UNIT_SPELLCAST_START", "player", "cast-4", SLAM)
	swing.cast = nil
	check(ns.Slam.Measured() ~= nil and math.abs(ns.Slam.Measured() - 1.2) < 1e-6,
		("a cast from 5000 to 6200 milliseconds measured as %s seconds")
			:format(tostring(ns.Slam.Measured())))
	check(math.abs(ns.Slam.Cast() - 1.2) < 1e-6,
		"the measurement did not replace the estimate")
	local _, _, moved = ns.Slam.Window()
	check(math.abs(moved - (3.4 - 1.2) / 3.4) < 1e-6,
		("the band did not move with the measured cast: %.4f"):format(moved))
else
	check(not mainBar.band:IsShown(),
		("a %s was drawn a Slam band"):format(PLAYER_CLASS))
	check(mainBar:IsShown(),
		("a %s holding a weapon was not drawn a swing bar"):format(PLAYER_CLASS))
end

----------------------------------------------------------------------
-- The page, which is where the check box lives
----------------------------------------------------------------------

local tabs = 0
for _, group in ipairs(window.groups) do
	for _, section in ipairs(group.sections) do
		if section.feature and section.feature.name == "swing" then
			tabs = tabs + 1
		end
	end
end
check(tabs == (WARRIOR and 2 or 1),
	("the swing part opened %d tabs on a %s"):format(tabs, PLAYER_CLASS))

-- On and off, from the setting the check box writes.
ns.db.swing = false
ns.SwingGauges.Apply()
check(not frame:IsShown(), "the swing bars stayed up with the setting off")
ns.db.swing = true
ns.SwingGauges.Apply()
check(frame:IsShown(), "the swing bars did not come back with the setting on")

-- Nothing in the main hand is nothing to time, whatever the setting says.
swing.mainhand = nil
ns.SwingGauges.Apply()
check(not frame:IsShown(), "the swing bars were drawn for an empty main hand")
swing.mainhand = itemLink("Arcanite Reaper")
ns.SwingGauges.Apply()

----------------------------------------------------------------------
-- Allocation
----------------------------------------------------------------------

local function swingChurn(n)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, n do
		advance(0.05)
		swingTicker.scripts.OnUpdate(swingTicker, 0.05)
		-- Restarted through ns.Swing rather than through the log, because a
		-- log event wakes the meters too and what would be measured is
		-- their segment rather than this tick.
		if not ns.Swing.Armed(ns.Swing.MAIN) or ns.Swing.Remaining(ns.Swing.MAIN) <= 0 then
			ns.Swing.Start(ns.Swing.MAIN)
			ns.Swing.Start(ns.Swing.OFF)
		end
	end
	local after = collectgarbage("count")
	collectgarbage("restart")
	return (after - before) / (n / 50)
end

swingChurn(200)
local swingKb = swingChurn(200)
check(swingKb <= CHURN.swing,
	("the swing timer allocates %.2f KB per 50 ticks, the gate is %.2f")
		:format(swingKb, CHURN.swing))

print(("swing  %d x %d px per hand, main %.2fs off %.2fs, Slam window %s, %.2f KB per 50 ticks, gate is %.2f")
	:format(ns.db.swingWidth, ns.db.swingHeight, ns.Swing.Speed(ns.Swing.MAIN),
		ns.Swing.Speed(ns.Swing.OFF),
		WARRIOR and ("%.0f%% of the bar"):format(select(3, ns.Slam.Window()) * 100) or "not a warrior",
		swingKb, CHURN.swing))

----------------------------------------------------------------------
-- Put the client back the way the sections after this one expect it.
----------------------------------------------------------------------

guids.player = nil
swing.mainhand, swing.offhand, swing.off = nil, nil, nil
swing.main, swing.talent = 3.4, 0
_G.WarriorKitSpellCast[SLAM] = nil
ns.Slam.Forget()
fire("UNIT_INVENTORY_CHANGED", "player")
ns.Swing.Stop(ns.Swing.MAIN)
ns.Swing.Stop(ns.Swing.OFF)
ns.SwingGauges.Apply()
