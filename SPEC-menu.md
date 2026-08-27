# SPEC: the /wk window

## Why now

`Core/Menu.lua` puts a WarriorKit button in the client's own Escape menu. That
is the whole of the first half of this piece of work and it is on main. It also
raises the stakes on the second half: until now the only way in was a slash
command, which meant everyone who opened the window had already read something
about the addon. Now a person who has never heard of it can press Escape, see a
button with a name on it and click. What they find has to make sense on its own.

It does not. This spec says what is wrong, with numbers, and what to build
instead.

## What is in there now, counted

Measured against main at the time of writing, by walking the registry rather
than by reading the source.

- 18 entries in the rail, one per registered part.
- 44 sections behind them, reached through a tab strip.
- 134 controls in total: check boxes, steppers, sliders, pickers, key fields,
  text fields and buttons.
- 134 notes, holding 40,268 characters of prose.

One note per control, exactly. That is not a coincidence, it is a habit: every
time somebody added a control they wrote a paragraph next to it explaining why
the control exists. Forty thousand characters is about fifteen pages. The
window is a document with switches embedded in it.

The rail is 118 pixels wide and each entry is 22 pixels tall with 4 between
them, so eighteen entries come to 464 pixels of rail inside a 390 pixel view.
Three of them sit below the fold and nothing on screen says so.

## The three complaints, named precisely

### Lots of text

Notes do three different jobs and the window draws all three the same way.

Most of them explain a decision. `Settings/Feature.lua:66-93` is four notes for
one slider, and three of the four are about why the pixel grid prefers whole
stops. That is true, it is worth writing down, and it belongs in
`docs/README.md`. A person who wants their windows bigger is not asking about
rasterisation.

Some are a live reading. `Feeds/Feature.lua:420` says how many of this client's
loot messages the addon recognises. `Perf/Feature.lua` draws its counters the
same way. Those are numbers, not prose, and they should not be drawn as a
paragraph of body text.

A few are the one sentence the control actually needs, and they are buried in
the other two kinds.

### Settings that do not make sense

Four knobs have been reinvented once per part.

`zoom` is a stepper on Buffs, Feeds, Swing, Meters and the enemy bars. Four of
those five declare their own `LOW_ZOOM, HIGH_ZOOM = 1, 3` at the top of their
own file: `Buffs/Feature.lua:14`, `Feeds/Feature.lua:16`,
`Swing/Feature.lua:13` and `Meter/Feature.lua:15`. Same name, same numbers,
four copies. And separately
there is a `UI size` slider on its own rail entry that runs 0.5 to 3 in
quarters and covers the addon's own windows only. Six size controls, two
different ideas, and no page says which of them owns the thing you are looking
at.

`background` is a slider on Chat and on Feeds, and the same control on Meters is
called `bar opacity`. All three run 0 to 100 in fives and all three declare that
range themselves.

`width` is a stepper on Feeds, Swing, Meters and the minimap, and the ranges are
200 to 520, 80 to 400, 120 to 400 and 120 to 300. Those differ for real reasons.
The labels do not say so, and the minimap's is the only one that admits its unit
by calling itself `width in pixels`.

`rows` is a stepper on Feeds and Meters, and the same idea on the enemy bars is
called `list bars`.

Then there are the labels that are not sentences. `Feeds/Feature.lua:297` builds
`"Collect " .. entry.collects`, so the string in the source ends in a space and
the label only reads correctly once the feed's name is glued on. Charge draws
three steppers for one icon: `icon size`, `world icon size` and
`world icon height`.

### Hard to find what is where

The rail is the registry with a capital letter on it. `Core/Panel.lua:154` is
literally `name:gsub("^%l", string.upper)`. So the top level of the window is
eighteen internal module names, and a new player is asked to guess that the
camera distance is under Comfort, that Blizzard's action bar art is under
Artwork, that the Edit Mode layout is under Interface, and that the window's own
size is under Settings. Three of those four are junk drawers with different
names.

Order is a float on each part and two parts collide: `artwork` and `minimap` are
both `order = 8`, so their relative position in the rail is whatever
`table.sort` felt like.

Section titles repeat their parent. The rail entry `Charge` opens a tab strip
whose second tab is also called `Charge`, because `Charge/Feature.lua:246`
writes a header with the part's own name in it.

And nothing searches. 134 controls behind 44 tabs behind 18 entries, with no way
to type "swing" and be shown the three controls that mention it.

## What the window is for

Three jobs, and the window should be built for these and nothing else.

Turn a part on or off. See at a glance which parts are on. Change one number
when you already know which number you want.

Explaining the addon is a fourth job and the window should stop doing it.
`docs/README.md` is where that lives, it is already good at it, and it can be
read on a second monitor while the game runs.

## The redesign

### 1. A section chooses its own group, and the rail is eight groups

The rail today is one entry per feature because `Core/Panel.lua:213` walks
`ns.features` and adds one. That is the wrong axis. A feature is a folder of
code. A group is what the player was thinking about when they opened the
window.

Change `ui.Header(title)` to `ui.Section(title, group)`. The panel builds a
fixed, declared list of groups, then walks the registry and files each section
under the group it named. A feature can put its sections in two different groups
without a line of code moving between files, which matters immediately:
`UnitFrames/Panel.lua` has three sections and two of them are about your own
frames while one is about enemy nameplates.

The eight groups, in this order, with every section mapped onto one. There are
43 section titles today across 44 `ui.Header` call sites, because Charge writes
one of two headers depending on whether you are a warrior.

**Start here.** Built by the panel, owned by no feature. Covered in point 6.

**Fighting**, 11. Charge key, Charge, Action targeting, Weapon, Marking, Switch
target, Loadouts, Swapping, Buttons, Our own bars, Spell ranks.

**You**, 8. Player and target frames, Swing timer, The Slam window, Missing
buffs, What it watches, Racials, Your own buffs, Placing.

**Them**, 2. Enemy bars, Debuffs on the bar.

**Readouts**, 7. Meters, Breakdown, Loot feed, Combat feed, Chat, People, Voice.

**The screen**, 8. Minimap, Addon buttons, Bar art, Interface layout, Clutter,
UI size, Camera, Errors.

**Chores**, 3. Loot, Vendor, Repair.

**Under the hood**, 4. Performance, What each ticker costs, What is on screen,
Timing.

Eight is more than the six I first drew and the two extra earn their place.
Selling greys is not a screen setting and neither is what a ticker costs, and
folding either into The screen would have rebuilt the junk drawer this whole
section exists to take apart. Nothing here has more than eleven tabs.

`order` on a part stops deciding rail position, because the rail is no longer
made of parts. It keeps deciding tab order inside a group, and it becomes an
integer with a uniqueness check, so `artwork` and `minimap` both sitting on 8 is
a login error rather than a coin toss.

### 2. Notes are deleted and replaced by three capped kinds

`ui.Note` goes. Three narrower calls replace it, and the point of the caps is
that a cap is the only thing that has ever stopped this from growing back.

`ui.Lede(text)` is one line under a section title, at most 160 characters. It
says what the section changes on screen, in the present tense. One per section,
never two.

`ui.Hint(text)` attaches to the control above it, at most 200 characters, and is
drawn in the addon's own tooltip on hover rather than in the column. The column
gets its vertical space back and the sentence is still one hover away.

`ui.Reading(fn)` is a live number or a short state, drawn in the accent colour
on the right of its own row, never wrapped. This is what `Feeds`, `Perf` and the
`Now:` lines in `Settings` become. It is not prose and it is not capped by
character count, but it must fit one line at the narrowest window width, and the
harness measures that.

Budget for the whole window: 44 ledes at 160 and, say, 90 hints at 200 is 25,040
characters, and I would expect the real figure to come in near 15,000 because
most controls do not need a hint at all. Against 40,268 today.

Everything cut moves to `docs/README.md` under the part it belongs to. Nothing
is thrown away. The reasoning in those notes is genuinely good and it is the
only written record of several decisions.

### 3. One switch per part, drawn by the panel, shown in the rail

Most parts have a boolean that decides whether they draw anything, and each one
draws its own check box with its own wording: `show the row`, `show the icon`,
`Show the meters`, `Show the swing bars`, `show enemy bars` and
`draw the WarriorKit chat window`.

A part declares it instead:

```lua
ns.Register({
    name = "meters",
    switch = { key = "meterShown", label = "the meters" },
    ...
})
```

The panel draws it, in the same place on every page, above the first section.
The rail draws a dot next to any group holding a part that is on. Now you can
see what the addon is drawing without opening 44 tabs, which is the single thing
the window has never been able to answer.

The wording stops being each author's choice, which is most of why those six
labels are six different shapes.

### 4. Four kit calls for the four repeated knobs

`ui.Zoom(get, set)` with no label and no range, because there is one range and
it is 1 to 3. Deletes four copies of `LOW_ZOOM, HIGH_ZOOM`.

`ui.Opacity(label, get, set)` with no range, because there is one and it is 0 to
100 in fives. Deletes three copies. The Meters control is renamed from
`bar opacity` to `background` so all three match, since all three do the same
thing.

`ui.Size(label, low, high, step, get, set)` for any pixel measurement. The range
stays per caller, because those ranges really do differ, but the widget labels
the unit itself, so `width in pixels`, `bar width, in pixels` and `frame width,
in pixels` all become `width` and the widget says `px` after the number.

`ui.Count(label, low, high, get, set)` for rows and bars. `list bars` becomes
`rows`.

Charge's three icon steppers become two: `icon size` for the button, and one
`size` and one `height` inside a section called `The icon over the mob`, where
`world` no longer has to be in every label because the section title says it.

### 5. Search

A field in the title bar, focused when the window opens. Typing filters, and the
result is a list of rows reading `group / section / label`. Clicking one selects
the group, selects the tab and flashes the row.

Links rather than the live controls, because a control is built into one
section's stack and cannot be in two at once. A link is honest anyway: it
teaches you where the thing lives, so the second time you go straight there.

This needs one new thing from the kit: every row records its label, its section
and its group into an index as it is built. That index is also what the gates
below read, so it pays for itself twice.

Search matches the label, the section title, the group name and the part's slash
word, so typing `swing` finds the swing controls and typing `skin` finds the
frame controls that `/wk skin` drives.

### 6. Start here

The first group, and what the window opens on the first time it is ever opened.
After that it opens on whatever you had last.

One page. Every part's switch from point 3, in one column, each with its lede.
Nothing else, no numbers, no ranges. Turn things on, look at your screen, come
back.

This is the page the Escape menu button now leads to, and it is the answer to
"easier for new players" that a rail of eighteen module names cannot be.

### 7. Naming rules

A rail entry names something you can see on the screen, not a folder in the
repo. A section title does not repeat its group's name. A control label is lower
case, starts with a noun you can point at or a verb you can do, and never ends
in a space. A label is not built by concatenation unless the whole label,
including the glued part, is in the index.

That last one exists so search can find `Collect enemy damage` when the source
says `"Collect " .. entry.collects`.

## What gets deleted

The zoom stepper on Buffs, Feeds and Meters. Three controls. Those three widgets
are read between fights rather than during one, `UI size` already scales the
addon's own windows, and the argument for a private zoom is that a thing you
read mid swing has to stay exact at a size you chose. That argument covers the
enemy bars and the swing timer and it does not cover a loot feed.

The `Artwork`, `Interface` and `Settings` rail entries, as entries. One check
box, three controls and one slider respectively. Their sections survive inside
The screen.

`ui.Note`, `ui.Text` and the first-section rename in `Core/Panel.lua:171-183`.
That rename exists only because the first section had no title of its own; once
`ui.Section` always carries one, it goes.

Nothing else. 134 controls go to 131, and that is deliberate: the complaint is
about finding things, not about having them. A settings window that answers a
question you have is worth more than a small one that does not.

## What the numbers should come out at

| | now | after |
|---|---|---|
| rail entries | 18 | 8 |
| section call sites | 44 | 46 |
| controls | 134 | 131 |
| prose blocks | 134 | about 130, capped |
| prose characters | 40,268 | under 16,000 |
| rail pixels against a 390 pixel view | 464 | 208 |

Sections go up by two: Start here is a page, and Charge's icon controls split
into a section of their own. The rail fits without scrolling for the first time.

## Gates

Three layers, as everywhere else in this repo: a harness section, the pre-commit
hook and `check.sh`.

`scripts/harness/sections/16-options-window.lua` already walks every rail entry,
every tab and every row and measures what came out. It grows six assertions.

Every section names a group, and every group named exists. A section that names
no group is a login error, not a section that quietly lands in a default.

Every lede is at most 160 characters and every hint at most 200, measured on the
string the feature actually produced rather than on the source.

No group holds two sections with the same title, and no section title equals its
group's name.

No control label ends in whitespace, and every label in the index is non-empty
after any concatenation the feature does.

Search finds every row: for each of the 131 controls, its own label typed in
full returns at least that row. This is what stops a control being added to a
page and left out of the index.

Every part with a boolean switch in its defaults declares it under `switch`. The
allow-list for parts that legitimately have none carries a reason per entry, the
same shape as every other allow-list here.

`check.sh` gets the cheap textual half, because a grep runs on a file that does
not load: `ui.Stepper("zoom"` and `ui.Slider("background"` and their friends
fail, with the message naming the kit call to use instead.

## Order of work

Each of these lands on main green, in its own worktree, and each is useful on
its own.

1. `ui.Section` with a group, and the eight-entry rail. The largest change,
   and the one everything else sits on. No prose moves yet.
2. The index and search. Needs the kit change and nothing else.
3. `ui.Lede`, `ui.Hint`, `ui.Reading`, and the caps. The prose pass happens part
   by part, and `docs/README.md` grows in the same commit that shrinks a page.
4. `switch` on the registry, the switch row, the rail dots and Start here.
5. `ui.Zoom`, `ui.Opacity`, `ui.Size`, `ui.Count`, and the three deletions.
6. The gates. Written alongside each step rather than after all of them, because
   a gate added afterwards is a gate written against whatever the code happened
   to end up doing.

## What this spec does not decide

The slash commands do not change. Every word keeps working, `/wk` on its own
still opens the window, and `Core/Command.lua` does not appear anywhere above.
Those words are muscle memory and they are sitting inside people's macros.

The theme does not change. Colours, fonts, the pixel grid and the window chrome
are all fine and none of them is what anybody complained about.

Nothing on the game screen moves. This is a spec about one window.
