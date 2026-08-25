# Changelog

## 1.7

### Three chores the client makes you do by hand

A ninth part, `Comfort`, one rail entry in `/wk` with a tab per chore. All three
are on by default, because every one of them is something you would otherwise do
every few minutes and off is not a state anyone would choose to start in. The
implementations are Leatrix Plus's, which is loaded on both of these clients and
is what proves every API involved.

**Fast loot.** The client's auto loot opens the loot window and then takes one
slot per frame, which is where the pause over each corpse comes from.
`LOOT_READY` fires before any of that, so the corpse is emptied there and the
window never draws. It runs only when auto loot is what your click asked for, so
a shift-click to open the window still opens it, and it is throttled to 0.3
seconds because the event fires again as each slot clears.

Under master loot only the slots below the threshold are taken. `LootSlot` on a
slot at or above it does nothing if you are not the master looter and quietly
assigns it to yourself if you are, and an addon should not do that on your
behalf. Where the client names no loot method at all the corpse is still emptied
solo and the job is handed back to the client in a group.

**Selling trash.** Grey items go at every merchant, and holding shift as you open
one skips that visit. Only grey, and only what a vendor will pay something for.
An item the client has not cached yet is left alone rather than sold on a guess,
and asked about again a fifth of a second later.

The sweep is a ticker rather than a single pass, because a sale is not instant:
the slot locks, the server clears it, and only then does the item leave the bag.
It repeats until a pass finds nothing left, backstopped at 25 passes, and it
stops early on the two vendor refusals worth naming. What it made is the
difference in your purse across the sweep rather than the sell prices added up,
which is the number that is still right when a vendor refuses something halfway
down the list.

The safety is the point. `UseContainerItem` sells a bag slot while a merchant
window is up and *uses* it when one is not, so the same call that sells your
greys eats your food and equips your weapons anywhere else. Every path into it is
behind a check that the window is still open, and the harness models the
difference: its stub sells with the window up and destroys with it down, so a
sweep that forgets to look fails the run rather than passing it.

**Max camera zoom.** `cameraDistanceMaxZoomFactor` goes to 4.0 instead of the
1.9 the client ships. The CVar is read straight back after it is written, so a
client that clamps reports what it clamped to in `/wk status` and in the panel
rather than being taken at its word. Off hands the CVar back at the client's own
default. It is written at every entry to the world rather than once at login,
because the CVar is the client's and anything that puts it back would otherwise
leave the setting saying one thing and the camera doing another.

### /wk destroy, for quest items you are finished with

Quest items for quests you have completed sit in your bags forever. Most cannot
be sold, so the vendor sweep is no help and the only way out is to destroy them.
`/wk destroy` opens a small window that shows one at a time: the item, the quest
it came from, a destroy and a skip.

The client will tell you an item is a quest item and will not tell you which
quest. There is no API for it. So this reads Questie's item database, which
carries the quest an item starts and every quest that wants it, and without
Questie the window says so and offers nothing rather than listing every quest
item in your bags.

Three things are never offered. An item that starts a quest you have not
provably finished, because starters look exactly like orphans and destroying one
loses a chain you never knew existed. An item tied to a quest in your log. And
anything the database has never heard of. What is left is sorted with the certain
ones first, and an item whose quest is still out there to pick up says "destroy
anyway" on the button rather than "destroy".

Four guards stand between the press and the delete: the slot is re-read against
the card, the item is picked up and the cursor is asked what it is really
holding, `DeleteCursorItem` is probed and pcalled because nothing installed on
either client calls it, and a 0.4 second debounce stops a double click landing on
the card that replaced the one you meant. The queue is rebuilt on every press
rather than advanced, because bags move under an open window.

None of this can know about repeatable quests, which never flag as completed, or
about a chain dropping part three's item while you are on part one. That is why
it asks instead of acting, and the panel tab says so above the button.

### Gates

`Comfort/Vendor.lua` names both of its ticker functions in check.sh's `HOT`
list, so the sweep is held to the same no-unguarded-writes, no-allocation rule
as the other four tickers. The harness gained a merchant, a corpse, a quest log,
a model of Questie, a cursor and two more bags, and asserts the negative cases:
a sweep that loses its window moves nothing, master loot leaves the master
looter's slots alone, both settings unregister their events rather than branching
inside a handler the client still calls, a stale clutter card never reaches the
cursor, a cursor holding the wrong item is not deleted, a client with no delete
call refuses, and an empty Questie module is not taken for a working database.

Ten mutations were applied to check those assertions bite, and one did not. The
"slot moved under the card" test was being caught by the cursor check rather than
by the slot re-read it claimed to cover, so both guards passed with the first one
deleted. The harness counts pickups now, which separates them: a stale card that
reaches a pickup means the first guard is gone even though the second one held.

The rail order had two parts sharing `order = 8`, which left `table.sort` to
decide between them. Perf and EditMode now have their own.

### The target's gauge, and the row of icons in it

Two bugs on the target frame, both of them the fit from 1.6 meeting something
the client measures off the frame's rectangle.

**The colour.** The target's health bar drew at 28 percent of its own colour at
any health, which on a tan warrior is the grey-brown of a corpse. The spent
track was a texture on our rail, one frame level under Blizzard's bar, and 1.6
had already written that level explicitly after the same bug appeared once
before. Both clients took the write. The target frame did not keep it: its
rails came out level with its bars, a tie goes to whichever frame was built
later, which is ours, and a 20 percent track at nine tenths alpha over the fill
is 28 percent. The player frame, one line of the same code away, was correct.

So the order is no longer between two frames. The spent track and the heal
slice are regions of Blizzard's own bar now, on the two lowest BACKGROUND
sublevels, and the fill is on ARTWORK above both. Inside one frame the layer
decides and there is nothing for a client to disagree with. Nothing else moved:
the rails still carry the geometry, the bars are still pinned to them corner to
corner, and the heal slice is still pinned to the fill texture, one boundary
crossing further out because its width is now written in the bar's units.

**The aura row.** The client hangs the target's buffs and debuffs off the
frame's bottom left corner and lifts the first icon of each row by the height
of the art that hangs under the bars on a frame 100 units tall. Fitting the
frame to the block took that art away and the lift then put the icons inside
the gauge.

The icons are not moved, and that is the design rather than a shortcut. Every
one of them is a child of a secure unit button, so an addon may only anchor one
out of combat, and the client re-anchors the head of each row on every aura the
target gains or loses. A row placed by this addon would be back in the gauge on
the first refresh of the first pull and stay there until it ended.

What moves is the edge the client measures from. The target frame is fitted to
the block plus the lift, so its bottom edge sits one lift below the block and
the client's own arithmetic lands the row against the block's bottom. It holds
in combat because nothing has to be written in combat. The lift itself is
measured rather than assumed: both clients keep it in a local, but the anchor
the client wrote on the icon carries the number, so the first target with an
aura settles it and a `UNIT_AURA` on the target is what catches that moment.
Until then there is no tail and the frame is the block, and a client that hangs
its row below the frame rather than above it measures as no lift and gets no
tail either.

A tail is a strip of frame under the block and a strip of frame takes clicks,
so `SetHitRectInsets` pulls the mouse region back off it, the Edit Mode
selection is pinned to the block rather than to the frame, and target of target
parks under the block rather than under the frame. What you can click and what
you can drag are still the thing you can see. `/wk skin probe` prints the lift
and says so when it has not measured one yet, and the insets go back with the
frame's size when the skin comes off.

### Gates for both

The harness stub now records a texture's draw layer and sublevel, which it
dropped before, so the ordering that decides what the gauge looks like is
asserted rather than assumed: the track and the slice are regions of the bar,
and the three layers run track, slice, fill. The old assertion compared two
frame levels, which is exactly the number the addon asked for rather than the
one that reached the screen, and it passed while the target was drawing at 28
percent.

The stub also stands up the head of each aura row, anchored the way the client
anchors it, and models hit rect insets and `RegisterUnitEvent`. Four things are
asserted from that: the frame carries no tail before an aura has been seen, it
is the block plus the client's lift afterwards, the addon has not touched the
anchors on either row head, and the mouse region stops at the block. Both
halves were checked by breaking the code and watching them fail.


## 1.6

### A performance tab

`/wk` has a Performance page, and `/wk perf` prints the same thing to chat.

The four tickers time themselves with `debugprofilestop`, two clock reads
bracketing each tick body. Each one reports per tick, which is the spike you
feel, and per second, which is the share of a 60 fps frame it actually takes,
plus the worst single tick since the counters were cleared. A part can register
a gauge beside its timing, because 0.31 ms means one thing at two nameplates and
another at fifteen, and the enemy bars register their own count.

Memory is the expensive half and it runs on a fifth ticker that exists only
while the tab is on screen. `UpdateAddOnMemoryUsage` walks every addon the
client has loaded, so sampling it on a ticker that never stops would make the
file measuring the cost the most expensive thing in the addon. The tab's row
starts it on `OnShow` and stops it on `OnHide`.

Two limits are written into the tab itself rather than buried here. The client
attributes Lua allocation and nothing else, so frames and textures never appear
in the figure and it should be read as churn rather than size. And per addon CPU
needs the `scriptProfile` CVar plus a reload and slows the whole client;
TitanPerformance owns that setting in this install, so the tab reads the number
where someone else has turned it on and never turns it on itself.

The tab accounts for itself. Its own sampling cost is a row in it, measured the
same way as everything else.

The harness proves the measurement is free rather than claiming it. Its clock is
stubbed before the addon loads, so every allocation figure it already gates on
was taken with the brackets live, and the bars still measure 0.17 KB per fifty
ticks. It also asserts that the counters move, that switching timing off stops
them accumulating rather than merely zeroing them, and that the sampler runs
only between `Watch(true)` and `Watch(false)`.


Weapon loadouts, one key each.

A loadout is a name, a pair of weapons, an optional stance and a key. A press
puts you in the stance and puts that pair in your hands, off one hardware event,
out of one macro:

    /cast [nostance:2] Defensive Stance
    /equipslot 16 Bloodspiller
    /equipslot 17 Aegis of the Blood God

Three are made for you, one per stance, because stance dancing is what this
started as and a warrior wants those three whatever else they want. Nothing in
the code treats them as special. They are rows in the same list as anything you
add, they can be renamed, unbound from their stance and deleted, and a loadout
with no stance at all is a weapon set with a key on it. Ten is the cap, one
secure button each, and the seed runs once rather than every login, so deleting
Berserker does not bring it back.

Nothing in the part calls `EquipItemByName`. Equipping during a fight is
something ordinary Lua may not do, and an `/equipslot` line off a key press is
the path that is allowed to, so every loadout is a secure button carrying
`macrotext`, the shape `Targeting/Switch.lua` already had.

The macro is written out of combat and never on the press. Every decision a
press makes is a macro conditional, which is what lets a key work in a fight at
all. Changing a loadout mid fight is the one thing that waits, and it waits
until PLAYER_REGEN_ENABLED rather than being lost. Every button is rewritten on
every apply rather than the one that moved, because deleting a row shifts every
row under it onto a different button and a partial pass would leave a key bound
to somebody else's macro. Both are asserted.

The main hand line is written before the off hand line, and the order is the
feature. Going from a two hander to a one hander and a shield, the first line is
what frees the hand the second one needs. A two hander in the main hand takes the
off hand line out of the macro entirely, because an `/equipslot 17` under one
would take the two hander back off. A blank hand means leave it alone: there is
no `/equipslot` for an empty hand, so a loadout cannot strip a shield, and the
panel says so rather than leaving you to work it out.

Swaps fire in combat by default, swing timer reset and all, because that is most
of the point. `loadout combat off` puts a `nocombat` conditional on every equip
line and leaves the stance change alone.

The page is a paperdoll. Blizzard's own model of your character sits in the
addon's own box with a gear square per hand under it, wearing Blizzard's
empty-slot art and Blizzard's slot ring, which is the layout the client's own
character sheet uses. Under that is the loadout strip, one button per loadout
and a `+` at the end, in the place Blizzard puts its own tabs. You drag a weapon
or a shield onto a hand and right click a hand to clear it.

Four widgets are new in the UI layer and none of them knows what a setting is: a
gear square, the paperdoll built out of two of them, a pooled tab strip, and a
line of text you type. The loadout strip is a control rather than the window's
own tab strip on purpose. The window's strip is chrome, built once at login out
of the headers each feature writes, and it cannot grow; a loadout list changes
while the window is open. That is why no rebuild path had to be cut into
`Core/Panel.lua`, and why adding a loadout costs no frames after the first time.

A name typed by hand builds an `/equipslot` line that silently does nothing, so
the panel offers no text field for one. `Core/Gear.lua` is `Charge/Weapons.lua`
promoted to the shared layer: one hand was one part's private knowledge, two
hands is not. It offers what you are carrying and nothing else, and a saved name
that is not on this character keeps its slot and goes orange rather than being
dropped by a panel that cannot see into your bank. `Core/Stance.lua` is the same
move for the three stance spells and their localised names, which the charge
macro and the loadout macros both bake in and could otherwise disagree about.

The harness grew a client to test against. Secure attributes are stored rather
than swallowed, so a macro can be read back; the override binding layer is
modelled, so the readback every part does after taking a key is answering
something rather than reporting a refusal; and there are three items in the
stub's backpack, so the gear scan has something to find. Sixteen assertions on
the macros: the lines, their order, the two rules that drop a line, the combat
conditional, the refused second claim on one key, the delete that has to move
every binding under it, and the loadout changed in combat that has to land after
it.

What the harness cannot settle, and only a key press in game can: whether the
client runs two `/equipslot` lines off one press, and what it does when a two
hander comes off into a full bag. Nothing installed on either client calls
`/equipslot`, so there is nothing to read that would answer either.


### Incoming heals on the skinned frames

The health gauge on the player, target and target of target frames now shows
what is already in the air. A pale green slice runs from where the fill stops to
where the heals in flight will take that unit. `/wk skin heals off` drops it, and
there is a checkbox on the same page.

It is clamped to what the unit is missing. A 2,000 heal on a warrior who is down
300 draws 300, because a slice that runs past the end of the bar is lying about
both numbers. The slice is drawn on our rail, two frame levels under Blizzard's
health bar, which clamps it a second time and for free: when the heal lands, the
fill draws straight over the prediction.

Where it starts is Blizzard's answer rather than ours. The slice is pinned to
the health bar's own fill texture, so its inner edge is exactly where the bar
stops whichever end the client fills from, and it stands as tall as the bar
without this file knowing how tall the bar is. The width is ours and is a whole
number of pixels, like everything else the skin draws.

`UnitGetIncomingHeals` is a real API on both clients. Both binaries register it
and both fire `UNIT_HEAL_PREDICTION`, so there is no LibHealComm here and
nothing parses anyone else's casts. It is probed the way the threat API is:
`ns.HasHealPrediction` answers, a client without it draws nothing, and
`/wk status` says which of those two things is happening.

The gates moved with it. `HealSlice` is in `HOT`, so the scan holds every write
in it to a guard, and it guards on the span it last drew rather than on the heal,
which means a fight where nothing is healing costs three comparisons a tick and
no widget writes. The harness stubs the API and drives three states through the
tick: nothing on the way draws nothing, 1,800 of 9,000 draws 33 pixels of a 167
pixel gauge, and a heal far past what the unit is missing draws the 89 pixels it
is down and stops there.


### The skinned frames are the size Edit Mode thinks they are

The block the skin draws used to hang off Blizzard's portrait anchor inside a
frame five times its size. Everything that reads a unit frame's rectangle read
that one. Edit Mode selected it, snapped it against the other frames and saved
it, while the thing you can see sat somewhere inside it, and the empty three
quarters went on eating clicks. Lining the player frame up with anything was
guesswork.

So the block is anchored to the frame's own top corner now, the one the
portrait is on, and `PlayerFrame`, `TargetFrame` and `TargetFrameToT` are each
resized to the block over them. On this monitor the player frame goes from 232
by 100 of Blizzard's units to 165.74 by 27.90, which is the 202 by 34 pixels
the block already was. What Edit Mode drags is what is drawn, the hit region is
the block, and the target's aura row follows the frame in rather than hanging
where a 232 by 100 frame left it.

Three things carry the resize. The original size is recorded before the first
fit and `/wk skin off` writes it back without a reload. `SetSize` on a secure
unit button is a protected action, so it sits behind the same lockdown guard as
the rest of `Place` and finishes at `PLAYER_REGEN_ENABLED`. And target of
target is placed by this addon once the target frame is fitted, three pixels
under the target block on the edge the two share, because Blizzard's anchor for
it was written against a target frame 100 units tall and points at a corner
that has moved. It goes back to that anchor the moment either frame is
unskinned.

Edit Mode draws a selection frame over the system it is dragging. Where this
client puts one, the skin pins it to the frame and post-hooks that frame's own
`AnchorSelectionFrame`, so the next time Edit Mode re-anchors it, it is pinned
again. Both names are retail's and both are probed before they are touched. A
client with neither still gets the fit, which is what Edit Mode draws over by
default. `/wk skin probe` says which of the two this client is, and prints what
each frame measured before the fit.

Two clamps went with it. The gauge was clamped to what was left of the frame's
width and the square to the frame's height, both because the space around the
block was not empty. The frame is the block now, so the two settings are the
whole of the size and there is nothing left to clamp against.

The harness asserts the fit in screen space, which is the only space the block
and the unit frame share: one is on the pixel grid and the other is on the
client's scale, so a comparison of the raw numbers would pass on a fit that
never converted. Each frame covers exactly the piece of screen its block does,
target of target is parked under the target block, and turning the skin off
hands all three frames back the size they were built at and target of target
back its own anchor.


## 1.5

A drawing layer, `UI/`, and everything the addon draws rebuilt on it. Eight
files: a pixel grid, a drawing kit, and a widget library.

### The pixel grid

`ns.Pixel` computed one screen pixel as `1 / scale`, which is the right answer
only on a screen 768 pixels tall. On a 1440 tall screen at UI scale 0.65 it
asked for 1.88 pixels wherever it meant one, so every border in the addon was a
smear. Frames go through `UI.Adopt` now, which takes them off their parent's
scale and puts them at `768 / screenHeight`, where one unit is one physical
pixel and every size in a layout is a whole number written as a whole number.

Sizes are absolute pixels as a result. The same setting draws the same physical
size on any monitor, which is the point, and `bars zoom` is the lever for a
screen where that is too small. Zoom is a whole number because a fractional one
would put every edge back on a half pixel.

A resolution change re-scales every adopted frame. One the client refuses
because a protected frame is in lockdown is deferred to
`PLAYER_REGEN_ENABLED`.

### Enemy bars

- Icons are cropped on a texel boundary, `5/64` rather than `0.08`, and the
  client's own texture snapping is turned off on them, which is what was
  softening the art. Text moved to Arial Narrow, shared as one font object per
  size rather than a private copy per font string.
- **Which bar is yours.** Your target sits at full alpha and every other bar at
  0.55, and with nothing targeted they all go bright again. `SetIgnoreParentAlpha`
  throws away the client's own dimming, deliberately, because plate alpha also
  fades with distance and there is no plate at all in list mode. The only signal
  before this was the name text turning from white to cream.
- Bars no longer land on top of each other when two mobs stand together. That
  was never a drawing bug: Blizzard's driver spaces plates by how big it thinks
  a plate is, and it thinks a plate is Blizzard's nameplate. `bars stack` tells
  it the real figure and asks it to stack rather than overlap, and hands both
  client settings back when you turn it off.
- A bar on a plate is `bars width` pixels, the same figure the list uses. It was
  the width of the plate under it, and that was a loop with no fixed point: the
  bar measured the plate, the driver sized the plate to the bar, and the next
  bar measured a plate that had changed. Which way it ran depended on the scale
  the client puts on a nameplate against the scale it puts on UIParent.
- The list collector stopped allocating. It was building a table for the list,
  one per mob in it and two closures every fifth of a second. At two bars over
  fifty ticks, 51.76 KB before and 0.17 KB after.

### Player, target and target of target

- The three frames the skin creates per unit frame are adopted onto the grid.
  Blizzard's portrait, status bars and state icons are not and cannot be: they
  are regions of a secure unit button. Every number crossing that line is
  converted and snapped in the direction it is crossing.
- Both gauges are pinned corner to corner onto rails the addon owns rather than
  given a height, so a bar's four corners are whole pixels without the bar
  leaving Blizzard's scale.
- The power bar was 11.63 physical pixels tall and is 10. The two text baselines
  were at -14.41 and -34.63 and are at -11 and -28. The state icons were 22.79
  and 29.84 pixels square and are 18 and 24, both even so that centring one on a
  corner keeps its edges on pixel boundaries.
- The block's anchor offsets were read off Blizzard's portrait anchor and used
  unconverted, which put the block out by the ratio between the two scales.
- The portrait and all four state icons take the sampling fix, crop on a texel
  boundary at `10/64` instead of `0.15`. `/wk skin off` hands snapping back.
- The level tag was built and then compared, so the guard never saved the
  building: 18.75 KB per fifty ticks across three frames, down to 0.00. The bar
  fill and the portrait crop read back before writing: 300 texture writes and
  150 crop writes per fifty ticks, down to zero.
- `skin height` and `skin width` are counts of screen pixels now rather than UI
  units, so **the frames will visibly shrink on first reload**. The ranges
  widened to 18-72 and 90-360; height 42 and width 246 restore the old size.

### The options window, rebuilt on a widget library

`UI/` grew `Theme.lua`, `Stack.lua`, `Scroll.lua`, `Widgets.lua` and
`Window.lua`. `Core/Panel.lua` went from 884 lines to 354 and now owns only
which parts exist and where their sections go.

- **Tabs.** There was never a tab strip. What the old file called a tab was the
  rail button, so choosing a part could not reveal anything. Every `ui.Header` a
  feature writes is now a tab within that part's page, which is twelve tabs
  across seven parts and four on Charge alone.
- **Text no longer overflows.** Every row measures itself, and the stack sets a
  row's width before it asks its height. The old layout did those two the other
  way round, so the one row that measured measured against the previous pass.
- **The window is smaller and it stays put.** 544 by 452 physical pixels, fixed.
  It was 486 by 634 units, which at a 0.65 UI scale is 592 by 773 pixels of a
  1440 pixel screen, and it grew every time a note wrapped and then scaled itself
  down when that overflowed.
- **It scrolls**, with a bar that shows position and drags, and a wheel handler.
  The bar hides entirely when the content fits.
- **No new ticker.** The scrollbar is a `Slider` frame type rather than a thumb
  the addon follows with an `OnUpdate`.
- The seven `panel = function(ui)` builders were not touched. Every widget name
  takes the arguments it always took.

### Gates

`check.sh` bans allocation on ticker paths the way it already banned unguarded
writes, and it runs `scripts/harness.lua`, which loads the addon against a stub
of the client and drives it. The harness asserts the grid arithmetic, whole
pixel geometry on every frame the addon owns, the texel-boundary crops, the
plate footprint, the four target-alpha states, a resolution change that lands in
combat, and every row of every tab of every page of the options window. Three
allocation ratchets sit just above their measured figures.

Two of those gates found real defects on their first run: a 20 Hz nameplate scan
in `Charge.PlateFor` that could never succeed on either target client, and the
level tag being built before it was compared.

## 1.4

One key that takes the next enemy and swings at it, bound in `/wk` under
Targeting or with `/wk switch <key>`. TAB cycles targets and leaves the new mob
standing there, so switching mid-fight cost a second press. The key is a secure
button carrying `/targetenemy` and `/startattack`, held as an override binding,
so putting it on TAB leaves your saved bindings alone.

## 1.3

Moved the addon into a repo of its own, outside the game tree, with both
clients linked into `src/`.
