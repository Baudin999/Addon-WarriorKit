---
revision: 1
id: 01M1XJZXPDETH9KDEHMY5B5G6R
type: feature
status: todo
title: "Paladin: the aura, the seal and the blessing."
parent: 01M1XJZW5CFY7JB9WKRNJC94H0
labels: [item-57]
---

`standing` is three slots and `word = "auras"`, on item 56's `buff` reader:
every aura, every seal, every blessing that lands on you. The seal carries
the clock, because it runs thirty seconds and lapses mid-pull silently.

`upkeep` gets the seal as well, cleared by any seal. Not a duplicate: the
row is a square and the upkeep entry is the nag, the same split Battle Shout
and the stance row sit either side of.

`requires` is the finding. Hammer of Wrath is castable below twenty percent,
which is Execute's rule word for word and the second entry in a field
`src/Buttons/Requires.lua` built for one. Nothing else here meets the bar.

No `charge`, `forms`, `swing` or `reactive`; Reckoning and Redoubt land as
buffs, so they go with item 59's `on = "buff"` or nowhere.

`suggested`: Judgement of Light, of Wisdom, of the Crusader and of Justice,
Hammer of Justice, Repentance, Avenger's Shield, Holy Vengeance and its
Horde spelling, Turn Evil and Exorcism if either lands an aura.

- Holy, tree 1. Cooldowns Avenging Wrath, Divine Favor, Divine Illumination,
  Lay on Hands, Divine Shield. Rotation Holy Shock, Hammer of Justice.
  Debuffs the judgement you are running, Hammer of Justice.
- Protection, tree 2. Cooldowns Avenging Wrath, Divine Shield, Divine
  Protection, Lay on Hands. Rotation Avenger's Shield, Holy Shield,
  Consecration, Judgement, Hammer of Justice. Debuffs Judgement of Wisdom,
  Judgement of Light, Hammer of Justice, the Avenger's Shield daze.
- Retribution, tree 3. Cooldowns Avenging Wrath, Divine Shield, Lay on
  Hands, Repentance. Rotation Crusader Strike, Judgement, Hammer of Wrath,
  Exorcism, Hammer of Justice. Debuffs the judgement, Hammer of Justice,
  Repentance.
