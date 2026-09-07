---
revision: 1
id: 01M1XJZT13XYG6HMR6VAZ14RX5
type: feature
status: todo
title: `Core/Menu.lua` registers a feature from inside Core.
parent: 01M1XJZSDGJ90YGY9ZP6HBYPS9
labels: [item-22]
---

`src/Core/Core.lua:8` promises Core knows nothing about any feature, and
twenty-five parts keep that by registering from `<Folder>/Feature.lua`.
`src/Core/Menu.lua:275` does not, and wants a folder like the rest. Last,
after 20 and 26 have proved the registry needs no help from Core.
