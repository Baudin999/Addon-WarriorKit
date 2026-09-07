---
revision: 1
id: 01M1XJZZVREHXM4B6NDVMPRG3Z
type: task
status: todo
title: "`/wk style`, the page that draws the palette."
parent: 01M1XJZYMA3V0YPE58CH5H938J
labels: [item-82]
---

`src/Settings/Style.lua`, registered by `src/Settings/Feature.lua`, built on
first open. Not in `src/UI/`, where no file registers a feature.

It draws itself out of the tables rather than describing them: every
`UI.Color` entry as a swatch with its key, every `UI.Metric` as a rule of
that many pixels with its number, the three font sizes in the shipped face,
`UI.Quality` as eight names in eight colours, and a wash, a badge, a chip, a
feed row and a readout row side by side. Side by side is the feature:
whether the feed row and the sheet row look like one addon is a thing eyes
answer in a second and a file never answers.

A page with no settings on it. The day a colour on it is editable is the day
`UI.Theme`'s header stops being true. After items 78 to 81.

## Deliberately not on this list

- `src/Progress/Progress.lua:70` and `src/Quests/Client.lua:43` hold the same
  four-line probed call. Each is written against its own returns, and a prober
  in Core would be a call every part reaches through rather than a seam.
- `src/UI/Feed.lua`, `src/UI/Log.lua` and `src/UI/Stack.lua` each open by saying
  why they are not one of the others, and each argument holds.
- `src/Class/*.lua` files repeat each other because each is a registry of one
  class's spells. The repeat is the table shape, not the data.
- `UI.Quality` at `src/UI/Theme.lua:100` and `Color.power` at
  `src/Unit/Color.lua:355` are two palettes that happen to be the same size.
- Ten parts open a placeable HUD frame with the same four calls, `CreateFrame`,
  `ns.UI.Adopt`, `ns.UI.Unit`, `ns.UI.Placeable`. That is what a constructor
  already looks like.
- Stripping comments from the shipped files. All 230 compile in 26 ms in stock
  Lua 5.1 with the comments in, so a build step buys under 10 ms a login.
- Chasing a serialise-on-logout cost. Chat history, quest drops, dungeon drops,
  breakdown spells and loadouts are all capped, most at 400.
- Item 93, scoping the tracker on where a quest's next open objective stands. It
  is the better answer and it costs hundreds of coordinate transforms per quest
  against a memo one quest deep. The tracker scopes on the log header, item 96's
  pin is the escape hatch, item 99 gates the walk to its one caller.
- Most of Narcissus: its photo mode is nine files and the reason it exists, and
  its AFK screen, achievement pages, minimap button, tooltip, guide and two
  databases are its largest folders. What was taken from it is items 60 to 72.
- Narcissus parking the whole Blizzard UI off `UIParent` while the sheet is up,
  `Main.lua:98-145`. A frame taken off `UIParent` and put back is a frame whose
  scale, strata and parent this addon then owns, and
  `src/UnitFrames/Blizzard.lua` already carries what that costs for one window.
- Narcissus drawing its stats as a radar chart, `Narci_RadarTemplate` in
  `Narcissus.xml:136`. Nobody remembers last week's pentagon; the column of
  numbers beside the figure answers the question the chart is drawn for.
