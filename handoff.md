# Handoff

Two agents are building against `UnitFrames/Skin.lua`. Item 8 has landed, item
9 is half built, and one gate number is owed back.

## On main

- `0d1ad42` merges item 8, the frame link. The player block anchors the target
  block and the target block anchors target of target, so Edit Mode positions
  one frame and the addon owns every relationship between frames. Settings are
  `/wk skin link|gap|level`, target of target keeps `TOT_GAP` at three pixels.
- `check.sh` is 0 warnings and 0 errors in 98 files, harness ok both classes.
- 17 new assertions in `scripts/harness/sections/15-skin-fit.lua`. Eleven fail
  against the unlinked layout; the six that do not are named in `6999ba7`.
- They caught a live bug in `Perch`, which early-returned and left target of
  target on the old grid's offset after a resolution change. It writes on every
  pass now.
- `750cabe` settles item 9's open question: the new aura rows are the target's
  only. Your own buffs stay with item 4's nag row, because a temporary weapon
  enchant appears at no aura index and `Buffs/Upkeep.lua:17` already says so.

## In flight

- Item 9's first half is on main. See below.

## Owed

- `Skin.lua`'s ceiling in `check.sh` went 1764 to 2012 rather than being split.
  Todo item 11 is the split that pays it back, after item 9. Measure the new
  number, do not carry one over.
- The `Feature.lua` entry at 879 is gone. `Panel.lua` landed and item 8's
  panel block moved into it, so the allow-list is back to three entries.

## Untested against the live client

All three are in the README's list with what would prove them: how this Edit
Mode signals a drop, whether a frame anchored to another frame can still be
dragged in it, and whether `EDIT_MODE_LAYOUTS_UPDATED` exists on this backport.
The first two fail soft and `/wk skin link off` is the way out without a reload.

## Careful

`docs/README.md` carries an uncommitted text pass that is not any agent's. It
was stashed across the item 8 merge and restored, 179 added lines intact.

## Item 9, first half, on main

`UI/Aura.lua` is one aura square: cropped icon, hairline, seconds along the
bottom, stacks in the corner, and who cast it said by draining the art. It came
out of `EnemyBars.lua` rather than being written beside it, so the bars' debuff
row and the target's row are the same code. The bars lost 39 lines and draw the
same picture, except the stack count is inset by a pixel rather than a unit, so
`bars zoom 2` no longer sits it two pixels in.

`UnitFrames/Auras.lua` is the rows: debuffs against the block, buffs under them,
wrapping downwards, mirrored off the portrait corner. Yours are placed first,
which is the one opinion in the file and the reason a row capped at twelve does
not lose your Rend under a raid's worth of bleeds. Flow runs at layout only; the
tick shows a prefix of squares already placed and moves nothing but the row's
own height. The client's row is hidden by a sweep of one global lookup per row
per tick, because its buttons are built in order and only the one after the last
one hidden can be new.

Settings: `/wk skin auras on|off`, `skin aura <12-32>`, `skin debuffs <0-16>`,
`skin buffs <0-32>`. `skin auras off` leaves the target with no row at all,
because the frame is the block and the client's own row would land in the gauge.

`scripts/harness/sections/34-probe.lua` is throwaway and says so at the top. It
builds an entry by hand and drives `ns.FrameAuras` directly, because nothing in
the addon reaches it yet. It proves the mirroring, the wrap, an empty row
collapsing to a pixel, yours-first, twenty unchanged ticks writing nothing, the
sweep catching buttons the client builds after the skin is on, and combat
refusing a strip with the next tick out of combat taking it.

## Still to do on item 9

- Delete the lift machinery from `Skin.lua`: `AURA_CEILING`, `AnchorOf`,
  `AuraLift`, `entry.auraLift`, `Fit`'s tail, the `UNIT_AURA` handler, the
  `auras` key on the target spec, the aura clause in `FitText`.
- Wire four call sites: `Build`, `Place`, `Refresh`, `Style`/`Unstyle`.
- Fold section 34 into `14-aura-row.lua` and delete it. Fix the hit-rect
  assertion in section 15. Drop `AURA_LIFT`, `auraHeads` and `anchorAuras` from
  `client/08-blizzard.lua`.
- Re-measure `Skin.lua`'s ceiling. It is still 2012 and the delete is worth
  about 110 lines.
- `docs/README.md` and `docs/CHANGELOG.md`, and item 9 to Landed in `todo.md`.
