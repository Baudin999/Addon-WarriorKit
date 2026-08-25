# Changelog

## 1.6

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
