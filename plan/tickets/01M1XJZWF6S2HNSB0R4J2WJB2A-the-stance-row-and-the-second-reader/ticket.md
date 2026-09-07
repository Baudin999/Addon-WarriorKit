---
revision: 1
id: 01M1XJZWF6S2HNSB0R4J2WJB2A
type: feature
status: todo
title: "The stance row, and the second reader."
parent: 01M1XJZW5CFY7JB9WKRNJC94H0
labels: [item-53]
---

The reader is `stance`, in the table at `src/Standing/Standing.lua:56`, and
every shapeshifting class uses it. It walks `GetShapeshiftFormInfo` and
matches each slot's spell name against the bar rather than indexing into it,
which is the correction to item 52's guess: `GetShapeshiftForm` answers a
position on a bar holding only the forms you have learned. A slot matched
and missing draws empty, the way an empty totem slot already does.

A stance fills three of the five reader values, and
`src/Standing/Row.lua:261` already reads the other two as `expires[index] or
0` and `span[index] or 0`, so `Row.lua` does not change.
`GetShapeshiftFormInfo` and `GetNumShapeshiftForms` are not in the harness;
they go beside `GetShapeshiftForm` at
`scripts/harness/client/05-quests.lua:691`, not in `03-player.lua`.

The plan goes in `src/Class/Warrior.lua` beside `forms`: three slots in that
file's order, `kind = "stance"`, `word = "stances"`, `one = "stance"`.

`src/Standing/Feature.lua:105` writes its slash words at file load, before
the client will say what class this is, so every class's word lives in that
table: `forms`, `aspects`, `poisons`, `auras`, `demon`. That is the one file
outside `Class/` a new class edits, and the fix is a gate: hold every `word`
and `one` a plan registers against the table, and fail on a table word no
plan claims.
