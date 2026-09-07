---
revision: 1
id: 01M1XJZSQ9RFZCH8SS8YRETP24
type: feature
status: todo
title: "`EachTexture` into Core, beside `ns.Strip`."
parent: 01M1XJZSDGJ90YGY9ZP6HBYPS9
labels: [item-20]
---

`src/Artwork/Artwork.lua:59` and `src/UnitFrames/Art.lua:248` are the same
pcall-guarded walk over a frame's texture regions, differing only in Art's
`keep` set. It goes beside `ns.Strip`, `ns.Unstrip` and `ns.Blocked`, the
three calls it exists to feed.
