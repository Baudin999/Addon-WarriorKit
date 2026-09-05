-- Floating messages
--
-- ns.Ck.Animations and ns.Ck.Float, and the first thing built on them, which is
-- a drop sliding in from the right edge of the screen.
--
-- Six questions, and not one of them is answerable by reading the files.
--
-- Does a message land where it was told to. The two offsets are measured
-- against different things on purpose, one from the screen's edge and one from
-- its centre, and the whole of that arithmetic happens inside Push. A lane that
-- resolved both against one anchor would look right on the monitor it was
-- written on and be off by half a screen on the next.
--
-- Does the column stay a column. Three drops at once are three slots, and the
-- thing that goes wrong is never the first one: it is the third landing on the
-- second because the slot was computed from a constant row height rather than
-- from the rows.
--
-- Does the stagger stagger. A burst has to read as arrivals, which means the
-- second message is still sitting at the edge on the frame the first has
-- already started moving.
--
-- Do the survivors climb. This is the only behaviour here that runs from inside
-- a tween's own completion, which is the tick path, and it is why Ck/Float.lua
-- carries two `hot:` markers.
--
-- Does arming clear the last run. A tween is re-armed rather than rebuilt, so
-- every field of the previous run has to come off, and the way that fails is a
-- fade that drags the frame back across the screen.
--
-- And does the tick give itself back. The addon spends most of a session with
-- nothing moving, and a library that held an OnUpdate open for all of it would
-- charge every part that animates nothing.

local H = ...
local ns, fire, check = H.ns, H.fire, H.check

local Animations = ns.Ck.Animations
local Floats = ns.Floats

-- One frame at sixty, with the wall clock moved by the same amount. Both are
-- needed: the tick advances a tween and GetTime decides the stagger, because
-- two messages pushed by two events in one frame have no tick between them to
-- count.
local FRAME = 1 / 60

local function beat(seconds)
	local tick = ns.UI.Ticking("anim")
	while seconds > 0 do
		local step = (seconds < FRAME) and seconds or FRAME
		if tick then
			tick:Beat(step)
		end
		H.advance(step)
		seconds = seconds - step
	end
end

local function show(name)
	return Floats.Show(_G.WarriorKitItemLink(name), 1)
end

-- Where a frame sits, as the two numbers this section is about.
local function at(frame)
	local _, _, _, x, y = frame:GetPoint(1)
	return x, y
end

-- Where a message comes to rest on this screen, worked out here rather than
-- read back off the lane, because a test that asks the file under test what the
-- answer is has not asked anything.
--
-- The width is in it, and that is the whole of what was wrong the first time. A
-- message is pinned by the corner nearest the edge it came from, so stopping
-- that corner forty short of the centre puts the rest of the message across it.
-- Forty short means the far edge, and the far edge is a width away.
local WIDTH = 380
local REST = ns.UI.Whole(-(GetScreenWidth() / 2 - 40 - WIDTH))

----------------------------------------------------------------------
-- The event reached it, and the scene drains
--
-- 40-loot-feed.lua fired a dozen CHAT_MSG_LOOT and nothing has ever ticked
-- the messages they pushed. That is worth asserting on its own: the part is
-- wired to the event with no help from this section. Drained after, so the
-- scenes below start on an empty screen.
----------------------------------------------------------------------

check(Floats.Count() > 0,
	"nothing floated for any of the drops 40-loot-feed.lua fired, so CHAT_MSG_LOOT is not reaching Feeds/Floats.lua")

beat(10)
check(Floats.Count() == 0 and Animations.Running() == 0,
	("%d messages and %d tweens survived ten seconds of ticking")
		:format(Floats.Count(), Animations.Running()))
check(ns.UI.Ticking("anim") == nil,
	"the animation tick is still armed with nothing left to move")

----------------------------------------------------------------------
-- One message, from the edge to its rest
--
-- The spec this was built to: in from forty pixels inside the right edge,
-- invisible, to forty pixels off the centre, solid, in half a second; a
-- second on screen; a hundred pixels down from the top.
----------------------------------------------------------------------

do
	local frame = show("Arcanite Reaper")
	check(Floats.Count() == 1, "a drop did not float")
	check(Animations.Running() == 3,
		("one message armed %d tweens, and it is three: the travel, the fade and the wait")
			:format(Animations.Running()))

	local point, _, relativePoint = frame:GetPoint(1)
	check(point == "TOPRIGHT" and relativePoint == "TOPRIGHT",
		("a message coming in from the right is pinned %s to %s")
			:format(tostring(point), tostring(relativePoint)))

	check(frame:GetWidth() == WIDTH,
		("a message is %s wide and the rest offset above was worked out for %d")
			:format(tostring(frame:GetWidth()), WIDTH))

	local x, y = at(frame)
	check(x == -40 and y == -100,
		("a message starts at %s,%s and the lane said 40 in from the right edge, 100 down")
			:format(tostring(x), tostring(y)))
	check(frame:GetAlpha() == 0, "a message is drawn before it has faded in")

	-- Half a second and a little, because a tween lands on the frame its own
	-- clock passes the duration rather than on the frame the caller counted to.
	beat(0.6)
	x, y = at(frame)
	check(x == REST and y == -100,
		("a message came to rest at %s and forty short of the centre of this screen is %d")
			:format(tostring(x), REST))
	check(frame:GetAlpha() == 1,
		("a message rests at %.2f alpha rather than solid"):format(frame:GetAlpha()))

	-- Most of the second it holds for. Still there, still solid, still where it
	-- landed: a hold that let go early would read as a flicker.
	beat(0.8)
	check(Floats.Count() == 1 and frame:GetAlpha() == 1,
		"a message did not hold for the second it was given")

	-- Past the hold and through the fade.
	beat(0.7)
	check(Floats.Count() == 0 and not frame:IsShown(),
		"a message is still on screen after its time and its fade")
	check(ns.UI.Ticking("anim") == nil,
		"the animation tick is still armed with nothing left to move")
end

----------------------------------------------------------------------
-- Three at once
--
-- One under the other, and a beat apart.
----------------------------------------------------------------------

do
	local first, second, third = show("Aegis"), show("Bloodspiller"), show("Emerald Pigment")
	check(Floats.Count() == 3, "three drops in one frame did not make three messages")

	local _, one = at(first)
	local _, two = at(second)
	local _, three = at(third)
	-- Fifty tall with four of air, summed rather than multiplied, because the
	-- rows are not promised to be the same height.
	check(one == -100 and two == -154 and three == -208,
		("the column sits at %s, %s and %s, and it is 100, 154 and 208 down")
			:format(tostring(one), tostring(two), tostring(three)))

	-- One frame. The first is travelling and the other two have not been let
	-- go yet, which is the whole of what a stagger is.
	beat(FRAME)
	local moved = at(first)
	local waiting = at(second)
	check(moved < -40, ("the first message has not moved off the edge, it is at %s")
		:format(tostring(moved)))
	check(waiting == -40,
		("the second message left with the first, from %s, so nothing is staggered")
			:format(tostring(waiting)))

	-- Two staggers and a travel, and a little over.
	beat(0.7)
	check(at(first) == REST and at(second) == REST and at(third) == REST,
		"three messages did not all come to rest on the same line")

	beat(2)
	check(Floats.Count() == 0, "the column did not clear")
end

----------------------------------------------------------------------
-- The climb
--
-- The one behaviour that runs from inside a tween's completion. Two
-- messages far enough apart that the second is resting when the first goes,
-- so what is measured is the climb and not the second one's own entry.
----------------------------------------------------------------------

do
	show("Aegis")
	beat(0.8)
	local second = show("Bloodspiller")

	local _, y = at(second)
	check(y == -154, ("the second message opened at %s rather than under the first")
		:format(tostring(y)))

	-- The first is 0.8 in, holds until 1.5 and has faded by 2.05.
	beat(0.75)
	check(Floats.Count() == 2, "the first message went before its time was up")
	beat(0.6)
	check(Floats.Count() == 1, "the first message did not go")

	-- And the survivor climbs into the slot it left.
	beat(0.6)
	local _, climbed = at(second)
	check(climbed == -100,
		("the surviving message sits at %s and the top of the lane is 100 down")
			:format(tostring(climbed)))

	beat(2)
	check(Floats.Count() == 0, "the lane did not clear")
end

----------------------------------------------------------------------
-- A tween re-armed is a tween with nothing left over
--
-- Arm is what clears the last run, and the way it fails is a travel that
-- survives into a run that meant to fade: the frame slides back across the
-- screen while it goes out.
----------------------------------------------------------------------

do
	local box = H.region("frame", _G.UIParent)
	local tween = Animations.New(box)

	Animations.Arm(tween, 1, Animations.Ease.linear, 0)
	Animations.Path(tween, "CENTER", _G.UIParent, "CENTER", 0, 0, 100, 0)
	Animations.Start(tween)
	beat(1.1)
	check(at(box) == 100, ("a travel finished at %s rather than at 100")
		:format(tostring(at(box))))

	Animations.Arm(tween, 1, Animations.Ease.linear, 0)
	Animations.Alpha(tween, 1, 0)
	Animations.Start(tween)
	beat(1.1)
	check(at(box) == 100,
		("the fade dragged the frame to %s, so the previous run's path survived Arm")
			:format(tostring(at(box))))
	check(box:GetAlpha() == 0, "the fade did not take the frame out")
end

----------------------------------------------------------------------
-- The switch
----------------------------------------------------------------------

do
	ns.db.lootFloat = false
	fire("CHAT_MSG_LOOT", ("You receive loot: %s."):format(_G.WarriorKitItemLink("Aegis")))
	check(Floats.Count() == 0, "a drop floated with the switch off")
	ns.db.lootFloat = true
end

----------------------------------------------------------------------
-- What a frame of animation costs
--
-- Two measurements, and the second is the interesting one.
--
-- The walk first: three messages on the list, beaten with no time passing,
-- so every tween is read, eased and compared and none of them writes. That
-- is what runs on every frame anything is moving, and it has to be free.
--
-- Then the guard. A tween is the one thing in the addon that writes a
-- different value on purpose, so the usual argument for comparing before
-- writing looks like it does not apply. It does: a coordinate is snapped to
-- a whole pixel, and a message crossing three pixels over two hundred
-- frames is three writes, not two hundred.
--
-- Measured through the stub's own cost rather than by counting calls. This
-- client models an anchor as a table per SetPoint, which is 0.14 KB a call
-- and is the stub's arithmetic rather than a game's; here that makes it a
-- counter. Ungated, the same run would be two hundred anchors and 28 KB.
----------------------------------------------------------------------

local walk, writes = 0, 0
do
	show("Aegis")
	show("Bloodspiller")
	show("Emerald Pigment")
	local tick = ns.UI.Ticking("anim")

	-- One beat first, so that the first write of each tween, which is the one
	-- with nothing to compare against, falls outside the window.
	tick:Beat(0)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 200 do
		tick:Beat(0)
	end
	walk = collectgarbage("count") - before
	collectgarbage("restart")
	check(walk < 0.05,
		("two hundred frames of walking three messages allocated %.2f KB"):format(walk))
	beat(3)
end

do
	local box = H.region("frame", _G.UIParent)
	local tween = Animations.New(box)
	-- Three pixels over ten seconds, which at sixty frames is a coordinate that
	-- repeats itself sixty times before it moves, and a fade underneath it that
	-- is a different number every single frame.
	Animations.Arm(tween, 10, Animations.Ease.linear, 0)
	Animations.Path(tween, "CENTER", _G.UIParent, "CENTER", 0, 0, 3, 0)
	Animations.Alpha(tween, 0, 1)
	Animations.Start(tween)
	local tick = ns.UI.Ticking("anim")

	tick:Beat(FRAME)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 200 do
		tick:Beat(FRAME)
	end
	writes = collectgarbage("count") - before
	collectgarbage("restart")
	-- Four anchors' worth of room for three pixels of travel. Two hundred is
	-- what an unguarded tween costs.
	check(writes < 0.6,
		("a tween crossing three pixels over two hundred frames wrote %.2f KB of anchors, and one anchor is about 0.14")
			:format(writes))
	Animations.Stop(tween)
end

-- One more frame, because the tick is what notices that its list is empty. A
-- Stop that gave the OnUpdate back from outside the tick would be a Stop that
-- can tear down the handler the client is halfway through calling.
beat(FRAME)
check(Floats.Count() == 0 and ns.UI.Ticking("anim") == nil,
	"the lane did not clear and hand the tick back")

print(("float  in from 40 inside the right edge to %d, 100 down, 0.5s travel and"
	.. " 1s on screen; three stack at 100, 154 and 208 and climb when the top"
	.. " one goes; %.2f KB to walk 200 frames, %.2f KB of anchors to cross three"
	.. " pixels"):format(REST, walk, writes))
