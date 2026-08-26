# Post-mortems

Bugs that cost more than they should have, written up so the next one costs
less. A trap that fits on one line goes in the **Traps already hit** list in
`docs/README.md`. A bug that survived a shipped fix goes here, with what was
believed at the time and why it was wrong.

One entry so far.

---

## Bar 1 would not take a dropped spell

26 August 2026. Two shipped fixes, neither of which worked. Fixed by
`2b9a4de`.

### What it looked like

With `actionbars on`, bar 1 hovered normally. The tooltip named the ability
under the cursor, an empty square highlighted, and a click made the square push
in. Drag a spell onto it and nothing happened: the spell would not leave the
cursor. The other four cloned bars took the same spell without complaint.

Nothing was printed, no error was raised, and the keys kept working, because a
key never asks the mouse anything.

### The two fixes that did not work

Both were written by reading Blizzard's XML rather than the running client.

The first, `3198aee`, found that `MainActionBar` is declared
`enableMouse="true"` at frame level 50 on MEDIUM, 454 by 35, anchored to the
bottom of UIParent. A frame built on UIParent starts at level 1, so the cloned
bar was standing under a mouse-enabled frame with no drag handler. Bar 1 is the
only cloned bar on that corner of the screen, and `MultiBarBottomLeft`,
`MultiBarBottomRight`, `MultiBarLeft` and `MultiBarRight` are each declared with
no `enableMouse` at all, which explained why exactly one bar was broken. The
cloned bars went to level 120. It was a real bug. It was not this bug.

The second was worse, because it was reasoning rather than reading. Hover works,
the tooltip works, the click animation works, therefore the mouse reaches our
square, therefore no frame is swallowing the drop, therefore the cause is
somewhere in the drop path. Every step of that follows and the conclusion is
wrong, which is dealt with below.

Both passed the harness. That is the part worth staring at.

### What actually found it

`/wk actionbars trace`, added in `0f41117`. It samples whatever the client says
is under the cursor, five times a second, and prints it when it changes, with
the frame's name, its strata, its level and the action slot it presses. It
prints every drag and every click a square gets, with the cursor either side.

Its first live run printed both halves of a pickup and never named a single
frame, which reads exactly like a cursor touching nothing. This client has no
`GetMouseFocus`. `35be245` made it ask for `GetMouseFoci` as well and say which
call answered as it switches on.

The second run answered in one line:

```
trace: under the cursor: MainActionBar (TOOLTIP 50), holding spell 21/spell
```

The same run named squares on all four working bars, by button name and by
action slot, and never once named a bar 1 square.

### The cause

`MainActionBar` runs in the TOOLTIP strata. Its XML declares MEDIUM.

TOOLTIP is the top strata there is, so the level fix never had a chance. The
cloned bar sat at MEDIUM 122 and lost the hit test to a frame at level 50,
because levels are only compared inside a strata. The frame is invisible, since
`Artwork/Artwork.lua` strips its textures by default, and it has no click
handler and no drag handler. It ate every drop aimed at that strip of screen and
did nothing with it.

I do not know what raises it. It may be the client raising its own bars while
the cursor carries an action, which would explain why hovering bar 1 worked and
dropping on it did not: two hit tests at two different moments against a frame
whose strata changed in between. Titan Panel is installed and moves the main bar
around, so it is also a candidate. The fix does not depend on the answer, and I
did not chase it.

### The fix

The frame cannot be hidden. The micro menu and the bag bar hang off the same
corner, which is the warning `Artwork/Artwork.lua` has carried since it was
written. It cannot be out-stacked either, because nothing stacks above TOOLTIP
except tooltips, and a bar drawn over the tooltip it just asked for is a worse
bug than the one being fixed.

So the mouse comes off it. `Buttons/Blizzard.lua` walks up from every Blizzard
button it hides, calls `EnableMouse(false)` on any ancestor that takes the
mouse, remembers exactly those, and hands every one of them back when the clone
is turned off. `Theirs.Recheck` re-silences on the same events it re-hides
buttons on, one of which is `ACTIONBAR_SHOWGRID`, the moment a mouse handed back
would cost the drop already on its way.

Three details that matter:

The walk collects every ancestor, not only the ones taking the mouse right now.
Deciding per pass would silence a frame, find it deaf on the next pass, leave it
out of the wanted set and hand the mouse straight back to it. Whether a frame is
worth silencing is decided once, at the moment it is silenced.

`EnableMouse` is per frame and is never inherited, so the micro menu and the bag
bar keep theirs.

Frames declared with no `enableMouse` are never touched. All four multi-bars are
in that group, and a fix that silenced everything it could reach would have
passed a check that only looked at `MainActionBar`.

One behaviour change comes with it. A click on that strip that misses a square
now reaches the world instead of being swallowed by an invisible frame.

### What changed so it cannot come back

`scripts/harness/client/02-text.lua` carries `MainActionBar` in TOOLTIP at
level 50 with bar
1's twelve buttons parented to it, and fails if the clone leaves it taking the
mouse, if it silences a holder that never took one, or if the off switch leaves
anything deaf. I checked the gate by removing the fix: two failures, and both
pass again with it back.

`Region:GetFrameStrata` used to return the string `"MEDIUM"` for every frame in
the fixture. It records what was set now. That one line is why both wrong fixes
passed: the harness could not express the bug, so it could not fail on it.

The trace stays in the addon, off by default and read only.

### What to take from it

Read the running client, not Blizzard's XML. This frame is declared MEDIUM and
does not run at MEDIUM.

Compare strata before level. A level is only meaningful inside a strata, and a
number that looks decisive on its own is not.

A fixture that cannot express a bug cannot gate a fix for it. When a fix passes
first time against a fixture written from the same reading that produced the
fix, that is not confirmation.

A diagnostic that can go quiet for two different reasons is not a diagnostic.
The trace's first run was silent because the API was missing, and that looks
identical to a cursor over nothing.

Do not reason from one gesture to another. Hover proved that the mouse reached
the square while the cursor was empty, and I took it as proof about a drop,
which happens with the cursor loaded. Those turned out to be different
questions.

Make refusals speak. Every failure mode here looked the same on screen: a bar
that ignores the mouse. A drop that reaches a square and moves nothing now says
which slot it was aimed at, and a square pointing at no slot says that instead.
Nothing about that is a diagnostic feature; it is the addon saying what it just
did.
