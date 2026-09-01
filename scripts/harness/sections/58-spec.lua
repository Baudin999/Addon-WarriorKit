-- Which spec this is, and what it swapped
--
-- Section 21 asks what class you are and proves the parts that read the
-- registry are built or absent accordingly. This is the same question one level
-- down, and the reason it needs a section of its own is that a spec decides
-- more than a class does: the cooldown row, the debuff row above every mob and
-- the bar plan are all read off it, and all three used to be one answer per
-- class that an alt inherited whether it fitted or not.
--
-- Every check below is written against what the registry says this character
-- brought rather than against a fixed answer, the way section 21 is, so the
-- same file is a gate on all thirteen runs: a warrior run proves fury and
-- protection swap the cooldown row between them, a shaman run proves an
-- enhancement plan does not reach an elemental shaman, and the hunter run
-- proves a class with no file resolves no spec and loses nothing by it.
--
-- The resolver itself is asserted rather than trusted, because it is the one
-- piece of this that a player never sees working: a signature spell outranks
-- the trees, the trees answer for a spec with no signature, and a character who
-- has committed to nothing gets nil and the class's own fields.

local H = ...
local PLAYER_CLASS, own = H.PLAYER_CLASS, H.own
local talentTrees, ns, check = H.talentTrees, H.ns, H.check

local Class, Spec = ns.Class, ns.Class.Spec

--------------------------------------------------------------------------
-- What the registry says this class has
--------------------------------------------------------------------------

local SPECS = Spec.All()
local mine = Spec.Mine()

-- A class file with no specs is a supported class, not an error, and so is a
-- class with no file at all. Both answer nil and both keep whatever the class
-- itself registered.
check((mine ~= nil) == (#SPECS > 0),
	("a %s has %d specs and resolved %s")
		:format(PLAYER_CLASS, #SPECS, tostring(Spec.Token())))

-- Every spec is registered under a key nothing else in the class uses, on a
-- tree nothing else in the class claims, and with a word to read out. The
-- registry asserts the first three at load; what is worth asserting here is
-- that the four class files actually keep the rule rather than that the assert
-- exists.
do
	local keys, trees = {}, {}
	for index = 1, #SPECS do
		local spec = SPECS[index]
		check(not keys[spec.key], ("two %s specs are called %s"):format(PLAYER_CLASS, spec.key))
		check(not trees[spec.tree],
			("two %s specs claim tree %d"):format(PLAYER_CLASS, spec.tree))
		check(spec.tree >= 1 and spec.tree <= #talentTrees.player,
			("the %s spec claims tree %d and this client counts %d")
				:format(spec.key, spec.tree, #talentTrees.player))
		keys[spec.key], trees[spec.tree] = true, true

		-- The label goes into a sentence behind an indefinite article, the same
		-- rule section 21 holds Class.Label to, and here it is followed by the
		-- class's own word: "an enhancement shaman". A label with a space in it
		-- would read as two words nobody typed and could not be typed at a
		-- slash word either.
		check(spec.label:find("%s") == nil,
			("the %s spec is labelled %q and a label is one word")
				:format(spec.key, spec.label))
	end
end

--------------------------------------------------------------------------
-- The overlay
--
-- Class.Of asks the spec first and the class second, per field. Both halves
-- matter and each is asserted on its own, because an overlay that always took
-- the spec would lose every field a spec does not mention and an overlay that
-- never took it would be the bug this whole file exists for.
--------------------------------------------------------------------------

if mine then
	local def = Class.All()[PLAYER_CLASS]

	for _, field in ipairs({ "cooldowns", "rotation", "debuffs", "loadout",
		"upkeep", "forms", "charge", "reactive", "swing", "requires", "suggested" }) do
		if mine[field] ~= nil then
			check(Class.Of(field) == mine[field],
				("the %s spec writes %s and Class.Of handed back the class's")
					:format(mine.key, field))
		else
			check(Class.Of(field) == def[field],
				("the %s spec says nothing about %s and Class.Of did not fall"
					.. " through to the class"):format(mine.key, field))
		end
	end

	-- The three fields the swap is actually for, each read through the part that
	-- reads it in the game rather than through Class.Of a second time.
	--
	-- At least, rather than exactly: the row carries the trinket slots on the end
	-- of the docked line and neither of them is a class fact.
	local listed = #(Class.Of("cooldowns") or {}) + #(Class.Of("rotation") or {})
	check(ns.Cooldowns.Count() >= listed,
		("the %s spec lists %d cooldowns over the two layers and the row drew %d")
			:format(mine.key, listed, ns.Cooldowns.Count()))

	local shipped = ns.EnemyBars.DefaultSpells()
	check(#shipped == #(Class.Of("debuffs") or {}),
		("the debuff row ships %d squares and the %s spec lists %d")
			:format(#shipped, mine.key, #(Class.Of("debuffs") or {})))

	-- A spec with no bar plan opens no loadout page and says which spec it is
	-- refusing for, which is the whole of what an elemental shaman gets today.
	if not Class.Of("loadout") then
		check(ns.Layout.Refusal():find(Class.Label(), 1, true) ~= nil,
			("a %s has no plan and the refusal does not name the class: %s")
				:format(Spec.Says(), ns.Layout.Refusal()))
	end
end

--------------------------------------------------------------------------
-- How the answer was arrived at
--
-- Driven rather than observed. Both readings are put in and out of play and
-- the resolver is asked again each time, which is the only way to tell a
-- signature that outranks the trees from one that happens to agree with them.
--
-- Everything here is put back before the section ends, because the sections
-- that follow read the row this one has been rearranging.
--------------------------------------------------------------------------

if #SPECS > 0 then
	local before = Spec.Token()

	-- Every point in one tree and no signature spell known at all. The tree is
	-- the only reading left and it has to answer.
	local spent, unknown = {}, {}
	for index, tree in ipairs(talentTrees.player) do
		spent[index] = tree.points
	end
	for _, spec in ipairs(SPECS) do
		for _, id in ipairs(spec.signature or {}) do
			unknown[id] = own.unknown[id]
			own.unknown[id] = true
		end
	end

	for _, spec in ipairs(SPECS) do
		for index, tree in ipairs(talentTrees.player) do
			tree.points = (index == spec.tree) and 41 or 0
		end
		Spec.Forget()
		check(Spec.Token() == spec.key,
			("every point is in tree %d and the addon reads %s rather than %s")
				:format(spec.tree, tostring(Spec.Token()), spec.key))
	end

	-- Nobody has committed to anything. Nil is the answer and it is not an
	-- error: the class's own fields stand, which is what a level nine character
	-- gets and what shipped before specs existed.
	for _, tree in ipairs(talentTrees.player) do
		tree.points = 1
	end
	Spec.Forget()
	check(Spec.Token() == nil,
		("three points over three trees was read as %s"):format(tostring(Spec.Token())))
	check(Spec.Says() == Class.Label(),
		("with no spec the addon calls you %q and the class is %q")
			:format(Spec.Says(), Class.Label()))

	-- A signature spell outranks the trees outright, which is what makes it
	-- worth having: the points say one thing and the spellbook says another,
	-- and the spellbook is a fact.
	for _, spec in ipairs(SPECS) do
		if spec.signature and #spec.signature > 0 then
			for index, tree in ipairs(talentTrees.player) do
				-- Every point in a tree that is not this spec's, so the
				-- fallback would answer something else if it were reached.
				tree.points = (index ~= spec.tree) and 41 or 0
			end
			for _, id in ipairs(spec.signature) do
				own.unknown[id] = nil
				Spec.Forget()
				check(Spec.Token() == spec.key,
					("%d is a %s signature and the addon reads %s")
						:format(id, spec.key, tostring(Spec.Token())))
				own.unknown[id] = true
			end
		end
	end

	-- Everything back, and the answer with it, because the row and the debuff
	-- list the sections below read were built off it at login.
	for index, tree in ipairs(talentTrees.player) do
		tree.points = spent[index]
	end
	for id, was in pairs(unknown) do
		own.unknown[id] = was
	end
	for _, spec in ipairs(SPECS) do
		for _, id in ipairs(spec.signature or {}) do
			if unknown[id] == nil then
				own.unknown[id] = nil
			end
		end
	end
	Spec.Forget()
	check(Spec.Token() == before,
		("the section left this character as %s and it came up as %s")
			:format(tostring(Spec.Token()), tostring(before)))
end

print(("spec   %s; %d spec(s) written for a %s, %d cooldowns over two layers,"
	.. " %d debuffs on the bar"):format(Spec.Says(), #SPECS, Class.Label(),
	#(Class.Of("cooldowns") or {}) + #(Class.Of("rotation") or {}),
	#ns.EnemyBars.DefaultSpells()))
