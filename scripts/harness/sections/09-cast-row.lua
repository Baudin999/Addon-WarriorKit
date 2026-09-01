-- The cast row
--
-- `grep UNIT_SPELLCAST` returned nothing across this addon until the row
-- existed. The bars replace the nameplate, so replacing it cost the one thing
-- on a plate that says when to press Pummel, and that is what this section is
-- about getting back.
--
-- Everything above measures where the row sits, which is the mistake the debuff
-- row shipped: the squares were in the right place for the whole life of the
-- setting and one of them never came on once. So this asserts a bar comes on, a
-- fill moves, a number counts down, and each of them goes away again.
--
-- The fill is held to the same three statements the swing bar is held to, and
-- for the same reason. It is a moving edge rather than a readout, so on every
-- frame it is given, the drawn position equals the elapsed fraction exactly, no
-- frame repeats the one before it, and every step is the same size. Put a
-- rounding call back in front of the fill and the second of those fails.
--
-- The rest is the failure modes that do not show up in a screenshot: a second
-- cast of the same spell, a cast that runs out between two ticks, a pooled
-- widget carrying somebody else's cast onto the next mob, and a Blizzard region
-- this addon hid on the way in and has to give back on the way out.

local H = ...
local CHURN, frames, plates = H.CHURN, H.frames, H.plates
local advance, enemyCasts, ns = H.advance, H.enemyCasts, H.ns
local fire, check = H.fire, H.check
local barTicker, churn = H.carry.barTicker, H.carry.churn

do
	local FRAME, FAST = 1 / 60, 1 / 144
	local plate = plates[1]
	local Palette = ns.Unit.Color.cast

	local function row()
		return ns.EnemyBars.WidgetFor("nameplate1").cast
	end

	-- One frame of the client, which is one call of the bars' OnUpdate. The
	-- accumulator inside it decides for itself whether that frame is also a
	-- tick, which is the arrangement being tested: the fills run on every frame
	-- and everything else runs at five hertz.
	local function paint(delta)
		delta = delta or FRAME
		advance(delta)
		barTicker.scripts.OnUpdate(barTicker, delta)
	end

	-- A cast on the mob, in the seconds the stub counts in.
	local function casts(name, seconds, immune, channel)
		local start = _G.GetTime()
		enemyCasts.cast.nameplate1, enemyCasts.channel.nameplate1 = nil, nil
		local entry = { name = name, start = start, finish = start + seconds, immune = immune }
		if channel then
			enemyCasts.channel.nameplate1 = entry
		else
			enemyCasts.cast.nameplate1 = entry
		end
		ns.EnemyBars.Update()
		return start, start + seconds
	end

	----------------------------------------------------------------------
	-- Empty, which is what a bar looks like almost all the time
	----------------------------------------------------------------------

	check(row() ~= nil, "the widget carries no cast row at all")
	check(not row():IsShown(), "the cast row is drawn with nothing casting")
	check(ns.CastImmuneKnown() == nil,
		"the addon has an opinion about uninterruptible casts before it has read one")

	-- Blizzard's own plate cast bar goes with the rest of the plate while ours
	-- is on. Two cast bars for one cast, in two places, is worse than either.
	check(plate.UnitFrame.castBar.wkStripped,
		"our cast row is on and Blizzard's plate cast bar is still drawn under it")

	-- And it stays down through the call that used to put it back. The plate's
	-- cast bar is the same CastingBarFrame mixin the target's is, so it shows
	-- itself with SetShown, which is resolved in C and walks straight past the
	-- Hide ns.Strip wrote over its Show. One cast anywhere in the zone was two
	-- cast bars for the rest of the session, and the strip flag above went on
	-- saying the region was hidden the whole time, which is why this asks what
	-- is on the screen instead.
	plate.UnitFrame.castBar:SetShown(true)
	check(not plate.UnitFrame.castBar:IsVisible(),
		"the plate cast bar showed itself with SetShown and nothing put it back down")

	----------------------------------------------------------------------
	-- A cast comes on
	----------------------------------------------------------------------

	casts("Shadow Bolt", 3, nil)
	check(row():IsShown(), "the mob is casting Shadow Bolt and the row is hidden")
	check(row().shownSpell == "Shadow Bolt",
		("the row says %q, the mob is casting Shadow Bolt"):format(tostring(row().shownSpell)))
	check(ns.CastImmuneKnown() == false,
		"a cast came back with no flag in the slot and the addon claims the client says")
	check(row().look == Palette.open,
		"a cast nothing said was immune to interruption was not drawn as one you can stop")

	-- The colour reaches the gauge rather than stopping at the bookkeeping
	-- field beside it, which is the shape of bug the skinned frames already hit.
	local r, g, b = row().bar:GetStatusBarColor()
	check(r == Palette.open[1] and g == Palette.open[2] and b == Palette.open[3],
		("the cast gauge is painted %.2f %.2f %.2f, the palette says %.2f %.2f %.2f")
			:format(r, g, b, Palette.open[1], Palette.open[2], Palette.open[3]))

	----------------------------------------------------------------------
	-- The fill, which is the half no tick may throttle
	----------------------------------------------------------------------

	for _, pass in ipairs({ { FRAME, 60 }, { FAST, 144 } }) do
		local delta, hz = pass[1], pass[2]
		local start, finish = casts("Shadow Bolt", 3, nil)
		paint(delta)

		local last = row().bar:GetValue()
		local worst, repeated, widest, narrowest, drawn = 0, 0, -1, 1e9, 0
		for _ = 1, math.floor(2.5 / delta) do
			paint(delta)
			local at = row().bar:GetValue()
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
			("at %d fps the cast fill drew the same position twice on %d of %d frames, and a frame it does not move on is a frame the eye reads as a stall")
				:format(hz, repeated, drawn))
		check(widest - narrowest < 1e-9,
			("at %d fps the widest step was %.9f more than the narrowest, and a fill at constant velocity takes one step size")
				:format(hz, widest - narrowest))
	end

	-- And the number under it, to the tenth rather than to the second. An
	-- interrupt is timed in tenths and a number that says 1 for a whole second
	-- is a number you cannot act on.
	local counting, ends = casts("Shadow Bolt", 3, nil)
	paint()
	local shown = row().shownTenths
	-- Floored, not rounded. Rounded, a row with 2.96 seconds left says 3.0, which
	-- is the number somebody is timing a press against promising a tenth of a
	-- second that is not there.
	check(row().timer:GetText() == ("%.1f"):format(math.floor((ends - _G.GetTime()) * 10) / 10),
		("the row says %q with %.3f seconds left"):format(tostring(row().timer:GetText()),
			ends - _G.GetTime()))
	paint(0.12)
	check(row().shownTenths == shown - 1,
		("an eighth of a second took the count from %s to %s, and it counts in tenths")
			:format(tostring(shown), tostring(row().shownTenths)))
	check(counting == ends - 3, "the stub disagrees with itself about when the cast began")

	----------------------------------------------------------------------
	-- A channel drains from the other end
	----------------------------------------------------------------------

	local start, finish = casts("Drain Life", 4, nil, true)
	paint()
	check(row():IsShown(), "a channel left the row hidden")
	check(row().shownSpell == "Drain Life",
		("a channel put %q on the row"):format(tostring(row().shownSpell)))
	local want = 1 - (_G.GetTime() - start) / (finish - start)
	check(math.abs(row().bar:GetValue() - want) < 1e-9,
		("a channel drew %.6f of the bar and what is left of it is %.6f")
			:format(row().bar:GetValue(), want))

	----------------------------------------------------------------------
	-- One the client says you cannot stop
	----------------------------------------------------------------------

	casts("Pyroblast", 4, true)
	check(row().look == Palette.locked,
		"a cast flagged uninterruptible was drawn as one you can stop")
	check(ns.CastImmuneKnown() == true,
		"the client put the flag in the slot and the addon still says it does not")
	r, g, b = row().bar:GetStatusBarColor()
	check(r == Palette.locked[1] and g == Palette.locked[2] and b == Palette.locked[3],
		"an uninterruptible cast did not repaint the gauge")

	----------------------------------------------------------------------
	-- Going away, on the frame rather than at the tick
	----------------------------------------------------------------------

	casts("Shadow Bolt", 0.5, nil)
	paint()
	check(row():IsShown(), "half a second of cast did not come on")
	-- Past the end without a tick in between. The client will say so within a
	-- fifth of a second and a fifth of a second is exactly how long a bar sitting
	-- full at the end of a cast is on the screen, which is the frame where you
	-- are deciding whether there is still time to press anything.
	advance(0.6)
	barTicker.scripts.OnUpdate(barTicker, FRAME)
	check(not row():IsShown(),
		"a cast that ran out of time is still drawn, and no tick has happened yet")

	-- And the client saying so takes it away too, which is what an interrupt
	-- looks like: the cast is gone before its own finish.
	casts("Shadow Bolt", 3, nil)
	check(row():IsShown(), "the row did not come back for a fresh cast")
	enemyCasts.cast.nameplate1 = nil
	ns.EnemyBars.Update()
	check(not row():IsShown(), "the cast was interrupted and the row is still drawn")

	----------------------------------------------------------------------
	-- The same spell twice
	--
	-- Guarded on the string alone, the second cast writes nothing, so the row
	-- stays hidden and the bar you needed most is the one that never came.
	----------------------------------------------------------------------

	casts("Shadow Bolt", 3, nil)
	check(row():IsShown(),
		"a mob cast the same spell twice in a row and the second one did not draw")

	----------------------------------------------------------------------
	-- The events, which are worth a fifth of a second and nothing else
	----------------------------------------------------------------------

	enemyCasts.cast.nameplate1 = nil
	ns.EnemyBars.Update()
	check(not row():IsShown(), "the row did not clear before the event test")

	local eventStart = _G.GetTime()
	enemyCasts.cast.nameplate1 = { name = "Fireball", start = eventStart,
		finish = eventStart + 3, immune = false }
	fire("UNIT_SPELLCAST_START", "nameplate1")
	check(row():IsShown() and row().shownSpell == "Fireball",
		"a cast event on a unit with a bar did not reach that bar before the next tick")

	-- One on a unit with no bar of ours is a lookup and nothing else.
	fire("UNIT_SPELLCAST_START", "party3")

	----------------------------------------------------------------------
	-- A widget goes back to the pool carrying a cast
	----------------------------------------------------------------------

	fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	enemyCasts.cast.nameplate1 = nil
	check(not row():IsShown(),
		"a pooled widget came back still drawing the cast the last mob was making")

	----------------------------------------------------------------------
	-- Off, and what has to come back with it
	----------------------------------------------------------------------

	-- Turning the chamber off takes nothing off the bar, and that is the whole
	-- assertion. It used to take fifteen pixels, because the row was reserved
	-- under the gauge whether or not anything cast: the setting moved every bar
	-- on the screen up or down, and PlaceOnPlate had to subtract the reserve back
	-- out to keep the gauge over the mob. The chamber lives inside the box now,
	-- so the widget is the same height either way and the only thing the setting
	-- decides is whether the box can grow.
	local tall = ns.EnemyBars.WidgetFor("nameplate1"):GetHeight()
	local openBox = ns.EnemyBars.WidgetFor("nameplate1").boxOpen
	ns.db.barsCast = false
	ns.EnemyBars.ApplyLayout()
	ns.EnemyBars.Rebuild()

	local bar = ns.EnemyBars.WidgetFor("nameplate1")
	check(math.abs(tall - bar:GetHeight()) < 1e-9,
		("switching the cast row off took %.0f px off the bar, and it must take none")
			:format(tall - bar:GetHeight()))
	check(math.abs(bar.boxOpen - bar.boxIdle) < 1e-9,
		("the chamber is off and the box can still open to %.0f px over its idle %.0f")
			:format(bar.boxOpen, bar.boxIdle))
	check(openBox > bar.boxIdle,
		"the chamber was on and the box could not open any further than idle")
	check(not bar.cast:IsShown(),
		"the cast row is switched off and still drawn")
	check(plate.UnitFrame.castBar:IsShown(),
		"our cast row is off and Blizzard's plate cast bar did not come back with it")

	-- The same door, and the bug that was already standing at it. Every region
	-- this file hides has to be on the list the restore walks, whether or not
	-- the setting that hid it is still on. Built from the settings in both
	-- directions, turning `bars marker` off hid Blizzard's raid icon for the
	-- rest of the session: the walk that was meant to give it back no longer
	-- had it to give.
	ns.db.barsMarker = false
	ns.EnemyBars.Rebuild()
	check(plate.UnitFrame.RaidTargetFrame:IsShown(),
		"switching our raid marker off left Blizzard's hidden, so the mob has none at all")
	ns.db.barsMarker = true

	ns.db.barsCast = true
	ns.EnemyBars.ApplyLayout()
	ns.EnemyBars.Rebuild()
	check(math.abs(ns.EnemyBars.WidgetFor("nameplate1"):GetHeight() - tall) < 1e-9,
		"the bar changed height when the cast row came back")
	check(ns.EnemyBars.WidgetFor("nameplate1").boxOpen > ns.EnemyBars.WidgetFor("nameplate1").boxIdle,
		"the cast row came back and the box still cannot open")

	----------------------------------------------------------------------
	-- The preview, which is the only way to look at this row on purpose
	--
	-- A mob that casts is not something you can arrange, so "unlock the frames
	-- and look" had nothing to look at and the row could not be placed, sized or
	-- judged until a caster pulled you. Unlocked, every bar draws its own cast
	-- instead of asking the client, which is what Buffs/Nag.lua already does
	-- with an equally empty row.
	----------------------------------------------------------------------

	enemyCasts.cast.nameplate1 = nil
	ns.EnemyBars.Update()
	check(not row():IsShown(), "the row did not clear before the preview test")

	ns.db.locked = false
	ns.EnemyBars.Update()
	check(row():IsShown(),
		"the frames are unlocked, nothing is casting, and the row has nothing on it")
	check(row().shownSpell == "cast" or row().shownSpell == "channel",
		("the preview put %q on the row, and it says what it is rather than naming a spell")
			:format(tostring(row().shownSpell)))
	check(ns.CastImmuneKnown() ~= nil,
		"the preview moved the client's own answer about uninterruptible casts")

	-- It rolls over rather than ending. A preview that goes out for a fifth of a
	-- second on every loop is a flicker, and the whole job of this is to be
	-- looked at.
	local blank = 0
	for _ = 1, math.floor(6 / FRAME) do
		paint()
		if not row():IsShown() then
			blank = blank + 1
		end
	end
	check(blank == 0,
		("the preview went out on %d of %.0f frames across a full loop")
			:format(blank, 6 / FRAME))

	-- Both pictures, across one loop: a cast that fills and a channel that
	-- drains. One unlock has to answer both, because they are what the row draws
	-- and they do not look alike.
	local sawCast, sawChannel = false, false
	for _ = 1, math.floor(6 / FRAME) do
		paint()
		if row().channel then
			sawChannel = true
		else
			sawCast = true
		end
	end
	check(sawCast and sawChannel,
		("a five second loop drew a cast %s and a channel %s, and it owes both")
			:format(tostring(sawCast), tostring(sawChannel)))

	-- Locked again, with the mob really casting at that moment, which is the case
	-- the preview flag has to be dropped for. Locked over an empty row the
	-- ordinary clear covers it; locked over a real cast, a flag left standing
	-- means the sweep rolls that cast over into another preview when it ends and
	-- the row never goes out again.
	casts("Shadow Bolt", 1, nil)
	ns.db.locked = true
	ns.EnemyBars.Update()
	check(row().shownSpell == "Shadow Bolt",
		("locking over a live cast left %q on the row"):format(tostring(row().shownSpell)))
	check(not row().preview, "a locked row is still flagged as a preview")

	advance(1.2)
	barTicker.scripts.OnUpdate(barTicker, FRAME)
	check(not row():IsShown(),
		"the cast ended and the row rolled over into a preview instead of going out")

	enemyCasts.cast.nameplate1 = nil
	ns.EnemyBars.Update()
	check(not row():IsShown(), "the row did not clear after the preview test")

	----------------------------------------------------------------------
	-- What the fills cost, which is the question every frame asks
	--
	-- The bars' own churn figure below is quoted with nothing casting, and with
	-- nothing casting the sweep is a walk and one IsShown per bar. This is the
	-- other case: two mobs both casting, every frame, which is the state the
	-- feature exists for and the only one where the row builds anything.
	--
	-- What it builds is one string, and only when the tenth on the row changes,
	-- which is ten times a second per casting mob rather than sixty. The fill
	-- itself is one subtract, one divide and one SetValue.
	----------------------------------------------------------------------

	do
		local opened = _G.GetTime()
		enemyCasts.cast.nameplate1 = { name = "Shadow Bolt", start = opened,
			finish = opened + 3, immune = false }
		enemyCasts.cast.nameplate2 = { name = "Fireball", start = opened,
			finish = opened + 3, immune = false }
		ns.EnemyBars.Update()

		local function frames(n)
			collectgarbage("collect")
			collectgarbage("stop")
			local before = collectgarbage("count")
			for _ = 1, n do
				advance(FRAME)
				-- Both mobs cast again the moment they finish, which is what a
				-- caster does and what makes this the steady state rather than
				-- a warm up. One long cast would walk a fresh tenth every tenth
				-- of a second and measure the interning of numbers that are
				-- never drawn twice; a mob casting the same three second spell
				-- draws the same thirty numbers for the rest of the fight.
				--
				-- The two entries are rewritten in place. A fresh table per cast
				-- would be this file allocating inside its own measurement.
				local now = _G.GetTime()
				local entry = enemyCasts.cast.nameplate1
				if entry.finish <= now then
					entry.start, entry.finish = now, now + 3
					entry = enemyCasts.cast.nameplate2
					entry.start, entry.finish = now, now + 3
				end
				barTicker.scripts.OnUpdate(barTicker, FRAME)
			end
			local after = collectgarbage("count")
			collectgarbage("restart")
			return after - before
		end

		-- Cold first, for the reason the bars' own measurement takes a cold
		-- pass: the first run interns every string the row will ever draw.
		frames(200)
		local burn = frames(200)
		print(("cast   %.2f KB per 200 frames with two mobs casting, gate is %.2f")
			:format(burn, CHURN.cast))
		check(burn <= CHURN.cast,
			("the cast sweep allocated %.2f KB per 200 frames, over the %.2f KB gate")
				:format(burn, CHURN.cast))

		enemyCasts.cast.nameplate1, enemyCasts.cast.nameplate2 = nil, nil
		ns.EnemyBars.Update()
	end

	-- The wall clock is shared, and this is the first section in the file to move
	-- it by fractions of a second: everything above it advances in whole tenths
	-- or better. Sections below open a combat segment, advance ten seconds
	-- across it and compare the rate that comes out against an exact 100, and
	-- ten added to a clock carrying fifteen seconds of sixtieths is not exactly
	-- ten seconds later in floating point. So the clock goes back on a whole
	-- second before anything else reads it, and the line under that is what says
	-- so rather than trusting the arithmetic.
	advance(math.ceil(_G.GetTime()) - _G.GetTime())
	check(_G.GetTime() == math.floor(_G.GetTime()),
		("the cast section left the clock at %.9f, and the sections below it want a whole second")
			:format(_G.GetTime()))

	local chamber = ns.EnemyBars.WidgetFor("nameplate1")
	print(("cast   %d px chamber in a %d px box, %d idle, fill exact at 60 and 144 fps, immune flag %s; %s")
		:format(chamber.cast:GetHeight(), chamber.boxOpen, chamber.boxIdle,
			tostring(ns.CastImmuneKnown()), ns.Cast.Describe()))
end

ns.db.barsMode = "list"
ns.EnemyBars.Rebuild()
churn(200)
local listChurn = churn(200)

-- Left for the sections below.
H.carry.listChurn = listChurn
