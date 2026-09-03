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
`44c79ef` for 15, at `a7772af` for 16, at `c37c149` for 19, at `b5d2277` for
17, at `30a42cb` for 28, at `2210d8f` for 18 and at `f3222c6` for 32 to 45. Items 14, 23 and 31 were never
written longer than they are here.

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
28. One Questie probe, in Core, and a gate that keeps it one. `07c4401`
18. One ticker, and a HOT list walked rather than typed. `903350d`
31. The four tick-path exemptions, all four allow-listed by name. `395e38a`
32. The action ticker armed once, and `UI.Ticker` refusing a second of one
    name. `86603a3`
33. The action squares drawn on a dirty bit from Blizzard's own events, the
    tick down to range and the count. `86603a3`, the merge fixed at `4021112`
34. Enemy bar threat compared as numbers, level cached per GUID, unit events
    on the plate, the reading at 1 Hz. `7140091`
35. The cast sweep walks the open chambers and stops when there are none.
    `7140091`
36. One combat log reader in Core, six subscribers, off the event when nobody
    listens. `d352b0c`
37. The options window built on first open and refreshed only where visible.
    `9e6accd`
38. Skin and party frames told by unit events, the bar texture hooked rather
    than read back. `eb884ee`
39. `Charge.State` memoised per frame, `Known` cached on SPELLS_CHANGED, the
    draw gated on events. `cd91ccc`
40. Caged frames hooked on SetParent and Show, the verify pass at 5 s.
    `cd91ccc`
41. Feeds and chat rooms mark on arrival and draw once a frame. `2d08eeb`
44. Eleven smaller costs, and a gate that every ticker name has a Perf slot.
    `ba87227`
43. One frame for the ticks that never stop, and a gate that a tick on a frame
    of its own says why. `156dede`
42. The sheet, the book, the aura squares, the feeds, the meters, the swing
    bars and the cooldown row built on first open or first switch. `d87c42d`,
    the last of three
45. Twelve event handlers seeded as hot roots, and a string built on a hot
    path counted as the allocation it is. `f89b5be`, the second of two

Item 10, the Slam mark carried out of item 1, was dropped rather than
finished. Nothing tracks it now. Its text is in this file at `d05546c`.

Items 23 and 31 were never in the Open list. Both came out of reading this file
against the code on 2026-09-02, and their numbers are where they were worked
rather than where a review found them.

Item 31 is item 18's gate read back. Item 18 counted its two markers exactly and
let scripts/ratchet.lua refuse a raise, which left no legal way to add a ninth
`cold:` in any number of commits: the raise fails the ratchet, and lowering the
number first fails the equality. Meanwhile the per-line `-- unguarded:` and
`-- allocates:` exemptions the same scan honours were uncounted, fifteen of them.
The strict door was shut and the unmeasured one was open, which is where the
next exemption would have gone. All four are path-keyed allow-lists now, one
entry per marked function, counted per file and cross-checked against what src/
carries, so an addition is a new key and reviewable and a raise still fails.

## Open

Items 16 to 22 came out of an architecture review on 2026-08-29. Items 16, 17,
18 and 19 landed on 2026-09-02 and are above, with 23. Item 18 had undercounted
the hand-written closure: it said about ninety-five function names and there
were two hundred by the time it was worked, which is the same lesson item 15
taught in the other direction. Read an item against the code before working it. Every one is a duplication
or a rule the addon already believes in and does not enforce. None is a bug: the
addon draws the right thing today. They are the shapes that make the next change
cost more than it should, ordered so the one that drags the most out with it
goes first. Item 15 undercounted its own sites by five and asked for a fix
`0312cf3` had already made.

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

    Item 28 gated the Questie half on 2026-09-02: `QuestieLoader` and
    `ImportModule` outside `Core/Core.lua` fail `check.sh`. The client half is
    the work that is left, and it is not one grep. `_G.` reads 286 times outside
    `src/Core/` and most of them are a frame looked up by name rather than a
    call probed for, so the rule has to name the shape it refuses, which is
    `type(_G.Something) == "function"` on a call the file then makes. Count
    those first: a gate with 286 violations is a warning wearing a gate's
    clothes.

    The other rule this item asked for is one of those two now.

    Item 18 added a third of the same kind on 2026-09-02: a frame handler names
    a function and never opens a closure in place. It is the same shape as the
    two above, a rule the addon already believed in, and it is worth reading
    before this one is written because it shows what the client half costs. That
    gate was one grep and it worked because the shape it refuses is exact.

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
`ns`. Item 28 landed the same day and is above. Two of the three came back quiet
and that is worth writing down. `ns.db` is not the god object it looks like: 215
keys read, and only four read from outside the folder whose `defaults` declares
them, of which `locked` is Core's and meant to be. File-level LCOM4 is 1 almost
everywhere, so the folders hold together. What the measurements did find is one
file that is three modules and five mechanisms each written out between two and
nine times, and they are below in that order.

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

29. The spell row on the options page, twice.

    `src/Buffs/Feature.lua:119-156` and `src/UnitFrames/Panel.lua:31-68` are the
    same 38 lines: a `Spell()` closure over a slot index, an icon, a remove
    button, a label pinned between them, and a measure function returning zero
    height for an empty slot. The comments differ in wording and agree in
    argument. Two lists, one row, and it wants to be `ui.SpellRow` in
    `UI/Widgets.lua` beside the other controls the panel builds.

30. `Bags/Grid.lua` and `Merchant/Grid.lua` are one grid.

    The same functions in the same order: `Subject`, `Enter`, `Leave`, `Build`,
    `Paint`, `Place`, `Trim`, then `Attach`, `Paint`, the pool, `Headers` and
    `Describe` public. The pile walk at the bottom of each is the same walk.

    Weaker than it was, and it is worth saying why rather than deleting it. The
    merchant's unit is a card now: a square with the item's name, the price and
    what is left of the supply beside it, laid out in columns worked out from the
    window's width. The bag window's unit is a bare square in a column count you
    set. So the shared thing left is the pile walk and the pool, and the parts
    that differ have grown. Ranked last of the seven, and the way to find out is
    still to write the shared grid and see what will not fit through it.


Items 32 to 45 came out of a performance review on 2026-09-02, read from source
against a five-man pull with fifteen plates up. The numbers are client calls per
second at steady state, counted from the code rather than measured on the live
client, and the Perf tab is where to check them before and after. One of them
is a bug. The rest are polls that should be events, formats that run before the
compare that would have skipped them, and windows built at login for a session
that never opens them. Ordered by what they cost, with the one that grows all
session first. The full review with every citation is off-tree

All fourteen landed on 2026-09-03, one agent per item in its own
worktree, and are above. Item 45 went last on purpose: it seeds markers on
functions the other thirteen touched, so its counts had to be taken after
them. Its prediction missed in three places worth keeping: there are six
combat-log subscribers, not five; `Breakdown.lua` allocates once per spell
and not once per event; and the seven writes in `Attach` and `Release` could
not take `-- cold:` because those two are the seeded roots, so they are
per-line reasons instead. The Ticker refusal it asked for had already landed
with item 32.

The architecture question the review raised is answered in item 36 and item 33
together. The client is already the event stream. What the addon lacks is not
a bus of its own on top of it but two things narrower than that: one shared
reader in front of each raw source whose read is the cost, and a dirty bit per
widget so that events mark and a tick draws. A general addon-wide stream would
re-broadcast client events through one more dispatch that every handler pays
for, and it would not have found a single item below.

Item 46 is a bug found in game on 2026-09-03, the first on this list that is
one. It is here because the harness passed it, and the fix has to be the gate
as much as the code.

46. A right click on a whisper room turns the camera and leaves the room.

    `src/Chat/Window.lua:787` hands `UI.List` an `onRight` that calls
    `ChatWindow.Close`, and `src/UI/Window.lua:1366` registers the row for
    `RightButtonUp` when a list offers one. Eight lines under that, `IconRow`
    calls `UI.PassCamera` on every row of an icon column, which is
    `SetPassThroughButtons("RightButton", "MiddleButton")`. A button passed
    through never reaches the frame's scripts, however the frame registered,
    so the chat rail hands the camera its right button on the same row that
    is waiting for it. In game the click turns the camera a degree and the
    conversation stays on the rail. `/wk chat close <name>` works, because it
    reaches `Close` without a row.

    The harness certified it. `List:Click` fetched the row's `OnClick` script
    and called it, so `59-chat-rooms` saw the close it asked for on a row the
    client would never have told. The stub records `SetPassThroughButtons` at
    `scripts/harness/client/02-text.lua:395` and nothing read the record back.

    Three lines. `IconRow` keeps the right button on a column that offers
    `onRight` or `onBack`, and the price is a right drag begun on those rows
    does not turn the camera, which is the same price every row that answers
    the button pays. `List:Click` goes through `Button:Click`, which is the
    client's own decision of whether a press reaches the script. And the
    stub's `Region:Click` refuses a button the frame passes through, the way
    it refuses one it never registered for, so the section fails on the code
    it passed.

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

The performance review adds two more that were looked at and left alone.
Stripping comments from the shipped files: all 230 compile in 26 ms in stock
Lua 5.1 with the comments in, so the 45 percent of lines that are comment or
blank cost under 10 ms a login and a build step would buy nothing. And the saved
variables: chat history, quest drops, dungeon drops, breakdown spells and
loadouts are all capped, most at 400, and nothing logs a growing feed or combat
sample, so there is no serialise-on-logout cost to chase.
