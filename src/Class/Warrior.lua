local ADDON, ns = ...

local Spell, Macro = ns.Class.Spell, ns.Class.Macro

--------------------------------------------------------------------------
-- Warrior
--
-- Everything this addon knows about a warrior, and the only file in it that
-- names a warrior spell. Eight fields, each read by exactly one part:
--
--   forms      Core\Stance.lua, and through it the charge macro
--   charge     Charge\Charge.lua
--   reactive   Buttons\Reaction.lua
--   requires   Buttons\Requires.lua
--   swing      Swing\Slam.lua
--   upkeep     Buffs\Upkeep.lua, added to the row everybody gets
--   cooldowns  Cooldowns\Cooldowns.lua, the row of long ones
--   loadout    Buttons\Layout.lua
--
-- No frames, no events, no drawing. A class file is facts.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- The bar plan
--
-- The whole design of the loadout is this table. Changing what a key does is
-- editing data, not code.
--
-- Bar 1 pages by stance, so it is written as one row per physical key with a
-- cell per page: same finger, same job, in every stance. The role is what the
-- key is for and it is what makes the three cells a row rather than three
-- unrelated spells. Bar 2 is the shift layer and does not page, which is the
-- point of it.
--
-- index 1 to 12 is the physical slot, which on this install is E Q Z X C V F
-- 1 2 3 4 5.
--------------------------------------------------------------------------

local LOADOUT = {
	-- The order the `stance:` macro conditional counts in, which is the order
	-- forms below is written in. The first is the page a client that will not
	-- page bar 1 gets, and it is the tank set because that is the one worth
	-- having when there is only one.
	pages = { "battle", "defensive", "berserker" },
	single = "defensive",

	-- Macros the plan needs. Created per character, prefixed so Restore finds
	-- exactly what was made and deletes nothing else.
	macros = {
		{
			name = "WK Taunt",
			body = "#showtooltip\n/cast [stance:1] Mocking Blow; [@mouseover,harm,nodead] Taunt; Taunt",
		},
		{
			name = "WK Bash",
			body = "#showtooltip\n/cast [@mouseover,harm,nodead] Shield Bash; Shield Bash",
		},
		{
			name = "WK Pummel",
			body = "#showtooltip\n/cast [@mouseover,harm,nodead] Pummel; Pummel",
		},
		{
			name = "WK Sunder",
			body = "#showtooltip\n/startattack\n/cast [@mouseover,harm,nodead] Sunder Armor; Sunder Armor",
		},
		{
			name = "WK Strike",
			body = "#showtooltip\n/startattack\n/cast Heroic Strike",
		},
	},

	bar1 = {
		{ role = "rage dump",    battle = Macro("WK Strike"),        defensive = Macro("WK Strike"),          berserker = Macro("WK Strike") },
		{ role = "aoe dump",     battle = Spell("Cleave"),           defensive = Spell("Cleave"),             berserker = Spell("Cleave") },
		{ role = "builder",      battle = Spell("Rend"),             defensive = Macro("WK Sunder"),          berserker = Spell("Whirlwind") },
		{ role = "proc window",  battle = Spell("Overpower"),        defensive = Spell("Revenge"),            berserker = Spell("Intercept") },
		{ role = "aoe hit",      battle = Spell("Thunder Clap"),     defensive = Spell("Thunder Clap"),       berserker = Spell("Berserker Rage") },
		{ role = "snare",        battle = Spell("Hamstring"),        defensive = Spell("Hamstring"),          berserker = Spell("Hamstring") },
		{ role = "interrupt",    battle = Macro("WK Bash"),          defensive = Macro("WK Bash"),            berserker = Macro("WK Pummel") },
		{ role = "execute",      battle = Spell("Execute"),          defensive = Spell("Execute"),            berserker = Spell("Execute") },
		{ role = "rage",         battle = Spell("Bloodrage"),        defensive = Spell("Bloodrage"),          berserker = Spell("Bloodrage") },
		{ role = "pull it back", battle = Macro("WK Taunt"),         defensive = Macro("WK Taunt"),           berserker = Spell("Challenging Shout") },
		{ role = "mitigation",   battle = Spell("Spell Reflection"), defensive = Spell("Shield Block"),       berserker = Spell("Recklessness") },
		{ role = "shout",        battle = Spell("Battle Shout"),     defensive = Spell("Demoralizing Shout"), berserker = Spell("Battle Shout") },
	},

	bar2 = {
		Spell("Shield Wall"),
		Spell("Last Stand"),
		Spell("Battle Shout"),
		Spell("Demoralizing Shout"),
		Spell("Commanding Shout"),
		Spell("Intimidating Shout"),
		Spell("Disarm"),
		nil, -- healing potion, yours to drag, the addon will not guess an item
		nil, -- healthstone or bandage, same
		Spell("Battle Stance"),
		Spell("Defensive Stance"),
		Spell("Berserker Stance"),
	},
}

ns.Class.Register("WARRIOR", {
	label = "warrior",

	--------------------------------------------------------------------------
	-- The three stances
	--
	-- The index is the number the `stance:` macro conditional counts in, so the
	-- order here is the order the generated macros are written against, and it
	-- is the order LOADOUT.pages is in.
	--------------------------------------------------------------------------
	forms = { 2457, 71, 2458 }, -- 1 Battle, 2 Defensive, 3 Berserker

	--------------------------------------------------------------------------
	-- The three openers the charge button casts
	--
	-- Which one applies is a function of combat and what the cursor is over.
	-- Every rank is listed because Known asks IsSpellKnown per rank, and rank
	-- one leads because the name and the icon are taken off it.
	--------------------------------------------------------------------------
	charge = {
		charge = {
			ranks = { 100, 6178, 11578 },
			stance = 1,
			hostile = true,
			inCombat = false, -- Charge only works out of combat
		},
		intervene = {
			ranks = { 3411 },
			stance = 2,
			hostile = false,
			inCombat = true,
		},
		intercept = {
			ranks = { 20252, 20616, 20617 },
			stance = 3,
			hostile = true,
			inCombat = true,
		},
	},

	--------------------------------------------------------------------------
	-- The two abilities the fight hands you
	--
	-- Overpower opens when your target dodges you. Revenge is the same
	-- mechanism from the other side and opens when you block, dodge or parry.
	-- Nothing else a warrior owns works this way, and `on` names which of the
	-- two triggers Buttons\Reaction.lua watches for each.
	--
	-- Rank 1 of each. Every other rank is matched by name against these, so
	-- this carries two ids rather than a rank list that goes stale at the next
	-- trainer visit.
	--
	-- Five seconds, and the sources do not agree. Every player-facing figure
	-- says five: the Vanilla wiki gives Overpower a "5 second period", every
	-- Classic warrior guide says the same, and both abilities carry a five
	-- second cooldown, so a warrior who presses on every window presses exactly
	-- on the cooldown. Against that, MaNGOS and TrinityCore both hold
	-- REACTIVE_TIMER_START at 4000 milliseconds.
	--
	-- Five is the number here because the two errors do not cost the same.
	-- Running a second long means a square says pressable when it is not, which
	-- costs a glance. Running a second short means the square goes grey while a
	-- free five rage attack is still sitting there, which costs the attack. A
	-- bar exists to show you the press, so it errs towards showing it. Settling
	-- it needs the live client and a stopwatch, and the README lists it under
	-- what has never been measured.
	--------------------------------------------------------------------------
	reactive = {
		window = 5,
		{ key = "overpower", spell = 7384, on = "dodged" },
		{ key = "revenge",   spell = 6572, on = "defended" },
	},

	--------------------------------------------------------------------------
	-- What the fight has to have done before the press lands
	--
	-- Read by Buttons\Requires.lua, which owns what a condition means and knows
	-- none of the abilities. One ability on a warrior meets the bar for being
	-- here, and the bar is that the client has no opinion and the answer is a
	-- fact rather than a guess.
	--
	-- Execute, rank 1, because every rank is called Execute and is matched by
	-- name against this one. Twenty percent is the number in its own tooltip on
	-- both of these clients and it is the whole rule: nothing about rage, nothing
	-- about stance and nothing about talents moves it. Without this the square
	-- drew ready from the pull, which is a bar shouting the one thing it should
	-- stay quiet about for four fifths of a fight.
	--
	-- Nothing else a warrior owns belongs here yet. Overpower and Revenge are
	-- next door in `reactive` because a window that arrives down the combat log
	-- is a clock and not a reading. Pummel and Shield Bash look like candidates
	-- and are deliberately absent: whether either may be pressed at a target
	-- that is not casting differs between these two clients and nobody here has
	-- measured it, and a square greyed on a rule the addon guessed at is worse
	-- than one that says nothing.
	--------------------------------------------------------------------------
	requires = {
		{ spell = 5308, below = 20 }, -- Execute, rank 1
	},

	--------------------------------------------------------------------------
	-- The cast that lives inside a swing
	--
	-- Slam, rank one. Only the name is taken off it and every rank shares that
	-- name, so one id covers a warrior at level 30 and one at 70.
	--
	-- perPoint is what one point of Improved Slam takes off the cast, in
	-- seconds. Warcraft wiki's rank table gives 0.1 per point across five
	-- points for Classic and for Burning Crusade, and dates the two point, 0.5
	-- per point version to patch 3.0.2, which is one expansion past both of
	-- these clients. Wowhead's TBC entry for spell 12330 reads -1000
	-- milliseconds, which does not agree, and no API will settle it: a talent's
	-- effect lives in its tooltip text and parsing that is a worse dependency
	-- than this number. It is a seed for the first cast and nothing more, and
	-- the measurement replaces it the moment one is cast.
	--------------------------------------------------------------------------
	swing = {
		cast = 1464, -- Slam, rank 1
		perPoint = 0.1,
	},

	--------------------------------------------------------------------------
	-- What this class adds to the upkeep row
	--
	-- Battle Shout, rank 1, and it is the one class ability on a row that is
	-- otherwise about things anybody standing in melee wants. Rank 1 covers all
	-- eight because the match is by name.
	--
	-- 6673 is Battle Shout rank 1: Wowhead's TBC database gives it as 10 rage,
	-- +15 attack power for 2 minutes, which is rank 1's own number. Rank 3 of
	-- the same spell, 6192, is in this install's Details saved variables off a
	-- live 2.5.6 session, so the ranked chain is real on this client.
	--------------------------------------------------------------------------
	upkeep = {
		{
			key = "shout", spell = 6673,
			fixed = "battle shout",
			word = "shout",
			switch = "tell me when Battle Shout has lapsed",
			hint = "Battle Shout has lapsed. Any rank counts and somebody else's shout"
				.. " counts as yours, because the attack power is on you either way.",
		},
	},

	--------------------------------------------------------------------------
	-- The long cooldowns
	--
	-- The four a warrior spends a fight counting in their head, and the reason
	-- the row exists. Every one of them is minutes long, none of them is on the
	-- global, and the bar square for each says only "not now" while what you
	-- want to know is how much longer.
	--
	-- Rank one of each and every one of them a single rank, because none of the
	-- four was ever ranked. The list is walked with IsSpellKnown, so a warrior
	-- who has not spent the talent point sees no square rather than a square
	-- for something they cannot cast: Death Wish and Last Stand are talents,
	-- Recklessness and Shield Wall are trained, and a levelling warrior below
	-- either trainer gets a shorter row that grows on its own.
	--
	-- The ids: 12292 Death Wish, 1719 Recklessness, 871 Shield Wall, 12975 Last
	-- Stand. All four are on Wowhead's TBC Classic database at those ids with
	-- the cooldowns the row draws, and all four are the same id on Era.
	--
	-- What is deliberately not here. Bloodrage and Sweeping Strikes are on the
	-- bar plan above, they come back inside a minute, and a row of things that
	-- are nearly always ready is furniture. Retaliation is thirty minutes on
	-- these clients, which is not a fight cooldown, it is a wing cooldown.
	-- Berserker Rage sits on bar 1 where you press it as a snare break rather
	-- than on a timer.
	--------------------------------------------------------------------------
	cooldowns = {
		{ key = "deathwish", spells = { 12292 } },
		{ key = "recklessness", spells = { 1719 } },
		{ key = "shieldwall", spells = { 871 } },
		{ key = "laststand", spells = { 12975 } },
	},

	loadout = LOADOUT,
})
