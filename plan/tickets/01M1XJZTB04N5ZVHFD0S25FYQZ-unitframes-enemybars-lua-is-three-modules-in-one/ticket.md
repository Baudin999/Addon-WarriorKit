---
revision: 1
id: 01M1XJZTB04N5ZVHFD0S25FYQZ
type: task
status: todo
title: `UnitFrames/EnemyBars.lua` is three modules in one file.
parent: 01M1XJZSDGJ90YGY9ZP6HBYPS9
labels: [item-24]
---

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
