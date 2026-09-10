---
revision: 4
id: 01M25AJKT5C5XDDD0QNP841656
type: bug
status: todo
title: A new item in the bags blanks every tooltip until a reload
---

Receive an item and the tooltips break: every hover in the addon shows its
title and nothing the client wrote, and the bags file every bound item as
unbound. A reload fixes it until the next time.

## Cause

`UI/Scan.lua` made its hidden GameTooltip and called `SetOwner` on it once, in
`Frame`. A GameTooltip that hides drops its owner, and one with no owner takes
every setter and writes nothing, so `NumLines` stayed at 0 for the rest of the
session. The client hides the scanner on its own terms, and a bag update from
new loot is the one reported.

The harness stub hid it: its `SetOwner` took anything and `Hide` never took the
owner away, so the path passed there and not in the game.

## Fix

`Ask` owns the scanner again, `UIParent` and `ANCHOR_NONE`, before every
question. TitanRepair does the same before each read on this client.

## Gate

`11-tooltip.lua` clears the owner on `Hide` and answers nothing from an unowned
setter. `48-tooltips.lua` hides the scanner and hovers the bag item again: the
client's `Aegis` and `Soulbound` have to come back.
