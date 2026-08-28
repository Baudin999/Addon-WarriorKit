# Handoff

Items 8 and 9 are on main and neither has been confirmed in game. Four things
have landed since and none has been seen in the game either: the `/wk hide`
switches that take the client's own copy of what this addon draws off the
screen, your own cast bar, the five settings per cloned action bar, and the loot
feed rebuild. That is the whole of where things stand.

## On main

- `0d1ad42` merges item 8, the frame link. The player block anchors the target
  block and the target block anchors target of target, so Edit Mode positions
  one frame and the addon owns every relationship between frames. Settings are
  `/wk skin link|gap|level`, target of target keeps `TOT_GAP` at three pixels.
- `a67c754` merges item 9, the target's aura rows, over `82ff746`, which was
  its first half.
- `750cabe` settles item 9's open question: the new rows are the target's only.
  Your own buffs stay with item 4's nag row, because a temporary weapon enchant
  appears at no aura index and `Buffs/Upkeep.lua:17` already says so.
- `UnitFrames/Blizzard.lua` holds one switch per thing you can see twice, all
  of them shipping on: your buffs, your debuffs, the target's auras, the
  target's cast bar and Blizzard's own cast bar. `/wk hide <word>` and a section
  of the panel walk the same list.
- `UnitFrames/PlayerCast.lua` is your own cast bar, under the swing timer and
  the same width as it. `/wk cast on|off`, `cast width|height|zoom|reset`, its
  own section in the panel, and `hide playercast` for Blizzard's.
- The loot feed is bare, filtered by chips and worth hovering. No word over the
  column and no line round it, both of them settings a stream now ships an
  answer to; seven chips over the rows, five quality colours plus quest and
  coin, filtering what is drawn rather than what is recorded; a ring round a
  quest item's icon; a vendor price per item and per stack on the hover, and an
  auction price out of whichever scanner is installed. `<prefix>Icon` makes the
  row a size. `feed loot header|edge|filters|poor|common|uncommon|rare|epic|quest|money`,
  the same switches on the panel page, and `Feeds/Auction.lua` is new.
- `Buttons/Look.lua` is five settings per cloned bar: the rows the twelve fold
  into, the colour and opacity of the ground under them, whether the bar goes
  down in combat and which key holds it up. Plus the bars' own lock, which is
  shift-dragging. `actionbars rows|colour|background|combat|key <bar> <value>`,
  `actionbars lock|unlock`, `actionbars plain`, and a tab strip page in the
  panel.
- `check.sh` exits 0, luacheck 0 warnings and 0 errors across 106 files,
  harness ok on both flavours, 38 sections.

## Item 9, as it landed

`UI/Aura.lua` is one aura square: cropped icon, hairline, seconds along the
bottom, stacks in the corner, who cast it said by draining the art. It came out
of `EnemyBars.lua` rather than being written beside it, so the bars' debuff row
and the target's rows are the same code and cannot drift apart. The bars lost 39
lines and draw the same picture, except the stack count is inset by one screen
pixel rather than one unit, so `bars zoom 2` stops sitting it two pixels in.

`UnitFrames/Auras.lua` is the rows: debuffs against the block, buffs under them,
wrapping downwards, mirrored off the portrait corner. Yours are placed first,
because the client's order is the order the auras landed in and a row capped at
twelve otherwise loses your Rend under a raid's worth of other people's bleeds.
`ns.UI.Flow` runs at layout only; the tick shows a prefix of squares already
placed and moves nothing but each row's height. The client's row is hidden by a
sweep of one global lookup per row per tick, because its buttons are built on
demand and in order.

The lift machinery is deleted, which was most of the point: `AURA_CEILING`,
`AnchorOf`, `AuraLift`, `entry.auraLift`, `Fit`'s tail, the `UNIT_AURA`
registration and handler, the `auras` key on the target spec, the aura clause in
`FitText`. All three frames are the block exactly. `Skin.lua` went 2012 to 1934.

Target of target is parked on exactly the corner the rows hang from, so `Perch`
calls `ns.FrameAuras.Under` and the first row hangs under it rather than through
it. That re-hangs on the ticker rather than at layout, because the client shows
and hides that frame with the unit. If target of target moves into the corridor,
the rows come back up against the block on their own.

Settings: `/wk skin auras on|off`, `skin aura <12-32>`, `skin debuffs <0-16>`,
`skin buffs <0-32>`. Off leaves the target with no row at all, because the frame
is the block and the client's own row would land in the gauge. `/wk skin off`
gives it back, because that is what gives the frame its size back.

## The cast bar, as it landed

A bar of its own with a point you drag, not a chamber under the player block.
The enemy row opens downward out of the bar it belongs to because a mob's cast
is one more thing about that mob; under the player block is where your debuff
row hangs, and a chamber there would push that row down and pull it back up on
every cast.

Four answers come out of `UnitFrames/Cast.lua` and none is written twice:
`Cast.Live`, `Cast.Fraction`, `Cast.Seconds` and `Cast.Preview`. Two of those
were private to that file and two were extracted out of its own tick and sweep,
so the enemy row and your bar are drawing the same cast through the same code.

What is new is the cast that failed: red, held where it stopped for seven tenths
of a second, because an empty bar is what a finished cast leaves behind too.

`Perf/Perf.lua` gained two keys while this was being written and one of them is
a fix. `Perf.Start("cast")` has bracketed the enemy cast sweep since that row
shipped and the performance tab has drawn a line for it, but `cast` was never in
`ORDER`, so the row read as unavailable for the life of the feature and nothing
said so.

## The bars' shape and hours, as it landed

Five settings per bar in `Buttons/Look.lua`, keyed by the plan's bar key in
`ns.db.barLook`, and every one of them defaults to something that is not a
setting: the plan's own columns in `Which.lua`, the window colour, and no for
both visibility answers. A bar nobody has touched carries no record, so
`actionbars plain` is a deletion and a fresh clone of the repo looks like the
machine it was written on. Same shape as the tick boxes.

Rows are the six numbers that divide twelve. The stepper walks between them on
the direction of travel, because snapping to the nearest does nothing on every
second press. Colours are eight names in source rather than three sliders, two
of them the theme's own and six deliberately dark, because the background is the
ground under twelve pieces of Blizzard icon art.

The two that decide when a bar is up are a visibility state driver, because
everything inside a bar is a secure button and a frame with one of those under
it cannot be hidden in lockdown. `[combat] hide; show`, or `[mod:shift] show;
hide`, and a key beats the combat switch rather than being read alongside it.
`ns.BarLook.CanDrive` probes for the calls, so a client with neither leaves every
bar up and says so.

How big a square is is a setting too, 16 to 54 pixels, defaulting to the 27 that
draws sharp and saying "blended" in the readout at every stop that does not. Two
buttons centre one bar on one axis, by dropping half of its anchor rather than by
measuring the screen, so it stays centred at every resolution.

While the options window is open, the bar the page's tab strip names wears an
accent rim, two pixels outside it. That needed `showing` on the registry, which
is the window opening and closing, fired off the frame's own `OnShow` and
`OnHide` because Escape closes the panel through `UISpecialFrames` and never
comes past `Core/Panel.lua`. It is the first hook of its kind and any part that
wants to point at one of its own rows can use it.

`Buttons/Placing.lua` gained the bars' own lock. Off, holding shift puts the drag
handles up, watched off `MODIFIER_STATE_CHANGED`. It ships locked because a
handle takes every click that lands on it.

`harness/sections/38-bar-look.lua` is the section, self-contained and last in the
run order. Writing it turned up one thing worth knowing: `22-chores.lua` had been
replacing `IsShiftKeyDown` with a constant and leaving it replaced, so every
section after it ran with shift welded off. It goes through the stub's own switch
now.

## What to do next

- Confirm item 8 and item 9 in game. Item 8's geometry has been looked at once
  and read right; the aura rows have not been seen at all.
- Target of target reads as an orphan under the target block's inner edge.
  `TOT_GAP` at three and `TOT_SCALE` at 0.62 were both chosen when the target
  block sat somewhere else, and the corridor item 8 opened is the natural place
  for it. Not written up as an item yet.

## Untested against the live client

The bar settings: whether a visibility state driver hides one of these bars on
2.5.6. It is the same unknown as the page driver and reached through the same two
calls, so a client that runs one runs the other; what is untested is the
condition rather than the machinery. The harness asserts the macro that is
registered and nothing about what the client does with it. To settle it: set a
bar to go down in combat, pull something, and watch it. Shift-dragging is the
other one to look at, because the handle eating a shift-click while it is up is
the cost of it and is a thing you feel rather than measure.

The cast bar: whether the nine `UNIT_SPELLCAST_*` names it watches fire on these
clients, and whether `CastingBarFrame` is what they call Blizzard's own. The
events fail soft, because the poll behind them asks `UnitCastingInfo("player")`
five times a second whatever the events do, so a missing name costs a fifth of a
second and the failed-cast hold. A missing frame name is the louder one: `hide
playercast` would hide nothing and you would have two cast bars. To settle both:
cast anything and watch the bar fill, then walk out of range mid cast and see
whether it goes red.

Item 8: how this Edit Mode signals a drop, whether a frame anchored to another
frame can still be dragged in it, and whether `EDIT_MODE_LAYOUTS_UPDATED` exists
on this backport. The first two fail soft and `/wk skin link off` is the way out
without a reload.

Item 9: whether the client's own target aura buttons are protected on this
backport, which decides whether one built mid fight can be hidden before combat
drops. `ns.Strip` asks rather than assumes and the sweep retries, so the worst
case is one Blizzard icon under the block for the rest of a fight, once per
session. To settle it: get a target to nine or more debuffs for the first time
in a session while in combat and watch for one. And whether twelve debuffs over
two lines under a 34 pixel block reads well, which is a look and not a
measurement.

Both lists are in `docs/README.md` with the same detail.

## Careful

`docs/README.md` carries an uncommitted text pass that is not any agent's, 179
added and 12 removed. It has now survived two merges by being stashed and
popped, and was compared line for line against a backup after the second.
