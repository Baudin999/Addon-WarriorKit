local ADDON, ns = ...

local Unit = ns.Unit
local Color = Unit.Color
local Roster = Unit.Roster
local Threat = {}
Unit.Threat = Threat

--------------------------------------------------------------------------
-- Threat
--
-- What the client's threat API says, asked once and shared. Two parts of the
-- addon want it and they want two different questions answered.
--
--   the enemy bars    who is closest to taking this mob off me, per mob, five
--                     times a second
--   the threat meter  how fast is everyone gaining on the mob I am looking at,
--                     and when does the next one overtake
--
-- The meter's model lives in Meter/Threat.lua, because rate smoothing and a
-- pull ETA are that readout's own arithmetic and nothing else wants them. What
-- is here is the part both were doing separately: probing the API, reading one
-- pair, and walking the group to find the worst.
--
-- Vanilla has no threat API at all. Nothing in that client computes threat,
-- which is why every Classic threat meter parses the combat log instead.
-- Threat.Ready answers once and every caller has its own honest fallback:
-- the bars colour by who each mob is swinging at, and the meter's pane says so
-- and stays empty. Nothing here guesses.
--------------------------------------------------------------------------

local UnitIsUnit = UnitIsUnit

-- Thresholds for how close is too close, in percent of the tank's threat. Both
-- are the caller's language rather than the client's: the API answers a scaled
-- percentage and these are where that number turns into a colour.
local CLOSE = 70
local LOSING = 90

function Threat.Ready()
	return ns.HasThreat()
end

-- isTanking, status, scaled percent, straight from the client. Nil all the way
-- down where the API is missing, which is a different answer from "no threat
-- on this mob" and the caller has to tell them apart, so ask Threat.Ready
-- first.
function Threat.On(source, unit)
	return ns.Threat(source, unit)
end

-- The group member with the most threat on a mob, not counting you. Two
-- returns and no table, because this runs once per mob per tick.
--
-- The roster is walked from the second entry rather than filtered, because
-- Unit/Roster.lua builds it player first and says so. Nil for a group of one,
-- and for a group where the client will not answer for anyone: both mean there
-- is nobody to lose the mob to, and the caller draws them the same.
function Threat.Top(unit)
	local group = Roster.Units()
	local worst, worstUnit = 0, nil
	for index = 2, #group do
		local member = group[index]
		local _, _, percent = ns.Threat(member, unit)
		if percent and percent > worst then
			worst, worstUnit = percent, member
		end
	end
	if not worstUnit then
		return nil, nil
	end
	return worst, worstUnit
end

-- The colour a percentage of the tank's threat is worth. Shared so that a bar
-- and any future readout cannot disagree about where amber starts.
function Threat.Shade(percent)
	if percent >= LOSING then
		return Color.threat.losing
	elseif percent >= CLOSE then
		return Color.threat.close
	end
	return Color.threat.safe
end

-- Where you stand on one mob, in the three pieces a bar draws.
--
--   colour       one of the threat palette's five, always
--   percent      the number worth printing beside it, or nil for none
--   challenger   whose percent that is, or nil when it is yours or nobody's
--
-- Nil for everything on a client with no threat API, so the caller can fall
-- back rather than draw a confident grey.
--
-- Holding the mob and having nobody behind you is safe with no number: a
-- percentage with nothing to compare it against is noise on a bar that already
-- carries three other things.
function Threat.State(unit)
	if not ns.HasThreat() then
		return nil
	end

	local isTanking, status = ns.Threat("player", unit)
	if status == nil then
		return Color.threat.idle, nil, nil
	end

	if isTanking then
		local percent, challenger = Threat.Top(unit)
		if not challenger then
			return Color.threat.safe, nil, nil
		end
		return Threat.Shade(percent), percent, challenger
	end

	-- On somebody else, which is always red: the mob is on the wrong person and
	-- how far behind you are does not change that.
	local _, _, percent = ns.Threat("player", unit)
	return Color.threat.off, percent or 0, nil
end

-- Who a mob is actually swinging at, which is the honest half of the question
-- a client with no threat API can answer. It cannot warn you before a mob
-- turns, only tell you after it has, and every caller says so.
--
-- The colour, the unit it is hitting, and whether that is you. Three returns
-- rather than a formatted line, because how a bar words it is the bar's
-- business and shortening a name is presentation.
--
-- Green when it is on you: this is a warrior addon and the mob being on you is
-- the state you were trying to reach.
function Threat.Swinging(unit)
	local victim = Unit.TargetToken(unit)
	if not UnitExists(victim) then
		return Color.threat.idle, nil, false
	end
	if UnitIsUnit(victim, "player") then
		return Color.threat.safe, victim, true
	end
	return Color.threat.off, victim, false
end
