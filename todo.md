# Todo

Each piece is built by one agent in its own worktree under `.worktrees/`,
on a branch named `worktree-<name>`, and merged into main when
`./scripts/check.sh` comes back at zero. The worktrees stay after the merge.

## Landed

A title and the commit that finished it. Where an item took several commits the
hash is the last of them. What was wrong and what fixed it is in
`docs/CHANGELOG.md` and `docs/README.md`, what is still unconfirmed in game is
in the README's untested list, and the full text of each item is this file at
`e7ef4ca` for 1 to 6, 8, 11 and 12, at `ca59a77` for 7, 9 and 13, and at
`44c79ef` for 15.

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
14. check.sh derives its class shapes from `Class/*.lua` rather than naming
    them. `371d82d`
15. A placeable HUD frame, named at last. `80528bc`
16. `ns.RegisterUnitEvent` in Core, where the other thirty shims live. Six
    files deleted their own two-branch registration. `3df1df1`
19. `UI.Window` re-zooms its own frame, and every screen sizes on its own.

    The item asked for two lines to move out of four windows and into
    `UI.Window`. By the time it was worked it was ten windows, because six new
    ones landed while it sat open and every one of them copied the pair, which
    is the item predicting its own cost and being right.

    It came out larger than the item asked because the shape underneath was
    wrong rather than repeated. One number sized every window, so the duplicated
    lines were four windows agreeing about a fact none of them owned.
    `UI.Window` takes a getter, each screen carries its own key, and the twenty
    three of them are declared through `ns.Register` and drawn off `ns.Zooms()`.
    Item 17's argument applies to this list too: a registry entry retires a
    hand-written page, and the page was never the thing worth writing.

23. A ceiling only moves down, in `scripts/ratchet.lua`. It reads the committed
    copy of `shape.lua` and of `check.sh` against the copies on disk and fails
    on any of the twenty three ceilings that went up. `271f8e6`

Item 10, the Slam mark carried out of item 1, was dropped rather than
finished. Nothing tracks it now. Its text is in this file at `d05546c`.

Item 23 was never in the Open list. It came out of reading the list against the
code on 2026-09-02: every item here is a rule the addon believes in and does not
enforce, and the allow-lists that hold those rules could be edited upward by the
change they blocked. `59b36ce` had already done it once. The list numbers it 23
because it is the twenty-third thing worked, not because a review found it.

## Open

Items 16 to 22 came out of an architecture review on 2026-08-29. Items 19 and
16 landed on 2026-09-02 and are above. Every one is a duplication or a rule the
addon already believes in and does not enforce. None is a bug: the addon draws
the right thing today. They are the shapes that make the next change cost more
than it should, ordered so the one that drags the most out with it goes first.
Item 15 undercounted its own sites by five and asked for a fix `0312cf3` had
already made, so read an item against the code before working it.

17. The slash dispatchers, off a table rather than a chain of ifs.

    `Command.Number` abstracts the parsing and stops there. Its 34 callers then
    each hand-write the same four steps: write `ns.db.<key>`, call the module's
    `Apply`, `ns.Print` a sentence, `return`. `src/Swing/Feature.lua:44`,
    `src/Cooldowns/Feature.lua:35` and `src/Progress/Feature.lua:44` are three
    identical zoom handlers differing in the db key, the apply call and one
    noun.

    What it costs is on the shape report. `SkinWord` is 119 lines and 37
    branches, `BarsWord` 97 and 37, `BuffWord` 97, and two of them hold entries
    in the `scripts/shape.lua` allow-list reading "a slash dispatcher, one
    branch per word". A declarative table of
    `{ word, key, low, high, apply, say }` handed to a shared runner retires
    both entries instead of raising a number, which is the direction that list
    is meant to move.

18. One ticker, and a HOT list derived from it.

    Twelve files write the same throttle: accumulate the delta, compare it to an
    interval, zero it, call, and in four of them wrap the call in `Perf.Start`
    and `Perf.Stop`. `src/Charge/Marker.lua:201`, `src/Meter/Window.lua:647`,
    `src/Perf/Perf.lua:247`, `src/Feeds/Stream.lua:290`, and the rest behind
    named `OnUpdate` locals.

    A `ns.UI.Ticker(interval, name, fn)` collapses them, and that is the smaller
    half. The larger half is `HOT` in `scripts/check.sh:208`: about ninety-five
    function names, written out by hand, which is a transitive closure a person
    is maintaining. `check.sh:481` checks that a file with an `OnUpdate` names
    something in HOT, which is a good first cut and does not catch the failure
    that matters. A hot function that grows a new callee nobody added to the
    list takes the guard scan quietly off that code. Registering every ticker
    through one call is what makes the closure derivable instead of typed.

20. `EachTexture` into Core, beside `ns.Strip`.

    `src/Artwork/Artwork.lua:59` and `src/UnitFrames/Art.lua:248` are the same
    pcall-guarded walk over a frame's texture regions, differing only in Art's
    `keep` set. Artwork's copy opens with "pcall guarded for the same reason
    `ns.Measure` is", which is the author noticing where it belongs and not
    moving it. It goes next to `ns.Strip`, `ns.Unstrip` and `ns.Blocked`, which
    are the three calls it exists to feed.

21. One layering rule, gated rather than commented.

    Item 16 has landed, so the rule it leaves behind can be gated. Outside
    `src/Core/`, no file probes the client for a call it means to make. It
    belongs with the GameTooltip rule and with the `src/UI/` rule item 15
    wrote, which are the same idea already written down and already enforced.

    The other rule this item asked for is one of those two now.

22. `Core/Menu.lua` registers a feature from inside Core.

    `src/Core/Core.lua:8` promises that Core knows nothing about any feature and
    that an eighth part must not mean editing this file. Twenty-five parts keep
    that promise by registering from `<Folder>/Feature.lua`. `Core/Menu.lua:275`
    is the one that does not. It is a small file and a real feature, with a
    slash word and a status line, and it wants a folder like everything else.
    Worth doing last, when the four items above have already proved the
    registry does not need Core's help.

## Deliberately not on this list

The architecture review turned up two more repeats and both are right as they
stand. `src/Progress/Progress.lua:70` and `src/Quests/Client.lua:43` hold the
same four-line probed call, and the comment above the first one argues that
each is written against its own returns and that a prober in Core would be a
call every part reaches through rather than a seam each part draws. That
argument holds. `src/UI/Feed.lua`, `src/UI/Log.lua` and `src/UI/Stack.lua` each
open by saying why they are not one of the others, and each of those three
arguments holds too.
