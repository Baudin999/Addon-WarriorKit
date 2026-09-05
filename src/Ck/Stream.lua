local ADDON, ns = ...

local UI = ns.UI
local Ease = ns.Ck.Animations.Ease

local Stream = {}
ns.Ck.Stream = Stream

--------------------------------------------------------------------------
-- Numbers thrown onto a curve
--
-- A thing appears at a point, flies a fixed path, shrinks, fades and is gone.
-- Several at once do not know about each other and never move out of each
-- other's way. That is the whole of it, and it is a different object from
-- Ck/Float.lua rather than a setting on it.
--
-- **Why this is not a lane and not a tween.** Ck/Animations.lua interpolates a
-- frame from one place to another and its hard part is interruption: a message
-- already travelling is re-aimed at a new slot from wherever it currently
-- stands, because the one above it expired. Ck/Float.lua exists to do that
-- re-aiming. Nothing here is ever re-aimed. A number's position at any moment
-- is a function of how long it has been alive, which style it was thrown with
-- and the seed it was born with, and no other number can change it.
--
-- That difference is worth a file because it removes the machinery rather than
-- adding to it. There is no start and no end to interpolate between, so the arc
-- and the scale envelope are evaluated rather than stored, and a caller who
-- wants a different shape writes a different style instead of arming a fourth
-- channel. A tween with a scale channel, a curved path and one easing per
-- channel would do this, and it would cost Ck/Animations.lua eight fields that
-- are nil on every run a message makes.
--
-- **What a style is.** Every number in one class of event flies the same way,
-- so the numbers that say how are held once, in a table built at setup, and an
-- item points at one. A critical is the ordinary style with a larger start, a
-- punch on the front and a later fade, and saying that is a second table rather
-- than a branch on the tick.
--
-- **What an item carries that its style does not.** Its seed. Two numbers
-- thrown in the same frame with the same style would otherwise draw on top of
-- each other for their whole life, which is the failure every floating number
-- in this game has and the reason the client's own jitters. So the bow, the
-- start and the height are nudged per item, decided once at birth and never
-- re-rolled, because a jitter re-rolled per frame is a number that vibrates.
--
-- **Why one frame and not two.** A frame's own offsets are read in its own
-- scale, so a frame shrinking from 1.0 to 0.7 while it travels covers seven
-- tenths of the distance it was told to. The obvious answer is a positioner
-- outside a scaler, which is two frames per number and a rig for the caller to
-- build. The offsets are divided by the scale instead. One frame, one division
-- an axis, and the number lands where the style said it would.
--
-- Nothing here reads a setting, names a frame or knows what a number means.
--------------------------------------------------------------------------

-- How far along the bow a number is, as a fraction of its sideways reach.
--
-- Zero at both ends and one in the middle, so a number leaves its anchor, drifts
-- out and comes back as it fades. A sine reads a shade smoother and costs a
-- trig call per number per frame to say the same thing at these sizes.
local function Bow(t)
	return 4 * t * (1 - t)
end

-- The defaults a style is filled in against, so a caller writing one names the
-- numbers it cares about. They describe an ordinary hit, because that is the
-- shape everything else is a variation on.
local STYLE = {
	-- How long one number is alive, in seconds.
	seconds = 1.3,
	-- How far it falls over that life, in the anchor's units.
	drop = 90,
	-- How far it bows sideways at the halfway point.
	arc = 18,
	-- Large to small. The end is the readable floor rather than nothing: a
	-- number that shrinks to a dot has spent its last third being unreadable.
	fromScale = 1,
	toScale = 0.72,
	-- An extra helping of scale at birth, gone by `punchFor` of the life. This
	-- is what reads as impact. A number that is merely born bigger reads as a
	-- bigger font.
	punch = 0,
	punchFor = 0.12,
	-- Fading in, as a fraction of the life. Short: a number is a report of
	-- something that already happened and should be legible immediately.
	dawn = 0.06,
	-- How much of the life is spent solid before the fade starts. The rest of
	-- it is the fade, so a later hold is a shorter and therefore steeper fade
	-- over a longer readable stretch.
	holdFor = 0.45,
	-- The fall's curve. Out is fast then slowing, which is a thing settling.
	-- Linear reads as debris dropping.
	ease = Ease.out,
}

--------------------------------------------------------------------------

-- Every number in the air. One list for every style and every anchor, because
-- they are all advanced by the same delta and nothing here cares about order.
local flying = {}
local tick

-- Rolled per item at birth. A counter rather than math.random, because two
-- numbers born in the same frame have to differ and a random pair sometimes
-- does not, and because a sequence is the same on every machine when the
-- harness reads it.
local seed = 0

--------------------------------------------------------------------------

-- One style, filled in against the defaults. Built at setup and never on a
-- tick: this is the one allocation in the file and a caller makes a handful of
-- them for the life of the session.
function Stream.Style(spec)
	local style = {}
	for key, value in pairs(STYLE) do
		local given = spec and spec[key]
		if given ~= nil then
			style[key] = given
		else
			style[key] = value
		end
	end
	assert(style.seconds > 0, "a number is alive for a length of time")
	assert(style.holdFor < 1, "a number that holds for its whole life never fades")
	assert(style.punchFor > 0 and style.dawn > 0, "a fraction of a life is more than none of it")
	-- Who takes the frame back when the number has gone. A style rather than an
	-- argument, because the frame came from the caller's pool and the style is
	-- already the thing that says which pool.
	style.onGone = spec and spec.onGone
	return style
end

--------------------------------------------------------------------------

-- Item tables, taken back when a number lands and never made on the tick after
-- the first few. A pull throws forty numbers a second and a table per number is
-- forty tables a second for the collector to walk, which is the cost this addon
-- has already paid twice and gated against once.
local spare = {}

-- Forward, because a number is placed once where it is born and again on every
-- tick after that, and the two callers sit either side of the definition.
local Place

local function Take()
	local item = spare[#spare]
	if item then
		spare[#spare] = nil
		return item
	end
	-- The one allocation, and it happens as many times as the busiest second of
	-- the session ever needs at once. The return above is the guard: this line
	-- is reached only while the pool is empty, which is the first few numbers of
	-- a session and never again.
	return {} -- allocates: the pool was empty, which happens as many times as the busiest second ever needs at once
end

-- The tick, armed on the first number rather than at load. An addon that spends
-- an evening out of combat should not be walking an empty list on every frame
-- the client draws. ns.UI.Ticker hands the OnUpdate back when the last tick on
-- the frame stops.
local function Wake()
	if not tick then
		tick = UI.Ticker(UI.Forever, 0, "numbers", Stream.Beat)
	elseif not tick:Running() then
		tick:Start()
	end
end

--------------------------------------------------------------------------

-- Throw one number.
--
--   anchor  the frame it flies away from, which is where the player put it
--   frame   the caller's own, already built, filled and sized
--   style   one of the tables Stream.Style made
--   weight  a multiplier on the whole scale envelope, or nil for one
--   key     what a later number has to match to merge into this one, or nil
--
-- Positional rather than a table of named fields, because this is called from a
-- combat log reader and a table an argument is a table a line.
function Stream.Push(anchor, frame, style, weight, key)
	assert(type(frame) == "table" and type(anchor) == "table", "a number flies from an anchor")

	local item = Take()
	item.anchor, item.frame, item.style = anchor, frame, style
	item.weight = weight or 1
	item.key = key
	item.elapsed = 0
	-- The punch runs on its own clock so that a number merged into can be hit
	-- again without its fall or its fade being wound back, which would read as
	-- the number jumping up the screen.
	item.punched = 0
	-- What the frame was last written to, cleared because the frame has been
	-- somewhere else in a previous life.
	item.atX, item.atY, item.atScale, item.atAlpha = nil, nil, nil, nil

	-- The seed, rolled once. Alternating sides rather than a random one, so two
	-- numbers in the same frame always bow apart instead of sometimes bowing
	-- together.
	seed = seed + 1
	item.side = (seed % 2 == 0) and 1 or -1
	-- Three sevenths, five sevenths, one, in a cycle. Enough spread that a
	-- burst reads as several numbers and not enough that one of them lands
	-- somewhere the anchor does not explain.
	item.spread = 0.4 + 0.3 * (seed % 3)
	-- And a head start down the fall, so a burst does not draw as one row.
	item.lead = (seed % 4) * 0.03

	flying[#flying + 1] = item
	frame:ClearAllPoints()
	Place(item, item.lead)
	frame:Show()
	Wake()
	return item
end

-- The number this one should join rather than sit on top of, or nil.
--
-- Asked by the caller before it throws, because what counts as the same thing
-- happening twice is a fact about damage and not about animation. `before` is
-- how far into its life a number may be and still be merged into: a number
-- already fading is one the eye has finished with, and adding to it reads as a
-- number that changed its mind.
function Stream.Find(key, before)
	for index = 1, #flying do
		local item = flying[index]
		if item.key == key and item.elapsed < item.style.seconds * before then
			return item
		end
	end
	return nil
end

-- Hit again. The fall and the fade are left exactly where they were and only
-- the punch is wound back, so the number swells in place rather than leaping.
function Stream.Bump(item, weight)
	item.punched = 0
	item.weight = weight or item.weight
	return item
end

--------------------------------------------------------------------------

-- One number written to its frame at one point in its flight.
--
-- Every write is compared against what this item last wrote, which is a gate
-- rather than a courtesy: a number spends its last third moving under a pixel a
-- frame and would otherwise book a relayout on every one of them.
--
-- The offsets are divided by the scale because a frame's own offsets are read
-- in its own scale, and a number that shrinks while it travels would otherwise
-- fall short of where the style said it lands.
function Place(item, t)
	local style = item.style
	local frame = item.frame

	local scale = style.fromScale + (style.toScale - style.fromScale) * t
	local punch = item.punched / (style.punchFor * style.seconds)
	if punch < 1 then
		scale = scale + style.punch * (1 - punch)
	end
	scale = scale * item.weight
	if scale ~= item.atScale then
		item.atScale = scale
		frame:SetScale(scale)
	end

	local x = style.arc * Bow(t) * item.side * item.spread
	local y = -style.drop * style.ease(t)
	x = UI.Whole(x / scale)
	y = UI.Whole(y / scale)
	if x ~= item.atX or y ~= item.atY then
		item.atX, item.atY = x, y
		frame:SetPoint("CENTER", item.anchor, "CENTER", x, y)
	end

	local alpha = 1
	if t < style.dawn then
		alpha = t / style.dawn
	elseif t > style.holdFor then
		alpha = (1 - t) / (1 - style.holdFor)
	end
	if alpha ~= item.atAlpha then
		item.atAlpha = alpha
		frame:SetAlpha(alpha)
	end
end

-- One number moved on by a frame's worth of time, and whether that finished it.
local function Step(item, delta)
	item.elapsed = item.elapsed + delta
	item.punched = item.punched + delta
	local t = item.elapsed / item.style.seconds + item.lead
	if t >= 1 then
		return true
	end
	Place(item, t)
	return false
end

-- One number off the list and its frame back to whoever owns it.
local function Land(item, index)
	local last = #flying
	flying[index] = flying[last]
	flying[last] = nil

	local frame, style = item.frame, item.style
	item.frame, item.anchor, item.key = nil, nil, nil
	spare[#spare + 1] = item
	frame:Hide()
	if style.onGone then
		style.onGone(frame)
	end
end

-- Every number advanced by one frame's worth of time.
--
-- Backwards, and the swap that takes an entry off is safe for exactly that
-- reason: the entry moved down into the hole came from above the walk and has
-- already been beaten, and a number thrown from inside a completion lands past
-- the end and starts on the next frame. Ck/Animations.lua cannot do this and
-- carries a longer answer, because a tween's completion stops other tweens and
-- that is a removal the walk did not make. Nothing here removes anything but
-- the number it is holding.
--
-- Exported rather than local because ns.UI.Ticker takes a named function and
-- scripts/hot.lua walks out from the name it is given.
function Stream.Beat(delta)
	for index = #flying, 1, -1 do
		local item = flying[index]
		if Step(item, delta) then
			Land(item, index)
		end
	end
	if #flying == 0 and tick then
		tick:Stop()
	end
end

-- Every number off the screen at once, for a part being switched off.
function Stream.Clear()
	for index = #flying, 1, -1 do
		Land(flying[index], index)
	end
end

function Stream.Count()
	return #flying
end

-- One number in the air, by position in the list. The order is not meaningful
-- and the list is walked backwards, so this is a way in for the harness and for
-- a caller counting its own, and not an order anything may rely on.
function Stream.At(index)
	return flying[index]
end
