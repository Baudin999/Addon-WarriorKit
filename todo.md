# Todo

Each item is built by one agent in its own worktree under `.worktrees/`,
on a branch named `worktree-<name>`, and merged into master when
`./scripts/check.sh` comes back at zero. That gate is the gate for every open
item below and no item repeats it.

## How this file works

A finished item folds to one line: number, title, hash. The commit is the
record, `git show <hash>` gives back everything the checklist said, and a
checklist kept beside it is a second copy that drifts. Open items keep only
what git cannot: the files to touch and the decisions already made. Numbers are
identifiers, not positions, so gaps are correct.

The long text of every item is in this file at `a9d743e`; item 10's is at
`d05546c` and item 62's at `17b6427`. What each landed item fixed is in
`docs/CHANGELOG.md`, and what is still unconfirmed in game is in the README's
untested list.

## Landed

1. Weapon swing timer. `8be9a43`
2. Deep Wounds missing from the enemy bar debuffs. `05e40ec`
3. Overpower drawn as ready when it is not. `dbbcd69`
4. Missing buff nag, including racials. `042df6c`
5. Enemy cast bar. `89a3e45`
6. Party and raid frames, ours off a secure group header. `e3de603`
7. Cooldown row for the long cooldowns, out of the class registry. `2245a01`
8. The target block reflected about the middle of the screen. `2a999b5`
9. Our own buff and debuff rows on the skinned frames. `1871fa6`
11. `Skin.lua`, which had three subjects, split into four. `a5624de`
12. The chat window, reimagined as a rail of rooms. `1c4de0e`
13. What the class split left behind, down to `Class.Label()`. `fc6c0e5`
14. check.sh derives its class shapes from `Class/*.lua`. `371d82d`
15. A placeable HUD frame, named at last. `80528bc`
16. `ns.RegisterUnitEvent` in Core, where the other thirty shims live. `3df1df1`
17. The slash dispatchers, off a table rather than a chain of ifs. `abddb67`
18. One ticker, and a HOT list walked rather than typed. `903350d`
19. `UI.Window` re-zooms its own frame, and every screen sizes on its own. `da4a01a`
21. A client probe outside `Core/` fails check.sh, path-keyed with a reason each. `7bb75c2`
23. A ceiling only moves down, in `scripts/ratchet.lua`. `271f8e6`
28. One Questie probe, in Core, and a gate that keeps it one. `07c4401`
31. The four tick-path exemptions, all four allow-listed by name. `395e38a`
32. The action ticker armed once, `UI.Ticker` refusing a second of one name. `86603a3`
33. The action squares drawn on a dirty bit from Blizzard's own events. `86603a3`, merge fixed at `4021112`
34. Enemy bar threat as numbers, level cached per GUID, the reading at 1 Hz. `7140091`
35. The cast sweep walks the open chambers and stops when there are none. `7140091`
36. One combat log reader in Core, six subscribers, off the event when idle. `d352b0c`
37. The options window built on first open, refreshed only where visible. `9e6accd`
38. Skin and party frames told by unit events, the bar texture hooked. `eb884ee`
39. `Charge.State` memoised per frame, `Known` cached, the draw gated. `cd91ccc`
40. Caged frames hooked on SetParent and Show, the verify pass at 5 s. `cd91ccc`
41. Feeds and chat rooms mark on arrival and draw once a frame. `2d08eeb`
42. Every window and row built on first open or first switch. `d87c42d`
43. One frame for the ticks that never stop, and a gate on the exceptions. `156dede`
44. Eleven smaller costs, and a gate that every ticker has a Perf slot. `ba87227`
45. Twelve handlers seeded as hot roots, a hot-path string counted. `f89b5be`
46. A row that answers the right button keeps it, and the harness presses like the client. `673d78c`
47. A bag pickup filter switched from the bag window, with a price floor. `547a5f8`
48. The tooltip goes with the pointer, the linger shipped at zero. `06cd212`
49. Chrome opens after four tenths of a second held still. `cce5ebc`
50. Ad hoc bars: six bars of sixteen per character, on a key, from snippets. `66ce6fc`
51. Ctrl-R given a window: four seconds of frames, and a reason on each bad one. `b32bd7c`
52. A totem bar: four slots in a fixed order with a hole where one is missing. `245bbee`
60. `UI.Clip`, a round icon masked at its own rim, and `scripts/bake-round.sh`. `b220ad6`
61. The gear page as nineteen rows over the figure. `7b8373a`
63. Noto Sans shipped in `src/Media/`, and forty windows relaid against it. `89de0a6`
64. The loadouts come out, with the tab that hosted them. `3b31e1c`
65. One page: no tab strip, skills in the stats column, standings on `/wk reputation`. `d667d93`
66. A name read on a gradient rather than on the grass, out of `UI.Wash`. `2b55319`
67. The world darkens behind the sheet, on a frame that never takes the mouse. `ff5816d`
68. A gear change is watched: the row dips and the columns arrive from their sides. `fdb49e3`
69. The socket carries its gem rather than a mark saying one is there. `7c6fb88`
70. The enchant under the name, and the oil counting down on the weapon. `0e17925`
71. A trinket says when it is up, swept on the disc's ring out of `UI.Arc`. `8b18daa`
72. The figure is yours to turn, and the pose is remembered. `fe3c4ce`
73. A feed folds a repeat into the row it is on, bounded at sixteen. `d65fcdd`
74. The loot feed folds on link, looter and minute, the tooltip keeping the total. `a36b893`
75. Coin folds on being coin, off a running total `Core/Loot.lua` reads back. `1ab1e8d`
76. Every feed row read on a gradient that ends where the text ends. `cafa7d8`
77. Every feed string off the rim and onto that ground, in the same commit. `cafa7d8`
79. The feed's quality stripe rests where the sheet's does, off a shared `rest`. `0fa0cb2`
83. One answer to why an item matters: quest, skill, trash, nothing. `463afe8`, moved out of Core by `4eafa88`
84. A reagent says whether it is still worth a point. `4ed288f`
85. An objective read into a name and two numbers, off the client's format strings. `afcc248`
86. The loot row says why it matters, in the dim column and on the icon ring. `c76af91`
87. A chip that draws any row with a reason on it. `e97217d`
88. What the loot filter refused, carried from the corpse's slot to the feed. `bffc7a1`
89. The one part of Questie that promises not to move. `726f79c`
90. Questie's tracker goes off, by its own hand. `57386bf`
91. A tracker of our own, off the log we already read. `024bdf7`, moved to the
    top left corner by `7a77cff`
92. Where you are, asked once. `d7d7262`
94. A list row knows which button and which modifier. `ee45b34`
95. A pin is ours, and the client's five slots are left alone. `2aeafd8`
96. The pin, drawn where you can see it. `fb6240f`
97. Who nearby has a quest you have never taken. `ae85182`
98. The line that says why not finish this one. `dbf2168`
99. What the friend will not do, held by a gate rather than by a comment. `116ae93`
100. A feed row draws a whole word or none of it. `b003b3c`

The options window's prose budget was deleted rather than raised again, at
`4bed7d6`. It counted every sentence in the window against a number that had
been raised eight times, each raise defined as the measurement plus a hint's
worth of room. The per-string caps stay: a lede at 160 characters, a hint at
200. Each page gets tuned on its own when the addon is done.

Item 10, the Slam mark, and item 62, a loadout carrying a whole set of gear,
were dropped rather than finished. Nothing tracks either.

## Open

Items 20 to 30 came out of architecture reviews on 2026-08-29 and 2026-09-02,
the second run against LCOM over shared module state, a token clone detector and
fan-in and fan-out on `ns`. None is a bug. Read an item against the code before
working it: item 15 undercounted its sites by five and item 18 undercounted its
closure by half. `ns.db` measured clean, 215 keys with four read outside the
folder that declares them, and file-level LCOM4 is 1 almost everywhere.

20. `EachTexture` into Core, beside `ns.Strip`.

    `src/Artwork/Artwork.lua:59` and `src/UnitFrames/Art.lua:248` are the same
    pcall-guarded walk over a frame's texture regions, differing only in Art's
    `keep` set. It goes beside `ns.Strip`, `ns.Unstrip` and `ns.Blocked`, the
    three calls it exists to feed.

22. `Core/Menu.lua` registers a feature from inside Core.

    `src/Core/Core.lua:8` promises Core knows nothing about any feature, and
    twenty-five parts keep that by registering from `<Folder>/Feature.lua`.
    `src/Core/Menu.lua:275` does not, and wants a folder like the rest. Last,
    after 20 and 26 have proved the registry needs no help from Core.

24. `UnitFrames/EnemyBars.lua` is three modules in one file.

    2,450 lines, 72 top-level functions, 25 mutable module locals, 26 distinct
    `ns.*` names, the largest fan-out in the addon. Its own headers are at
    `:269`, `:578`, `:774`, `:1482` and `:1734`.

    - `:269` is 17 functions over `trackedNames`, `trackedIcons` and
      `unresolved` with no frame in any of them: a saved list with Add, Remove,
      Reset, Repair and Resolve, inside a nameplate widget.
    - `:1482` is 8 functions over `stripped`, `pending` and `passThrough`,
      sharing one name with the modes block. The ninth `Blizzard.lua`, filed
      under another name inside the file it hides plates for.

    File-level LCOM4 reads it as cohesive because the call graph glues it
    together. On state alone it is five components, so measure it that way.

25. Nine `*/Blizzard.lua` files, one contract, written down nowhere.

    2,292 lines. Seven of the nine define `Wanted`, `Apply` and `Describe` over
    `Frame` and `Remember`, on two mechanisms: park the frame off screen at no
    alpha, or put it in the attic and take its key.
    `src/Mail/Blizzard.lua:65-160` and `src/Merchant/Blizzard.lua:68-198` are
    the same 90 lines of park, minus Merchant's drift check.
    `src/Map/Blizzard.lua:55-190` and `src/Quests/Blizzard.lua:60-165` are the
    same cage, minus Map opening the dungeon window.

    Five of the seven end with `ns.BlizzHide.Also(Blizz.Apply)`. Mail and Quests
    take seven hand-written `Apply()` calls across their `Feature.lua` and
    `Window.lua` instead, and nothing says whether that is deliberate.

26. Taking a key off the client, written eight times.

    `SetOverrideBindingClick` onto a secure button, `ClearOverrideBindings`
    before it, a `Holds(key)` reading the override layer back through
    `GetBindingAction`, and a record of the displaced binding, at
    `src/Targeting/Switch.lua:74`, `src/Charge/Icon.lua:275`,
    `src/Hover/Cast.lua:194`, `src/Dungeons/Key.lua:57`,
    `src/Marking/Keys.lua:74`, `src/Buttons/Bars.lua:371` and
    `src/Character/Blizzard.lua:167`. The first two match down to the comment
    above `Holds`.

    The shared piece is the take, not the re-take: `ns.Rebind` at
    `src/Core/Core.lua:1459` already owns the re-take after `UPDATE_BINDINGS`.
    `ns.TakeKey(button, key, name)` returns the displaced binding and calls
    `ns.Rebind` inside itself, which retires seven copies and the three probe
    entries in `scripts/check.sh` that name it. `src/Buttons/Bars.lua:813`
    answers the event itself and Core's comment at `:1434` allows that;
    `src/Character/Blizzard.lua:200` is Core's mechanism rebuilt beside Core's
    and goes.

27. A window has no lifecycle, so twelve files invented one.

    `UI.Window` hands back `Show`, `Hide` and `IsShown` at
    `src/UI/Window.lua:493-504`, and twelve callers wrap that in their own
    `Show`, `Hide`, `Shown` and `Toggle` over a file-local `window`. Four
    spellings of one boolean came out of it, and `src/Mail/Window.lua:1097`
    reaches past the object into `window.frame:IsShown()`, which breaks the day
    the object grows a wrapper. `src/Breakdown/Window.lua` carries five names
    for two states; `src/Dungeons/Window.lua:847-864` and
    `src/Map/Window.lua:406-423` are identical line for line.

    The fix is on the object, not in Core: `Toggle`, one spelling of `Shown`,
    and an optional `onShow` for the parts that paint on the way up.

29. The spell row on the options page, twice.

    `src/Buffs/Feature.lua:119-156` and `src/UnitFrames/Panel.lua:31-68` are the
    same 38 lines: a `Spell()` closure over a slot index, an icon, a remove
    button, a label pinned between them, and a measure returning zero height for
    an empty slot. It wants to be `ui.SpellRow` in `src/UI/Widgets.lua`.

30. `Bags/Grid.lua` and `Merchant/Grid.lua` are one grid.

    The same functions in the same order: `Subject`, `Enter`, `Leave`, `Build`,
    `Paint`, `Place`, `Trim`, then `Attach`, `Paint`, the pool, `Headers` and
    `Describe`.

    Weaker than it was. The merchant's unit is a card in columns worked out from
    the window's width and the bag's is a bare square in a column count you set,
    so what is shared is the pile walk and the pool. Ranked last of the seven,
    and the way to find out is to write the shared grid and see what will not
    fit through it.

Items 53 to 59 came out of an ask on 2026-09-04: write down what every class and
build needs before any of them is written. Nine classes, twenty-seven builds,
four class files on disk. Five rules settle most of it.

- A class file is facts and one file, `src/Class/Class.lua:27`. That holds for
  eleven of the twelve fields; `standing` is the exception and item 53 says what
  it costs.
- The fields are listed at `src/Class/Warrior.lua:11`. `forms`, `charge`,
  `reactive`, `requires`, `swing`, `upkeep`, `suggested` and `standing` go at
  the top; `cooldowns`, `rotation`, `debuffs` and `loadout` go inside a spec,
  which writes only what it disagrees with. Caps are eight, six and four,
  asserted in `Cooldowns.All` and `Upkeep.Fixed`, and they fire at PLAYER_LOGIN
  as a Lua error in somebody's game.
- No item carries a spell id. Bake them at implementation from Wowhead's TBC
  Classic database, rank 1, and read each back by name; drop what this client
  cannot resolve rather than guessing. An ability with no cooldown comes off the
  rotation line.
- No item writes a `loadout`. `src/Class/Shaman.lua:37` and
  `src/Class/Priest.lua:17` refuse a plan for a build nobody here has played,
  which covers twenty-four of the twenty-seven.
- No item writes a signature. `src/Class/Spec.lua:54` wants a one-rank talent at
  the foot of a tree; each item names the tree instead, and the signature is
  confirmed a rank at a time or left out.

53. The stance row, and the second reader.

    The reader is `stance`, in the table at `src/Standing/Standing.lua:56`, and
    every shapeshifting class uses it. It walks `GetShapeshiftFormInfo` and
    matches each slot's spell name against the bar rather than indexing into it,
    which is the correction to item 52's guess: `GetShapeshiftForm` answers a
    position on a bar holding only the forms you have learned. A slot matched
    and missing draws empty, the way an empty totem slot already does.

    A stance fills three of the five reader values, and
    `src/Standing/Row.lua:261` already reads the other two as `expires[index] or
    0` and `span[index] or 0`, so `Row.lua` does not change.
    `GetShapeshiftFormInfo` and `GetNumShapeshiftForms` are not in the harness;
    they go beside `GetShapeshiftForm` at
    `scripts/harness/client/05-quests.lua:691`, not in `03-player.lua`.

    The plan goes in `src/Class/Warrior.lua` beside `forms`: three slots in that
    file's order, `kind = "stance"`, `word = "stances"`, `one = "stance"`.

    `src/Standing/Feature.lua:105` writes its slash words at file load, before
    the client will say what class this is, so every class's word lives in that
    table: `forms`, `aspects`, `poisons`, `auras`, `demon`. That is the one file
    outside `Class/` a new class edits, and the fix is a gate: hold every `word`
    and `one` a plan registers against the table, and fail on a table word no
    plan claims.

54. What a fifth class file costs the gate, before the fifth one lands.

    `scripts/check.sh:1354` reads the class tokens off `Class/*.lua` and runs
    the harness once per shape: thirteen runs today, twenty-eight at nine
    classes, and the harness is the slowest thing in `check.sh`. Measure one run
    before item 56 lands and again after.

    HUNTER at `scripts/check.sh:1377` is the proof that the class-agnostic parts
    stand up with nothing registered, and item 56 eats it silently. Replace it
    in the same commit with a token no class file can claim, and say in the
    comment above the loop that the token is deliberately not a class.

55. Druid: forms, and the first plan a spec overrides.

    `forms` in learn order, Bear, Aquatic, Cat, Travel, because the `stance:`
    conditional counts positions on the bar the reader walks and the prefix
    holds while levelling. Moonkin and Tree are talents and go last. Confirm the
    order at 70 and at 25, and if it does not hold drop `forms` rather than
    generate a macro against a moving number; only the loadouts page reads it
    here and `src/Core/Stance.lua:20` already allows a weapon set with no stance.

    `standing` is the second `stance` user and the first field a spec overrides
    for something other than a number: all three builds get bear, aquatic, cat
    and travel, balance appends Moonkin Form and restoration Tree of Life.

    `upkeep` is one entry, the mark, cleared by Mark of the Wild or Gift of the
    Wild. No `charge`, `swing` or `requires`; Omen of Clarity lands as a buff,
    so it is item 59's `on = "buff"` or nothing.

    `suggested`: Moonfire, Insect Swarm, Faerie Fire and its feral form,
    Entangling Roots, Rake, Rip, Pounce, Lacerate, Mangle, Demoralizing Roar,
    Hibernate, Cyclone.

    - Balance, tree 1. Cooldowns Innervate, Force of Nature, Barkskin, Rebirth.
      Rotation Hurricane and Force of Nature, the only two with real clocks.
      Debuffs Moonfire, Insect Swarm, Faerie Fire.
    - Feral, tree 2. Cooldowns Innervate, Barkskin, Rebirth, Enrage. Rotation
      Mangle, Feral Charge, Swipe, Faerie Fire (Feral). Debuffs Rake, Rip,
      Lacerate, Mangle, Faerie Fire, Demoralizing Roar, at the cap.
    - Restoration, tree 3. Cooldowns Innervate, Nature's Swiftness, Rebirth,
      Tranquility. Rotation Swiftmend, Nature's Swiftness. Debuffs Faerie Fire,
      Entangling Roots.

56. Hunter: aspects, the pet, and the second class to fill `reactive`.

    Lands with item 54 or after it, because it takes the no-file proof away.

    Two new readers. `buff` matches a list of names against `UnitAura("player")`
    and reports the first that is up, with the client's own icon and expiry;
    item 57 needs it too. `pet` answers `UnitExists("pet")` with the pet's name
    and portrait and no clock; item 59 needs it. `UnitAura` is stubbed at
    `scripts/harness/client/03-player.lua:205`; `UnitCreatureFamily`,
    `GetPetHappiness` and a pet unit in the roster are not there at all.

    `standing` is two slots, aspect and pet, `word = "aspects"`. The aspect slot
    carries Hawk, Monkey, Cheetah, Pack, Wild, Beast and Viper and lights
    whichever is up, because the question is which and not whether. The pet slot
    is dark when the pet is dead or dismissed.

    `reactive` is the finding: Mongoose Bite opens on a dodge and Counterattack
    on a parry, which is Overpower and Revenge with the names swapped, and
    `src/Buttons/Reaction.lua` already owns the parse. Confirm the window
    against the warrior's five seconds; the two may not share it.

    No `charge`, `forms`, `swing`, `requires` or `upkeep`. Every `requires`
    candidate here is a range or aim rule the client already answers, and the
    aspect is on the row above.

    `suggested`: Hunter's Mark, Serpent Sting, Viper Sting, Scorpid Sting,
    Wyvern Sting, Concussive Shot, Wing Clip, Scatter Shot, Silencing Shot,
    Intimidation, Freezing Trap, Explosive Trap.

    - Beast mastery, tree 1. Cooldowns Bestial Wrath, Intimidation, Rapid Fire,
      Misdirection. Rotation Arcane Shot, Multi-Shot, Kill Command if this
      client has it. Debuffs Hunter's Mark, Serpent Sting, Intimidation stun.
    - Marksmanship, tree 2. Cooldowns Rapid Fire, Readiness, Misdirection,
      Silencing Shot. Rotation Aimed Shot, Arcane Shot, Multi-Shot, Silencing
      Shot. Debuffs Hunter's Mark, Serpent Sting, Scatter Shot.
    - Survival, tree 3. Cooldowns Rapid Fire, Misdirection, Deterrence,
      Readiness if the talent is not marksmanship-only here. Rotation Mongoose
      Bite, Counterattack, Wyvern Sting, Arcane Shot, Explosive Trap. Debuffs
      Hunter's Mark, Serpent Sting, Wyvern Sting, Wing Clip.

57. Paladin: the aura, the seal and the blessing.

    `standing` is three slots and `word = "auras"`, on item 56's `buff` reader:
    every aura, every seal, every blessing that lands on you. The seal carries
    the clock, because it runs thirty seconds and lapses mid-pull silently.

    `upkeep` gets the seal as well, cleared by any seal. Not a duplicate: the
    row is a square and the upkeep entry is the nag, the same split Battle Shout
    and the stance row sit either side of.

    `requires` is the finding. Hammer of Wrath is castable below twenty percent,
    which is Execute's rule word for word and the second entry in a field
    `src/Buttons/Requires.lua` built for one. Nothing else here meets the bar.

    No `charge`, `forms`, `swing` or `reactive`; Reckoning and Redoubt land as
    buffs, so they go with item 59's `on = "buff"` or nowhere.

    `suggested`: Judgement of Light, of Wisdom, of the Crusader and of Justice,
    Hammer of Justice, Repentance, Avenger's Shield, Holy Vengeance and its
    Horde spelling, Turn Evil and Exorcism if either lands an aura.

    - Holy, tree 1. Cooldowns Avenging Wrath, Divine Favor, Divine Illumination,
      Lay on Hands, Divine Shield. Rotation Holy Shock, Hammer of Justice.
      Debuffs the judgement you are running, Hammer of Justice.
    - Protection, tree 2. Cooldowns Avenging Wrath, Divine Shield, Divine
      Protection, Lay on Hands. Rotation Avenger's Shield, Holy Shield,
      Consecration, Judgement, Hammer of Justice. Debuffs Judgement of Wisdom,
      Judgement of Light, Hammer of Justice, the Avenger's Shield daze.
    - Retribution, tree 3. Cooldowns Avenging Wrath, Divine Shield, Lay on
      Hands, Repentance. Rotation Crusader Strike, Judgement, Hammer of Wrath,
      Exorcism, Hammer of Justice. Debuffs the judgement, Hammer of Justice,
      Repentance.

58. Rogue: the two poisons, and a rotation line that is nearly empty.

    `standing` is two slots, main hand and off hand, `word = "poisons"`, on a
    fourth reader called `enchant`. It reads `GetWeaponEnchantInfo`, which
    `src/Buffs/Upkeep.lua:439` already documents across that call's three shapes
    and `:479` already picks the stride for at runtime, so reuse that reading.

    Write the limit into the reader: the call says whether a hand is enchanted,
    for how long and how many charges are left, but not which poison, so the
    square draws the weapon's own icon off `GetInventoryItemTexture`. The
    charges are the number the client's buff frame buries.

    `reactive` gets Riposte, which opens on a parry and is Revenge under another
    name, and wants the `defended` trigger `src/Class/Warrior.lua` spells.

    No `charge`, `forms`, `swing`, `requires` or `upkeep`. Stealth stays off the
    row on `src/Class/Shaman.lua:12`'s Ghost Wolf argument, and a bare weapon is
    already the first entry on the shipped buff nag.

    `suggested`: Rupture, Garrote, Expose Armor, Hemorrhage, Deadly Poison,
    Crippling Poison, Wound Poison, Mind-numbing Poison, Cheap Shot, Kidney
    Shot, Gouge, Blind, Sap.

    The rotation line does not fit this class: almost nothing a rogue presses
    has a cooldown, and the number that decides every press is the combo point
    count, which nothing here draws. Write the lists short rather than padding
    them; a combo point row is a new part and a new item.

    - Assassination, tree 1. Cooldowns Cold Blood, Vanish, Evasion, Blind.
      Rotation Mutilate, Kidney Shot. Debuffs Rupture, Garrote, Deadly Poison,
      Kidney Shot.
    - Combat, tree 2. Cooldowns Adrenaline Rush, Blade Flurry, Evasion, Vanish.
      Rotation Riposte, Kick, Gouge. Debuffs Rupture, Expose Armor, Crippling
      Poison, Kidney Shot.
    - Subtlety, tree 3. Cooldowns Preparation, Shadowstep, Vanish, Evasion.
      Rotation Shadowstep, Premeditation. Debuffs Rupture, Hemorrhage, Cheap
      Shot, Kidney Shot.

59. Warlock: the demon, and two things the fields cannot say yet.

    `standing` is one slot, the demon, `word = "demon"`, on item 56's `pet`
    reader. Soul shards stay off: a count is a number in a bag and the reader
    contract at `src/Standing/Standing.lua:41` has nowhere to put it. If it is
    wanted it goes on the upkeep row as a floor.

    `upkeep` gets the armor, Fel Armor, Demon Armor and Demon Skin, matched the
    way `src/Class/Mage.lua:142` matches its four. No `charge`, `forms`, `swing`.

    Two findings, both extensions rather than entries.

    - `reactive` cannot say Nightfall, which arrives as Shadow Trance, a buff
      with a ten second clock, rather than down the combat log. That wants
      `on = "buff"` with a spell id read off `UnitAura("player")` by item 56's
      reader. Three classes want it, so write it here or as its own item first.
    - `requires` cannot say Conflagrate, which needs your Immolate on the target
      rather than a health percentage. A second condition kind belongs in
      `src/Buttons/Requires.lua`: `needs = <spell>` on the target, matched by
      name, mine only. Shadowburn and Death Coil need nothing and stay off.

    `suggested`: Corruption, Immolate, Curse of Agony, of the Elements, of
    Weakness, of Tongues, of Doom, Siphon Life, Unstable Affliction, Seed of
    Corruption, Fear, Howl of Terror, Banish, Death Coil.

    - Affliction, tree 1. Cooldowns Curse of Doom, Death Coil, Howl of Terror,
      Amplify Curse. Rotation Death Coil and Howl of Terror, which is two
      because the rest is dots with no clocks. Debuffs Corruption, Curse of
      Agony, Siphon Life, Immolate, Unstable Affliction.
    - Demonology, tree 2. Cooldowns Fel Domination, Soulshatter, Death Coil,
      Howl of Terror. Rotation Shadowburn if the character has it, Death Coil,
      Howl of Terror. Debuffs Corruption, Immolate, Curse of Agony, Curse of the
      Elements.
    - Destruction, tree 3. Cooldowns Soulshatter, Death Coil, Howl of Terror,
      Shadowfury. Rotation Conflagrate, Shadowburn, Shadowfury, Death Coil.
      Debuffs Immolate, Corruption, Curse of the Elements, the Shadowfury stun.

Items 78 to 82 came out of the sheet redesign of 2026-09-05 and the feed work
after it. They are one finding twice: two windows drew one picture, and the
numbers behind it were typed at the call site.

78. A badge is a widget, not a thing the paperdoll has.

    The four readings at the head of the stats column, `LABELS` at
    `src/Character/Paperdoll.lua:544` with `BADGE` and `BADGERIM` at `:197`, and
    the three numbers along the bottom of the loot feed, built in
    `Instance:BuildStatus` at `src/Feeds/Stream.lua:264` off `Purse.Line` at
    `src/Feeds/Purse.lua:322`, are one picture: a number, a word under it, a
    tone the number earned, a hover that explains it.

    `UI.Badge` in `src/UI/Widgets.lua` takes a value, a label, a tone and a
    tooltip. The sheet's four keep their fraction, which the durability badge
    draws as a bar; the feed's three pass none. Items 76 and 77 put the strip's
    readings on a wash driven off the row slider, so the widget inherits ground
    under it and has to keep it. The tones stay where they are: `WearTone` is a
    fact about durability and `Tone` in `Purse.lua` about whether the afternoon
    paid.

80. The palette takes the colours twelve files still write by hand.

    Forty-seven fractional colour literals outside `src/UI/Theme.lua` and
    `src/Unit/Color.lua`: twelve in `src/UI/Ability.lua`, seven in
    `src/Feeds/Combat.lua`, six in `src/Swing/Gauges.lua`, four each in
    `src/Meter/Window.lua`, `src/Class/Shaman.lua` and `src/Buttons/Look.lua`,
    three in `src/CombatText/Numbers.lua`, two each in
    `src/Character/Paperdoll.lua` and `src/Buffs/Nag.lua`, one each in
    `src/Perf/Hud.lua`, `src/Mail/Window.lua` and `src/Feeds/Loot.lua`. Stale by
    two: item 83 gave `quest`, `skill` and `trash` a home in `UI.Color` and item
    79 moved `REST` into `UI.Metric` as `rest`.

    Sort them by kind. `QUEST` at `src/Feeds/Loot.lua:62` is a palette entry and
    goes to `UI.Color`. `RIM` at `src/Character/Paperdoll.lua:126` is a distance
    and goes to `UI.Metric`, with `DENSE`, `TIGHT` and `VALUE` at
    `src/Character/Readout.lua:79`, `:72` and `:64`, which are the dense-list
    metrics and now have a second reader. `src/Feeds/Combat.lua`'s seven grade a
    kind of event, so they become a named table with a header in that file, the
    way `Unit/Color.lua` owns power colours. A class colour is the client's and
    stays. Land the move, count what is left, then write item 81.

81. A colour written by hand is an error.

    `scripts/check.sh` refuses a fractional colour triple outside
    `src/UI/Theme.lua` and `src/Unit/Color.lua`: a table constructor of three or
    four numbers with a fraction in it, and the same shape passed to
    `SetColorTexture`, `SetTextColor` or `SetVertexColor`. A fraction, not any
    triple, because `SetVertexColor(1, 1, 1)` is a reset and
    `SetColorTexture(0, 0, 0, 0.55)` is a shadow.

    Whatever item 80 leaves is allow-listed by file with a one-line reason each,
    in the shape the eight rules above it use, and the length of that list is a
    ceiling in `scripts/ratchet.lua`. A file that clears its last literal comes
    off the list in the same commit. Error, not warning: a colour typed at a
    call site is invisible until two windows are open side by side.

82. `/wk style`, the page that draws the palette.

    `src/Settings/Style.lua`, registered by `src/Settings/Feature.lua`, built on
    first open. Not in `src/UI/`, where no file registers a feature.

    It draws itself out of the tables rather than describing them: every
    `UI.Color` entry as a swatch with its key, every `UI.Metric` as a rule of
    that many pixels with its number, the three font sizes in the shipped face,
    `UI.Quality` as eight names in eight colours, and a wash, a badge, a chip, a
    feed row and a readout row side by side. Side by side is the feature:
    whether the feed row and the sheet row look like one addon is a thing eyes
    answer in a second and a file never answers.

    A page with no settings on it. The day a colour on it is editable is the day
    `UI.Theme`'s header stops being true. After items 78 to 81.

## Deliberately not on this list

- `src/Progress/Progress.lua:70` and `src/Quests/Client.lua:43` hold the same
  four-line probed call. Each is written against its own returns, and a prober
  in Core would be a call every part reaches through rather than a seam.
- `src/UI/Feed.lua`, `src/UI/Log.lua` and `src/UI/Stack.lua` each open by saying
  why they are not one of the others, and each argument holds.
- `src/Class/*.lua` files repeat each other because each is a registry of one
  class's spells. The repeat is the table shape, not the data.
- `UI.Quality` at `src/UI/Theme.lua:100` and `Color.power` at
  `src/Unit/Color.lua:355` are two palettes that happen to be the same size.
- Ten parts open a placeable HUD frame with the same four calls, `CreateFrame`,
  `ns.UI.Adopt`, `ns.UI.Unit`, `ns.UI.Placeable`. That is what a constructor
  already looks like.
- Stripping comments from the shipped files. All 230 compile in 26 ms in stock
  Lua 5.1 with the comments in, so a build step buys under 10 ms a login.
- Chasing a serialise-on-logout cost. Chat history, quest drops, dungeon drops,
  breakdown spells and loadouts are all capped, most at 400.
- Item 93, scoping the tracker on where a quest's next open objective stands. It
  is the better answer and it costs hundreds of coordinate transforms per quest
  against a memo one quest deep. The tracker scopes on the log header, item 96's
  pin is the escape hatch, item 99 gates the walk to its one caller.
- Most of Narcissus: its photo mode is nine files and the reason it exists, and
  its AFK screen, achievement pages, minimap button, tooltip, guide and two
  databases are its largest folders. What was taken from it is items 60 to 72.
- Narcissus parking the whole Blizzard UI off `UIParent` while the sheet is up,
  `Main.lua:98-145`. A frame taken off `UIParent` and put back is a frame whose
  scale, strata and parent this addon then owns, and
  `src/UnitFrames/Blizzard.lua` already carries what that costs for one window.
- Narcissus drawing its stats as a radar chart, `Narci_RadarTemplate` in
  `Narcissus.xml:136`. Nobody remembers last week's pentagon; the column of
  numbers beside the figure answers the question the chart is drawn for.
