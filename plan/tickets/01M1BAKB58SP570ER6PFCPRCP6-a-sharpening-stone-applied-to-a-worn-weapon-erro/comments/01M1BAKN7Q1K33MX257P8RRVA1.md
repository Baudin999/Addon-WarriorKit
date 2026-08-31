---
revision: 1
id: 01M1BAKN7Q1K33MX257P8RRVA1
---

Cause. A stone, an oil, an enchanting scroll or a poison leaves the client holding a spell that is waiting to be told which item it is for. In that state a click on a slot means "that item", and the call that says so is UseInventoryItem. Character/Worn.lua asked no such question: every left click went to PickupInventoryItem, which is the call the client refuses while a spell is pending, so the click errored. The same stone on the same weapon sitting in a bag worked, because the client's own bag button asks first. Baganator does the same thing two lines from its own click handler, which is where the API name was confirmed for this client.

Fix. Worn.Targeting() asks SpellCanTargetItem, then SpellCanTargetItemID, both through the pcall every other client call in that file goes through, because the two clients need not agree that either exists. Worn.Swap routes to Worn.Use when it answers yes. The combat refusal is untouched and still correct: item use is protected, so an insecure click cannot apply anything mid-fight whatever it calls.

Gate. The client stub had no third state, so it grew one: moved.targeting behind SpellCanTargetItem. Section 52 clicks the main hand with it on and asserts the use call was reached and the pickup was not. Checked the gate bites by pulling the fix out: two FAILs, and green with it back in.
