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
8. The target block linked to the player block. The first build hung it a fixed
   distance off the player, which put the line the pair mirrored about wherever
   Edit Mode had left the player. Reflected in the middle of the screen
   instead, confirmed in game. 0d1ad42, 2b90c7f, 2a999b5
6. Party and raid frames. Ours rather than Blizzard's skinned, off a secure
   group header, in a slot order that is role then name and is only rewritten
   out of combat. Done, untested in game. e3de603
12. The chat window, reimagined. Three tabs became a rail of rooms, the room
   you are reading is the channel you type into and fills the line in with its
   own slash, the important people are in named groups with a room each, and
   Blizzard's chat window is hidden with everything it would have drawn
   forwarded to a System room. Done, untested in game; three things to look at
   are in the README's untested list.

## Open

## 7. Cooldown row for the long cooldowns

Death Wish, Recklessness, Shield Wall, Last Stand, trinkets. The bars draw a
swipe, but the cooldowns that matter are the ones not under your eyes.

## 9. Our own buff and debuff rows on the skinned frames

Built on both frames. Not confirmed in game, and it stays here until it is.

`UI/Aura.lua` is one aura square and every row in the addon is made of it: the
debuff row on an enemy bar, the two under the target block and the two under
the player block. That is what stops them drifting apart, and it is why
`EnemyBars.lua` lost 39 lines rather than gaining a twin. `UnitFrames/Auras.lua`
is the rows themselves, out of `C_UnitAuras` with the `UnitAura` fallback, laid
out by `ns.UI.Flow` at layout time only. Yours are placed first, because the
client's order is the order the auras landed in and a capped row otherwise loses
your Rend under a raid.

The lift machinery is deleted, which was most of the point: no measured lift, no
`UNIT_AURA` handler waiting for the first target with an aura, no frame fitted
to block plus tail, no hit rect pulled off a strip that no longer exists. All
three frames are the block exactly.

The client's rows are hidden by a sweep of one global lookup per row per tick,
because its buttons are built on demand and in order.

Settings are `/wk skin auras on|off`, `skin aura 12-32`, `skin debuffs 0-16` and
`skin buffs 0-32`, and one number covers both frames rather than four. Off
leaves both frames with no row at all, because each frame is its block and the
client's own row would land inside the gauge.

Buffs over the block and debuffs under it, every row starting on the gauge end
and running outward, so the four of them read away from the corridor the way
the two blocks do. Nothing chains, so a target picking up a raid's worth of
bleeds moves nothing that was already on the screen. `lineOrder` on the
`ns.UI.Flow` node was already there for the enemy bars and is what keeps line
one against the block on the row above it.

The open question at the foot of this item was answered the wrong way and is
answered again. `750cabe` said your own buffs stay with item 4's nag row,
because Blizzard does not hang them off `PlayerFrame`: they are `BuffFrame`, and
a temporary weapon enchant appears at no aura index at all. Item 8 made the
target the player mirrored, and a HUD with rows on one side of it only is not
one HUD. The player is now an entry in `Auras.lua`'s own table, which is what
that file was shaped for, and `Skin.lua` did not change at all.

One thing went off the screen with `BuffFrame` and stays off. Right click to
cancel a buff is gone, because cancelling one is a protected call and a square
drawn here cannot make it; getting it back is a secure button per square and
waits for somebody to miss it. The temporary weapon enchant on each hand leads
your buff row instead, out of `Buffs/Upkeep.lua`, because it sits at no aura
index and the client's row was the only thing drawing it.

Three things to look at in game rather than measure. Whether the client's aura
buttons are protected on this backport, which decides whether one built mid
fight can be hidden before combat drops. Whether the four button names are what
this client calls them, which `/wk skin probe` answers in one look at a full
list. And whether twelve debuffs over two lines under a block reads well at
all, starting with the player's pair, because you carry more buffs than a
target does and the count ships at 8. All three are in the README's untested
list with what would settle them.

## 10. The Slam mark, still unconfirmed in game

Carried out of item 1 rather than closed with it. The mark was reported as
wandering once, changed once in `4ab4480`, and has not been looked at in game
since. Nothing in the smoothness work that closed item 1 touched it, and the
bar being smooth says nothing about where the mark sits. Ask before assuming it
is fixed.

## 11. Split Skin.lua, because it has three subjects

The number this item used to be about is gone. `8ad829f` deleted the file line
ceiling and put `scripts/shape.lua` in its place, which measures a function's
own lines, its depth and its branches, so cutting a file in half moves nothing
it reports. What is left is the reason that was always underneath: the file
holds three unrelated jobs. The region walk that strips Blizzard's art and puts
it back. The block geometry that sizes and places what we draw. The tick.

Item 9 no longer blocks it. The lift machinery is deleted and the rows are
`UnitFrames/Auras.lua`, so nothing is left that belongs to none of the three.

Measure the three files after the cut and say what they came out at. Nothing is
owed back, and a function that moves without changing has to come back with the
same three numbers, which is the check that the cut was a move and not a
rewrite.

## 13. What the class split left behind

Five things out of a read of `c536c44`. The split itself is right: the registry
is the correct shape, the load order is correct, and the "nil is the gate" rule
holds everywhere it was traced. All four harness shapes pass. These are what
did not come with it.

`Layout.Describe` errors on a class with no plan. `Buttons/Layout.lua:452`
calls `Paging(plan)` with `plan` possibly nil, and `CanApply` tests combat and
the cursor before it tests the plan, so `BUSY_COMBAT` and `BUSY_CURSOR` fall
past the early return and reach `#plan.pages` at `Buttons/Layout.lua:237`.
`/wk status` reaches it through `Buttons/Feature.lua:604`. It needs
`Bar1Bases` to answer, so it is a druid in a form and not a hunter in a field.
A regression: `Layout.PLAN` was a constant table and was never nil. Proved
against the harness as a hunter, with `InCombatLockdown` forced true and the
client put in stance 1: `attempt to index local 'plan' (a nil value)`.

`Class.Is` is dead and its comment says otherwise. `Class/Class.lua:118` reads
"Everything that decides once at login goes through here" and nothing in `src`
calls it. `Charge.Available`, `Reaction.Arm`, `Loadouts.All`, `Icon.lua` and
`Marker.lua` all go through `Class.Of`, which answers no on an unresolved
class, which is the failure `Class.Is` was written against. Every one of them
fires at `PLAYER_LOGIN` where `UnitClass` answers, so nothing is broken today,
but `Loadouts.All` writes `loadoutsSeeded` off `Stance.Count() == 0` and that
write is one way. Either wire the login deciders through `Class.Is` or delete
it and rewrite the comment to say the guard is to ask at `PLAYER_LOGIN` and
never earlier.

`Charge/Feature.lua:72` states the opposite of what the code does. It says the
row is drawn and refuses rather than being left out, and `BuildStart` at
`Core/Panel.lua:506` now leaves it out. The commit message carries the reason
for the reversal; the comment never got it.

`docs/README.md` still documents `ns.IsWarrior()` as live API in three places:
the index at line 735, the gotcha at 1562, which teaches the removed
unresolved-answers-yes semantics and is now wrong in a way that would mislead
the next reader, and the Charge section at 1745, which says that page is one
sentence instead of four tabs when it is no page. `ns.Class` and `Class/`
appear nowhere in it.

`Class.Label()` falls back to `"this character"`, which reads "a this character
has none" through `Charge.Refusal` and `Layout.Refusal`. Only reachable before
the client answers, so it is cosmetic.

One coverage gap to close with the fix. `FillRail`'s drop branch, where a class
registers a file but opens no page under its own rail entry, runs on no harness
shape, because Mage and Shaman both carry a `loadout`. Add a check that calls
`Layout.Describe` under lockdown on every run, and a shape that registers
`upkeep` and nothing else.
