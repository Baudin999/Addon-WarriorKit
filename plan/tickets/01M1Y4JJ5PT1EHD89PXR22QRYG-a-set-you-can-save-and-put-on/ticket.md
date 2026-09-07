---
revision: 1
id: 01M1Y4JJ5PT1EHD89PXR22QRYG
type: task
status: todo
title: A set you can save and put on
parent: 01M1Y4JDFMVHEB87QK9R1KP4BJ
---

Phase 1 of the equipment manager. The model, the planner, the queue, and four
slash words. No UI at all, and it is still a thing you can use for a week.

## What lands

`src/Sets/` with four files, in the shape every other folder here has.

    Sets/Key.lua      an item's identity, and the scan that finds one
    Sets/Sets.lua     the model: what a set is, saved and read back
    Sets/Apply.lua    the plan and the queue
    Sets/Feature.lua  ns.Register: saved variables, slash words, status, help

`Key.lua` reads fields 2 through 8 of the item string, which is id, enchant,
four gems and suffix, and drops `uniqueId` onward. See the feature card for
why that is the cut. It also owns the sweep that answers "where is the item
with this key", over the five bags and the nineteen worn slots.

`Sets.lua` holds sets in `charDefaults`, because gear is a fact about one
character. A slot is an item, deliberately empty, or unset, and unset is the
default for every slot a save did not fill.

`Apply.lua` is the plan and the queue described on the feature card. The plan
is pure and takes the world as an argument, which is what makes it testable
without a client.

## The words

    /wk set save <name>     what you have on, into a set of that name
    /wk set wear <name>     put it on
    /wk set list            the sets, and how much of each you can reach
    /wk set forget <name>   drop one

`save` fills all nineteen. Partial sets are phase 3's, built by editing.

`wear` refuses in a fight with the reason, and names the three slots that
would have been allowed. The wait for `PLAYER_REGEN_ENABLED` is phase 4's.

The reply is one line:

    put on fury: 12 changed, 4 already on, 1 not in your bags (Dragonspine Trophy)

`ns.Register` also owns the `status` line and the `help` lines, the way every
other feature does.

## Testing it in game

Wear your fury gear. `/wk set save fury`. Swap three pieces, one of them a
ring so the two slot case runs. `/wk set wear fury` and watch them go back.
Then put a piece in the bank and wear it again, and read the sentence that
names what it could not reach.

## The gate

`scripts/harness/sections/88-gear-sets.lua`, driving the planner against
stubbed bags and inventory. What it has to assert:

- a set already worn plans zero moves;
- two rings trading places plans the three cursor operations and no bag slot;
- a source that moved between the plan and the move is re-checked and skipped
  rather than moved blind;
- an item nowhere reachable leaves its slot alone and is named in the report;
- the deadline fires and the queue stops.

The stubs go in `scripts/harness/client/`, extending what `04-hands.lua`
already fakes for the worn slots rather than a second fake beside it.
