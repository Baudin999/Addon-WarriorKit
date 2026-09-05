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
