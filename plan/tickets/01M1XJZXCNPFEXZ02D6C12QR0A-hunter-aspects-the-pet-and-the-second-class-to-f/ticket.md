---
revision: 1
id: 01M1XJZXCNPFEXZ02D6C12QR0A
type: task
status: todo
title: "Hunter: aspects, the pet, and the second class to fill `reactive`."
parent: 01M1XJZW5CFY7JB9WKRNJC94H0
labels: [item-56]
---

Lands with item 54 or after it, because it takes the no-file proof away.

Two new readers. `buff` matches a list of names against `UnitAura("player")`
and reports the first that is up, with the client's own icon and expiry;
item 57 needs it too. `pet` answers `UnitExists("pet")` with the pet's name
and portrait and no clock; item 59 needs it. `UnitAura` is stubbed at
`scripts/harness/client/03-player.lua:205`; `UnitCreatureFamily`,
`GetPetHappiness` and a pet unit in the roster are not there at all.

`standing` is two slots, aspect and pet, `word = "aspects"`. The aspect slot
carries Hawk, Monkey, Cheetah, Pack, Wild, Beast and Viper and lights
whichever is up, because the question is which and not whether. The pet slot
is dark when the pet is dead or dismissed.

`reactive` is the finding: Mongoose Bite opens on a dodge and Counterattack
on a parry, which is Overpower and Revenge with the names swapped, and
`src/Buttons/Reaction.lua` already owns the parse. Confirm the window
against the warrior's five seconds; the two may not share it.

No `charge`, `forms`, `swing`, `requires` or `upkeep`. Every `requires`
candidate here is a range or aim rule the client already answers, and the
aspect is on the row above.

`suggested`: Hunter's Mark, Serpent Sting, Viper Sting, Scorpid Sting,
Wyvern Sting, Concussive Shot, Wing Clip, Scatter Shot, Silencing Shot,
Intimidation, Freezing Trap, Explosive Trap.

- Beast mastery, tree 1. Cooldowns Bestial Wrath, Intimidation, Rapid Fire,
  Misdirection. Rotation Arcane Shot, Multi-Shot, Kill Command if this
  client has it. Debuffs Hunter's Mark, Serpent Sting, Intimidation stun.
- Marksmanship, tree 2. Cooldowns Rapid Fire, Readiness, Misdirection,
  Silencing Shot. Rotation Aimed Shot, Arcane Shot, Multi-Shot, Silencing
  Shot. Debuffs Hunter's Mark, Serpent Sting, Scatter Shot.
- Survival, tree 3. Cooldowns Rapid Fire, Misdirection, Deterrence,
  Readiness if the talent is not marksmanship-only here. Rotation Mongoose
  Bite, Counterattack, Wyvern Sting, Arcane Shot, Explosive Trap. Debuffs
  Hunter's Mark, Serpent Sting, Wyvern Sting, Wing Clip.
