# Handoff

Items 8 and 9 are both on main and neither has been confirmed in game. That is
the whole of where things stand.

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
- `check.sh` exits 0, luacheck 0 warnings and 0 errors across 101 files,
  harness ok on both flavours.

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

## What to do next

- Confirm item 8 and item 9 in game. Item 8's geometry has been looked at once
  and read right; the aura rows have not been seen at all.
- Todo item 11, the `Skin.lua` split, for the reason the file has three subjects
  rather than because of a line count.
- Target of target reads as an orphan under the target block's inner edge.
  `TOT_GAP` at three and `TOT_SCALE` at 0.62 were both chosen when the target
  block sat somewhere else, and the corridor item 8 opened is the natural place
  for it. Not written up as an item yet.

## Untested against the live client

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
