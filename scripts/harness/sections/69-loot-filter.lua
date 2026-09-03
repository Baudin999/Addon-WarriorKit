-- The loot filter
--
-- Fast loot takes everything, which is what you want on a pull and not what you
-- want on the twelfth corpse of an old dungeon. The filter is the sentence the
-- player says out loud put into settings: cloth, greens and up, mining, and
-- what my professions use.
--
-- The assertions that carry the weight here are the negative ones, the way they
-- are in the chores section above. A filter that takes too much is a bag you
-- clear by hand, which is where this started; a filter that takes too little
-- has walked past something you wanted and there is no way back to that corpse.
-- So every pass reads which slots came home rather than how many, the two slots
-- that may never be refused are asserted under every combination of rules, and
-- the master loot guard is asked again with the filter on top of it, because
-- the filter must not be able to talk the addon into a slot the master looter
-- has to hand out.
--
-- The corpse this section stands up is a longer one than the four slots every
-- other section counts, one slot per rule, and it is put back at the foot of
-- the file.

local H = ...
local ns, check, fire, advance = H.ns, H.check, H.fire, H.advance
local state, loot, looted, ITEMS = H.state, H.loot, H.looted, H.ITEMS

-- One slot per rule the filter has, so a claim about a rule is a claim about a
-- slot. The coins first because they are on every corpse in the game, and the
-- quest item and the grey femur because they are the two the filter has to
-- treat as opposites: one is never refused whatever is switched off, and the
-- other is wanted by nothing here at all.
local COINS, CLOTH, ORE, GREEN, QUEST, JUNK = 1, 2, 3, 4, 5, 6
local CRAFTED, HERB, LEATHER, DUST, MEAT, GEM = 7, 8, 9, 10, 11, 12

local SLOTS = {
	{ quality = 0 },
	{ quality = 0, item = "Moth-eaten Wool" },
	{ quality = 1, item = "Silver Ore" },
	{ quality = 2, item = "Bandit's Cudgel" },
	{ quality = 1, item = "Mangled Sigil", quest = true },
	{ quality = 0, item = "Splintered Femur" },
	{ quality = 1, item = "Elemental Water" },
	{ quality = 1, item = "Peacebloom" },
	{ quality = 1, item = "Light Leather" },
	{ quality = 1, item = "Strange Dust" },
	{ quality = 1, item = "Chunk of Boar Meat" },
	{ quality = 1, item = "Tigerseye" },
}

-- One pass over the corpse with the settings as they stand. The clock is
-- advanced past the throttle first, because Comfort/Loot.lua empties a corpse
-- once and ignores the rest of the burst, and a pass that fell inside the
-- throttle would look exactly like a filter that refused everything.
local function pass()
	for slot in pairs(looted) do
		looted[slot] = nil
	end
	advance(1)
	fire("LOOT_READY")
end

-- Which slots came home, in order. A number rather than a count, so a failure
-- names the slot that was taken or left instead of saying it was one out.
local function took()
	local slots = {}
	for slot in pairs(looted) do
		slots[#slots + 1] = slot
	end
	table.sort(slots)
	return table.concat(slots, " ")
end

local function expect(...)
	local slots = { ... }
	table.sort(slots)
	return table.concat(slots, " ")
end

-- Every rule off and the colour rule with it, which is the state every claim
-- below starts from: whatever it takes, it takes because of the one thing that
-- section turned on.
local function nothing()
	ns.dbc.lootFloor = 5
	ns.dbc.lootCloth, ns.dbc.lootOre, ns.dbc.lootHerbs = false, false, false
	ns.dbc.lootLeather, ns.dbc.lootEnchanting = false, false
	ns.dbc.lootGems, ns.dbc.lootMeat = false, false
	ns.dbc.lootCrafted = false
end

_G.SetCVar("autoLootDefault", 1)
state.lootMethod = "group"
ns.db.fastLoot = true
ns.Loot.Apply()
loot.Set(SLOTS)

----------------------------------------------------------------------
-- Off is the addon as it was
----------------------------------------------------------------------

ns.dbc.lootFilter = false
pass()
check(took() == expect(COINS, CLOTH, ORE, GREEN, QUEST, JUNK, CRAFTED, HERB,
	LEATHER, DUST, MEAT, GEM),
	("the filter off left slots behind, and took %s"):format(took()))
check(ns.Wanted.Describe() == "off",
	("the filter off reads as %q"):format(ns.Wanted.Describe()))

----------------------------------------------------------------------
-- On with every rule off
----------------------------------------------------------------------

-- The two that are never refused, and nothing else. This is the shape the
-- whole feature is measured against: a filter with nothing switched on is a
-- player who said they want the coins and the quest items, and a corpse they
-- walked away from with a grey femur in the bag is the bug.
ns.dbc.lootFilter = true
nothing()
pass()
check(took() == expect(COINS, QUEST),
	("every rule off took %s, and the coins and the quest item are all it may"):format(took()))
check(not looted[JUNK],
	"a slot the filter refused was looted anyway, so LootSlot ran on a refusal")

----------------------------------------------------------------------
-- The colour floor
----------------------------------------------------------------------

ns.dbc.lootFloor = 2
pass()
check(took() == expect(COINS, QUEST, GREEN),
	("greens and up took %s"):format(took()))

ns.dbc.lootFloor = 1
pass()
check(took() == expect(COINS, QUEST, GREEN, ORE, CRAFTED, HERB, LEATHER, DUST,
	MEAT, GEM),
	("whites and up took %s, and every grey on the corpse should have stayed"):format(took()))

ns.dbc.lootFloor = 0
pass()
check(took() == expect(COINS, CLOTH, ORE, GREEN, QUEST, JUNK, CRAFTED, HERB,
	LEATHER, DUST, MEAT, GEM),
	("greys and up took %s, which is not the whole corpse"):format(took()))

----------------------------------------------------------------------
-- One kind rule at a time
----------------------------------------------------------------------

-- Each on its own, from a corpse where the colour rule is switched off, so the
-- slot that comes home comes home because of the class and subclass the client
-- files it under and for no other reason. A rule that read the wrong subclass
-- would take somebody else's slot and this is where that shows.
local KINDS = {
	{ key = "lootCloth", slot = CLOTH },
	{ key = "lootOre", slot = ORE },
	{ key = "lootHerbs", slot = HERB },
	{ key = "lootLeather", slot = LEATHER },
	{ key = "lootEnchanting", slot = DUST },
	{ key = "lootGems", slot = GEM },
	{ key = "lootMeat", slot = MEAT },
}

for index = 1, #KINDS do
	local entry = KINDS[index]
	nothing()
	ns.dbc[entry.key] = true
	pass()
	check(took() == expect(COINS, QUEST, entry.slot),
		("%s on took %s, and slot %d is the one it names")
			:format(entry.key, took(), entry.slot))
end

----------------------------------------------------------------------
-- What my professions use
----------------------------------------------------------------------

-- Comfort/Reagents.lua is the part that answers this and it is asked for by
-- name at the moment the question comes up, so both halves of that are worth a
-- pass: one where it is there and says yes to one item, and one where it is not
-- there at all, which is the state a build without that file is in and must not
-- be a Lua error over a corpse.
-- The real part is loaded by now and 70-reagents.lua reads it, so it is put
-- back at the foot of this block rather than dropped.
local reagents = ns.Reagents
nothing()
ns.dbc.lootCrafted = true
ns.Reagents = {
	Has = function(itemId) return itemId == ITEMS["Elemental Water"].id end,
}
pass()
check(took() == expect(COINS, QUEST, CRAFTED),
	("the profession scan took %s, and slot %d is the one it wanted")
		:format(took(), CRAFTED))

ns.Reagents = nil
pass()
check(took() == expect(COINS, QUEST),
	("with no profession scan the filter took %s"):format(took()))
ns.Reagents = reagents

----------------------------------------------------------------------
-- Master loot, with the filter on top of it
----------------------------------------------------------------------

-- The threshold is 2 and it is the outer rule: a slot at or above it belongs to
-- the master looter whatever the filter says, and the filter deciding it wants
-- greens must not reach past that. With the colour rule wide open the corpse
-- comes home except for the one slot the master looter has to hand out.
nothing()
ns.dbc.lootFloor = 0
state.lootMethod = "master"
pass()
check(took() == expect(COINS, CLOTH, ORE, QUEST, JUNK, CRAFTED, HERB, LEATHER,
	DUST, MEAT, GEM),
	("master loot with the filter wide open took %s, and the green is the"
		.. " master looter's"):format(took()))

-- And the filter still refuses inside what master loot allows.
nothing()
pass()
check(took() == expect(COINS, QUEST),
	("master loot with every rule off took %s"):format(took()))
state.lootMethod = "group"

----------------------------------------------------------------------
-- The reading
----------------------------------------------------------------------

nothing()
ns.dbc.lootFloor = 2
ns.dbc.lootCloth, ns.dbc.lootOre, ns.dbc.lootCrafted = true, true, true
check(ns.Wanted.Describe() == "greens and up, cloth, ore, and what my professions use",
	("the filter reads as %q"):format(ns.Wanted.Describe()))

nothing()
ns.dbc.lootHerbs = true
check(ns.Wanted.Describe() == "nothing by colour, herbs",
	("the filter with one rule on reads as %q"):format(ns.Wanted.Describe()))

----------------------------------------------------------------------
-- The corpse and the settings put back
----------------------------------------------------------------------

nothing()
ns.dbc.lootFloor = 2
ns.dbc.lootCloth, ns.dbc.lootOre, ns.dbc.lootCrafted = true, true, true
local shipped = ns.Wanted.Describe()
ns.dbc.lootFilter = false

loot.Reset()
advance(1)
fire("LOOT_READY")
check(H.CORPSE and #H.CORPSE == 4,
	("the corpse came back with %d slots on it"):format(#H.CORPSE))

print(("loot   a corpse of %d slots, %d kind rules one at a time; off takes all"
	.. " %d, every rule off leaves all but the coins and the quest item, and"
	.. " switched on it ships %s")
	:format(#SLOTS, #KINDS, #SLOTS, shipped))
