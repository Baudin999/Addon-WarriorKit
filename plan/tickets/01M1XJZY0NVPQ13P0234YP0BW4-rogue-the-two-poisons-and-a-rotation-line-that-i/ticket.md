---
revision: 1
id: 01M1XJZY0NVPQ13P0234YP0BW4
type: feature
status: todo
title: "Rogue: the two poisons, and a rotation line that is nearly empty."
parent: 01M1XJZW5CFY7JB9WKRNJC94H0
labels: [item-58]
---

`standing` is two slots, main hand and off hand, `word = "poisons"`, on a
fourth reader called `enchant`. It reads `GetWeaponEnchantInfo`, which
`src/Buffs/Upkeep.lua:439` already documents across that call's three shapes
and `:479` already picks the stride for at runtime, so reuse that reading.

Write the limit into the reader: the call says whether a hand is enchanted,
for how long and how many charges are left, but not which poison, so the
square draws the weapon's own icon off `GetInventoryItemTexture`. The
charges are the number the client's buff frame buries.

`reactive` gets Riposte, which opens on a parry and is Revenge under another
name, and wants the `defended` trigger `src/Class/Warrior.lua` spells.

No `charge`, `forms`, `swing`, `requires` or `upkeep`. Stealth stays off the
row on `src/Class/Shaman.lua:12`'s Ghost Wolf argument, and a bare weapon is
already the first entry on the shipped buff nag.

`suggested`: Rupture, Garrote, Expose Armor, Hemorrhage, Deadly Poison,
Crippling Poison, Wound Poison, Mind-numbing Poison, Cheap Shot, Kidney
Shot, Gouge, Blind, Sap.

The rotation line does not fit this class: almost nothing a rogue presses
has a cooldown, and the number that decides every press is the combo point
count, which nothing here draws. Write the lists short rather than padding
them; a combo point row is a new part and a new item.

- Assassination, tree 1. Cooldowns Cold Blood, Vanish, Evasion, Blind.
  Rotation Mutilate, Kidney Shot. Debuffs Rupture, Garrote, Deadly Poison,
  Kidney Shot.
- Combat, tree 2. Cooldowns Adrenaline Rush, Blade Flurry, Evasion, Vanish.
  Rotation Riposte, Kick, Gouge. Debuffs Rupture, Expose Armor, Crippling
  Poison, Kidney Shot.
- Subtlety, tree 3. Cooldowns Preparation, Shadowstep, Vanish, Evasion.
  Rotation Shadowstep, Premeditation. Debuffs Rupture, Hemorrhage, Cheap
  Shot, Kidney Shot.
