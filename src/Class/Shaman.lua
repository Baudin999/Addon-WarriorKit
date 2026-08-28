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

ns.Class.Register("SHAMAN", {
	label = "shaman",

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
	-- The long cooldowns
	--
	-- Six, and four of them are Burning Crusade only, so an Era shaman sees the
	-- two that were always there and nothing is wrong. IsSpellKnown decides the
	-- rest: Elemental Mastery and Nature's Swiftness are talents at the foot of
	-- two different trees and nobody has both.
	--
	-- The ids, from Wowhead's Classic and TBC Classic databases: 2825 Bloodlust,
	-- 32182 Heroism, 30823 Shamanistic Rage, 16166 Elemental Mastery, 16188
	-- Nature's Swiftness, 2894 Fire Elemental Totem, 2062 Earth Elemental Totem.
	--
	-- Bloodlust and Heroism are one entry with two ids, because they are the
	-- same button on two factions and a shaman has exactly one of them. The
	-- entry takes whichever this character knows, which is what the two id form
	-- is for.
	--
	-- Mana Tide Totem is not here. It is a restoration talent, this shaman is
	-- enhancement, and a row written for a spec nobody plays is a row written
	-- from a talent calculator. Add it the day somebody heals on one.
	--------------------------------------------------------------------------
	cooldowns = {
		{ key = "lust", spells = { 2825, 32182 } },
		{ key = "rage", spells = { 30823 } },
		{ key = "mastery", spells = { 16166 } },
		{ key = "swiftness", spells = { 16188 } },
		{ key = "fireelemental", spells = { 2894 } },
		{ key = "earthelemental", spells = { 2062 } },
	},

	loadout = LOADOUT,
})
