local ADDON, ns = ...

local Cast = {}
ns.Cast = Cast

--------------------------------------------------------------------------
-- The cast row under an enemy bar
--
-- `grep UNIT_SPELLCAST` returned nothing across this addon until this file.
-- The enemy bars replace the nameplate, and the one thing a nameplate says
-- that no bar here says is that a cast is running and there are two seconds
-- left to press Pummel. Replacing the plate cost that, so the replacement owes
-- it back.
--
-- No state. There is nothing to accumulate: ns.CastingInfo is a live question
-- with a live answer, so the tick asks it once per bar and this file draws
-- what came back. That is the difference between this and Swing/Swing.lua,
-- which has to reconstruct a clock the client does not keep. A cast bar built
-- on a model would need a model keyed by unit token, and nameplate tokens are
-- recycled the moment a mob dies, which is a whole class of stale bar this
-- file cannot have.
--
-- The row is reserved whether or not the mob is casting, and it draws nothing
-- at all while it is empty: the box is hidden, so there is no fill, no edge and
-- no backdrop. Both halves of that are deliberate.
--
-- Reserved, because a row that appeared would shove the health bar upwards at
-- the exact moment the thing you are watching starts happening, and a bar that
-- moves when the fight gets interesting is a bar you have to re-find.
--
-- Empty rather than dark, because the three pixel threat bar that used to sit
-- above the gauge got this wrong. It drew its backdrop and its edge whether or
-- not anything was pulling, and solo that is a dark stripe along the bar that
-- reads as a fill somebody forgot to finish. What is left here when nothing is
-- casting is air.
--
-- Two things move on this row and they move at different rates, so they are
-- two functions. Cast.Update is what the client said and runs on the bars'
-- tick; Cast.Sweep is the moving edge and runs on every frame. See the note at
-- the head of Swing/Gauges.lua for why the second one is not on a ticker.
--------------------------------------------------------------------------

local Color = ns.Unit.Color
local Gauge = ns.UI.Gauge
local Text = ns.UI.Label

-- The row's height, in pixels like every other size in the bars, and shorter
-- than the health gauge on purpose. It is the second thing you read on a bar
-- and drawing it the same height as the first would make you decide which one
-- you were looking at.
local PLATE_HEIGHT = 11
local LIST_HEIGHT = 14

-- The text on the row, capped by the row rather than by the bar's own size.
-- Fourteen pixels of glyph in an eleven pixel bar is a bar with a name lying
-- across both its edges.
local PLATE_TEXT = 12
local LIST_TEXT = 14
local TEXT_FLOOR = 7
local PAD = 4

-- Two decimals is a number you cannot read off a moving bar and none is a
-- number that says 1 for a whole second. One tenth is what an interrupt is
-- timed in.
--
-- Floored rather than rounded, and that is not a detail on this row. Rounding
-- writes 3.0 with 2.96 left, which is the row promising a tenth of a second it
-- does not have, on the one number in the addon somebody is timing a press
-- against. Floored it under-reads by less than a tenth and never over-reads.
local REMAINING = "%.1f"

-- The seconds left, built once per tenth and kept.
--
-- A cast runs for a few seconds and passes through the same short run of
-- numbers every time, so this fills in the first fight and stops growing. What
-- it replaces is one string built per tenth per casting mob for the rest of the
-- session: at fifteen plates in a raid that is a hundred and fifty throwaway
-- strings a second to draw about thirty distinct numbers, which is the shape
-- this addon has already caught on the list collector and on the level tag.
--
-- Keyed by the tenth rather than by the float, which is what makes it a cache
-- at all: there are ten values a second and not sixty.
local seconds = {}

local function Seconds(tenths)
	local held = seconds[tenths]
	if not held then
		-- Once per tenth this addon ever draws. The lookup above is the guard,
		-- and it is one check.sh cannot see.
		held = REMAINING:format(tenths / 10)
		seconds[tenths] = held
	end
	return held
end

local BACKDROP = Color.backdrop
local NAME_TEXT = Color.text.name
local TIMER_TEXT = Color.text.value
local OPEN = Color.cast.open
local LOCKED = Color.cast.locked

--------------------------------------------------------------------------
-- Building and laying out
--------------------------------------------------------------------------

-- One row, built with the widget that carries it and hidden until something
-- casts. Nothing here is sized or anchored: every measurement on this row
-- follows a setting that moves while the addon is up, so all of it is Cast.Fit's.
function Cast.Build(widget)
	local box = CreateFrame("Frame", nil, widget)
	local back = ns.Fill(box, "BACKGROUND", BACKDROP[1], BACKDROP[2], BACKDROP[3], BACKDROP[4])
	back:SetAllPoints()
	box.edges = ns.Outline(box, OPEN[1], OPEN[2], OPEN[3], 1)
	box.bar = Gauge.New(box)

	-- Pinned to the gauge rather than arranged, for the reason the mob's name
	-- and its health number are: both are sized by whatever the spell happens
	-- to be called, which is not a number the layout knows before it runs.
	box.name = Text(box.bar, PLATE_TEXT, NAME_TEXT, "LEFT")
	box.timer = Text(box.bar, PLATE_TEXT, TIMER_TEXT, "RIGHT")

	box:Hide()
	widget.cast = box
	return box
end

-- Forget what the tick last put on this row. Called when a widget goes back to
-- the pool and when the list stops showing it, because a pooled widget keeps
-- its drawn state and the next mob it lands on is not the one that was casting.
function Cast.Clear(widget)
	local box = widget.cast
	if not box then
		return
	end
	box.shownSpell, box.shownTenths, box.look = nil, nil, nil
	box:Hide()
end

-- Fit the row to a widget, and answer two things: the node the widget's layout
-- puts under its gauge, and how tall that node is. There is no width here
-- because there is nothing to decide: the row is stretched to the bar by the
-- column it sits in, the same as the box above it.
--
-- The height is what PlaceOnPlate needs. The widget is anchored by its bottom
-- edge and the gauge used to sit on that edge, so everything reserved below the
-- gauge has to come back out of the offset or the health bar climbs off the
-- mob. A node that takes no room answers zero, which is the same arithmetic
-- with nothing in it.
function Cast.Fit(widget, unit, px, onPlate)
	local box = widget.cast
	if not ns.db.barsCast then
		Cast.Clear(widget)
		return { skip = true }, 0
	end

	local height = (onPlate and PLATE_HEIGHT or LIST_HEIGHT) * unit
	local pad = PAD * unit
	-- The glyph is capped by the room inside the hairlines rather than by the
	-- bar's own font size, and floored at seven, below which nothing is legible
	-- and the row should be made taller instead. It sits on the row's own opaque
	-- fill, so ns.UI.NumberFont is what decides whether it can carry an outline.
	local size = math.max(TEXT_FLOOR, math.floor(math.min(
		(onPlate and PLATE_TEXT or LIST_TEXT) * unit, height - 2 * px) + 0.5))
	local font = ns.UI.NumberFont(size)

	ns.EdgeSize(box.edges, px)

	box.name:SetFontObject(font)
	box.timer:SetFontObject(font)
	box.timer:ClearAllPoints()
	box.timer:SetPoint("RIGHT", box.bar, "RIGHT", -pad, 0)
	-- Pinned to the number rather than given a width, so a long spell name
	-- yields to the seconds left. The seconds are the half you act on.
	box.name:ClearAllPoints()
	box.name:SetPoint("LEFT", box.bar, "LEFT", pad, 0)
	box.name:SetPoint("RIGHT", box.timer, "LEFT", -pad, 0)

	-- The fonts and the sizes moved, so whatever the tick last wrote was measured
	-- against the old ones and the guards would keep it. Cleared rather than
	-- reset field by field, which hides a cast that was running: a layout
	-- happens on a setting change, a resolution change or a rebuild, and losing
	-- a fifth of a second of one cast bar to any of those costs nothing that a
	-- second list of fields to keep true would not cost more of.
	Cast.Clear(widget)

	-- The gauge is the inside of the box less the hairline around it, grown
	-- rather than sized, exactly as the health box is: the two hairlines come
	-- off the box's own measurement and the fill is what is left however the
	-- numbers round.
	local boxHeight = height + px * 2
	return { frame = box, height = boxHeight, pad = px, align = "stretch",
		direction = "column",
		{ frame = box.bar, grow = 1 },
	}, boxHeight
end

-- How many cast events have reached a bar. Counted rather than inferred, for
-- the reason EnemyBars.CameraState counts: nothing installed on these clients
-- proves UNIT_SPELLCAST_START fires for a `nameplateN` token, and the honest
-- answers are "none yet" and a number, not a claim either way. Losing the
-- events costs a fifth of a second and nothing else, so this is a line in the
-- status rather than a warning.
local heard = 0

--------------------------------------------------------------------------
-- Painting
--
-- Cast.Update runs on the bars' tick against every bar on the screen, and again
-- on a cast event for the one unit it names. Cast.Sweep runs on every frame.
-- Neither allocates, and every write in the first is guarded on what is already
-- on the row. The one write that is not is the fill, which is the whole point
-- of the second, and check.sh is told why on the line itself.
--------------------------------------------------------------------------

-- What the client says this unit is doing, read onto the row.
--
-- The shown guard is on the frame rather than on the spell's name, and that is
-- not tidiness. A mob that casts Shadow Bolt, is interrupted, and casts Shadow
-- Bolt again has not changed the string, so a name guard alone would leave the
-- second cast on a hidden row.
function Cast.Update(widget, unit, fromEvent)
	local box = widget.cast
	if not box or not ns.db.barsCast then
		return
	end

	if fromEvent then
		heard = heard + 1
	end

	-- A cast that has already run out is nothing to draw, whatever the client
	-- still has in its own table. Cast.Sweep takes a finished cast off the row
	-- on the frame it ends, and without this line the next tick would put it
	-- straight back for as long as the client kept answering.
	local name, start, finish, channel, immune = ns.CastingInfo(unit)
	if not name or not finish or finish <= start or finish <= GetTime() then
		if box:IsShown() then
			Cast.Clear(widget)
		end
		return
	end

	-- Plain fields on a table, not writes to a frame, so they are unguarded on
	-- purpose: comparing three numbers to save writing three numbers is the
	-- guard costing more than the write. The frame writes below are the ones
	-- that measure text and dirty a layout.
	box.start, box.finish, box.channel = start, finish, channel

	if box.shownSpell ~= name then
		box.shownSpell = name
		box.name:SetText(name)
	end

	local look = immune and LOCKED or OPEN
	if box.look ~= look then
		box.look = look
		Gauge.Paint(box.bar, box.bar.track, look)
		ns.Recolor(box.edges, look)
	end

	if not box:IsShown() then
		box:Show()
	end
end

-- The moving edge, on every frame, and the only thing this file draws that is
-- not a readout.
--
-- The fill is written as a fraction with nothing in front of it. See the head
-- of Swing/Gauges.lua: a rounded fill is a throttle as well as a quantiser, and
-- an animation is drawn on the frame the screen is drawn on or it is drawn in
-- steps. This one crosses the bar in a second and a half rather than in three
-- and a half, so it steps harder than the swing bar did.
--
-- A cast that has run out of time is over here rather than at the next tick.
-- The client will say so within a fifth of a second, but a fifth of a second is
-- what a bar sitting full at the end of a cast looks like, and that is the
-- frame where you are deciding whether you still have time to press anything.
function Cast.Sweep(widget, now)
	local box = widget.cast
	if not box or not box:IsShown() then
		return
	end

	local left = box.finish - now
	if left <= 0 then
		Cast.Clear(widget)
		return
	end

	local done = (now - box.start) / (box.finish - box.start)
	if done < 0 then
		done = 0
	end
	box.bar:SetValue(box.channel and (1 - done) or done) -- unguarded: the moving edge, and a frame it does not write is a frame it does not move on

	-- Guarded on the tenth that gets drawn, not on the float behind it. A cast
	-- has about fifteen of them and this runs on every frame.
	local tenths = math.floor(left * 10)
	if box.shownTenths ~= tenths then
		box.shownTenths = tenths
		box.timer:SetText(Seconds(tenths))
	end
end

--------------------------------------------------------------------------

-- One line for /wk status and for the panel, covering the two things about this
-- row that are the client's answer rather than a setting.
function Cast.Describe()
	if not ns.db.barsCast then
		return "off"
	end
	if not ns.HasCastInfo() then
		return "|cffd08040this client answers no UnitCastingInfo|r, so the row never draws"
	end
	local line = "on"
	local known = ns.CastImmuneKnown()
	if known == nil then
		line = line .. ", no cast read yet, so whether this client flags an"
			.. " uninterruptible one is unproven"
	elseif known then
		line = line .. ", and this client flags an uninterruptible cast, which draws grey"
	else
		line = line .. ", and no cast read so far carried the uninterruptible flag,"
			.. " so every one is drawn as a cast you can stop"
	end
	if heard == 0 then
		return line .. "; no cast event has reached a bar, so a cast shows up on the"
			.. " next tick rather than at once"
	end
	if heard == 1 then
		return line .. "; one cast event has reached a bar"
	end
	return line .. ("; %d cast events have reached a bar"):format(heard)
end
