---
revision: 1
id: 01M1XJZX2T7CTA69DR84NR59XR
type: task
status: todo
title: "Druid: forms, and the first plan a spec overrides."
parent: 01M1XJZW5CFY7JB9WKRNJC94H0
labels: [item-55]
---

`forms` in learn order, Bear, Aquatic, Cat, Travel, because the `stance:`
conditional counts positions on the bar the reader walks and the prefix
holds while levelling. Moonkin and Tree are talents and go last. Confirm the
order at 70 and at 25, and if it does not hold drop `forms` rather than
generate a macro against a moving number; only the loadouts page reads it
here and `src/Core/Stance.lua:20` already allows a weapon set with no stance.

`standing` is the second `stance` user and the first field a spec overrides
for something other than a number: all three builds get bear, aquatic, cat
and travel, balance appends Moonkin Form and restoration Tree of Life.

`upkeep` is one entry, the mark, cleared by Mark of the Wild or Gift of the
Wild. No `charge`, `swing` or `requires`; Omen of Clarity lands as a buff,
so it is item 59's `on = "buff"` or nothing.

`suggested`: Moonfire, Insect Swarm, Faerie Fire and its feral form,
Entangling Roots, Rake, Rip, Pounce, Lacerate, Mangle, Demoralizing Roar,
Hibernate, Cyclone.

- Balance, tree 1. Cooldowns Innervate, Force of Nature, Barkskin, Rebirth.
  Rotation Hurricane and Force of Nature, the only two with real clocks.
  Debuffs Moonfire, Insect Swarm, Faerie Fire.
- Feral, tree 2. Cooldowns Innervate, Barkskin, Rebirth, Enrage. Rotation
  Mangle, Feral Charge, Swipe, Faerie Fire (Feral). Debuffs Rake, Rip,
  Lacerate, Mangle, Faerie Fire, Demoralizing Roar, at the cap.
- Restoration, tree 3. Cooldowns Innervate, Nature's Swiftness, Rebirth,
  Tranquility. Rotation Swiftmend, Nature's Swiftness. Debuffs Faerie Fire,
  Entangling Roots.
