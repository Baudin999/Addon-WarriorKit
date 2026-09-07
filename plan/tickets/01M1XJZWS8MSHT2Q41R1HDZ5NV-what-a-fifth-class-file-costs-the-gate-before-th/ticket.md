---
revision: 1
id: 01M1XJZWS8MSHT2Q41R1HDZ5NV
type: task
status: todo
title: "What a fifth class file costs the gate, before the fifth one lands."
parent: 01M1XJZW5CFY7JB9WKRNJC94H0
labels: [item-54]
---

`scripts/check.sh:1354` reads the class tokens off `Class/*.lua` and runs
the harness once per shape: thirteen runs today, twenty-eight at nine
classes, and the harness is the slowest thing in `check.sh`. Measure one run
before item 56 lands and again after.

HUNTER at `scripts/check.sh:1377` is the proof that the class-agnostic parts
stand up with nothing registered, and item 56 eats it silently. Replace it
in the same commit with a token no class file can claim, and say in the
comment above the loop that the token is deliberately not a class.
