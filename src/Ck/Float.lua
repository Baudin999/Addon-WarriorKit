local ADDON, ns = ...

local Animations = ns.Ck.Animations
local Ease = Animations.Ease

local Float = {}
ns.Ck.Float = Float

--------------------------------------------------------------------------
-- Floating messages
--
-- A message arrives from one side of the screen, holds where it landed, and
-- fades. Several at once form a column under the first, each entering a beat
-- after the one above it, and when the top one goes the rest climb into the
-- space it left.
--
-- **A lane, not a message.** The interesting part is never one message. One
-- message is a slide and a fade and would be four lines at the call site. What
-- costs a file is the second one arriving while the first is still travelling,
-- and the third landing after the first has gone. So the object here is the
-- column: it owns the order, the slots and the stagger, and a caller hands it a
-- finished frame and gets told when that frame is free again.
--
-- **The two offsets are measured against different things on purpose.** A
-- message comes in from an edge and rests near the middle, and those are two
-- different questions. `enterEdge` is how far inside the screen's edge it
-- starts, which is a fact about the edge it is coming from; `restCentre` is how
-- far short of the screen's centre it stops, which is a fact about where the
-- eye is. Expressing both against one anchor would mean the caller doing the
-- screen-width arithmetic, and doing it again on every resolution change. Both
-- are resolved here, at the moment a message is pushed, so a lane written once
-- is right on every monitor.
--
-- **They are also measured to different edges of the message, which is the part
-- that was wrong first.** A message is pinned by the corner nearest the side it
-- came from, so the entry offset is a distance to that corner and needs no
-- width. The rest offset is not: the eye reads the message by its far edge, and
-- a lane that stopped the near corner forty pixels short of the centre put two
-- hundred and twenty pixels of message across it. So the rest offset is
-- measured to the far edge and the width is taken off.
--
-- **Why the frames belong to the caller.** This file draws nothing. A loot row
-- is an icon, a name in the item's own colour and a count; an achievement is a
-- different shape and a warning is a third. A lane that built its own rows
-- would have to know all three, and the one thing it actually needs from a row
-- is how tall it is. So `Push` takes a frame and a height, and `onGone` hands
-- the frame back when the message has finished, which is where a caller pools
-- it.
--
-- The lane's own bookkeeping is pooled here for the same reason the tweens are:
-- a message that appears fifty times an evening must not be fifty tables for
-- the collector, because the reflow below runs from inside a tween's completion
-- and that is the tick path.
--------------------------------------------------------------------------

local Lane = {}
Lane.__index = Lane

-- Which corner of the screen a side pins to. The row is anchored by the same
-- corner it is anchored to, so the offsets below are distances from that edge
-- and a row's own width never enters the arithmetic.
local CORNER = { RIGHT = "TOPRIGHT", LEFT = "TOPLEFT" }

-- spec.side        "RIGHT" or "LEFT", the edge messages come in from
-- spec.enterEdge   pixels inside that edge where a message starts
-- spec.restCentre  pixels short of the screen's centre where it stops
-- spec.enterAlpha  how solid it is at the start
-- spec.restAlpha   how solid it is once it has landed
-- spec.seconds     how long the travel and each fade take
-- spec.ttl         how long it holds once it has landed
-- spec.top         pixels from the top of the screen to the first message
-- spec.gap         pixels between one message and the next
-- spec.stagger     the least time between two messages entering
-- spec.most        how many messages the column shows at once
-- spec.ease        the curve the travel follows
-- spec.onGone      called with a frame the lane has finished with
function Float.Lane(spec)
	local side = spec.side or "RIGHT"
	assert(CORNER[side], "a lane comes in from the RIGHT or the LEFT")
	return setmetatable({
		side = side,
		point = CORNER[side],
		enterEdge = spec.enterEdge or 40,
		restCentre = spec.restCentre or 40,
		enterAlpha = spec.enterAlpha or 0,
		restAlpha = spec.restAlpha or 1,
		seconds = spec.seconds or 0.5,
		ttl = spec.ttl or 1,
		top = spec.top or 100,
		gap = spec.gap or 4,
		stagger = spec.stagger or 0.08,
		most = spec.most or 5,
		ease = spec.ease or Ease.out,
		onGone = spec.onGone,
		rows = {},
		spare = {},
	}, Lane)
end

--------------------------------------------------------------------------

-- Where the message at this position in the column sits, measured down from the
-- top of the screen.
--
-- Summed rather than multiplied, because the rows are not all the same height:
-- a loot row with a wrapped name is taller than the one above it, and a column
-- laid out on a constant would overlap it. This is the same argument
-- ns.UI.Stack makes for asking a row how tall it is.
local function Slot(lane, index)
	local y = lane.top
	for above = 1, index - 1 do
		y = y + lane.rows[above].height + lane.gap
	end
	return -y
end

-- Every message moved to the slot it now occupies.
--
-- Retargeting rather than restarting. A row that is already travelling to this
-- slot is left alone, which is what stops a burst of arrivals from re-arming
-- each other's entries every time one of them lands. A row that is not gets its
-- travel re-armed from wherever it currently stands, so a message still sliding
-- in when the one above it expires bends towards the new slot instead of
-- jumping to it.
--
-- The delay is carried across. A message still waiting its turn to enter has
-- not been drawn anywhere yet, and re-arming it with no delay would fire it in
-- ahead of the message it was queued behind.
local function Reflow(lane)
	for index = 1, #lane.rows do
		local row = lane.rows[index]
		local move = row.move
		local y = Slot(lane, index)
		if move.toY ~= y then
			local fromX = move.atX or move.fromX
			local fromY = move.atY or move.fromY
			local delay = move.delay
			if delay < 0 then
				delay = 0
			end
			Animations.Arm(move, lane.seconds, lane.ease, delay)
			Animations.Path(move, lane.point, UIParent, lane.point,
				fromX, fromY, row.restX, y)
			Animations.Start(move)
		end
	end
end

-- hot: Leave is a tween's onDone, called back through the field when a message has finished fading
local function Leave(tween)
	local row = tween.row
	local lane = row.lane
	local rows = lane.rows
	for index = 1, #rows do
		if rows[index] == row then
			table.remove(rows, index)
			break
		end
	end

	-- Both of the other two taken off the tick as well. The hold has already
	-- landed, but a reflow that caught this message on its way out re-armed the
	-- travel for a full transition, and a pooled row whose travel is still
	-- running writes a position onto a hidden frame every frame until it ends.
	Animations.Stop(row.move)
	Animations.Stop(row.hold)

	local frame = row.frame
	frame:Hide()
	row.frame = nil
	lane.spare[#lane.spare + 1] = row
	if lane.onGone then
		lane.onGone(frame)
	end
	Reflow(lane)
end

-- Send a message out, whether its time ran out or the column needs the room.
--
-- From wherever it currently stands rather than from solid, because a message
-- pushed off the bottom of a full column may still be fading in, and a fade
-- that starts at full alpha on a frame drawn at a fifth of it is a flash.
--
-- Asked twice is not asked twice. A row already on its way out is skipped, and
-- that is what stops the ceiling below from dismissing the same top message on
-- every one of six drops that arrive together.
local function Dismiss(row)
	if row.leaving then
		return false
	end
	row.leaving = true
	local lane = row.lane
	local from = row.fade.atAlpha or lane.restAlpha
	Animations.Stop(row.hold)
	Animations.Arm(row.fade, lane.seconds, Ease.linear, 0)
	Animations.Alpha(row.fade, from, 0)
	Animations.Start(row.fade, Leave)
	return true
end

-- hot: Expire is a tween's onDone, called back through the field when a message's time on screen runs out
local function Expire(tween)
	Dismiss(tween.row)
end

--------------------------------------------------------------------------

-- One row's bookkeeping and the three tweens it runs on, built once and re-used
-- for every message that lands in this position of the column.
--
-- Three rather than one, because a message is doing three things at once and
-- they do not share a clock. The travel eases and the fade does not. The hold
-- is a tween with no channels at all, which is this library's answer to a timer:
-- one mechanism, one tick, and the wait ends up on the performance tab beside
-- the movement rather than in a C timer nothing measures.
local function NewRow(lane)
	local row = { lane = lane }
	row.move = Animations.New(nil)
	row.fade = Animations.New(nil)
	row.hold = Animations.New(nil)
	row.move.row, row.fade.row, row.hold.row = row, row, row
	return row
end

-- Send a frame in.
--
-- The frame is the caller's, already built, already sized and parented. Height
-- is asked for rather than measured because a row that grows to fit its own
-- text has not been laid out yet at the moment it is pushed, and a height read
-- off it here would be last message's.
function Lane:Push(frame, height)
	-- The ceiling, before anything else. A column that grew with the drops
	-- would cover the screen on a full bag, and the message worth losing is the
	-- oldest one rather than the one that just arrived.
	local live = 0
	for index = 1, #self.rows do
		if not self.rows[index].leaving then
			live = live + 1
		end
	end
	if live >= self.most then
		for index = 1, #self.rows do
			if Dismiss(self.rows[index]) then
				break
			end
		end
	end

	local row = table.remove(self.spare) or NewRow(self)
	row.frame, row.height, row.leaving = frame, height, false
	row.move.frame, row.fade.frame, row.hold.frame = frame, frame, frame
	self.rows[#self.rows + 1] = row

	-- Both offsets resolved here rather than held on the lane, so a lane
	-- survives a resolution change and a UI scale change without being told
	-- about either.
	local half = GetScreenWidth() / 2
	-- Width read off the frame where height is asked for, and the difference is
	-- not an inconsistency. A caller sets a width, because a message that grew
	-- to fit its own text would be a message whose left edge moves with the
	-- name in it. A height it cannot set, because a row that wraps has not been
	-- laid out at the moment it is pushed.
	local width = frame:GetWidth() or 0
	local enterX, restX
	if self.side == "RIGHT" then
		enterX, restX = -self.enterEdge, -(half - self.restCentre - width)
	else
		enterX, restX = self.enterEdge, half - self.restCentre - width
	end
	row.restX = restX

	-- A beat behind whatever went before it, and no wait at all when nothing
	-- did. Measured from when the last message was cleared to enter rather than
	-- from now, so a burst of six arriving in one frame comes in as six beats
	-- and not as one.
	local now = GetTime()
	local delay = 0
	if self.lastEntry and now < self.lastEntry + self.stagger then
		delay = self.lastEntry + self.stagger - now
	end
	-- And a ceiling on the queue behind it, which is the half that is not
	-- obvious and is what a whole bag of loot found. Each message is booked a
	-- beat after the last one was, so a burst larger than the column can hold
	-- books beats for messages the ceiling above has already decided not to
	-- show: forty drops at eight hundredths of a second is three seconds of
	-- backlog, and the last of them arrives long after the fight is over.
	-- Nothing waits longer than it takes the column to fill.
	local longest = self.stagger * self.most
	if delay > longest then
		delay = longest
	end
	self.lastEntry = now + delay

	local y = Slot(self, #self.rows)
	frame:ClearAllPoints()
	frame:SetPoint(self.point, UIParent, self.point, enterX, y)
	frame:SetAlpha(self.enterAlpha)
	frame:Show()

	Animations.Arm(row.move, self.seconds, self.ease, delay)
	Animations.Path(row.move, self.point, UIParent, self.point, enterX, y, restX, y)
	Animations.Start(row.move)

	Animations.Arm(row.fade, self.seconds, Ease.linear, delay)
	Animations.Alpha(row.fade, self.enterAlpha, self.restAlpha)
	Animations.Start(row.fade)

	-- One tween for the entry and the hold together, rather than a second one
	-- armed when the first lands. Chaining would put the hold's start on the
	-- frame the travel finished, which is a frame late and drifts by that much
	-- every time; this lands exactly ttl after the message came to rest.
	Animations.Arm(row.hold, self.seconds + self.ttl, Ease.linear, delay)
	Animations.Start(row.hold, Expire)
	return row
end

-- How many messages the lane is showing, for the harness and for a caller
-- deciding whether it has already said this.
function Lane:Count()
	return #self.rows
end
