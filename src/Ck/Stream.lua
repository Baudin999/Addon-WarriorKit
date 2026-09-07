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
-- harder attack and a later fade, and saying that is a second table rather than
-- a branch on the tick.
--
-- **What an item carries that its style does not.** Its seed. Two numbers
-- thrown in the same frame with the same style would otherwise draw on top of
-- each other for their whole life, which is the failure every floating number
-- in this game has and the reason the client's own jitters. So the bow, the
-- start and the height are nudged per item, decided once at birth and never
-- re-rolled, because a jitter re-rolled per frame is a number that vibrates.
--
-- **And which way it bows is the caller's, not the seed's.** A stream that
-- alternates is one column of numbers opening both ways, which is what this
-- shipped as and reads as a mess the moment there are two columns: half of one
-- side leans into the other. So the caller says `lean` at the moment it throws,
-- because it is the only thing that knows what the column means. The seed still
-- decides when the caller has no opinion.
--
-- The bow alone was not enough of it. Two blows a tenth of a second apart came
-- off the same point at the same height and crossed each other on the way down,
-- and a bow of eighteen pixels around a sixty pixel glyph is inside the glyph.
-- An item is given a height at birth as well as a side and a reach, so a burst
-- opens as a scatter rather than as a column, and the scatter is a style's
-- number because it belongs to the class of event rather than to the number.
--
-- **The envelope has an attack, and that is what reads as a hit.** Every
-- channel here used to decay from the instant of birth: a number appeared at
-- its largest and shrank, which is the shape of something receding. A blow
-- landing is the other shape. It arrives, it goes past where it is going to
-- rest, it comes back, and only then does it leave. So the scale channel is
-- two things multiplied rather than one interpolation: a slow drift from
-- `fromScale` to `toScale` over the whole life, and a fast `Attack` over the
-- first tenth of a second that starts under the rest, overshoots it by `over`
-- and settles back. The drift is the number ageing and the attack is the blow.
--
-- `beat` is the other half of the same idea. A number that starts falling on
-- the frame it is born never holds still long enough to be read, so the fall
-- and the bow are held at nothing for the first `beat` of the life and the
-- ease is stretched over what is left. Nothing about a critical is a different
-- kind of thing from an ordinary hit: it is a larger `over`, a longer `beat`
-- and a later fade, which is a bigger version of one shape rather than a
-- second shape.
--
-- **Why one frame and not two.** A frame's own offsets are read in its own
-- scale, so a frame shrinking from 1.0 to 0.7 while it travels covers seven
-- tenths of the distance it was told to. The obvious answer is a positioner
-- outside a scaler, which is two frames per number and a rig for the caller to
-- build. The offsets are divided by the envelope instead. One frame, one
-- division an axis, and the number lands where the style said it would.
--
-- **Why the scale is two numbers and not one.** `ground` is whatever the
-- caller's frame is already scaled by and the envelope is what this file does
-- on top of it. They are separated rather than multiplied together by the
-- caller because the offsets are divided by the envelope alone: a caller whose
-- frames sit on ns.UI's pixel grid carries the grid's scale in `ground`, and a
-- fall of ninety is then ninety of the caller's own pixels rather than ninety
-- divided by however large the grid made the glyph. Fold the two into one and
-- the fall shrinks every time the font grows, which is not a thing anybody
-- asked for and is invisible until somebody drags the size slider.
--
-- Nothing here reads a setting, names a frame or knows what a number means.
--------------------------------------------------------------------------

-- How much of its reach a number is already out by when it is born, before the
-- bow has taken it anywhere.
--
-- The bow used to be zero at both ends, and that is where two numbers meshed. A
-- burst is not spread evenly through a flight: they arrive together, so they
-- are all near the start of theirs at the same moment, and with a beat in front
-- of the fall they sit on one vertical line for the whole of the part of the
-- flight the eye actually reads. Both ends of the bow are the crowded ends.
--
-- So a number leaves its anchor already off to its own side and bows further
-- out from there. It never crosses the line the anchor is on and never comes
-- back to it.
local SPLAY = 0.55

-- How far along the bow a number is, as a fraction of its sideways reach.
--
-- Splayed at both ends and one in the middle, so a number leaves its anchor
-- already out, drifts further and comes back to where it started rather than to
-- the middle. A sine reads a shade smoother and costs a trig call per number per
-- frame to say the same thing at these sizes.
local function Bow(t)
	return SPLAY + (1 - SPLAY) * 4 * t * (1 - t)
end

-- The defaults a style is filled in against, so a caller writing one names the
-- numbers it cares about. They describe an ordinary hit, because that is the
-- shape everything else is a variation on.
local STYLE = {
	-- How long one number is alive, in seconds.
	seconds = 1.3,
	-- How far it falls over that life, in the caller's own pixels.
	drop = 90,
	-- How far it bows sideways at the halfway point.
	arc = 18,
	-- How far up or down a number may be born off its anchor, either way. Zero
	-- is a column: every number in one burst starts on the same row and the bow
	-- is all that separates them, which is not enough once the glyphs are taller
	-- than the bow is wide.
	scatter = 0,
	-- What the caller's frame is already scaled by, and the envelope below
	-- multiplies it. One for a frame on nobody's grid.
	ground = 1,
	-- Large to small, over the whole life. The end is the readable floor rather
	-- than nothing: a number that shrinks to a dot has spent its last third
	-- being unreadable, which is what 0.72 did here until somebody looked at it
	-- on a screen.
	fromScale = 1,
	toScale = 0.85,
	-- The attack, which is the part that reads as a blow landing rather than as
	-- a caption receding. `birth` is the fraction of the resting size a number
	-- appears at, `rise` is how long in seconds it takes to reach its peak,
	-- `over` is how far past the rest that peak is, and `settle` is how long it
	-- takes to come back down to it. Fifty to eighty milliseconds of rise is
	-- what an impact is: longer and it reads as a thing growing, shorter and
	-- the eye never sees the movement at all and it is back to a number that
	-- was simply born big.
	birth = 0.6,
	rise = 0.06,
	over = 0.16,
	settle = 0.1,
	-- Fading in, as a fraction of the life. Two frames at sixty a second and
	-- shorter than the attack on purpose: a number that is still fading in
	-- while it snaps up is a number whose snap happens at two thirds opacity,
	-- which is most of the impact given away. It was 0.06, which outlasted the
	-- rise, and that is the sort of thing only a filmstrip finds.
	dawn = 0.025,
	-- How much of the life is spent still before the fall starts, as a fraction
	-- of it. The attack runs inside this, so what the eye gets is a number that
	-- snaps up, holds where it landed and only then leaves.
	beat = 0.1,
	-- How much of the life is spent solid before the fade starts. The rest of
	-- it is the fade, so a later hold is a shorter and therefore steeper fade
	-- over a longer readable stretch.
	holdFor = 0.45,
	-- The fall's curve. Out is fast then slowing, which is a thing settling.
	-- Linear reads as debris dropping.
	ease = Ease.out,
}

-- The attack, as a multiplier on whatever size the drift says this number is.
--
-- Three straight pieces of one curve: up from where the item was struck from,
-- past the rest by `over`, and back down to one, where it stays for the rest of
-- the life. Both halves are eased out rather than linear, so the peak is a turn
-- and not a corner.
--
-- `item.from` rather than `style.birth` because a number merged into is struck
-- again in mid air. A new number comes up from under its resting size; one that
-- is already on the screen swells from where it is, because dropping it back to
-- six tenths first would read as the number flinching.
local function Attack(item, style)
	local age = item.struck
	if age < style.rise then
		return item.from + (1 + style.over - item.from) * Ease.out(age / style.rise)
	end
	local settling = age - style.rise
	if settling < style.settle then
		return 1 + style.over * (1 - Ease.out(settling / style.settle))
	end
	return 1
end

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
	assert(style.beat < 1, "a number that is still for its whole life never falls")
	assert(style.dawn > 0, "a fraction of a life is more than none of it")
	assert(style.rise > 0 and style.settle > 0,
		"an impact takes a length of time to arrive and a length of time to settle")
	assert(style.ground > 0, "a frame is drawn at a scale")
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
--   lean    -1 to bow left of the anchor, 1 to bow right, 0 or nil to alternate
--
-- Positional rather than a table of named fields, because this is called from a
-- combat log reader and a table an argument is a table a line.
function Stream.Push(anchor, frame, style, weight, key, lean)
	assert(type(frame) == "table" and type(anchor) == "table", "a number flies from an anchor")

	local item = Take()
	item.anchor, item.frame, item.style = anchor, frame, style
	item.weight = weight or 1
	item.key = key
	item.elapsed = 0
	-- The attack runs on its own clock so that a number merged into can be hit
	-- again without its fall or its fade being wound back, which would read as
	-- the number jumping up the screen. `from` is where that clock starts from,
	-- and it is the one thing about the attack a bump changes.
	item.struck = 0
	item.from = style.birth
	-- What the frame was last written to, cleared because the frame has been
	-- somewhere else in a previous life.
	item.atX, item.atY, item.atScale, item.atAlpha = nil, nil, nil, nil

	-- The seed, rolled once, and the side the caller asked for over it.
	--
	-- Alternating is what a stream on its own wants: two numbers in the same
	-- frame always bow apart instead of sometimes bowing together. A caller
	-- drawing two columns wants the opposite and knows it, so `lean` wins where
	-- it is given. What separates two numbers in a leaning column is the height
	-- and the reach below, which is the half of the scatter that never depended
	-- on the side.
	seed = seed + 1
	if lean and lean ~= 0 then
		item.side = lean
	else
		item.side = (seed % 2 == 0) and 1 or -1
	end
	-- Seven tenths, seventeen twentieths, all of it, in a cycle. Enough spread
	-- that a burst reads as several numbers and not enough that one of them
	-- lands somewhere the anchor does not explain. It was 0.4, 0.7, 1.0 and the
	-- shortest of the three put two numbers inside one glyph of each other; what
	-- the cycle is for is telling two numbers apart, and it cannot do that from
	-- under a glyph's width.
	item.spread = 0.7 + 0.15 * (seed % 3)
	-- And a height, in five steps either side of the anchor.
	--
	-- This replaced a head start down the fall, which gave one number in four a
	-- lead of up to nine hundredths of its life so that a burst did not draw as
	-- one row. It did that by starting the number partway through its own
	-- flight, which is a shorter life and, now that a number holds still before
	-- it falls, a hold it never gets. A height does the same job standing still:
	-- the five steps and the three reaches share no factor, so two numbers land
	-- on the same pair once in fifteen rather than once in four.
	item.nudge = style.scatter * (((seed % 5) - 2) * 0.5)

	flying[#flying + 1] = item
	frame:ClearAllPoints()
	Place(item, 0)
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
-- the attack is wound back, so the number swells in place rather than leaping.
-- It swells from the size it is being drawn at rather than from the size a new
-- number starts at, which is the whole of the difference between a blow landing
-- on a number and a number being replaced by another one.
function Stream.Bump(item, weight)
	item.struck = 0
	item.from = 1
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
-- The offsets are divided by the envelope because a frame's own offsets are read
-- in its own scale, and a number that shrinks while it travels would otherwise
-- fall short of where the style said it lands. By the envelope and not by the
-- whole scale: `ground` is the caller's own pixel, so dividing it out again is
-- what makes a fall of ninety ninety of them whatever size the glyph is.
function Place(item, t)
	local style = item.style
	local frame = item.frame

	-- Two channels multiplied. The drift is the number ageing over its whole
	-- life and the attack is the tenth of a second the blow lands in.
	local shape = style.fromScale + (style.toScale - style.fromScale) * t
	shape = shape * Attack(item, style) * item.weight
	local scale = shape * style.ground
	if scale ~= item.atScale then
		item.atScale = scale
		frame:SetScale(scale)
	end

	-- Nothing moves for the first `beat` of the life, and the ease is stretched
	-- over what is left rather than clipped, so the fall still finishes exactly
	-- at the end of the life.
	local fall = t - style.beat
	if fall > 0 then
		fall = fall / (1 - style.beat)
	else
		fall = 0
	end

	local x = style.arc * Bow(fall) * item.side * item.spread
	local y = item.nudge - style.drop * style.ease(fall)
	x = UI.Whole(x / shape)
	y = UI.Whole(y / shape)
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
	item.struck = item.struck + delta
	local t = item.elapsed / item.style.seconds
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
