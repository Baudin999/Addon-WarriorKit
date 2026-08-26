local ADDON, ns = ...

local Unit = {}
ns.Unit = Unit

--------------------------------------------------------------------------
-- What a unit is
--
-- The questions every part of the addon that draws a unit has to answer, in
-- one place, so that two parts drawing the same mob cannot disagree about it.
--
-- This layer was extracted rather than designed. The enemy bars and the frame
-- skin had each grown their own copy of four of these, and the copies had
-- drifted: the class colour was a hex string in one file and an {r,g,b} table
-- in the other, the level tag carried a difficulty colour in one and none in
-- the other, and the reaction palette was declared twice with the same five
-- literals. Neither copy was wrong. Having two of them was.
--
-- Four files sit under this one:
--
--   Color    the palette, the class colour and the reaction colour
--   Level    the level tag, the classification suffix and what a kill is worth
--   Roster   who is in the group, kept by event rather than by ticker
--   Threat   what the client's threat API says, for one mob or across a group
--
-- Loaded between Core and UI, because none of it draws anything and all of it
-- is wanted by things that do.
--
-- Two rules hold for everything here, and both come from the callers rather
-- than from taste.
--
--   Nothing allocates. Every function on this page is reachable from a ticker
--   running five to twenty times a second against every mob on the screen.
--   Answers come back as multiple returns or as a reference to a table this
--   layer already owns, never as a table built to carry them.
--
--   A colour is a reference, not a value. Every caller guards its widget
--   writes by comparing what it is about to draw against what it drew last,
--   and for a colour that comparison is table identity. So the same state must
--   hand back the same table every time. That is why the palette is a set of
--   module constants and why nothing here ever builds a colour.
--------------------------------------------------------------------------

local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType

-- Current, maximum, and the whole percent that actually gets drawn.
--
-- The percent is floored to an integer here rather than at each site, because
-- the integer is what the guards compare: a mob losing one point out of four
-- thousand must not redraw a number that still says 99%. Returning the ratio
-- and letting each caller floor it is how one of them ends up guarding on the
-- ratio and redrawing every tick.
--
-- A max of zero is a unit the client has not filled in yet, and the percent
-- comes back as -1 rather than 0. Zero is a claim that the mob is dead.
function Unit.Health(unit)
	local health = UnitHealth(unit) or 0
	local max = UnitHealthMax(unit) or 0
	if max <= 0 then
		return health, 0, -1
	end
	return health, max, math.floor(health / max * 100)
end

-- Current, maximum, and the number the client files this power under. The
-- number rather than the token beside it, because the number is the half that
-- has never been renamed between clients.
--
-- A max of zero is a unit with no power bar at all, which on these clients is
-- most of what you fight, and the caller draws nothing rather than an empty
-- rail.
function Unit.Power(unit)
	local max = UnitPowerMax(unit) or 0
	if max <= 0 then
		return 0, 0, UnitPowerType(unit) or 0
	end
	return UnitPower(unit) or 0, max, UnitPowerType(unit) or 0
end

-- "raid17" .. "target" is a fresh string every time it is asked for, and it is
-- asked for once per group member and once per mob on the screen, five times a
-- second. The token set is fixed and under a hundred entries, so it is
-- memoised rather than rebuilt.
--
-- Here rather than in either caller, because both the enemy bars and the
-- threat fallback want the same tokens and one of the two was building them
-- fresh on every tick while the other, in the same file, had a cache.
local targetTokens = {}

function Unit.TargetToken(unit)
	local token = targetTokens[unit]
	if not token then
		token = unit .. "target" -- allocates: once per unit token ever seen, and the lookup above is the guard the scan cannot see
		targetTokens[unit] = token
	end
	return token
end
