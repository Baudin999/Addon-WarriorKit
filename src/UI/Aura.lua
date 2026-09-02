local ADDON, ns = ...

local UI = ns.UI
local Aura = {}
UI.Aura = Aura

--------------------------------------------------------------------------
-- One aura, drawn
--
-- A square with a cropped icon in it, a hairline round the icon, a sweep over
-- the art that empties as the aura runs out, the time left over the top of it
-- and the stack count in the corner. Whoever cast it is the fifth thing it
-- says, and it says it by draining the art rather than by adding a colour:
-- yours in full colour, someone else's grey.
--
-- Two rows in this addon draw one of these. The debuff row on an enemy bar
-- draws a fixed list of spells you asked it to watch, lit when the mob has one
-- and dimmed when it does not. The row under the skinned target block draws
-- whatever is actually on the target, however many that is. Those two ticks
-- have nothing in common and both were writing the same four guarded writes,
-- which is what this file is instead.
--
-- It is not UI/Ability.lua and it does not want to be. That file's whole
-- vocabulary is ten reasons a press does or does not land, and it hangs the
-- countdown text off `status == "cooldown"` because below the global there is
-- nothing worth counting. An aura is not a press. It has no cost, no range and
-- no stance, its timer is the thing you actually read, and the six extra
-- textures a button needs for its pushed state, its equipped ring and its
-- armed ring are six textures per square nobody will ever see. The one thing
-- the two files do share is the client's Cooldown frame, because there is one
-- widget in the game that draws a wedge and this is it.
--
-- Three calls, split by when they run, which is the split UI/Gauge.lua and
-- UI/Ability.lua both use.
--
--   Aura.New    allocates. Once per square.
--   Aura.Size   lays the square out. On a settings change or a rescale.
--   Aura.Draw   runs on a ticker against every square on the screen, so it
--               allocates nothing and writes nothing already on the widget.
--               check.sh's HOT list holds it to that.
--------------------------------------------------------------------------

local Color = ns.Unit.Color

local EDGE = Color.iconEdge
local COUNT_TEXT = Color.text.count

-- What the number is written in, and it is the client's own rule rather than
-- one of ours. The client's buff frame has read a duration in gold and a
-- countdown in white for twenty years: over a minute it is written in minutes
-- and is gold, under a minute it is written in seconds and is white. So the
-- colour and the unit are the same fact said twice, which is why Tint below
-- takes the unit and not the seconds.
--
-- This replaced an amber-under-ten, red-under-five ladder of our own. The
-- ladder was not wrong about what is urgent; it was wrong about who decides.
-- Half the auras on your screen are drawn by the client, in a row above this
-- one, and two rows that disagree about what a colour means are two rows you
-- have to read separately.
local TIMER_TEXT = Color.text.name
local DURATION_TEXT = Color.text.duration

-- What the sweep is made of. Black, because it is a shadow over the art rather
-- than a colour of its own, and at two thirds so the icon under it is still
-- identifiable at the moment it matters most, which is the moment it is nearly
-- covered.
local SWIPE = { 0, 0, 0, 0.65 }

local MINUTE, HOUR = 60, 3600

-- Both numbers are sized off the square rather than off whatever is beside it,
-- because the square is a setting in both callers: a fourteen pixel timer on a
-- sixteen pixel icon covers the art it is annotating. The caller's own ceiling
-- comes in as an argument, so a row of squares cannot carry type larger than
-- the rest of the widget it sits on.
--
-- Both go through UI.NumberFont and come back flat with a shadow, which is the
-- whole reason a seven pixel stack count is readable: nothing is spent on a
-- rim. The count has the icon's own art behind it, which is what a shadow is
-- for. The timer has the world, and it keeps the shadow anyway, because it is
-- eight to fourteen pixels tall and an outline at that size closes the hole in
-- a 6. UI/Text.lua's floor is the reason that trade is written down here.
--
-- The timer's share is under half the square because the string is now up to
-- four characters wide rather than up to two. At six tenths, "28 m" was wider
-- than the square it stands over, and a strip that overhangs on both sides is
-- what makes two squares beside each other read as one number.
local TIMER_SHARE, TIMER_FLOOR = 0.45, 8
local COUNT_SHARE, COUNT_FLOOR = 0.5, 7

-- Three states and not eight. Nobody has it, someone else has it, you have it.
-- Everything the square says about who cast it is in this table and in one
-- SetDesaturated, so the two callers cannot drift into disagreeing about what
-- a debuff of yours looks like.
--
-- "none" is only reachable from the enemy bars, where a slot stands for a
-- spell you asked to watch and the mob may not have it. The target row never
-- draws a square for an aura that is not there.
local ALPHA = { mine = 1, theirs = 0.65, none = 0.22 }

-- What the strip over the square reads, as a number and the unit it is in.
--
-- It used to be the seconds, whole, whatever the number was, which is what put
-- 1972 across a sixteen pixel square. Four digits of a half hour buff are a
-- precision nobody reads and they cover the art that says which buff it is.
-- The client's own frames have read "28 m" for twenty years and they are
-- right, so this answers in the largest unit that still says something true.
--
-- The unit is written out, seconds included, and with the space the client
-- puts there. "56 s" and "14 m" are what the row above ours says, and a row
-- that dropped the s would be the one row on the screen where a bare 56 could
-- be either.
--
-- Rounded up, in every unit. A buff reading 1 m has at least a minute left in
-- it, and a number that reaches 0 while the aura is still on the unit is a
-- number lying about the thing it is written on.
--
-- The two returns are what the caller guards on, so the string behind them is
-- built when the reading moves and not five times a second: above a minute
-- that is once a minute per square, and above an hour once an hour.
local function Reading(left)
	if left >= HOUR then
		return math.ceil(left / HOUR), " h"
	end
	if left >= MINUTE then
		return math.ceil(left / MINUTE), " m"
	end
	return math.ceil(left), " s"
end

-- Which of the two the number is written in, off the unit it came back in.
-- Returns one of the palette's own tables, so the caller's guard is one
-- comparison of identity rather than three of floats.
local function Tint(unit)
	if unit == " s" then
		return TIMER_TEXT
	end
	return DURATION_TEXT
end

function Aura.New(parent)
	-- Two frames and not one. The widget is the square plus the strip of air
	-- over it that carries the number, and `box` is the square itself: the art,
	-- the hairline round it and the sweep across it.
	--
	-- The split is what lets the number sit outside the art. ns.Outline hangs
	-- its four hairlines off the frame's own corners with no offsets, so a
	-- widget that was the square would have drawn its border round the strip as
	-- well, and the layout above would have had to know which part of the
	-- rectangle was the picture. Now the caller lays out one rectangle, and
	-- everything about where the picture is inside it is here.
	local w = CreateFrame("Frame", nil, parent)
	w.box = CreateFrame("Frame", nil, w)
	w.edges = ns.Outline(w.box, EDGE[1], EDGE[2], EDGE[3], EDGE[4])
	w.icon = UI.Icon(w.box)

	-- The sweep, over the art and under the numbers.
	--
	-- It is the only thing on the square that reads without being read. A
	-- number says thirty seconds and you have to know what a long Rend is; a
	-- wedge says half, against a square whose full is the same size every time.
	-- It is the client's Cooldown frame because that is the only widget in the
	-- game that draws one, and the client's own countdown text on it is off
	-- because the reading along the bottom is this file's and the two would sit
	-- on top of each other.
	--
	-- Reversed, which is the whole difference between a cooldown and an aura.
	-- A cooldown starts covered and uncovers as it comes back. An aura starts
	-- clear and fills as it runs out, so the square you just refreshed is the
	-- bright one and the square about to drop is the dark one.
	w.swipe = CreateFrame("Cooldown", nil, w.box, "CooldownFrameTemplate")
	if w.swipe.SetHideCountdownNumbers then
		w.swipe:SetHideCountdownNumbers(true)
	end
	if w.swipe.SetReverse then
		w.swipe:SetReverse(true)
	end
	if w.swipe.SetSwipeColor then
		w.swipe:SetSwipeColor(SWIPE[1], SWIPE[2], SWIPE[3], SWIPE[4])
	end
	-- The bright line the client draws at the leading edge of the wedge, off.
	-- It is a spinning highlight on a square that is sixteen pixels across in
	-- the row it is smallest in, where it reads as flicker rather than as an
	-- edge.
	if w.swipe.SetDrawEdge then
		w.swipe:SetDrawEdge(false)
	end
	if w.swipe.SetDrawBling then
		w.swipe:SetDrawBling(false)
	end
	-- A square is a tooltip on both rows and a right click that cancels the
	-- buff on one of them, and both of those are on the frame underneath this.
	-- Said rather than assumed: a Cooldown is a frame, what a frame does with
	-- the mouse is the template's business, and a square whose tooltip stopped
	-- working is indistinguishable from a square drawn over the wrong aura.
	w.swipe:EnableMouse(false)

	-- The time over the square and the stack count in its corner.
	--
	-- Over it, outside the art, which is where the client puts it and is the
	-- whole of what this widget got wrong. A number written on the icon is a
	-- number over a picture chosen by whoever drew the spell: 27 on a pale
	-- bandage and 27 on a dark bleed are two different readings of the same
	-- number, and the shadow behind it only ever fixes one of them. Over the
	-- square it has the world behind it, which is a worse background in theory
	-- and a better one in practice, because a number nothing else is competing
	-- with is a number you read at a glance.
	--
	-- The timer is a child of the widget rather than of the sweep, because it
	-- no longer stands on the art the sweep darkens. The count still does, so
	-- it stays a child of the sweep: a font string on the box draws under a
	-- frame that is a child of the box, and the sweep would take two thirds out
	-- of the number it was standing behind.
	w.timer = UI.Label(w, TIMER_FLOOR, TIMER_TEXT, "CENTER", UI.SHADOW)
	w.count = UI.Label(w.swipe, COUNT_FLOOR, COUNT_TEXT, "RIGHT", UI.SHADOW)

	-- What was last drawn. Every one of these is compared before its write in
	-- Aura.Draw. They start nil so that the first draw writes everything, which
	-- matters because both callers pool their squares and a pooled square
	-- carries whatever the last mob put on it.
	w.shownIcon, w.shownState = nil, nil
	w.shownLeft, w.shownUnit, w.shownTint = nil, nil, nil
	w.shownStart, w.shownDuration = nil, nil
	w.shownCount = nil
	return w
end

-- `side` is in the frame's own units. The conversion belongs at the call site,
-- which is the rule UnitFrames/Skin.lua and UI/Ability.lua already follow. `px`
-- is one screen pixel and is for the hairline and the two insets, which stay
-- one pixel however large the square gets.
--
-- The count used to be inset by a flat 1 on the enemy bars, which is one unit
-- rather than one pixel, so at `bars zoom 2` it sat two pixels in while the
-- border beside it stayed one. It is `px` here, like every other hairline in
-- the addon.
--
-- Returns the width and the height of the whole widget, and they are no longer
-- the same number: the number sits over the square now, so a square of `side`
-- needs a rectangle taller than `side` to live in. Both callers put what comes
-- back into their layout node. A caller that kept passing `side` for the
-- height would lay the rows one number closer together than they are drawn and
-- the strip over each square would land on the row above it.
-- cold: a settings change and a rescale, never a tick, as Ability.Size is.
function Aura.Size(w, side, px, timerCeiling, countCeiling)
	local timerSize = math.max(TIMER_FLOOR,
		math.min(timerCeiling, math.floor(side * TIMER_SHARE)))
	w.timer:SetFontObject(UI.NumberFont(timerSize))

	-- The strip the number stands in: its own type height and a pixel of air
	-- under it, taken up to whole pixels so the square below still starts on
	-- one. Off the size we just asked for rather than off the string, because a
	-- font string measures 0 tall until it has text in it and a square with
	-- nothing on it yet is most of the row.
	local lift = (math.ceil(timerSize / px) + 1) * px
	w:SetSize(side, side + lift)

	-- The mouse stays on the square. The strip is empty most of the time and a
	-- tooltip that opens when you pass over blank sky above an icon is a
	-- tooltip you did not ask for.
	w:SetHitRectInsets(0, 0, lift, 0)

	w.box:ClearAllPoints()
	w.box:SetSize(side, side)
	w.box:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 0, 0)

	-- Every region of the square is given a size as well as an anchor, which is
	-- the one rule that separates this widget from the rest of the addon and it
	-- is earned. The square's edge is a setting, so the frame is resized while
	-- the addon is up, and the art and the hairline are the two things on it
	-- that had no size of their own: the art hung off two opposite corners and
	-- each edge off two adjacent ones, so both were rectangles the client had
	-- to derive from a frame that had just changed under it.
	--
	-- The failure that makes it worth the four extra calls is silent. A region
	-- the client cannot work a rectangle out for draws nothing and raises
	-- nothing, and the timer is a font string and is as big as its text either
	-- way, so what is left on the screen is a number floating over the block
	-- with no square around it and no icon in it. That is what got reported.
	ns.EdgeSize(w.edges, px, side, side)

	local inner = math.max(side - px * 2, px)
	w.icon:ClearAllPoints()
	w.icon:SetSize(inner, inner)
	w.icon:SetPoint("TOPLEFT", w.box, "TOPLEFT", px, -px)

	-- The sweep covers the art and stops at it. Given the same rectangle for
	-- the same reason: it is a frame whose size is a setting, and a wedge one
	-- pixel wider than the icon is a wedge over the hairline, which is the one
	-- line on the square that says where one square ends and the next begins.
	w.swipe:ClearAllPoints()
	w.swipe:SetSize(inner, inner)
	w.swipe:SetPoint("TOPLEFT", w.box, "TOPLEFT", px, -px)

	w.count:SetFontObject(UI.NumberFont(math.max(COUNT_FLOOR,
		math.min(countCeiling, math.floor(side * COUNT_SHARE)))))

	w.timer:ClearAllPoints()
	w.timer:SetPoint("BOTTOM", w.box, "TOP", 0, px)
	w.count:ClearAllPoints()
	w.count:SetPoint("TOPRIGHT", w.box, "TOPRIGHT", -px, -px)
	return side, side + lift
end

-- One square, one tick.
--
-- `texture` is the art, `state` one of the three above, `expires` when the
-- client says the aura runs out and 0 for one that does not, `duration` how
-- long it was applied for and 0 where the client will not say, `count` the
-- stack number, and `now` the time the caller already read. The clock is an
-- argument because a row of ten squares wants one GetTime between them and not
-- ten.
--
-- The two timing arguments are read as a pair and neither replaces the other.
-- `expires` alone is the number along the bottom, and the sweep needs the
-- fraction, which is the only thing `duration` is for. A temporary weapon
-- enchant has an expiry and no duration anywhere in the client's API, so its
-- square counts down in text and never sweeps, which is the truth about what
-- is known rather than a wedge drawn against a guess.
function Aura.Draw(w, texture, state, expires, duration, count, now)
	-- Guarded like the rest, and the guard is what makes the enemy bars' fixed
	-- row free: it passes the same texture every tick for the life of the
	-- setting and this writes it once.
	if w.shownIcon ~= texture then
		w.shownIcon = texture
		w.icon:SetTexture(texture)
	end

	if w.shownState ~= state then
		w.shownState = state
		w.icon:SetDesaturated(state ~= "mine")
		w:SetAlpha(ALPHA[state] or ALPHA.none)
	end

	-- The sweep, driven by the two numbers alone and guarded on the pair. The
	-- client runs the wedge off them once and animates it itself, so a square
	-- the caller re-reports every tick for a minute is one write a minute.
	local span = (duration and duration > 0 and expires and expires > 0)
		and duration or 0
	local start = span > 0 and expires - span or 0
	if w.shownStart ~= start or w.shownDuration ~= span then
		w.shownStart, w.shownDuration = start, span
		w.swipe:SetCooldown(start, span)
	end

	local left = 0
	if expires and expires > 0 then
		left = expires - now
		if left < 0 then
			left = 0
		end
	end

	-- Guarded on the reading rather than on the seconds, so the string is built
	-- about five times a minute per square below a minute and about once a
	-- minute above it, rather than five times a second at any range.
	local reading, unit = Reading(left)
	if w.shownLeft ~= reading or w.shownUnit ~= unit then
		w.shownLeft, w.shownUnit = reading, unit
		w.timer:SetText(reading > 0 and (reading .. unit) or "")
	end

	local tint = Tint(unit)
	if w.shownTint ~= tint then
		w.shownTint = tint
		w.timer:SetTextColor(tint[1], tint[2], tint[3])
	end

	local stacks = count or 0
	if w.shownCount ~= stacks then
		w.shownCount = stacks
		w.count:SetText(stacks > 1 and tostring(stacks) or "")
	end
end
