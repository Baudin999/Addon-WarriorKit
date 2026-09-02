# Todo

Each piece is built by one agent in its own worktree under `.worktrees/`,
on a branch named `worktree-<name>`, and merged into main when
`./scripts/check.sh` comes back at zero. The worktrees stay after the merge.

## Landed

A title and the commit that finished it. Where an item took several commits the
hash is the last of them. What was wrong and what fixed it is in
`docs/CHANGELOG.md` and `docs/README.md`, what is still unconfirmed in game is
in the README's untested list, and the full text of each item is this file at
`e7ef4ca` for 1 to 6, 8, 11 and 12, at `ca59a77` for 7, 9 and 13, at
`44c79ef` for 15, at `a7772af` for 16, at `c37c149` for 19 and at `b5d2277` for
17. Items 14 and 23 were never written longer than they are here.

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
16. `ns.RegisterUnitEvent` in Core, where the other thirty shims live.
    `3df1df1`
17. The slash dispatchers, off a table rather than a chain of ifs. `abddb67`
19. `UI.Window` re-zooms its own frame, and every screen sizes on its own.
    `da4a01a`
23. A ceiling only moves down, in `scripts/ratchet.lua`. `271f8e6`

Item 10, the Slam mark carried out of item 1, was dropped rather than
finished. Nothing tracks it now. Its text is in this file at `d05546c`.

Item 23 was never in the Open list. It came out of reading this file against the
code on 2026-09-02, and its number is where it was worked rather than where a
review found it.

## Open

Items 16 to 22 came out of an architecture review on 2026-08-29. Items 16, 17
and 19 landed on 2026-09-02 and are above, with 23. Every one is a duplication
or a rule the addon already believes in and does not enforce. None is a bug: the
addon draws the right thing today. They are the shapes that make the next change
cost more than it should, ordered so the one that drags the most out with it
goes first. Item 15 undercounted its own sites by five and asked for a fix
`0312cf3` had already made, so read an item against the code before working it.

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
    Worth doing last, when the three items above have already proved the
    registry does not need Core's help.

Items 24 to 30 came out of a second architecture review on 2026-09-02, run
against three measurements rather than a reading: LCOM over shared module state,
a token clone detector across every pair of files, and fan-in and fan-out on
`ns`. Two of the three came back quiet and that is worth writing down. `ns.db`
is not the god object it looks like: 215 keys read, and only four read from
outside the folder whose `defaults` declares them, of which `locked` is Core's
and meant to be. File-level LCOM4 is 1 almost everywhere, so the folders hold
together. What the measurements did find is one file that is three modules and
five mechanisms each written out between two and nine times, and they are below
in that order.

24. `UnitFrames/EnemyBars.lua` is three modules in one file.

    2,450 lines, 72 top-level functions, 25 mutable module locals, and 26
    distinct `ns.*` names, which is the largest fan-out in the addon. Its own
    section headers name five subjects, at `:269`, `:578`, `:774`, `:1482` and
    `:1734`, and two of the five touch none of the other three's state.

    The tracked spell list at `:269` is 17 functions over `trackedNames`,
    `trackedIcons` and `unresolved`, and nothing else. It is a saved list with
    Add, Remove, Reset, Repair and Resolve on it, no frame anywhere in it, and
    it is sitting inside a nameplate widget.

    The Blizzard plate handling at `:1482` is 8 functions over `stripped`,
    `pending` and `passThrough`, and it shares exactly one name, `stripped`,
    with the modes block under it. It is the ninth `Blizzard.lua`, filed under a
    different name and inside the file it hides plates for.

    Worth measuring the way it was found, because a file-level LCOM4 reads this
    file as cohesive: the call graph glues the three together even though the
    state does not. On state alone it is five components.

25. Nine `*/Blizzard.lua` files, one contract, written down nowhere.

    2,292 lines. Seven of the nine define the same three public calls, `Wanted`,
    `Apply` and `Describe`, over the same two private ones, `Frame` and
    `Remember`. Two mechanisms sit under that: park the frame off the screen at
    no alpha, or put it in the attic and take its key.

    `src/Mail/Blizzard.lua:65-160` and `src/Merchant/Blizzard.lua:68-198` are
    the same 90 lines of park. Run both through `diff` with the words `mail` and
    `merchant` substituted out and what is left is Merchant's drift check and
    two spellings of the same early return. `src/Map/Blizzard.lua:55-190` and
    `src/Quests/Blizzard.lua:60-165` are the same cage and key swap, and the
    only real difference is that Map opens the dungeon window when you are
    standing in one.

    The consequence is already on disk. Five of the seven end with
    `ns.BlizzHide.Also(Blizz.Apply)`; Mail and Quests do not, and are driven
    instead by seven hand-written `Apply()` calls across their `Feature.lua`
    and `Window.lua`. Nothing says whether that is deliberate, and the only way
    to find out is to open seven files side by side.

26. Taking a key off the client, written nine times.

    `SetOverrideBindingClick` onto a secure button, `ClearOverrideBindings`
    before it, a `Holds(key)` that reads the override layer back through
    `GetBindingAction` rather than trusting the set, and a record of the binding
    that got displaced. That is four calls with a subtle contract, and it is
    written out in `src/Targeting/Switch.lua:74`, `src/Charge/Icon.lua:275`,
    `src/Hover/Cast.lua:194`, `src/Dungeons/Key.lua:57`,
    `src/Marking/Keys.lua:74`, `src/Buttons/Bars.lua:371`,
    `src/Loadouts/Loadouts.lua:278` and `src/Character/Blizzard.lua:167`.
    `src/Dungeons/Key.lua:60-90` and `src/Targeting/Switch.lua:74-104` are the
    same 30 lines down to the comment above `Holds`.

    `ns.Rebind` at `src/Core/Core.lua:1459` already centralises the half that
    hurt: the re-take after `UPDATE_BINDINGS`, with the frame's delay and the
    latch that collapses the storm. Six files register with it. Two do not.
    `src/Buttons/Bars.lua:813` answers the event itself and Core's own comment
    at `:1434` allows for that. `src/Character/Blizzard.lua:200` is the one
    worth looking at: a second frame, a second `UPDATE_BINDINGS` registration,
    and a `dirty` flag picked up on `BlizzHide`'s tick, which is Core's
    mechanism rebuilt beside Core's mechanism.

    So the shared piece is the take, not the re-take. `ns.TakeKey(button, key,
    name)` returning the displaced binding, with `ns.Rebind` called from inside
    it, retires eight copies and makes the registration impossible to forget.

27. A window has no lifecycle, so twelve files invented one.

    `UI.Window` hands back an object with `Show`, `Hide` and `IsShown` on it at
    `src/UI/Window.lua:493-504`. Twelve files call `UI.Window(` and every one of
    them wraps that object in its own `Show`, `Hide`, `Shown` and `Toggle` over
    a file-local named `window`.

    Four spellings of one boolean came out of it. `window ~= nil and
    window:IsShown()` in Map, Quests, Dungeons and Character. `(window and
    window:IsShown()) and true or false` in Bags and Merchant. `built and
    window:IsShown() and true or false` in Chat. And
    `src/Mail/Window.lua:1097`, which reaches past the object into
    `window.frame:IsShown()`, which is the one that will break when the object
    grows a wrapper.

    The names went too. `src/Breakdown/Window.lua` carries `Open`, `Close`,
    `IsShown`, `Shown` and `Toggle`, which is five names for two states in one
    file. `src/Dungeons/Window.lua:847-864` and `src/Map/Window.lua:406-423`,
    which are `Hide`, `Shown` and `Toggle`, are identical line for line.

    The fix is on the object, not in Core: `Toggle`, a `Shown` that is the one
    spelling, and an optional `onShow` for the parts that paint on the way up.

28. The Questie probe, four times, after somebody already extracted it.

    `src/Quests/Where.lua:96` hands out `Where.Module`, and the comment above it
    at `:81` says a third copy of a pcall round `ImportModule` is how the first
    two got there. Nothing outside that file reads it. There are four identical
    copies now, at `src/Quests/Where.lua:84`, `src/Quests/Tracker.lua:54`,
    `src/Quests/Party.lua:46` and `src/Map/Pins.lua:93`, plus a fifth variant at
    `src/Comfort/Clutter.lua:45`.

    This is item 21's rule with a name on it. The probe belongs in Core, the
    export in `Where.lua` comes out, and the rule item 21 writes is what stops
    the fifth copy.

29. The spell row on the options page, twice.

    `src/Buffs/Feature.lua:119-156` and `src/UnitFrames/Panel.lua:31-68` are the
    same 38 lines: a `Spell()` closure over a slot index, an icon, a remove
    button, a label pinned between them, and a measure function returning zero
    height for an empty slot. The comments differ in wording and agree in
    argument. Two lists, one row, and it wants to be `ui.SpellRow` in
    `UI/Widgets.lua` beside the other controls the panel builds.

30. `Bags/Grid.lua` and `Merchant/Grid.lua` are one grid.

    701 lines between them, and the same eighteen functions in the same order:
    `Subject`, `Enter`, `Leave`, `Build`, `Square`, `Paint`, `Place`, `Trim`,
    then `Attach`, `Paint`, `Squares`, `Headers` and `Describe` public.
    `src/Bags/Grid.lua:366-377` and `src/Merchant/Grid.lua:268-279` are the same
    lines.

    The two differ in where a square's contents come from and what a click does,
    which is a table of callbacks rather than a second file. Ranked last of the
    seven because it is the one where the split might be right, and the way to
    find out is to write the shared grid and see what will not fit through it.


## Deliberately not on this list

The architecture review turned up two more repeats and both are right as they
stand. `src/Progress/Progress.lua:70` and `src/Quests/Client.lua:43` hold the
same four-line probed call, and the comment above the first one argues that
each is written against its own returns and that a prober in Core would be a
call every part reaches through rather than a seam each part draws. That
argument holds. `src/UI/Feed.lua`, `src/UI/Log.lua` and `src/UI/Stack.lua` each
open by saying why they are not one of the others, and each of those three
arguments holds too.

This review adds three more that measured badly and read fine. `src/Class/*.lua`
files repeat each other because each is a registry of one class's spells, and
the repeats are the table shape rather than the data. `UI.Quality` in
`src/UI/Theme.lua:100` and `Color.power` in `src/Unit/Color.lua:355` are two
palettes that happen to be the same size. And ten parts open a placeable HUD
frame with the same four calls, `CreateFrame`, `ns.UI.Adopt`, `ns.UI.Unit` and
`ns.UI.Placeable`, which is four lines with no logic in them and is what a
constructor already looks like.
