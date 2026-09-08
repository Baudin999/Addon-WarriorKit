---
revision: 1
id: 01M20BB87C9S7FF0PGRX2GE228
type: task
status: done
title: The hand-in mark is grey until the quest is finished
---

Follow-up to 01M208VZCR8TZRA5ZFCJ06GBF9, which put Questie's icons on the quest
log's map. The hand-in came out as the gold question mark on every quest,
finished or not.

That is wrong in the one way the map is meant to be right. Questie draws nothing
at the hand-in until every objective is done; this map draws it early on
purpose, because knowing the person is on the way back rather than across the
zone is worth having while you are still killing things. Gold says walk there
now, and walking there now wastes the trip.

Questie has the art and the rule. `QuestgiverFrame.determineAppropriateQuestIcon`
picks `incomplete` for an NPC whose quest you hold and have not finished and
`complete` for one you have, which is the grey question mark the client itself
has drawn over unfinished business since the first build.

Whether the quest is done comes off the quest object's own `IsComplete`, which
is the one shape both versions agree on: v11 assigns `QuestieDB.IsComplete` onto
the quest as a method, v6 writes the method out on the quest itself, and both
answer 1, -1 or 0. Every doubt answers unfinished, so the mark is grey.
