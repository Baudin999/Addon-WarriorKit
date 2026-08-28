# Todo

Each piece is built by one agent in its own worktree under `.worktrees/`,
on a branch named `worktree-<name>`, and merged into main when
`./scripts/check.sh` comes back at zero. The worktrees stay after the merge.

## Landed

A title and the commit that finished it. Where an item took several commits the
hash is the last of them. What was wrong and what fixed it is in
`docs/CHANGELOG.md` and `docs/README.md`, what is still unconfirmed in game is
in the README's untested list, and the full text of each item is this file at
`e7ef4ca` for 1 to 6, 8, 11 and 12, and at `ca59a77` for 7, 9 and 13.

1. Weapon swing timer. `8be9a43`
2. Deep Wounds missing from the enemy bar debuffs. `05e40ec`
3. Overpower drawn as ready when it is not. `dbbcd69`
4. Missing buff nag, including racials. `042df6c`
5. Enemy cast bar. `89a3e45`
6. Party and raid frames, ours off a secure group header. `e3de603`
7. Cooldown row for the long cooldowns, out of the class registry. `2245a01`
8. The target block linked to the player block, reflected about the middle of
   the screen rather than pinned a fixed distance off it. `2a999b5`
9. Our own buff and debuff rows on the skinned frames. `1871fa6`
11. Split `Skin.lua`, which had three subjects and came apart into four.
    `a5624de`
12. The chat window, reimagined as a rail of rooms. `1c4de0e`
13. What the class split left behind, down to the `Class.Label()` fallback.
    `fc6c0e5`

## Open

## 10. The Slam mark, still unconfirmed in game

Carried out of item 1 rather than closed with it. The mark was reported as
wandering once, changed once in `4ab4480`, and has not been looked at in game
since. Nothing in the smoothness work that closed item 1 touched it, and the
bar being smooth says nothing about where the mark sits. Ask before assuming it
is fixed.

## 14. check.sh names its class shapes by hand

`scripts/check.sh:636` runs the harness as WARRIOR, MAGE, SHAMAN, PRIEST and
HUNTER, written out as five words with nothing tying them to `src/Class/*.lua`.
A sixth class file gets no run at all.

What that hides is a login error rather than a wrong answer. The cap of eight
entries on the cooldown row and four on the upkeep row is an `assert` inside
`Cooldowns.All` and `Upkeep.Fixed`, which fires on the client, at login, as a
Lua error, and the only thing that reaches it first is a harness run as that
class. `Class/Mage.lua` already lists eight cooldowns, so the ninth is the one
that does it.

The fix is to derive the loop from the files, keeping HUNTER as the shape with
no file of its own, which turns a login error into a check.sh failure.
