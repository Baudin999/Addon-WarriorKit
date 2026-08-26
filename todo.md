# Todo

Seven pieces, in this order. Each is built by one agent in its own worktree under
`.worktrees/`, on a branch named `worktree-<name>`, and merged into main
when `./scripts/check.sh` comes back at zero. The worktrees stay after the
merge.

## 1. Weapon swing timer  [built, fixed twice, wants one look in game]

The addon talks about the swing and never draws it. `UI/Ability.lua:48` says
Heroic Strike is armed and goes off on the next swing, `UI/Ability.lua:229`
brightens the border to say so, and nothing on screen says when that swing
lands. Arms is guesswork without it.

Two gauges under the player, main hand and off hand. `UI/Gauge.lua` draws
them, `Meter/Meter.lua:54` already reads `SWING_DAMAGE` off the combat log, and
`Unit/Color.lua` holds the palette. Reset the timer on a Slam cast, re-read
`UnitAttackSpeed` when haste moves, and mark the window where pressing Slam
costs no swing. That window is the point of the feature, so it is drawn rather
than left to be read off a moving bar.

### What was actually wrong

There were two throttles on one moving edge and the first one hid the second.

The first was the ticker. The fill was drawn on a 50 ms ticker whose
accumulator reset to zero instead of subtracting the interval, so the real rate
was 15 Hz on a 60 fps client and the real step 3.5 pixels. That was fixed and
the bar still stepped, which is what made the first repair look wrong. It was
not wrong; it was half.

The second was the rounding, in `DrawHand` in `Swing/Gauges.lua`. The fill was
snapped to a whole pixel before being written, and a fill snapped to a whole
pixel can only change value as many times as the bar has pixels. At 180 pixels
across a 3.4 second swing that is 53 times a second and no oftener, whatever
rate the tick runs at. Deleting the ticker raised the drawn rate from 20 to 53
and left that ceiling exactly where it was. The bar stood still on 91 of the 144
frames a fast screen draws, and every move was a whole design unit, which is
three screen pixels at `swing zoom 3`.

Nothing was wrong with `UI/Gauge.lua`, with `bar.pixels`, with the `StatusBar`
or with where the swing's start time comes from. The client's own cast bar is a
`StatusBar` fed a float and it glides. The quantiser was ours.

The fill is now written as a fraction, every frame, unguarded. That needed the
addon's whole-pixel rule split into two rules rather than excused once: a static
edge lands on a whole pixel, a moving fill is not quantised. Both are in
`docs/README.md` under the pixel grid and both are gated in the harness.

The old assertions were the wrong statements and are gone. "Never jumps more
than one pixel between two frames" and "visits all 180 positions" are both
satisfied by a quantised fill, which is why they passed twice against a bar that
stepped. What is asserted now is that the drawn position equals the elapsed
fraction exactly, that it changes on every frame at 60 fps and at 144, and that
every step is the same size. No harness assertion can prove a bar looks smooth,
and the README says so rather than pretending.

What to check in game: pull something with a slow weapon and watch the main hand
bar fill. The edge should glide with no stutter and no stall, at any
`/wk swing zoom`. The Slam mark was not re-reported after the first repair and
nothing here touched it, so it is still unconfirmed rather than fixed.

## 2. Deep Wounds is missing from the enemy bar debuffs  [merged]

The debuff walk at `UnitFrames/EnemyBars.lua:552` does not show Deep Wounds.
Find out why and fix it. The likely cause is that the bleed is attributed to a
source the filter rejects, so the check is on what `sourceUnit` actually comes
back as for a proc rather than on the aura's name.

## 3. Overpower is drawn as ready when it is not  [merged]

Overpower can only be pressed inside the few seconds after the target dodges,
and the bars show it as ready all the time. `Buttons/Slot.lua:188` asks
`IsUsableAction`, and this client answers yes for a reactive ability whether or
not the window is open, so the ladder never reaches a status that says no.

Watch the combat log for a dodge against your target, hold the window, and let
the slot report it. Revenge is the same mechanism off a block, dodge or parry
of yours, so build the window once and use it twice. Third in the order because
it wants the same combat-log watching item 1 stands up.

## 4. Missing buff nag, including racials

Nothing in the addon reads your own auras. A lapsed sharpening stone costs more
damage than most rotational mistakes, and Battle Shout falling off is silent
today. A row of dim icons for what is missing, out of combat.

Racials are in scope, and Blood Fury is the reason the feature exists. The long
cooldowns, Death Wish and Recklessness, are timed by hand and stay out of this
one; they are item 7.

## 5. Enemy cast bar

`grep UNIT_SPELLCAST` returns nothing across the addon. The enemy bars replace
the nameplate, so replacing it costs the one thing that says when to Pummel or
Shield Bash. The per-unit tick already exists in `UnitFrames/EnemyBars.lua`.

## 6. Party frames

`UnitFrames/Skin.lua:180-223` skins player, target and target of target, then
stops. The Charge button casts Intervene at whoever you are looking at and
there is no fast way to look at a party member, so the frames close a loop the
addon already opened.

## 7. Cooldown row for the long cooldowns

Death Wish, Recklessness, Shield Wall, Last Stand, trinkets. The bars draw a
swipe, but the cooldowns that matter are the ones not under your eyes.
