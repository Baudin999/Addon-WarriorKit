local ADDON, ns = ...

local Spell, Macro = ns.Class.Spell, ns.Class.Macro

--------------------------------------------------------------------------
-- Mage
--
-- Three of the seven fields, and the four that are missing are the point of the
-- registry: a mage has no stances, no opener the charge button could cast, no
-- ability that opens on a dodge and nothing that casts inside a swing. Four
-- parts of the addon read those fields, find nothing, and are not built. No
-- secure button, no nameplate scan, no combat log handler, no page in the
-- options window.
--
-- Blink is deliberately not a charge. The charge button is three abilities that
-- close on a unit, aimed by the camera and swapped into a stance on the way;
-- Blink goes where you are facing and takes no target at all, so putting it
-- behind that machinery would be a button that ignores everything the machinery
-- is for.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- The bar plan
--
-- Frost, because that is what this one is levelled as, and one page because a
-- mage has nothing to page between. Same shape as any other plan: one row per
-- physical key, and the role is what the key is for.
--
-- index 1 to 12 is the physical slot, which on this install is E Q Z X C V F
-- 1 2 3 4 5.
--------------------------------------------------------------------------

local LOADOUT = {
	pages = { "main" },
	single = "main",

	macros = {
		-- Counterspell on whatever the cursor is over. An interrupt you have to
		-- target first is an interrupt you land late, which is the same argument
		-- the warrior plan makes for Shield Bash and Pummel.
		{
			name = "WK Counter",
			body = "#showtooltip\n/cast [@mouseover,harm,nodead] Counterspell; Counterspell",
		},

		-- Sheep on the mouseover, which is the one that keeps your target while
		-- you take the add out of the fight.
		{
			name = "WK Sheep",
			body = "#showtooltip\n/cast [@mouseover,harm,nodead] Polymorph; Polymorph",
		},

		-- Decurse on the mouseover, falling back to whoever is targeted and then
		-- to yourself.
		--
		-- Two casts, because the spell is not called the same thing on both of
		-- these clients: it is Remove Lesser Curse on 2.5.6 and 1.15.9, and
		-- Remove Curse from Wrath onwards. A line naming a spell you do not have
		-- does nothing at all, so writing both is how one macro covers both and
		-- keeps covering it if this install ever moves.
		{
			name = "WK Decurse",
			body = "#showtooltip"
				.. "\n/cast [@mouseover,help,nodead] Remove Lesser Curse; [help] Remove Lesser Curse; [@player] Remove Lesser Curse"
				.. "\n/cast [@mouseover,help,nodead] Remove Curse; [help] Remove Curse; [@player] Remove Curse",
		},
	},

	bar1 = {
		{ role = "nuke",        main = Spell("Frostbolt") },
		{ role = "instant",     main = Spell("Fire Blast") },
		{ role = "aoe",         main = Spell("Blizzard") },
		{ role = "aoe instant", main = Spell("Arcane Explosion") },
		{ role = "snare",       main = Spell("Cone of Cold") },
		{ role = "root",        main = Spell("Frost Nova") },
		{ role = "interrupt",   main = Macro("WK Counter") },
		{ role = "get out",     main = Spell("Blink") },
		{ role = "mitigation",  main = Spell("Ice Barrier") },
		{ role = "take it out", main = Macro("WK Sheep") },
		{ role = "burst",       main = Spell("Icy Veins") },
		{ role = "mana",        main = Spell("Evocation") },
	},

	bar2 = {
		Spell("Ice Block"),
		Spell("Cold Snap"),
		Spell("Mana Shield"),
		Spell("Arcane Intellect"),
		Spell("Ice Armor"),
		Spell("Mage Armor"),
		Macro("WK Decurse"),
		Spell("Slow Fall"),
		Spell("Conjure Water"),
		Spell("Conjure Food"),
		nil, -- a mana gem, whose name changes with its rank, so nothing guesses
		nil, -- healing potion, yours to drag, the addon will not guess an item
	},
}

ns.Class.Register("MAGE", {
	label = "mage",

	--------------------------------------------------------------------------
	-- What this class adds to the upkeep row
	--
	-- The armour spell, and it is exactly what this row is for: it is silent
	-- when it lapses, it is expensive while it is lapsed, and it comes off on
	-- every death and every dispel. Four spells and any one of them clears the
	-- square, because which armour you are running is a choice and this row does
	-- not have opinions about choices.
	--
	-- Rank 1 of each, because the match is by name and every rank shares one.
	-- 168 Frost Armor, 7302 Ice Armor, 6117 Mage Armor, 30482 Molten Armor. The
	-- last is Burning Crusade only and simply never resolves on Classic Era,
	-- which costs nothing: an id this client cannot name is left out of the
	-- table and the other three still answer.
	--------------------------------------------------------------------------
	upkeep = {
		{
			key = "armor", spells = { 168, 7302, 6117, 30482 },
			fixed = "no armour",
			word = "armor",
			switch = "tell me when no armour spell is up",
			hint = "You have no armour spell up. Frost, Ice, Mage and Molten all"
				.. " count, so any one of them clears this square, and all of them"
				.. " come off when you die.",
		},
	},

	--------------------------------------------------------------------------
	-- The long cooldowns
	--
	-- Eight, which is more than any other class file lists, and the row is
	-- nothing like eight squares long: IsSpellKnown decides which of them a
	-- character actually has, and no mage owns the arcane, fire and frost lists
	-- at once. A frost mage sees Evocation, Ice Block, Cold Snap and Icy Veins.
	-- A fire mage sees Evocation, Ice Block and Combustion. That is the whole
	-- reason the list is spells rather than a spec.
	--
	-- The ids, all from Wowhead's Classic and TBC Classic databases: 12051
	-- Evocation, 45438 Ice Block, 11958 Cold Snap, 12472 Icy Veins, 12042 Arcane
	-- Power, 12043 Presence of Mind, 11129 Combustion, 66 Invisibility.
	--
	-- Ice Block carries two ids for the one entry. 45438 is what both of these
	-- clients answer for it and 27619 is the older number the same spell has
	-- been filed under, and the list takes whichever one this client knows.
	-- Every other entry is a single unranked spell.
	--
	-- Invisibility is Burning Crusade only and never resolves on Era, which
	-- costs one square on one client and nothing else.
	--------------------------------------------------------------------------
	cooldowns = {
		{ key = "evocation", spells = { 12051 } },
		{ key = "iceblock", spells = { 45438, 27619 } },
		{ key = "coldsnap", spells = { 11958 } },
		{ key = "icyveins", spells = { 12472 } },
		{ key = "arcanepower", spells = { 12042 } },
		{ key = "presence", spells = { 12043 } },
		{ key = "combustion", spells = { 11129 } },
		{ key = "invisibility", spells = { 66 } },
	},

	loadout = LOADOUT,
})
