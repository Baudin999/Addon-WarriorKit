---
revision: 1
id: 01M1XJZYAD0DSDBH9VE9MEYXZG
type: feature
status: todo
title: "Warlock: the demon, and two things the fields cannot say yet."
parent: 01M1XJZW5CFY7JB9WKRNJC94H0
labels: [item-59]
---

`standing` is one slot, the demon, `word = "demon"`, on item 56's `pet`
reader. Soul shards stay off: a count is a number in a bag and the reader
contract at `src/Standing/Standing.lua:41` has nowhere to put it. If it is
wanted it goes on the upkeep row as a floor.

`upkeep` gets the armor, Fel Armor, Demon Armor and Demon Skin, matched the
way `src/Class/Mage.lua:142` matches its four. No `charge`, `forms`, `swing`.

Two findings, both extensions rather than entries.

- `reactive` cannot say Nightfall, which arrives as Shadow Trance, a buff
  with a ten second clock, rather than down the combat log. That wants
  `on = "buff"` with a spell id read off `UnitAura("player")` by item 56's
  reader. Three classes want it, so write it here or as its own item first.
- `requires` cannot say Conflagrate, which needs your Immolate on the target
  rather than a health percentage. A second condition kind belongs in
  `src/Buttons/Requires.lua`: `needs = <spell>` on the target, matched by
  name, mine only. Shadowburn and Death Coil need nothing and stay off.

`suggested`: Corruption, Immolate, Curse of Agony, of the Elements, of
Weakness, of Tongues, of Doom, Siphon Life, Unstable Affliction, Seed of
Corruption, Fear, Howl of Terror, Banish, Death Coil.

- Affliction, tree 1. Cooldowns Curse of Doom, Death Coil, Howl of Terror,
  Amplify Curse. Rotation Death Coil and Howl of Terror, which is two
  because the rest is dots with no clocks. Debuffs Corruption, Curse of
  Agony, Siphon Life, Immolate, Unstable Affliction.
- Demonology, tree 2. Cooldowns Fel Domination, Soulshatter, Death Coil,
  Howl of Terror. Rotation Shadowburn if the character has it, Death Coil,
  Howl of Terror. Debuffs Corruption, Immolate, Curse of Agony, Curse of the
  Elements.
- Destruction, tree 3. Cooldowns Soulshatter, Death Coil, Howl of Terror,
  Shadowfury. Rotation Conflagrate, Shadowburn, Shadowfury, Death Coil.
  Debuffs Immolate, Corruption, Curse of the Elements, the Shadowfury stun.

Items 78 to 82 came out of the sheet redesign of 2026-09-05 and the feed work
after it. They are one finding twice: two windows drew one picture, and the
numbers behind it were typed at the call site.
