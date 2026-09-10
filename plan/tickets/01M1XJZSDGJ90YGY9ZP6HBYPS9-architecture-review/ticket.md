---
revision: 4
id: 01M1XJZSDGJ90YGY9ZP6HBYPS9
type: epic
status: todo
title: Architecture review
---

The items architecture reviews on 2026-08-29 and 2026-09-02 turned up, the second run
against LCOM over shared module state, a token clone detector, and fan-in and fan-out on
`ns`. None of them is a bug.

Read an item against the code before working it. Item 15 undercounted its sites by five
and item 18 undercounted its closure by half. `ns.db` measured clean, 215 keys with four
read outside the folder that declares them, and file-level LCOM4 is 1 almost everywhere.

The numbers on these cards are the numbers they carried in `todo.md`, kept as labels,
because commit messages reference them and a number that moved would break every one.
