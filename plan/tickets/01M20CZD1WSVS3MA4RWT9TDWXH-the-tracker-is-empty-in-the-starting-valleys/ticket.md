---
revision: 1
id: 01M20CZD1WSVS3MA4RWT9TDWXH
type: bug
status: todo
title: The tracker is empty in the starting valleys
---

A new character sees nothing at the top left. The addon's own tracker
(`src/Quests/Column.lua`) is on, the quests are in the log, and the column
hides itself anyway.

Cause. `Column.Quests()` keeps a quest when `zone.name == ns.QuestHere.Now().name`,
which is the client's quest log header string against C_Map's name for the map
you are standing on. In every starting area those two disagree. The client files
the first quests under the subzone: Northshire Valley, Coldridge Valley,
Deathknell, Shadowglen, Valley of Trials, Camp Narache, Sunstrider Isle. Vanilla
has no map of its own for any of them, so `GetBestMapForUnit` answers with the
parent zone, Elwynn Forest. Nothing matches, `Column.Paint` counts zero and
`frame:SetShown(count > 0)` takes the column off the screen. The same is true of
every subzone in Questie's `subZoneToParentZone`, so Darkshire in Duskwood and
Kharanos in Dun Morogh miss too, not only the level 1 valleys.

Fix. Accept a zone whose area sits under the area you are standing in.
`ns.QuestHere.Now()` already carries `area`, and Questie's
`ZoneDB:GetParentZoneId(areaId)` walks a subzone up to its zone. What is missing
is the other direction: the header is a name and the join wants a number. The
one door is Questie's `l10n.zoneLookup`, an areaId to localised name table, read
once into a reverse lookup. With no Questie, fall back to the exact name match
that is there now.

Gate. `scripts/check.sh` at zero, and a harness case per starting race with the
header set to the subzone and the map to the parent.
