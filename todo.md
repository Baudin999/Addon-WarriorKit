# Todo

Each piece is built by one agent in its own worktree under `.worktrees/`,
on a branch named `worktree-<name>`, and merged into main when
`./scripts/check.sh` comes back at zero. The worktrees stay after the merge.

## Landed

Items 1 to 6, 8, 11 and 12 are on main. The list, with the commit that put each
one there, is this file at `e7ef4ca`; the reasons are in `docs/CHANGELOG.md` and
`docs/README.md`, and what is still unconfirmed in game is in the README's
untested list.

Item 11 split `UnitFrames/Skin.lua` into four rather than three: `Art.lua` for
the walk, `Block.lua` for the geometry, `Paint.lua` for the tick, and `Skin.lua`
left as the part. Taking three subjects out of a file leaves a fourth behind.
The three functions the item asked to be measured came out at what they went in
at, `Place` at 195 lines of its own, `Build` at 83 and `Refresh` at 99, which is
the check that the cut was a move.

## Open

## 7. Cooldown row for the long cooldowns

Death Wish, Recklessness, Shield Wall, Last Stand, trinkets. The bars draw a
swipe, but the cooldowns that matter are the ones not under your eyes.

Built, and it stays here until it has been looked at in game.

It is a class part rather than a warrior one, which is the half worth writing
down. The list is a seventh field in the class registry, so `Class/Warrior.lua`
names those four and no file outside `Class/` names a spell. A mage brings
eight, a shaman six, a priest five, and a class nobody has written a file for
brings none and still gets its trinkets. Adding a class is still one file.

Three filters decide what is actually drawn and each one drops a square on its
own: an id this client cannot name, which is most of what separates Era from
Burning Crusade in those files; a spell this character has not learned, which is
how an unspent talent and an unvisited trainer both come out right without the
class file knowing about specs; and one switch per entry, per character, for
whatever you do not want to look at.

The trinkets are the client's answer rather than a list. An item with a use
effect answers `GetItemSpell` and a passive one answers nothing, so the row
carries the one you press and skips the one you wear.

`Cooldowns/Cooldowns.lua` is what is on the row, `Row.lua` is when it is on the
screen and what it looks like, `Feature.lua` is the settings.
`42-cooldown-row.lua` runs it on all five class shapes and measures the counts
against the class file rather than against a number written in the test.

Two things fell out of it that are not the row. `UI/Ability.lua` counts in
minutes above a minute, so a thirty minute cooldown reads 30m rather than 1798
on every square in the addon. `ns.BuffName` moved into Core, because two parts
now walk your own buffs for the same string. The rail renumbered as well: the
row took 10 and the nine parts below it moved down one, because the registry
takes whole numbers only.

Four things to look at in game rather than measure. Whether the nineteen ids in
the mage, shaman and priest files name what this addon thinks they name, which
`/wk cooldowns list` answers per character in one look. Whether Ice Block
answers to either of its two ids. Whether `GetItemSpell` and
`GetInventoryItemCooldown` answer at all on these clients, which decides whether
the trinket half exists. And whether a row of five squares over your character
at 1x reads at a glance mid-pull, or wants the buff nag's 2x. All four are in
the README's untested list with what would settle them.

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

## 13. What the class split left behind

One thing left out of a read of `c536c44`, down from five. The split itself is
right: the registry is the correct shape, the load order is correct, and the
"nil is the gate" rule holds everywhere it was traced. All five harness shapes
pass.

`Class.Label()` falls back to `"this character"`, which reads "a this character
has none" through `Charge.Refusal` and `Layout.Refusal`. Only reachable before
the client answers, so it is cosmetic.

The other four landed. The `Layout.Describe` crash went first, with the refusal
ordering that caused it and the coverage gap that hid it: `CanApply` asks for
the plan before it asks about combat, section 21 calls both under lockdown on
every class, and `Class/Priest.lua` is the fifth harness shape. `Class.Is` is
deleted, because nothing called it and the guard it claimed to be was never in
the path; the rule it stood for is the section comment in `Class/Class.lua` plus
one explicit check in `Loadouts.All`, which was the one place a wrong answer was
written down and kept, and `20-loadouts` fails without it.
`Charge/Feature.lua` no longer says its row on Start is drawn and refuses when
`BuildStart` leaves it out. `docs/README.md` names `ns.Class` in all three
places it used to name `ns.IsWarrior()`, and its file layout lists `Class/`. The
reasons are in `docs/CHANGELOG.md`.
