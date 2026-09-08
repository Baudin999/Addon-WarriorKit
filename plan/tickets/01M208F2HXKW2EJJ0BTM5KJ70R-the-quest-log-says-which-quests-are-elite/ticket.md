---
revision: 1
id: 01M208F2HXKW2EJJ0BTM5KJ70R
type: task
status: doing
title: The quest log says which quests are elite
---

The left column drew every quest as `[20] Name` and the line under a quest's
title never said "Elite". A log you cannot scan for elite quests is a log that
sends you to a camp you needed a group for.

The cause is one client call. `GetQuestLogTitle`'s third return on 2.5.6 is the
suggested group size, a number, and never the word: see the eight-value unpack
in `src/Quests/Client.lua:140` and Questie's own reads in
`Modules/Quest/QuestieQuest.lua`. `Tagline` in `src/Quests/Window.lua` had a
branch for a string in that slot which this client can never take.

`Quests/Where.lua` already reads the tag off Questie and its own header names
three boxes that draw it: the map marker hover, the creature hover, and "the
line under a quest's name in the log". Only the first two were ever wired.

Fix. `Row` asks `Where.Tag` when the column is built, which warms Questie's
cache, and `Label` puts a "+" inside the brackets for an elite quest, the same
suffix `src/Unit/Level.lua` puts on an elite mob's level. `Tagline` reads the
word back and draws it beside the suggested group size, because a party of five
and an elite camp are two different facts.

Gate. `scripts/harness/sections/47-quest-log.lua` matches `[20+] The Missing
Diplomat` exactly, and quest 204 with no tag is the control.
