# Todo

Seven pieces, in this order. Each is built by one agent in its own worktree under
`.worktrees/`, on a branch named `worktree-<name>`, and merged into main
when `./scripts/check.sh` comes back at zero. The worktrees stay after the
merge.

## 1. Weapon swing timer  [merged, STILL BROKEN, parked]

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

### Still not fixed. Parked, come back to it.

Tested in game after the first repair. The bar is still chunky. The Slam mark
was not reported again, so treat that half as unconfirmed rather than fixed.

What the repair changed, so the next attempt does not redo it: the fill was
drawn on a 50 ms ticker whose accumulator reset to zero instead of subtracting
the interval, which made the real rate 15 Hz on a 60 fps client and the real
step 3.5 pixels. It draws every frame now and the accumulator is gone. That was
a real bug and it was not the whole cause, because the bar still steps.

What was ruled out by reading, and should be re-checked rather than trusted:
`bar.pixels` is not stale on any reachable path, `Whole()` and
`SetMinMaxValues` agree on 180 units meaning 180 physical pixels at zoom 1, and
the quantisation to whole pixels is correct.

What has not been looked at. The gauge is a client `StatusBar` fed whole pixel
values through `SetValue`, so the next place to look is `UI/Gauge.lua` and what
the client does with a value between two of its own steps. Also worth checking:
whether the OnUpdate is attached to a frame that is throttled or hidden, what
the fill's texture anchoring does at a fractional width, and whether the swing's
start time comes from an event that arrives in bursts rather than from GetTime.
Ask the user for a screen recording or a frame by frame description before
guessing again, because two rounds of reading have now produced one real bug
and no fix.

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
