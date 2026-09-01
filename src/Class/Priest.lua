local ADDON, ns = ...

--------------------------------------------------------------------------
-- Priest
--
-- Two of the seven fields, and no bar plan, which still makes this the shortest
-- class file in the addon. A priest has no stances to page bar 1 between, no
-- opener the charge button could cast, no ability that opens on a dodge and
-- nothing that casts inside a swing. Four parts read those fields, find nothing
-- and are not built.
--
-- The missing plan is a decision rather than an omission. The plans
-- in the other three files are written off a character somebody plays: the
-- twelve keys are the roles that character presses and the macros are the ones
-- they use. Nobody here has levelled a priest, and a plan written from a
-- talent calculator would fill your bars with somebody's guess and take a
-- backup you then have to put back. So the loadout page does not open, and the
-- refusal names the class rather than pretending.
--
-- What is left is two entries on the buff row and five on the cooldown row, so
-- the rail entry named after you opens no page at all and is dropped. That is
-- the shape this file is here to keep working: a class file with no page of its
-- own.
--
-- Shadowform is not a form. GetShapeshiftForm counts it the way it counts a
-- shaman's Ghost Wolf, but bar 1 does not page into it, the bonus bar offset
-- stays 0, and a weapon set bound to it is a loadout for a caster who does not
-- swap weapons. The same argument, written down in Class\Shaman.lua.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- The cooldowns every spec counts
--
-- 34433 Shadowfiend and 6346 Fear Ward, written once and named by all three.
-- Both are Burning Crusade on this account and neither belongs to a tree.
--------------------------------------------------------------------------

local SHADOWFIEND = { key = "shadowfiend", spells = { 34433 } }
local FEAR_WARD = { key = "fearward", spells = { 6346 } }

ns.Class.Register("PRIEST", {
	label = "priest",

	--------------------------------------------------------------------------
	-- What this class adds to the upkeep row
	--
	-- Both are exactly what the row is for: silent when they lapse, expensive
	-- while they are lapsed, and gone after every death.
	--
	-- Fortitude is the buff most often missing after a wipe, and 1243 is Power
	-- Word: Fortitude rank 1. 21562 is Prayer of Fortitude, which is the same
	-- job on the whole group and lands under its own name, so both ids are
	-- listed and either one clears the square. Which of the two you cast is a
	-- question about how many of you there are and this row has no opinion
	-- about it.
	--
	-- Inner Fire, 588, is the one that goes without saying so. It runs out on
	-- charges rather than only on the clock, so it can lapse in the middle of a
	-- pull that had a minute left on it.
	--
	-- Rank 1 of each, because the match is by name and every rank shares one.
	--------------------------------------------------------------------------
	upkeep = {
		{
			key = "fortitude", spells = { 1243, 21562 },
			fixed = "no fortitude",
			word = "fortitude",
			switch = "tell me when fortitude is down",
			hint = "You have no Fortitude up. The single and the group version both"
				.. " count, so either one clears this square, and both come off"
				.. " when you die.",
		},
		{
			key = "innerfire", spells = { 588 },
			fixed = "no inner fire",
			word = "inner",
			switch = "tell me when Inner Fire is down",
			hint = "Inner Fire is not up. It is spent by being hit as well as by the"
				.. " clock, so it can run out mid pull without the timer having"
				.. " looked close.",
		},
	},

	--------------------------------------------------------------------------
	-- What the picker offers
	--
	-- Shared by all three specs. 589 Shadow Word: Pain, 34914 Vampiric Touch,
	-- 15407 Mind Flay, 15286 Vampiric Embrace, 14914 Holy Fire.
	--------------------------------------------------------------------------
	suggested = { 589, 34914, 15407, 15286, 14914 },

	--------------------------------------------------------------------------
	-- The three specs
	--
	-- Tree order, which is the order the client counts them in and the order the
	-- resolver falls back on: 1 discipline, 2 holy, 3 shadow.
	--
	-- Still no bar plan anywhere, for the reason at the top of this file, and the
	-- specs do not change that argument: nobody here has levelled a priest, so
	-- there is no character to write one off. What the specs do add is the same
	-- thing they add everywhere else, which is a shorter cooldown row and a debuff
	-- row that is about this priest rather than about priests.
	--
	-- The ids, from Wowhead's Classic and TBC Classic databases: 14751 Inner
	-- Focus, 10060 Power Infusion, 34433 Shadowfiend, 33206 Pain Suppression,
	-- 6346 Fear Ward, 589 Shadow Word: Pain, 15407 Mind Flay, 34914 Vampiric
	-- Touch, 15286 Vampiric Embrace, 14914 Holy Fire, 8092 Mind Blast.
	--
	-- Three of the cooldowns are Burning Crusade, and Fear Ward is the odd one:
	-- on Era it is a dwarf and draenei priest ability rather than a trained one,
	-- so on that client it is on the row for some priests and not for others,
	-- which IsSpellKnown answers without this file having to know about races.
	--
	-- Desperate Prayer is deliberately absent for the same reason and the opposite
	-- outcome: it is a racial on Era and a class ability in Burning Crusade, its
	-- id moved between them, and an id that resolves to the wrong spell is worse
	-- than an id that resolves to nothing. Whoever plays a priest here can add it
	-- once they can read it off their own spellbook.
	--
	-- Only discipline carries a signature, and it carries two: Power Infusion at
	-- thirty one points and Pain Suppression at forty one. Both are single rank
	-- and both are deep enough that nobody holding one is playing anything else.
	--
	-- Inner Focus is deliberately not one of them, and it is the case worth
	-- writing down. It is single rank and it is a discipline talent, so it looks
	-- like the obvious third; it sits fifteen points up, which is inside the reach
	-- of a holy priest, and a signature a second spec commonly owns is not a
	-- signature at all, it is a way to call every holy priest discipline. It is
	-- on both cooldown lists below for exactly the same reason.
	--
	-- Holy and shadow own nothing of that shape, so both are answered by their
	-- tree, which is what the fallback is for.
	--------------------------------------------------------------------------
	specs = {
		{
			key = "discipline", label = "discipline", tree = 1,
			signature = { 10060, 33206 }, -- Power Infusion, Pain Suppression

			cooldowns = {
				{ key = "innerfocus", spells = { 14751 } },
				{ key = "infusion", spells = { 10060 } },
				{ key = "suppression", spells = { 33206 } },
				SHADOWFIEND, FEAR_WARD,
			},

			rotation = {
				{ key = "mindblast", spells = { 8092 } },
			},

			debuffs = { 589, 14914 },
		},

		{
			key = "holy", label = "holy", tree = 2,

			cooldowns = {
				{ key = "innerfocus", spells = { 14751 } },
				SHADOWFIEND, FEAR_WARD,
			},

			rotation = {
				{ key = "mindblast", spells = { 8092 } },
			},

			debuffs = { 14914, 589 },
		},

		{
			key = "shadow", label = "shadow", tree = 3,

			cooldowns = {
				SHADOWFIEND, FEAR_WARD,
			},

			rotation = {
				{ key = "mindblast", spells = { 8092 } },
			},

			-- The four a shadow priest keeps up and cannot read anywhere else. All
			-- but Shadow Word: Pain are Burning Crusade, and on Era the row is one
			-- square long, which is correct rather than short.
			debuffs = { 589, 34914, 15407, 15286 },
		},
	},
})
