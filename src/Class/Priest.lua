local ADDON, ns = ...

--------------------------------------------------------------------------
-- Priest
--
-- One of the six fields, which makes this the shortest class file in the addon
-- and the one that proves a class may bring nothing but a fact. A priest has no
-- stances to page bar 1 between, no opener the charge button could cast, no
-- ability that opens on a dodge and nothing that casts inside a swing. Five
-- parts read those fields, find nothing and are not built.
--
-- No bar plan either, and that is a decision rather than an omission. The plans
-- in the other three files are written off a character somebody plays: the
-- twelve keys are the roles that character presses and the macros are the ones
-- they use. Nobody here has levelled a priest, and a plan written from a
-- talent calculator would fill your bars with somebody's guess and take a
-- backup you then have to put back. So the loadout page does not open, and the
-- refusal names the class rather than pretending.
--
-- What is left is one entry on the buff row, so the rail entry named after you
-- opens no page at all and is dropped. That is the shape this file is here to
-- keep working: a class file with no page of its own.
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
})
