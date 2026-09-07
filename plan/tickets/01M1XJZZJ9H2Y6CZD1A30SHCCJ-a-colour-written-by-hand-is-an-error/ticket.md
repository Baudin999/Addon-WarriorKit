---
revision: 1
id: 01M1XJZZJ9H2Y6CZD1A30SHCCJ
type: feature
status: todo
title: A colour written by hand is an error.
parent: 01M1XJZYMA3V0YPE58CH5H938J
labels: [item-81]
---

`scripts/check.sh` refuses a fractional colour triple outside
`src/UI/Theme.lua` and `src/Unit/Color.lua`: a table constructor of three or
four numbers with a fraction in it, and the same shape passed to
`SetColorTexture`, `SetTextColor` or `SetVertexColor`. A fraction, not any
triple, because `SetVertexColor(1, 1, 1)` is a reset and
`SetColorTexture(0, 0, 0, 0.55)` is a shadow.

Whatever item 80 leaves is allow-listed by file with a one-line reason each,
in the shape the eight rules above it use, and the length of that list is a
ceiling in `scripts/ratchet.lua`. A file that clears its last literal comes
off the list in the same commit. Error, not warning: a colour typed at a
call site is invisible until two windows are open side by side.
