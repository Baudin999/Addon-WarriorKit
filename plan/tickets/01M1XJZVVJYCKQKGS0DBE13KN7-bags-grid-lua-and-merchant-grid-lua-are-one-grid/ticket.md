---
revision: 1
id: 01M1XJZVVJYCKQKGS0DBE13KN7
type: task
status: todo
title: `Bags/Grid.lua` and `Merchant/Grid.lua` are one grid.
parent: 01M1XJZSDGJ90YGY9ZP6HBYPS9
labels: [item-30]
---

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
