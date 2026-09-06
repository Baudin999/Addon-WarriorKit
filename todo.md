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
17, at `30a42cb` for 28, at `2210d8f` for 18, at `f3222c6` for 32 to 45 and at
`1ad54d1` for 46 and at `229a60f` for 47. Items 14, 23 and 31 were never
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
46. A right click on a whisper room turned the camera and left the room;
    a row that answers the right button keeps it, and the harness presses
    rows the way the client does. `673d78c`
47. A bag pickup filter switched from the bag window: a price floor for greys
    and whites, one button that throws the filter and the leftovers together,
    and the title bar's buttons as marks with a sentence on hover. `547a5f8`
48. The tooltip goes with the pointer, the way the client's own does: the
    linger ships at zero and stays a setting for whoever reads slowly.
    `06cd212`
49. Chrome waits for the hand to stop: tabs, close marks, chips and settings
    hints open after four tenths of a second held still, through the settle
    the bags already use. `cce5ebc`
50. Ad hoc bars: a bar of your own on a key, hidden until the key is pressed
    and hidden again after a press on one of its squares, holding only what
    you dragged onto it, up to six bars of sixteen per character. Shown,
    hidden, moved and put away from snippets so it works mid fight. `66ce6fc`

51. Ctrl-R, taken off the client and given a window: the last four seconds of
    frames as a strip, what the last second went on, and a log of the frames
    that went wrong with a measured reason on each. `b32bd7c`
52. A totem bar: the four slots in a fixed order with a hole where one is
    missing, built so a warrior's three stances are one more plan and one more
    reader rather than a second part. `245bbee`
60. `UI.Clip`, a round icon with a mask that fades it out at its own rim, and
    `scripts/bake-round.sh` to write the mask. `b220ad6`
61. The gear page as nineteen rows: a name in its quality colour, the level and
    the socket dots under it, the durability as the name's own underscore, and
    the figure behind all of it rather than boxed between the columns.
    `7b8373a`
63. A typeface of the addon's own: Noto Sans shipped in `src/Media/`, and the
    forty windows that were laid out against a narrower face. `89de0a6`
64. The loadouts come out, with the tab that hosted them. `3b31e1c`
65. One page, the tab strip gone, the skills folded into the stats column and
    the standings given a window on `/wk reputation`. `d667d93`
66. A name is read on a gradient rather than on the grass, out of `UI.Wash`.
    `2b55319`
67. The world darkens behind the sheet, on a frame that never takes the
    mouse. `ff5816d`
68. A gear change is watched: the row dips where a link moved and the two
    columns arrive from their own sides. `fdb49e3`
69. The socket carries its gem rather than a mark saying one is there.
    `7c6fb88`
70. The enchant on the line under the name, and the oil counting down on the
    weapon. `0e17925`
71. A trinket says when it is up, swept on the disc's own ring out of
    `UI.Arc`. `8b18daa`
72. The figure is yours to turn, and the pose is remembered. `fe3c4ce`

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
    `ImportModule` outside `Core/Core.lua` fail `check.sh`. The client half
    landed on 2026-09-04 and is `PROBED_ALLOWED` in `check.sh`. The count the
    item asked for first came back at 78, not 286: `_G` is read 365 times
    outside `src/Core/` and most of those are a frame fetched by name, which is
    the client's own naming scheme and not a probe. The gate names the shape
    instead, `type(_G.Foo)` or `type(_G[name])`, which is 78 sites in 39 files
    and holds exactly, in the path-keyed shape items 18 and 31 already use. It
    ships as an error with every file on it and a reason on every entry, so it
    is a migration state that drains: a probe moved into Core comes off the list
    in the same commit, a raise fails `scripts/ratchet.lua`, and a probe in a
    file that is not listed fails outright. Item 26 retires four of the entries
    on its own, the `SetOverrideBindingClick` pairs in `Character`, `Spellbook`
    and `Talents`, and `Feeds/Auction.lua` is two other addons' price calls and
    wants `ns.Questie`'s shape rather than Core's shims.

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

26. Taking a key off the client, written eight times.

    `SetOverrideBindingClick` onto a secure button, `ClearOverrideBindings`
    before it, a `Holds(key)` that reads the override layer back through
    `GetBindingAction` rather than trusting the set, and a record of the binding
    that got displaced. That is four calls with a subtle contract, and it is
    written out in `src/Targeting/Switch.lua:74`, `src/Charge/Icon.lua:275`,
    `src/Hover/Cast.lua:194`, `src/Dungeons/Key.lua:57`,
    `src/Marking/Keys.lua:74`, `src/Buttons/Bars.lua:371` and
    `src/Character/Blizzard.lua:167`. It was nine until item 64 deleted
    `src/Loadouts/Loadouts.lua`.
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
    it, retires seven copies and makes the registration impossible to forget.

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

Item 46 is a bug found in game on 2026-09-03, the first on this list that was
one, and it landed the same day and is above. The harness had passed it, and
the fix is the gate as much as the code: the stub now refuses a press on a
button the frame passes through, the way it refuses one never registered for.

Item 47 was asked for in game on 2026-09-03, a mode for a run of an old
dungeon rather than a fix, and it landed the same day and is above. Most of
it was already built: the colour floor, the kinds and the profession list in
`Comfort/Wanted.lua`, and the destroy in `Comfort/Leftovers.lua`. What was
missing was the price floor and the switch on the window.

Items 53 to 59 came out of an ask on 2026-09-04: write down what every class and
every build needs before any of them is written, so that a class file is one
sitting rather than a research project. Nine classes and twenty-seven builds.
Four files on disk cover four classes and twelve of the builds, and the five
missing files are one item each below.

Four things settle most of what follows and are worth stating once.

A class file is facts and a class file is one file. `src/Class/Class.lua:27`
says a class that registers nothing is a supported class and that adding one is
additive: one file, no edits anywhere else. That holds for eleven of the twelve
fields. `standing` is the exception and item 53 says what it costs.

The twelve fields and who reads each are listed at `src/Class/Warrior.lua:11`.
Eight of them are facts about the class and four are facts about the build.
`forms`, `charge`, `reactive`, `requires`, `swing`, `upkeep`, `suggested` and
`standing` go at the top of a class file; `cooldowns`, `rotation`, `debuffs` and
`loadout` go inside a spec, and a spec writes only what it disagrees with. The
caps are eight on the cooldown row, six on the rotation line and four on the
upkeep row, they are asserts inside `Cooldowns.All` and `Upkeep.Fixed`, and they
fire at PLAYER_LOGIN as a Lua error in somebody's game.

No item below carries a spell id, and no name below is final. Every id is baked
at implementation from Wowhead's TBC Classic database, rank 1, and read back by
name, which is the rule every entry in `src/Class/Warrior.lua` already keeps and
which one letter of Deep Wound already cost. A name that this client cannot
resolve is dropped rather than guessed, the way three of the shaman's four long
cooldowns are dropped on Era. An ability with no cooldown comes off the rotation
line before the list is written, because a clock on a spell that is always ready
is a square that never says anything.

No item below writes a bar plan. `src/Class/Shaman.lua:37` and
`src/Class/Priest.lua:17` both refuse a plan for a build nobody here has played,
on the argument that a plan taken off a talent calculator fills your bars with a
guess and takes a backup you then have to put back. That argument covers
twenty-four of the twenty-seven builds and it still holds. `loadout` is named in
every item below only to say it is not being written, and each stays unwritten
until somebody levels the character and presses the keys.

Signatures are the same refusal one level down. `src/Class/Spec.lua:54` wants a
talent with one rank at the foot of a tree, and takes the tree count where there
is none, which is what arms does and what costs arms nothing. A signature
guessed from memory that turns out to carry six ranks is a build that resolves
wrong for the character sitting on rank two. So every item below names the tree,
which always answers for anyone who has spent points, and leaves the signature
to be confirmed one rank at a time or left out.

53. The stance row, and the second reader.

    Item 52 built `Standing/` around a table of readers at
    `src/Standing/Standing.lua:56` and shipped one, `totem`. Its whole claim was
    that a warrior's three stances are one more plan and one more reader rather
    than a second part of the addon. This is the item that finds out.

    The reader is `stance`, and it is the one every shapeshifting class uses:
    warrior here, druid in item 55, and a rogue's Stealth and a priest's
    Shadowform if either is ever wanted. It walks `GetShapeshiftFormInfo` and
    matches each slot's spell name against the bar, rather than indexing into
    it. That is the correction this item makes to item 52's guess.
    `GetShapeshiftForm` answers one number, and the number is a position on a
    bar that holds only the forms you have learned, so a level 10 warrior stands
    in stance 1 and owns nothing else. A slot matched by name and found missing
    draws empty, which is exactly what an empty totem slot already draws.

    The reader contract is five values and a stance fills three: filled, art and
    the name. `src/Standing/Row.lua:261` already reads the two it will not get
    as `expires[index] or 0` and `span[index] or 0`, so nothing in `Row.lua`
    changes for a reader with no clock.

    `GetShapeshiftFormInfo` and `GetNumShapeshiftForms` are not in the harness.
    `GetShapeshiftForm` is, at `scripts/harness/client/05-quests.lua:691`, and
    the two new stubs belong beside it rather than in `03-player.lua`, which is
    where the totem stub is.

    The plan goes in `src/Class/Warrior.lua` beside `forms`: three slots in the
    order that file already writes them in, `kind = "stance"`, `word = "stances"`
    and `one = "stance"`. The colours are the three the addon already uses for
    the three stances if there are any, and three hues far enough apart to be
    told apart in one pixel of hairline if there are not.

    One thing this item finds that item 52 did not.
    `src/Standing/Feature.lua:105` writes its slash words out, `totems` and
    `stances`, and `ns.Register` runs at file load, before the client will say
    what class this is. So the words cannot be built off the plan and every
    class's word has to be in that table: `forms` for a druid, `aspects` for a
    hunter, `poisons` for a rogue, `auras` for a paladin, `demon` for a warlock.
    That table is the one file outside `Class/` a new class edits, which is a
    hole in the promise at `src/Class/Class.lua:27`, and the fix is a gate
    rather than a redesign. Hold every `word` and `one` a plan registers against
    the table, and fail on a word in the table that no plan claims.

54. What a fifth class file costs the gate, before the fifth one lands.

    `scripts/check.sh:1354` reads the class tokens off `Class/*.lua` and the
    spec keys off each file, and runs the harness once per shape. Thirteen runs
    today, twelve builds and a hunter. Nine classes at three builds each is
    twenty-eight, and the harness is the slowest thing in `check.sh`. Measure
    one run before item 56 lands and again after, because a gate that takes four
    minutes is a gate somebody starts reaching around.

    HUNTER is written out at `scripts/check.sh:1377` and that run is the whole
    proof that the class-agnostic parts stand up with nothing registered. Item
    56 writes a hunter file and takes the proof away silently: the loop keeps
    passing, and what it stops covering is not in its output. Replace it in the
    same commit with a token no class file can ever claim, and say in the
    comment above the loop that the token is deliberately not a class, so that
    the next class file does not quietly eat it again.

55. Druid: forms, and the first plan a spec overrides.

    Six of the eight class-wide fields, and it is the class that exercises the
    registry hardest.

    `forms` is written in learn order, Bear, Aquatic, Cat, Travel, because the
    `stance:` macro conditional counts positions on the same bar the reader
    walks and a druid learns those four in that order. The prefix holds while
    levelling: a druid who knows the first two has them at 1 and 2. Moonkin and
    Tree come after Travel and are talents, so they go at the end. Confirm the
    order in game by reading `GetShapeshiftFormInfo` back at 70 and at 25, and
    if it does not hold, drop `forms` entirely rather than generating a macro
    against a moving number. Nothing but the loadouts page reads it on this
    class, and `src/Core/Stance.lua:20` already supports a weapon set with no
    stance on it.

    `standing` is the second user of the `stance` reader and the first field in
    the addon that a spec overrides for a reason other than a number. All three
    builds get bear, aquatic, cat and travel. Balance writes the field again with
    Moonkin Form on the end and restoration with Tree of Life, because a square
    for a form the character cannot take is a square that stays dark for the life
    of the character.

    No `charge`, no `swing`, no `requires`. `reactive` is worth a look and is not
    on this item: nothing a druid owns opens on a dodge or a parry the way
    Overpower and Revenge do, and Omen of Clarity lands as a buff rather than
    down the combat log, which is a second kind of `on` and belongs with the
    warlock's Nightfall in item 59.

    `upkeep` gets one entry, the mark, and any of Mark of the Wild and Gift of
    the Wild clears it, on the shaman's shield argument: which one you are
    running is a group question and standing there with neither is never right.

    `suggested` is every debuff a druid lands: Moonfire, Insect Swarm, Faerie
    Fire and its feral form, Entangling Roots, Rake, Rip, Pounce, Lacerate,
    Mangle, Demoralizing Roar, Hibernate, Cyclone.

    Balance, tree 1. Cooldowns are Innervate, Force of Nature, Barkskin and
    Rebirth. The rotation line is thin and honest: Hurricane and Force of
    Nature are the two with real clocks, Moonfire and Starfire have none.
    Debuffs are Moonfire, Insect Swarm and Faerie Fire.

    Feral, tree 2, and the fullest of the three. Cooldowns are Innervate,
    Barkskin, Rebirth and Enrage. Rotation is Mangle, Feral Charge, Swipe and
    Faerie Fire (Feral). Debuffs are Rake, Rip, Lacerate, Mangle, Faerie Fire
    and Demoralizing Roar, which is six and at the cap.

    Restoration, tree 3. Cooldowns are Innervate, Nature's Swiftness, Rebirth
    and Tranquility. Rotation is Swiftmend and Nature's Swiftness. Debuffs are
    Faerie Fire and Entangling Roots, which is the shortest row in the addon and
    correct: a resto druid is not putting anything on a mob.

56. Hunter: aspects, the pet, and the second class to fill `reactive`.

    This is the file that takes the no-file proof away, so item 54 lands first
    or in the same commit.

    Two new readers. `buff` matches a list of spell names against
    `UnitAura("player")` and reports the first that is up, with the client's own
    icon and expiry, which is what an aspect slot needs and what item 57's aura,
    seal and blessing slots need after it. `pet` answers `UnitExists("pet")`
    with the pet's name and portrait and no clock, which item 59 uses for the
    demon. Neither call is stubbed for the pet half: `UnitAura` is at
    `scripts/harness/client/03-player.lua:205`, and `UnitCreatureFamily`,
    `GetPetHappiness` and a pet unit in the roster are not there at all.

    `standing` is two slots, aspect and pet, `word = "aspects"`. The aspect slot
    carries every aspect this client has, Hawk, Monkey, Cheetah, Pack, Wild,
    Beast and Viper, and the reader lights whichever is up: the question a
    hunter asks a row is which one, not whether. The pet slot is dark when the
    pet is dead or dismissed, which is the one fact on the row worth a glance
    mid-pull.

    `reactive` is the finding on this item. Mongoose Bite opens when you dodge
    and Counterattack opens when you parry, which is Overpower and Revenge with
    the names swapped, and `src/Buttons/Reaction.lua` already owns the combat
    log parse and knows no ability. Confirm the window against the five seconds
    the warrior file argues for at length; the two abilities may not share it.

    No `charge`, no `forms`, no `swing`. `requires` gets nothing: every candidate
    on a hunter is a range or an aim rule the client already answers, and a
    square greyed on a rule the addon guessed at is worse than one that says
    nothing.

    `upkeep` gets nothing either. The aspect is on the row above and a bare
    ranged weapon is not a thing this client tracks.

    `suggested` is Hunter's Mark, Serpent Sting, Viper Sting, Scorpid Sting,
    Wyvern Sting, Concussive Shot, Wing Clip, Scatter Shot, Silencing Shot,
    Intimidation, Freezing Trap and Explosive Trap.

    Beast mastery, tree 1. Cooldowns are Bestial Wrath, Intimidation, Rapid Fire
    and Misdirection. Rotation is Arcane Shot, Multi-Shot and Kill Command if
    this client has it. Debuffs are Hunter's Mark, Serpent Sting and the
    Intimidation stun.

    Marksmanship, tree 2. Cooldowns are Rapid Fire, Readiness, Misdirection and
    Silencing Shot. Rotation is Aimed Shot, Arcane Shot, Multi-Shot and
    Silencing Shot. Debuffs are Hunter's Mark, Serpent Sting and Scatter Shot.

    Survival, tree 3. Cooldowns are Rapid Fire, Misdirection, Deterrence and
    Readiness if the talent is not marksmanship-only on this client. Rotation is
    Mongoose Bite, Counterattack, Wyvern Sting, Arcane Shot and Explosive Trap.
    Debuffs are Hunter's Mark, Serpent Sting, Wyvern Sting and Wing Clip.

57. Paladin: the aura, the seal and the blessing, and the second user of
    `requires`.

    `standing` is three slots and `word = "auras"`, on the `buff` reader item 56
    writes. The aura slot carries every aura, the seal slot every seal, and the
    blessing slot every blessing that lands on you. Three squares that answer
    the only three questions a paladin has about themselves, and the seal is the
    one with a clock on it because it runs for thirty seconds and lapses in the
    middle of a pull without saying so.

    `upkeep` gets the seal as well, and that is not a duplicate. The row is a
    square and the upkeep entry is the nag, which is the same split Battle Shout
    and the stance row already sit on either side of for a warrior. Any seal
    clears it.

    `requires` is the finding. Hammer of Wrath is castable below twenty percent
    and nothing else moves that number, which is Execute's rule word for word
    and makes this the second entry in a field `src/Buttons/Requires.lua` built
    for one. Nothing else on a paladin meets the bar.

    No `charge`, no `forms`, no `swing`, no `reactive`. Reckoning and Redoubt are
    procs that land as buffs rather than windows opened by a dodge, so they go
    with Nightfall in item 59 or nowhere.

    `suggested` is Judgement of Light, Judgement of Wisdom, Judgement of the
    Crusader, Judgement of Justice, Hammer of Justice, Repentance, Avenger's
    Shield, Holy Vengeance and its Horde spelling, Turn Evil and Exorcism if
    either lands an aura.

    Holy, tree 1. Cooldowns are Avenging Wrath, Divine Favor, Divine
    Illumination, Lay on Hands and Divine Shield. Rotation is Holy Shock and
    Hammer of Justice. Debuffs are the judgement you are running and Hammer of
    Justice.

    Protection, tree 2. Cooldowns are Avenging Wrath, Divine Shield, Divine
    Protection and Lay on Hands. Rotation is Avenger's Shield, Holy Shield,
    Consecration, Judgement and Hammer of Justice. Debuffs are Judgement of
    Wisdom, Judgement of Light, Hammer of Justice and the Avenger's Shield
    daze.

    Retribution, tree 3. Cooldowns are Avenging Wrath, Divine Shield, Lay on
    Hands and Repentance. Rotation is Crusader Strike, Judgement, Hammer of
    Wrath, Exorcism and Hammer of Justice. Debuffs are the judgement, Hammer of
    Justice and Repentance.

58. Rogue: the two poisons, and a rotation line that is nearly empty.

    `standing` is two slots, main hand and off hand, `word = "poisons"`, on a
    fourth reader called `enchant`. It reads `GetWeaponEnchantInfo`, which
    `src/Buffs/Upkeep.lua:439` already documents across the three shapes that
    call has had, and `src/Buffs/Upkeep.lua:479` already picks the stride at
    runtime. Reuse that reading rather than writing a second one.

    The limit is worth writing into the reader. `GetWeaponEnchantInfo` says
    whether a hand is enchanted, for how long, and how many charges are left. It
    does not say which poison, so the square cannot draw a poison's icon and
    must draw the weapon's own, off `GetInventoryItemTexture`. A rogue reads the
    charges anyway, which is the number the client's own buff frame buries.

    `reactive` gets one entry, Riposte, which opens when you parry and is
    Revenge with a different name. Third class into that field, and the second
    that wants the parry trigger `src/Class/Warrior.lua` already spells
    `defended`.

    No `charge`, no `forms`, no `swing`, no `requires`. Stealth is a shapeshift
    form and is deliberately not on the row, on `src/Class/Shaman.lua:12`'s Ghost
    Wolf argument: the screen already says you are stealthed and a square
    repeating it is furniture.

    `upkeep` gets nothing. A rogue with a bare weapon is already the first entry
    on the shipped buff nag, which is the same call and the same slot.

    `suggested` is Rupture, Garrote, Expose Armor, Hemorrhage, Deadly Poison,
    Crippling Poison, Wound Poison, Mind-numbing Poison, Cheap Shot, Kidney
    Shot, Gouge, Blind and Sap.

    The honest finding is that the rotation line does not fit this class. Almost
    nothing a rogue presses has a cooldown, and the number that decides every
    press is the combo point count, which nothing in this addon draws. Write the
    three lists short rather than padding them, and if a rogue is played here the
    thing worth building is a combo point row, which is a new part and a new
    item rather than a field on this file.

    Assassination, tree 1. Cooldowns are Cold Blood, Vanish, Evasion and Blind.
    Rotation is Mutilate and Kidney Shot. Debuffs are Rupture, Garrote, Deadly
    Poison and Kidney Shot.

    Combat, tree 2. Cooldowns are Adrenaline Rush, Blade Flurry, Evasion and
    Vanish. Rotation is Riposte, Kick and Gouge. Debuffs are Rupture, Expose
    Armor, Crippling Poison and Kidney Shot.

    Subtlety, tree 3. Cooldowns are Preparation, Shadowstep, Vanish and Evasion.
    Rotation is Shadowstep and Premeditation. Debuffs are Rupture, Hemorrhage,
    Cheap Shot and Kidney Shot.

59. Warlock: the demon, and the two things `reactive` and `requires` cannot say
    yet.

    `standing` is one slot, the demon, `word = "demon"`, on the `pet` reader item
    56 writes. One square, and it is the right size: a warlock has one demon out
    and the whole question is which and whether.

    Soul shards are deliberately not on the row. A shard count is a number in a
    bag rather than a slot with something standing in it, and the reader contract
    at `src/Standing/Standing.lua:41` has nowhere to put it. If the count is
    wanted it goes on the upkeep row as a floor, or nowhere.

    `upkeep` gets the armor, and it is the mage's entry with different names:
    Fel Armor, Demon Armor and Demon Skin, matched the way
    `src/Class/Mage.lua:142` matches its four. Standing there with none is never
    right and the client says nothing about it.

    Two findings, and both are extensions rather than entries.

    `reactive` cannot say Nightfall. The field watches the combat log for a
    dodge or a block, and Nightfall arrives as Shadow Trance, a buff on you with
    a ten second clock. That is a second kind of `on`, it is the same shape as
    the druid's Omen of Clarity and the paladin's Reckoning, and it wants
    `on = "buff"` with a spell id, read off `UnitAura("player")` by the reader
    item 56 writes. Three classes want it. Write it here or write it as its own
    item first.

    `requires` cannot say Conflagrate. The field compares the target's health to
    a number, and Conflagrate needs your Immolate on the target, which is an
    aura and not a percentage. `src/Buttons/Requires.lua` owns what a condition
    means and knows none of the abilities, so a second condition kind belongs
    there: `needs = <spell>` on the target, matched by name, mine only. Shadowburn
    and Death Coil need nothing and stay off.

    No `charge`, no `forms`, no `swing`.

    `suggested` is Corruption, Immolate, Curse of Agony, Curse of the Elements,
    Curse of Weakness, Curse of Tongues, Curse of Doom, Siphon Life, Unstable
    Affliction, Seed of Corruption, Fear, Howl of Terror, Banish and Death Coil.

    Affliction, tree 1. Cooldowns are Curse of Doom, Death Coil, Howl of Terror
    and Amplify Curse. Rotation is Death Coil and Howl of Terror, which is two,
    because an affliction warlock's whole rotation is dots with no clocks on
    them. Debuffs are Corruption, Curse of Agony, Siphon Life, Immolate and
    Unstable Affliction.

    Demonology, tree 2. Cooldowns are Fel Domination, Soulshatter, Death Coil
    and Howl of Terror. Rotation is Shadowburn if the character has it, Death
    Coil and Howl of Terror. Debuffs are Corruption, Immolate, Curse of Agony
    and Curse of the Elements.

    Destruction, tree 3. Cooldowns are Soulshatter, Death Coil, Howl of Terror
    and Shadowfury. Rotation is Conflagrate, Shadowburn, Shadowfury and Death
    Coil. Debuffs are Immolate, Corruption, Curse of the Elements and the
    Shadowfury stun.

Items 60 to 62 came out of a redesign asked for on 2026-09-05, against two
retail character sheets and one armory page. Items 60 and 61 landed the same
day and are above. Item 62, a loadout that carried a whole set of gear rather
than two weapons, is dropped rather than finished. Item 64 deletes the part it
was an extension of. Its text is in this file at `17b6427`.

73. A feed folds a repeat into the row it is already on.

    `src/UI/Feed.lua` is the only file that can do this, because the ring is
    what has to stay honest: `written` at `Feed:Push` `:859`, the offset it
    nudges when you are reading history, and the `matching` count that
    `Feed:Entry` `:823` decrements when an entry falls out of the ring.

    `Feed:Fold(match)` takes a function and a filled slot. It walks back from
    the newest through a bounded lookback, hands each held entry and the new one
    to `match`, and on the first yes it lets the caller add to that entry in
    place and marks the feed. Nothing is pushed, `written` does not move, the
    offset does not move, and `matching` is already right because the entry it
    folded into was already counted.

    Bounded, and the bound is this file's. A walk of the whole ring per arrival
    is four hundred comparisons on the path a pull drives, which is the cost
    `Feed:Window` `:782` exists to avoid. Sixteen entries back is a corpse and
    the two before it, which is the whole of what a fold is for.

    In place and not to the top. An entry that folded and then jumped to the
    newest row would reorder the column under the eyes of somebody reading it,
    which is the thing `Feed:Push`'s offset arithmetic is written to prevent.
    The bandage row stays where it is and its number climbs.

    The slot `Feed:Entry` handed out is left unpushed, which that function's own
    header already says is safe: the next caller wipes it.

    `./scripts/check.sh` green before committing.

74. The loot feed folds on the item, and the tooltip says what the row stopped
    saying.

    `AddItem` at `src/Feeds/Loot.lua:333` asks `Feed:Fold` first and pushes only
    if nothing took it. Two entries are the same drop when the link is the same
    and the older one arrived inside the window; the link is already on the
    entry and `Stream.Clock` already reads `entry.at`.

    Sixty seconds, and it is a number rather than the whole ring for the reason
    item 73 is bounded. Bandages come off a craft one a second and a vendor run
    an hour ago is a different afternoon. The window is not a setting. A slider
    on it would be the third control over what the column shows and the header
    of `Passes` at `:150` is an argument against the second.

    `entry.count` becomes the running total and `entry.amount` at `:347` is
    written from it, so the row reads `x12` where it read `x1` twelve times.
    `entry.at` moves to the newest of them, because a row that folded is a row
    about the last one you picked up.

    The tooltip at `Fill` `:218` keeps what the row can no longer hold. The
    `Stack` line at `:226` becomes the total and how many pickups made it, and
    the `Looted` line says the last one. A row reading `x12` with a tooltip
    saying `12` and nothing else has thrown the fold away.

    `./scripts/check.sh` green before committing.

75. Coin folds too.

    `AddMoney` at `src/Feeds/Loot.lua:368` folds on being coin at all rather
    than on a link, inside the same window, and the row's name is rebuilt from
    the running total through `ns.Coined` rather than from the client's phrase.

    That loses the client's own sentence, which is what the comment at `:375`
    picked on purpose, and it is the right trade only because the total is the
    thing being kept. A folded coin row saying "12 Silver, 39 Copper" when three
    corpses paid is a lie in the one column that is arithmetic.

    The purse along the bottom is unaffected. It reads `GetMoney` and a ledger,
    never the rows.

    `./scripts/check.sh` green before committing.

76. The feed's rows are read on a gradient, and the slider behind them goes.

    `UI.Wash(parent, color, edge, layer)` at `src/UI/Draw.lua:147` under each
    row of `src/UI/Feed.lua`, sized to the row and running from the stripe out,
    so a drop is read against something the addon painted rather than against
    grass. The edge is `"LEFT"`, which is that function's own default and is the
    way a feed row reads.

    A client with no gradient gets a flat wash at half strength, which that
    function already arranges and this one does not have to think about. It is
    the worse picture and it is legible, and it is the only state where the
    outline coming off in item 77 is a real loss.

    `lootFeedAlpha`, which ships at 15 at `src/Feeds/Loot.lua:293`, becomes the
    wash's strength rather than a panel's alpha. It is the same slider on the
    same page saying the same thing, and the comment above that default already
    describes the wash without knowing the word: almost nothing behind it,
    because a panel was covering scenery to hold up text that did not need
    holding up. A gradient is what holds up text without a panel.

    Every stream gets it, not the loot one. The combat feed is over the world by
    the same argument and `Feeds/Combat.lua` never asked for a different answer.

    Watch the ends. A wash as wide as the row is a black bar with a fade on one
    side, which is a panel again. It ends where the text ends, which the row
    already measures per resize in `Resize` and hands out as `geom`.

    `./scripts/check.sh` green before committing.

77. Every string in a feed comes off the rim and onto the shadow.

    `UI.OUTLINE` at ten sites in `src/UI/Feed.lua` and three in
    `Instance:BuildStatus` at `src/Feeds/Stream.lua:264` becomes `UI.SHADOW`,
    which is what the character sheet draws in and what item 66 argues for: a
    rim on a stroke is a patch for having no ground, and after item 76 there is
    ground.

    `UI.OutlineFloor` at `src/UI/Text.lua:269` stops applying to a feed row,
    which is the point. The floor is why `FEED_ICON_LOW` is 16 at `:97`, and a
    row that no longer needs an outlined glyph can go smaller than a row that
    does. Do not lower it in this commit. Measure it first with the wash
    actually under the text, and if it comes down, item 23's ratchet is where
    the new number is written.

    This is one commit with item 76 or it is a regression. Text with no rim and
    no wash under it is the worst of the three states and it is what the
    intermediate commit ships.

    `./scripts/check.sh` green before committing.

78. A badge is a widget, not a thing the paperdoll has.

    The four readings at the head of the stats column, `LABELS` at
    `src/Character/Paperdoll.lua:544` with `BADGE` and `BADGERIM` at `:197`, and
    the three numbers along the bottom of the loot feed, built in
    `Instance:BuildStatus` at `src/Feeds/Stream.lua:264` off `Purse.Line` at
    `src/Feeds/Purse.lua:322`, are the same picture: a number, a word under it,
    a tone the number earned, and a hover that explains it.

    `UI.Badge` in `src/UI/Widgets.lua` takes a value, a label, a tone and a
    tooltip, and both call it. The sheet's four keep their fraction, which the
    durability badge draws as a bar; the feed's three have no fraction and pass
    none.

    This lands with item 65 and not before it. That item is already moving the
    four badges up into the room the tab strip leaves, which means it is already
    rewriting their placement, and doing the extraction in a separate commit is
    placing them twice.

    The tones stay where they are. `WearTone` is a fact about durability and
    `Tone` in `Purse.lua` is a fact about whether your afternoon paid, and
    neither belongs in a widget that draws a number.

    `./scripts/check.sh` green before committing.

79. Quality is one picture in both windows.

    The sheet draws an item's grade as a band round the icon at `REST` 0.55,
    `src/Character/Paperdoll.lua:126`, and the hover takes it to full. The feed
    draws the same grade as a stripe down the row and a ring round the icon, at
    full strength always, `src/UI/Feed.lua:236` and `:255`. Two answers to one
    question, and after item 76 they are on two surfaces that finally match.

    The feed takes the sheet's: the stripe and the ring rest at `REST` and the
    hover takes the row to full, which the row already has a hook for at
    `Feed:Enter`. Nineteen quality colours at full strength is a page of
    coloured lights, and thirteen rows of it is a column of them.

    The quest ring is the exception and stays at full. It is not a quality, it
    is the one thing on the row that is telling you to look, and item 86 gives
    it company rather than taking it away.

    `./scripts/check.sh` green before committing.

80. The palette takes the colours twelve files still write by hand.

    Forty-seven fractional colour literals outside `src/UI/Theme.lua` and
    `src/Unit/Color.lua`, in twelve files. `src/UI/Ability.lua` has twelve,
    `src/Feeds/Combat.lua` seven, `src/Swing/Gauges.lua` six,
    `src/Meter/Window.lua`, `src/Class/Shaman.lua` and `src/Buttons/Look.lua`
    four each, `src/CombatText/Numbers.lua` three, `src/Character/Paperdoll.lua`
    and `src/Buffs/Nag.lua` two, and one each in `src/Perf/Hud.lua`,
    `src/Mail/Window.lua` and `src/Feeds/Loot.lua`.

    They are not all the same kind of thing and the commit has to sort them.
    `QUEST` at `src/Feeds/Loot.lua:62` is a palette entry with one reader and
    item 86 makes it two, so it goes to `UI.Color`. `REST` and `RIM` at
    `src/Character/Paperdoll.lua:126` are a strength and a distance, so they go
    to `UI.Metric` where item 79 needs them. `Feeds/Combat.lua`'s seven grade a
    kind of event, which is a palette that file owns the way `Unit/Color.lua`
    owns power colours, so it becomes a named table with a header rather than
    seven literals at seven sites. A class colour is the client's and stays.

    The numbers the sheet invented and the feed will want go with them:
    `DENSE`, `TIGHT` and `VALUE` at `src/Character/Readout.lua:79`, `:72` and
    `:64` are the addon's dense-list metrics and there is now a second dense
    list.

    Item 81 is the gate and it is the next commit rather than this one. Land the
    move first, count what is left, then write the rule against the number that
    is actually there.

    `./scripts/check.sh` green before committing.

81. A colour written by hand is an error.

    `scripts/check.sh` refuses a fractional colour triple outside
    `src/UI/Theme.lua` and `src/Unit/Color.lua`: a table constructor of three or
    four numbers with a fraction in it, and the same shape passed to
    `SetColorTexture`, `SetTextColor` or `SetVertexColor`.

    A fraction, not any triple. `SetVertexColor(1, 1, 1)` is a reset and
    `SetColorTexture(0, 0, 0, 0.55)` is a shadow, and a rule that caught those
    would be a rule people learn to work around.

    Whatever item 80 leaves behind is allow-listed by file with a one-line
    reason each, in the shape the eight rules above it already use, and the
    length of that list is a ceiling in `scripts/ratchet.lua`. A file that
    clears its last literal comes off the list in the same commit that clears
    it.

    Error, not warning. The rule is worth nothing as a warning: the whole
    argument for it is that a colour typed at a call site is invisible until two
    windows are open side by side, which is the moment this addon has just spent
    ten items getting to.

    `./scripts/check.sh` green before committing.

82. `/wk style`, the page that draws the palette.

    `src/Settings/Style.lua`, registered by `src/Settings/Feature.lua` the way
    every other word is, built on first open. Not in `src/UI/`: no file in that
    folder registers a feature and that layering is worth more than the
    convenience.

    It draws itself out of the tables rather than describing them. Every entry
    of `UI.Color` as a swatch with its key under it, every `UI.Metric` as a rule
    of that many pixels with its number, the three font sizes in the shipped
    face, `UI.Quality` as eight names in eight colours, a wash, a badge, a chip,
    a feed row and a readout row side by side.

    Side by side is the whole feature. Nothing on this page is information you
    could not get by reading `src/UI/Theme.lua`; what you cannot get by reading
    it is whether the feed row and the sheet row look like they came from the
    same addon, which is a thing eyes answer in a second and a file never
    answers at all.

    It is after items 76 to 79 because a page drawn now would be a page missing
    the wash, the badge and the rest brightness, which are the three things that
    made the two rows disagree.

    A page with no settings on it. It reads the tables and shows them, and the
    day a colour on it is editable is the day `UI.Theme`'s header stops being
    true.

    `./scripts/check.sh` green before committing.

83. One question: why does this item matter to you.

    `ns.Need(link)` in `src/Core/`, answering a reason, a short phrase and a
    colour, or nothing at all. Four sources, each of which already exists and
    none of which knows about the others.

      quest      an objective in your log this item feeds, and how far along it
                 is. Item 85 is the reading.
      skill      a reagent a profession of yours uses, and whether the recipes
                 using it can still gain you a point. Item 84 is the reading.
      trash      something `Comfort/Wanted.lua` would have left on the corpse.
                 Item 88.
      nothing    which is most items, and is answered fast.

    In Core because three parts outside `src/Feeds/` are going to want it and a
    part may not name a file outside its own tree. The bag window is the first
    of them and it is not on this list.

    One answer per item, in that order, because a wolf liver that is also a
    leatherworking reagent is a wolf liver you need eight of. Ordered here and
    not left to the caller: two callers ranking the same item differently is the
    thing this function exists to stop.

    Cached per item id and thrown away on the events that change the answer,
    which are the quest log's, `SKILL_LINES_CHANGED` and the trade window's.
    `AddItem` at `src/Feeds/Loot.lua:333` calls this on a path a pull drives,
    and a walk of the quest log per drop is what that path cannot afford.

    `./scripts/check.sh` green before committing.

84. A reagent says whether it is still worth a point.

    `Walk` at `src/Comfort/Reagents.lua:110` reads the difficulty of every
    recipe and throws it away. `ns.TradeSkillRow` at `src/Core/Core.lua:1997`
    returns it as `kind`, which is the client's `optimal`, `medium`, `easy` or
    `trivial`, and the walk uses it only to tell a header from a row.

    Keep the best of it. `ns.dbc.lootReagents` maps an item id to a profession
    name at `List` `:83`; it becomes the profession and the best difficulty any
    recipe wanting that reagent has, so `Reagents.Has` at `:187` still answers
    what it answers and a new reading says whether the point is still there.

    Trivial is the whole value of the change. Six stacks of linen is a reagent
    tailoring uses and has not given you a point for in twelve levels, and a
    feed that says "tailoring" about it is a feed telling you to keep something
    you should be selling.

    The saved shape changes, so the old table has to be readable or dropped on
    sight. Dropped: it is rebuilt the next time the trade window opens, which
    is the same recovery the throttle at `Due` `:139` already assumes.

    `./scripts/check.sh` green before committing.

85. An objective is a name and two numbers.

    `Client.Objectives` at `src/Quests/Client.lua:191` hands back the client's
    own sentence, its kind and whether it is finished. "Boar Hide: 3/8" is one
    string, and the three and the eight are inside it.

    Read them with the client's own format strings, the way `Core/Loot.lua`
    reads a loot line and for the same reason: those are what the client built
    the sentence from, turning one into a pattern reads a German client by
    German rules, and typing a colon and a slash here is an addon that captures
    nothing outside English. There are three and the kind says which:
    `QUEST_ITEMS_NEEDED` for an `item`, `QUEST_MONSTERS_KILLED` for a `monster`
    and `QUEST_OBJECTS_FOUND` for an `object`. Only the first matters to a loot
    row and all three are cheap.

    Questie on disk carries the one thing that will otherwise cost an evening.
    `Modules/Quest/QuestieQuest.lua:1191` and `:1204` match the pattern and then
    check whether the name came back as a number, with the comment "SOME
    objectives are reversed in TBC": the two captures arrive the other way round
    on some quests on this client. Handle it the way that file does rather than
    finding it in the field.

    It goes beside the existing call as a second reading rather than replacing
    it, because the tracker and the quest window both draw the sentence whole
    and neither wants it taken apart.

    Matching an objective to an item is by name, which is what the client gives.
    That is right for the great majority and wrong for the handful whose
    objective is worded differently from the item. Questie knows the real
    mapping and `src/Quests/Drops.lua` already reads it; this item does not, and
    the reason is that a feed which says nothing about one item in fifty is
    worth shipping and a Questie dependency on the loot path is not.

    `./scripts/check.sh` green before committing.

86. The loot row says why it matters.

    The dim middle column already exists. `row.note` is built on every feed row
    at `src/UI/Feed.lua:272` and the loot stream asks for zero width of it
    through `opts.note` at `:354`, so this is a width and a string rather than a
    region.

    The string is item 83's phrase: `4/8` for a quest objective, the profession
    for a reagent that can still gain you a point, nothing for an item with no
    reason. It is short by design, because the column it goes in takes its width
    off the name.

    The ring round the icon takes the reason's colour and stops being the quest
    ring. It is already the right shape, already shown per row, and orange is
    already the reason colour; a second ring for a second reason would be a row
    with two rings on it.

    The tooltip says it as a sentence, in `Fill` at `src/Feeds/Loot.lua:218`,
    above the `Looted` line. "Wolf Liver, 4 of 8" is the sentence, and the row
    is the glance.

    Folding and this have to agree. A row that folded twelve bandages and shows
    `4/8` is showing a count that moved while it folded, so the note is read on
    the fold as well as on the arrival, which item 73 makes cheap by handing the
    caller the entry it folded into.

    `./scripts/check.sh` green before committing.

87. A chip that leaves only what you needed.

    A seventh chip in `Chips` at `src/Feeds/Loot.lua:162`, past the break with
    the quest and coin chips, on when item 83 gave the row a reason.

    It is an override the way the quest chip is, not a quality. On, a row with a
    reason is drawn whatever its quality chip says, which is the combination
    that matters: greys and whites off, the chip on, and the column is the six
    things you picked up this hour that you were actually looking for.

    The quest chip is now a special case of it and stays anyway. Somebody who
    wants quest items and not reagents has to be able to say so, and the two
    chips together are what says it.

    `Passes` at `:150` gains one branch, `Feature.lua`'s panel page gains a
    check box at `:556` and a slash word at `LootWords` `:214`, because a chip
    without both is a switch that disagrees with the page describing it.

    `./scripts/check.sh` green before committing.

88. What the addon left on the corpse, said out loud.

    `Wanted.Take(slot)` at `src/Comfort/Wanted.lua:103` is the question the
    auto-loot asks per slot, and its four answers are a quality floor, a kind
    your professions use, a vendor price and a quest flag. The loot feed asks
    the overlapping question and neither has ever heard of the other.

    Item 83's `trash` reason is this call, so a drop the filter would have
    refused is marked in the column as what it is. And the feed becomes the only
    place the filter can be checked: `Comfort/Loot.lua` empties a corpse before
    a window is drawn, so what it decided is invisible by design, and a rule set
    too tight is a rule set nobody finds out about.

    The mark is quiet. Trash is the reason nobody is looking for, it is the
    commonest answer on the list, and a column of loud grey rows is the feed
    back where it started.

    `./scripts/check.sh` green before committing.

Items 89 to 99 came out of an ask on 2026-09-06. The quest log is the addon's
best window and it no longer looks like the rest of the addon, Questie's tracker
sitting beside it looks like neither, and the questing itself is three questions
nothing answers: what is here, what am I always watching, and what would I walk
past without noticing.

**Questie is not reskinned and will not be.** `src/Quests/Where.lua` and
`src/Quests/Drops.lua` are the pattern and it is the right one: read the
database, draw in our own style, degrade to nil when it is not there. Its
tracker is two thousand lines with its own line pool, its own options tree and
its own layout pass, and a hook that repainted it would break on the next
release and would leave this addon owning frames it did not build. Its tracker
goes off through its own call, ours goes on, and its world and minimap icons
stay exactly where they are. Those icons are why Questie is installed.

The reading behind these items was of the live install, Questie 11.37.1 at
`_anniversary_/Interface/AddOns/Questie`, not of the v6 copy in `~/Downloads`.
Three things came out of it that were not known when `Where.lua` was written. It
now ships a declared-stable API in `Public/`, which v6 had nothing of.
`QuestieTracker:Disable` at `Modules/Tracker/QuestieTracker.lua:482` is the call
its own options checkbox makes. And `AvailableQuests.__availableQuestsByNpc`
knows every quest you could pick up and have not, keyed by the person holding
it.

89. The one part of Questie that promises not to move.

    `Public/` is new in v11 and its README says what everything else in that
    addon does not: what is in this folder is stable and safe to use. Four
    things are: `Questie.API.isReady`, `Questie.API.RegisterOnReady(callback)`,
    `Questie.API.RegisterForQuestUpdates(callback)` and
    `Questie.API.GetQuestObjectiveIconForUnit(guid)`.

    `ns.Questie` at `src/Core/Core.lua:1048` cannot reach any of it. It asks
    `QuestieLoader` for a module by name, and `Questie.API` is a plain table on
    a global. So this adds `ns.QuestieAPI(name)` beside it, the same shape and
    the same silence: the global, the field, the type check, nil for all three
    failures.

    The quest update callback is what it buys. `src/Quests/Window.lua` redraws
    off the client's four events, and the client's are the wrong grain: it fires
    `QUEST_LOG_UPDATE` several times a second while you are killing things, and
    `Where.lua:243` carries what that already cost once. Questie's fires on
    accept, update, turn-in and abandon, with the quest id and the objective
    index, out of `Questie.API.Enums.QuestUpdateTriggerReason`.

    The client's events stay. Questie may not be installed, and a quest log that
    only redraws when another addon says so is a quest log that is blank without
    it. This is a second source that makes the redraws sharper, not a
    replacement for the first.

    `RegisterOnReady` replaces the probe-every-time rule for the one question it
    answers. Nothing else changes: the header of `ns.Questie` argues that a
    cached answer taken before the database compiles is wrong for the session,
    and this callback is the database saying it has finished compiling.

    `./scripts/check.sh` green before committing.

90. Questie's tracker goes off, by its own hand.

    `QuestieTracker:Disable()` at `Modules/Tracker/QuestieTracker.lua:482`, with
    `Enable()` at `:469` putting it back. Both are what the "Enable Tracker"
    checkbox in Questie's own options calls, at
    `Modules/Options/TrackerTab/QuestieOptionsTracker.lua:101`.

    Its own call and nothing else. No `Hide` on its frame, no `SetParent` into
    the attic, no `EachTexture`. `src/Core/Attic.lua` exists for Blizzard's
    frames, which nobody else is going to re-show behind our back, and Questie
    re-shows its tracker on a dozen of its own events. A frame we hid would come
    back on the first quest accepted and we would be hiding it forever.

    It writes another addon's saved setting, which is a thing this addon has
    never done, and that is the reason it needs a switch of its own and a line
    in `/wk status`. `Questie.db.profile.trackerEnabled` is the player's
    setting; a feature that turned it off and did not say so is a feature that
    looks like Questie broke.

    Off the switch, `Enable()` is called and the setting goes back to true, once
    and not on every login. It follows the same rule
    `src/Quests/Blizzard.lua`'s attic does: the switch is what owns the state,
    and the file's job is that the two ends agree.

    In combat neither call is made. Questie's own options disable that checkbox
    on `InCombatLockdown` and the reason is its tracker builds frames.

    `./scripts/check.sh` green before committing.

91. A tracker of our own, off the log we already read.

    A placeable column over the world: the quest name, its objectives under it,
    a mark on the pinned ones. `src/UI/Placeable.lua`, `src/UI/Stack.lua` for
    the rows, and item 76's `UI.Wash` under them, because this is a third window
    the addon draws over the world and the ground under it is settled by then.

    **It draws from `ns.QuestLog`'s zones and nothing else.** That file already
    turns the client's flat run of rows into zones holding quests and already
    caches it, `src/Quests/Log.lua:41`, and the quest window's left column is
    already its only reader. A tracker with a second reading of the log is the
    sheet and the loot feed all over again: two pictures of one thing, drifting
    apart in the details nobody looks at until they are side by side. One
    reading, two drawings.

    So this file owns placement, rows and the pin mark, and asks `ns.QuestLog`
    for everything it says.

    It does not open on a quest. Clicking a row is `src/Quests/Tracker.lua`'s
    existing swap arriving from our own frame instead of Questie's, which is one
    call and no new path.

    Nothing on a ticker. The log changes on events, item 89 adds a better one,
    and a tracker is not a compass.

    `./scripts/check.sh` green before committing.

92. Where you are, asked once.

    `ns.QuestHere`, answering the place you are standing in as a map id, a name
    and whether it is a dungeon.

    Off the map id and never off a name, which `src/Dungeons/Here.lua:12` argues
    at length and is right about: `GetInstanceInfo` hands back Blizzard's name
    in the player's language, it is a different name from the book's for eight
    of the forty dungeons, and matching English text is a feature that works on
    one client in ten.

    The dungeon half is `ns.DungeonHere` and is not rewritten. The open world
    half is `GetBestMapForUnit`, which `src/Map/Zones.lua:182` and
    `src/UI/Chart.lua:497` already probe the same way, and this is the third
    reader rather than a third probe.

    Questie's `ZoneDB` is what joins the two number spaces. Its
    `GetAreaIdByUiMapId` at `Database/Zones/zoneDB.lua:98` turns the client's
    map id into the area id the quest database is keyed on, and
    `ZoneDB.IsDungeonZone` at `:158` and `GetParentZoneId` at `:164` are the
    other two. `src/Quests/Where.lua:529` already goes the other way through
    `GetUiMapIdByAreaId` and this is that reader's opposite number.

    In Core because two folders read it, `Quests` and eventually `Map`, and a
    part may not name a file outside its own tree.

    `./scripts/check.sh` green before committing.

93. A quest is where its next step is, not where the client filed it.

    The client's log header is a sort category. It is the zone for most quests,
    the dungeon's name for a dungeon quest and a class name for a class quest,
    and it says nothing about where the thing you still have to do is standing.
    Scope the tracker on the second, not the first.

    `Where.Nearest` at `src/Quests/Where.lua:292` already answers it. It reads
    Questie's `DistanceUtils.GetNearestSpawnForQuest`, which walks the open
    objectives, and returns the area, the name and the yardage. The area is what
    this item wants and it is already coming back.

    So a quest is on the tracker when its nearest open thing is in the place
    `ns.QuestHere` names, and a quest whose header says Winterspring but whose
    next step is a Felwood innkeeper is on the tracker in Felwood. That case is
    the whole argument for doing it this way and it is common.

    Fall back to the header when Questie is not installed or has not compiled.
    The header is a worse answer and it is a great deal better than an empty
    tracker.

    Mind the cost, which is item 97's whole problem arriving early. Read
    `Where.lua:243` before writing a line of this: the walk is hundreds of
    coordinate transforms per quest, it is memoised for one quest for one
    second, and a tracker that asked it about twenty quests on a paint would be
    a stutter in the world rather than anything visibly wrong in the window. The
    scoping reading is per quest per zone change, held until the zone changes,
    and it is not on the paint path.

    `./scripts/check.sh` green before committing.

94. A list row knows which button and which modifier.

    `UI.List` at `src/UI/Window.lua:1414` hands `onSelect` an id and nothing
    else. It already carries `onRight` and `onBack` for the gestures that were
    wanted before this one, so the shape is settled: `onSelect` gains the button
    and the modifier state, and every existing caller ignores the extra
    arguments.

    Read `RegisterForClicks` against `OnMouseUp` before choosing. The rows here
    are frames rather than buttons and the modifier is read at the moment of the
    press either way, but the two disagree about which presses arrive at all,
    and the wrong one of them is a gesture that silently does nothing on one of
    the two clients.

    One widget, so the chat rail, the dungeon shelf, the mail list and the quest
    log all gain the same gesture vocabulary at once. That is the argument for
    doing it in the widget rather than in the quest window: a shift click that
    means one thing in one list and nothing in the next is a worse interface
    than no shift click at all.

    `./scripts/check.sh` green before committing.

95. A pin is ours, and the client's five slots are left alone.

    Shift left click on a row of the quest log's left column pins the quest.
    Saved per character, uncapped, keyed on the quest id for the reason
    `src/Quests/Log.lua:20` gives about indices: an index is a position that
    moves on every turn-in and a window holding one changes what it is showing
    while you read it.

    **The client's watch list stops being written.** `Client.Watch` at
    `src/Quests/Client.lua:288` calls `AddQuestWatch`, the client caps that at
    five, and Questie replaces the global `GetNumQuestWatches` outright to get
    around the cap. That is a fight with the client and this addon is not
    joining it. The `track` button at `src/Quests/Window.lua:808` becomes `pin`
    and the `watched` field on a row becomes `pinned`.

    Say the cost out loud in the panel, because there is one. Questie's map
    icons can be filtered to tracked quests only, and a player using that filter
    will find our pins do not reach it. `Client.Watch` stays on the file
    unused rather than deleted, so the day that trade turns out to be the wrong
    one it is one line to write both.

    `./scripts/check.sh` green before committing.

96. The pin, drawn where you can see it.

    Two drawings of one fact. On the row, the mark `UI.List` already builds for
    `opts.marks`, in the addon's heading gold. And at the top of the left
    column, pinned quests as their own group above the zones, in the order they
    were pinned.

    The group is the half that matters. A mark on a row is a thing you find by
    scrolling to the row; a group is the answer to "what am I always watching"
    without looking for it, which is the question the pin exists to answer.

    An empty group is not drawn. A heading with nothing under it is a row of the
    column spent saying you have not used a feature.

    A pinned quest also draws in its zone, and does not vanish out of the list
    it was in. A quest that moved when you pinned it is a quest you then have to
    find again.

    On the tracker, item 91's mark, and pinned quests are shown wherever you are
    standing. That is what pinning is for: item 93 takes everything else off the
    tracker when you leave the zone, and this is the exception you asked for by
    hand.

    `./scripts/check.sh` green before committing.

97. How far away everything is, on a budget.

    `ns.QuestNear`, a list of what is close to you, ordered by distance, over
    two sources.

    Your log, through `Where.Nearest`, which is the existing reader and is not
    duplicated.

    And what you have not picked up, which is the half worth building this for.
    `AvailableQuests.__availableQuestsByNpc` in
    `Modules/Quest/AvailableQuests/AvailableQuests.lua:57` is every quest
    Questie says you could accept, keyed by the npc holding it, and
    `QuestieDB:GetNPC(npcId).spawns` is where that npc stands.
    `DistanceUtils.GetNearestSpawn(spawns)` takes exactly that table and hands
    back the yardage. That path is far cheaper than the log's, because an npc
    has spawns and a quest has objectives that have spawns.

    Two fields rather than functions, so `ns.Questie`'s function check does not
    cover them and this file checks the types itself, at the read, which is the
    rule in that function's own header.

    **The budget is the design.** `Where.lua:243` measured the cost of the log
    half already: hundreds of zone-to-world transforms per quest, memoised one
    quest deep for one second, and a twenty quest log walked on a paint is
    thousands of them. So this walks a few entries per tick off `UI.Ticker`,
    keeps the answer, and finishes a full pass in a couple of seconds rather
    than blocking on one. It gets a name and a `Perf` slot, which item 44's gate
    requires of every ticker in the addon.

    It never runs on a paint and never on `QUEST_LOG_UPDATE`. Both are the
    mistake this file exists downstream of.

    In yards, unranked, unsorted into a route. Ordering is item 98's and the
    restraint is item 99's.

    `./scripts/check.sh` green before committing.

98. The line that says why not finish this one.

    One line at the foot of the tracker, naming one thing that is close to you.
    Either something in your log you are near, or somebody standing nearby with
    a quest you have never taken.

    It is a friend and not a route planner, and the phrasing carries that. "The
    last two Deadwood Trappers are close by, north" rather than "127.4 yards".
    The distance is Euclidean over world coordinates, `QuestieLib.Euclid`
    through HereBeDragons, and a cliff or a lake between you and the murloc
    makes sixty yards a three minute walk. A number sounds like a promise the
    data cannot keep. A direction and a nearness are true.

    Direction is the addon's own arithmetic off the player facing and the
    spawn's bearing, and it is eight words rather than a compass. It is the one
    number here the game will actually confirm as you walk.

    Anything past `ELSEWHERE` at `src/Quests/Where.lua:46` is not close and is
    not mentioned. Questie adds half a million yards to a spawn outside your
    instance so that local things sort first, and that constant is already on
    the file for exactly this reason.

    It speaks when the answer changes. Not on a clock, and not again for the
    thing it just named.

    `./scripts/check.sh` green before committing.

99. What the friend will not do, held by a gate rather than by a comment.

    Item 98 is one sentence of code and a page of restraint, and every piece of
    that restraint is the kind that erodes in a refactor nobody meant anything
    by. So it is a section in `scripts/harness/` and a rule in
    `scripts/check.sh`, which is the two layers every other gate in this repo
    lives in.

    Four things, and each of them is the feature rather than a tidiness:

      one thing    the line names a single quest. A second name in it is a list,
                   a list is a route, and a route is the module this was
                   explicitly not going to be.
      quiet        it does not speak twice inside its own quiet period, and it
                   does not repeat the thing it just named.
      silent       nothing in combat, and nothing while `ns.QuestHere` says you
                   are in a dungeon, where everything is thirty yards away and
                   the friend would be a chatterbox.
      no order     nothing in `src/Quests/` sorts the log by distance, by
                   experience or by level. The gate reads for it, the way the
                   `GameTooltip` rule reads comments, because the sort that
                   makes this a levelling addon is four lines and would arrive
                   looking like a convenience.

    The harness proves the first three by driving the reading rather than by
    reading the source: feed it two things at the same distance and one line
    comes out, ask twice inside the period and the second is silent, set the
    dungeon flag and nothing comes out at all.

    Written while it is already satisfied, which is the only cheap moment, and
    that is the same argument the rule at `scripts/check.sh:845` makes about
    itself.

    `./scripts/check.sh` green before committing.

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

The Narcissus reading adds most of that addon. Its photo mode is nine of its
files and the reason it exists: a camera you drive with the keyboard, a spell
visual browser, an NPC browser, an animation browser, a weapon browser, speech
balloons, stickers, letterbox filters and a turntable. None of it is on this
list and none of it should be. The same goes for its AFK screen, its
achievement pages, its minimap button, its own tooltip, its guide and its
NPC and item databases, which are the four largest folders it ships. What is
taken from it is what makes a character sheet legible and alive, which is the
ten items above and nothing else.

Two of its mechanisms were looked at and refused. It parks the whole Blizzard
UI off `UIParent` while the sheet is up, at `Main.lua:98-145`, so that hiding
the interface leaves its own page standing. That is a photo booth feature with
a real cost: a frame taken off `UIParent` and put back is a frame whose scale,
strata and parent this addon then owns, and `src/UnitFrames/Blizzard.lua`,
which owns `ns.BlizzHide`, already carries what that costs when it is done to
one window rather than to all of them. And it draws its stats as a radar
chart, `Narci_RadarTemplate` in `Narcissus.xml:136`. A radar chart of five
stats is a shape you compare against a shape you remember, and nobody
remembers last week's pentagon. The column of numbers beside the figure
answers the question the chart is drawn to answer.
