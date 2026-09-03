-- Your own cast bar
--
-- The enemy cast row is measured two sections up and almost every answer this
-- bar draws comes out of the same file, so what is asserted here is the half
-- that is not shared.
--
-- That it is a bar of its own. It has a point you drag, a size in whole screen
-- pixels and a grid under it, which the row under an enemy bar does not,
-- because that one is a chamber inside somebody else's box.
--
-- That the fill is the same moving edge. It is held to the three statements the
-- swing bar and the enemy cast row are held to, and for the same reason: on
-- every frame it is given, the drawn position is exactly the elapsed fraction,
-- no frame repeats the one before it, and every step is the same size. This is
-- the one thing in the file that would still look fine in a screenshot after it
-- had stopped being right.
--
-- That a cast which did not finish reads differently from one that did. This is
-- the whole of what a player's cast bar has that a mob's does not: interrupted,
-- moved out of, or refused, the bar goes red and holds where it stopped rather
-- than emptying, because an empty bar is what a finished cast leaves too.
--
-- And that the client's own cast bar went down when ours came up, which is the
-- half nobody notices until there are two of them.

local H = ...
local CHURN, frames, advance = H.CHURN, H.frames, H.advance
local swing, enemyCasts, ns = H.swing, H.enemyCasts, H.ns
local fire, check = H.fire, H.check

do
	local FRAME, FAST = 1 / 60, 1 / 144
	local Palette = ns.Unit.Color.cast

	check(ns.UI.Ticking("playercast") ~= nil and ns.UI.Ticking("castsweep") ~= nil,
		"the cast bar registered no ticker")
	-- Both of them, in the order they were armed in, which is the order the
	-- client ran them in while they had a frame to themselves.
	local poll, sweep = H.tick("playercast"), H.tick("castsweep")

	-- At the design size. The bar ships at 2x, because it is under your
	-- character and read while you are looking at the fight rather than at it,
	-- and the grid assertion below is a whole pixel by definition only at 1x.
	local shippedZoom = ns.db.playerCastZoom
	ns.db.playerCastZoom = 1
	ns.PlayerCast.Apply()

	local frame = _G.WarriorKitPlayerCast
	check(frame ~= nil, "no cast bar frame came up")
	local bar = ns.PlayerCast.Bar()
	check(bar ~= nil, "the cast bar built no gauge")

	-- One frame of the client, which is one call of this part's OnUpdate. The
	-- accumulator inside it decides for itself whether that frame is also a
	-- poll, which is the arrangement being tested: the fill runs on every frame
	-- and the client is asked five times a second.
	local function paint(delta)
		delta = delta or FRAME
		advance(delta)
		poll:Beat(delta)
		sweep:Beat(delta)
	end

	-- A cast of yours, in the milliseconds the stub answers UnitCastingInfo in.
	-- The event is fired as well as the table being written, because that is
	-- what happens in the game and because a bar that only ever came up on the
	-- poll would be up to a fifth of a second late without anything saying so.
	local function casts(name, seconds)
		local start = _G.GetTime()
		enemyCasts.channel.player = nil
		swing.cast = { name = name, start = start * 1000, stop = (start + seconds) * 1000 }
		fire("UNIT_SPELLCAST_START", "player")
		return start, start + seconds
	end

	-- A channel of yours. The stub answers UnitChannelInfo in seconds and
	-- UnitCastingInfo in milliseconds, which is not a slip: the two calls are
	-- reached through different tables and the point of the pair is that a shim
	-- reading either one positionally has to divide.
	local function channels(name, seconds)
		local start = _G.GetTime()
		swing.cast = nil
		enemyCasts.channel.player = { name = name, start = start, finish = start + seconds }
		fire("UNIT_SPELLCAST_CHANNEL_START", "player")
		return start, start + seconds
	end

	local function quiet()
		swing.cast, enemyCasts.channel.player = nil, nil
		ns.PlayerCast.Update(_G.GetTime())
	end

	----------------------------------------------------------------------
	-- The shape, which is the half the enemy row has nothing to say about
	----------------------------------------------------------------------

	check(math.abs(ns.UI.Pixel(frame) - 1) < 1e-9,
		("the cast bar is not on the grid: one pixel is %.4f units")
			:format(ns.UI.Pixel(frame)))
	check(frame:GetWidth() == ns.db.playerCastWidth,
		("the bar is %.1f px wide, the setting says %d")
			:format(frame:GetWidth(), ns.db.playerCastWidth))
	check(frame:GetHeight() == ns.db.playerCastHeight,
		("the bar is %.1f px tall, the setting says %d")
			:format(frame:GetHeight(), ns.db.playerCastHeight))
	check(bar:GetWidth() == frame:GetWidth() and bar:GetHeight() == frame:GetHeight(),
		"the gauge is not the frame, so the rim and the fill disagree about where the bar is")


	----------------------------------------------------------------------
	-- Empty, which is what the bar looks like almost all of the time
	----------------------------------------------------------------------

	quiet()
	check(not frame:IsShown(), "the bar is drawn with nothing being cast")

	-- And the client's own is down, which is the half of replacing a thing that
	-- is easy to forget. Held down, too: the client turns its own cast bar back
	-- on every time it starts drawing one.
	check(not _G.CastingBarFrame:IsShown(),
		"our cast bar is up and Blizzard's is still drawn under it")
	_G.CastingBarFrame:Show()
	check(not _G.CastingBarFrame:IsShown(),
		"the client showed its own cast bar again and the strip did not hold it")

	----------------------------------------------------------------------
	-- A cast comes on
	----------------------------------------------------------------------

	casts("Slam", 1.5)
	check(frame:IsShown(), "you are casting Slam and the bar is down")
	check(ns.PlayerCast.Bar() == bar, "the bar was rebuilt under a running cast")
	check(frame:GetHeight() == ns.db.playerCastHeight,
		"a cast starting changed the height of the bar it is drawn on")

	-- The colour reaches the gauge rather than stopping at the bookkeeping,
	-- which is the failure a field comparison on its own cannot see.
	local r, g, b = bar:GetStatusBarColor()
	check(r == Palette.open[1] and g == Palette.open[2] and b == Palette.open[3],
		"a cast of yours was not drawn in the cast colour")

	-- The event alone put it up, before any poll could have. A bar that needed
	-- the poll would be right and late, and late is most of what a cast bar is
	-- for.
	check(bar:GetValue() < 0.01,
		("the bar opened at %.3f of the way through a cast that has just started")
			:format(bar:GetValue()))

	----------------------------------------------------------------------
	-- The fill, held to the swing bar's three statements
	----------------------------------------------------------------------

	for _, pass in ipairs({ { FRAME, 60 }, { FAST, 144 } }) do
		local delta, hz = pass[1], pass[2]
		local start, finish = casts("Slam", 3)
		paint(delta)

		local last = bar:GetValue()
		local worst, repeated, widest, narrowest, drawn = 0, 0, -1, 1e9, 0
		for _ = 1, math.floor(2.5 / delta) do
			paint(delta)
			local at = bar:GetValue()
			local want = (_G.GetTime() - start) / (finish - start)
			if math.abs(at - want) > worst then
				worst = math.abs(at - want)
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
			drawn = drawn + 1
		end

		check(worst < 1e-9,
			("at %d fps the cast fill was drawn %.9f off where the elapsed time puts it")
				:format(hz, worst))
		check(repeated == 0,
			("at %d fps the fill drew the same position twice on %d of %d frames, and a frame it does not move on is a frame the eye reads as a stall")
				:format(hz, repeated, drawn))
		check(widest - narrowest < 1e-9,
			("at %d fps the widest step was %.9f more than the narrowest, and a fill at constant velocity takes one step size")
				:format(hz, widest - narrowest))
	end

	----------------------------------------------------------------------
	-- The number under it, in tenths
	----------------------------------------------------------------------

	local ends = select(2, casts("Slam", 3))
	paint()
	check(bar.spell:GetText() == "Slam",
		("the bar says %q while you are casting Slam"):format(tostring(bar.spell:GetText())))

	-- Floored rather than rounded, which is Cast.Seconds' rule and is the one
	-- that matters on the number somebody is timing a press against: rounded, a
	-- bar with 2.96 seconds left says 3.0 and has promised a tenth it has not
	-- got.
	local want = ("%.1f"):format(math.floor((ends - _G.GetTime()) * 10) / 10)
	check(bar.timer:GetText() == want,
		("the bar reads %q with %.3f seconds left, and %q is the floored tenth")
			:format(tostring(bar.timer:GetText()), ends - _G.GetTime(), want))

	local counted = bar.timer:GetText()
	paint(0.12)
	check(bar.timer:GetText() ~= counted,
		("an eighth of a second left the bar still reading %q, and it counts in tenths")
			:format(tostring(counted)))

	----------------------------------------------------------------------
	-- A channel drains from the other end
	----------------------------------------------------------------------

	local start, finish = channels("First Aid", 4)
	paint()
	check(frame:IsShown(), "a channel of yours left the bar down")
	local left = 1 - (_G.GetTime() - start) / (finish - start)
	check(math.abs(bar:GetValue() - left) < 1e-9,
		("a channel drew %.6f of the bar and what is left of it is %.6f")
			:format(bar:GetValue(), left))

	----------------------------------------------------------------------
	-- Going away, on the frame rather than at the poll
	----------------------------------------------------------------------

	casts("Slam", 0.5)
	paint()
	check(frame:IsShown(), "half a second of cast did not come on")
	advance(0.6)
	poll:Beat(FRAME)
	sweep:Beat(FRAME)
	check(not frame:IsShown(),
		"a cast that ran out of time is still drawn, and no poll has happened yet")

	----------------------------------------------------------------------
	-- The one thing a mob's cast bar has no use for
	--
	-- Interrupted, the bar holds where it stopped and turns red. An empty bar
	-- is what a finished cast leaves behind, so a cast that died has to look
	-- like something else or the bar has answered the wrong question.
	----------------------------------------------------------------------

	casts("Slam", 3)
	paint()
	local held = bar:GetValue()
	swing.cast = nil
	fire("UNIT_SPELLCAST_INTERRUPTED", "player")
	check(frame:IsShown(), "the cast was interrupted and the bar went straight down")
	r, g, b = bar:GetStatusBarColor()
	check(r == ns.Unit.Color.hue.red[1] and g == ns.Unit.Color.hue.red[2]
		and b == ns.Unit.Color.hue.red[3],
		"an interrupted cast was not drawn as one that failed")
	check(bar.timer:GetText() == "interrupted",
		("the bar reads %q where the seconds were, and the cast was interrupted")
			:format(tostring(bar.timer:GetText())))
	check(bar.spell:GetText() == "Slam",
		"the spell that was interrupted stopped being named on the bar")

	-- Held, rather than carried on filling towards a finish that will not
	-- happen.
	paint()
	paint()
	check(bar:GetValue() == held,
		("the bar kept moving after the cast died, from %.4f to %.4f")
			:format(held, bar:GetValue()))
	check(frame:IsShown(), "two frames took the failed cast off before its hold was up")

	-- And it does go, without needing another cast to push it off.
	advance(1)
	poll:Beat(FRAME)
	sweep:Beat(FRAME)
	check(not frame:IsShown(), "the failed cast never came off the screen")

	-- A press the client refused before anything started. There is no cast to
	-- report the failure of, and inventing one is a red bar for a spell you
	-- never began.
	quiet()
	fire("UNIT_SPELLCAST_FAILED", "player")
	check(not frame:IsShown(),
		"a press that was refused before it started put a failed cast on the screen")

	-- Somebody else's cast, on a client with no RegisterUnitEvent to filter it.
	casts("Slam", 3)
	paint()
	fire("UNIT_SPELLCAST_INTERRUPTED", "party2")
	r = select(1, bar:GetStatusBarColor())
	check(r == Palette.open[1],
		"a party member's cast was interrupted and it turned your own bar red")

	----------------------------------------------------------------------
	-- Off, and what has to be said when it goes
	----------------------------------------------------------------------

	quiet()
	ns.db.playerCast = false
	ns.PlayerCast.Apply()
	casts("Slam", 3)
	paint()
	check(not frame:IsShown(), "the cast bar is switched off and still draws a cast")
	check(ns.PlayerCast.Describe():match("Blizzard"),
		("with ours off and Blizzard's hidden the readout says %q, which does not"
			.. " mention that nothing is drawing your casts")
			:format(ns.PlayerCast.Describe()))

	ns.db.hideBlizzPlayerCast = false
	ns.BlizzHide.Apply()
	check(_G.CastingBarFrame:IsShown(),
		"Blizzard's cast bar was put back and stayed hidden")
	ns.db.hideBlizzPlayerCast = ns.DefaultFor("hideBlizzPlayerCast")
	ns.BlizzHide.Apply()
	check(not _G.CastingBarFrame:IsShown(),
		"the switch went back on and Blizzard's cast bar stayed on screen")

	ns.db.playerCast = ns.DefaultFor("playerCast")
	ns.PlayerCast.Apply()

	----------------------------------------------------------------------
	-- The preview, which is the only way to look at an empty bar on purpose
	----------------------------------------------------------------------

	quiet()
	ns.db.locked = false
	ns.PlayerCast.Lock()
	check(frame:IsShown(),
		"the frames are unlocked and the bar you are meant to be placing is invisible")
	local previewed = bar:GetValue()
	paint(0.3)
	check(bar:GetValue() ~= previewed, "the preview is not moving, so it is a still picture")

	ns.db.locked = true
	ns.PlayerCast.Lock()
	check(not frame:IsShown(),
		"the frames were locked again and the made up cast stayed on the screen")

	----------------------------------------------------------------------
	-- What a cast costs per frame
	--
	-- The sweep is a subtract, a divide and a SetValue, plus one string every
	-- tenth of a second out of the table Cast.Seconds fills once. Casting the
	-- same spell over and over is the steady state rather than a warm up: it
	-- draws the same thirty numbers for the rest of the fight.
	----------------------------------------------------------------------

	do
		local opened = _G.GetTime()
		swing.cast = { name = "Slam", start = opened * 1000, stop = (opened + 1.5) * 1000 }
		ns.PlayerCast.Update(opened)

		local function burnFrames(n)
			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			for _ = 1, n do
				advance(FRAME)
				-- Cast again the moment it finishes, and the entry is rewritten
				-- in place: a fresh table per cast would be this file
				-- allocating inside its own measurement.
				local now = _G.GetTime()
				if swing.cast.stop <= now * 1000 then
					swing.cast.start, swing.cast.stop = now * 1000, (now + 1.5) * 1000
				end
				poll:Beat(FRAME)
				sweep:Beat(FRAME)
			end
			local after = collectgarbage("count")
			collectgarbage("restart")
			return after - before
		end

		-- Cold first, for the reason the enemy row's measurement takes a cold
		-- pass: the first run interns every string the bar will ever draw.
		burnFrames(200)
		local burn = burnFrames(200)
		print(("cast   %.2f KB per 200 frames of your own casting, gate is %.2f")
			:format(burn, CHURN.cast))
		check(burn <= CHURN.cast,
			("the cast bar allocated %.2f KB per 200 frames, over the %.2f KB gate")
				:format(burn, CHURN.cast))
	end

	----------------------------------------------------------------------
	-- Put the client back
	----------------------------------------------------------------------

	quiet()
	check(not frame:IsShown(), "the section left a cast on the screen")

	ns.db.playerCastZoom = shippedZoom
	ns.PlayerCast.Apply()

	print(("cast   %d x %d px bar on the grid, fill exact at 60 and 144 fps, a"
		.. " failed cast holds; %s")
		:format(frame:GetWidth(), frame:GetHeight(), ns.PlayerCast.Describe()))
end
