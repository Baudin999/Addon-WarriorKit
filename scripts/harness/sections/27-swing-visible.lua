-- The swing timer, as a person sees it
--
-- The section above asserts the arithmetic and every one of its assertions
-- passed while the feature was unusable in game. Two things were wrong and
-- neither is arithmetic.
--
-- The bar moved in steps, and it took two goes to find out why, because there
-- were two throttles on one edge and removing the first left the second.
--
-- The first was a 20 Hz ticker. The second was the rounding: the fill was
-- snapped to a whole pixel, so it could only change value 53 times a second at
-- the shipped width however often the tick ran. A 144 Hz screen drew the same
-- position on 91 of its 144 frames, and each move was a whole design unit,
-- which is three screen pixels at swing zoom 3.
--
-- No assertion in this file can prove that a bar looks smooth. Smooth is a
-- property of a screen and an eye, and the stub has neither. What can be
-- proved is the property that leaves the client nothing to be blamed for, and
-- it is one sentence: on every frame it is given, the addon hands the widget
-- the exact position the elapsed time puts the edge at. So the fill is driven
-- across a whole swing at two frame rates and three things are asserted, none
-- of which is a tolerance. The drawn position equals elapsed over duration
-- times the width, exactly. The value changes on every frame, with no frame
-- repeating the one before it. And every step is the same size as every other,
-- which is what constant velocity means and what a quantiser destroys.
--
-- The second of those is also the gate on the addon's second pixel rule: a
-- moving fill is not quantised. Reintroduce a Whole() around the fill and the
-- repeated frames come back and this fails. The first rule, that a static edge
-- lands on a whole pixel, is gated by the anchor sweep at the end of the file
-- and by the mark assertions below.
--
-- And the mark moved. It was drawn from a cast time re-measured on every cast,
-- so the number under it changed while the player was aiming at it. The
-- assertion is that several casts in a row leave the mark on the same pixel.
--
-- What is allowed to move it is the swing speed, and that is asserted as the
-- invariant rather than as a percentage: at every weapon speed, the moment the
-- fill reaches the mark is the moment the swing has exactly a cast time left
-- to run. The percentage is the thing that moves; the invariant is the thing
-- that must not.

local H = ...
local WARRIOR, frames, guids = H.WARRIOR, H.frames, H.guids
local advance, itemLink, swing = H.advance, H.itemLink, H.swing
local ns, fire, check = H.ns, H.fire, H.check

-- One frame on a 60 fps client. The fill test below runs at 144 fps as well,
-- because a rounded fill is worse on a faster screen and an addon that only
-- ever looked right at 60 is an addon that looks wrong on half the monitors
-- sold. Everything else in the section is about drawing rather than rate and
-- uses the 60 fps figure.
local FRAME = 1 / 60
local FAST_FRAME = 1 / 144
local SLAM = 1464

guids.player = "Player-0-0000000f"
swing.mainhand = itemLink("Arcanite Reaper")
swing.main, swing.off, swing.offhand = 3.4, nil, nil
swing.talent = 5
_G.WarriorKitSpellCast[SLAM] = 1500
ns.Slam.Forget()
-- The section above cast a Slam and the number it took off it is still held.
-- A respec is what drops one, and this section starts from a character who has
-- never cast the spell.
fire("CHARACTER_POINTS_CHANGED")
fire("PLAYER_ENTERING_WORLD")
ns.SwingGauges.Apply()

local ticker = H.tick("swing")

local bar = ns.SwingGauges.Bar(ns.Swing.MAIN)
local width = ns.db.swingWidth

-- One frame of the client, through whatever the ticker decides to do with it.
-- Only the fill test below uses this, because it is the only test about the
-- rate rather than about the drawing.
local function tick(interval)
	ticker:Beat(interval or FRAME)
end

-- A draw, taken straight rather than through the ticker, so a test about where
-- the mark sits cannot pass or fail on when the ticker last ran.
local function redraw()
	ns.SwingGauges.Update()
end

local function markPixel()
	local point = bar.mark.points and bar.mark.points[1]
	return point and point[4]
end

-- The layout has run, so the bar counts in its own width rather than in the
-- one pixel it was built with. A bar left on the seed draws a whole swing in
-- two positions.
check(bar.pixels == width,
	("the bar counts to %s and the setting says %d"):format(tostring(bar.pixels), width))

----------------------------------------------------------------------------
-- The fill, frame by frame
----------------------------------------------------------------------------

do
	local SPEED = 3.4

	-- One swing, one frame at a time, reading the widget rather than the field
	-- beside it. Three numbers come back: the worst distance between what was
	-- drawn and where the elapsed time says the edge belongs, how many frames
	-- drew the same position as the frame before them, and the widest and
	-- narrowest step taken.
	--
	-- The elapsed time is accumulated here in the same order the stub clock
	-- accumulates it, so the two agree bit for bit and the comparison can be an
	-- exact one. A tolerance would let a rounded fill through at any width where
	-- a pixel is small.
	local function run(interval)
		swing.main = SPEED
		fire("UNIT_ATTACK_SPEED", "player")
		ns.Swing.Start(ns.Swing.MAIN)
		tick(interval)

		local elapsed, frames, repeated = 0, 0, 0
		local worst, widest, narrowest = 0, 0, math.huge
		local last = bar:GetValue()
		while elapsed + interval < SPEED do
			advance(interval)
			elapsed = elapsed + interval
			tick(interval)

			local at = bar:GetValue()
			local off = math.abs(at - elapsed / SPEED * width)
			if off > worst then
				worst = off
			end
			local step = at - last
			if step == 0 then
				repeated = repeated + 1
			end
			if step > widest then
				widest = step
			end
			if step < narrowest then
				narrowest = step
			end
			last = at
			frames = frames + 1
		end
		return frames, worst, repeated, widest - narrowest
	end

	for _, pass in ipairs{ { FRAME, 60 }, { FAST_FRAME, 144 } } do
		local frames, worst, repeated, spread = run(pass[1])
		check(worst < 1e-9,
			("at %d fps the fill was drawn %.4f px from where the elapsed time puts it")
				:format(pass[2], worst))
		check(repeated == 0,
			("at %d fps the fill drew the same position twice on %d of %d frames, and a frame it does not move on is a frame the eye reads as a stall")
				:format(pass[2], repeated, frames))
		check(spread < 1e-9,
			("at %d fps the widest step was %.6f px more than the narrowest, and a fill at constant velocity takes one step size")
				:format(pass[2], spread))
	end

	-- And the positive form of the addon's second pixel rule, stated on its own
	-- so that deleting the three assertions above cannot quietly take it with
	-- them: the fill really does sit between pixels. A whole number every frame
	-- is a quantiser, and a quantiser is the defect this section exists for.
	ns.Swing.Start(ns.Swing.MAIN)
	local fractional = 0
	for _ = 1, 60 do
		advance(FRAME)
		tick()
		local at = bar:GetValue()
		if math.abs(at - math.floor(at + 0.5)) > 1e-6 then
			fractional = fractional + 1
		end
	end
	check(fractional >= 50,
		("the fill landed off a whole pixel on %d of 60 frames, and a moving fill is not quantised")
			:format(fractional))
end

----------------------------------------------------------------------------
-- The mark
----------------------------------------------------------------------------

if WARRIOR then

do
	swing.main = 3.4
	fire("UNIT_ATTACK_SPEED", "player")
	ns.Swing.Start(ns.Swing.MAIN)
	redraw()

	check(ns.Slam.Measured() == nil, "a cast was measured before one was ever made")
	local estimated = markPixel()
	check(estimated ~= nil, "no press mark was drawn before the first cast")

	-- The first Slam of the session. The client's own number replaces the
	-- estimate, which is the whole reason the estimate is allowed to be a guess.
	swing.cast = { name = ns.Slam.Name(), start = 5000, stop = 6000 }
	fire("UNIT_SPELLCAST_START", "player", "cast-1", SLAM)
	swing.cast = nil
	fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", SLAM)
	redraw()

	local held, at = ns.Slam.Cast(), markPixel()
	check(math.abs(held - 1.0) < 1e-6,
		("a cast from 5000 to 6000 milliseconds measured as %.3fs"):format(held))

	-- And every Slam after it. Nothing about this character changed, so nothing
	-- about the mark may change either, whatever the server declares. Four
	-- casts, each one a different length, because a mark that follows the last
	-- cast is a mark that wanders while you are aiming at it.
	local declared = { { 8000, 9500 }, { 12000, 13040 }, { 16000, 16960 }, { 20000, 21200 } }
	for index = 1, #declared do
		swing.cast = {
			name = ns.Slam.Name(),
			start = declared[index][1],
			stop = declared[index][2],
		}
		fire("UNIT_SPELLCAST_START", "player", "cast-more", SLAM)
		swing.cast = nil
		fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-more", SLAM)
		redraw()
		check(math.abs(ns.Slam.Cast() - held) < 1e-9,
			("cast %d declared %.2fs and the drawn cast time moved to %.3fs from %.3fs")
				:format(index + 1, (declared[index][2] - declared[index][1]) / 1000,
					ns.Slam.Cast(), held))
		check(markPixel() == at,
			("cast %d moved the press mark from %s px to %s px")
				:format(index + 1, tostring(at), tostring(markPixel())))
	end

	-- An aura that moved no speed moves no mark either.
	fire("UNIT_AURA", "player")
	redraw()
	check(markPixel() == at, "an aura event that moved no speed moved the press mark")
end

do
	-- A respec is the one thing that makes the held number a reading of a cast
	-- this character no longer has, so the next cast is measured again. What
	-- comes back is snapped to a twentieth of a second: the real cast is 1.5
	-- less a tenth per point of Improved Slam, so the milliseconds under that
	-- are the server's rounding and nothing else, and a mark that follows them
	-- moves a pixel per cast.
	fire("CHARACTER_POINTS_CHANGED")
	check(ns.Slam.Measured() == nil, "a respec left the old cast time in place")

	-- A reading that is not a Slam. The event carried some other cast, or the
	-- client answered for one already in flight. Refused rather than held,
	-- because the held number is held for the session.
	swing.cast = { name = ns.Slam.Name(), start = 5000, stop = 8000 }
	fire("UNIT_SPELLCAST_START", "player", "cast-wild", SLAM)
	swing.cast = nil
	check(ns.Slam.Measured() == nil,
		("a 3.00s reading was held against a 1.50s spell: %s"):format(tostring(ns.Slam.Measured())))

	-- And one that rounds away to nothing. Zero is truthy in Lua, so a held
	-- zero would beat the estimate and then tell the player they have no Slam.
	swing.cast = { name = ns.Slam.Name(), start = 5000, stop = 5010 }
	fire("UNIT_SPELLCAST_START", "player", "cast-nothing", SLAM)
	swing.cast = nil
	check(ns.Slam.Measured() == nil, "a reading of one hundredth of a second was held")
	check(ns.Slam.Known(), "a refused reading left the character with no Slam")

	swing.cast = { name = ns.Slam.Name(), start = 5000, stop = 6003 }
	fire("UNIT_SPELLCAST_START", "player", "cast-respec", SLAM)
	swing.cast = nil
	check(math.abs(ns.Slam.Cast() - 1.0) < 1e-9,
		("1.003s off the server measured as %.4fs, and it is a 1.00s cast")
			:format(ns.Slam.Cast()))
end

do
	-- What the mark is, at any weapon speed: the point where the swing has
	-- exactly a cast time left to run. The share of the bar that lands on is
	-- different at every speed and is not what is asserted, because it is the
	-- number that moves.
	local speeds = { 3.4, 2.4, 1.6 }
	for index = 1, #speeds do
		local speed = speeds[index]
		swing.main = speed
		fire("UNIT_ATTACK_SPEED", "player")
		ns.Swing.Start(ns.Swing.MAIN)
		local _, _, at = ns.Slam.Window()
		advance(at * speed)
		redraw()
		check(math.abs(ns.Swing.Remaining(ns.Swing.MAIN) - ns.Slam.Cast()) < 1e-6,
			("on the mark at a %.1fs swing the swing has %.3fs left, and the cast is %.3fs")
				:format(speed, ns.Swing.Remaining(ns.Swing.MAIN), ns.Slam.Cast()))
		check(bar.shownNow,
			("the fill reached the mark at a %.1fs swing and the gauge did not flip")
				:format(speed))
	end
end

do
	-- Flurry, landing in the middle of a swing. The mark moves back down the
	-- bar, because a shorter swing spends a bigger share of itself on the same
	-- cast, and where it lands is still the point with a cast time left.
	swing.main = 3.4
	fire("UNIT_ATTACK_SPEED", "player")
	ns.Swing.Start(ns.Swing.MAIN)
	local _, _, before = ns.Slam.Window()
	advance(1.0)
	swing.main = 2.4
	fire("UNIT_AURA", "player")
	local _, _, after = ns.Slam.Window()
	check(after < before,
		("a 3.4s swing put the mark at %.4f and a 2.4s swing at %.4f, and the hasted one is earlier")
			:format(before, after))
	advance(ns.Swing.Remaining(ns.Swing.MAIN) - ns.Slam.Cast())
	check(math.abs(ns.Swing.Fraction(ns.Swing.MAIN) - after) < 1e-6,
		("with a cast time left the fill is at %.4f and the mark is at %.4f")
			:format(ns.Swing.Fraction(ns.Swing.MAIN), after))
end

do
	-- A wider bar is the same mark drawn on more pixels, and both the fill's
	-- scale and the mark have to follow it in the same layout pass.
	ns.db.swingWidth = 240
	ns.SwingGauges.Apply()
	ns.Swing.Start(ns.Swing.MAIN)
	advance(0.1)
	redraw()
	check(bar.pixels == 240,
		("the width went to 240 and the bar still counts to %s"):format(tostring(bar.pixels)))
	local _, _, at = ns.Slam.Window()
	check(markPixel() == math.floor(at * 240 + 0.5),
		("the mark is at %s px on a 240 pixel bar and the arithmetic says %d")
			:format(tostring(markPixel()), math.floor(at * 240 + 0.5)))
	ns.db.swingWidth = ns.DefaultFor("swingWidth")
	ns.SwingGauges.Apply()
end

end

----------------------------------------------------------------------------
-- Put the client back the way the sections after this one expect it.
----------------------------------------------------------------------------

guids.player = nil
swing.mainhand, swing.offhand, swing.off = nil, nil, nil
swing.main, swing.talent, swing.cast = 3.4, 0, nil
_G.WarriorKitSpellCast[SLAM] = nil
ns.Slam.Forget()
fire("CHARACTER_POINTS_CHANGED")
fire("UNIT_INVENTORY_CHANGED", "player")
ns.Swing.Stop(ns.Swing.MAIN)
ns.Swing.Stop(ns.Swing.OFF)

-- The two section 26 pinned to the design scene, back to what the addon ships.
ns.db.swing = ns.DefaultFor("swing")
ns.db.swingZoom = ns.DefaultFor("swingZoom")
ns.SwingGauges.Apply()
