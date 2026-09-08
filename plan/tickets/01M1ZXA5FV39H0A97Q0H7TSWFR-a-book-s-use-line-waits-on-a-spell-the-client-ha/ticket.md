---
revision: 1
id: 01M1ZXA5FV39H0A97Q0H7TSWFR
type: bug
status: done
title: A book's Use line waits on a spell the client has not fetched
---

Hover a profession book in the bags and the box says the item's name, its
level and what skill it requires, and nothing about what it is for. The line
that is missing is `Use: Teaches you advanced first aid, allowing a maximum of
375 first aid skill.`, which is the whole reason anybody carries the book.

## Why it is missing

That line is not the item's. It is the spell's own sentence printed on the
item, and the client does not hold every spell's text at all times: it fetches
one when something asks for it and leaves the line off the tooltip until it
lands. A potion or a trinket you press reads correctly because its spell is
already on the machine; a book teaching something you have never cast is the
case where nothing ever asked.

`UI/Scan.lua` reads the tooltip once, at the moment the pointer arrives, and
the box that comes back is complete in every respect but the one. `Thin` in
`UI/Tip.lua` already rebuilds a box that was waiting on an item, and it cannot
see this: the head band has lines in it and none of them is
`RETRIEVING_ITEM_INFO`.

Syndicator does the same three calls on this client, in
`Search/CheckItem.lua:508`: `C_Item.GetItemSpell` for the id,
`C_Spell.IsSpellDataCached` for whether the text is here, and
`C_Spell.RequestLoadSpellData` for one that is not.

## The fix

- `Scan.Waiting(link)`: the spell behind an item's Use line, whether the client
  has it, and the ask for one it has not.
- `Thin` counts a box waiting on that spell as thin, so `Tip.Arrived` rebuilds
  it, and `SPELL_DATA_LOAD_RESULT` joins `GET_ITEM_INFO_RECEIVED` on the frame
  that drives it.
- A worn slot carries no link, so it is asked for: a trinket you press has a
  Use line the same as a book does.

## Gate

`48-tooltip-arrival.lua`, on a book fixture whose spell is not cached: the
first hover draws no Use line and asks the client for the spell, and the box
fills in where it stands when `SPELL_DATA_LOAD_RESULT` arrives.
