# Changelog

## Unreleased

### The purse and the tooltip drew their text the wrong way

The three numbers along the bottom of the loot feed looked worse than the rest
of the window. They were outlined at 12 pixels, and `UI/Text.lua` puts the floor
for an outline at 14 for a reason: a rim spends a pixel of every stroke, so
below the floor the hole in a 6 closes and the waist of an 8 fills in. On the
one line in the window that is nothing but digits, that is the whole line. The
strip is 20 tall now and its text is at the floor.

Dropping the rim instead would have been the obvious fix and it would have been
wrong. A feed looks like it is painted on a surface this addon owns, and it is
not one: the background is a slider the player drags, it goes to zero, and
`Feeds/Feature.lua` promises them in writing that the text reads all the way
down to nothing. Flat text there goes with the surface. So the strip keeps the
outline it had and gets the height to carry one.

Two more strings were under the floor and nobody had hovered them: the drag
captions on the swing bars and the buff row, both at 12 over the world.

The tooltip was a different fault with the same shape. Its body was 11, a number
the file wrote for itself, and 11 is `UI.Metric.small` - the size the panel keeps
for a hint under a control. Every line of a tooltip is the thing you opened it to
read, so a box whose prose was smaller than the panel under it had it backwards.
Title and body come off `UI.Metric` now, at 13 and 12.

### Every string in the addon says what is behind it, and the addon checks

`UI.Label` used to take an outline when the caller named no role, which is how
ten sites ended up outlined without anybody choosing it. There is no default
now: `UI/Text.lua` names all three roles, `UI.FLAT`, `UI.SHADOW` and
`UI.OUTLINE`, every caller passes one, and `check.sh` fails a call that does not.

A grep can only see that a role was named. Whether it is the right one is a fact
about what is behind the glyph, and that is not in the source at all, so
`harness/sections/36-font-roles.lua` asks the built addon instead. It walks every
string that has text in it, 881 of them, finds what each is standing on by
climbing its parents until it hits a surface, and fails on three things: an
outline under the floor, a string with nothing behind it that is not outlined,
and MONOCHROME.

Then it drags every background opacity to zero and walks them all again. That
second pass is the one worth having. Three surfaces in this addon are not
surfaces - the two feeds and the chat window - and a string on one of them is a
string over the world that looks like it is not.

What counts as a surface is the whole difficulty, and it is a question about
geometry rather than about art. Taking any texture with a file path throws the
rule away: a loot row carries the item's icon at its left edge, and that backs
the name sitting beside it, which is 26 rows excused a rule they were never
measured by. Demanding a texture pinned corner to corner throws away the aura
square's icon, which is cropped and single-anchored, and fails 168 strings that
are right. What settles it is measuring the texture against the frame it is in
rather than against the glyph: an icon that is most of its square is a surface,
and a sixteen pixel icon in a two hundred pixel row is a surface for nothing but
itself.

Three sites are allow-listed with the reason written next to them, and each is
excused one rule rather than all three. The chat window is the one place the
three roles do not settle it: its text size is a slider from 9 to 20 and its
background is a slider to 0, and at the bottom of both there is no role that
works. It stays flat until one of the two sliders gets a floor. The
timer over an aura square is the other: it sits above the art rather than on it,
so it has the world behind it and takes a shadow anyway, because at 8 to 14
pixels an outline closes the hole in a 6. `UI/Aura.lua` already argued that
trade where it is made; the allow-list is where it is now enforced.

### Five icons, cut onto the letters they replace

The chevron on a folded group was a lowercase `v`, the shut one was a `>`, the
close button was an `x` and both ends of every stepper were `+` and `-`. Those
are not icons, they are the letters that look most like icons, and at ten pixels
of Arial Narrow they read as a typo.

`Media/Glyphs.ttf` is five marks of Font Awesome Free Solid, subset by
`scripts/bake-glyphs.sh` out of the copy already on the machine that builds it.
It is 2,172 bytes.

The part worth writing down is where the five sit in the font. They are not on
Font Awesome's own codepoints, they are on `v`, `>`, `x`, `+` and `-`. So no
call site carries a codepoint escape, no call site knows it is drawing an icon,
and nothing anywhere checks whether the font loaded: a client that refuses the
file leaves the font object empty, `UI/Text.lua` puts Arial Narrow in its place
at the same size, and the window draws the letters it drew last week. The
fallback is what the code was already doing, so there is no second path through
any caller to get wrong.

`ns.UI.Glyph` is a string in that face and `ns.UI.Button` takes `glyph = true`.
A glyph is not an icon here: an icon is the game's own art for a spell and
`ns.UI.Icon` still means that. Marks draw at 10 pixels against the body's 12,
because a Font Awesome glyph fills its em box and a letter of Arial Narrow uses
about two thirds of one.

The font is under the SIL OFL, which reserves the name Font Awesome, so the
subset goes out as WarriorKit Glyphs with the licence beside it in `Media/`.
`check.sh` learned that Media holds three kinds of file: a texture is TGA or BLP
with both sides a power of two, a font is a TTF and is measured for nothing but
has to have its licence next to it, and a licence is allowed there only because
its font is. `release.sh` fails a zip missing either file, and the harness walks
every string in the window, asserts the five marks are in the glyph face and
everything else is not, and drives the branch where the client refuses the file.

### The /wk window is sorted by what you came to change

`Core/Menu.lua` put a WarriorKit button in the client's own Escape menu last
week, and that raised the stakes on what the button opens. Until then the only
way in was a slash command, so everyone who opened the window had already read
something about the addon. Now somebody who has never heard of it can press
Escape, see a name and click.

What they found was eighteen rail entries, each one a registered part with a
capital letter on it. Three sat below the fold of a 390 pixel view and nothing
on screen said so. Behind them were 44 tabs, 134 controls and 134 notes holding
40,268 characters, about fifteen pages of prose with switches embedded in it.

**A section names its own group.** `ui.Header(title)` is now
`ui.Section(title, group)`, and the panel declares eight groups: Start here,
Fighting, You, Them, Readouts, The screen, Chores, Under the hood. A group that
does not exist is a login error rather than a section quietly landing in a
default. Eight entries come to 184 pixels, so the rail fits a 390 pixel view
folded shut, which the eighteen never did.

That also lets one part's sections sit apart. `UnitFrames/Panel.lua` has three
and two of them are about your own frames while the third is about enemy
nameplates; they are in **You** and in **Them** now without a line of code
moving between files.

`order` no longer decides rail position, because the rail is not made of parts.
It decides where a part's sections sit inside a group, and `ns.Register`
refuses anything that is not a whole number or that another part already took.
`artwork` and `minimap` were both on 8 and their relative position was whatever
`table.sort` felt like.

**The rail folds.** The group you are in stands open with its sections listed
under it, indented, and choosing one is a single click on the thing you came
for. It replaced a strip of tabs across the top of the page, which had two
faults. The strip could only show the sections of the group you were already on,
so the window never showed more than an eighth of itself at once. And Fighting's
eleven wrapped onto three lines of stubs, which took a fifth of the page's
height to say what a column says in a column.

One group is open at a time. Clicking the open one shuts it and leaves its page
up, with the mark moved onto the group's own line, so the rail can be folded
flat to eight lines without the window going blank; clicking a shut one opens it
onto whichever of its sections you were last reading. The rail is 180 pixels
wide because a section title has to be readable in it, and the window is 608 so
that the page keeps the 400 pixels it had. Open is taller than the view when
Fighting is out, and the rail scrolls; whatever is selected is kept inside the
viewport. The title of the section you are on is drawn over the page, on the
hairline that used to be the underside of the tab strip.

**One switch per part, drawn by the panel.** A part declares
`switch = { key, label, apply }` and the panel draws the check box in the same
place on every part's first page. Eleven features had each written their own for
the same idea: `show the row`, `show the icon`, `Show the meters`, `Show the
swing bars`, `show enemy bars`, `draw the WarriorKit chat window`. The rail now
marks any group holding a part that is on, which is the one question the window
could never answer without opening forty five pages, and **Start here** is a
whole page of nothing but those switches and their ledes.

**Notes are gone and three capped calls replace them.** `ui.Lede` is one line
under a section title at most 160 characters, `ui.Hint` is at most 200 and draws
in the addon's own tooltip on hover, and `ui.Reading` is a live number in the
accent colour that never wraps. 44 ledes, 75 hints and 81 readings come to
14,375 characters against 40,268, and the harness fails past 16,000. The
reasoning the notes carried moved to `docs/README.md`, which is where explaining
the addon belongs and which can be read on a second monitor while the game runs.
Five parts had no notes there at all before this: the feeds, the chat window,
the minimap, the performance tab and the breakdown were documented only inside
the panel.

**A search field in the title bar, focused when the window opens.** Every
control records its label, its section and its group as it is built. Typing
filters and each result reads `group / section / label`; clicking one opens the
group, selects the section and marks the row. Emptying the field puts the page
back. It did not while the tab strip existed. The strip returned and the section
under it stayed hidden, so the window sat blank until you clicked a tab, and the
harness now clears a query and checks the page is there.

A query matches the label, the section title, the group name and the part's
slash words, so typing `skin` finds the frame controls that `/wk skin` drives.

**Four kit calls for the four knobs every part had reinvented.** `ui.Zoom` has
no range because there is one and it is 1 to 3; four files had declared
`LOW_ZOOM, HIGH_ZOOM = 1, 3` at the top of themselves. `ui.Opacity` has no range
for the same reason, and the meters' `bar opacity` is called `background` like
the other two. `ui.Size` keeps the caller's range, because a feed is 200 to 520
wide and a minimap is 120 to 300, and writes `px` after the number so four pages
can all say `width`. `ui.Count` is rows and bars, and `list bars` is called
`rows`. Charge's three icon steppers became `icon size` on the button and a
`size` and a `height` in a section called **The icon over the mob**.

Three controls were deleted: the zoom stepper on Buffs, Feeds and Meters. Those
three are read between fights, and the argument for a private zoom is that a
thing you read mid swing has to stay exact at a size you chose. That covers the
enemy bars and the swing timer and it does not cover a loot feed. Every setting
they wrote is still there and every slash word still takes it.

Nothing about the slash commands changed. Every word keeps working, `/wk` on its
own still opens the window, and the words are sitting inside people's macros.
Nothing on the game screen moved.

Section 16 of the harness grew the rules: every section names a group that
exists, no group holds two sections with one title, no title repeats its group's
name, every lede and hint is inside its cap, every reading fits one line, no
label is empty or ends in whitespace, all 147 labels are findable by typing them
in full, and every part with a boolean in its defaults declares a switch or is
allow-listed with a reason. The fold has its own: one group open at a time, one
line under it per section, every line short enough to be read whole in the
column it sits in, and the page still up when the group it belongs to is folded
shut over it. `check.sh` got the half a grep can settle, with each
rule naming the kit call to use instead.


### The client's own aura row has a switch of its own

`/wk auras off`, and the corner of the screen is empty: your buffs, your
debuffs and the temporary weapon enchant beside them. The panel carries the same
switch on the frame skin's aura tab, under the rows this addon draws.

It exists because the sweep that was already hiding those buttons could not be
relied on to. The skin hides them one name at a time, `BuffButton1` through
`BuffButton32` and the three enchant buttons, because a button the client builds
the first time you carry nine buffs has no other handle. A name this backport
spells some other way stops the sweep and hides nothing, which is what two
reported screenshots were: the client's row drawing over ours, in gold, saying
the same thing.

So the switch takes the other handle. It hides `BuffFrame` and
`TemporaryEnchantFrame`, two globals rather than fifty-one names, and every
button the client parents to them goes down whatever it is called. The two
mechanisms never argue over a region. The sweep holds buttons, the switch holds
their frames, `ns.Strip` marks what it holds, so turning either off gives back
only what that one took.

On by default, and on a default install you will not see it do anything: the
skin is drawing your auras under the block and the client's buttons are already
hidden. The switch is for the player running with `skin off` or with the player
frame left alone, whose buffs are the client's row and nothing else. That player
loses the last reading of the stone on their weapon when they switch it off,
because the missing-buff row only speaks once the stone has run out, and the
panel note says so rather than letting them find out in a raid. Right click to
cancel a buff goes with the row too.

`/wk status` says which of the two frames this client carries. Nothing hidden
and neither frame found is a client that names its aura frames something else,
which is a different failure from a switch that did nothing.

Section 14 asserts both frames down, the strip holding against the client
showing its own row again, and both frames back on the way out. The harness
client parents `BuffButton1` and `DebuffButton1` to `BuffFrame` and
`TempEnchant1` to `TemporaryEnchantFrame`, the way both clients do.

### The addon is in the game menu, and there is a spec for the window it opens

A slash command is a thing you have to be told about. Escape is a thing everyone
already presses. **There is one button in the client's own game menu now**, it
says WarriorKit, and it opens the panel `/wk` opens. No setting guards it,
because a check box that hides the way into the settings is a check box nobody
can find their way back to.

The menu belongs to Blizzard and the two clients this addon ships for do not
build it the same way, so `Core/Menu.lua` names no Blizzard button, reads no
localised string and assumes no count. It reads the anchor chain the menu is
already laid out with, hangs our button off the end of it and grows the frame by
exactly what it added. Our button takes the foot's anchor verbatim and the foot
takes the same anchor again off ours, so whatever gap the client leaves between
two buttons is the gap above ours and below it. A client that lays its menu out
some other way gets no button, no error, and a reason in `/wk status`.

The foot is the button nothing else hangs off. Every button in the column
contributes what it hangs off, shown or hidden, and only shown ones can be the
foot, because Blizzard hides buttons in that column and a walk that skipped one
would lose track of the button above it and find two feet where there is one.

The work is on the menu's `OnShow` rather than done once at login, because a
client that lays its own menu out on show will have dropped us out of the chain
by the time it is next opened. Everything the attach reads it reads fresh, and a
run that changes nothing writes nothing. A version that grew the frame on every
show would reach the top of the screen inside a session.

**`SPEC-menu.md` is the redesign of the window that button now leads to**, and
it starts by counting what is in there: eighteen entries in the rail, 44
sections behind them, 134 controls, and 134 notes holding 40,268 characters of
prose. One note per control, exactly. The spec asks for eight groups a player
can rank instead of eighteen module names, capped prose in three narrower kinds
with what is cut moving to the README, one declared switch per part so you can
see what the addon draws without opening 44 tabs, four kit calls for the four
knobs that were reinvented once per part, a search field, and a Start here page
of nothing but switches. Nothing in it changes a slash word.

### The aura square reads the way the client's own row does

Reported from the game with a screenshot of Blizzard's buff row above ours. Two
rows of icons, one over the other, saying the same kind of thing in two
different languages: theirs `14 m` in gold above the icon, ours `4m` in white
inside it, and the number inside the art was the one you could not read.

**The number moved off the art and into a strip over the square.** A number
written on an icon is a number over a picture somebody else chose. 27 on a pale
bandage and 27 on a dark bleed are two different readings, and the drop shadow
behind it only ever rescues one of them. Over the square it has the world
behind it, which is a worse background in theory and a better one in practice,
because nothing else is competing for those pixels.

That makes the widget taller than it is wide, so it is two frames now: the
square, which is the art and the hairline and the sweep, and the widget, which
is the square plus the strip. `Aura.Size` hands its caller back a width and a
height instead of one number, and both rows put what comes back into their
layout node. The strip is the timer's own type height and a pixel of air, taken
up to whole pixels so the art below it still starts on one. The mouse stays on
the art: `SetHitRectInsets` keeps the strip out of it, because a tooltip that
opens over blank sky above an icon is a tooltip nobody asked for.

**The colour is the client's rule now, and so is the format.** Gold while the
time is counted in minutes or hours, paper white once it is counted in seconds.
That is the same fact the unit already carries, which is why `Tint` takes the
unit rather than the seconds. The string is written out the way the client
writes it, with the space and the unit on every reading: `14 m`, `2 h`, `56 s`.

The amber-under-ten, red-under-five ladder this replaces was not wrong about
what is urgent. It was wrong about who decides. Half the auras on the screen
are drawn by the client in a row of its own, and two rows that disagree about
what a colour means are two rows you have to read separately.
`Color.text.duration` is the client's `NORMAL_FONT_COLOR` written down rather
than read, for the reason the class colours are written down: a global this
addon does not own can be absent on one client or moved by another addon. It is
not a token, because it stands over the world rather than on a fill the palette
caps.

Sections 6, 7 and 14 measure all of it. The bar's height is built from the
square the setting draws plus the strip over it rather than from the setting
alone, section 7 asserts the string and its colour at both ranges, and section
14 asserts the anchor, the strip in whole pixels and the hit rect at three
square sizes. The harness client records `SetTextColor` for that, since one
string in the addon says two things in two colours.

`LayoutWidget` on the enemy bars gave its tracked row up to `IconRow` on the way
through, and shape.lua's entry for it comes down from 203 lines to 185.

### The aura square sweeps, and says the time the way the client does

Reported from the game with a screenshot of Blizzard's buff row beside ours:
theirs reads `28 m`, ours read `1972`.

Both halves of that are fixed and they are one reading between them.

**The square sweeps.** A wedge over the art, drawn by the client's own Cooldown
frame, reversed so it fills as the aura runs out rather than emptying the way a
cooldown does. That is the difference worth having: a number is a thing you read
and a wedge is a thing you see, and a row of twelve squares is read at a glance
or not at all. The refreshed square is the bright one and the square about to
drop is the dark one.

The wedge needs a fraction, so both scans now carry the aura's duration beside
its expiry. A temporary weapon enchant has an expiry and no duration anywhere in
the client's API, so its square counts down in text and never sweeps. That is
the truth about what is known rather than a wedge drawn against a guess.

**The number is in the largest unit that still says something true.** Whole
seconds, at any range, is what put four digits across a sixteen pixel icon: a
half hour buff read `1972`, which is a precision nobody uses, over the art that
says which buff it is. It reads `28 m` now, and `2 h`, and seconds under a
minute, rounded up in every unit so a square never reads 0 while the aura is
still on the unit. The type is sized at under half the square rather than six
tenths, because the string is four characters wide now and was two.

The colour of that number, and the exact format of it, are the entry above:
this one landed an amber and red ladder of our own, and the client's own gold
and white replaced it before either shipped.

Measured in section 7, which now asserts the reading and its unit, the two
numbers handed to the sweep, and that the sweep is reversed. The harness client
records `SetReverse` for that, because an aura sweep and a cooldown sweep are
the same two numbers and opposite pictures.

`UpdateWidget` on the enemy bars gave up its tracked row to a function of its
own on the way through, and shape.lua's entry for it comes down from 142 lines
and 41 branches to 123 and 31.

### The aura square draws its art again

Reported from the game with a screenshot: the squares over the block show their
timer and nothing else. No icon, no hairline, at a size that had been working.

Two things could do that and both are fixed, because the screenshot cannot tell
them apart and either one on its own leaves the same empty square.

**Every region of the square has a size of its own now.** The art hung off two
opposite corners of the square and each hairline off two adjacent ones, so all
five were rectangles the client had to derive from a frame that had just been
resized under them. The square's edge is a setting, which makes it the one
widget in the addon that gets resized while the addon is up, and a region the
client declines to work a rectangle out for draws nothing and raises nothing.
The timer cannot fail that way, because a font string is as big as its text and
is anchored to a corner rather than sized by one, which is exactly why a number
was the only thing left on the screen. `ns.EdgeSize` takes an optional length
for this and nothing else passes it.

**An aura with no art falls back to its spell's own texture.** A client is
allowed to hand back an aura carrying no icon, and these rows are the only
reader in the addon that takes one off the aura rather than off a spell it
already holds: the enemy bars draw the list you asked them to watch and have
`ns.SpellTexture` for every entry in it. So the same picture is asked for from
the other end, at the cost of one call on the aura that has no art rather than
one on every aura.

Both are measured. Section 14 lays the rows out at 12, 20 and 28 and asserts the
art's inset and size, both hairlines, and that an aura answering no icon still
draws the spell's. Reverting either fix fails the run.

### `/wk skin probe` measures the aura square rather than repeating the setting

Reported from the game with a screenshot: the aura squares draw their timer and
nothing else. No art, no hairline, at a size that had been working.

The screenshot settles more than it looks like it does. The block is 68 pixels
tall, the two numbers over it sit 31.5 apart, which is a 28 pixel square and the
3 pixel gap, and they are right aligned on the block's top corner one gap up. So
the row is exactly where the row belongs and the layout is not what is wrong.
What is gone is everything that is a region of the square, because a font string
draws off its own anchor whatever the square does while the art and the hairline
take their size from the square's edges.

Every number the probe printed was a number that went in rather than one the
client used, which is why none of them said anything about this. Each row's line
now carries the width the square came out at, the width the art came out at,
whether the art was ever handed a texture, and how thick the hairline is, all
read back off the widget.

**The resize itself is measured now.** Section 14 lays the rows out at 12, 20 and
28 and asserts the square, both corners of the art's one pixel inset, the
hairline and that the square still holds its texture afterwards. It passes,
which is the point: it says the arithmetic in `Auras.Place` is not the fault and
narrows what is.

**The harness could not have caught an inset bug at all.** The client stub took
`SetPoint("TOPLEFT", x, y)`, which is how every inset in the addon is written,
and stored the two offsets in the fields `GetPoint` hands back as the relative
frame and the relative point. So the offset read back as zero and the relative
frame read back as a number, and anything asserting on an inset was asserting on
nothing. The stub models both shapes.

### The client's weapon enchant goes off the screen with the rest of its auras

Reported from the game: with the addon's own rows on, the client is still
drawing auras.

`TemporaryEnchantFrame` was the one thing the sweep deliberately spared, and
the reason expired in the change directly below this one. While nothing here
drew the enchant, the client's copy was the only reading of the stone on your
weapon and taking it down would have taken that reading with it. The row draws
both hands at its own head now, so what the corner held was a second copy of a
number the square already carried, sitting where you have to look away to read
it. `TempEnchant1` and up are swept like `BuffButton1` and up, and an aura this
addon draws is back to having exactly one place on the screen.

**It is a run of its own rather than the tail of the buff row's names.** The
sweep stops at the first name the client has not built, because the client
builds those buttons on demand and in order, and the two names do not fill
together: on a character carrying six buffs the walk stops at `BuffButton7` and
a single list of both would never reach an enchant. So each name the client
counts from 1 carries its own mark, and `/wk skin probe` adds them up.

### The weapon enchant leads your buff row, and the square can be bigger

Reported from the game with a screenshot: the squares are too small and the
sharpening stone is nowhere.

**The enchant was left to the client and the client's row is hidden.** That was
the wrong end of the trade. A temporary weapon enchant sits at no aura index at
all, so `GetWeaponEnchantInfo` is the only call that knows about it, and hiding
`BuffFrame` took the last reading of it off the screen. Both hands now lead your
buff row, read through `Buffs/Upkeep.lua` because that file already counts the
returns rather than picking one of the three shapes the call has had. The square
borrows the weapon's own art, the way Blizzard's enchant button does, and
hovering it opens the item's tooltip, because the enchant is a line on the item.
A client with no such call adds nothing and says nothing.

**The size ceiling was a constant that stopped being true.** `/wk skin aura`
ran to 32, which was the block's height when the rows were written. The block is
`/wk skin height` and runs to 72, so the ceiling follows it: the rule was always
that a square should not be taller than the frame it hangs off, and now the rule
is what is written down instead of the number it came to that day.

**The flag reached the table and not the row.** `enchants` was on the spec in
`ROWS` and `Auras.Build` copies named fields onto the row it builds, so the row
never saw it and drew nothing. The harness caught it on the first run, which is
the whole argument for asserting a feature rather than looking at it.

### The aura rows go on both sides of the block and run outward

Both rows sat under the block and chained, debuffs then buffs. Asked for from
the game: buffs over the block and debuffs under it, and every row running
outward from the middle of the screen rather than in from the portrait.

**Nothing chains any more, and that is the point.** Each row anchors to the
block itself, buffs on its top edge and debuffs on its bottom. A target picking
up a raid's worth of bleeds moved the buff row before and now moves nothing:
the two rows cannot push each other about because neither one is holding the
other up.

**Every row starts on the gauge end.** That is the edge facing the other block,
which is the opposite corner to the portrait, and it comes off `spec.mirror`
the way everything else about the mirroring does. So your rows run right to
left and the target's run left to right, and the four of them read outward from
the corridor the two blocks are already mirrored about. `reverse` and `justify`
on the `ns.UI.Flow` node both flipped for it.

**A row grows away from the block.** `lineOrder` was already in `ns.UI.Flow`,
put there for the enemy bars' debuff row, and it is what puts line one against
the block on the row above it: the frame is sized for a full list and fills
from its bottom edge up. Nothing new was needed in the layout engine.

**The row's height stops changing on the tick.** It is set once, to what a full
list comes to. No row hangs off another one now, so a height that tracked the
count buys nothing, and on the row above the block it would cost that row every
square it has: those are placed against the frame's bottom edge, and that edge
is the one an anchor on the block's top holds still. `Height` and the
per-row line count go with it.

**Target of target is cleared by dropping past it rather than by hanging off
it.** It is parked under the target block on the portrait corner and the debuff
row now runs from the other corner, so an anchor between them would inset the
row by the difference between the two widths. `Perch` still says the frame is
there. What is taken off it is its height, converted into the block's units
because it is drawn at a scale of its own, and the row keeps hanging from the
block's own corner with that much more drop. Read on a change of head, not on
the tick, so it costs one comparison against nil while the target holds still.

### Your own buffs and debuffs, under your own block

The aura rows were built for the target only, on the argument that Blizzard
does not hang your buffs off `PlayerFrame` at all. That was the wrong half of
the job once the target became the player mirrored, and it was reported the
plain way: "I do not see them anchored to the character." The two blocks are
one HUD. What is on you belongs beside what is on the target, not in the corner
of the screen you have to look away to read.

**The player is one entry in `ROWS` and nothing else moved.**
`UnitFrames/Auras.lua` was already a table keyed by frame, so the player's two
rows are the same rows off the same settings, drawn by the same code and hidden
the same way. `UnitFrames/Skin.lua` is untouched: it already called `Build`,
`Place`, `Style` and `Update` for every frame it skins, and the player simply
started having rows to draw. Both differences come off the spec the file
already had. The player block is not mirrored, so its rows start on the corner
the portrait is on and run right. And nothing is ever parked under it, so its
debuff row hangs on the block itself while the target's hangs under target of
target.

**Two things go off the screen with the client's row.** Cancelling one of your
own buffs is a protected call, so a square drawn here cannot offer right click
to cancel. Getting that back means a secure button per square, which is its own
piece of work and is not worth starting until somebody misses it. The temporary
weapon enchant is the other, and it is the reason `TemporaryEnchantFrame` is
deliberately left alone: it sits at no aura index, so nothing here can find it,
and hiding it would take the only reading of the sharpening stone on your
weapon off the screen. `Buffs/Nag.lua` says when it is missing and says nothing
about how long the one you have has left.

**Each row asks the client for its own ceiling by name.** `MAX_TARGET_DEBUFFS`
for the target and `BUFF_MAX_DISPLAY` for you, out of a `max` field on the spec
rather than out of a branch on the filter that only knew about the target.
`Auras.CountCeiling` reads across every frame instead of off the target's, so a
row given a longer ceiling than the others cannot end up with a setting that
refuses to reach it.

**One harness check was finding the portrait square by luck.** Section 10 walks
a unit frame's children for one pinned to the block, and the two aura rows are
pinned to the block as well. On the target that never showed, because the rows
hang off target of target instead. On the player it came back with the debuff
row and failed on the spot. It now skips the children that carry a name, which
is the real difference between them: every frame this addon has to be findable
from a macro is a named global, and the portrait square is not one.

### The target block is the player block mirrored, and the gap setting is gone

`/wk skin gap` is retired. There is no number between the two blocks any more,
because the distance across was never a preference and pretending it was is
what made the pair look wrong.

**A fixed distance apart is not a mirror.** The link anchored the target block
120 pixels off the player block's far edge, which put the line the two mirrored
about wherever Edit Mode had last left the player. In game that is left of
centre and low, so the pair sat off to one side facing each other. Reported
from the game, and the specification was wrong rather than the code that
implemented it.

**The target's facing edge is the player's reflected in the middle of the
screen.** Reflecting a point about the centre moves it 2 * (centre - point),
read in screen units because that is the only space two frames on different
scales share, then divided back into the frame's own units because that is what
an anchor offset counts in. The corridor between the blocks is now twice the
player's distance from the centre, so you widen it by dragging the player
outward and you close it by dragging the player in. Drag the player across the
centre and the pair crosses, which is what a mirror does and is worth knowing
before it surprises you.

**Dragging the target still means something, and it means one thing now.** The
drop sets the level, which is how far the target's top edge sits below the
player's. The sideways half is measured and thrown away, and the re-anchor puts
the frame back on the mirror line, because opposite the player is the only place
it can go. `Landed` reads two edges instead of four for it.

**A pass that cannot measure writes nothing.** `Mirrored` comes back empty on a
pass where the client has not resolved the player block's position yet, which
happens once at login. There is nothing to fall back to now that the fixed
distance is gone, and that is the better answer. The target stays on the point
it arrived with and the next pass asks again, instead of jumping to an invented
distance and then jumping a second time. `/wk status` says the rest follows on
the next pass rather than blaming combat for it.

Three harness assertions changed with the specification rather than being
adjusted to fit it. What they assert is the mirror stated as the thing you can
see: the midpoint of the two facing edges is the middle of the screen, at three
UI scales. The stub parks the player right of centre on purpose, so a pair
anchored a fixed distance apart fails all three. A fourth asserts `skinGap` is
still absent from the settings, because a distance that quietly became a number
again would pass every other check while the mirror only held for whatever value
it happened to hold. The key is in `RETIRED`, so a saved variable written before
this is cleared rather than left to be found.

### The target's aura rows are the addon's now

Blizzard drew the target's buffs and debuffs and the skin worked around where
they landed. It draws them itself instead, and the machinery that did the
working around is deleted.

**The row could not be moved, which is why it had to be replaced.** Every icon
in the client's row is a child of a secure unit button, so an addon may anchor
one out of combat only, and the client re-anchors the head of each row on every
aura the target gains or loses. Anything placed there is back inside the gauge
one refresh into the first pull.

What the skin did instead was move the edge the client measures from. It read
the lift off an icon the client had already placed, fitted the target frame to
the block plus that lift, and let the client's own arithmetic drop the icons
under the block. It worked, and it cost four things: a number that only settled
on the first target carrying an aura, a `UNIT_AURA` handler waiting for that
moment, a frame that was not the same rectangle as the block, and a mouse region
inset to pull clicks off the strip underneath. All four are gone. All three
frames are the block exactly.

**One square, two rows.** `UI/Aura.lua` is one aura drawn: the cropped icon, a
hairline round it, the seconds left along the bottom, the stack count in the
corner, and who cast it said by draining the art rather than by adding a colour.
It came out of `UnitFrames/EnemyBars.lua` rather than being written beside it,
so the debuff row on a nameplate and the row under the target block are the same
code and cannot drift apart. The bars lost 39 lines and draw the same picture,
with one difference: the stack count is inset by one screen pixel now instead of
one unit, so at `bars zoom 2` it stops sitting two pixels in while the border
beside it stays at one.

It is deliberately not `UI/Ability.lua`. That file's whole vocabulary is ten
reasons a press does or does not land, and it hangs the countdown off
`status == "cooldown"` because below the global there is nothing to count. An
aura has no cost, no range and no stance, its timer is the thing you actually
read, and the six textures a button needs for its pushed, equipped and armed
states are six per square nobody would ever see.

**Yours go first.** The client's order is the order the auras landed in, so on
anything with a raid on it your Rend is somewhere behind a screen of other
people's bleeds and a row capped at twelve loses it. Sorting would allocate on a
ticker; two passes over the same list do not, and the answer is the same.

**`ns.UI.Flow` never runs on the ticker.** Every square is placed once at layout
for the longest the row is allowed to be, the tick shows a prefix of them and
moves none, and the only thing that changes is the row's own height, which is
what tells the row below where to sit. The gap between rows is folded into each
row's height, so a target with no debuffs puts the buff row against the block
rather than one gap below where the debuffs would have been.

**Hiding the client's row is a sweep, not a walk.** Those buttons are built on
demand, so it cannot be done once when the skin goes on, and walking all
forty-eight names every tick to find that out would be silly. They are built in
order, so the only one that can have appeared since the last look is the one
after the last one hidden: one global lookup per row per tick once the row has
settled. `ns.Strip` refuses on a protected region in combat and says so, so a
button the client builds mid fight is retried and lands when combat drops.

**Target of target is parked on exactly the corner the rows hang from.** `Perch`
tells them it is there and the first row hangs under it rather than through it.
That happens on the ticker rather than at layout, because the client shows and
hides that frame with the unit and a target with nothing targeted would
otherwise leave a hole the size of it. Writing it there is allowed in combat
where re-anchoring target of target itself is not, for the one reason that
matters: that frame is ours.

**Your own buffs stay where they are.** Blizzard does not hang them off
`PlayerFrame` at all. They are `BuffFrame`, a top level Edit Mode system carrying
thirty-two buffs, sixteen debuffs, three temporary weapon enchants and right
click to cancel, and none of the payoff above is on that side. What this addon
has to say about your own buffs is the nag row's, which reads
`GetWeaponEnchantInfo` as well as your auras and so can see the sharpening stone
that appears at no aura index.

`/wk skin auras on|off`, `/wk skin aura 20`, `/wk skin debuffs 12`,
`/wk skin buffs 8`. Turning the rows off leaves the target with no row at all,
which is the honest answer rather than an oversight: the frame is the block, so
handing the client's row back would hang it in the gauge. `/wk skin off` gives
it back, because that is what gives the frame its size back.

**Two gates moved in the same change.** `UnitFrames/Feature.lua` hit the 800
line limit, and the page came out into `UnitFrames/Panel.lua` rather than a
fourth entry on the length allow-list; the seam was already there, since nothing
in the page decides anything and nothing left in `Feature.lua` draws. That also
paid off the entry item 8 had added at 879, so the allow-list is back to three.
`UnitFrames/EnemyBars.lua` ratcheted from 2050 to 2011 and `UnitFrames/Skin.lua`
from 2012 to 1934.

### A breakdown of what this character actually does

One row per ability, kept between sessions: how much of your damage it is, how
often it lands, how often it crits, what it averages, what its best hit was and
what stopped it when it did not land. It is the question the meters cannot
answer, because a meter totals the pull you are in and forgets it when the next
one starts. This never forgets and never reports a rate.

**Counters, not history.** Every question it exists to answer is a ratio over
counters. Crit chance is crits over landed hits, miss chance is the miss table
over attempts, and what share of your damage is Thunder Clap is a sum over rows.
None of them needs the event that produced it kept, and keeping the events is
the one thing this could not afford. An evening of solo play is tens of
thousands of combat log lines, and the client writes saved variables by
serialising the whole table to Lua source at logout. So the table grows with the
number of abilities you use and never with the number of swings you take.

**There is no flush, so there is nothing to flush.** An addon cannot ask the
client to write saved variables; they are written at logout, at a reload and on
quitting, and the only way to force one in between is `ReloadUI`, which is why
Titan puts a confirmation box in front of changing a profile. So this does not
accumulate into a private table and copy it across at `PLAYER_LOGOUT`. It counts
straight into the table the client serialises, and there is no logout hook that
can be forgotten.

**Crit damage is kept apart from total damage**, and that is what makes both
averages come back out. The average normal hit is the damage that was not a crit
over the hits that were not crits; the average crit is the other half. A single
blended average of a 500 and a 900 is 700, which describes no hit the character
has ever landed, and it cannot be taken apart afterwards. Four counters instead
of two, and the harness asserts both halves.

**A miss keeps its type.** The client names ten outcomes and the table holds the
ones that happened to you. A dodge says you were in front of it and a parry says
something about the target, and one pooled "missed" number teaches neither.

**Rates are banded by the target's level against yours.** In this era level
difference drives miss and dodge hard, and a lifetime crit rate pooled across
grey trash and an elite is an average of two unrelated fights. There are four
bands and the fourth is the honest one: the combat log carries no level, so it
is only ever learned from a unit token, which means the mob was your target or
had a nameplate up. Anything you hit without ever seeing lands in "level not
seen" rather than being quietly counted as your own level, which is the answer
that would flatter every rate in the table.

**Stored by spell id, added up by name.** A name is localised and collides: the
eight ranks of Heroic Strike are eight ids and one word. Reading by id would
give eight thin rows nobody wants and storing by name would throw away the
ability to look at one rank alone. The pane says the one thing that does not
survive the roll up, which is that a rate pools across ranks correctly and an
average hit does not.

**Only what swings at something is listed.** Battle Shout, Charge and every
stance are counted like everything else and kept out of the table, because in a
ranking by damage they can only ever be a run of zeroes above the rows you
opened it to read. They stay in the store, since an ability that does nothing
today is one damage event away from being worth a row. An ability that has only
ever been dodged does get listed: no damage across four dodges is not the same
fact as no damage because the thing does none.

There is one ranking and no control for it. It ranked by casts and by landed
hits as well for a while, off three chips on the window, and both of those
answer a question this table does not ask. Ranked by press count Battle Shout
sits above Mortal Strike, which reads as a bug rather than as a view.

**Only your own hits.** `Meter/Meter.lua` reads the same event and counts
everybody, deliberately, because it is answering what the group did to this
pull. Counting the group here would grow the table by every stranger you have
ever been in a party with, and that is the one filter keeping it bounded.

The table opens from the meter. It lived on a settings page first, on the
argument that a month of play summed up is read between sessions rather than
during a pull and does not need a frame to place. That argument was about where
the numbers are kept; it said nothing about how you get to them, and the way you
got to them was six clicks into a settings tree. The meter is what you are
looking at when the question occurs to you, so a left click on the meter header
opens the table and a right click still swaps the meter between damage and
healing. Escape or the cross closes it, and there is no frame at all until the
first open and no ticker behind it ever.

`/wk breakdown open` opens the same window and `/wk breakdown` prints the
ranking to chat. Throwing the record away takes two presses or `reset yes`,
because a mistyped word should not be able to delete a month of counting.

### Loot and the combat log, as feeds you can scroll

Two columns of what just happened, newest at the top and older underneath.
A loot row is the item's icon, its name in its own quality colour and how many
dropped. A combat row is three columns: what happened, who the other party was,
and the number. Down the left edge of each row is a stripe, so a pull reads as a
ribbon before you read a word of it: quality for loot, and for combat which way
the blow went, white out, red in, green healed and grey missed.

**A combat row has to say who, and for a while it did not.** The rule was to
draw the spell where there was one and the other party's name where there was
not, which put "Overpower 321" and "Plains Creeper 26" on the screen in the same
shape, neither of them saying who was on the other end. So the name column is
now always what happened, a spell or the client's own word for a swing, and the
dim middle column is always who, reading "on Plains Creeper" for something you
did and "from Plains Creeper" for something done to you. The number column is a
fixed width, so a run of hits reads as a column rather than as a ragged edge.

A critical draws its number in gold **and** puts a mark after it, `871!`. Gold
alone was the whole signal, on the one row in the feed that exists to be
noticed, and a signal carried by hue alone is one a colourblind player does not
get. The same argument runs one level up in the stripe, which is why the middle
column carries the preposition rather than leaving the direction to the colour.

**Entering and leaving combat draw a band across the feed.** Without them a feed
is one unbroken column and the only thing separating this pull from the last one
is a gap in timestamps a row does not carry. A marker is a band the width of the
row with a word on it: no icon, no middle column, nothing an event can look
like, because a marker that could be read as a hit for nothing is worse than no
marker at all. The band at the end of a fight says how long it lasted, which is
a fact nothing else in the addon reports: the meters total a fight and reset on
the next one, and neither of them ever says how long you were in it.

A pair of markers with nothing between them is left standing rather than
swallowed. That pair is information too. It says you were in combat and nothing
that happened in it cleared the floor, which is exactly what somebody who has
set that floor too high is looking for.

`Feed:Mark` is a capability of the widget rather than something the combat feed
fakes with an ordinary row, because "one set of events ends and another begins"
is a thing any feed wants, and a marker built out of an ordinary row is one an
ordinary row can be mistaken for.

Both feeds ship wider than they did, 260 for loot and 320 for the combat log,
and the combat feed shows twelve rows rather than ten. Three columns need the
width, and a pull produces rows an order of magnitude faster than a corpse does:
at ten rows a fight scrolled off the bottom before you had read the top of it.
The width slider now runs 200 to 520 rather than 140 to 420, because 140 units
is not a row, it is four things clipped to two glyphs each.

**One widget, two feeds, and that was the point.** `UI/Feed.lua` knows about a
column of entries and nothing else: not where it sits, not whether it is
switched on, not what an item or a swing is. `Feeds/Stream.lua` is the frame one
of them sits in and the seven settings behind it, found by prefix so both
streams read the same six. What is left in `Feeds/Loot.lua` and
`Feeds/Combat.lua` is only the capture. A third feed is a file and a table.

**The rows do not move.** There is one frame per visible row, built once,
anchored once, and never anchored again. Arrivals go into a ring and scrolling
is an offset into it, so ten rows repaint whether the feed holds ten entries or
four hundred, and a scroll costs the same as a drop. `UI/Log.lua` already
refused to build a chat window out of `UI/Stack.lua` for this reason and the
constant here is worse: a stack would remeasure four hundred entries every time
a mob died. It also means there is no clipping to arrange and no ScrollFrame to
probe, because the rows exactly fill the space.

The ring reuses its tables, and the harness states that by identity rather than
by measuring it: the four hundred and first drop has to land in the table the
first one used. Nothing in either feed is on a ticker. They change when
something happens to you and when you scroll them, and never in between, which
is why a row carries no clock and the time of day lives in the tooltip.

**An arrival must not scroll the feed under you.** Scrolled back into history,
a drop pushes the list down under the offset rather than under your eyes. That
is the defect that would make the scrollback useless and it cannot be seen in a
screenshot: a feed that jumped and one that did not are the same picture taken
at different moments. It is gated.

**The loot sentences are built, not typed.** The client hands over the same
localised format strings it used, so `LOOT_ITEM_SELF_MULTIPLE` becomes a pattern
and a German client is read by German rules without the addon knowing a word of
German. Order in that table is its whole correctness: "You receive loot: %s."
matches the counted sentence as well, because the link is followed by "x8" and
`(.+)` will happily swallow it, so every counted form is tried before its
uncounted twin. The harness carries both forms of each for exactly that, and
deliberately leaves two of the twelve out, because a client that carries some
and not others is a real state and `/wk status` has to say so rather than
quietly capturing two thirds of what drops.

The combat feed is about you and nothing else. The log names every creature in
range, including the other party fighting the pack next door, and a feed that
drew all of it would be the client's own combat log tab, which is the thing
nobody reads. It is not the meters either: they total a fight, this is a list of
moments, and the two share no state.

### The addon has its own tooltip now

Every hover in the addon went to `GameTooltip` until this release, which meant a
parchment scroll with a gold border rising out of an interface that has neither
anywhere else. `UI/Tooltip.lua` is the addon's own: the theme's palette, the
shared Arial Narrow, the pixel grid, one frame with a pool of lines refilled on
every open.

**It is the size of the thing it describes.** One frame serves every hover in
the addon, so it has one zoom and forty possible owners, and it took that zoom
from `UI.WindowZoom`, which is the settings window's. With the UI size slider
above 1 that meant hovering a feed row opened a box six hundred screen pixels
across to explain a row thirty pixels tall. It now asks the owner what zoom the
owner is drawn at, through the new `UI.ZoomOf`, and moves itself onto that. The
padding, the line gap, the rule spacing and the wrap width all came in with it:
a tooltip is a label that follows the cursor and is read in the half second
before you move on, and every unit of air in it is a unit of the game it is
covering.

**A caller hands over a table, not a run of calls.** `Tooltip.Show(owner, data)`
takes a title, a colour, an optional item link, and a list of lines: a plain
sentence, a label and its value pushed to opposite edges, a quiet blue hint that
names a switch, a spacer. The five imperative writers it published before are
locals now. Five ways to write a line is five things a caller can do in the
wrong order, and the one that actually mattered, whether a title had been
written yet, was bookkeeping every caller had to get right on its own. What a
hover says is a value the caller returns, which is also what let the feed guard
the reopen: with the cursor resting on a feed, a tooltip was being refilled once
per combat log event, and it is now refilled only when the entry under it moves.

An item's text is the client's and there is no API that hands it over as data,
so the supported way to read it is to point a tooltip of your own at the link
and read back the font strings it filled in. That is what a hovered loot row
does, and it is why the tooltip carries a scanner. Where the client refuses the
frame, or hands over nothing, the row falls back to its name and the facts the
feed knows, and `/wk feed` says which of the three happened rather than leaving
you to guess from a thin box.

`Buffs/Nag.lua` was the file that had invented this shape, three lines of a
title, what is wrong and the name of the switch that silences it, and it is now
the first caller rather than the only implementation. Its `PassCamera` came with
it and is `ns.UI.PassCamera`: a mouse enabled frame swallows every button that
lands on it, including the right drag that turns the camera, and everything in
this addon you can hover sits exactly where that drag starts. Written once for
four nag squares, it is the same trap at forty times the area on a feed, which
is what moved it into the library. Where the client has no
`SetPassThroughButtons` the price is real and both the panel and the feeds' own
setting say so out loud.

The blue instruction colour that was one of two literals in `Buffs/Nag.lua` is
`UI.Color.hint` now. Its detail line takes the theme's reading colour rather
than the near-identical grey it had, which is the point of having a palette.

### The enemy bars say when to Pummel again

`grep UNIT_SPELLCAST` returned nothing across the addon. The bars replace the
nameplate, so replacing it cost the one thing on a plate that says a cast is
running and there are two seconds left to stop it. Every enemy bar carries a
cast row now: the spell's name on the left, the seconds left on the right, a
fill that runs left to right for a cast and drains right to left for a channel.

Violet, and deliberately nothing else on the bar. The gauge above it carries
threat, which is the green through red scale, and the tag beside it carries the
XP scale, which is those same five colours meaning something else. A cast bar in
any of them would read as a third opinion about the mob's health. A cast the
client flags as uninterruptible draws in the idle slate instead: there is
nothing for you to do and the colour says so.

**The row is reserved and it draws nothing.** It is kept clear whether or not
the mob is casting. A row that appeared would shove the health bar upwards at
the exact moment the thing you are watching starts happening, and a bar that
moves when the fight gets interesting is a bar you have to find again. Empty, it
hides its box, so there is no fill, no edge and no backdrop and what is left is
air. The three pixel threat bar that used to sit above the gauge is the version
of this that got deleted for drawing its backdrop while nothing was pulling.

**The fill is drawn on every frame.** One `OnUpdate` now runs two bodies:
`EnemyBars.Sweep` on every frame, which advances the fills and nothing else, and
`EnemyBars.Update` behind the fifth of a second accumulator it always had. This
is the swing timer's argument and it took two repairs to learn there: a readout
a fifth of a second stale is one nobody can fault, and a moving edge drawn at
five hertz is a moving edge that steps. The harness holds the cast fill to the
same three statements the swing bar is held to, at 60 fps and at 144, and none
of them is a tolerance.

The accumulator subtracts the interval now instead of zeroing. Zeroing throws
away however far past the interval the frame landed, which turns a 5 Hz tick
into every fourth frame at 60 and every twelfth at 144, rates of 4.6 and 4.8.
That was the first of the two throttles on the swing bar, and it was the same
line.

**Nothing is kept between frames.** `ns.CastingInfo` is a live question with a
live answer, so the tick asks it once per bar and `UnitFrames/Cast.lua` draws
what came back. A model keyed by unit token would have to survive nameplate
tokens being recycled the moment a mob dies, and that is a class of stale bar
that cannot happen if there is no model.

The `UNIT_SPELLCAST_*` events are registered as well, and they buy exactly one
thing: the fifth of a second between a cast starting and the next tick, which on
a one and a half second window is an eighth of the reason to look. They are not
what the feature rests on. A client that never fires one of them for a nameplate
unit draws the same bar a fifth of a second later, which is the lesson the
debuff row paid for. `/wk status` says how many have ever reached a bar.

**Two calls, one answer, and a flag that is counted rather than assumed.**
`UnitCastingInfo` counts up and `UnitChannelInfo` counts down, and both open the
same six returns and then differ by one slot: a cast carries a castID and a
channel does not, so `notInterruptible` is the eighth return of one and the
seventh of the other. Neither slot is trusted. What comes back is type checked,
and `ns.CastImmuneKnown` reports what has been seen rather than what is assumed:
nil before the first cast is read, false once one has been read without the
flag, true once one has carried it.

That both calls answer for a unit that is not you is the one inference this rests
on, and it is a good one. Vanilla answered only for the player, which is why
every Classic cast bar was built on a combat log estimator. Details ships that
estimator and its framework used to route both calls through it on Era; the
branch is switched off in its own source under the comment "disable this for
now, as it appears to be working now through API changes". An addon deleting its
own workaround is a stronger proof than an addon calling the API.

**Unlocking previews it.** A mob that casts is not something you can arrange, so
"unlock the frames and look", which is how everything else in this addon gets
placed and sized, had nothing to look at: the row could not be judged until a
caster pulled you. Unlocked, every bar draws its own cast instead of asking the
client, five seconds around, a cast filling and then a channel draining, through
the same guarded writes the real thing uses. `Buffs/Nag.lua` had the same
problem with an equally empty row and this is its answer. You still need a bar
to look at, which means a hostile target or a nameplate up.

`replace` style now hides Blizzard's plate cast bar, which it deliberately did
not before. Two cast bars for one cast, in two places on the screen, is worse
than either alone. `bars cast off` takes our row away and gives Blizzard's back
in the same breath, so it is a real off switch rather than a way to stop seeing
casts.

`Swing/Slam.lua` reads the cast it measures through the same shim now. It had
its own positional read of `UnitCastingInfo`, which is exactly the thing Core
exists to do once.

### A region hidden by a setting was not always given back

Found on the way in, because the cast bar would have had the identical bug the
first time anyone typed `bars cast off`.

`PlateRegions` decided which of Blizzard's nameplate regions to hide by reading
the settings, and the restore walk called the same function. Hide the raid icon
with `bars marker` on, switch the setting off, and the walk that was meant to
give it back no longer had it on the list. The icon stayed hidden for the rest
of the session, nothing was written anywhere, and the only symptom was a mob
with no raid marker at all: not ours, because the setting is off, and not
Blizzard's, because we are still standing on it.

The strip list may shrink with a setting. The restore list may not. It is
`PlateRegions(plate, every)` now, restore passes `every`, and `ns.Unstrip` is a
no-op on a region that was never taken, so asking for all of them costs a table
lookup.

### Bar 1 takes a dropped spell, and this time the client said why

Two fixes went in for this and neither worked, because both were written by
reading the code. Bar 1 hovered, named what was on it, highlighted an empty
square and pushed under a click, and a spell dragged onto it would not leave the
cursor. Every other bar took the same spell.

So this release stopped guessing and asked. `/wk actionbars trace` prints what
the client says is under the cursor, whenever that changes, with the frame's
name, its strata, its level and the action slot it presses if it has one. It
answered in one line:

    trace: under the cursor: MainActionBar (TOOLTIP 50), holding spell 21/spell

`MainActionBar` is mouse enabled in **TOOLTIP**, which is the top strata there
is. The previous fix stood the cloned bars at frame level 120 to beat that
frame's level of 50, and a level cannot win an argument with a strata: our bar
sat at MEDIUM 122 and lost every hit test on that corner of the screen anyway.
The same trace never once named a bar 1 square while it named squares on the
other four, which is the same fact from the other side.

That frame cannot be hidden, because the micro menu and the bag bar hang off the
same corner, and it cannot be out-stacked, because nothing stacks above TOOLTIP
except tooltips. So the mouse comes off it. It has no click handler and no drag
handler; it exists to stop a press reaching the world, and the bar of ours
standing over it does that job now. `Buttons/Blizzard.lua` walks up from each
Blizzard button it hides, silences any ancestor that actually takes the mouse,
and hands every one of them back when the clone is turned off, which is the
same shape the button hiding already had. Frames declared with no `enableMouse`,
which is all four multi-bars, are never touched. `EnableMouse` is per frame and
never inherited, so the micro menu and the bag bar keep theirs.

**The trace stays.** It is off unless asked for, read only, and it prints three
things: the frame under the cursor as it changes, every drag gesture a square
gets with the cursor either side of it, and every click, through `PostClick`,
because a spell is dropped by clicking as often as by dragging. Its first live
run printed every gesture and never named a frame, because this client has no
`GetMouseFocus`; both that and the `GetMouseFoci` that replaced it are asked
for now, and the trace says which one answered as it switches on.

The drop path also stops being silent with the trace off. A drop that reaches a
square and moves nothing says which action slot it was aimed at, once per reason
per session, and a square pointing at no slot says that instead. The old latch
fired on the first refusal and swallowed every other reason for the rest of the
session, which was the same silence one layer down; it is keyed by the line now.

`scripts/harness.lua` carries `MainActionBar` in TOOLTIP with bar 1's twelve
buttons parented to it, and fails if the clone leaves it taking the mouse, if it
silences a holder that never took one, or if the off switch leaves anything
deaf. The old fixture said MEDIUM and both failed fixes passed it.

### A nag you cannot silence is a nag you learn to ignore

The report was one sentence: "I do not have a weapon enchant, and I know that's
bad, but I do not need a permanent nag for something I cannot fix." The row had
one master switch and no way to stop watching one thing, so a character with no
sharpening stones got the main hand square every time they left combat, forever.

That is worse than a wasted square. The row is one row. Once you have learned to
look past the stone you have learned to look past Battle Shout, the food and
Blood Fury sitting on your keyboard, and the whole feature is gone. One
unfixable entry costs you the other three.

So every entry has its own switch: `buffs weapon off`, `buffs offhand off`,
`buffs shout off`, `buffs food off`, and a tick box each under a new **What it
watches** heading on the panel. The words name the thing rather than the slot,
with one exception. `offhand` is a hand, because for that entry the hand is the
thing: the only rule on it is that a shield in that hand is never nagged about
and a weapon in it is.

**Off means off the list, not hidden.** A switched-off entry never reaches the
list `Upkeep.Rebuild` builds, so the tick never asks about it, the row never
draws it, and `Describe` never counts it. Drawing it at alpha zero would have
cost the same four calls a tick for a square nobody can use, and testing it on
the tick and dropping the answer is the same work with none of the answer. The
harness asserts the entry is absent from the walked list rather than that the
square is hidden, which is what makes both cheap versions fail rather than pass.

**Per character, and this is the one scope decision in the addon taken on
editorial grounds.** Everything else on the buffs page is a preference about the
row itself, and how big the row is is the same answer on every character you
own. Whether a bare weapon is worth a square is a fact about the character: a
raiding main carries a stack of stones and wants the square, a bank alt has
never bought one and never will. Account wide would have taken the raider's
answer and forced it on the alt, which is the complaint that produced the
setting, repeated one level up. It is `ns.dbc.buffWatch`, and absent means
watched, so a fresh character carries an empty table and an entry added in a
later release arrives switched on.

**What you switched off is visible.** `/wk status` and the panel both name it,
so the status reads `3 tracked, 1 missing; bare weapon switched off`. A nag you
turned off six weeks ago and can find no trace of is the same defect in a new
place: the row is quiet and you no longer know why.

**The captions say what is wrong instead of which hand.** `main hand` became
`bare weapon` and `off hand` became `bare off hand`. The old ones named the slot
and left you to work out what about it, which on a bare icon over your character
is no help at all. The racial half was already speaking correctly with `press
Blood Fury`.

**Hovering a square says the rest.** Two words of caption is the right length
for something you read at a glance mid-raid and it is not enough the first time
you see it. The tooltip carries what the caption could not: that a bare weapon
means no stone, no oil and no imbue on the weapon you swing; that a bare off
hand can only be a real weapon, because a shield is never nagged about; that
Battle Shout has lapsed and any rank counts; and for the racial, which racial it
is and how many seconds it has been sitting off cooldown. That last figure is
the row's own record. A spell that is ready reports a duration of zero and no
end time, so nothing in the client can answer it, and `Nag.Update` stamps the
moment the racial half came up.

The last line of every tooltip names the switch that silences that square.
Turning one off from the square you are tired of, rather than reading a settings
page to find which tick box it is, is most of what the switch is worth.

`Buttons/Square.lua` owns this shape for the action bars and the row follows it
rather than inventing a second way: `OnEnter` and `OnLeave`, anchored to the
square, refused outright when there is nothing to say. It is not shared code,
because every step in that file is about an action slot read off a secure
button's attribute and handed to the client to describe.

**One real cost, and it is worth naming rather than discovering.** A square
takes the mouse only while the row is locked and drawn, and this row sits above
the middle of the screen, which is where a right button drag to turn the camera
starts. A mouse enabled frame swallows every button that lands on it. The right
and middle buttons are handed back through `SetPassThroughButtons`, which
arrived in 1.14.4 and 10.0 and is probed rather than trusted, so on a client
without it a right drag begun exactly on one of these squares does not turn the
camera: at most four squares of 54 pixels, only while something is missing, and
only out of combat. It is in the untested list. Unlocked, the squares release
the mouse entirely, because unlocked the row is a thing you drag and a square on
top would eat the button first.

**The spells you add yourself have no switch, and remove is why.** The four that
ship cannot be taken off the row, so a switch is the only way to stop one. A
spell you added is one press from gone, and gone is the better answer: it hands
the slot back, and a flask you have stopped keeping up is not something you want
listed in a quiet state. A switch there would turn six slots into twelve states
with nothing on screen to tell them apart.

The assertions found one bug while they were being written.
`ns.dbc.buffWatch[key] = on and nil or false` is the short way to write the
setter and it is wrong in Lua: `and nil` is falsy, so the `or` takes over and
every call writes `false`. Switching an entry back on left it off. It is a
branch now, with the reason on the line.

### The swing bar still stepped, because there were two throttles on one edge

The last repair deleted a 20 Hz ticker with a broken accumulator, which was a
real bug and a real fix. The bar still stepped in game. The reason is that the
rounding to whole pixels was a second throttle sitting behind the first, and
finding the first is what hid it.

A fill snapped to a whole pixel can only change value as many times as the bar
has pixels. At the shipped 180 pixels across a 3.4 second swing that is 53 times
a second and no oftener, whatever rate the tick runs at. So the bar stood still
on 7 of the 60 frames a 60 Hz screen draws and on 91 of the 144 a fast one
draws, and every move it did make was a whole design unit, which is three screen
pixels at `swing zoom 3`. Deleting the ticker raised the drawn rate from 20 to
53 and changed nothing else.

`DrawHand` now writes the fill as a fraction of a pixel, on every frame, with no
comparison in front of it. The quantisation is gone and so is the guard it
doubled as. That is one line of arithmetic and five fewer lines of code.

**This is a second pixel rule, not an exception to the first.** The addon has a
hard rule that every edge lands on a whole pixel, enforced across 6,836 offsets,
and it exists so borders and art are sharp. It was written when every edge in
this addon was static and for that codebase it was the whole truth. A moving
fill wants the opposite thing: what the eye reads on a moving edge is velocity,
and velocity lives in where the edge sits between two pixels as much as in which
pixel it is on. Round it and you have destroyed the only thing being looked at
to buy a sharpness that cannot be seen on something in motion.

So there are two named rules now rather than one rule and a hole beside it. A
static edge lands on a whole pixel. A moving fill is not quantised. Both are
written out under the pixel grid in the README, both cover a category rather
than a file, and both are gated: the anchor sweep keeps walking every static
offset, and the swing section now asserts the positive form of the second rule,
that the fill really does land off a whole pixel on nearly every frame. Put a
round back around the fill and that fails. The Slam band and its mark move only
when your weapon speed does, a few times a fight, so they are static edges and
they stay on whole pixels.

**The old smoothness assertions were the wrong statements.** They said the fill
never jumps more than one pixel between two frames and that it visits all 180
positions, and both passed against a bar that visibly stepped, because a
quantised fill satisfies them exactly. No assertion in this repo can prove that
a bar looks smooth: smooth is a property of a screen and an eye and the harness
has neither. What it can prove is the property that leaves the client nothing to
be blamed for, so the fill is driven across a whole swing at 60 fps and again at
144, and three things have to hold on every frame with no tolerance allowed. The
drawn position equals elapsed over duration times the width, exactly. The value
changes on every frame, with no frame repeating the one before it. And every
step is the same size as every other, which is what constant velocity means.
Against the rounded code those read `the fill drew the same position twice on
309 of 489 frames` and `the widest step was 1.000000 px more than the narrowest`.

**What the unguarded write costs was measured, not assumed.** The swing tick
allocated 0.03 KB per fifty ticks rounded and guarded, and allocates 0.03 KB per
fifty ticks written every frame. The gate stays at 0.05. It is the addon's only
`-- unguarded:` exemption and the reason is on the line.

### The addon reads your own auras now, and says what you forgot

`grep UnitBuff` across `src/` used to find nothing. A sharpening stone that wore
off forty minutes ago costs more damage over a raid than any single rotational
mistake, and Battle Shout falling off says nothing at all.

`Buffs/` is a row of squares over your character, and it is not there when
nothing is wrong. That is the design decision. A row that is always up with the
missing ones lit is furniture, and you stop seeing furniture in about a week,
which is exactly long enough to convince yourself the addon is watching for you.
A row that exists only when something is wrong carries its whole message in
existing. The cost is a frame you cannot find to drag, so unlocking shows every
square it watches at three quarters alpha, which is the trade the meters already
make when they draw an outline round an empty pane.

**Two halves, taking turns rather than sharing one row.** Out of combat it is
what is missing: no stone on either hand, no Battle Shout, no food. In combat it
is the racial you own and have not pressed. They can never both be on screen,
which is why one row answers two questions.

That split is not a layout convenience. You fix a missing buff out of combat
because out of combat is when you can fix it, and shouting about a lapsed stone
mid pull is telling you about a thing you cannot do. Blood Fury is the opposite.
It is not a buff you keep up; it is two minutes of attack power sitting on a key,
and the only moment worth saying anything is the moment you are swinging at
something with it off cooldown.

**The weapon enchants are the reason the feature exists and are the only entry
that is not an aura.** A temporary enchant does not appear in an aura scan at any
index. `GetWeaponEnchantInfo` is the only thing in the client that knows, and
that call has had three shapes: six values at three per hand, eight once 6.0 put
the enchant's own id in after the charges, and twelve once Cataclysm added a
ranged hand. Nothing installed here settles which one 2.5.6 and 1.15.9 answer
with. So the stride is counted with `select("#", ...)` rather than read
positionally on a guess: at a guessed three against a client that answers eight,
the main hand's enchant id lands where the off hand's "has an enchant" belongs,
and a number is truthy, so the off hand would read as enchanted forever and never
say why. The harness drives both shapes and reads the off hand in both.

**A shield is never nagged about**, and that is the client's own
`OffhandHasWeapon` rather than a reading of the slot. A shield, a
held-in-off-hand item and an empty hand all answer no to it, and every one of the
three is a state a warrior is in on purpose.

**Auras are matched by name and scanned on an event, never on the tick.** Battle
Shout has eight ranks and the aura carries whichever one was shouted, so the ids
in the source exist only to ask this client what it calls the spell in the
language it is running in. `UNIT_AURA` fires for every buff you gain and every one
you lose, so the walk runs from the event and the tick reads a field. On a client
carrying `C_UnitAuras` that walk would also build a table per aura, which is
allocation on a ticker.

**Flasks and elixirs are a setting rather than a table.** These clients will not
say that an aura came from an elixir. There is no category on an aura and no call
that maps one back to the item, so the built-in version is about forty hand
written spell ids that cannot be checked from outside the game, go stale on the
next patch, and are wrong in a way nothing reports. `/wk buffs add <id>` takes six
of your own, the same shape the debuff row on the enemy bars already has.

**Only the racials that are damage are nagged about.** Blood Fury on an orc and
Berserking on a troll: both are throughput, both come back inside three minutes,
and forgetting one across a boss fight is free damage thrown away. Every other
racial a warrior can have is listed with the nag off so the status line and the
panel can name yours and say why it is quiet. Stoneform is spent when something
bleeds you and War Stomp when something needs stunning, and a row that shouted
about either every fight would teach you to ignore the row, which would cost you
Blood Fury as well.

The ids come from Wowhead's TBC Classic database and each was checked against the
cooldown its page states. Blood Fury has a second proof and it is the one that
matters: 20572 sits in this install's own Details saved variables as a buff with
uptime, recorded off a live 2.5.6 session. The race is `UnitRace`'s second
return, which is the token and is the same string in every locale, and it is read
every time rather than cached for the reason `ns.IsWarrior` reads the class every
time.

**The racial square breathes, and there is no sound.** Its alpha runs between a
floor and full over 1.6 seconds, which at the row's ten hertz is sixteen steps
and reads as a pulse rather than a strobe. It is on by default, because a nag you
can ignore is not what was asked for, and `/wk buffs pulse off` makes it a still
square. A sound would be a new kind of thing in this addon and is not worth it: a
chime in a raid competes with the sounds you are already listening for, it fires
whether or not you are looking at the screen, and a racial coming off cooldown is
worth noticing within a few seconds rather than immediately. The alpha is
quantised to twentieths so a tick that would draw the same value writes nothing.

Two states silence the missing-buff half and neither touches the racial half.
Dead, because nagging a corpse about its sharpening stone is noise, and that one
is not a setting. Resting, because an inn is where you have not put a stone on
yet on purpose and the row would be up through an hour at the auction house; that
one is `/wk buffs resting` for anyone who buffs in the bank.

**Not gated on warrior.** A lapsed stone costs a hunter's melee weapon exactly
what it costs a warrior's, and a troll rogue forgets Berserking the same way.
Battle Shout is the one entry that asks `ns.IsWarrior`, inside `Upkeep.Rebuild`,
and the hunter harness run asserts it is not on the list.

The long personal cooldowns are deliberately absent. Death Wish and Recklessness
are timed by hand on purpose and are their own piece of work.

### Overpower is a reaction, and the bars say so now

Overpower was drawn ready from the first pull to the last. It is pressable for
about five seconds after your target dodges you and not one moment else, which
makes it the one square on a warrior's bar whose whole point is that it is
usually dark. It was the brightest thing on the row.

The client is the reason and it is worth stating exactly, because nothing in the
code read wrong. `IsUsableAction` answers yes for Overpower in Battle Stance
whether or not anything has dodged you. It is not confused and it is not
answering about rage: the window lives on the server and the client is never
told, so there is no aura to scan, no cooldown to read, no event when it opens
and none when it shuts. Every rung of the ladder above that call was correct and
the square was still a lie.

The combat log is the only place the fact appears, so `Buttons/Reaction.lua`
reads it, the same event `Meter/Meter.lua` and `Swing/Swing.lua` already read and
the same way. A dodge of yours opens Overpower. A block, dodge or parry of yours
opens Revenge, which is the identical mechanism seen from the other end and is
in the same file for that reason: two copies of one five second clock is how the
two drift, and the drift would be silent because each would be right most of the
time. Pressing the ability shuts its own window, and leaving combat shuts both.

A block is read in two shapes, not one. A block that stops the whole hit arrives
as a miss; a block that stops part of it arrives as a landed hit carrying a
blocked amount, and on a tank that is the common one. A parser that took only
the tidy shape would leave Revenge dark through most of the fight it was open
in.

**The window is five seconds and that number is a decision.** Every
player-facing source says five, and both abilities carry a five second cooldown,
so a warrior pressing on every window presses on the cooldown. The MaNGOS and
TrinityCore server cores both hold `REACTIVE_TIMER_START` at four. Five wins
because the two errors do not cost the same: a second long says pressable when
it is not and costs a glance, a second short greys a free five rage attack that
is still sitting there and costs the attack. `/wk status` prints the seconds left
on each window so the figure can be checked against the live client, and the
README lists it under what has never been measured.

**A new reason, and no new colour.** `reaction` joins the vocabulary in
`UI/Ability.lua` and takes the look every unpressable square takes. A shut
window is not a state you can act on: you cannot walk out of it and you cannot
wait it out on purpose, so there is nothing for a colour to tell you to do. What
says the window opened is the square leaving that look, which on a bar is a jump
from drained grey to full colour and is the biggest change any square in the row
can make.

**The rung sits above the usable split**, which is the ladder's own rule that
what cannot be fixed at all comes first. That ordering also quiets the square
that used to shout for nothing: Overpower on a bar in Defensive Stance drew
orange "swap" all fight, telling you to swap into a stance where the press still
would not land. Now the orange turns up only while the window is open, where
swapping really does let you press it.

Stances needed no new code. Overpower is Battle Stance only and Revenge is
Defensive Stance only, and the client already refuses both in the wrong stance
in exactly the shape the ladder splits `cost` from `stance` on.

Warrior only, decided once at login, so on another class nothing is registered
and no combat log line is read. Only a plain spell is recognised, matched by
asking the client its own name for the two abilities and comparing that against
its name for whatever is in the slot: locale-proof, rank-proof, and two spell IDs
in the source rather than a rank list that goes stale at the next trainer visit.
An Overpower wrapped in a macro keeps the old behaviour, because the client will
not say what a `/cast` line resolves to.

### The swing bar jumped, and the Slam mark wandered

Both halves of the report were true and neither was arithmetic. Every assertion
the feature shipped with passed the whole time.

**The bar jumped because 20 Hz is an animation rate, not a refresh rate.** Every
other ticker in the addon updates a readout, where fifty milliseconds of staleness
is invisible. The swing bar is a moving edge. At the shipped width the fill
crosses 53 pixels a second, so a draw every fifty milliseconds moved it about
three pixels at a time, and three pixels is a step you can see. The accumulator
made it worse by resetting to zero instead of subtracting the interval, so on a
60 fps client it fired every fourth frame rather than every third and the real
rate was 15 Hz.

So the bar draws on every frame and there is no accumulator left to be wrong.
That costs nothing, because the pixel quantisation is the guard: the fill is a
whole number compared against the whole number already on the bar, so a frame
that would draw the same pixel writes nothing. Inside a swing that is 53 writes a
second, outside one it is none, and the churn measurement did not move.

The harness now drives a whole swing one 60 fps frame at a time and asserts that
the fill never jumps more than a pixel between two frames and that it visits all
180 positions. Against the shipped code those read `the fill jumped 3 pixels in
one frame` and `the fill took 69 positions across a 180 pixel swing`.

**The mark wandered because the cast time under it was re-measured on every
cast.** `UNIT_SPELLCAST_START` was read every time and the number it gave was
drawn straight away, so the mark moved a pixel or twenty depending on what the
server declared and on which cast the client happened to be describing. That is
the player's own words: it moved depending on when they clicked the spell.

Haste does not touch Slam's cast time on either of these clients. Warcraft
wiki's patch history dates that to Cataclysm 4.0.1, "Slam can now be cast while
moving, and haste now reduces the cast time". Before that patch the cast is 1.5
seconds less the talent and nothing else moves it, which makes it a constant per
character and makes a second reading of it worthless. So the first Slam of a
session is measured and every one after it is ignored, and a talent point is
what drops the held number. The reading is snapped to a twentieth of a second,
because every value the real cast can take is a multiple of a tenth and the
milliseconds under that are the server's rounding. A reading that snaps to zero
is refused, since zero is truthy in Lua and would have won over the estimate for
the session and then reported the character has no Slam. A reading longer than
the spell's own cast time is refused as some other cast.

What is still allowed to move the mark is your weapon speed, and it has to be:
the press is the moment with a cast time left to run, and a shorter swing spends
a bigger share of itself on the same cast, so Flurry walks the band back down
the bar rather than up it. That is asserted as the invariant rather than as a
percentage, at three weapon speeds and across a proc that lands mid swing.

`ns.Swing.Duration(hand)` is new and is what the band divides by now. It is the
swing being drawn rather than what `UnitAttackSpeed` says this instant. The two
are the same number today, and asking for the first is what stops the mark and
the fill from being two answers that agree by luck.

Three smaller repairs in the same files. `unit` was read once at login and used
by every layout pass after it, so on a client with no `SetIgnoreParentScale` a
monitor swap sized the bars off the old screen height. The band's guard compared
its two edges and not the line down the middle, so two windows a hair apart drew
the right band with a stale line in it. And a bar built before its layout ran
seeded its scale at one pixel, which draws a whole swing in two positions; it
now seeds at nothing and draws an empty bar until the layout gives it a width.

The performance tab's swing row said 20 Hz. It says "every frame" and costs the
row against 60 of them, which is the budget the rest of that tab already
measures against.

### A chat window, and a tab for the people you play with

The complaint was that the chat interface is fiddly and not worth reading, and
both halves of that are true for the same reason. Blizzard's window is one
column carrying two different things: people talking, and the game reporting
loot, experience, faction, reputation, skill-ups, errors and every addon's
output. The conversation is a few lines an hour and the reporting is a few lines
a second, so the half you would answer is the half that scrolls away.

So the addon draws the conversation and leaves the reporting where it is.

`Chat/Window.lua` is three tabs. People is anyone on your list, in any channel,
plus the whispers you send them. Chat is every person talking. Whispers is
whispers. That is the whole design, and the people tab is the reason the part
exists: a wife in party chat and a son whispering from two zones away land in
the same place, and neither of them goes past behind an argument about loot.

One tab for all of them, not a tab per person. A tab per person is a row of
stubs you have to read the labels of, and it splits one conversation between
three people into three windows. The question you actually have is whether
anybody you care about has said anything, and that is one question with one
answer. The tab is not drawn at all until there is a name on the list, which is
what makes it turn up on its own when you add the first one.

A name is what the list holds, matched with the realm suffix off and the case
flattened, so `Aria`, `aria` and `Aria-Firemaw` are one person. A GUID would be
exact and there is nothing to type into a settings panel to get one, and it is
per character, so a son who rerolls would be a stranger again. `/wk people
group` puts everyone you are grouped with on the list in one press, which is the
only reason filling it in is bearable: three names typed by hand, spelled right,
is the chore this addon exists to remove.

**Blizzard's window is not hidden and nothing of it is unregistered.** That is
the decision with the longest argument behind it. Hiding it and mirroring
`AddMessage` into a fourth tab is what a chat replacement usually does, and it
cannot be made correct here: the lines arriving at `AddMessage` include the ones
Blizzard's own handler just built from the events this addon already drew, and
there is no supported way to tell those from an addon's `print`. Every way of
guessing is a heuristic on formatted text. So the conversation is claimed and
nothing else is touched, Blizzard's window keeps everything this one does not
draw, and you shrink it into a corner yourself.

The claim is `ChatFrame_AddMessageEventFilter`, which is FrameXML's own
extension point for exactly this. One tick box puts the conversation back in
Blizzard's window on the next line, with no reload and no frame handed back,
which is the same contract the artwork strip and the minimap corral hold.

The capture is a registration of our own rather than a hook on Blizzard's
frames, and those are two mechanisms doing two jobs rather than one job twice.
Which messages a Blizzard chat frame receives is a per character setting the
player owns, so a guild tab switched off in the client's own chat settings is a
guild message this window would never see if it listened through that frame.

The numbered channels are a setting and it ships off. General and Trade are most
of the volume in a city and none of the conversation.

### A log widget, and why it is not built out of the stack

`UI/Log.lua` is the new piece of the widget library: a column of lines that
grows from the bottom, wraps, caps itself at five hundred and scrolls. Each tab
holds one.

It is not built out of `UI/Stack.lua` and `UI/Scroll.lua`, which is worth
writing down because everything else in the interface is. The stack asks every
row how tall it is and lays the column out again from the top, which is right
for a settings page and wrong here: a line arrives, the whole column reflows,
and in a raid that is several hundred measured font strings a second. Worse, a
font string on a hidden frame does not report its wrapped height on this client,
which is why the panel reflows a section only after showing it, and a chat tab
you are not looking at is hidden all evening.

So the log is the client's own `ScrollingMessageFrame`, which is a frame type
rather than a template, probed with `pcall` exactly as `UI/Scroll.lua` probes
the Slider and the ScrollFrame. What the client contributes is the buffer and
the wrap. The font is the addon's shared Arial Narrow, the bar beside it is
`UI.ScrollBar`, lifted out of the scroll view so both draw the same bar, and the
colours are the theme's.

Two things it does that Blizzard's does not. Nothing fades: a line stays until
it falls off the end of the buffer, because a window you are meant to read is
not a river you glance at. And the insert mode is written and read back, because
the two clients disagree about which spelling of that token they accept and a
refused write is silent, which would put the newest line at the top and say
nothing about it.

### A voice channel, joined when you log in

Pick your party or raid channel in `/wk`, or a community's where this client has
communities, and the addon activates it at login and again the moment the
channel appears, which for a party channel is when you group up.

The picker offers what the client's own Chat Channels window draws a voice
button on: your party or raid, and every stream of every community and guild you
are in. There is nothing else to offer. Blizzard's voice chat is not the one
from patch 2.2 with channels you could name; since it was rebuilt on the
Battle.net service it is attached to the groups you are already in, and the
panel says so rather than leaving you looking for the button that makes one.

The first version of this listed only the community streams the client already
had a voice channel for, on the argument that a text stream is not a voice
channel and offering one that is not there would be a lie. That emptied the
picker at exactly the moment it is used. A community voice channel does not
exist until somebody joins it, so at login, which is when you are choosing what
to join, there is nothing to list. It offers every stream now and asks for the
one you picked, which is what pressing the voice button in the client's own
window does.

The pick is saved as the club and the stream behind it, and the name it was
picked under is saved beside them. Communities load a few seconds after you
enter the world, and without the name the picker and the status line spell your
voice channel as a pair of numbers until they do.

**It only ever joins.** Nothing in it leaves a channel, mutes anyone, picks a
device or moves a volume. Those are the client's own settings, somebody pressed
something to get them where they are, and an addon undoing one while your hands
are full is not a feature.

A channelID is deliberately not what is saved: it is handed out per session, so
saving one would mean joining whatever happens to take that number tomorrow.

The request is rate limited and gives up after five tries. Everything that makes
this look again is an event, and those arrive in bursts: a roster change, a
channel appearing, the service signing in. A join request per event is an addon
hammering a Battle.net service, and a channel that never turns up is a channel
the player has to sort out in the client's own settings rather than one worth
asking for forever.

### The harness was skipping an event handler

Found while testing the above, and it had been true for every part that ever
registered `ADDON_LOADED`.

Several parts unregister that event from inside their own handler for it, which
is what the client asks you to do and what Core does first of all. The stub's
`fire` walked the list of registered frames with `ipairs` while
`UnregisterEvent` removed entries from that same list, so every unregister
shifted the frames after it down by one and the next one in line never got the
event. Which part got skipped depended on the order the TOC happened to load
them in.

The chat part is what caught it: it registers its events in that handler,
therefore registered none of them, and every line fired at it in the test landed
nowhere. In the game it would have worked, which is the worst shape a harness
bug can have. `fire` walks a copy now.

The same section is why `scripts/harness.lua` has one table where it had four
locals. That file is a single chunk sitting on Lua 5.1's two hundred local
limit, which turns out to be a real ceiling: the allocation gates are one
concept and are one table now, and the chat stubs bring one name between them.

### A swing timer, with the Slam press drawn on it

The addon talked about the swing everywhere and never drew it. `UI/Ability.lua`
brightens a square's border to say Heroic Strike is armed and goes off on the
next swing, and nothing on screen said when that swing was coming.

`Swing/` is two gauges under the character, one per hand, on the pixel grid.
The clock is the combat log: `SWING_DAMAGE` and `SWING_MISSED` with you as the
source, because a swing landing is the same instant the next one starts, and
`UnitAttackSpeed` is how long that instant lasts. A miss counts, since
`SWING_MISSED` is the server saying the swing happened and did nothing, and a
timer that only heard damage would stop dead against a mob you cannot hit.

Which hand swung is a flag in two different slots, twenty-one on a landed swing
and thirteen on a missed one. Reading one index for both gives an off hand bar
that never runs and a main hand bar that runs twice as fast, which reads as a
haste bug and is a parser bug, so the harness feeds both subevents.

Haste scales what is left of a swing rather than restarting it. Flurry landing
halfway through a 3.4 second swing leaves you halfway through a 2.4 second one.
That is one line of arithmetic and it is the single thing a warrior's swing
timer has to get right, so it is asserted rather than described.
`UNIT_ATTACK_SPEED` is not enough on its own, because it does not reliably
follow an aura on these clients, so the player's own `UNIT_AURA` is registered
too and every one of them ends in a comparison against the speed already held.
`UNIT_INVENTORY_CHANGED` is the third door into the same arithmetic and this
addon opens it itself, off a loadout key.

The band is the point of the whole thing. Slam has a cast time, it does not
interrupt the swing while it casts, and finishing it restarts the swing. Press
early and the restart throws away the charge you had; press late and the swing
is pushed out to the end of the cast. The one right press is where the cast ends
as the swing ends, at `(D - C) / D` of the bar, and that is drawn as a green
band two tenths of a second wide with a line down the middle of it. The whole
gauge flips green while the fill is inside, because four percent of a bar is not
enough to catch out of the corner of an eye and all of it is.

The cast time is the client's own. `UNIT_SPELLCAST_START` carries what the
server actually started, talents and haste folded in, so from the first Slam of
a session the band is drawn off a measurement. Until then it is the spell's cast
time out of the new `ns.SpellCastTime` less a tenth of a second per point of
Improved Slam, and the talent is found by name rather than by position, because
every "Improved X" talent carries the ability's own localised name inside it.
Whether this client already folds that talent into `GetSpellInfo` could not be
settled without logging in, and the measurement means it does not have to be.

A completed Slam restarts the main hand timer off `UNIT_SPELLCAST_SUCCEEDED`.
Nothing in the log says so: the next event you would see is the swing that lands
a full weapon speed later, and a timer built on the log alone draws the whole of
that swing wrong.

The bars are gated on holding a weapon and not on being a warrior, because a
swing timer is worth the same to anybody standing in melee. The band is Slam's
and is warrior only, and the hunter run of the harness asserts both halves.

The tick counts in whole pixels: the bar's scale is its own width, so the fill
is an integer compared against the integer already on it and between swings the
tick writes nothing at all. It measures 0.03 KB per fifty ticks against a gate
of 0.05. It shipped at 20 Hz and does not run at a rate any more; the section at
the top of this file says why.

`scripts/harness.lua` grew an attack speed, a talent tree, a cast in flight and
a weapon in each hand, and its combat log stub went from sixteen values to
twenty-one so the off hand flag exists to be read. The swing gate went into the
`CHURN` table with the others rather than taking a local of its own, for the
reason the chat work gives above: that chunk is at Lua 5.1's ceiling of two
hundred locals, and the swing gate is what it ran out on.

### Deep Wounds never lit up, because the talent is not the bleed

The debuff row above an enemy bar matches auras by name, and the picker offered
12162 for Deep Wounds. 12162 is the talent. It is a hidden passive on the
warrior, the client names it "Deep Wounds", and no mob has ever carried an aura
by that name. What lands is 12721, and the client spells that one "Deep Wound",
singular. One letter, no error in the log, and an arms warrior watching a square
that could not come on.

The shortlist now carries 12721. Anyone who already picked Deep Wounds keeps the
dead ID, because the default list is read once on a fresh account and never
again, so `EnemyBars.Repair` swaps it at login and `AddSpell` swaps it on the way
in. Type 12162 into the panel's id field and the addon tells you Deep Wound is on
the bar, which is the truth and is visibly not what you typed.

Charge and Intercept have the same shape and were already right: 7922 and 20253
are the applied stuns, not the abilities. The comments beside them say so now, so
the next person to tidy the list does not "fix" them into the ability IDs.

The panel note used to say to use rank 1's id since the match is by name. That is
true for a ranked spell and false for a proc, and it is the sentence that made
12162 look correct. It now says to use the ID of the aura that lands, and names
both halves of the Deep Wounds pair.

The harness stubs auras now instead of answering nil forever, which left the
half of `ScanDebuffs` that lights a square up unreachable. It puts a "Deep Wound"
bleed on a mob and asserts the slot goes to mine with the timer and the stack the
client reported, dims for another warrior's, and goes out when it falls off. Put
12162 back and it says the mob is bleeding and the slot reads "none".

### The addon has a face

`Media/Icon.tga` is the first art the addon ships: the sword emblem, 64 by 64,
cut round with an alpha edge. Both TOCs name it as `## IconTexture:`, which is
what the client draws beside WarriorKit in the addon list. It is the only place
this art goes. The panel is flat, pixel-exact and deliberately plain, and a
gold plaque inside it would be a sticker on a schematic.

Three rules in `check.sh` came with it, because a texture fails silently in
every direction. A path a TOC names has to resolve to a file in the addon; a
file in `Media/` has to be a `.tga` or a `.blp` and has to be named by
something; and both its sides have to be powers of two. A path that does not
resolve draws a green question mark and writes nothing to the log, and a
texture 60 pixels wide is simply not drawn. `IconTexture` also joined the list
of fields the two TOCs must agree on, and `release.sh` now fails if the icon is
missing from the zip.

### The bars say what you can afford, and what is already armed

Two things a square was not saying.

A spell you have no rage for was drawn in full colour with a blue hairline
round it. The hairline is correct and it is not enough on its own: it is one
pixel on a 27 pixel square, and "what can I press" is a question asked with the
eye moving rather than stopping. The bars carry no rage bar and no mana bar of
their own, so what you can afford is readable off the squares or it is not
readable anywhere. The `cost` look now drains the art the way the `no` look
does, in both palettes. The blue edge stays and says which of the two kinds of
no it is once the eye has landed.

Range deliberately does not get the same drain. Out of range is a fact about
one mob and it goes away when you take a step; out of rage is a fact about you
and it is the one that decides what to press. Two states that both grey out are
two states you have to read the border to tell apart, which is the border doing
the work the art should have done.

The other was a queued Heroic Strike, which is the one press in a warrior's
rotation whose entire answer is "it is armed and it goes off on the next
swing". `Slot.Active` had it right the whole time and `Ability.Draw` drew it as
22% additive gold over the icon, which is invisible on art that is already
bright. It now draws a gold ring on the edge of the art as well, which is the
half you can see across a screen, and keeps the tint underneath so the square
reads as lit rather than merely outlined. Blizzard draws a checked border for
the same fact.

The ring lands exactly where the green equipped ring lands and is built after
it, so on the one square that is both, armed wins. Two rings a pixel apart on a
27 pixel square is mush, so there is only room for one and it has to be picked:
being worn is still true a second from now and the green comes back the moment
the swing lands, where an armed press you did not see is a press you make
again.

`scripts/harness.lua` holds both. The drain on `cost` and its absence on
`range` are asserted against both palettes, and the ring is driven on and off
against a status that is not `ready`, so it cannot quietly become a tenth rung
of the ladder or take the border the status owns.

### A black edge round the map, and a clock on the end of it

The ring was doing one job worth keeping. It ended the picture. Take it off and
the world runs out to a rectangle with nothing round it, which reads as a hole
cut in the screen rather than as a map.

So the square gets the box the action bars are already built on: three pixels
of near black with a hairline on the outside of it, in the same two colours, so
the two read as pieces of one interface. It is drawn as four bands round the
map rather than as one rectangle behind it. A rectangle would have to sit under
the map to avoid covering the world, and where a child frame lands against its
parent's own drawing is the client's business rather than something an addon
gets to state. Four bands are outside the map's bounds and cover nothing
whatever the client decides.

Two more pieces of Blizzard's furniture come off with the ring. The sun and
moon said whether it was day in a game whose sky says the same thing. The
digital clock draws its numbers on a strip of the old stone minimap tile, so on
a stripped square it was the last of the round map anywhere on the screen,
hanging under the bottom edge looking like the one bit that survived. That
strip is what this change started as.

`Minimap/Clock.lua` puts the reading back as a tab off the middle of the bottom
of the black. It overlaps the bezel by exactly one pixel, so the tab's top edge
and the bezel's bottom edge land in the same row, and the seam between them is
painted out with one band of the fill colour inset a pixel at each end. The
outline then turns both corners and runs round the map and the clock as one
silhouette rather than as a box with a box stuck to it. That join is the whole
reason it is a file and not four lines in `Shape.lua`.

It says local time, where Blizzard's shipped saying the realm's. The realm's is
the time an addon needs and not the time a person does, and it is one hover
away with the date. The twelve hour toggle is read off the client's own CVar,
because a player who set it set it for a clock and this is the clock now; a
client with no such CVar reads as twenty four hours, which everybody can parse,
where the wrong guess in the other direction puts a pm on the wrong half of the
day. The tick looks once a second and writes twice an hour.

Blizzard's clock belongs to an addon loaded on demand, so at login there is
nothing for the strip to take. `Shape.lua` runs another apply on `ADDON_LOADED`
and that is the one that catches it. Login is still the first apply and nothing
before it counts, because an apply taken earlier would read the width off a
frame the client has not sized yet and remember that number as the one to hand
back when the square goes off.

### The auto repair never repaired

It gated on `MerchantFrame:IsShown()`, and `MERCHANT_SHOW` is the server
opening a merchant session rather than the client finishing the window.
`ShowUIPanel` defers when another panel holds the slot, and a client that loads
`MerchantFrame` on demand has no frame to ask at all. So the repair asked a
frame that was not up yet, `Repair.Run` answered "no merchant window is open",
and `OnEvent` swallows every refusal on purpose, because a refusal at a
merchant is nearly always "nothing is damaged". It failed at every vendor, in
silence, for four releases.

The sale next door never saw it, and that is the part worth writing down. The
sweep is a ticker: it asks the same question again a fifth of a second later,
by which time the window is up. Two parts on one event, one of them working,
and the difference was that the broken one asked once.

The gate is the session now. `MERCHANT_SHOW` sets a flag and `MERCHANT_CLOSED`
clears it, both stay registered whatever the setting says, and `autoRepair`
decides whether the handler repairs rather than whether the handler runs. That
second half fixes a smaller bug in the same line: with the setting off the
frame used to unregister, so `/wk repair` at a merchant told you there was no
merchant.

The harness grew a merchant that can be open with its window shut, which is the
only shape that catches this. It also had to stop telling the sweep's frame
from the repair's by which events they hold, because they hold the same two
now; it flicks `sellTrash` once instead and takes whichever frame leaves
`MERCHANT_SHOW`.

### A filter for the red text in the middle of the screen

A warrior generates more of it than anyone. Charge, Intercept and Intervene are
all positional, the charge button in this addon aims by camera and so misses on
purpose, and every miss costs a line of red text across the middle of the
screen. While it is up it hides the one message that would have been worth
reading.

`Comfort/Errors.lua` replaces `UIErrorsFrame.AddMessage` and drops what is on
your list. Two decisions shape it.

Nothing is muted that you did not tick. The list ships empty, and the panel
offers what has actually come past this session rather than a guess at what you
can live without. There is one preset, `/wk errors charge`, and it is a press
rather than a default.

The list is account-wide, and it is keyed by the name of the global holding the
message rather than by the message. `ERR_BADATTACKPOS`, not "You are too far
away!". A name survives a locale, survives a client rewording the string, and
means the same thing on the character you log into next, which is the whole
point of it being in `ns.db` rather than `ns.dbc`. Messages built from a format
string cannot key that way and fall back to their own text; none of them is the
spam this exists for.

The hook is installed once and never taken off. Turning the setting off makes
the wrapper pass everything through. Putting the old method back would write
over whatever addon hooked after this one, and a filter is not worth breaking
somebody else's.

### The minimap is square, and one button holds the rest

Two files, one part, and they are one decision. The round mask throws away the
corners of a map the client has already drawn and the ring spends about twenty
pixels of every edge on rivets, so `Minimap/Shape.lua` takes both off and sizes
the frame to `minimapSize`, 180 by default against the client's 140. The north
tag and the two zoom buttons go with the ring and the mousewheel takes over the
zoom, clamped at both ends because a client asked for a level it does not have
raises.

Blizzard's own icons were anchored to points on the arc and a square has no
arc, so the mail, the tracking, the battleground and the calendar are pulled to
the four corners. Each one's original anchor is recorded the first time it is
moved and handed back when the square goes off, which is the same contract
`Artwork.lua` has: off is a state, not a reload.

`Minimap/Corral.lua` is the other half. Every addon that wants to be reachable
puts a round icon on the edge of the map, and with eight installed the map is a
ring of icons with a map in the middle. The corral takes every named child of
the minimap that is not Blizzard's and not ours, parents it to a tray behind
one square, and replaces the button's own `SetPoint` with a no-op, because a
minimap button drags itself back to the arc whenever it feels like it. That is
`ns.Strip` replacing `Show` with `Hide`, on a different method and for the same
reason. Parent, anchor and the real `SetPoint` all come back on release, and
nothing else about the button is touched, so a press in the tray is the press
it always was.

No ticker. Addons load late, so the scan runs at login, on `ADDON_LOADED`
after login, and whenever you open the tray, and never on a clock.

The first test on a real client collected 555 buttons, and the shape of that
mistake is worth keeping. The minimap is not only where addons hang their
button; it is also where every addon that draws a pin on the map hangs the pin,
and Questie parents several hundred quest icons to it. The corral took the lot
and, because a taken button has its `SetPoint` replaced, left Questie unable to
move its own map.

Four tests now, and the last is the one that would have caught it alone. A
candidate has to be a Button, because a pin is often a Frame and a button
almost never is. It has to measure between 18 and 48, because LibDBIcon draws
at 31 and a pin is drawn at 12 to 16. It has to not be one of a family:
candidates are grouped by their name with the trailing digits taken off, and a
group of more than two is a pool rather than a button, because pins are pooled
and named by counter and a button has one name and no siblings. And there is a
ceiling of 24, which is not a filter but a refusal, reported in `/wk status`
and in the panel rather than swallowed.

`/wk minimap list` names what is held and how much was left as pins, because
the way this was found was a square on the minimap reading 555 with no way to
ask what it meant.

The harness grew a minimap: a cluster, a ring of art, four of Blizzard's
buttons anchored the way the client anchors them, three addon buttons of the
two shapes that actually turn up, and one unnamed child that must never be
collected because a nameless button could not be released. Most of what it
asserts is the reverse direction, because the forward one is the easy half of
both files.

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

### The harness was one file, and it had nearly stopped loading

Eleven thousand lines: a stub of the client, then thirty six sections of
assertions, in one chunk. Lua 5.1 gives one function two hundred locals, a chunk
is a function, and the count had reached a hundred and seventy one. What that
number buys at two hundred is not a failing test. It is `main function has more
than 200 local variables`, and the harness does not start.

Nothing measured it. The file carried a header asking whoever came next to scope
their section in a `do ... end`, which is a request rather than a gate, and
eleven of the thirty six sections had not. Ten of those eleven had left a name
behind that a later section was reading.

**It is a directory now.** `scripts/harness.lua` is still the command and still
runs the same assertions in the same order, against the same client, to the same
output. Under it, `harness/client/` is the stub, one file per part, loaded in the
order `client/init.lua` lists. `harness/sections/` is the questions, one file per
subject, in the order `harness/runner.lua` lists. Every file is its own chunk
with its own two hundred names. The worst declares fifty eight.

**What one section leaves for a later one is named at both ends.** Sections
depend on each other on purpose: a churn figure measured in one is compared in
another, the skin is fitted in one and taken off again three down. In the single
file that worked because the variable was still in scope, which is also how a
section could pick one up by accident. It goes through `H.carry` now, written
where it is handed over and read where it is used. The ten values the stub keeps
and a section writes, the purse and the repair bill and how tall the screen is,
live on one table that both sides name.

**Naming a section stops the run after it.**

    lua5.1 scripts/harness.lua src WARRIOR 12-debuff-square-size

Everything above that section still runs. Not the section alone: it reads what
the ones above it left behind, so a run of one on its own is a crash rather than
a smaller suite.

**`check.sh` measures the shape**, which is the part that was missing the whole
time. No harness file over 800 lines or 40 names at chunk level unless it carries
its own ceiling and a written reason, both ratcheting in each direction, and the
runner's section list has to match what is on disk.

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
