---
revision: 1
id: 01M1Y4JJF3NH511BGFDH3N7JY9
type: task
status: todo
title: The set that follows your spec
parent: 01M1Y4JDFMVHEB87QK9R1KP4BJ
---

Phase 5 of the equipment manager, and the one to build last or not at all.

## What lands

A set may name one of `Class.Spec.All()`. The chip on the character page
shows the badge, and when `Class/Spec.lua` reports your spec has moved, the
set that names the new one is offered.

Offered rather than applied. See below.

## Why this is the weakest phase

TBC has no dual spec. You respec at a trainer, it costs gold, and it happens
maybe once a week. That is already an out of combat moment where you are
standing in a city with time to click a chip.

So the automatic swap is a swap that fires once a week in a situation where
the manual path was fine. The key from phase 4 is what gets pressed forty
times a night, and the sets people actually switch between on this client are
tanking against dps, PvE against PvP, and a resistance set for one boss.
None of those is a spec change.

What the spec link is genuinely worth is the label. A badge saying which spec
a set belongs to is how you tell four sets apart at a glance, and that is
most of the value for none of the risk.

Build the badge. Hold the automatic apply until somebody asks for it twice.

## Testing it in game

The badge draws from `Spec.Token()` without respeccing. The offer needs a
forced re-read, which `Class/Spec.lua` already has a path for: `Spec.Forget`
and the pass that prints when the answer changes.

## The gate

Extends `88-gear-sets.lua`. A set with no spec named behaves exactly as it
did in phase 1, which is the assertion that matters: nothing about this phase
may change what a set without a badge does.
