# Todo

**This file is the log. The open work is in `plan/`, and `ckplan` reads it.**
It moved there on 2026-09-07 at `ce73068`. `CLAUDE.md` is how to read and write
it; `ckplan ls` is the list and `ckplan show <id>` is one card with its thread.

Each item was built by one agent in its own worktree under `.worktrees/`, on a
branch named `worktree-<name>`, and merged into master when `./scripts/check.sh`
came back at zero. That gate is still the gate for every card in the plan and no
card repeats it.

## How this file works

A finished item is one line: number, title, hash. The commit is the record,
`git show <hash>` gives back everything the checklist said, and a checklist kept
beside it is a second copy that drifts. Numbers are identifiers, not positions,
so gaps are correct, and a card in the plan carries its number as a label.

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

Nineteen items, now nineteen cards under three blocks: the architecture review,
the class files and the palette. `ckplan ls --status todo` is the list and each
card carries its number here as a label, so `item-24` is item 24.
