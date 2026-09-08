---
revision: 1
id: 01M208VZCR8TZRA5ZFCJ06GBF9
type: task
status: done
title: "The quest log's map is bigger, zooms and wears Questie's icons"
---

Three things about the map behind the quest log's middle column, asked for
together because they are one complaint: the picture is too small to read.

**The window is bigger.** `Quests/Window.lua` holds `WIDTH, HEIGHT = 810, 520`
and the middle column is whatever is left after the 250 wide list and the 200
wide reward column. The map is what gets the difference, so the window grows and
the two fixed columns do not.

**The picture pans.** `UI/Chart.lua` hangs its mouse handlers only where the
caller passed an `onClick` or an `onOut`, on the argument that enabling the
mouse stops the window under it seeing the drag. The quest log passes neither,
so its map zooms on the wheel and then has no way to move: at six times the box
is looking at a sixth of the zone and the only way across it is to zoom out and
back in. The world map has the drag because it navigates. Split the mouse and
the drag off the two click handlers so every board gets the drag and only a
caller with a handler gets the click.

**The dots are Questie's own marks.** `Quests/Where.lua` hands the board points
carrying a `kind`, and `UI/Chart.lua` draws those as a coloured square with a
wash behind it. The world map next door draws Questie's own icons, because it
reads them off Questie's frames. The quest log builds its points from the
database instead, so it has no texture to carry -- but the icon Questie would
have drawn is on the data: a live `spawnList` entry carries `Icon` and an
`ObjectiveData` row carries `Type` and an optional `Icon` override. Resolve
those against Questie's own icon table and the same marks come out.

Questie names its icons two ways and the addon ships for both: v11 keys
`Questie.usedIcons` by a number off `Questie.ICON_TYPE_*`, v6 hands the path
around as a global string. That is a third door in `Core/Core.lua` beside
`ns.QuestieAPI` and `ns.QuestieProfile`, because `scripts/check.sh` refuses a
`type(_G.` probe anywhere else.

The coloured square stays as the fallback. Questie absent, not compiled, or a
version whose icon table moved is a map drawn the way it is drawn today rather
than a map with nothing on it.
