---
revision: 2
id: 01M1B7PS9TKQS7A12J6P9DV5RS
type: block
status: done
title: Dungeon Journal
---

A simple Journal where we can see the dungeons, their bosses, their descriptions and their drops. From here we can add the items the bosses drop to our Wishlist

Built as `Dungeons/`, eight files, shaped like the quest log: bosses down the
left, the dungeon's own map in the middle with a numbered mark per boss, drops
on the right. Shift-L.

Two departures from the text above, both deliberate.

No boss descriptions. They were asked out: what a dungeon log is opened for is
what drops and where the fight is, and a paragraph of lore per boss is two
hundred and thirty seven paragraphs nobody would have read twice.

No wishlist yet. That is its own ticket and it depends on this one and on the
quest mapper. What this leaves it is the join it needs: `ns.DungeonBook.Loot`
answers a boss's drops as `{ id, name }` pairs, and `ns.DungeonLoot.Row` turns
one into what the client says about it, which is everything a wishlist row wants
without going near this window.
