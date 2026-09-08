---
revision: 1
id: 01M20AK0TP8SFZ2ZMFMBFQQXR1
---

Landed at 5947336, check.sh at 0 warnings / 0 errors and the harness green.

Size. Quests/Window.lua WIDTH, HEIGHT 810,520 -> 1000,640. LIST and PAY are untouched, so the whole 190 by 120 goes to the middle column and the zone comes out about 502 by 335 at rest.

Zoom. UI/Chart.lua's Clicks split into Grip and Taps. Grip is the mouse, the drag and the pan tick and goes up on every board unconditionally; Taps is OnMouseUp and still goes up only where onClick or onOut was passed. Board:Tap and Board:Back already refuse without a handler, so the quest log's board getting the mouse costs it nothing on the button. Quests/Window.Drag is the harness handle, matching Map/Window.Drag.

Icons. ns.QuestieIcon in Core/Core.lua takes a number, a name or a path. usedIcons is read before icons on purpose: they differ exactly on the icons the player has replaced in Questie's options. Quests/Where.lua threads the resolved path down Scatter and Mark, and the dedupe step key now carries the icon so a mob and a chest in the same five pixels stay two dots. Points that resolve nothing keep kind and draw the old coloured square.

Fixture correction worth knowing about. The spawn list entries in harness/client/12-questlog.lua carried Type = "monster", which is a field Questie has never put on one; the real field is Icon and it is a number. Fixed, and the Questie global in 05-quests.lua now carries icons, usedIcons and the ICON_TYPE numbers, with slay deliberately replaced so a reader that took the stock path out of icons is caught.

Split. 47-quest-log.lua was 878 against a ceiling of 823 and the ceiling does not go up. The map's third of it is 47-quest-map.lua, registered in runner.lua between 47-quest-log and 47-quest-pin so the log state it reads is unchanged. 05-quests.lua is a new key on the line budget at 832 with its reason.

Not done: the arrow and the corpse are still the client's own art rather than Questie's, which is right -- they are the client's marks and every player already reads them.
