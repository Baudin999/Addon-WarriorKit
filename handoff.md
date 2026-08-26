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

- Session `warriorkit-8e`, branch `worktree-target-auras` at `5f5a1fb`, holds
  item 9's first half: `UI/Aura.lua`, `UnitFrames/Auras.lua`, and a
  `UnitFrames/Panel.lua` split that takes `Feature.lua` from 904 to 481.
  `Skin.lua` untouched, `check.sh` at zero. It is waiting to rebase onto
  `0d1ad42`.
- What is left there: delete the lift machinery from `Skin.lua`, wire four call
  sites, rewrite section 14, fix the hit-rect assertion in section 15.

## Owed

- `Skin.lua`'s ceiling in `check.sh` went 1764 to 2012 rather than being split.
  Todo item 11 is the split that pays it back, after item 9. Measure the new
  number, do not carry one over.
- The `Feature.lua` entry at 879 disappears when item 9's `Panel.lua` split
  lands and item 8's panel block relocates into it.

## Untested against the live client

All three are in the README's list with what would prove them: how this Edit
Mode signals a drop, whether a frame anchored to another frame can still be
dragged in it, and whether `EDIT_MODE_LAYOUTS_UPDATED` exists on this backport.
The first two fail soft and `/wk skin link off` is the way out without a reload.

## Careful

`docs/README.md` carries an uncommitted text pass that is not any agent's. It
was stashed across the item 8 merge and restored, 179 added lines intact.
