---
revision: 1
id: 01M1BBYKRPVKC5T5KPP7M43FNM
---

Found it, from the screenshot. The dialog is ADDON_ACTION_FORBIDDEN: "WarriorKit has been blocked from an action only available to the Blizzard UI." That names a protected action, not a wrong call, which is why reading the client's own handler did not explain it: PaperDollItemSlotButton_OnClick may make that call because it is the client's own frame, and this page may not, whatever it calls. UseInventoryItem is protected, and so is finishing a spell the client is holding until it is told which item it is for, which is what a stone, an oil, a scroll or a poison is.

Fix. The squares are SecureActionButtonTemplate now. The right button carries type2 macro and macrotext2 "/use <slot>", written once at build, so taking a piece off and firing a trinket run on the path a macro runs on, in a fight as well. The left button is armed with the same line in PreClick only while Worn.Targeting() says a spell is waiting, and disarmed in PostClick, so a left click at rest is still the swap and a left click in a fight cannot fire a macro armed before it. It is the same "/use 16" every sharpening stone macro in the game already carries.

Second defect in the same square, and probably why right click never appeared to do anything: UI.PassCamera handed RightButton and MiddleButton straight through to the camera while the button was registered for RightButtonUp. Drawn, hovered and dead. Off these squares now, and the harness asserts it stays off.

Gate. The stub learned PreClick, which Region:Click never ran, and SetPassThroughButtons, which fell through to a no-op. Section 52 reads the attributes rather than watching for a call, because a call is the thing that must not happen. Pulled the arming and put PassCamera back to check it bites: three FAILs.
