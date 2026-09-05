local ADDON, ns = ...

local UI = ns.UI

-- The library this file starts. Everything under Ck/ is written to know nothing
-- about WarriorKit, so that lifting it into an addon of its own is a change to
-- this line and to the two TOCs, and nothing else.
ns.Ck = {}

local Animations = {}
ns.Ck.Animations = Animations

--------------------------------------------------------------------------
-- Animation
--
-- Nothing in this addon moved before this file. Every part that looked like it
-- did was a bar being resized on a ticker: the cast fill, the swing timer, the
-- gauges. A resize on a tick is not an animation, it is a number being drawn,
-- and the difference shows up the moment something has to arrive somewhere it
-- was not, wait, and go.
--
-- **Why not the client's own animation groups.** CreateAnimationGroup is on
-- this client and it draws a translation more smoothly than a Lua tick can,
-- because it runs in C between frames. Three things it cannot do are the three
-- this is for. It animates a frame's position by offset and gives nothing back
-- that says where the frame currently is, so a second animation that has to
-- start from wherever the first one got to has to guess; a group's OnFinished
-- is a closure per group, which is an allocation per message; and a group is
-- built, not armed, so a row that appears twice a minute builds two groups a
-- minute for the collector to walk. A tween here is a table that is filled in
-- once and re-armed forever.
--
-- **What a tween is.** A frame, a duration, an easing, and up to two channels:
-- where it sits and how solid it is. Both channels are optional, so a tween
-- with neither is a timer, which is what a message resting on screen is, and
-- the wait is then the same object running through the same tick as the move
-- that preceded it rather than a second mechanism beside it.
--
-- **Why arming is four calls and not one table.** A table handed in per
-- animation is garbage per animation, and the reflow below runs from inside a
-- tween's own completion, which is on the tick path. So a tween is allocated
-- once by whoever owns the frame and re-armed with positional arguments after
-- that. Arm, then Path and Alpha for whichever channels this run wants, then
-- Start. Arm is what clears the previous run, so a tween that was a slide can
-- be re-armed as a fade with no fields left over.
--
-- Nothing here reads a setting, names a frame or knows what is being animated.
--------------------------------------------------------------------------

-- The curves, as functions of the fraction of the run that has elapsed.
--
-- A named table rather than a number naming a curve, because the caller reads
-- better for it and because an easing is a field on the tween: the tick calls
-- `tween.ease(t)` and never asks which one it got.
local Ease = {}
Animations.Ease = Ease

function Ease.linear(t)
	return t
end

-- Fast at first and slowing into place, which is what an object arriving from
-- off the edge of the screen does. This is the default for a reason: linear
-- entry reads as mechanical at any duration, and the eye is reading the last
-- fifth of the move as "did it land" rather than as travel.
function Ease.out(t)
	local u = 1 - t
	return 1 - u * u
end

function Ease.inOut(t)
	if t < 0.5 then
		return 2 * t * t
	end
	local u = 1 - t
	return 1 - 2 * u * u
end

--------------------------------------------------------------------------

-- Every tween currently being advanced. Appended to on Start and swap-removed
-- on finish, which is why the tick walks it backwards: the element moved into a
-- vacated slot has already been visited this frame and must not be beaten
-- twice.
local running = {}

-- The one tick. Armed on the first Start rather than at load, because the addon
-- spends most of a session with nothing moving and a tick that runs on every
-- frame to walk an empty list is the cost this file would otherwise add to
-- every part that never uses it. ns.UI.Ticker gives the frame's OnUpdate back
-- when the last tick on it stops.
local tick

local function Wake()
	if not tick then
		tick = UI.Ticker(UI.Forever, 0, "anim", Animations.Beat)
	elseif not tick:Running() then
		tick:Start()
	end
end

--------------------------------------------------------------------------

-- A tween bound to a frame, built where the frame is built and never on a tick.
--
-- The frame is fixed for the life of the tween because that is what makes the
-- object reusable: a message row that appears, rests and goes fifty times an
-- evening is one table, armed fifty times, and the collector never hears about
-- it.
-- The frame may arrive later. A part that pools its widgets builds the tween
-- with the record rather than with the frame, and binds the two together when
-- the record is handed a frame to drive; Start is where that has to have
-- happened, and is where it is checked.
function Animations.New(frame)
	return {
		frame = frame,
		seconds = 0,
		elapsed = 0,
		delay = 0,
		ease = Ease.linear,
		playing = false,
	}
end

-- Clear whatever the last run set, and set what this one takes.
--
-- Both channels come off here rather than at Start, so that arming is the same
-- three or four lines whichever channels a run wants and a field can never
-- survive from one run into the next. That is the bug this shape exists to
-- refuse: a tween re-armed as a fade that still carries the previous run's
-- path drags the frame back across the screen while it fades.
function Animations.Arm(tween, seconds, ease, delay)
	assert(type(seconds) == "number" and seconds > 0, "a tween runs for a length of time")
	tween.seconds = seconds
	tween.ease = ease or Ease.linear
	tween.delay = delay or 0
	tween.elapsed = 0
	tween.moving = false
	tween.fading = false
	tween.onDone = nil
	-- What the frame was last written to. Held so the tick can compare before
	-- it writes, and cleared here because the frame may have been moved by
	-- somebody else between two runs of this tween.
	tween.atX, tween.atY, tween.atAlpha = nil, nil, nil
	return tween
end

-- Where the frame travels, as one anchor and two ends.
--
-- One anchor throughout rather than an anchor per end, because a frame pinned
-- to two different corners over the run is a frame whose apparent speed depends
-- on its own width. The offsets are what move.
function Animations.Path(tween, point, relative, relativePoint, fromX, fromY, toX, toY)
	tween.moving = true
	tween.point = point
	tween.relative = relative
	tween.relativePoint = relativePoint
	tween.fromX, tween.fromY = fromX, fromY
	tween.toX, tween.toY = toX, toY
	return tween
end

function Animations.Alpha(tween, from, to)
	tween.fading = true
	tween.fromAlpha, tween.toAlpha = from, to
	return tween
end

-- Put it on the list, and hand back what to call when it lands.
--
-- The callback is a field, which is what a completion has to be, and it is
-- called once with the tween it finished. A caller that chains the next run out
-- of it is on the tick path and the `-- hot:` marker on its own definition is
-- what says so; nothing here can work that out for it.
function Animations.Start(tween, onDone)
	assert(type(tween.frame) == "table", "a tween animates a frame")
	tween.onDone = onDone
	if not tween.playing then
		tween.playing = true
		running[#running + 1] = tween
	end
	Wake()
	return tween
end

-- Take it off the list wherever it is, leaving the frame where it stands.
--
-- Used when a message is dismissed under an animation rather than by it. The
-- swap is the same one the tick does; there is no ordering to keep, because
-- every tween is advanced by the same delta.
function Animations.Stop(tween)
	if not tween.playing then
		return false
	end
	tween.playing = false
	tween.onDone = nil
	for index = 1, #running do
		if running[index] == tween then
			running[index] = running[#running]
			running[#running] = nil
			return true
		end
	end
	return false
end

function Animations.Running()
	return #running
end

--------------------------------------------------------------------------

-- One tween written to its frame at one point in its run.
--
-- Both writes are compared against what this tween last wrote. That guard is
-- not a formality on a moving thing: a tween spends its delay in the list
-- without moving, a fade holds the same alpha through the frames a slower slide
-- is still travelling, and a coordinate snapped to a whole pixel repeats
-- itself whenever the frame's own speed is under a pixel a frame. The
-- comparison costs less than the relayout a repeated SetPoint books.
local function Apply(tween, k)
	local frame = tween.frame
	if tween.moving then
		local x = UI.Whole(tween.fromX + (tween.toX - tween.fromX) * k)
		local y = UI.Whole(tween.fromY + (tween.toY - tween.fromY) * k)
		if x ~= tween.atX or y ~= tween.atY then
			tween.atX, tween.atY = x, y
			frame:SetPoint(tween.point, tween.relative, tween.relativePoint, x, y)
		end
	end
	if tween.fading then
		local alpha = tween.fromAlpha + (tween.toAlpha - tween.fromAlpha) * k
		if alpha ~= tween.atAlpha then
			tween.atAlpha = alpha
			frame:SetAlpha(alpha)
		end
	end
end

-- Off the list, then the callback, in that order.
--
-- The order is the whole of it. A completion that arms the next leg of the same
-- animation would otherwise find the tween still on the list, and Start would
-- decline to add it because it is already there, so the second leg would run
-- with the first leg's elapsed time and land instantly.
local function Land(tween, index)
	local last = #running
	running[index] = running[last]
	running[last] = nil
	tween.playing = false
	local done = tween.onDone
	if done then
		tween.onDone = nil
		done(tween)
	end
end

-- Every tween advanced by one frame's worth of time.
--
-- Exported rather than local because ns.UI.Ticker takes a named function and
-- scripts/hot.lua walks out from the name it is given. Nothing else calls it.
function Animations.Beat(delta)
	for index = #running, 1, -1 do
		local tween = running[index]
		if tween.delay > 0 then
			tween.delay = tween.delay - delta
		else
			tween.elapsed = tween.elapsed + delta
			local t = tween.elapsed / tween.seconds
			if t >= 1 then
				t = 1
			end
			Apply(tween, tween.ease(t))
			if t >= 1 then
				Land(tween, index)
			end
		end
	end
	if #running == 0 and tick then
		tick:Stop()
	end
end
