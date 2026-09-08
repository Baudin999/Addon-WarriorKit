---
revision: 1
id: 01M20J18M6MPNFD1PVB8KSZRYQ
type: task
status: todo
title: "Action targeting on every class, not only warriors"
---

## What is wrong

`SoftTargetEnemy` is driven off combat by `src/Charge/SoftTarget.lua`: `3` out
of combat, `0` in it. It never runs on anything but a warrior. `Wanted()` gates
on `ns.Charge.Available()`, and only `Class/Warrior.lua` registers a `charge`
set, so on every other class the CVar is left where the client put it.

The setting itself is already account wide (`softAuto` in `WarriorKitDB`,
default true). The class gate is the only thing stopping it.

## Why it is in the wrong tree

Action targeting is a client setting about how you pick a mob. It landed in
`Charge/` because the charge marker was the first thing that wanted the
`softenemy` token, which is the same shape as every other entry on
`scripts/trees.lua`'s allow-list: a service parked in whichever feature asked
first. The fix for that is to move the file.

The refusal is written in three places, so dropping the gate in `Wanted()`
alone would write the CVar on a mage with no way to see it or turn it off:

- `Charge/SoftTarget.lua:72`, `Wanted()`
- `Charge/Feature.lua:26`, `Refuse()` in front of the slash word
- `Charge/Feature.lua:237`, the panel's early return

## The move

`Charge/SoftTarget.lua` becomes `Targeting/Aim.lua`, `ns.SoftTarget` becomes
`ns.Aim`. `Targeting/` already exists, is class independent, and is named for
this; it becomes the two things targeting does, a switch key and an aim token.

The saved keys keep their names, `softAuto` on the account and `softPrior` on
the character, so nobody's setting is lost and nothing needs retiring.

What stays in `Charge/`: `Charge.SoftUnit`, `Charge.SoftTargetState` and the
`softProven` latch. Those ask whether the `softenemy` token resolves, which is
a question about the charge marker's aiming and not about the CVar.

## The setting

`Targeting/Feature.lua` gains the section, the word and the status line:

- panel section "Action targeting" under Fighting, next to Switch target
- `/wk aim on|off`
- `ns.Aim.Describe()` on the targeting status line

`Charge/` loses its "Action targeting" section, its `charge soft` sub-word,
`softAuto`/`softPrior` from its defaults, the `ns.SoftTarget.Apply()` call in
`ApplyChargeChange` (dead once `Wanted()` stops reading charge state), and the
`SoftTarget.Describe()` half of its status line. The token reading moves down
into the marker section, where it is about the marker.

## Gate

`scripts/harness/sections/21-which-class.lua:106` asserts the class gate
verbatim: `cvars.SoftTargetEnemy == (CHARGE and "3" or "0")`. It has to become
`"3"` on every class. `src/.luacheckrc:412` and two comments in
`Charge/Charge.lua` name the old path.
