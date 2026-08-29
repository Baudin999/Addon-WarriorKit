# Why the mouseover keys cast

One key, one spell, and whatever the mouse is over. This is the part of the
addon with the most ways to fail silently, so this file is the chain a press
travels and the evidence for each link. It was written after the feature bound
its keys correctly for weeks and cast nothing.

Nothing here is read out of the client's own Lua. That source is not on this
machine. Every claim below is inferred from working code that runs on this
client, and each one names where.

## The chain

You press `SHIFT-BUTTON3`. Five things have to line up.

1. The key has to be on the binding layer, pointing at the button.
2. The click has to be dispatched to the button rather than dropped.
3. The button has to act on the edge the click arrives on.
4. The client has to compute an attribute name the button actually carries.
5. The attribute has to name a spell and a unit, not run a script.

Only the first is visible from inside the addon. `GetBindingAction` reads the
layer back, and `Cast.Apply` believes the readback rather than its own call. The
other four leave no trace at all. A key that fails at step four looks exactly
like a key that was never bound, except the readback says it was.

## Step four is the one that was wrong

`SetOverrideBindingClick(button, true, key, BUTTON_NAME, name)` puts
`CLICK WarriorKitHoverButton:<name>` on the layer. When the key is pressed the
click arrives at the button carrying `<name>`, and the client turns that name
into the tail of an attribute it looks up.

It answers five names with a bare number. LeftButton is `1`, RightButton is `2`,
MiddleButton is `3`, then Button4 and Button5. Every other name is a name, and
the client puts a dash in front of it before using it as a suffix.

This file used to hand over `"1"`. That is not button one, it is a name that
happens to be a digit, so the press went looking for `type-1` while the action
sat under `type1`. The binding was right, the readback was right, the press
arrived, and nothing was there.

Three pieces of working code say so.

`Clique/core/utils.lua`, in `AttributeName`, branches on exactly this:

```lua
local suffixSep = tonumber(suffix) and "" or "-"
```

A numeric suffix is a real mouse button and gets no dash. Anything else gets
one. That branch is Clique writing down the client's rule.

`Clique/core/attributes.lua` never hands the binding layer a number. Every name
it sends is a word it built itself, `cliquebuttonshiftF` or `cliquemousealt3`,
and every attribute it writes for one carries the dash:
`type-cliquebuttonshiftF`.

`Buttons/Bars.lua` in this addon is the same rule seen from the other side, and
is why its keys have always worked. It hands over the literal `LeftButton`,
which is one of the five, and reads `type1`.

So the click is `wk<index>` and the action is `*type-wk<index>`.

## The star in front

The client reads the modifier off the keyboard at the moment of the press and
puts it on the front of the name. A binding on `ALT-BUTTON3` therefore asks for
`alt-type-wk1`. Every key worth putting a mouseover spell on carries a modifier,
so the modified name is the only name most presses will ever ask for.

`*` is the wildcard the client falls back to when the modified name holds
nothing. Writing under it means one attribute answers every modifier state.
`UnitFrames/Group.lua` writes its click actions the same way.

Clique does not do this. It sets the prefix to empty for its global button and
writes the bare name. That works for it and would not work here, and the honest
answer is that I cannot tell you why from the code on disk. The wildcard covers
both cases, so this file uses it and does not depend on the answer.

## The filter is a second name

There is no attribute meaning "only when it is an enemy". A macro conditional
says it, `[@mouseover,harm]`, but a conditional needs macro text, and macro text
set by insecure code and run off a keypress is the one thing the secure system
exists to refuse. It reads it, declines it, and says nothing. That is how this
shipped once.

`harmbutton` and `helpbutton` say the same thing in a name. `*harmbutton-wk1`
holding `enemywk1` tells the client to deliver the click as `enemywk1` instead
of `wk1` when the unit under the cursor can be attacked. The action lives only
under `enemywk1`. A press on a friend arrives as `wk1`, finds no type, and does
nothing, which is the same silence a conditional gives and costs no script.

`*unit-wk1` has to be `mouseover` for this to work at all, because the remap is
a question about a unit and that attribute is what says which unit to ask about.

The one thing lost with the conditional is `nodead`. A key pressed on a corpse
now casts and the client refuses it out loud. That is worse manners than the old
silence and better than not casting.

The conditional is still written, in `Hover.Macro`. Nothing presses it. It is
the line `/wk hover show` prints, because a player can read a macro, and it is
what the debug log hands to `SecureCmdOptionParse` when it wants the client's own
opinion of the same filter.

## Which edge

`RegisterForClicks` decides whether the click is dispatched at all. A click
matching no registration is dropped before any script runs, which is silent in
exactly the way an unbound key is silent.

`useOnKeyDown` decides which edge a key-delivered click acts on. Those are two
switches, not one, and letting them disagree is its own bug. `Buttons/Bars.lua`
already paid for that lesson: forty eight cloned squares that drew, lit, counted
down and cast nothing under the key, because they registered `AnyUp` against an
unset attribute.

So this button registers `AnyDown` and sets `useOnKeyDown` to true, and
`44-hover.lua` asserts the two agree rather than asserting either value. Clique
pairs the same two on its own global button and ships them on the down edge.

## The log, and why it is a PostClick

`/wk hover debug on` prints a line where the binding is written, a line where the
press arrives, the verdict, and `UNIT_SPELLCAST_SENT` when the client actually
sends something. A press with an arrival line and no sent line is the press being
thrown away.

It is a `PostClick`, installed only while the log is on, and both halves matter.
A `PreClick` runs insecure Lua inside the click before the secure handler, which
taints it, so the protected call at the end is dropped. An early return does not
help. The taint is the script running at all. For a while the log sat under every
press saying everything was fine while being the reason nothing cast.

With the log off there is no script on this button and the click path is the
client's own.

## What the harness cannot prove

`44-hover.lua` pins the names, the readback, the edge, the leftovers a removed
binding must not leave behind, and that the log survives a press. The stub's
`SetAttribute` is a table. It cannot tell you the client agrees about any of it.

To settle it in game: bind a spell, hover a mob, press the key. With the log on,
a press that works prints `the client sent <spell> at <target>`. A press with no
such line is still asking for a name the button does not carry.
