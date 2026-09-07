---
revision: 1
id: 01M1Y4JDFMVHEB87QK9R1KP4BJ
type: feature
status: todo
title: Equipment Manager
parent: 01M1B7D84Q2BKFK2CHXKRZCH8B
---

Named sets of gear you can put on with a click or a key. A tanking set, a
shadow resist set for Mother Shahraz, the two hander you swing once the boss
is down.

## What the client will and will not do

Six facts decide the whole shape of this, and five of them are already
written down somewhere in the tree.

**There is no equipment manager on this client.** Blizzard's arrived in 3.3.
Baganator guards its own set tracker with `not IsEra and not IsBC` and the
comment "Wrath onwards", which is the proof: `C_EquipmentSet` is not there
and every part of this is built from nothing.

**Armour cannot be equipped in a fight.** `Character/Worn.lua:327` already
holds the rule. Slots 16, 17 and 18 are the three combat allows, and the
server refuses the rest with its own message.

**Equipping goes through the cursor.** `PickupContainerItem` then
`PickupInventoryItem`, which is what `Worn.Swap` does and what
`Core/Sockets.lua` does in the same order. `EquipItemByName` is the wrong
call and `Worn.lua` says why in its header.

**Nothing here is protected, so nothing here needs a secure button.** That is
the difference between this and the weapon loadouts, which came out at
`e497197`: three files, 764 lines, ten secure buttons made at login whether
or not anybody owned a loadout, and a macro rewritten onto each of them on
every apply. All of that was paying for a stance in macro text. A set is
items, a swap is item moves, and item moves are plain Lua.

**The spec reader already exists.** `Class/Spec.lua` answers `Spec.Mine`,
`Spec.Token` and `Spec.All`, and already runs a pass when your talents move.

**The word "loadout" is taken.** `Class/*.lua` calls its bar plan a loadout
and the removal commit calls out the clash. The slash word here is `/wk set`
and the folder is `src/Sets/`.

## What a set is

A name and up to nineteen slots. Each slot is in one of three states: an
item, deliberately empty, or unset.

Unset is the state that matters. A shadow resist set names five pieces and
leaves your rings and trinkets alone, and that is the most common real set on
this client. A full nineteen slot set is only the case where nothing is
unset. Deliberately empty is the third because taking the shield off is a
thing a set has to be able to say.

Sets are per character, in `WarriorKitCharDB`. Gear is a fact about one
character.

Nineteen and not twenty: the ammo slot is not in `Worn.SLOTS` and no hunter
class file exists. A set records items and never bag contents, so nothing
here moves your reagents.

## How an item is written down

By what it does, not by where it is. The key is fields 2 through 8 of the
item string, which is id, enchant, four gems and suffix. Auctionator's legacy
path reads the suffix out of that position on this client, which is what
proves the offset.

`uniqueId` and everything past it is dropped. It changes as an item moves and
it would make a set stop matching itself. Two genuinely identical rings are
then interchangeable, which is the right answer.

The link is saved beside the key, so a piece sitting in the bank still draws
with its name, colour and icon. `Gear.List` already greys a weapon it cannot
see and this is the same move.

## Putting a set on: a plan, then a queue

Separating the two is the engineering argument for the whole feature.

**The plan** runs in one frame and calls nothing that changes anything.

1. Mark every slot whose worn item already matches and reserve that item. A
   set you are already wearing costs zero moves.
2. Find an unreserved source for each remaining slot, in the bags or in
   another worn slot.
3. Order the moves.

Two rings trading places is the case a naive per slot loop fights itself on,
and it needs no free bag slot: pick up 11, drop into 12 which hands back the
other ring, drop that into 11. Three cursor operations.

**The queue** then runs the plan one move per event, off `ITEM_LOCK_CHANGED`
and `BAG_UPDATE`. Every move is a server round trip and a second pickup while
the first is in flight fails silently. Before each move it re-checks that the
source still holds the wanted key. It clears the cursor on any abort, which
`Sockets.lua` already argues for. It has a deadline, and when it gives up it
names the slots it could not fill.

One line comes back:

    put on fury: 12 changed, 4 already on, 1 not in your bags (Dragonspine Trophy)

## The phases

Five, each one a vertical you can use in game on its own.

1. A set you can save and put on. Slash only, no UI.
2. The sets on the character page.
3. Editing a set on the doll.
4. A key on a set, and the swap that waits for the fight.
5. The set that follows your spec.

Phase 5 is the weakest and it should be built last or not at all. TBC has no
dual spec. You respec at a trainer for gold, maybe once a week, and that is
already an out of combat moment with time to click a chip. The key in phase 4
is what gets pressed forty times a night. Specs are why you name the sets,
not why you switch them.

Held back until the five land: remembering where a missing piece was last
seen, so "not in your bags" becomes "in your bank"; and marking a set's items
in the bag window, the way Baganator marks Blizzard's.
