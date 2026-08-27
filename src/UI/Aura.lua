local ADDON, ns = ...

local UI = ns.UI
local Aura = {}
UI.Aura = Aura

--------------------------------------------------------------------------
-- One aura, drawn
--
-- A square with a cropped icon in it, a hairline round the icon, the seconds
-- left along the bottom and the stack count in the top corner. Whoever cast it
-- is the fourth thing it says, and it says it by draining the art rather than
-- by adding a colour: yours in full colour, someone else's grey.
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
-- armed ring are six textures per square nobody will ever see.
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
local TIMER_TEXT = Color.text.name
local COUNT_TEXT = Color.text.count

-- Both numbers are sized off the square rather than off whatever is beside it,
-- because the square is a setting in both callers: a fourteen pixel timer on a
-- sixteen pixel icon covers the art it is annotating. The caller's own ceiling
-- comes in as an argument, so a row of squares cannot carry type larger than
-- the rest of the widget it sits on.
--
-- Both sit on the icon's own art, which is opaque, so they go through
-- UI.NumberFont and come back flat with a shadow. That is the whole reason a
-- seven pixel stack count is readable: nothing is spent on a rim.
local TIMER_SHARE, TIMER_FLOOR = 0.6, 8
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

function Aura.New(parent)
	local w = CreateFrame("Frame", nil, parent)
	w.edges = ns.Outline(w, EDGE[1], EDGE[2], EDGE[3], EDGE[4])
	w.icon = UI.Icon(w)

	-- Timer along the bottom edge and stacks in the corner, which leaves the
	-- middle of the art readable. A number across the icon does not.
	w.timer = UI.Label(w, TIMER_FLOOR, TIMER_TEXT, "CENTER", UI.SHADOW)
	w.timer:SetPoint("BOTTOM", w, "BOTTOM", 0, 0)
	w.count = UI.Label(w, COUNT_FLOOR, COUNT_TEXT, "RIGHT", UI.SHADOW)

	-- What was last drawn. Every one of these is compared before its write in
	-- Aura.Draw. They start nil so that the first draw writes everything, which
	-- matters because both callers pool their squares and a pooled square
	-- carries whatever the last mob put on it.
	w.shownIcon, w.shownState = nil, nil
	w.shownSeconds, w.shownCount = nil, nil
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
function Aura.Size(w, side, px, timerCeiling, countCeiling)
	w:SetSize(side, side)

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
	w.icon:SetPoint("TOPLEFT", w, "TOPLEFT", px, -px)

	w.timer:SetFontObject(UI.NumberFont(math.max(TIMER_FLOOR,
		math.min(timerCeiling, math.floor(side * TIMER_SHARE)))))
	w.count:SetFontObject(UI.NumberFont(math.max(COUNT_FLOOR,
		math.min(countCeiling, math.floor(side * COUNT_SHARE)))))

	w.count:ClearAllPoints()
	w.count:SetPoint("TOPRIGHT", w, "TOPRIGHT", -px, -px)
	return side
end

-- One square, one tick.
--
-- `texture` is the art, `state` one of the three above, `expires` when the
-- client says the aura runs out and 0 for one that does not, `count` the stack
-- number, and `now` the time the caller already read. The clock is an argument
-- because a row of ten squares wants one GetTime between them and not ten.
function Aura.Draw(w, texture, state, expires, count, now)
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

	-- Whole seconds, and guarded on the integer rather than on the expiry, so
	-- the string behind it is built about five times a minute per square rather
	-- than five times a second.
	local seconds = 0
	if expires and expires > 0 then
		seconds = math.floor(expires - now)
		if seconds < 0 then
			seconds = 0
		end
	end
	if w.shownSeconds ~= seconds then
		w.shownSeconds = seconds
		w.timer:SetText(seconds > 0 and tostring(seconds) or "")
	end

	local stacks = count or 0
	if w.shownCount ~= stacks then
		w.shownCount = stacks
		w.count:SetText(stacks > 1 and tostring(stacks) or "")
	end
end
