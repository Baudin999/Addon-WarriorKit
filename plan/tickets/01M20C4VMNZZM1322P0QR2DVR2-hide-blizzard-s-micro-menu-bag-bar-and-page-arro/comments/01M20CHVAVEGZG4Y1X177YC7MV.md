---
revision: 1
id: 01M20CHVAVEGZG4Y1X177YC7MV
---

Second pass, 80166c4. Cause. The arrows have no global name on either client. Blizzard_ActionBar/Classic/MainActionBar.xml declares ActionBarPageNumber as a parentKey on MainActionBar with Text, UpButton and DownButton inside it, on classic_anniversary and on classic_era both. ActionBarUpButton, ActionBarDownButton, MainMenuBarPageNumber and SlidingActionBarTexture0/1 are the pre-rewrite spelling and resolve to nil, so the walk skipped five names in silence. Fix. ART_KEYS, one entry, written off the XML; the key is left on the owner because MainActionBar's mixin writes to self.ActionBarPageNumber unguarded in four places. The five dead names are gone. Gate. check.sh at 0 and 0, harness ok. Still open: MainActionBar.EndCaps.LeftEndCap and .RightEndCap are the gryphons on this client and are also reached by parentKey, so the two MainMenuBar*EndCap globals this file still names may be a second bar nobody sees. Nobody has reported a gryphon, so it is not chased here.
