---
revision: 1
id: 01M1XJZV8CGSQ7VJHSTTCE825X
type: task
status: todo
title: "A window has no lifecycle, so twelve files invented one."
parent: 01M1XJZSDGJ90YGY9ZP6HBYPS9
labels: [item-27]
---

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
