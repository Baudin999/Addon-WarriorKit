# Changelog

## Unreleased

### The cloned bars answer a press

The squares read the right slots, drew the right art and cast the right spells,
and they still did not feel like buttons. Five things were missing and four of
them are the same missing thing: nothing on a square changed in response to
anything you did with it.

The loudest was the global cooldown. `Buttons/Slot.lua` withheld the swipe below
1.5 seconds on the grounds that a bar sweeping on every press is a strobe. It
is, and that strobe was the only thing on screen answering a key press: a rage
dump has no cooldown to count, no colour to change and nothing to grey, so
pressing one moved no pixel at all. `Slot.State` now returns the cooldown's
numbers whether or not it returns the `cooldown` status, and `Ability.Draw`
takes the swipe off the numbers and the countdown off the status. The global
sweeps and gets no number; a real cooldown still gets both.

Then the three the client will draw for you if asked. A highlight on the
HIGHLIGHT layer, which the client shows and hides itself for any frame that
takes the mouse. A pushed tint, which the Button widget draws between mouse down
and mouse up. And a tooltip, which was on the list of things a square
deliberately was not and should not have been: drag is a way to lose a bar to a
misclick, and a tooltip is how you find out which rank of Rend the loadout put
in slot four.

The fifth is the active tint. `IsCurrentAction` and `IsAutoRepeatAction` fold
into `Slot.Active`, and a square that is already what is running gets an
additive gold wash over the art. On a warrior that is the stance you are
standing in, drawn on the bar at a glance, and the auto attack already swinging.
It is an argument to `Ability.Draw` rather than a tenth status, because the
active stance is also `ready` and the two must be able to be true at once. The
two calls are probed separately from the five in `NEEDED`: a client without them
loses a tint, not the bar.

And empty slots stopped being question marks. An empty slot has no art, so it
fell to the `no` look and came out as `INV_Misc_QuestionMark` at 55 percent, a
row of grey question marks where Blizzard's bar had holes. Both palettes grew an
`empty` look carrying `blank`, which says draw no art at all.

### You can drop a spell on a square, and a worn item says so

The two things the entry above listed as not done.

Dragging was refused on the grounds that `PickupAction` and `PlaceAction` on a
frame you can drop anything onto is a way to lose a bar to a misclick. The risk
is real and the conclusion did not follow. With Blizzard's buttons hidden
underneath, nothing could be dropped on a bar at all, so learning a spell meant
turning the whole clone off to place it and back on again. A misclick moves one
slot and hands back what it displaced. Nothing is destroyed, and the picture is
right on the next tick.

So a square takes `OnDragStart` and `OnReceiveDrag`, both refused in combat,
which is where `PickupAction` cannot be called anyway. They ask
`Layout.CanCarry`, which is new and is the smaller half of `Layout.CanWrite`.
That split was a bug found while wiring this up: `CanWrite` refuses while the
cursor is holding something, which is the state every drop happens in, so a drop
asking it would be told to put down the thing it was in the middle of putting
down. It also demanded all seven action calls, and moving one slot onto another
needs two. `CARRY` is those two, `COMPOSE` is the five a loadout needs on top,
and each is probed once.

Empty squares are drawn at full alpha now rather than faded. That looks
backwards and is not: with `blank` there is no art left to fade, so the alpha
only reached the black backing and the hairline, and fading those leaves a drop
target you cannot see. It is also why there is no grid. The client shows one on
`ACTIONBAR_SHOWGRID` because its bar has no background to see a hole against,
and this one is squares on a box.

The equipped ring is `IsEquippedAction` folded into `Slot.Equipped`, drawn as a
second green outline one pixel inside the status border rather than a recolour
of it. The outer edge already carries the status, and being worn is not a
status: a wielded weapon can be on cooldown and out of range at once, and all
three are worth saying. It sits on `OVERLAY` because `BORDER` is under the art,
and a ring on the art's own bounds would be covered by it.

`Buttons/Bars.lua` hit 832 lines doing this, over the 800 line gate. It took the
split rather than a fourth entry on the allow-list. `Buttons/Square.lua` is what
one square answers to the mouse: everything in it hangs a script on a button and
touches the cursor, and none of it knows what a bar is or which slot a square
points at.

### The meter bars have an opacity slider

`BAR_ALPHA = 0.15` was a constant in `Meter/Window.lua` and the note beside it
argued the number well: a bar is read against the bars next to it rather than
against the world behind it, so a tint ranks four players and a wash only hides
the floor. The argument holds and the number does not travel. 15 percent over a
dark crypt is what it was drawn for, and 15 percent over Tanaris at noon is
nothing at all, which is a thing the addon cannot see and a player can see in a
second.

So it is `meterBarAlpha`, whole percent, 0 to 100 in fives, still 15 by default.
The panel gets a slider under the pane width and `/wk meter alpha 60` reaches
the same stops, through `Command.Step` so a value off them is refused rather
than quietly rounded. At 0 there are no bars and the meter is columns of
outlined text over the world, which is one of the reasons the range starts
there rather than at something safe.

The one part worth writing down is the guard. A row writes its bar and its name
only when the player on it changes class, which is what keeps the tick free, and
the alpha is not the class: left alone, the slider would have looked broken to
anyone dragging it outside a fight and landed later on a class change that never
comes. `MeterWindow.Apply` clears the colour guard on every row, so a setting
change lands on the next tick. The harness asserts that, rather than asserting
the saved variable took the number, and the panel's slider census went from two
to three so the next one is a decision as well.

### The unit frames share one layer instead of two copies of it

`UnitFrames/EnemyBars.lua` and `UnitFrames/Skin.lua` draw the same things about
the same units, and each had grown its own copy of how. Neither copy was wrong.
Having two of them was, and they had already drifted:

- the class colour was a hex string in one file and an `{r, g, b}` table in the
  other, with a cache each;
- the level tag was interned in the skin and rebuilt on every tick in the bars,
  which is a `tostring` and a concat per mob to say a number that changes when
  the mob does;
- the reaction palette was declared in both, four of the nine colours being the
  same three literals typed out twice, which holds until somebody warms the
  green on one of them;
- the bars walked the whole party or raid on their own ticker to get the unit
  list their threat comparison needs, which is eighty unit queries five times a
  second in a forty man, while `Meter/Roster.lua` already held that list and
  rebuilt it on `GROUP_ROSTER_UPDATE`.

There is a `Unit/` layer now, between Core and UI, and both files read it.
`Unit/Color.lua` is every colour the addon puts on a unit, one palette with the
semantic maps on top of it, so a green that appears in two answers is the same
table in both. `Unit/Level.lua` is the tag and what the kill is worth, so the
bars got the skin's cache and the skin got the bars' colour. `Unit/Threat.lua`
is what the client's threat API says, for one mob or across a group.
`Unit/Roster.lua` is `Meter/Roster.lua` moved, because the bars wanted the same
answer it was already giving the meters.

`Unit/` draws nothing and signs into no registry. Two rules hold across it, and
both come from the callers rather than from taste. Nothing allocates, because
everything on that page is reachable from a ticker running against every mob on
the screen. And a colour is handed back by reference and never built at call
time, because the tickers guard their widget writes on colour identity, so the
same state has to answer the same table every time.

The enemy bars' allocation gate went from 0.25 to 0.05 KB per fifty ticks, and
what it measures is 0.00. The roster walk was the whole of what was left.

Nothing about what either frame looks like changed.

### A stack panel, so a widget's layout is a tree rather than a hundred SetPoints

`ns.UI.Flow` is what XAML calls a StackPanel and CSS calls a flex container:
rows, columns, gaps, padding, alignment, growth, wrapping and mirroring. Two
passes, the same two XAML has. Measure asks every node how big it wants to be,
bottom up; Arrange hands every node the rectangle it got, top down, and pins
each frame to the root's top left corner at the offset that came out.

`LayoutWidget` in `UnitFrames/EnemyBars.lua` was a hundred and eighty lines of
`SetPoint` with the failure mode every hand-written layout has: each anchor is
individually correct and the relationship between them lives only in whoever
wrote them. Moving the threat line up three pixels meant finding the four other
offsets measured off the same edge. It is a tree now, and the widget's own
height falls out of the measurement instead of being derived by hand from four
other numbers.

Three shapes were worth adding for what the bars actually needed. `lineOrder`
lets a wrapping row grow upwards, so the debuff line nearest the gauge is the
one that fills first and a partial line hangs off the top. `direction = "stack"`
is XAML's single-cell Grid, every child getting the whole rectangle and placing
itself in it, which is how the threat number and the debuff row share one strip
without either reserving room from the other. And `reverse` is the whole of
mirroring a layout, which is what the target frame is against the player frame.

It does not do content sizing and it will not. A node's size is a number the
caller knows before the layout runs, so the two strings inside a gauge, sized by
whatever the mob happens to be called, stay pinned to each other with plain
anchors. A layout that had to re-run on a name change would be a layout running
on the tick. `check.sh` is what holds that line: no function in `UI/Flow.lua` is
named in `HOT`, so the engine may allocate and everything that calls it may not.

`scripts/harness.lua` gates the engine on its own, nine shapes read back off the
offsets it wrote, before anything built out of it is touched. The debuff row
test stopped naming an anchor pair and measures where the square lands instead,
which also covers the gauge's own placement and did not before.

### The frame skin is laid out by the same engine, and mirroring is one flag

`Place` in `UnitFrames/Skin.lua` carried the block's whole geometry by hand, and
`spec.mirror` was three variables named `portraitEdge`, `gaugeEdge` and `pull`
whose signs were threaded through every offset in the function. The target frame
mirrors the player frame, so every one of those offsets had to carry which way
it was facing.

The box's interior is a Flow row of three cells now with `reverse = spec.mirror`
on it, and mirroring is that flag. Two details made it work. The pixel the box's
outline draws into is its own empty cell at the end of the row rather than
padding, because `reverse` reverses child order and not padding, so an inset
written as padding would have stayed on the same edge when mirrored. And the
divider is the square's inner column expressed as a nested reversed row, so it
turns with the square.

Three things `reverse` could not take, and all three for the same reason Flow
does not do content sizing. The block's own anchor on Blizzard's frame is placed
by its owner. The four badge regions belong to the client and stay hand pinned.
And the four font strings are as wide as whatever the unit is called, so they
are anchored rather than arranged. `pull` survives in that last block alone
instead of running through the whole function.

Nine anchors went out of the addon: the rails and the divider each used two
points and use one. The blocks measure what they measured, 202 by 34 with a 21
and 10 gauge and a one pixel hairline.

### One gauge, drawn one way

The addon drew a flat status bar in three places and had three implementations
of it. Two of them shared an exact pair of lines, the fill colour followed by
the spent track at a fifth of that colour on nine tenths alpha, typed out in
`EnemyBars.lua` and again in `Skin.lua`.

`UI/Gauge.lua` holds what is actually shared. `Gauge.New` builds a flat bar with
its track. `Gauge.Flatten` turns a bar the client made into a flat one and reads
back first, so a bar that is already flat costs a comparison rather than a
texture write. `Gauge.Underlay` puts a texture inside a bar and under its fill
by draw layer, which is where the note about the target frame drawing at 28
percent of its own colour now lives. `Gauge.Paint` is the pair, once.

`Meter/Window.lua` was looked at and deliberately left alone. Its rows wear the
same look and are a different widget: one texture whose width is that player's
share, with nothing behind it and no spent part to colour. Putting it through a
gauge would add a frame per row, raise an ordering question against the row's
icon and text that does not exist today, and hand a StatusBar's internal float
the rounding the meter does in whole pixels on purpose. Three implementations
were two implementations and a lookalike.

### check.sh caps how long a file may be

The addon gates allocation on tickers, TOC parity between the two flavours and
version drift between the TOCs and `ns.version`, and had nothing watching a file
reach nineteen hundred lines. Two had. That is the same class of debt: nothing
is wrong with any one line, the whole is past what fits in a head, and the next
change lands wherever there is room rather than where it belongs.

800 lines in general. Three files carry their own ceiling, set at what they
measure today, each with a one-line reason and the split it would take. The
ceiling fails in both directions: growing past it fails, and shrinking below it
fails until the number comes down in the same commit, which is what makes it a
ratchet rather than a licence to grow back.

## Unreleased

### The charge part now stays out of the way on another class

Charge, Intervene and Intercept are warrior abilities. On a hunter the part was
still built anyway: a secure button holding a key override, a ten-a-second
ticker behind an icon that could never light, a twenty-a-second nameplate scan
behind a marker for an ability that does not exist, and `SoftTargetEnemy`
rewritten on every combat transition to serve all of it. Four tabs of settings
in `/wk` wrote values nothing on that character read.

`ns.IsWarrior()` is the one answer now, in `Core/Core.lua`, and the loadout
reads the same one instead of asking the client itself. `Icon.lua` and
`Marker.lua` unregister their event frames at PLAYER_LOGIN rather than building
something and hiding it, because a hidden marker still pays for the scan.
`SoftTarget.Wanted` returns nil, which is the single place that decides whether
that CVar gets written, so the panel, the slash word and the combat transitions
all leave it alone together. The slash words say why, `/wk status` says why, and
the Charge page is one sentence instead of four tabs of dead controls.

The saved settings are untouched. They are account-wide and a warrior alt shares
them, so a class gate is a fact about this character rather than a preference
about the addon.

The class is read every time rather than cached. Class data is not reliable
while the files load, and a cache taken then would lock a warrior out of their
own charge button for the session. An unresolved class counts as a warrior for
the same reason: the two wrong answers do not cost the same.

`check.sh` runs the harness twice, and the second run comes up as a hunter.
Both halves are decided once at PLAYER_LOGIN, so the only way to assert that
nothing was built is to start as something else. That run asserts the button
and the marker are absent, the key was refused, the Charge page is one tab and
the CVar came out holding the value it went in with, and it re-runs every other
part of the addon on the way, which is how a part that quietly needed a warrior
would now fail here rather than in someone's game.

### The charge key did nothing while the frames were unlocked

`ApplySecure` cleared the button's `type` attribute whenever `ns.db.locked` was
false, so that a left-press meant for a drag could not also cast. It did stop
the drag casting. It also killed the bound key, because the key is an override
that clicks the same button, and a secure button with no type is a button with
no action. The symptom is a charge key that silently does nothing until you type
`/wk lock`, with no error and nothing in chat.

The two jobs are on two frames now. The button keeps `type = "macro"` the whole
time and never takes the mouse at all; a plain frame laid over it takes every
click while the frames are unlocked and does the dragging. The key works in both
states, a stray click while placing still cannot cast, and the tooltip moved
onto the handle with the drag.

### Blizzard's damage number sat across the level and the rage gauge

`StripArt` walks textures. The combat feedback number is a font string, so the
walk never saw it, and Blizzard draws it centred on a portrait sized for a frame
a hundred units tall. On a 34 pixel block it lands over the level text and half
the power gauge, and neither number can be read.

It goes with the name, the level and the two bar numbers, which is the list of
font strings this file already hides by name. It is the one entry on that list
with nothing drawn in its place: the art that used to hold it does not exist any
more, so there is nowhere correct to put it. The harness shows it and asserts it
stays hidden, because the client calls `Show` on it at every hit.

### Repairing

The other half of what a merchant is for. Grey items have sold themselves at
every merchant since 1.4 and the repair was still a click on an anvil.

`Comfort/Repair.lua` pays at any merchant the client says can mend, the moment
the window opens, behind the same shift key that skips the sale. Guild funds
first where your rank's withdraw allowance covers the bill, your own purse where
it does not, and nothing at all where neither can cover it: half a repair is not
something the client offers, and an emptied purse is worse than broken mail.
A guild that answers yes and then refuses falls through to your own gold rather
than walking away.

`/wk repair` with no argument repairs the merchant in front of you now and says
why not when it cannot. `/wk repair on|off` is the setting. `/wk status` carries
the worst piece you are wearing.

One call and no ticker, which is the whole reason it is a separate file from the
sale. `RepairAllItems` does every slot at once, so unlike a sweep there is
nothing to repeat. The two parts share the merchant window and share nothing
else.

The merchant calls are named in `.luacheckrc` on the usual standard: TitanRepair
and Leatrix Plus both call them unguarded on both clients, inside the feature
this one is. The guild bank trio is not, because Classic Era has no guild bank
and TitanRepair calling them there proves only that TitanRepair would break.
Those three go through `_G` and are pcalled, so a client without them loses
guild funding and keeps the repair.

### The numbers on a debuff square were outlined into blobs

The threat line and the targeted-by line went up to 14 for the same reason from
the other direction. Those two sit in the gap above the gauge, over whatever the
player is standing on, so the outline is not a choice there: with nothing behind
the glyph, flat is not softer, it is gone. That makes the floor a hard minimum
rather than a switch point, and 12 outlined was the one combination that is
wrong both ways at once, too small to carry a rim and unable to drop it. The
empty bar is two pixels taller as a result, and the harness derives that height
from `ns.UI.OutlineFloor` rather than carrying a literal, so the two move
together.

The name, the health number and the level tag are the same 12 and stay outlined.
They sit on an opaque fill, which makes the outline a contrast judgement rather
than a necessity, and a pale name on a pale gauge is a real argument for keeping
it. The gate encodes that distinction rather than flattening it: outlined text
over the world must reach the floor, text over a fill may be either.

An outline is a rim drawn round a glyph and it costs the same pixels whatever
the glyph is, so below about fourteen it has eaten the counters: the hole in a
6, the waist of an 8. UI/Theme.lua has said so since the panel was rebuilt, and
said it about panel text, which is why panel text is flat. The timer and the
stack count on a debuff square are over the icon's own opaque art for exactly
the same reason, and they were being drawn outlined at seven to twelve pixels.

Both go through `ns.UI.NumberFont` now, which keeps the outline while the glyph
is big enough to carry one and drops it when it is not. The harness sets every
icon size in the range and reads the size and flags back off the font object,
so it fails on the old values at every one of them.

Worth saying rather than hiding, because the harness prints it: every number on
a square comes out flat, at every setting. Both are capped by a design constant
under the floor, the timer by the bar's own text size and the count by
`COUNT_TEXT_SIZE`, so no icon setting can lift either to fourteen. That means a
56 pixel square still carries a 12 pixel timer, which is legible and small for
the room it has. Left alone for now; it is a look decision rather than a defect.

Found by the other half of this pair working on the meters, which had the same
bug in its own rows. A number can be arithmetically correct at every zoom and
still be the wrong number, and the layout is exactly as consistent as it would
be if it were right.

### two meters, and no window round them

A damage and healing readout and a threat readout, side by side in one
draggable frame. A row is a spec icon, a name, a number and a class-coloured bar
as long as that player's share of the top row. Clicking the damage header swaps
it to healing. There is no breakdown to open, because there is nothing behind a
row to open.

Nothing is drawn but the rows. No backdrop, no border, no title bar. Details
draws a window because it is a tool you go and use; this is two columns you read
out of the corner of one eye during a pull, and every pixel of chrome around
them is a pixel of the fight underneath.

**The threat pane differentiates.** The percentage is the client's own, where
100 means that player takes the mob, thresholds and talents already folded in.
What is new is the rate it is changing at and what that projects to: 82% and
falling is a rogue who stopped, 82% and climbing four points a second is a rogue
who takes the mob in four and a half seconds, and the header says which and
names them. Smoothed over half second samples, because threat arrives in lumps
the size of a Sinister Strike and two raw samples can differ by twenty points
either way. Nothing past a minute is projected.

On Classic Era the pane says `no api` and stays empty. Vanilla computes no
threat, so every Classic threat meter is a combat log simulation carrying a
table of coefficients, and that is a different addon.

**Spec icons on clients with no specs.** There is no `GetSpecialization` here.
A character is three talent trees with points in them, and the tree with the
most is the whole of what anyone means by a spec. Yours is read directly and
re-read on every point spent. Everybody else's is an inspect, inside about 28
yards and out of combat, one in flight and never the same person twice inside a
minute. Until one lands the row draws a class icon, so the icons sharpen over
the first minute in a group and never block anything while they do.

**One clock for every row.** Details gives each player their own activity
window, which flatters whoever stopped early. This divides everyone by the
segment, which is the only version where the rows add up to the total on the
header. Overheal is subtracted: a healer who lands 40k into a full health bar
has healed nothing.

**The group filter is the parsing.** The combat log carries the party next door,
both sides of the duel by the mailbox and every mob in the pack. A pet's damage
is its owner's, so a hunter does not read as half a hunter. What a member
summoned is theirs, taken from `SPELL_SUMMON`, because a totem is not a pet and
no unit token points at one. Everything else is nobody's.

**A new gate.** `METER_CHURN_KB`, measured with the clock running rather than
frozen. A meter with nothing moving allocates nothing at all, because every
write is guarded on a number rather than on the string it would make, and a gate
on that figure would be measuring the guards. With the seconds ticking over it
measures 0.16 KB per fifty ticks and the gate is 0.20.

Worth knowing which way round the guards pay. In a fight they save almost
nothing, 0.16 against 0.27, because the numbers move every tick and the string
gets built either way. What they buy is the meter sitting on screen between
pulls, which is most of a session, at nothing at all.

**The icon is 27 pixels because that is a size the client stores.** Every other
number in the layout follows it. A spell icon is kept at 64 texels, the crop
takes the five texel border off each edge, and the 54 that are left are exact
only where they halve onto whole pixels: 54 and 27, nothing between. So a row
icon draws 27 at zoom 1 off the half size copy and 54 at zoom 2 off the full
one, which is as sharp as a spell icon gets. The row is the icon with a pixel
above and below, 29, so the icon decides the height rather than the text. Six
rows and a header is 196 pixels tall, two panes and a gap is 408 wide.

**Every string on it is 14, because every string on it is outlined.** With no
background behind them the outline is the only thing between a number and a pale
floor, so unlike a timer on a debuff square this text cannot fall back to flat
when it shrinks: flat over the world is gone rather than soft. That makes the
outline floor a hard minimum here, and both sizes sit on it. The number lives in
`UI/Text.lua` and the harness reads it from there, so the meters and the bars
are held to one figure.

That is the second version of those numbers. The first drew a 12 pixel icon and
11 pixel row text, and the report from the client was two words: shrunken, and
not sharp. The pane headers were wrong too, at 12, and nobody reported those
because nobody reads a header twice. The harness fails now on an icon size the
client does not store, at either zoom that can be exact, and on any outlined
string under the floor.

**Five defects, four of them caught before any of this ran in a client.** The
group total was `0/0` before the first fight of a session, and the client's
`string.format` renders that nan as `-9223372036854775808`; that was the first
tick of every login. The threat header never wrote at all while the state was
quiet, because the guard's unchanged case was identical to the state the pane
starts in with nothing drawn. The same header then stuck on `no target` after a
target came back. An inspect the client never answered parked the queue on that
GUID for the rest of the session, because there is no failure event for one.
And the fifth is the sizing above, which no gate caught because there was no
gate until a person looked at the thing. Each has a test that fails without its
fix.

### bars zoom does something now

It never has. The setting shipped, the panel offered 1 to 3, the README called
it the answer to sizes being absolute on a high resolution monitor, and the bar
measured 180 by 62 screen pixels at zoom 1, 2 and 3 alike. Fonts included.

One line did it. Every design number in `LayoutWidget` was multiplied by
`ns.Pixel(widget)`, which on the grid is `1 / zoom`, and the scale the zoom put
on the frame multiplied it straight back. The two cancel exactly, which is why
nothing looked wrong: the bar was not the wrong size, it was the same size.

The fix is a second conversion with a name of its own. `ns.UI.Pixel` is one
screen pixel and is for hairlines and insets, which stay one pixel when the
design grows. `ns.UI.Unit` is one pixel of the design, which on the grid is one
unit whatever the zoom, because turning that unit into a 2x2 or 3x3 block of
screen pixels is the entire job of a zoom. Every size in the bars goes through
`Unit` now and every edge still goes through `Pixel`.

    zoom 1   bar 180 x  62 px, gauge 23, icon 20, hairline 1
    zoom 2   bar 360 x 122 px, gauge 44, icon 40, hairline 1
    zoom 3   bar 540 x 182 px, gauge 65, icon 60, hairline 1

At `bars zoom 2` a debuff square draws 38 screen pixels of art, which is about
what Blizzard's own buff buttons draw and roughly twice what this addon has been
drawing. If you have ever thought the bars looked small on a big monitor, that
is the setting, and it works now.

**The sharp icon size moves with the zoom.** The art is the square times the
zoom, less two pixels for the border, sampled from 54 texels. So one stored
texel lands on one pixel at `bars icon 29` when the zoom is 1, and at
`bars icon 28` when the zoom is 2, where it draws the full 54 texel copy one for
one and is the sharpest a spell icon gets. `EnemyBars.IconAdvice` works that out
rather than carrying a table, the panel and `bars icon` both read it, and the
harness checks the number it names against the texel arithmetic at each zoom.

**Two new gates.** The harness converts the bar to screen pixels and compares it
against what the design asked for at each whole zoom, which is the check that
was missing: every assertion in that file was written in the widget's own units,
and in those units the bar genuinely does change size at 2x. It is half as many
units on twice the scale, the same picture, and no measurement taken in units
can tell the two apart. The whole-pixel anchor sweep now runs at 1x, 2x and 3x
as well, because a number that was even before a multiply is not obliged to stay
even after one.

### The bars were half a pixel low, and the icons were never the size they said

Reported as "the bar does not feel crisp", which it was not, and the cause was
not the nameplate. Three anchor offsets in the enemy bars were fractions of a
pixel, and a frame whose own origin sits half a pixel off a boundary has every
edge, every glyph and every icon inside it drawn across two rows.

The one that mattered: `PLATE_BAR_HEIGHT / 2 + 1` is 11.5, it is the offset that
puts the widget where Blizzard's bar was, and replace is the style that ships.
Every bar this addon has ever drawn in its default configuration was half a
pixel low. The level tag's number was 2.5 pixels off centre, half the width of
the reaction stripe, on every bar as well. The threat line lands on a half pixel
at any odd debuff icon size. All three now round, and the comment explaining why
rounding is necessary was already sitting three lines above the worst of them.

An odd bar cannot be centred on a point and land on a boundary, so half a pixel
of centring is what this gives up. It is not visible. The smear was.

**The harness walks every anchor now.** Every frame the addon puts on the pixel
grid, every offset on it, and it fails on anything that is not a whole number of
physical pixels: 2843 offsets across 1779 regions. This class of bug is
invisible in review because the arithmetic that causes it looks like centring,
and it cannot be caught by reading one file, so it is caught by a number
instead.

**Debuff icons: 29, and nothing else.** The panel said 16 and 32 were the sizes
that draw sharp. Neither is, and the square has never been drawn at either. The
client keeps each texture at half the size of the one above and picks the pair
nearest what was asked for, so a draw is exact only where the sampled texels
halve down to the drawn pixels. `ns.UI.Icon` crops five texels a side to lose
the border baked into the art, leaving 54 rather than 64, and the square draws a
one pixel border with the art inset inside it, so a 20 pixel setting draws 18
pixels of icon. 54 halves to 27, plus the border is 29, and 13.5 is not a number
of pixels. Nothing else in the range lands.

The shipped 20 draws 18 from 54, which is 58 percent of the way between two
stored copies and about as blended as the range gets. The default has not moved,
because moving it rewrites a setting nobody touched, but the row is a slider
that steps by one instead of a stepper that stepped by two, so 29 is reachable
from the panel for the first time, and the note names it. `bars icon` says the
same thing. `EnemyBars.IconAdvice` is the one place that arithmetic lives and
the harness checks the size it names is genuinely exact rather than trusting the
note. 29 is the answer at `bars zoom 1`, which is the default and was the only
zoom that existed in practice when this was written. See the zoom entry above
for what the number becomes once the zoom does something.

The ceiling on `bars icon` is 56 now rather than 32. 54 texels survive the crop
and the border takes two pixels, so 56 is the largest square where a stored
texel still lands on a screen pixel; above it the client stretches 54 texels
over more pixels than it has and the art softens again. The old 32 was chosen
when the row was four fixed icons on a 180 pixel bar, and it put the whole top
half of the useful range out of reach: with `bars zoom` inert, this number was
the only way to get a big icon, and it stopped well short of one.

What this does not fix: a nameplate's own origin is wherever the mob is
standing, which is a moving fraction of a pixel no addon can read. The bar is
exact in geometry and in its offset from the plate now. Where the plate lands is
still the client's business.

### A settings tab, and a slider that says how big you want this

An eleventh part, `Settings`, one rail entry in `/wk` holding the preferences
that belong to no feature. There is one of them so far. `UI size` is a slider
from 0.5x to 3x in quarters, and it sizes the windows this addon draws: the
`/wk` panel and the Clutter window. `/wk uisize 1.5` does the same from a macro
and `/wk uisize` on its own prints where you are.

It multiplies the whole step the screen already picks rather than replacing it,
which is the arithmetic that makes the control mean what its name says. On a 4K
panel the addon has been drawing everything at 2x on its own; dragging to 0.5x
there lands back on the design size with every edge still exact. On a 1080p
panel 0.5x is genuinely half.

Eleven stops, and they do not all cost the same. A stop keeps the pixel grid
when the size times the screen's own step comes out whole, which on most
monitors means 1x, 2x and 3x. The other eight ask for a one pixel hairline at
1.25 or 1.75 pixels and get a blur. `bars zoom` refuses a fraction outright and
still does, because a bar over a mob's head is the addon deciding what you see
in the middle of a pull. A settings window is you deciding how you want to read
it, so the fraction is allowed here and the panel names the stops that stay
exact and tells you which one you are on. The slash word refuses anything off a
step rather than rounding it, so a macro and the slider reach the same values.

`kit.Slider` is new in the widget kit, built on the client's `Slider` frame type
the way the scrollbar is, with a pair of nudge buttons behind a probe for a
client that refuses the type. Both paths are in the harness now, which is how
the fallback turned out to be broken on the day it was written: `pcall` returns
the error message where the frame would be, and the fallback called `Hide` on a
string.

A drag updates the readout and commits nothing until the button comes up. The
client reads a slider's value off where the cursor sits against where the track
sits, so a setter that resizes the window the slider is in walks the track out
from under the cursor and the next frame reads a value off geometry that has
moved. Committing live made the thumb slam between 0.5x and 3x for as long as
the button was held. The harness holds the button, moves the thumb, asserts
nothing was saved, lets go and asserts the value landed.

### The debuff row on the enemy bars is yours

It tracked Sunder Armor, Demoralizing Shout, Thunder Clap and Rend, in that
order, because those are the four an editor once typed into a constant. Which
debuffs matter is a spec question and a fight question, so the list is a setting
now. `/wk` has a Debuffs tab under Enemy bars: a row per tracked spell with the
icon, the name and a button that takes it off, a picker holding every debuff a
warrior can apply on these clients, and a field that takes any spell ID at all.
`bars debuff add 12162` does the same from a macro, and `bars debuff` prints
what is on the bar.

Ten slots. Matching is still on the localised name, so rank 1 is enough, every
rank counts and another warrior's Sunder still shows up desaturated. Two IDs
that resolve to one name are refused, because they would be two identical
squares lighting up and going out together. An ID this client cannot name keeps
its place and draws nothing, so a spell added on the TBC character comes back
when you log into it rather than vanishing from an Era session.

`bars icon` sizes one square between 16 and 32 pixels. Those two are the sizes
the client actually holds a copy of, a 64 texel icon halved and halved again, so
they are the two that draw sharp and everything between them is a blend of two
copies. The panel says which of the two you are on rather than pretending the
stepper is flat. The timer and the stack count now scale with the square: a
fourteen pixel number on a sixteen pixel icon covered the art it was
annotating.

The row still ends flush with the right end of the gauge, which is what it was
always for. What it does when it no longer fits is new: it wraps upwards, one
right aligned row at a time, so ten 32 pixel icons on a 180 pixel bar become two
rows of five instead of four icons hanging off the left edge into the mob next
to it. The bar grows by exactly the rows it gained, and the nameplate driver is
told the new height, so two mobs standing together still get two bars that do
not cover each other. An empty list costs the row entirely and leaves the threat
line its own height.

`Command.Number` now refuses a fraction instead of taking it. Every caller is a
pixel count, a bar count or a zoom step, all three of which sit on the pixel
grid, and `bars zoom 1.5` used to be accepted and put every edge in the addon
onto a half pixel.

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
