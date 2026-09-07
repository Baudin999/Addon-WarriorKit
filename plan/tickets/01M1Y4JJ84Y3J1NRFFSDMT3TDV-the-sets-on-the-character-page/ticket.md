---
revision: 1
id: 01M1Y4JJ84Y3J1NRFFSDMT3TDV
type: task
status: todo
title: The sets on the character page
parent: 01M1Y4JDFMVHEB87QK9R1KP4BJ
---

Phase 2 of the equipment manager. The sets get a face, on the page that is
already about your gear.

## What lands

A row of chips under the figure on `Character/Paperdoll.lua`, one per set,
plus one at the end that saves what you have on.

- Click a chip and it wears that set, through phase 1's `Apply`.
- The chip for the set you are wearing is lit.
- Hover lists the pieces, and marks the ones you cannot reach.

No new window, and no fifth tab in the stats column. That column is
readouts; a set is not a readout. The character page already draws all
nineteen slots, the item level and the durability, which are the things you
read while you are building a set, so this belongs there and nowhere else.

## What "lit" means

Every slot the set names matches what you are wearing. A set that names five
slots is on when those five match, whatever is in the other fourteen. That is
the definition partial sets force and it is the right one.

The page repaints on the six gear events already, so the lit chip follows
your body with no new plumbing. Nothing here goes on a ticker, same as the
rest of the window.

## Testing it in game

Open C. The chip for what you are wearing is lit and the others are not.
Click another and watch the doll redress and the light move. Swap one ring by
hand and watch the light go out.

## The gate

Extends `88-gear-sets.lua` rather than adding a section: the new assertions
are about which chip is lit for a given worn state, including the partial
set, and the options harness sees the row exists.
