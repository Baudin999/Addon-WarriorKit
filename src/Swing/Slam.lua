local ADDON, ns = ...

local Slam = {}
ns.Slam = Slam

--------------------------------------------------------------------------
-- The one press the bar exists for
--
-- Slam is the only ability in the game whose whole difficulty is a swing
-- timer. It has a cast time, it does not interrupt the swing while it casts,
-- and when it completes the swing timer restarts. Those three together make
-- one instant correct and every other instant a loss:
--
--   press too early and the cast finishes with the swing still charging. The
--   restart throws that charge away, so you paid for the part of the swing
--   that had already elapsed and got nothing for it.
--   press too late and the swing would land inside the cast. It does not; it
--   is pushed out to the end of the cast instead, which is what everybody
--   means by clipping a swing.
--
-- The right press is the one where the cast ends as the swing ends, which is
-- the moment the swing has exactly a cast time left to run. That is a number,
-- it moves with haste and with the weapon, and no amount of watching a bar
-- move tells you where it is. So it is drawn: a band on the main hand gauge
-- with a line down the middle of it, and the gauge itself flips colour while
-- the fill is inside the band. You press on a mark rather than reading a
-- moving bar, which is the whole feature.
--
-- Two numbers decide where that mark sits and neither is a constant here.
--
-- The swing is ns.Swing's, out of UnitAttackSpeed.
--
-- The cast is the spell's own, out of ns.SpellCastTime, less what Improved
-- Slam takes off it. The talent is read out of the talent trees rather than
-- assumed, and it is found by name: every "Improved X" talent in this game is
-- named with the ability's own localised name inside it, in every locale
-- Blizzard ships, so the talent whose name contains the localised name of Slam
-- and is not itself Slam is Improved Slam. That is a rule about how Blizzard
-- names things rather than an API, which is why the whole of it is one
-- fallback: the moment you cast a Slam, the client tells the truth.
--
-- UNIT_SPELLCAST_START carries the cast the server actually started, start and
-- end in milliseconds, talents and haste and everything else already folded
-- in. That measurement replaces the estimate for the rest of the session and
-- is re-taken on every cast. So the first Slam of a session is drawn from an
-- estimate that may be a tenth out, and every Slam after it is drawn from the
-- client's own number. Nothing here has to be right about whether this client
-- folds a talent into GetSpellInfo, which is the one thing about it that could
-- not be settled without logging in.
--------------------------------------------------------------------------

local UnitCastingInfo = _G.UnitCastingInfo
local GetNumTalentTabs = _G.GetNumTalentTabs
local GetNumTalents = _G.GetNumTalents
local GetTalentInfo = _G.GetTalentInfo

-- Slam, rank one. Only the name is taken off it, and every rank of Slam shares
-- that name, so one id covers a warrior at level 30 and one at 70 and there is
-- no table of ranks to keep true.
local SLAM = 1464

-- What one point of Improved Slam takes off the cast, in seconds. The talent
-- is the same 0.1 per point on both of these clients. There is no API that
-- will say so: a talent's effect lives in its tooltip text and parsing that is
-- a worse dependency than this number. It is a seed for the first cast and
-- nothing more, because the measurement below replaces it.
local PER_POINT = 0.1

-- Half the width of the drawn band, in seconds.
--
-- The band exists because a person pressing a key lands within about a tenth
-- of a second of where they aimed, and a mark with no width is a mark you can
-- only hit by luck. Two tenths wide on a 3.4 second swing is six percent of
-- the bar, which is eleven pixels at the shipped width: big enough to aim at
-- and small enough that hitting it means something.
--
-- Symmetric, because the two ways of missing cost about the same. Early throws
-- away the charge you had; late pushes the swing out by what you clipped.
local HALF = 0.1

local name, nameKnown
local rank
local estimate
local measured

--------------------------------------------------------------------------
-- What Slam costs to cast
--------------------------------------------------------------------------

-- Forgotten on every event that could move any of the three, which is cheap
-- and rare. Everything below is a cache read on the tick.
function Slam.Forget()
	name, nameKnown, rank, estimate = nil, false, nil, nil
end

function Slam.Name()
	if not nameKnown then
		nameKnown = true
		name = ns.SpellName(SLAM)
	end
	return name
end

-- Points in Improved Slam, or zero. Walks the trees once per talent change and
-- allocates nothing while it does: the match is a plain substring test against
-- the name the client already holds.
function Slam.Rank()
	if rank then
		return rank
	end
	rank = 0
	local slam = Slam.Name()
	if not slam or type(GetNumTalentTabs) ~= "function"
		or type(GetNumTalents) ~= "function" or type(GetTalentInfo) ~= "function" then
		return rank
	end
	for tab = 1, GetNumTalentTabs() do
		for index = 1, GetNumTalents(tab) do
			local talent, _, _, _, points = GetTalentInfo(tab, index)
			if type(talent) == "string" and talent ~= slam
				and talent:find(slam, 1, true) and type(points) == "number" then
				rank = points
				return rank
			end
		end
	end
	return rank
end

-- The estimate, which is what the bar draws until the first Slam of the
-- session is cast. Floored at zero rather than allowed to go negative, because
-- a negative cast time puts the mark past the end of the bar.
function Slam.Estimate()
	if estimate then
		return estimate
	end
	-- Asked by id rather than by the name resolved above. Every rank of Slam
	-- casts in the same time, so rank one answers for a warrior at any level,
	-- and an id cannot collide with another spell the way a name can.
	local base = Slam.Name() and ns.SpellCastTime(SLAM) or 0
	estimate = base - Slam.Rank() * PER_POINT
	if estimate < 0 then
		estimate = 0
	end
	return estimate
end

-- What the client said the last real cast took, or nil before there has been
-- one. Handed out so the panel can say which of the two numbers is being drawn.
function Slam.Measured()
	return measured
end

function Slam.Cast()
	return measured or Slam.Estimate()
end

-- Whether this character has Slam at all. Warrior is asked first because
-- ns.SpellName answers for any spell id on any class and a hunter would
-- otherwise be told about a warrior's cast time.
function Slam.Known()
	return ns.IsWarrior() and Slam.Name() ~= nil and Slam.Cast() > 0
end

--------------------------------------------------------------------------
-- Where the mark goes
--------------------------------------------------------------------------

-- Whether the cast is longer than the swing it is meant to land at the end of.
-- A slow two hander is 3.4 seconds and a 1.5 second Slam fits inside it with
-- room to spare, so this is not the normal case. It is the case a fast weapon
-- and no Improved Slam gets to, and there the honest answer is that there is
-- no window: every press clips something and the mark would be a lie.
function Slam.Longer()
	local duration = ns.Swing.Speed(ns.Swing.MAIN)
	return duration > 0 and Slam.Cast() >= duration
end

-- The band, as three shares of the main hand swing: where it opens, where it
-- closes, and the exact press in the middle.
--
-- The arithmetic is the same sentence three times. A swing of D seconds drawn
-- as a bar has f of it spent, so the time left is D minus D times f. Setting
-- that equal to the cast time C and solving for f puts the press at (D - C)
-- over D, and the two edges of the band are the same with the half width added
-- and taken off. Early is the smaller f, because early means more swing left.
--
-- Nil when there is nothing to draw: another class, no swing speed yet, no
-- cast time yet, or a cast longer than the swing.
function Slam.Window()
	if not Slam.Known() then
		return nil
	end
	local duration = ns.Swing.Speed(ns.Swing.MAIN)
	local cast = Slam.Cast()
	if duration <= 0 or cast <= 0 or cast >= duration then
		return nil
	end
	local open = (duration - cast - HALF) / duration
	local close = (duration - cast + HALF) / duration
	local at = (duration - cast) / duration
	if open < 0 then
		open = 0
	end
	if close > 1 then
		close = 1
	end
	return open, close, at
end

-- Whether pressing Slam right now is the press the band is drawn for. Read on
-- the tick, so it does no client calls and builds nothing.
function Slam.Open()
	local open, close = Slam.Window()
	if not open or not ns.Swing.Armed(ns.Swing.MAIN) then
		return false
	end
	local spent = ns.Swing.Fraction(ns.Swing.MAIN)
	return spent >= open and spent <= close
end

--------------------------------------------------------------------------
-- What the client says about a cast in flight
--------------------------------------------------------------------------

-- The three shapes UNIT_SPELLCAST_* arrives in across these clients. The
-- modern one is unit, castGUID, spellID; the old one leads with the spell's
-- name. Rather than picking, every value that could carry the spell is tested
-- against the name, which costs three comparisons on a handful of events a
-- second and cannot be wrong about a client nobody here has run.
local function IsSlam(unit, a, b, c)
	if unit ~= "player" then
		return false
	end
	local slam = Slam.Name()
	if not slam then
		return false
	end
	if a == slam or b == slam or c == slam then
		return true
	end
	if type(b) == "number" and ns.SpellName(b) == slam then
		return true
	end
	if type(c) == "number" and ns.SpellName(c) == slam then
		return true
	end
	return false
end

-- The cast the server actually started, in seconds. This is the number the
-- estimate above is only trying to guess, and it arrives on the first Slam of
-- every session.
local function Learn()
	if type(UnitCastingInfo) ~= "function" then
		return
	end
	local _, _, _, startTime, endTime = UnitCastingInfo("player")
	if type(startTime) ~= "number" or type(endTime) ~= "number" then
		return
	end
	local taken = (endTime - startTime) / 1000
	if taken > 0 then
		measured = taken
	end
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("CHARACTER_POINTS_CHANGED")
-- Filtered to the player where the client can filter. Unfiltered, these two
-- carry every cast every unit in range starts and finishes, which in a raid is
-- a great many events reaching a handler whose first line is "not you".
if type(events.RegisterUnitEvent) == "function" then
	events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
	events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
else
	events:RegisterEvent("UNIT_SPELLCAST_START")
	events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end
events:SetScript("OnEvent", function(_, event, unit, a, b)
	if event == "UNIT_SPELLCAST_START" then
		if IsSlam(unit, a, b) then
			Learn()
		end
		return
	end

	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		-- The restart, which is the reason a warrior's timer cannot be built
		-- out of the combat log alone. A completed Slam starts the swing again
		-- on this client, and nothing in the log says so: the next event you
		-- would see is the swing that lands a full weapon speed later, and a
		-- timer that waited for it would draw the whole of that swing wrong.
		if IsSlam(unit, a, b) then
			ns.Swing.Start(ns.Swing.MAIN)
		end
		return
	end

	-- A respec moves the talent, so the measurement taken before it is a
	-- reading of a cast this character no longer has. Dropped here and not on
	-- SPELLS_CHANGED, which fires whenever anything is learned and would throw
	-- away a good number to no purpose.
	if event == "CHARACTER_POINTS_CHANGED" then
		measured = nil
	end
	Slam.Forget()
end)
