---
revision: 1
id: 01M1ZXK9A2DQN15DXYHF6W16DW
---

Cause. The Use line on an item is the spell's own sentence, and the client fetches a spell's text separately from the item that prints it. A book teaching something nobody has cast is the one case where nothing ever asked, so the line was never on the tooltip UI/Scan.lua read. Every potion and trinket read correctly because their spells were already on the machine, which is why this looked like a book-shaped bug.

Fix. aa906b6. Scan.Waiting is the second question: the item's spell id, whether its text is here, and the request for one that is not, which are Syndicator's three calls in Search/CheckItem.lua on this client. Thin in UI/Tip.lua counts a box waiting on that spell as thin and SPELL_DATA_LOAD_RESULT joins GET_ITEM_INFO_RECEIVED on the frame that rebuilds it. A worn slot has no link so one is asked for through GetInventoryItemLink; a trinket you press has a Use line the same as a book does. ns.ItemSpell hands back the id beside the name and nothing else reads it.

Gate. 48-tooltip-arrival.lua, second half, on a book fixture carrying spell 27029 with its text uncached: the first hover draws the client's text without the Use line and asks for the spell, the sentence is in the box after the load fires, and a box that already says what it does does not rebuild for the next spell anybody loads. ./scripts/check.sh at 0 warnings and 0 errors, harness ok.
