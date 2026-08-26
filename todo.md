# Todo

Each piece is built by one agent in its own worktree under `.worktrees/`,
on a branch named `worktree-<name>`, and merged into main when
`./scripts/check.sh` comes back at zero. The worktrees stay after the merge.

## Landed

The hash is the commit that put it on main. What was wrong and what fixed it is
in `docs/CHANGELOG.md` and `docs/README.md`; this list is only the receipt.

1. Weapon swing timer. Done, smooth confirmed in game. 8be9a43
2. Deep Wounds missing from the enemy bar debuffs. Done. 05e40ec
3. Overpower drawn as ready when it is not. Done. dbbcd69
4. Missing buff nag, including racials. Done, untested in game. 042df6c
5. Enemy cast bar. Done, untested in game. 89a3e45

## Open

## 6. Party frames

`UnitFrames/Skin.lua:180-223` skins player, target and target of target, then
stops. The Charge button casts Intervene at whoever you are looking at and
there is no fast way to look at a party member, so the frames close a loop the
addon already opened.

## 7. Cooldown row for the long cooldowns

Death Wish, Recklessness, Shield Wall, Last Stand, trinkets. The bars draw a
swipe, but the cooldowns that matter are the ones not under your eyes.

## 8. Link the target block to the player block

### The Edit Mode boundary, which items 8 and 9 both sit on

Edit Mode is not being replaced. It is demoted to one job: it positions the
player block, and that is all it positions. Every relationship between frames
becomes this addon's, starting with the target hanging off the player and the
aura rows of item 9 hanging off both.

That is the only division available, not a compromise. Edit Mode has no notion
of one system anchored to another; it stores an absolute point per system and
writes it back. Anything relational is ours by definition, and the only real
question is how much absolute positioning is left with it. One anchor is the
right amount. Dragging, snapping, switching layouts and storing them per
character all keep working, and none of it has to be written here.

### The link

`UnitFrames/Skin.lua` fits three frames to three blocks and then leaves each
one wherever Edit Mode parked it, so a pair that is mirrored inside each block
sits at unmatched heights and unmatched distances apart. The two blocks should
be one HUD.

One anchor does it: the target block's top corner on the player block's other
top corner, offset by a horizontal gap and a vertical level. Written once, out
of combat, behind the same lockdown guard as `Place` and `Relayout`. The client
maintains it after that, so nothing runs on a tick and nothing resyncs after a
drag. Target of target already hangs off the target block at
`UnitFrames/Skin.lua:1225` and follows with no new code.

The mirroring makes the pair symmetric for free. The player's gauge end is its
right edge and the target's is its left, so linking them faces the two gauges
across the gap and turns the portraits outward.

The gap is measured inner edge to inner edge, in screen pixels, snapped, like
`/wk skin height` and `/wk skin width`. Where the pair lands on screen is still
a fraction of a pixel nobody can read, because the player frame's origin is
Blizzard's. That is the boundary `docs/README.md` already draws round the
block, unchanged.

Four things carry it.

  Dragging the target in Edit Mode sets the offsets. A linked frame that
  swallows your drag is a bug report. On drop, derive `gap` and `level` from
  where it landed relative to the player block, store them, re-anchor. The
  drag still means something and it teaches the two numbers without a slash
  command.

  Edit Mode writes its saved point back over the anchor on login and on layout
  change, so the link re-applies on those events and after the skin's own
  relayout. `Skin.lua` already post-hooks `AnchorSelectionFrame` for this class
  of problem. Which event this hybrid client actually fires goes in the
  untested list in `docs/README.md`, not in a comment claiming it works.

  Off restores. The target frame's own point is recorded before the first link
  and written back by `/wk skin link off`, without a reload, the same
  discipline the skin applies to the frame size and `Charge/SoftTarget.lua`
  applies to a cvar.

  The link requires both frames skinned. Unskinned, `TargetFrame` is 232 by 100
  and a gap measured off its edge means nothing. The setting says so rather
  than drawing something wrong.

    /wk skin link on|off         hang the target block off the player block
    /wk skin gap 120             0 to 400, between the two facing edges
    /wk skin level 0             -100 to 100, the target's drop from the player

Gated in `scripts/harness.lua`: the gap equals the setting at three UI scales;
level 0 puts both block tops on one Y; link off returns the recorded point
exactly; a simulated Edit Mode drag re-derives the gap it was given; turning
the link on during lockdown writes nothing and finishes at
`PLAYER_REGEN_ENABLED`; target of target stays three pixels under the target
block after a relink.

The corridor the gap opens is the reason this is worth building and it is not
in this item. The swing gauges and the enemy cast bar both want to live level
with your eyes between the two blocks rather than under the player, and moving
them there changes what the swing timer means and where you look for it. That
is its own decision, taken after the corridor exists to look at.

## 9. Our own buff and debuff rows on the skinned frames

Depends on item 8, and on the same boundary.

`Skin.lua` does not place the target's aura row today. It measures the lift
Blizzard's row hangs by and sizes the target frame to block plus lift so that
the client's own arithmetic lands the icons under the block. That trick exists
because the row cannot be touched directly: every icon is a child of a secure
unit button, an addon may anchor one out of combat only, and the client
re-anchors the head of the row on every aura the target gains or loses, so
anything placed here is back inside the gauge one refresh into the first pull.

So there is one shape available. Hide the client's row and draw our own, the
way `UnitFrames/EnemyBars.lua` already does: `C_UnitAuras.GetDebuffDataByIndex`
with the `UnitAura` fallback at line 630, our own squares with our own border,
crop and fonts, laid out by `ns.UI.Flow`. That code exists, it is already the
look these frames wear, and the two rows stop being free to drift apart.

The lift machinery dies with it, and that is most of the payoff. No measured
lift, no `UNIT_AURA` handler waiting for the first target with an aura to
settle the number, no frame fitted to block plus tail, no `SetHitRectInsets`
pulling the mouse off a tail that no longer exists, and the target frame
becomes the block exactly like the other two. Deleting it is part of this item,
not a follow-up: leaving both mechanisms in place means two answers for where a
row goes.

Still to decide before it is built: whether the player's own buffs come here or
stay with item 4's nag row, which already reads your auras and already has an
opinion about what is missing.

## 10. The Slam mark, still unconfirmed in game

Carried out of item 1 rather than closed with it. The mark was reported as
wandering once, changed once in `4ab4480`, and has not been looked at in game
since. Nothing in the smoothness work that closed item 1 touched it, and the
bar being smooth says nothing about where the mark sits. Ask before assuming it
is fixed.
