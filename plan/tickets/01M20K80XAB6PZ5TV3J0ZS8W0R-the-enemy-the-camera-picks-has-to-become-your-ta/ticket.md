---
revision: 1
id: 01M20K80XAB6PZ5TV3J0ZS8W0R
type: task
status: todo
title: The enemy the camera picks has to become your target
---

## The report

"The softtarget is great, but after the first cast, we do not actually select
the enemy as the target, so we cannot attack anymore."

## Cause

Two faults, and they compound.

`SoftTargetEnemy` gives you a soft target, which is not a target. `softenemy`
resolves and a macro written against it casts, but nothing is selected, so auto
attack has nothing and the bar has nothing. The CVar that closes that is
`SoftTargetForce`, "auto-set target to match soft target, 1 for enemies and 2
for friends". The addon has never written it.

Its client default is 1, which is why this was never caught: the feature reads
as working on a client sitting at the default and as broken on one that is not,
and nothing in either case says which. Owning half a mechanism is owning none
of it.

The second is the combat split. `Aim.Apply` wrote `SoftTargetEnemy` to 0 at
`PLAYER_REGEN_DISABLED`, which is one second into every fight, and that takes
the target that had been forced from it away with it. The argument for the
split was that a client re-aiming at whatever you glance at is the last thing
you want while holding a mob. The argument is right and the mechanism was
wrong: `SoftTargetMatchLocked` defaults to 1, "match appropriate soft target to
locked target", so the client already pins the soft target to the one you hold
and stops the camera choosing. The split was solving a problem the client
solves, at the price of your target.

## Fix

`Targeting/Aim.lua` owns a list of CVars rather than one, writes
`SoftTargetEnemy=3` and `SoftTargetForce=1`, and reads both back. No combat
branch: one state, held whenever the setting is on. `PLAYER_REGEN_DISABLED` is
no longer listened for; `PLAYER_REGEN_ENABLED` stays as the retry for a write
the client refused in combat.

`softPrior` was a bare string for the one CVar. It becomes `aimPrior`, a table
keyed by CVar name, and `softPrior` is retired in `Core/Core.lua` for the
markKeys reason: a string left where a table is indexed would have been read on
the way out and written to a CVar.

## Gate

`21-which-class.lua` asserts both halves come back on, on every class, and that
a fight does not take them down. That last is asked through the combat flag and
a direct `Apply` rather than by firing `PLAYER_REGEN_DISABLED`, which every
meter and clock in the addon hears and would count as a fight for the rest of
the run.

## Sources

https://warcraft.wiki.gg/wiki/Console_variables/Classic gives SoftTargetForce
default 1, SoftTargetEnemy 0/1/2/3, SoftTargetMatchLocked default 1.
