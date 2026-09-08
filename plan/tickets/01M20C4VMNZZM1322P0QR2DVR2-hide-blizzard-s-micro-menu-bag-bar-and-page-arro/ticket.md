---
revision: 1
id: 01M20C4VMNZZM1322P0QR2DVR2
type: task
status: todo
title: "Hide Blizzard's micro menu, bag bar and page arrows at login"
---

A fresh install still shows three pieces of the client's own bottom bar under
everything this addon draws: the micro menu, the bag bar with the key ring on
it, and bar 1's page arrows with the page number beside them. Getting rid of
them meant Edit Mode, which is a thing nobody should have to find.

Two of the three had no switch at all. Core/BlizzHide.lua named eleven things
and none of them was a button standing on MainMenuBarArtFrame, and
Bags/Blizzard.lua takes the nine calls that open the client's bags without
touching the six buttons on the bar those calls used to be reached from.

The third had a switch that did not hold. Artwork/Artwork.lua names
ActionBarUpButton, ActionBarDownButton and MainMenuBarPageNumber and hides them
with ns.Strip, which loses to SetShown, which is the hole Core/Attic.lua's
header was written about.

Fix. Two switches in Core/BlizzHide.lua, hideBlizzMicroMenu and
hideBlizzBagBar, twelve micro button names and six bag button names, both
defaulted on with the feature that draws the replacement: the micro menu in
Artwork/Feature.lua, which owns the rest of that bar, and the bag bar in
Bags/Feature.lua beside bagsHideBlizz. The buttons and not the frame they stand
on, because MainMenuBarArtFrame carries the micro menu, the bag bar and bar 1's
twelve, so a switch that took the frame would be three switches in one label.

Artwork/Artwork.lua's named regions go through ns.Attic.Vanish instead of
ns.Strip. The attic refuses a texture, so the endcaps and the sliding textures
fall back to the strip inside the same call and the list does not have to know
which of the two this client made each name. Core/BlizzHide.lua's sweep then
keeps the arrows down for free.

Gate. ./scripts/check.sh at 0 warnings and 0 errors, harness ok.

Left open. MainMenuBarPageNumber is a FontString and the attic will not take
one, on the rule in Core/Attic.lua's header that moving a region takes it out
of its frame's draw order rather than off the screen. It keeps ns.Strip. If the
"1" is still on the screen after this, `/wk hide probe` says so and the answer
is a handle for a font string rather than a fourth name in a list.
