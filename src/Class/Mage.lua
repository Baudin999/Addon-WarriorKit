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
--
-- Three specs, and only one of them carries a bar plan. The plan below is
-- written off the frost mage somebody here plays; a fire or arcane plan written
-- from a talent calculator would fill your bars with a guess and take a backup
-- you then have to put back, which is the argument Class\Priest.lua makes for
-- refusing a plan altogether. So those two open no loadout page and the refusal
-- names the spec.
--
-- The cooldown lists and the debuff rows are written for all three, because
-- being wrong there costs an empty square rather than your bars.
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

--------------------------------------------------------------------------
-- The cooldowns every spec counts
--
-- Written once and named by all three, because none of the three is a fact
-- about a tree. 12051 Evocation, 45438 Ice Block with 27619 for the older
-- clients that filed it under that number, 66 Invisibility.
--------------------------------------------------------------------------

local EVOCATION = { key = "evocation", spells = { 12051 } }
local ICE_BLOCK = { key = "iceblock", spells = { 45438, 27619 } }
local INVISIBILITY = { key = "invisibility", spells = { 66 } }

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
	-- What the picker offers
	--
	-- Shared by all three specs. 12579 Winter's Chill, 116 Frostbolt, 122 Frost
	-- Nova, 120 Cone of Cold, 118 Polymorph, 22959 Fire Vulnerability, 133
	-- Fireball, 11366 Pyroblast, 31589 Slow.
	--------------------------------------------------------------------------
	suggested = { 12579, 116, 122, 120, 118, 22959, 133, 11366, 31589 },

	--------------------------------------------------------------------------
	-- The three specs
	--
	-- Tree order, which is the order the client counts them in and the order the
	-- resolver falls back on: 1 arcane, 2 fire, 3 frost.
	--
	-- Eight cooldowns used to sit on one list here and IsSpellKnown sorted them
	-- out, which worked and said nothing. A frost mage got Evocation, Ice Block,
	-- Cold Snap and Icy Veins because those are the four a frost mage has, not
	-- because anything in the addon knew what a frost mage is. Now it does, and
	-- the row is short by design rather than by accident.
	--
	-- The ids, all from Wowhead's Classic and TBC Classic databases: 12051
	-- Evocation, 45438 Ice Block, 11958 Cold Snap, 12472 Icy Veins, 12042 Arcane
	-- Power, 12043 Presence of Mind, 11129 Combustion, 66 Invisibility.
	--
	-- Ice Block carries two ids for the one entry. 45438 is what both of these
	-- clients answer for it and 27619 is the older number the same spell has been
	-- filed under, and the list takes whichever one this client knows.
	-- Invisibility is Burning Crusade only and never resolves on Era, which costs
	-- one square on one client and nothing else.
	--
	-- Each signature is a single rank talent nobody in another tree can have.
	-- Arcane carries two because Presence of Mind sits fifteen points up and
	-- Arcane Power at thirty, so a levelling arcane mage is named by the first of
	-- them long before the second.
	--------------------------------------------------------------------------
	specs = {
		{
			key = "arcane", label = "arcane", tree = 1,
			signature = { 12043, 12042 }, -- Presence of Mind, Arcane Power

			cooldowns = {
				{ key = "arcanepower", spells = { 12042 } },
				{ key = "presence", spells = { 12043 } },
				EVOCATION, ICE_BLOCK, INVISIBILITY,
			},

			-- 2139 Counterspell, 2136 Fire Blast, 122 Frost Nova. Arcane Explosion
			-- and the missiles have no cooldown of their own, so the squares that
			-- are worth drawing are the three that do.
			rotation = {
				{ key = "counterspell", spells = { 2139 } },
				{ key = "fireblast", spells = { 2136 } },
				{ key = "frostnova", spells = { 122 } },
			},

			-- 31589 Slow, 118 Polymorph, 122 Frost Nova.
			debuffs = { 31589, 118, 122 },
		},

		{
			key = "fire", label = "fire", tree = 2,
			signature = { 11129 }, -- Combustion

			cooldowns = {
				{ key = "combustion", spells = { 11129 } },
				EVOCATION, ICE_BLOCK, INVISIBILITY,
			},

			rotation = {
				{ key = "fireblast", spells = { 2136 } },
				{ key = "counterspell", spells = { 2139 } },
			},

			-- 22959 Fire Vulnerability, which is what Improved Scorch lands and is
			-- the one debuff a fire mage keeps up on purpose; 133 Fireball for its
			-- own burn, 11366 Pyroblast, 118 Polymorph.
			debuffs = { 22959, 133, 11366, 118 },
		},

		{
			key = "frost", label = "frost", tree = 3,
			signature = { 12472 }, -- Icy Veins

			cooldowns = {
				{ key = "icyveins", spells = { 12472 } },
				{ key = "coldsnap", spells = { 11958 } },
				EVOCATION, ICE_BLOCK, INVISIBILITY,
			},

			-- 122 Frost Nova, 120 Cone of Cold, 2136 Fire Blast, 2139 Counterspell.
			-- Frostbolt is the whole rotation and has no cooldown, which is exactly
			-- why these four are the ones worth a clock.
			rotation = {
				{ key = "frostnova", spells = { 122 } },
				{ key = "coneofcold", spells = { 120 } },
				{ key = "fireblast", spells = { 2136 } },
				{ key = "counterspell", spells = { 2139 } },
			},

			-- 12579 Winter's Chill, 116 Frostbolt for its own snare, 122 Frost Nova,
			-- 120 Cone of Cold, 118 Polymorph.
			debuffs = { 12579, 116, 122, 120, 118 },

			loadout = LOADOUT,
		},
	},
})
