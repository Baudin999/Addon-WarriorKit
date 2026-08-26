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
aura row of item 9 hanging off the target block.

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

Built. Not confirmed in game, and it stays here until it is, the same as item 8.

`UI/Aura.lua` is one aura square and both rows in the addon are made of it: the
debuff row on an enemy bar and the two under the target block. That is what
stops them drifting apart, and it is why `EnemyBars.lua` lost 39 lines rather
than gaining a twin. `UnitFrames/Auras.lua` is the rows themselves, out of
`C_UnitAuras` with the `UnitAura` fallback, laid out by `ns.UI.Flow` at layout
time only. Yours are placed first, because the client's order is the order the
auras landed in and a capped row otherwise loses your Rend under a raid.

The lift machinery is deleted, which was most of the point: no measured lift, no
`UNIT_AURA` handler waiting for the first target with an aura, no frame fitted
to block plus tail, no hit rect pulled off a strip that no longer exists. All
three frames are the block exactly. `Skin.lua` went 2012 to 1934 with it.

The client's row is hidden by a sweep of one global lookup per row per tick,
because its buttons are built on demand and in order.

Settings are `/wk skin auras on|off`, `skin aura 12-32`, `skin debuffs 0-16` and
`skin buffs 0-32`. Off leaves the target with no row at all, because the frame
is the block and the client's own row would land inside the gauge.

The open question at the foot of this item is answered and the reasoning is in
`750cabe`: your own buffs stay with item 4's nag row. Blizzard does not hang
them off `PlayerFrame`, they are `BuffFrame`, and a temporary weapon enchant
appears at no aura index at all. The rows are built so that one entry in
`Auras.lua`'s own table adds the player later if that ever changes.

Two things to look at in game rather than measure. Whether the client's aura
buttons are protected on this backport, which decides whether one built mid
fight can be hidden before combat drops. And whether twelve debuffs over two
lines under the target block reads well at all. Both are in the README's
untested list with what would settle them.

Target of target is the third. The rows hang under it because it is parked on
the corner they hang from, so if it moves into the corridor the way item 8's
test suggests it should, the rows come straight back up against the block on
their own and nothing here has to change.

## 10. The Slam mark, still unconfirmed in game

Carried out of item 1 rather than closed with it. The mark was reported as
wandering once, changed once in `4ab4480`, and has not been looked at in game
since. Nothing in the smoothness work that closed item 1 touched it, and the
bar being smooth says nothing about where the mark sits. Ask before assuming it
is fixed.

## 11. Split Skin.lua, and take the ceiling back down

Item 8 raised `UnitFrames/Skin.lua` in `check.sh` from 1764 to 2012 rather than
taking the split, and that number is owed back. The split `check.sh` names for
that file is the region walk, the block geometry and the tick.

It waits for item 9, which deletes the lift machinery: roughly 110 lines that
belong to none of the three pieces. Carving first means cutting a file that
still has them in it and then deleting a slice out of one of the pieces, with
both open branches rebasing across the rewrite. After item 9 the three pieces
are the three subjects and nothing moves twice.

Measure the new number rather than reusing one. Item 9 lowers the file too, and
a ceiling handed from one commit to the next instead of measured is not a
ratchet.

The fourth allow-list entry, `UnitFrames/Feature.lua` at 879, goes away on its
own when item 9's `UnitFrames/Panel.lua` split lands and item 8's panel block
relocates into it. It is not part of this item.
