---
revision: 1
id: 01M1XJZZ8DP9JJJ1CN50SFQ9PB
type: task
status: todo
title: The palette takes the colours twelve files still write by hand.
parent: 01M1XJZYMA3V0YPE58CH5H938J
labels: [item-80]
---

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
