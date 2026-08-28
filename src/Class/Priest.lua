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
	-- The long cooldowns
	--
	-- Five, and this is the second field this file has, so the paragraph at the
	-- top about a class that brings one fact is now a class that brings two.
	-- The argument for writing these down without a priest to look at is not
	-- the argument that was refused for the bar plan: a plan decides what every
	-- key on your bars does and gets it wrong in a way you have to undo, and a
	-- cooldown entry the client cannot resolve or the character does not know
	-- draws nothing at all. The cost of being wrong here is an empty square,
	-- and the cost of being wrong there was your bars.
	--
	-- The ids, from Wowhead's Classic and TBC Classic databases: 14751 Inner
	-- Focus, 10060 Power Infusion, 34433 Shadowfiend, 33206 Pain Suppression,
	-- 6346 Fear Ward.
	--
	-- Three of the five are Burning Crusade, and Fear Ward is the odd one:
	-- on Era it is a dwarf and draenei priest ability rather than a trained one,
	-- so on that client it is on the row for some priests and not for others,
	-- which IsSpellKnown answers without this file having to know about races.
	--
	-- Desperate Prayer is deliberately absent for the same reason and the
	-- opposite outcome: it is a racial on Era and a class ability in Burning
	-- Crusade, its id moved between them, and an id that resolves to the wrong
	-- spell is worse than an id that resolves to nothing. Whoever plays a priest
	-- here can add it once they can read it off their own spellbook.
	--------------------------------------------------------------------------
	cooldowns = {
		{ key = "innerfocus", spells = { 14751 } },
		{ key = "infusion", spells = { 10060 } },
		{ key = "shadowfiend", spells = { 34433 } },
		{ key = "suppression", spells = { 33206 } },
		{ key = "fearward", spells = { 6346 } },
	},
})
