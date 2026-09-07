---
revision: 1
id: 01M1Y4JJADXT00H6V1Z6660YBG
type: task
status: todo
title: Editing a set on the doll
parent: 01M1Y4JDFMVHEB87QK9R1KP4BJ
---

Phase 3 of `01M1Y4JDFMVHEB87QK9R1KP4BJ`, the equipment manager. Build a set
out of things you are not wearing, on the doll you already have.

## What lands

Pick a set to edit and the page changes what it is drawing. The nineteen rows
show what the set holds instead of what you have on, and the figure wears the
set rather than your body. Everything else on the page stays put.

- Drop a bag item on a row and it goes into the set. It does not go on you.
- Right-click a row clears the slot back to unset.
- Shift-right-click makes the slot deliberately empty.
- An edge or a tint says the page is in edit mode, because a doll showing
  gear you are not wearing is the one thing here that could be read wrong.

This is the phase that makes the three slot states visible, and it is why
they exist. Until now every set was a snapshot of your whole body.

## Why the doll and not a picker

`Worn.Swap` already takes a cursor drop on all nineteen rows, so the drop
target is built. A picker would be a second way to say the same thing, drawn
against a list rather than against a body, and you would lose the item level
and the durability you were reading when you decided. `Core/Gear.lua` offers
a list for one hand in a macro, and that is the right shape there and the
wrong shape here.

## Testing it in game

Build a shadow resist set without putting a single piece on. Five slots
named, fourteen left unset. Then `/wk set wear` it and confirm your rings and
trinkets did not move.

Then make one slot deliberately empty and wear it, and confirm the shield
comes off.

## The gate

Extends `88-gear-sets.lua`. A drop writes the key and not the body, an unset
slot plans no move, and a deliberately empty slot plans a move to a bag slot
and refuses with a reason when the bags are full.
