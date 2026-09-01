local ADDON, ns = ...

local Spell, Macro = ns.Class.Spell, ns.Class.Macro

--------------------------------------------------------------------------
-- Warrior
--
-- Everything this addon knows about a warrior, and the only file in it that
-- names a warrior spell. Nine fields, each read by exactly one part:
--
--   forms      Core\Stance.lua, and through it the charge macro
--   charge     Charge\Charge.lua
--   reactive   Buttons\Reaction.lua
--   requires   Buttons\Requires.lua
--   swing      Swing\Slam.lua
--   upkeep     Buffs\Upkeep.lua, added to the row everybody gets
--   rotation   Cooldowns\Cooldowns.lua, the big squares on the top line
--   cooldowns  Cooldowns\Cooldowns.lua, the small ones docked under them
--   debuffs    UnitFrames\EnemyBars.lua, the row above a mob's bar
--   loadout    Buttons\Layout.lua
--
-- Six of them are the same whatever you have spent your points on and are
-- written here. Three are not and are written inside `specs` at the foot of the
-- file, which Class\Spec.lua picks between.
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
	-- What the picker offers
	--
	-- Every debuff a warrior puts on a mob on these two clients, shared by all
	-- three specs, because the shortlist is what you may add rather than what
	-- you are handed. A fury warrior who wants Sunder for one fight finds it
	-- here instead of typing a number.
	--
	-- Every ID is the ID of the aura that lands, never the spell or talent that
	-- applies it. 7922 is the Charge stun and not Charge; 20253 is the Intercept
	-- stun and not Intercept; 12721 is the Deep Wound bleed and not the Deep
	-- Wounds talent, which is the one that shipped wrong and stayed dark.
	--------------------------------------------------------------------------
	suggested = {
		7386,  -- Sunder Armor
		1160,  -- Demoralizing Shout
		6343,  -- Thunder Clap
		772,   -- Rend
		12721, -- Deep Wound, the bleed the Deep Wounds talent applies
		12294, -- Mortal Strike
		1715,  -- Hamstring
		12323, -- Piercing Howl
		355,   -- Taunt
		694,   -- Mocking Blow
		1161,  -- Challenging Shout
		676,   -- Disarm
		12809, -- Concussion Blow
		5246,  -- Intimidating Shout
		7922,  -- Charge Stun, not Charge
		20253, -- Intercept Stun, not Intercept
	},

	--------------------------------------------------------------------------
	-- The three specs
	--
	-- Tree order, which is the order the client counts them in and the order the
	-- resolver falls back on: 1 arms, 2 fury, 3 protection.
	--
	-- What is not written again inside them is the point of the shape. All three
	-- stand in the same three stances, cast the same three openers, open on the
	-- same dodge, wait on the same twenty percent, put the same Slam inside the
	-- same swing and want the same shout on the upkeep row. Those six fields are
	-- above and stay there. What a warrior spec actually disagrees about is which
	-- long cooldowns are worth counting, which short ones are worth a clock, and
	-- which debuffs are worth a square, and that is what each of these three says.
	--
	-- The bar plan is above as well, and deliberately. It pages by stance rather
	-- than by tree, every cell of it is a spell all three own, and it is the plan
	-- the warrior on this account presses. A per spec plan would be three copies
	-- of one table differing in two cells.
	--
	-- Arms carries no signature and does not need one. Death Wish and Last Stand
	-- are single rank talents at the foot of the other two trees, so a warrior who
	-- has neither and has spent points somewhere is named by their tree, and arms
	-- is what that answers. Mortal Strike would be the obvious signature and has
	-- six ranks, which is a rank table that goes stale at the next trainer visit.
	--
	-- The long ids: 12292 Death Wish, 1719 Recklessness, 871 Shield Wall, 12975
	-- Last Stand. All four are on Wowhead's TBC Classic database at those ids with
	-- the cooldowns the row draws, and all four are the same id on Era. None of
	-- the four was ever ranked.
	--
	-- What is deliberately not on any of the three. Retaliation is thirty minutes
	-- on these clients, which is not a fight cooldown, it is a wing cooldown.
	-- Bloodrage comes back inside a minute and is on the rotation layer instead,
	-- which is where a thing that is nearly always ready belongs.
	--------------------------------------------------------------------------
	specs = {
		{
			key = "arms", label = "arms", tree = 1,

			cooldowns = {
				{ key = "recklessness", spells = { 1719 } },
				{ key = "shieldwall", spells = { 871 } },
			},

			-- 100 Charge, 12294 Mortal Strike, 7384 Overpower, 12328 Sweeping
			-- Strikes, 6343 Thunder Clap, 18499 Berserker Rage. Rank 1 of each,
			-- because every rank stays in the spellbook on these clients and every
			-- rank of one ability shares one cooldown, so the first id answers for
			-- the sixth.
			--
			-- Charge leads all three lists and is on this layer despite `charge`
			-- above building a button for it. The button is where you press it and
			-- the row is how long until you can, which is the same split Overpower
			-- already sits on either side of. A fifteen second cooldown you open
			-- every pull with is a rotation cooldown whatever else the addon does
			-- with it.
			--
			-- Overpower is on this layer as well as in `reactive` above, and the two
			-- say different things: the reaction window is whether the fight has
			-- opened it, and this is whether the five second cooldown has run out.
			-- A window that opens on a square still counting down is a press you do
			-- not get.
			rotation = {
				{ key = "charge", spells = { 100 } },
				{ key = "mortalstrike", spells = { 12294 } },
				{ key = "overpower", spells = { 7384 } },
				{ key = "sweeping", spells = { 12328 } },
				{ key = "thunderclap", spells = { 6343 } },
				{ key = "berserkerrage", spells = { 18499 } },
			},

			-- 772 Rend, 12721 Deep Wound, 12294 Mortal Strike, 6343 Thunder Clap,
			-- 1160 Demoralizing Shout. The bleeds and the strike that decide whether
			-- the pull is going well.
			--
			-- 12721 and not 12162. The talent is called Deep Wounds and the aura it
			-- lands is called Deep Wound, the row matches on the name, and one letter
			-- was a square that stayed dark through every fight. See REPLACED in
			-- UnitFrames\EnemyBars.lua, which shuts the same door on a number typed
			-- in by hand.
			debuffs = { 772, 12721, 12294, 6343, 1160 },
		},

		{
			key = "fury", label = "fury", tree = 2,
			signature = { 12292 }, -- Death Wish

			cooldowns = {
				{ key = "deathwish", spells = { 12292 } },
				{ key = "recklessness", spells = { 1719 } },
				{ key = "shieldwall", spells = { 871 } },
			},

			-- 100 Charge, 23881 Bloodthirst, 1680 Whirlwind, 18499 Berserker Rage,
			-- 6343 Thunder Clap.
			rotation = {
				{ key = "charge", spells = { 100 } },
				{ key = "bloodthirst", spells = { 23881 } },
				{ key = "whirlwind", spells = { 1680 } },
				{ key = "berserkerrage", spells = { 18499 } },
				{ key = "thunderclap", spells = { 6343 } },
			},

			-- No Rend and no Deep Wound, because a fury warrior applies neither, and
			-- two squares that never come on are two squares of the row spent saying
			-- nothing. 1160 Demoralizing Shout, 6343 Thunder Clap, 1715 Hamstring.
			debuffs = { 1160, 6343, 1715 },
		},

		{
			key = "protection", label = "protection", tree = 3,
			signature = { 12975 }, -- Last Stand

			cooldowns = {
				{ key = "shieldwall", spells = { 871 } },
				{ key = "laststand", spells = { 12975 } },
				{ key = "recklessness", spells = { 1719 } },
			},

			-- 100 Charge, 23922 Shield Slam, 6572 Revenge, 2565 Shield Block, 72
			-- Shield Bash, 6343 Thunder Clap.
			--
			-- Revenge is here for the reason Overpower is on the arms layer: the
			-- reaction window says the fight opened it and this says the cooldown
			-- allows it, and they are not the same question.
			rotation = {
				{ key = "charge", spells = { 100 } },
				{ key = "shieldslam", spells = { 23922 } },
				{ key = "revenge", spells = { 6572 } },
				{ key = "shieldblock", spells = { 2565 } },
				{ key = "shieldbash", spells = { 72 } },
				{ key = "thunderclap", spells = { 6343 } },
			},

			-- 7386 Sunder Armor leads, which is the one debuff the shipped list left
			-- off on the argument that a warrior reads the stack count off his own
			-- frame. That argument holds for the warrior applying it and not for the
			-- one tanking four mobs, which is the whole of what a protection row is
			-- for. 1160 Demoralizing Shout, 6343 Thunder Clap, 12809 Concussion Blow.
			debuffs = { 7386, 1160, 6343, 12809 },
		},
	},

	loadout = LOADOUT,
})
