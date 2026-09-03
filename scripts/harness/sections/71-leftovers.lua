-- Destroying what the loot filter refused
--
-- The switch for the person who skins: a corpse only opens for a skinner once
-- every slot is gone, so a slot the filter would have left is looted anyway and
-- the item is destroyed when it lands. It is the only thing in the addon that
-- deletes what you own with nobody looking at it, so most of what is asserted
-- here is the refusals. The blue and the quest item on the corpse are the two
-- that matter, and both have to end with the slot still on the corpse and
-- nothing destroyed.
--
-- The arithmetic is the other half. Loot lands in a stack you already had, so
-- the slot the item arrived in is not the item that arrived: three cloth
-- carried in and two looted is one stack of five, and what has to come out of
-- it is two.
--
-- This section runs on bags of its own and puts the character's back at the
-- foot of the file. Every other section that touches a bag works on the ones
-- the fixtures give you, and that is right for a sweep counted against what is
-- in them. This one is arithmetic about where one item landed, and a second
-- stack of the same cloth in some bag above would take the landing and let
-- every assertion pass for the wrong reason.

local H = ...
local ns, fire, check = H.ns, H.fire, H.check
local advance, events = H.advance, H.events
local CARRIED, carrying, counted = H.CARRIED, H.carrying, H.counted
local ITEMS = H.ITEMS
local loot, looted, destroyed = H.loot, H.looted, H.destroyed

local Leftovers = ns.Leftovers

local opened = #destroyed

local held = {}
for index = 0, 4 do
	held[index] = CARRIED[index]
	CARRIED[index] = nil
end

-- One bag, with as many free slots as it is given names.
local function bags(...)
	CARRIED[4] = { ... }
end

-- The corpse in front of you, stood up in place of the four slots every other
-- section counts, the way 69-loot-filter.lua does. The counter is cleared with
-- it, so no scene reads what the one above it took. A slot's quality is the
-- item's own, because that is what the client answers for a slot too.
local function corpse(...)
	for slot in pairs(looted) do
		looted[slot] = nil
	end
	local slots = {}
	for index, spoil in ipairs({ ... }) do
		slots[index] = { item = spoil.item, count = spoil.quantity,
			quest = spoil.quest, quality = ITEMS[spoil.item].quality }
	end
	loot.Set(slots)
end

local function listening(event)
	return #(events[event] or {})
end

ns.dbc.lootDestroy = true
Leftovers.Apply()

check(listening("BAG_UPDATE_DELAYED") == 1,
	"the switch went on and nothing is listening for a bag to change")
check(listening("LOOT_CLOSED") == 1,
	"the switch went on and nothing is listening for the corpse to close")

----------------------------------------------------------------------
-- A grey the filter refused
----------------------------------------------------------------------

advance(1)
bags(false, false, false)
corpse({ item = "Chipped Boar Tusk" })

local before = #destroyed
check(Leftovers.Discard(1) == true, "a grey the filter refused was left on the corpse")
check(looted[1] == true, "the grey was never taken off the corpse")
check(#destroyed == before + 1,
	("%d items were destroyed where one grey was looted to be destroyed")
		:format(#destroyed - before))
check(Leftovers.Pending() == 0,
	("%d items are still pending after the grey landed"):format(Leftovers.Pending()))
check(carrying(4, 1) == nil, "the grey that was destroyed is still in the bag")

----------------------------------------------------------------------
-- Three carried in and two looted ends at three
--
-- The one claim the whole file rests on. Both stacks are the same item and no
-- call in this client can tell them apart, so what is destroyed has to be the
-- count that arrived rather than the slot it arrived in.
----------------------------------------------------------------------

advance(1)
bags("Linen Cloth", false, false)
counted(4, 1, 3)
corpse({ item = "Linen Cloth", quantity = 2 })

check(Leftovers.Discard(1) == true, "a white the filter refused was left on the corpse")
check(carrying(4, 1) == "Linen Cloth",
	"the stack that was carried in went with the two that were looted")
check(counted(4, 1) == 3,
	("the stack holds %d cloth where three were carried in and two were looted")
		:format(counted(4, 1)))
check(Leftovers.Pending() == 0,
	("%d items are still pending after the cloth landed"):format(Leftovers.Pending()))

----------------------------------------------------------------------
-- The two that are never taken
----------------------------------------------------------------------

advance(1)
bags(false, false, false)
corpse({ item = "Aged Chain Vest" })

before = #destroyed
check(Leftovers.Discard(1) == false, "a blue was taken off the corpse")
check(looted[1] == nil, "a blue was looted with the switch on")
check(#destroyed == before, "a blue was destroyed")
check(Leftovers.Pending() == 0, "a blue was left pending")

corpse({ item = "Hogger's Claw", quest = true })

check(Leftovers.Discard(1) == false, "a quest item was taken off the corpse")
check(looted[1] == nil, "a quest item was looted with the switch on")
check(#destroyed == before, "a quest item was destroyed")
check(Leftovers.Pending() == 0, "a quest item was left pending")

----------------------------------------------------------------------
-- What the throttle skipped, and the corpse closing behind it
--
-- One pass over the bags a frame, so two slots taken inside one frame leave the
-- second waiting. LOOT_CLOSED is what comes back for it, because an item that
-- arrived under the throttle has nothing else coming.
----------------------------------------------------------------------

advance(1)
bags(false, false, false)
corpse({ item = "Chipped Boar Tusk" }, { item = "Tattered Cloth" })

Leftovers.Discard(1)
Leftovers.Discard(2)
check(Leftovers.Pending() == 1,
	("%d items are pending where the second landed inside the first one's frame")
		:format(Leftovers.Pending()))

advance(1)
fire("LOOT_CLOSED")
check(Leftovers.Pending() == 0,
	"the corpse closed and what arrived under the throttle was left in the bags")
check(carrying(4, 1) == nil and carrying(4, 2) == nil,
	"a bag slot still holds what the corpse closing was supposed to clear")

----------------------------------------------------------------------
-- Nothing arrived, so the entry is dropped
--
-- A LootSlot the server refused because the bags were full is an item that
-- never lands. The entry has to go, because one left waiting would destroy the
-- next one of those picked up an hour later.
----------------------------------------------------------------------

advance(1)
CARRIED[4] = {}
corpse({ item = "Chipped Boar Tusk" })

before = #destroyed
check(Leftovers.Discard(1) == true, "a grey was left on a corpse with the bags full")
check(Leftovers.Pending() == 1,
	"a slot taken with nowhere to put it left nothing pending")

advance(1)
fire("BAG_UPDATE_DELAYED")
check(Leftovers.Pending() == 1, "a pending item was dropped before its five seconds were up")

advance(6)
fire("BAG_UPDATE_DELAYED")
check(Leftovers.Pending() == 0,
	"a pending item that nothing ever arrived for is still waiting")

bags("Chipped Boar Tusk", false, false)
advance(1)
fire("BAG_UPDATE_DELAYED")
check(carrying(4, 1) == "Chipped Boar Tusk",
	"one of those turning up later was destroyed for an entry that had expired")
check(#destroyed == before, "something was destroyed where nothing ever arrived")

local said = Leftovers.Describe()
check(said:find("looted and destroyed") ~= nil,
	("the switch is on and reads %q"):format(said))
check(said:find("gone this session") ~= nil,
	("the switch has destroyed things this session and reads %q"):format(said))

----------------------------------------------------------------------
-- Off
----------------------------------------------------------------------

ns.dbc.lootDestroy = false
Leftovers.Apply()

check(listening("BAG_UPDATE_DELAYED") == 0,
	"the switch went off and the bag event is still registered")
check(listening("LOOT_CLOSED") == 0,
	"the switch went off and LOOT_CLOSED is still registered")

corpse({ item = "Chipped Boar Tusk" })
check(Leftovers.Discard(1) == false, "the switch is off and a slot was still taken")
check(looted[1] == nil, "the switch is off and a slot was still looted")
check(Leftovers.Describe() == "off",
	("the switch is off and reads %q"):format(Leftovers.Describe()))

loot.Reset()
for index = 0, 4 do
	CARRIED[index] = held[index]
end

print(("leftovers %d items destroyed, %s"):format(#destroyed - opened, Leftovers.Describe()))
