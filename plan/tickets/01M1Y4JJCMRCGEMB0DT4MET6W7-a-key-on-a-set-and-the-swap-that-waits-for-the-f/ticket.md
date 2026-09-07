---
revision: 1
id: 01M1Y4JJCMRCGEMB0DT4MET6W7
type: task
status: todo
title: "A key on a set, and the swap that waits for the fight"
parent: 01M1Y4JDFMVHEB87QK9R1KP4BJ
---

Phase 4 of `01M1Y4JDFMVHEB87QK9R1KP4BJ`, the equipment manager. The part
that gets pressed forty times a night.

## What lands

A key per set. The chip on the character page shows what it is bound to, and
the key is taken and handed back the way the addon already takes a key
everywhere else.

There is a card open about that: taking a key off the client is written eight
times in this tree. This is the ninth, so it either uses whatever that card
lands or it is written to be the ninth caller of it. Do not write a tenth
private copy.

No secure button. Nothing in a gear swap is protected, so the key runs plain
Lua, and the ten buttons at login that killed the weapon loadouts do not come
back.

## The swap that waits

Press it in a fight and the hands go on immediately, because slots 16, 17 and
18 are the three combat allows. The rest is held and finished on
`PLAYER_REGEN_ENABLED`, and the line says so:

    put on prot: shield on, 9 pieces waiting for the fight to end

Refusing would be the wrong answer. A shield press mid pull is exactly when
you want this, and the queue from phase 1 already exists, so the wait is a
state on the queue rather than a second mechanism.

A second press while a swap is waiting replaces the wait rather than queueing
behind it. Two sets half applied is the worst outcome available here.

## Testing it in game

Bind a key to a tanking set. Press it standing still and watch the whole
thing go on. Pull something, press it, watch the shield land and the rest
wait, then let the fight end and watch it finish. Press two different sets
mid fight and confirm the second one wins outright.

## The gate

Extends `88-gear-sets.lua`. The combat split plans the hands and defers the
rest, the deferred half runs on regen enabled, and a second apply replaces a
waiting one instead of stacking.
