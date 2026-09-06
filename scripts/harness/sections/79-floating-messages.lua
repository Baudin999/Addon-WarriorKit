-- Floating messages
--
-- ns.Ck.Animations and ns.Ck.Float, and the first thing built on them, which is
-- a drop sliding in from the right edge of the screen.
--
-- Seven questions, and not one of them is answerable by reading the files.
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
-- Does the walk keep its footing while the list changes under it. A message
-- leaving stops two other tweens from inside a third one's completion, so the
-- list the tick is halfway through indexing loses entries it has not reached.
-- A bag's worth of drops at once is what found that, and what it read as was a
-- Lua error rather than a wrong number.
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
--
-- One rest offset per side, because both sides are settings now and the left
-- one is not the right one with a sign on it in the file either: it is the same
-- sentence written against the other corner, and that is where a mirrored
-- branch goes wrong.
local WIDTH = 380
local REST = ns.UI.Whole(-(GetScreenWidth() / 2 - 40 - WIDTH))
local LEFT_REST = ns.UI.Whole(GetScreenWidth() / 2 - 40 - WIDTH)

-- Every number the scenes below type out, written onto the lane before the
-- first message moves.
--
-- Typed rather than read off ns.db for the reason above, and written rather
-- than asserted because what the addon starts at is not a fixed number any
-- more: Core\Shipped.lua is a capture of one install, and this lane runs down
-- the left of it at three quarters of a second a message. A section that
-- happened to agree with the shipped screen was a section that stopped
-- agreeing the first time somebody dragged something and re-baked, and every
-- scene below would have failed as a position off by a number nobody
-- recognises. The lane is the subject here; the screen it ships on is section
-- 53's.
local WRITTEN = {
	lootFloatSide = "RIGHT", lootFloatEdge = 40, lootFloatRest = 40,
	lootFloatTop = 100, lootFloatGap = 4, lootFloatEnter = 0,
	lootFloatAlpha = 100, lootFloatSeconds = 0.5, lootFloatHold = 1,
	lootFloatStagger = 0.08, lootFloatMost = 5, lootFloatWidth = 380,
	lootFloatIcon = 50, lootFloatName = 20, lootFloatCount = 16,
}

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

-- Written onto the lane once the screen is empty, because Floats.Apply builds
-- it again and a message halfway across is a message the rebuild drops.
for key, value in pairs(WRITTEN) do
	ns.db[key] = value
end
Floats.Apply()

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
-- A completion that takes other tweens off the list
--
-- The walk's own footing, asked of the library directly, because what goes
-- wrong is arithmetic on the list rather than anything a message does. A
-- message leaving stops the travel and the wait of the row it retires, from
-- inside the fade's own completion, so the list the tick is halfway through
-- indexing loses entries the tick has not reached yet.
--
-- Four tweens, and the third finishes on this frame and stops the first and
-- the last. Both halves of what that used to do are measured: the walk read a
-- slot that had been swapped out from under it, which was a Lua error in
-- somebody's game every time a pull dropped more than a few things, and the
-- entry the swap moved down into a slot it had already beaten was advanced
-- twice in the one frame.
----------------------------------------------------------------------

do
	local boxes, tweens = {}, {}
	for index = 1, 4 do
		boxes[index] = H.region("frame", _G.UIParent)
		tweens[index] = Animations.New(boxes[index])
		-- Six hundred pixels in a second, which is ten a frame at sixty and is
		-- what makes a doubled beat readable off the anchor rather than a
		-- rounding argument.
		Animations.Arm(tweens[index], 1, Animations.Ease.linear, 0)
		Animations.Path(tweens[index], "CENTER", _G.UIParent, "CENTER", 0, 0, 600, 0)
		Animations.Start(tweens[index])
	end

	-- Half a frame, so it lands on the first beat and nothing else does.
	Animations.Arm(tweens[3], FRAME / 2, Animations.Ease.linear, 0)
	Animations.Path(tweens[3], "CENTER", _G.UIParent, "CENTER", 0, 0, 600, 0)
	Animations.Start(tweens[3], function()
		Animations.Stop(tweens[1])
		Animations.Stop(tweens[4])
	end)

	ns.UI.Ticking("anim"):Beat(FRAME)

	check(Animations.Running() == 1,
		("%d tweens are still on the list, and one is: the other three landed or were stopped")
			:format(Animations.Running()))
	check(at(boxes[2]) == 10,
		("the surviving tween is at %s after one frame of ten pixels, so it was beaten twice")
			:format(tostring(at(boxes[2]))))

	Animations.Stop(tweens[2])
	beat(FRAME)
end

----------------------------------------------------------------------
-- A bag's worth at once
--
-- The same thing through the front door, and the scene that found it. Eight
-- drops in one frame is three more than the column holds, so the ceiling
-- dismisses while the stagger is still letting messages in, and every one of
-- those retirements stops two tweens from inside a third one's completion.
----------------------------------------------------------------------

do
	for _ = 1, 8 do
		show("Aegis")
	end
	check(Floats.Count() == 8,
		("eight drops in one frame made %d messages: the three over the ceiling are"
			.. " on their way out, not refused"):format(Floats.Count()))

	beat(4)
	check(Floats.Count() == 0 and Animations.Running() == 0,
		("%d messages and %d tweens survived the burst"):format(
			Floats.Count(), Animations.Running()))
end

----------------------------------------------------------------------
-- The other way across
--
-- The left branch of Push, which is not the right branch with a sign on it:
-- the message pins by the corner nearest the edge it came from, so both the
-- anchor and the arithmetic change, and the rest offset still has the row's
-- width taken off it or the message crosses the middle instead of stopping
-- beside it.
--
-- The top offset moves in the same scene, because a lane resolves its numbers
-- when it is built and a setting that does not reach it is the failure this
-- page's rows were written to avoid. A message opening at the new height is
-- the whole of the proof that the old lane was thrown away.
----------------------------------------------------------------------

do
	ns.db.lootFloatSide = "LEFT"
	ns.db.lootFloatTop = 60
	Floats.Apply()

	local frame = show("Aegis")
	local point, _, relativePoint = frame:GetPoint(1)
	check(point == "TOPLEFT" and relativePoint == "TOPLEFT",
		("a message coming in from the left is pinned %s to %s")
			:format(tostring(point), tostring(relativePoint)))

	local x, y = at(frame)
	check(x == 40 and y == -60,
		("a message starts at %s,%s and the settings said 40 in from the left edge, 60 down")
			:format(tostring(x), tostring(y)))

	beat(0.6)
	x, y = at(frame)
	check(x == LEFT_REST and y == -60,
		("a message came to rest at %s and forty short of the centre from the left is %d")
			:format(tostring(x), LEFT_REST))

	beat(2)
	check(Floats.Count() == 0, "the message did not clear")
end

----------------------------------------------------------------------
-- A setting changed under a message that is still on screen
--
-- The lane is thrown away rather than edited, and there is a message in the
-- old one when that happens. It has to play out on the numbers it started on
-- and hand its row back the ordinary way, because the pool belongs to
-- Feeds/Floats.lua and not to the lane that borrowed the frame.
--
-- The sizes go back to their defaults here as well, and are read off a pooled
-- row on the way past: the frames outlive the setting, so a pool that dressed
-- its rows once would put two icon sizes on the screen at the same time.
----------------------------------------------------------------------

do
	local old = show("Aegis")
	beat(0.2)
	check(old:GetWidth() == WIDTH, ("a row is %s wide"):format(tostring(old:GetWidth())))

	ns.db.lootFloatSide = "RIGHT"
	ns.db.lootFloatTop = 100
	ns.db.lootFloatWidth = 200
	ns.db.lootFloatIcon = 24
	Floats.Apply()

	local new = show("Bloodspiller")
	check(new ~= old, "the second message re-used the frame the first is still holding")
	-- The face rather than the icon on it. The picture is pinned to all four of
	-- that frame's corners now, so the frame is what the setting sizes and the
	-- texture takes its width from anchors the stub deliberately does not
	-- resolve.
	check(new:GetWidth() == 200 and new.face:GetWidth() == 24,
		("the new row is %s wide with a %s icon, and the settings said 200 and 24")
			:format(tostring(new:GetWidth()), tostring(new.face:GetWidth())))
	check(at(new) == -40,
		("the new message came in at %s rather than 40 inside the right edge")
			:format(tostring(at(new))))

	beat(4)
	check(Floats.Count() == 0 and Animations.Running() == 0,
		("%d messages and %d tweens survived the settings change")
			:format(Floats.Count(), Animations.Running()))

	-- Back to the defaults, and the row that comes out of the pool next has to
	-- be dressed in them rather than in what it was built as.
	for key, value in pairs(WRITTEN) do
		ns.db[key] = value
	end
	Floats.Apply()

	local back = show("Aegis")
	check(back:GetWidth() == WIDTH and back.face:GetWidth() == 50,
		("a pooled row came back %s wide with a %s icon and was not re-dressed")
			:format(tostring(back:GetWidth()), tostring(back.face:GetWidth())))
	-- The rim is re-dressed with everything else, and it is the one part of the
	-- row whose size is not the size of anything: ns.Outline hands back four
	-- edges a unit thick, and a hairline that stayed a unit is four pixels on a
	-- scaled frame.
	check(back.face.edges[1]:GetHeight() == ns.Pixel(back.face),
		("the rim came back %s thick and a pixel here is %s")
			:format(tostring(back.face.edges[1]:GetHeight()),
				tostring(ns.Pixel(back.face))))
	beat(4)
	check(Floats.Count() == 0, "the lane did not clear")
end

----------------------------------------------------------------------
-- The rim carries the grade
--
-- The picture is blended rather than added, which makes it an opaque square,
-- and a square gets a hairline round it the way every other icon in the addon
-- does. That line is where the item's grade goes.
--
-- Two rules rather than one, and the split is UI/Slot.lua's: green and up take
-- the grade, anything under it takes the theme's edge. A white drop with a
-- white rim would put the brightest line on the screen round the least
-- interesting item of the pull.
--
-- The pool is what makes this a scene rather than a line. One frame draws both
-- colours over its life, so a repaint that only ran when a row was built would
-- leave an epic's purple round the next grey out of the pool, and nothing else
-- in this section would notice.
----------------------------------------------------------------------

do
	local EPIC = ns.UI.Quality[4]
	local EDGE = ns.UI.Color.edge

	local function rim(frame)
		local edge = frame.face.edges[1]
		return edge.r, edge.g, edge.b
	end

	local epic = show("Arcanite Reaper")
	local r, g, b = rim(epic)
	check(r == EPIC[1] and g == EPIC[2] and b == EPIC[3],
		("an epic's rim came out %s,%s,%s and the palette says %s,%s,%s")
			:format(tostring(r), tostring(g), tostring(b),
				EPIC[1], EPIC[2], EPIC[3]))
	beat(4)

	local white = show("Linen Cloth")
	check(white == epic,
		"the white drop got a second frame, so this says nothing about repainting")
	r, g, b = rim(white)
	check(r == EDGE[1] and g == EDGE[2] and b == EDGE[3],
		("a white drop's rim came out %s,%s,%s and the theme's edge is %s,%s,%s")
			:format(tostring(r), tostring(g), tostring(b),
				EDGE[1], EDGE[2], EDGE[3]))
	beat(4)
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
	.. " 1s on screen, and every one of those is a setting; the other way across"
	.. " rests at %d; three stack at 100, 154 and 208 and climb when the top one"
	.. " goes; %.2f KB to walk 200 frames, %.2f KB of anchors to cross three"
	.. " pixels"):format(REST, LEFT_REST, walk, writes))
