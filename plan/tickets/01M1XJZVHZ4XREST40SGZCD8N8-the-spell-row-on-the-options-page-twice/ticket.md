---
revision: 1
id: 01M1XJZVHZ4XREST40SGZCD8N8
type: feature
status: todo
title: "The spell row on the options page, twice."
parent: 01M1XJZSDGJ90YGY9ZP6HBYPS9
labels: [item-29]
---

`src/Buffs/Feature.lua:119-156` and `src/UnitFrames/Panel.lua:31-68` are the
same 38 lines: a `Spell()` closure over a slot index, an icon, a remove
button, a label pinned between them, and a measure returning zero height for
an empty slot. It wants to be `ui.SpellRow` in `src/UI/Widgets.lua`.
