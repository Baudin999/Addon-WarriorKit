local ADDON, ns = ...

local Unit = ns.Unit
local Color = Unit.Color
local Level = {}
Unit.Level = Level

--------------------------------------------------------------------------
-- What a unit is worth
--
-- One question with two halves. The tag is what the mob's level reads as,
-- including the suffix that says it is an elite; the worth is the colour the
-- client's own XP scale puts on that number.
--
--     42   normal        42+   elite        42r   rare        42r+  rare elite
--     ??   a boss, or a level this client will not name
--
-- Both halves were already written, in two files, and each had what the other
-- was missing. UnitFrames/Skin.lua cached its tags and drew them in one
-- colour; UnitFrames/EnemyBars.lua coloured its tags on the XP scale and built
-- the string fresh every tick, which at three frames and five ticks a second
-- is thirty strings a second to say a number that changes when the mob does.
-- Merged here, both callers get the cache and the colour.
--------------------------------------------------------------------------

local CLASSIFICATION = {
	elite = "+",
	worldboss = "+",
	rareelite = "r+",
	rare = "r",
}

-- One string per level and classification pair, built the first time that pair
-- is seen and kept for the session. Levels are bounded and there are five
-- classifications, so the cache is too.
local tags = {}

local UnitLevel = UnitLevel

function Level.Tag(unit)
	local level = UnitLevel(unit) or 0
	local suffix = CLASSIFICATION[ns.Classification(unit) or "normal"] or ""
	local bySuffix = tags[suffix]
	if not bySuffix then
		bySuffix = {} -- allocates: once per classification, and the lookup above is the guard the scan cannot see
		tags[suffix] = bySuffix
	end
	local tag = bySuffix[level]
	if not tag then
		tag = (level > 0 and tostring(level) or "??") .. suffix -- allocates: once per level and classification pair, and the lookup above is the guard
		bySuffix[level] = tag
	end
	return tag
end

-- What killing it pays, on the client's own quest scale, which is also its XP
-- scale. More than GetQuestGreenRange below you and the mob pays nothing, two
-- either side of you is even, five above is the top of the range.
--
-- A level the client will not name is above yours by definition, so it takes
-- the top colour rather than the bottom one.
--
-- A client with no GetQuestGreenRange gets green rather than grey for the mobs
-- below that line. Grey is a claim that the kill is worth zero, and that claim
-- needs the number the shim could not get.
function Level.WorthOf(level)
	if type(level) ~= "number" or level <= 0 then
		return Color.xp.deadly
	end

	local diff = level - (UnitLevel("player") or level)
	if diff >= 5 then
		return Color.xp.deadly
	elseif diff >= 3 then
		return Color.xp.hard
	elseif diff >= -2 then
		return Color.xp.even
	end

	local green = ns.GreenRange()
	if green and -diff > green then
		return Color.xp.none
	end
	return Color.xp.easy
end

-- The same scale read off a unit, which is every caller but one.
--
-- The number is the question and the unit is one way of asking it. The quest
-- log is the other: a quest carries a level and no unit at all, and a second
-- copy of this ladder written against a number is a second copy that drifts on
-- the first change to GetQuestGreenRange.
--
-- A unit answers one thing the number cannot: whether somebody else tagged it.
-- A tapped mob pays nothing at any level, so it takes the bottom colour no
-- matter what its level would have said. Deliberately here and not in WorthOf,
-- because WorthOf is handed a level by the quest log and a quest cannot be
-- tagged out from under you.
function Level.Worth(unit)
	if ns.TapDenied(unit) then
		return Color.xp.none
	end
	return Level.WorthOf(UnitLevel(unit) or 0)
end

-- Whether the kill pays anything at all: the five colour scale collapsed to
-- the one bit you act on while you are choosing what to hit.
--
-- The scale is drawn on a two character level tag, and two characters is too
-- quiet a place to say "walk past this one". Callers that want to say it
-- louder ask here rather than comparing colours themselves, so there is one
-- definition of worthless and not one per frame.
function Level.Pays(unit)
	return Level.Worth(unit) ~= Color.xp.none
end

-- Both halves, for the one caller that draws them together. Two returns rather
-- than a table, because this is reached from a ticker once per mob.
function Level.Of(unit)
	return Level.Tag(unit), Level.Worth(unit)
end
