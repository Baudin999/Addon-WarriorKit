---
revision: 1
id: 01M1XJZTMYRYN6A1THBPY15VSD
type: task
status: todo
title: "Nine `*/Blizzard.lua` files, one contract, written down nowhere."
parent: 01M1XJZSDGJ90YGY9ZP6HBYPS9
labels: [item-25]
---

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
