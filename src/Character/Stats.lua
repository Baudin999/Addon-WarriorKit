local ADDON, ns = ...

local Stats = {}
ns.CharStats = Stats

--------------------------------------------------------------------------
-- What your character actually does
--
-- The client's own sheet draws eight numbers and puts the rest behind a hover
-- you have to know is there. This draws every number it will answer for, in
-- groups, with the one thing it will not answer for worked out from what it
-- will: how often you miss.
--
-- **Missing is the point of this page.** Every other number here is a lookup.
-- Hit is the number that decides whether a fight goes the way the rest of the
-- sheet says it should, and no client on either of these versions has ever put
-- it on the character sheet, because the client knows your hit rating and not
-- your hit chance. So the miss chance is computed, against a target of your own
-- level and against the three above it, for a special, for a white swing and
-- for a spell, and the row underneath says how much more hit would take each of
-- them to nothing.
--
-- **The formula is written down and it reproduces the three published
-- numbers.** A character at the weapon skill their level allows misses 5.5% at
-- one level up, 6% at two and 9% at three, and those three are what every hit
-- cap anybody quotes is derived from. The constants below are the only shape
-- that lands on all three: the first ten points of the target's defence over
-- your weapon skill cost a tenth of a percent each, and every point after those
-- ten costs six tenths. Change one of them and check it against 5.5, 6 and 9
-- before believing it.
--
-- **What this cannot see is talent hit.** The client rates hit that came off
-- gear and has no call at all for the flat percentage a talent gives, so a
-- warrior with three points in the one that grants it is one percent better
-- than this page says. The row says so rather than quietly being wrong, which
-- is the whole difference between a computed number that helps and one that
-- costs somebody a set of enchants.
--
-- **Every call is probed and a group that answered nothing is not drawn.** Two
-- clients load this addon and they disagree about ratings, expertise and
-- resilience: the older one has none of the three. A row that would print
-- "unknown" nineteen times is a page that teaches you to stop reading it, so a
-- row the client will not answer is absent, and the two places where absence is
-- itself the answer say so in a sentence instead.
--
-- Nothing here is cached and nothing here is on a ticker. The window reads this
-- when it opens and when the client says a number moved.
--------------------------------------------------------------------------

-- The client, asked for something it may not have.
--
-- A local rather than a shim per call in Core/Core.lua, and the reason is the
-- one Progress/Progress.lua gives for keeping its own: these are two dozen
-- calls read by this file and by nothing else, each one written against its own
-- returns, and two dozen one-line functions in Core would be a layer every
-- reader has to step through to find out that GetCritChance returns a
-- percentage. What belongs in Core is a question two parts ask.
local function Ask(name, ...)
	local call = _G[name]
	if type(call) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e, f = pcall(call, ...)
	if not ok then
		return nil
	end
	return a, b, c, d, e, f
end

local function Round(value)
	return math.floor((value or 0) + 0.5)
end

-- Both formatters answer nil for nil, so a call this client does not carry
-- falls out of the list rather than printing as a confident zero. That is the
-- difference between "your gear has no hit on it" and "nothing here can say",
-- and every row below leans on it.
local function Whole(value)
	if type(value) ~= "number" then
		return nil
	end
	return ("%d"):format(Round(value))
end

local function Percent(value)
	if type(value) ~= "number" then
		return nil
	end
	return ("%.2f%%"):format(value)
end

-- One row, or nothing at all where the client did not answer. Every group below
-- is a list of these with the nils dropped, which is what makes a client
-- missing a whole subject draw no heading for it.
local function Row(rows, label, value, note)
	if value == nil then
		return rows
	end
	rows[#rows + 1] = { label = label, value = value, note = note }
	return rows
end

--------------------------------------------------------------------------
-- Missing
--------------------------------------------------------------------------

-- The melee miss curve. See the header: these four reproduce 5.5%, 6% and 9%
-- at one, two and three levels up, and nothing else does.
local BASE_MISS = 5.0
local STEP = 10
local FIRST_TEN = 0.1
local BEYOND_TEN = 0.6

-- What a second weapon costs every white swing. It is not on the curve because
-- it has nothing to do with the target: it is the penalty for swinging two
-- things at once and it applies at every level difference.
local DUAL_WIELD = 19.0

-- Spells are a table rather than a curve. The step from two levels up to three
-- is eleven points, which no line through the first three points goes near, and
-- writing it as a formula would be inventing a mechanism to explain a number
-- that was chosen.
local SPELL_MISS = { [0] = 4.0, [1] = 5.0, [2] = 6.0, [3] = 17.0 }

-- A spell always has one percent of going wide, so hit past that point is spent
-- on nothing. There is no equivalent for melee.
local SPELL_FLOOR = 1.0

-- How many levels above you the thing you are gearing for is.
local BOSS = 3

-- The client's own numbers for the two hit ratings, read off the globals rather
-- than written down, because a rating index is a client constant and this addon
-- runs on a client that has none of them.
local function RatingIndex(name)
	local index = _G[name]
	return type(index) == "number" and index or nil
end

-- What your gear buys you, as a percentage, or nil on a client with no ratings
-- at all. Nil is not zero: zero would be a claim that your gear has no hit on
-- it, which on the older client is a claim nothing can support.
local function HitBonus(which)
	local index = RatingIndex(which)
	if not index then
		return nil
	end
	local bonus = Ask("GetCombatRatingBonus", index)
	return type(bonus) == "number" and bonus or nil
end

-- Your weapon skill, and the client's fallback for a client that will not say.
-- Skill is capped at five per level, so a client with no call for it is a
-- client where assuming the cap is right for everybody who has been using the
-- weapon they are holding.
local function Skill()
	local level = Ask("UnitLevel", "player") or 1
	local base, mod = Ask("UnitAttackBothHands", "player")
	if type(base) == "number" and base > 0 then
		return base + (type(mod) == "number" and mod or 0), level
	end
	return level * 5, level
end

-- The chance a swing or a special goes wide, before any hit is taken off.
function Stats.MeleeMiss(delta)
	local skill, level = Skill()
	local gap = (level + delta) * 5 - skill
	if gap <= 0 then
		return BASE_MISS
	end
	return BASE_MISS
		+ math.min(gap, STEP) * FIRST_TEN
		+ math.max(gap - STEP, 0) * BEYOND_TEN
end

function Stats.SpellMiss(delta)
	return SPELL_MISS[delta] or SPELL_MISS[BOSS]
end

-- Whether both hands are holding a weapon, which is what makes a white swing
-- cost nineteen points more than a special. A shield in the off hand is not a
-- weapon and does not.
local function DualWielding()
	local off = Ask("OffhandHasWeapon")
	if off ~= nil then
		return off and true or false
	end
	return ns.Worn.Link(17) ~= nil
end

local function Left(miss, hit)
	if not hit then
		return miss
	end
	return math.max(miss - hit, 0)
end

--------------------------------------------------------------------------
-- The groups
--------------------------------------------------------------------------

local function Missing(rows)
	local melee, spell = HitBonus("CR_HIT_MELEE"), HitBonus("CR_HIT_SPELL")
	local dual = DualWielding()

	local special = Left(Stats.MeleeMiss(BOSS), melee)
	Row(rows, "a special, three levels up", Percent(special),
		("%s against your own level. Three levels up is what a raid boss is.")
			:format(Percent(Left(Stats.MeleeMiss(0), melee))))

	local swing = Left(Stats.MeleeMiss(BOSS) + (dual and DUAL_WIELD or 0), melee)
	Row(rows, "a white swing, three levels up", Percent(swing),
		dual and "Nineteen points of that is the second weapon, and no amount of hit is spent better than the first point of it."
			or "One weapon, so a swing misses as often as a special does.")

	local cast = Left(Stats.SpellMiss(BOSS), spell)
	Row(rows, "a spell, three levels up", Percent(math.max(cast, SPELL_FLOOR)),
		("A spell never goes below %s, so hit past that point buys nothing.")
			:format(Percent(SPELL_FLOOR)))

	if melee then
		Row(rows, "hit off your gear", ("%s melee, %s spell")
			:format(Percent(melee), Percent(spell or 0)),
			"Gear only. The client rates what your gear gave you and has no call at all for the flat percentage a talent grants, so a talent that gives hit is not in this number.")
		Row(rows, "hit still wanted", ("%s to stop missing specials, %s for swings")
			:format(Percent(special), Percent(swing)),
			"What each of the rows above would take to reach nothing.")
	else
		Row(rows, "hit off your gear", "this client does not rate hit",
			"There are no combat ratings on this version, so nothing can be taken off the rows above. They are the miss chance of a character with no hit at all.")
	end

	local skill, level = Skill()
	Row(rows, "weapon skill", ("%d of %d"):format(skill, level * 5),
		skill < level * 5
			and "Under the cap for your level, and every point under it is on the rows above."
			or "At the cap for your level.")
	return rows
end

local STAT_NAMES = { "strength", "agility", "stamina", "intellect", "spirit" }

-- What the client added or took away, as the sentence under a stat. Written
-- only where something did, because "+0" under five rows in a row is furniture.
local function Swing(positive, negative)
	positive, negative = positive or 0, negative or 0
	if positive == 0 and negative == 0 then
		return nil
	end
	if negative == 0 then
		return ("%d of that is buffs and gear."):format(Round(positive))
	end
	if positive == 0 then
		return ("Something is taking %d off it."):format(Round(-negative))
	end
	return ("%d on from buffs and gear, %d off again.")
		:format(Round(positive), Round(-negative))
end

local function Attributes(rows)
	for index = 1, #STAT_NAMES do
		local base, total, positive, negative = Ask("UnitStat", "player", index)
		if base then
			Row(rows, STAT_NAMES[index], Whole(total or base),
				Swing(positive, negative))
		end
	end

	local _, effective, _, positive, negative = Ask("UnitArmor", "player")
	if effective then
		Row(rows, "armour", Whole(effective), Swing(positive, negative))
	end
	Row(rows, "health", Whole(Ask("UnitHealthMax", "player")))
	local power = Ask("UnitPowerMax", "player") or Ask("UnitManaMax", "player")
	if power and power > 0 then
		Row(rows, "power", Whole(power))
	end
	return rows
end

local function Melee(rows)
	local minimum, maximum, minOff, maxOff, bonus, percent = Ask("UnitDamage", "player")
	local speed, offSpeed = Ask("UnitAttackSpeed", "player")
	if minimum and speed and speed > 0 then
		local low = (minimum + (bonus or 0)) * (percent or 1)
		local high = (maximum + (bonus or 0)) * (percent or 1)
		Row(rows, "damage", ("%d to %d"):format(Round(low), Round(high)))
		Row(rows, "speed", ("%.2f seconds"):format(speed))
		Row(rows, "damage a second", ("%.1f"):format((low + high) / 2 / speed))
	end
	if minOff and maxOff and offSpeed and offSpeed > 0 then
		Row(rows, "off hand damage", ("%d to %d, every %.2f seconds")
			:format(Round(minOff), Round(maxOff), offSpeed))
	end

	local base, positive, negative = Ask("UnitAttackPower", "player")
	if base then
		Row(rows, "attack power", Whole(base + (positive or 0) + (negative or 0)),
			Swing(positive, negative))
	end
	Row(rows, "critical", Percent(Ask("GetCritChance")))

	local expertise = Ask("GetExpertise")
	if expertise then
		Row(rows, "expertise", Whole(expertise),
			"Every point of it takes a quarter of a percent off the chance the target dodges or parries you.")
	end
	return rows
end

local function Ranged(rows)
	if not ns.Worn.Link(18) then
		return rows
	end
	local speed, minimum, maximum = Ask("UnitRangedDamage", "player")
	if minimum and speed and speed > 0 then
		Row(rows, "damage", ("%d to %d"):format(Round(minimum), Round(maximum)))
		Row(rows, "speed", ("%.2f seconds"):format(speed))
	end
	local base, positive, negative = Ask("UnitRangedAttackPower", "player")
	if base then
		Row(rows, "attack power", Whole(base + (positive or 0) + (negative or 0)),
			Swing(positive, negative))
	end
	Row(rows, "critical", Percent(Ask("GetRangedCritChance")))
	return rows
end

-- The six schools, in the order the client indexes them. Physical is index one
-- and is not a school anything here reads, so the list starts at holy.
local SCHOOLS = { "holy", "fire", "nature", "frost", "shadow", "arcane" }

-- The school you are best at, because six rows of spell power on a warrior is
-- six rows of zero. The name comes with it, so a shadow priest reading one
-- number knows which one it is.
local function Best(call)
	local top, name
	for index = 1, #SCHOOLS do
		local value = Ask(call, index + 1)
		if type(value) == "number" and (not top or value > top) then
			top, name = value, SCHOOLS[index]
		end
	end
	return top, name
end

-- Drawn for a character who has spell power or healing power on their gear,
-- and for nobody else.
--
-- The client answers a spell crit chance and a mana regen for a warrior in
-- plate, both off intellect they never chose to have, so a group drawn whenever
-- one of its calls answered would put two rows of noise on every melee
-- character's sheet. Spell power is the thing that says somebody is casting,
-- and without it the other three rows are three ways of saying nought.
local function Spell(rows)
	local power, school = Best("GetSpellBonusDamage")
	local healing = Ask("GetSpellBonusHealing")
	if (power or 0) <= 0 and (healing or 0) <= 0 then
		return rows
	end
	if power and power > 0 then
		Row(rows, "spell power", Whole(power), ("Your best school is %s."):format(school))
	end
	if healing and healing > 0 then
		Row(rows, "healing power", Whole(healing))
	end
	Row(rows, "critical", Percent((Best("GetSpellCritChance"))))
	local base, casting = Ask("GetManaRegen")
	if base then
		Row(rows, "mana every five seconds",
			("%d standing still, %d casting"):format(Round(base * 5), Round((casting or 0) * 5)))
	end
	return rows
end

-- What a given amount of armour takes off a physical hit, against an attacker
-- of your own level.
--
-- Two formulas because the game has two. Below level sixty the divisor grows by
-- eighty-five per attacker level; from sixty up it grows by four hundred and
-- sixty-seven and a half and a constant comes off, which is the change that
-- stopped armour scaling out of reach in the expansion this addon's newer
-- client is. A single formula would be wrong on one side of sixty and nobody
-- would ever see which.
local function Mitigation(armor, level)
	local divisor
	if level >= 60 then
		divisor = armor + 467.5 * level - 22167.5
	else
		divisor = armor + 400 + 85 * level
	end
	if divisor <= 0 then
		return nil
	end
	return math.min(armor / divisor, 0.75) * 100
end

local function Defence(rows)
	local _, effective = Ask("UnitArmor", "player")
	local level = Ask("UnitLevel", "player") or 1
	if effective then
		local taken = Mitigation(effective, level)
		Row(rows, "armour", Whole(effective), taken and
			("%s off a physical hit from something your own level.")
				:format(Percent(taken)) or nil)
	end

	local base, modifier = Ask("UnitDefense", "player")
	if base then
		Row(rows, "defence", Whole(base + (modifier or 0)))
	end
	Row(rows, "dodge", Percent(Ask("GetDodgeChance")))
	Row(rows, "parry", Percent(Ask("GetParryChance")))
	Row(rows, "block", Percent(Ask("GetBlockChance")))
	local shield = Ask("GetShieldBlock")
	if shield and shield > 0 then
		Row(rows, "blocked for", Whole(shield))
	end

	local resilience = RatingIndex("CR_CRIT_TAKEN_MELEE")
	if resilience then
		Row(rows, "resilience", Whole(Ask("GetCombatRating", resilience)),
			"It takes crit off what lands on you, and it is the only stat here that another player's gear cannot answer.")
	end
	return rows
end

local function Resistance(rows)
	for index = 2, 6 do
		local value = Ask("UnitResistance", "player", index)
		if type(value) == "number" then
			Row(rows, SCHOOLS[index], Whole(value))
		end
	end
	return rows
end

--------------------------------------------------------------------------

-- Every group, in the order the page draws them, with the empty ones dropped.
--
-- Missing goes first, above the attributes the client's own sheet leads with,
-- and that is a decision rather than an accident: strength is a number you look
-- at once when you put a piece on, and hit is the number you came here for.
local GROUPS = {
	{ title = "Hit and miss", fill = Missing },
	{ title = "Attributes", fill = Attributes },
	{ title = "Melee", fill = Melee },
	{ title = "Ranged", fill = Ranged },
	{ title = "Spell", fill = Spell },
	{ title = "Defence", fill = Defence },
	{ title = "Resistance", fill = Resistance },
}

function Stats.Groups()
	local groups = {}
	for index = 1, #GROUPS do
		local rows = GROUPS[index].fill({})
		if #rows > 0 then
			groups[#groups + 1] = { title = GROUPS[index].title, rows = rows }
		end
	end
	return groups
end

function Stats.Describe()
	local melee = HitBonus("CR_HIT_MELEE")
	if not melee then
		return ("no ratings on this client, %s to miss a special on a boss")
			:format(Percent(Stats.MeleeMiss(BOSS)))
	end
	return ("%s hit, %s to miss a special on a boss")
		:format(Percent(melee), Percent(Left(Stats.MeleeMiss(BOSS), melee)))
end
