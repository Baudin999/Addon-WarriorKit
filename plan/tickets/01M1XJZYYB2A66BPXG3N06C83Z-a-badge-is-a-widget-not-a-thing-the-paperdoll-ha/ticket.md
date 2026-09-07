---
revision: 1
id: 01M1XJZYYB2A66BPXG3N06C83Z
type: task
status: todo
title: "A badge is a widget, not a thing the paperdoll has."
parent: 01M1XJZYMA3V0YPE58CH5H938J
labels: [item-78]
---

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
