---
revision: 1
id: 01M20F4JFCSPPYGAF4W9FJPFB5
type: task
status: todo
title: The notice about what else is running
---

This addon draws the whole interface, and a player arriving from a folder of
bag addons and damage meters gets two of each with nothing in the game saying
why. Both addons work, the screen is a mess, and the player reads that as this
addon being broken.

So it says so, once, on the first login where there is something to say.

`src/Core/Replaced.lua` holds the list of what it draws over, keyed by folder
name, and the phrase that says what each one draws. `ns.AddOnRunning` in
`src/Core/Core.lua` is the door: outside Core a file does not probe the client
for a call it means to make, and the addon list is spelled two ways across
these builds.

Auctionator, RECrystallize and the other scanners in `Feeds/Auction.lua` are
deliberately absent from the list. This addon reads them for the price on a
loot row, and telling somebody to turn one off would take a number out of its
own tooltip. Questie and DialogueUI are named in the notice as the two worth
keeping.

`replacedTold` is a record rather than a preference, so it is in Core's KEPT
list and `/wk defaults` steps over it. `/wk replaces` and the button on the
Other addons page are the two ways back to the notice.
