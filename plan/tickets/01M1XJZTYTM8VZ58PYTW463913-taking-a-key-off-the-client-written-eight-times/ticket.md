---
revision: 1
id: 01M1XJZTYTM8VZ58PYTW463913
type: feature
status: todo
title: "Taking a key off the client, written eight times."
parent: 01M1XJZSDGJ90YGY9ZP6HBYPS9
labels: [item-26]
---

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
