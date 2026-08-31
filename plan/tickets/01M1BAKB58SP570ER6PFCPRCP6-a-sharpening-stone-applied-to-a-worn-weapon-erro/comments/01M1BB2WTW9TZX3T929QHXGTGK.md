---
revision: 1
id: 01M1BB2WTW9TZX3T929QHXGTGK
---

Wrong cause, reverted. Pulled this client's own handler rather than reasoning about it: Gethe/wow-ui-source, branch classic_anniversary, Interface/AddOns/Blizzard_CharacterFrame/Vanilla/PaperDollFrame.lua. PaperDollItemSlotButton_OnClick is left button to PickupInventoryItem, right button to UseInventoryItem, and the file does not mention SpellCanTargetItem anywhere. With a spell waiting for an item the pickup call is what points it at that item; the client does this below Lua, which is why its own sheet asks nothing first. Character/Worn.lua already made exactly that call, so the fix was a no-op at best and a divergence at worst, and the Baganator line quoted in the previous comment was its own refresh notification, not the applying call. Everything from that attempt is out: Worn.Targeting, the routing, the stub state and the section 52 block.

Still open, and the click path is now provably identical to the client's own, so the cause is somewhere else. Blocked on the error text: no BugGrabber or Swatter installed, Logs/FrameXML.log holds only a stale 26 August load line, and the muted-error list in Comfort/Errors.lua is session-only and saves nothing.
