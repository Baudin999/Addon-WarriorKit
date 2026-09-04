local ADDON, ns = ...

local Spell, Macro = ns.Class.Spell, ns.Class.Macro

--------------------------------------------------------------------------
-- Shaman
--
-- Three of the seven fields, for the same reason the mage file has three:
-- nothing here opens on a dodge, nothing casts inside a swing, and nothing
-- closes on a unit the way the charge button's three do.
--
-- Ghost Wolf is deliberately not a form. GetShapeshiftForm counts it, so the
-- client would answer 1 for a shaman running between mobs, but `forms` exists
-- for two things and Ghost Wolf serves neither: bar 1 does not page into it,
-- because the bonus bar offset stays 0, and a weapon set bound to it would be a
-- loadout you can only press while you are a wolf and cannot swing anything.
-- Listing it would seed a loadout row nobody wants and offer a stance page that
-- does not exist.
--
-- The weapon imbue is not here either, and that is the shipped row doing its
-- job. A bare main hand is already the first entry on the buff nag, and it says
-- so in its own hint: a sharpening stone, an oil and a shaman's imbue are the
-- same fact about the same slot, read out of the same call.
--
-- Three specs, and the split between what this file says and what each of them
-- says is worth stating. The shield square on the buff row is here, because all
-- three want one and none of them cares which. Everything a spec disagrees
-- about is written inside it: the four cooldowns worth counting, the debuffs
-- worth a square above a mob, and the bar plan.
--
-- And one field no other class file writes yet. `standing` is the four totem
-- slots, which is a fact about being a shaman in the way the three stances are
-- a fact about being a warrior, and it is the first thing in this addon that
-- both classes will fill in. Standing\Standing.lua reads it and knows the word
-- totem nowhere.
--
-- The bar plan lives inside enhancement and nowhere else. That is the same
-- decision Class\Priest.lua takes for the whole class: the plan below is
-- written off a character somebody plays, and an elemental plan written from a
-- talent calculator would fill your bars with a guess and take a backup you
-- then have to put back. So an elemental shaman opens no loadout page and the
-- refusal names the spec. Somebody who levels one writes the plan.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- The bar plan
--
-- Enhancement, because that is what this one is levelled as, and one page: a
-- shaman has nothing to page between.
--
-- Bar 2 is nine totems and three spells, which is what a shift layer is for on
-- this class. Nothing on these clients drops a set in one press, so each is its
-- own square and they sit together where the fingers can find them.
--
-- index 1 to 12 is the physical slot, which on this install is E Q Z X C V F
-- 1 2 3 4 5.
--------------------------------------------------------------------------

local LOADOUT = {
	pages = { "main" },
	single = "main",

	macros = {
		-- Earth Shock is the interrupt and the filler at once, so it takes the
		-- mouseover the way the warrior plan's Shield Bash does, and starts the
		-- swing the way its Sunder Armor does.
		{
			name = "WK Shock",
			body = "#showtooltip\n/startattack\n/cast [@mouseover,harm,nodead] Earth Shock; Earth Shock",
		},

		{
			name = "WK Purge",
			body = "#showtooltip\n/cast [@mouseover,harm,nodead] Purge; Purge",
		},

		-- A heal on the mouseover, then on whoever is targeted, then on you. A
		-- shaman in melee heals without dropping the mob they are hitting, and
		-- the fallback to yourself is what makes it one key rather than two.
		{
			name = "WK Wave",
			body = "#showtooltip"
				.. "\n/cast [@mouseover,help,nodead] Healing Wave; [help] Healing Wave; [@player] Healing Wave",
		},

		-- One key for the raid cooldown whichever side you are on. Bloodlust is
		-- Horde and Heroism is Alliance, no character has both, and a line naming
		-- a spell you do not have does nothing, so the two lines are one button.
		{
			name = "WK Lust",
			body = "#showtooltip\n/cast Bloodlust\n/cast Heroism",
		},
	},

	bar1 = {
		{ role = "main strike", main = Spell("Stormstrike") },
		{ role = "interrupt",   main = Macro("WK Shock") },
		{ role = "dot",         main = Spell("Flame Shock") },
		{ role = "snare",       main = Spell("Frost Shock") },
		{ role = "aoe",         main = Spell("Magma Totem") },
		{ role = "burst",       main = Macro("WK Lust") },
		{ role = "take it off", main = Macro("WK Purge") },
		{ role = "heal",        main = Macro("WK Wave") },
		{ role = "shield",      main = Spell("Lightning Shield") },
		{ role = "mitigation",  main = Spell("Shamanistic Rage") },
		{ role = "get there",   main = Spell("Ghost Wolf") },
		{ role = "imbue",       main = Spell("Windfury Weapon") },
	},

	bar2 = {
		Spell("Searing Totem"),
		Spell("Fire Nova Totem"),
		Spell("Strength of Earth Totem"),
		Spell("Stoneskin Totem"),
		Spell("Windfury Totem"),
		Spell("Grace of Air Totem"),
		Spell("Mana Spring Totem"),
		Spell("Tremor Totem"),
		Spell("Grounding Totem"),
		Spell("Water Shield"),
		Spell("Flametongue Weapon"),
		Spell("Chain Lightning"),
	},
}

--------------------------------------------------------------------------
-- The four slots
--
-- What Standing\Standing.lua draws a square for, and the whole of what this
-- addon knows about a totem.
--
-- `index` is the client's own slot number and not ours to choose: the constants
-- in the 2.5.6 interface are FIRE_TOTEM_SLOT 1, EARTH_TOTEM_SLOT 2,
-- WATER_TOTEM_SLOT 3 and AIR_TOTEM_SLOT 4, and GetTotemInfo counts in those.
--
-- The order they are written in is the order they are drawn in, and it is
-- Blizzard's rather than the numbers': SHAMAN_TOTEM_PRIORITIES is earth, fire,
-- water, air. A shaman has read their totems in that order for twenty years and
-- an addon that renumbered them would be teaching a second order for the same
-- four things. It is also the order that reads best, because earth and fire are
-- the two you drop every pull and they land where the eye starts.
--
-- The colour is the only thing an empty slot has to say. It is here rather than
-- in the row because the row has no opinion about elements: a stance plan will
-- hand it three different colours and neither list belongs to a file that draws
-- squares. Four hues far enough apart to be told apart in one pixel of hairline
-- over a dark floor.
--
-- `kind` names the reader. There is one today and the shape of the field is the
-- point: a warrior's three stances are the same question with a different
-- source, and they are a second reader and a second table like this one rather
-- than a second part of the addon.
--------------------------------------------------------------------------

local STANDING = {
	kind = "totem",
	word = "totems",
	one = "totem",

	slots = {
		{ key = "earth", label = "earth", index = 2, color = { 0.55, 0.42, 0.24 } },
		{ key = "fire",  label = "fire",  index = 1, color = { 0.88, 0.35, 0.14 } },
		{ key = "water", label = "water", index = 3, color = { 0.24, 0.58, 0.88 } },
		{ key = "air",   label = "air",   index = 4, color = { 0.66, 0.62, 0.92 } },
	},
}

--------------------------------------------------------------------------
-- The cooldowns every spec counts
--
-- Written once and named by all three, because these three are facts about
-- being a shaman rather than about which tree you spent your points in.
--
-- The ids, from Wowhead's Classic and TBC Classic databases: 2825 Bloodlust,
-- 32182 Heroism, 2894 Fire Elemental Totem, 2062 Earth Elemental Totem. Three
-- of the four are Burning Crusade only, so an Era shaman sees the one that was
-- always there and nothing is wrong: an id this client cannot name draws no
-- square.
--
-- Bloodlust and Heroism are one entry with two ids, because they are the same
-- button on two factions and a shaman has exactly one of them. The entry takes
-- whichever this character knows, which is what the two id form is for.
--------------------------------------------------------------------------

local LUST = { key = "lust", spells = { 2825, 32182 } }
local FIRE_ELEMENTAL = { key = "fireelemental", spells = { 2894 } }
local EARTH_ELEMENTAL = { key = "earthelemental", spells = { 2062 } }

ns.Class.Register("SHAMAN", {
	label = "shaman",

	-- All three specs, because all three drop totems and none of them cares
	-- which. Which totems you have out is a fight question rather than a tree
	-- question, so nothing inside `specs` writes this again.
	standing = STANDING,

	--------------------------------------------------------------------------
	-- What this class adds to the upkeep row
	--
	-- The shield, and any one of the three clears it. Which shield you are
	-- running is a spec and a fight question: enhancement takes Water Shield for
	-- the mana and Lightning Shield when the damage is worth more, and both are
	-- right. What is never right is standing there with none, which is what this
	-- square is for.
	--
	-- Rank 1 of each, matched by name. 324 Lightning Shield, 24398 Water Shield,
	-- 974 Earth Shield. The last two are Burning Crusade and never resolve on
	-- Classic Era, which costs nothing: an id this client cannot name is left out
	-- of the table and Lightning Shield still answers.
	--------------------------------------------------------------------------
	upkeep = {
		{
			key = "shield", spells = { 324, 24398, 974 },
			fixed = "no shield",
			word = "shield",
			switch = "tell me when no shield is up",
			hint = "You have no shield up. Lightning, Water and Earth all count, so"
				.. " any one of them clears this square, and all of them are spent"
				.. " down to nothing without saying so.",
		},
	},

	--------------------------------------------------------------------------
	-- What the picker offers
	--
	-- Shared by all three specs, because the shortlist is what you may add
	-- rather than what you are handed. 17364 Stormstrike, 8050 Flame Shock,
	-- 8056 Frost Shock, 8042 Earth Shock, 421 Chain Lightning.
	--------------------------------------------------------------------------
	suggested = { 17364, 8050, 8056, 8042, 421 },

	--------------------------------------------------------------------------
	-- The three specs
	--
	-- Tree order, which is the order the client counts them in and the order the
	-- resolver falls back on: 1 elemental, 2 enhancement, 3 restoration.
	--
	-- Each signature is a talent with one rank at the foot of one tree, so
	-- IsSpellKnown settles the question outright for anyone who has reached it and
	-- no rank table has to be kept up to date. All three ids are already on the
	-- cooldown lists below, which is not a coincidence: a forty one point talent
	-- is both the thing that names your spec and the thing you count in your head.
	--
	-- Bloodlust and the two elementals are shared, so they are written once above
	-- and named by each spec. Sharing the table is safe because a character has
	-- one spec and the row resolves the entry it is handed.
	--------------------------------------------------------------------------
	specs = {
		{
			key = "elemental", label = "elemental", tree = 1,
			signature = { 16166 }, -- Elemental Mastery

			cooldowns = {
				{ key = "mastery", spells = { 16166 } },
				LUST, FIRE_ELEMENTAL, EARTH_ELEMENTAL,
			},

			-- 421 Chain Lightning, 8042 Earth Shock, 8050 Flame Shock. The three
			-- shocks share one cooldown between them, so only the two an elemental
			-- shaman actually presses are here and the third would be a second
			-- square counting the same clock.
			rotation = {
				{ key = "chainlightning", spells = { 421 } },
				{ key = "earthshock", spells = { 8042 } },
				{ key = "flameshock", spells = { 8050 } },
			},

			debuffs = { 8050, 8056, 8042 },
		},

		{
			key = "enhancement", label = "enhancement", tree = 2,
			signature = { 30823 }, -- Shamanistic Rage

			cooldowns = {
				{ key = "rage", spells = { 30823 } },
				LUST, FIRE_ELEMENTAL, EARTH_ELEMENTAL,
			},

			-- 17364 Stormstrike, 8042 Earth Shock, 8050 Flame Shock. Stormstrike is
			-- the ten seconds the whole rotation is built around and the client says
			-- nothing about it that a bar square does not already say badly.
			rotation = {
				{ key = "stormstrike", spells = { 17364 } },
				{ key = "earthshock", spells = { 8042 } },
				{ key = "flameshock", spells = { 8050 } },
			},

			-- The Stormstrike debuff is the one worth a square: it is what the next
			-- two nature hits are worth double for, it falls off silently, and
			-- somebody else's does not count.
			debuffs = { 17364, 8050, 8056, 8042 },

			loadout = LOADOUT,
		},

		{
			key = "restoration", label = "restoration", tree = 3,
			signature = { 16188 }, -- Nature's Swiftness

			cooldowns = {
				{ key = "swiftness", spells = { 16188 } },
				LUST, FIRE_ELEMENTAL, EARTH_ELEMENTAL,
			},

			rotation = {
				{ key = "earthshock", spells = { 8042 } },
			},

			debuffs = { 8042, 8056 },
		},
	},
})
