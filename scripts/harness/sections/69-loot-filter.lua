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
	ns.dbc.lootWorth = 0
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
-- A grey or white worth carrying to a vendor
----------------------------------------------------------------------

-- The floor is read against the whole slot, so the fixture's prices are the
-- claim: the dust is a slot worth one silver, the gem two, the water four,
-- and the ore thirty copper. The cudgel is worth twelve silver and is green,
-- and it staying on the corpse is the assertion that carries the weight: the
-- price rule reads greys and whites and nothing the colour floor was told to
-- refuse.
nothing()
ns.dbc.lootWorth = 100
pass()
check(took() == expect(COINS, QUEST, DUST, GEM, CRAFTED),
	("a floor of one silver took %s, and the dust, the gem and the water are"
		.. " the three slots worth that"):format(took()))

ns.dbc.lootWorth = 30
pass()
check(took() == expect(COINS, QUEST, ORE, DUST, GEM, CRAFTED),
	("a floor of thirty copper took %s, and the ore is worth exactly that"):format(took()))

-- Two on the slot doubles what the slot is worth, which is the whole reason
-- the rule reads the slot rather than the item.
loot.Set({ { quality = 0 }, { quality = 1, item = "Light Leather", count = 4 } })
ns.dbc.lootWorth = 100
pass()
check(took() == expect(1, 2),
	("four leather at twenty five is a slot worth a silver, and the pass took %s"):format(took()))
loot.Set({ { quality = 0 }, { quality = 1, item = "Light Leather", count = 3 } })
pass()
check(took() == expect(1),
	("three leather at twenty five is under a silver, and the pass took %s"):format(took()))
loot.Set(SLOTS)

-- An item the client has not priced yet is left on the corpse and asked
-- about again when the price arrives. The stub's "not cached" is GetItemInfo
-- answering nothing, and with the floor on that must read as neither: keep
-- let a Tough Cloak worth four silver through on its first sighting in game,
-- and refuse would bin a white sword worth two gold on its. Four whites at
-- twenty five is a slot worth a gold, so the answer, once it comes, is take.
loot.Set({ { quality = 0 }, { quality = 1, item = "Light Leather", count = 4 } })
ns.dbc.lootWorth = 100
do
	-- Both doors, because Core resolves C_Item.GetItemInfo where the client
	-- carries it and the loose global where it does not, and the stub carries
	-- both.
	local real = _G.C_Item.GetItemInfo
	local function uncached(link)
		if type(link) == "string" and link:find("Light Leather", 1, true) then
			return nil
		end
		return real(link)
	end
	_G.C_Item.GetItemInfo, _G.GetItemInfo = uncached, uncached
	pass()
	check(took() == expect(1),
		("an unpriced slot was decided on the first pass, which took %s"):format(took()))
	check(ns.Loot.Waiting() == 1,
		("%d slots are waiting for a price and one should be"):format(ns.Loot.Waiting()))
	-- An answer about some other item asks again and the slot waits on.
	fire("GET_ITEM_INFO_RECEIVED", 1, true)
	check(took() == expect(1) and ns.Loot.Waiting() == 1,
		"an answer about another item decided the waiting slot")
	_G.C_Item.GetItemInfo, _G.GetItemInfo = real, real
end
fire("GET_ITEM_INFO_RECEIVED", ITEMS["Light Leather"].id, true)
check(took() == expect(1, 2),
	("the price arrived and the pass had taken %s"):format(took()))
check(ns.Loot.Waiting() == 0,
	("%d slots still waiting after the price arrived"):format(ns.Loot.Waiting()))

-- The corpse closing forgets what was waiting, and never deletes it.
loot.Set({ { quality = 0 }, { quality = 1, item = "Light Leather", count = 4 } })
do
	local real = _G.C_Item.GetItemInfo
	local function uncached(link)
		if type(link) == "string" and link:find("Light Leather", 1, true) then
			return nil
		end
		return real(link)
	end
	_G.C_Item.GetItemInfo, _G.GetItemInfo = uncached, uncached
	pass()
	_G.C_Item.GetItemInfo, _G.GetItemInfo = real, real
end
fire("LOOT_CLOSED")
fire("GET_ITEM_INFO_RECEIVED", ITEMS["Light Leather"].id, true)
check(took() == expect(1) and ns.Loot.Waiting() == 0,
	("a corpse that closed while a slot waited took %s afterwards"):format(took()))
loot.Set(SLOTS)

-- Nought is the rule off, and the reading says nothing about it.
nothing()
pass()
check(took() == expect(COINS, QUEST),
	("the price rule at nought took %s"):format(took()))
check(ns.Wanted.Describe() == "nothing by colour",
	("the price rule at nought reads as %q"):format(ns.Wanted.Describe()))

-- The two halves of the field on the settings page: what it shows and what it
-- reads back. Every shape somebody would type is a sum, and a word is not.
check(ns.CoinSpelt(2000) == "0g 20s 0c",
	("twenty silver spelt as %q"):format(ns.CoinSpelt(2000)))
check(ns.CoinSpelt(12345) == "1g 23s 45c",
	("one gold twenty three forty five spelt as %q"):format(ns.CoinSpelt(12345)))
check(ns.Uncoin("0g 20s 0c") == 2000 and ns.Uncoin("20s") == 2000
	and ns.Uncoin("1g5s") == 10500 and ns.Uncoin(" 1G 20S 3C ") == 12003
	and ns.Uncoin("45") == 45,
	"a sum of money typed into the field did not read back as the copper it is")
check(ns.Uncoin("twenty") == nil and ns.Uncoin("") == nil
	and ns.Uncoin("20s and a bit") == nil and ns.Uncoin(nil) == nil,
	"a line that is not a sum of money read back as one")

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
-- What it left, said out loud
--
-- The corpse is emptied before the loot window is drawn, so the one thing the
-- filter can never tell you is what it decided. A rule set too tight is a rule
-- nobody finds out about, and the loot feed is the only window that ever sees a
-- slot that went.
--
-- The seam is a link and not a slot. Comfort/Loot.lua writes the refusal down at
-- the moment it makes it and CHAT_MSG_LOOT arrives afterwards carrying the item
-- and no corpse at all, so what is asserted here is that the two halves meet.
-- 82-need.lua holds the answer's own order and its expiry, and 40-loot-feed.lua
-- holds what a row draws.
----------------------------------------------------------------------

local feed = ns.LootFeed.Stream():Feed()
local FEMUR = ("You receive loot: %s."):format(_G.WarriorKitItemLink("Splintered Femur"))

do
	nothing()
	pass()
	feed:Clear()
	fire("CHAT_MSG_LOOT", FEMUR)

	local entry = feed:At(0) or {}
	check(entry.ring == ns.UI.Color.trash,
		"a grey the filter refused off the corpse reached the feed with no trash ring")
	check(entry.note == nil,
		("the trash mark put %s in the row's own column"):format(tostring(entry.note)))
	-- Quiet on purpose. `look` is what holds a ring at full while the stripe
	-- beside it rests, and trash is the commonest answer of the three and the
	-- one nobody is looking for: a column of greys each wearing a bright ring is
	-- the feed back where it started.
	check(entry.look == nil, "the trash ring is held at full brightness")
end

-- And nothing at all while the filter is off, which is the state this addon
-- ships in. Take answers true on its first line, so no refusal is ever written
-- down and the greys reach the feed unmarked.
--
-- Past the memory first, because it outlives the switch by design: a refusal
-- made a moment ago was still a refusal, and the state being read here is a
-- corpse emptied with the filter already off.
do
	ns.dbc.lootFilter = false
	advance(91)
	pass()
	feed:Clear()
	fire("CHAT_MSG_LOOT", FEMUR)
	check((feed:At(0) or {}).ring == nil,
		"the filter switched off still marked a grey as trash")
	ns.dbc.lootFilter = true
	feed:Clear()
end

----------------------------------------------------------------------
-- And the chip that leaves it standing
--
-- Trash is one of the three reasons, so the chip over rows with a ring draws a
-- grey the filter would have left whatever the grey chip says. That is the
-- point of it and not a leak. This feed is the only place a rule set too tight
-- is ever found out, and the combination that finds it out is the greys off and
-- this chip on.
--
-- The chip is the ring on the entry rather than the question asked again, so
-- the assertion that carries the weight is the second one: a grey nobody has a
-- reason for goes off the column with its quality and stays off.
--
-- 40-loot-feed.lua holds the strip itself and the quest half of the same
-- override. What is here is the half that needs a corpse.
----------------------------------------------------------------------

do
	nothing()
	pass()
	feed:Clear()
	fire("CHAT_MSG_LOOT", FEMUR)

	ns.LootFeed.Light(0, false)
	feed:Chipped()
	check(feed:Shown() == 1,
		("the greys are off, the reason chip is on and the column draws %d rows")
			:format(feed:Shown()))

	ns.db.lootFeedReason = false
	feed:Chipped()
	check(feed:Shown() == 0, "the reason chip is off and a refused grey is still drawn")
	ns.db.lootFeedReason = true

	-- The same grey off a corpse the filter never looked at, which is the row
	-- this chip must not bring back.
	ns.dbc.lootFilter = false
	advance(91)
	pass()
	feed:Clear()
	fire("CHAT_MSG_LOOT", FEMUR)
	feed:Chipped()
	check(feed:Shown() == 0, "the reason chip drew a grey the filter never refused")

	ns.dbc.lootFilter = true
	ns.LootFeed.Light(0, true)
	feed:Chipped()
	feed:Clear()
end

----------------------------------------------------------------------
-- The reading
----------------------------------------------------------------------

nothing()
ns.dbc.lootFloor = 2
ns.dbc.lootCloth, ns.dbc.lootOre, ns.dbc.lootCrafted = true, true, true
check(ns.Wanted.Describe() == "greens and up, cloth, ore, and what my professions use",
	("the filter reads as %q"):format(ns.Wanted.Describe()))

ns.dbc.lootWorth = 2000
check(ns.Wanted.Describe() == "greens and up, cloth, ore, a grey or white worth 20s 0c, and what my professions use",
	("the filter with a price floor reads as %q"):format(ns.Wanted.Describe()))

----------------------------------------------------------------------
-- The switch the bag window presses
----------------------------------------------------------------------

-- One press is both settings, because a filter without the leftovers is a
-- corpse nobody can skin. Off puts both back, and Leftovers is told each
-- way, which is what its pending count going to nought proves.
ns.dbc.lootFilter, ns.dbc.lootDestroy = false, false
check(ns.Wanted.Toggle() == true and ns.dbc.lootFilter and ns.dbc.lootDestroy,
	"the first press did not switch the filter and the leftovers on together")
check(ns.Wanted.Running(), "the filter is on and Running says it is not")
check(ns.Wanted.Toggle() == false and not ns.dbc.lootFilter and not ns.dbc.lootDestroy,
	"the second press did not switch both off again")
check(not ns.Wanted.Running(), "the filter is off and Running says it is on")
ns.dbc.lootFilter = true

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
ns.dbc.lootWorth = 2000
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
