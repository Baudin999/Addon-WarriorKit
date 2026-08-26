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
-- The row is the second chamber of the health bar's own box, not a box of its
-- own under it, and it takes no room at all while nothing is casting.
--
-- It began as a separate box: its own backdrop, its own four sided violet
-- outline, four pixels of gap. Two independently framed rectangles near each
-- other, with nothing but proximity saying they were about the same mob. One
-- outline round both and one dark line between them says it instead, and the
-- line is the cheaper claim: a seam reads as a division inside one object, a
-- gap reads as two objects.
--
-- The room it used to hold is the other half. The row was reserved whether or
-- not the mob ever cast, so seventeen pixels of nothing hung under every bar on
-- the screen, permanently. The goal that bought was right and is kept: a row
-- that appears must not shove the health bar upward at the exact moment the
-- thing you are watching starts happening, because a bar that moves when the
-- fight gets interesting is a bar you have to re-find. Reserving was only one
-- way to reach it, and it was the expensive way. The widget hangs by its top
-- edge now, so the chamber opens downward out of the box's bottom and every
-- pixel above it, the health gauge included, stays exactly where it was.
--
-- What is left when nothing is casting is not air. It is nothing: the box is
-- the health gauge and its hairline, and the bar is twelve pixels shorter.
--
-- Two things move on this row and they move at different rates, so they are
-- two functions. Cast.Update is what the client said and runs on the bars'
-- tick; Cast.Sweep is the moving edge and runs on every frame. See the note at
-- the head of Swing/Gauges.lua for why the second one is not on a ticker.
--------------------------------------------------------------------------

local Color = ns.Unit.Color
local Gauge = ns.UI.Gauge
local Text = ns.UI.Label

-- The chamber's height, in pixels like every other size in the bars, and half
-- the health gauge on purpose. It is the second thing you read on a bar and
-- drawing it the same height as the first would make you decide which one you
-- were looking at. Eleven against a twenty two pixel gauge is that ratio said
-- exactly, which it was not against twenty one.
local PLATE_HEIGHT = 11
local LIST_HEIGHT = 14

-- The text on the row, capped by the row rather than by the bar's own size.
-- Fourteen pixels of glyph in an eleven pixel chamber is a chamber with a name
-- lying across both its edges, so this stays under the bar's own size and under
-- ns.UI.OutlineFloor: the font below drops the outline rather than closing up
-- the glyph, which is what ns.UI.NumberFont is for.
local PLATE_TEXT = 10
local LIST_TEXT = 12
local TEXT_FLOOR = 7
local PAD = 5

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

local NAME_TEXT = Color.text.name
local TIMER_TEXT = Color.text.value
local OPEN = Color.cast.open
local LOCKED = Color.cast.locked
local SEAM = Color.seam

--------------------------------------------------------------------------
-- Building and laying out
--------------------------------------------------------------------------

-- One row, built with the widget that carries it and hidden until something
-- casts. Nothing here is sized or anchored: every measurement on this row
-- follows a setting that moves while the addon is up, so all of it is Cast.Fit's.
-- Open or close the chamber, which is one write to the health box's height.
--
-- The box is the frame both gauges live in, so growing it is the whole of
-- opening the chamber: the health gauge above carries a height Flow already
-- gave it and is pinned to the widget's top left, so it does not move, and the
-- box's outline follows its own frame. Nothing is laid out again.
--
-- Both heights are numbers LayoutWidget worked out and left on the widget. The
-- guard is on the height already set rather than on a flag, because this is
-- reached from Cast.Update's tick as well as from a cast event, and the write
-- it is guarding measures nothing but still dirties the frame.
local function Chamber(box, open)
	local widget = box.widget
	local height = (open and widget.boxOpen) or widget.boxIdle
	if height and widget.box:GetHeight() ~= height then
		widget.box:SetHeight(height)
	end
	if box.seam:IsShown() ~= (open and true or false) then
		box.seam:SetShown(open)
	end
end

function Cast.Build(widget)
	-- Parented to the health box, not to the widget, and with neither a fill of
	-- its own nor an outline. It is inside the frame the box already draws, so a
	-- backdrop would be a second dark layer over the first and an edge would cut
	-- the box in half with a violet line. What separates the two chambers is one
	-- seam, and EnemyBars draws it.
	local box = CreateFrame("Frame", nil, widget.box)
	box.bar = Gauge.New(box)

	-- The one line between the two chambers. Drawn on the health box rather
	-- than on either gauge because it belongs to neither, and owned here rather
	-- than by the bar because it comes and goes with the chamber under it.
	box.seam = ns.Fill(widget.box, "ARTWORK", SEAM[1], SEAM[2], SEAM[3], SEAM[4])
	box.seam:Hide()
	-- The widget the chamber belongs to. Show and Clear are handed the chamber
	-- and have to resize the box around it, and walking up through GetParent
	-- would be reaching for the same thing without saying so.
	box.widget = widget

	-- Pinned to the gauge rather than arranged, for the reason the mob's name
	-- and its health number are: both are sized by whatever the spell happens
	-- to be called, which is not a number the layout knows before it runs.
	box.name = Text(box.bar, PLATE_TEXT, NAME_TEXT, "LEFT", ns.UI.SHADOW)
	box.timer = Text(box.bar, PLATE_TEXT, TIMER_TEXT, "RIGHT", ns.UI.SHADOW)

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
	box.shownSpell, box.shownTenths, box.look, box.preview = nil, nil, nil, nil
	box:Hide()
	Chamber(box, false)
end

-- Fit the chamber to a widget and answer how tall it is, which is the one
-- number EnemyBars needs: the box's open height is its idle height plus a seam
-- plus this. There is no node and no width, because the chamber is not in the
-- widget's column at all. It is anchored to the health gauge above it and takes
-- that gauge's two vertical edges, so it is exactly as wide as the fill it sits
-- under, however the box's own width rounds.
--
-- A chamber that is turned off answers zero, which makes the open height equal
-- the idle height and the box a box with one gauge in it.
function Cast.Fit(widget, unit, px, onPlate)
	local box = widget.cast
	if not ns.db.barsCast then
		Cast.Clear(widget)
		return 0
	end

	local height = (onPlate and PLATE_HEIGHT or LIST_HEIGHT) * unit
	local pad = PAD * unit
	-- The glyph is capped by the room inside the hairlines rather than by the
	-- bar's own font size, and floored at seven, below which nothing is legible
	-- and the row should be made taller instead. It sits on the row's own opaque
	-- fill, so ns.UI.NumberFont gives it a shadow and no outline: a chamber is
	-- eleven pixels tall and a rim in there closes the glyph it is drawn round.
	local size = math.max(TEXT_FLOOR, math.floor(math.min(
		(onPlate and PLATE_TEXT or LIST_TEXT) * unit, height - 2 * px) + 0.5))
	local font = ns.UI.NumberFont(size)

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

	-- Under the health gauge, one seam below it, and squared off against that
	-- gauge's own left and right edges rather than against the box's. The box
	-- has a hairline on both sides and the health gauge is already inside it, so
	-- taking the gauge's edges puts the two fills in the same column by
	-- construction instead of by subtracting the same pixel twice.
	--
	-- The chamber fills itself: it is anchored on three sides and given a
	-- height, and it is not in any Flow tree, so nothing measures it but this.
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", widget.health, "BOTTOMLEFT", 0, -px)
	box:SetPoint("TOPRIGHT", widget.health, "BOTTOMRIGHT", 0, -px)
	box:SetHeight(height)
	box.seam:ClearAllPoints()
	box.seam:SetPoint("TOPLEFT", widget.health, "BOTTOMLEFT", 0, 0)
	box.seam:SetPoint("TOPRIGHT", widget.health, "BOTTOMRIGHT", 0, 0)
	box.seam:SetHeight(px)
	box.bar:ClearAllPoints()
	box.bar:SetAllPoints(box)

	return height
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

-- What an unlocked frame draws instead of asking the client.
--
-- The row is empty almost all of the time, which makes "unlock the frames and
-- look" a thing with nothing to look at: a feature you cannot see until a
-- caster pulls you is one you cannot place, size or judge. Buffs/Nag.lua has
-- the same shape of problem and the same answer, and its preview mode is where
-- this idea comes from.
--
-- Five seconds, and both halves are drawn because the row draws two different
-- pictures. The first is a cast filling left to right and the second is a
-- channel draining right to left, so one unlock answers both questions.
--
-- Named in English like everything else this addon says in its own voice, and
-- named for what it is rather than after a spell. A row reading "Shadow Bolt"
-- over a boar that is not casting is a preview lying about the thing it is
-- previewing.
local PREVIEW = 2.5

local function Preview(now)
	local phase = now % (PREVIEW * 2)
	local channel = phase >= PREVIEW
	local start = now - (channel and (phase - PREVIEW) or phase)
	return channel and "channel" or "cast", start, start + PREVIEW, channel
end

-- The guarded writes, shared by the client's answer and by the preview, so the
-- preview really is a preview: it goes through the drawing the real thing goes
-- through rather than through a second copy of it that can drift.
--
-- The shown guard is on the frame rather than on the spell's name, and that is
-- not tidiness. A mob that casts Shadow Bolt, is interrupted, and casts Shadow
-- Bolt again has not changed the string, so a name guard alone would leave the
-- second cast on a hidden row.
local function Show(box, name, start, finish, channel, immune)
	-- Plain fields on a table, not writes to a frame, so they are unguarded on
	-- purpose: comparing three numbers to save writing three numbers is the
	-- guard costing more than the write. The frame writes below are the ones
	-- that measure text and dirty a layout.
	box.start, box.finish, box.channel = start, finish, channel

	if box.shownSpell ~= name then
		box.shownSpell = name
		box.name:SetText(name)
	end

	-- The fill alone now. The chamber has no edge of its own: the box's outline
	-- is reaction's and colouring it violet for the length of a cast would say
	-- the mob had turned neutral. Violet appears in exactly one place on this
	-- widget and that is the point of it.
	local look = immune and LOCKED or OPEN
	if box.look ~= look then
		box.look = look
		Gauge.Paint(box.bar, box.bar.track, look)
	end

	if not box:IsShown() then
		box:Show()
	end
	Chamber(box, true)
end

-- What the client says this unit is doing, read onto the row.
function Cast.Update(widget, unit, fromEvent)
	local box = widget.cast
	if not box or not ns.db.barsCast then
		return
	end

	if fromEvent then
		heard = heard + 1
	end

	-- Unlocked, the row previews itself and the client is not asked at all. The
	-- unlocked state already means "show me where things are and how big they
	-- are" everywhere else in this addon, and a row that answers that question
	-- with nothing is a row you place by memory.
	if not ns.db.locked then
		box.preview = true
		Show(box, Preview(GetTime()))
		return
	end
	if box.preview then
		-- Locked again. Cleared here rather than left to fall through, because
		-- what is on the row is a number this file made up and the branch below
		-- would leave it there until the mob happened to cast.
		Cast.Clear(widget)
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

	Show(box, name, start, finish, channel, immune)
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

	-- A preview rolls over instead of ending. Refreshed here rather than left to
	-- the tick, because the tick is up to a fifth of a second away and a fifth
	-- of a second of empty row on every loop is exactly the flicker a preview
	-- exists to rule out.
	if box.preview and box.finish - now <= 0 then
		Show(box, Preview(now))
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
	if not ns.db.locked then
		return "on, and previewing itself on every bar because the frames are"
			.. " unlocked: a cast, then a channel, five seconds around"
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
