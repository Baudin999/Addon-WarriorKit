local ADDON, ns = ...

local ThreatMeter = {}
ns.MeterThreat = ThreatMeter

--------------------------------------------------------------------------
-- Threat on what you are looking at
--
-- The client already does the hard half. UnitDetailedThreatSituation's third
-- return is threat scaled against the amount needed to take the mob off
-- whoever is holding it: 100 means this player pulls, and the client has
-- already folded in the melee and ranged thresholds, the tank's own total and
-- every talent that moves either. Nothing here recomputes any of that. It
-- samples that one number per member and does two things the client will not.
--
-- It sorts, so the pane is a list rather than five separate questions.
--
-- And it differentiates. A percentage tells you where someone is; the rate of
-- change tells you where they are going, and where they are going is the whole
-- point of watching threat at all. 82% and falling is a rogue who stopped;
-- 82% and climbing four points a second is a rogue who takes the mob in four
-- and a half seconds, and you would like to know that now rather than then.
--
-- The rate is smoothed, because the raw one is unusable. Threat arrives in
-- lumps the size of a Sinister Strike and the denominator is a tank whose own
-- total steps up every swing, so two consecutive samples can differ by twenty
-- points in either direction. What is wanted is the trend across the last
-- couple of seconds, which is what an exponential average of half second
-- deltas is.
--
-- On a client with no threat API this whole file answers nothing and the pane
-- says so. Vanilla computes no threat at all, which is why every Classic
-- threat meter is a combat log simulation with a table of every spell's
-- coefficient in it. That is a different addon, and a wrong number here is
-- worse than an honest blank.
--------------------------------------------------------------------------

-- How often the reference sample moves, and how much of the new delta goes
-- into the average. Half a second is two ticks of the window's own clock, which
-- is long enough for a swing to land and short enough to see a taunt.
local SAMPLE = 0.5
local WEIGHT = 0.4

-- Past this, a projection is noise. Sixty seconds of "they overtake you
-- eventually" is not information, and every fight that lasts that long has had
-- a dozen things happen to threat in the meantime.
local HORIZON = 60

local slots = {}   -- guid -> slot, kept for as long as the client runs
local ranked = {}  -- the slots with threat on this target, sorted

local target        -- the GUID the samples below are about
local tanking       -- the slot holding the mob, or nil

--------------------------------------------------------------------------

local function Slot(guid)
	local slot = slots[guid]
	if not slot then
		slot = { guid = guid, pct = 0, rate = 0, eta = nil,
			markPct = 0, markAt = 0, tanking = false, live = false }
		slots[guid] = slot
	end
	return slot
end

-- Everything sampled so far is about a different mob. Not cleared to zero and
-- kept: a rate carried across a target switch is a rate measured between two
-- unrelated numbers, and it would draw a projection out of nothing.
local function Forget()
	for _, slot in pairs(slots) do
		slot.pct, slot.rate, slot.eta = 0, 0, nil
		slot.markPct, slot.markAt, slot.tanking, slot.live = 0, 0, false, false
	end
	tanking = nil
end

function ThreatMeter.Ready()
	return ns.HasThreat()
end

-- Whether there is anything to measure against. A friendly target, a corpse or
-- nothing at all are all the same answer, and the pane draws the reason rather
-- than an empty list.
function ThreatMeter.Watching()
	return UnitExists("target") and UnitCanAttack("player", "target")
		and not UnitIsDead("target")
end

--------------------------------------------------------------------------

-- One member, one sample. Split out of Update so the loop below is a loop and
-- so check.sh has a name to hold the arithmetic to.
local function Sample(unit, now)
	local guid = UnitGUID(unit)
	if not guid then
		return
	end

	local isTanking, status, pct = ns.Threat(unit, "target")
	local slot = Slot(guid)

	if status == nil or pct == nil then
		slot.live = false
		return
	end

	slot.live = true
	slot.tanking = isTanking and true or false
	slot.pct = pct

	if slot.tanking then
		tanking = slot
	end

	-- The reference moves on its own clock rather than every tick, so each
	-- delta is measured across enough time to mean something.
	--
	-- The first sample for a slot only plants the reference. Measuring against a
	-- mark of zero would divide this member's whole threat by however long the
	-- client has been running, which is a rate of about nothing and would be
	-- mistaken for a member who has stopped.
	local since = now - slot.markAt
	if slot.markAt == 0 then
		slot.markPct, slot.markAt = pct, now
	elseif since >= SAMPLE then
		local moved = (pct - slot.markPct) / since
		slot.rate = slot.rate * (1 - WEIGHT) + moved * WEIGHT
		slot.markPct, slot.markAt = pct, now
	end

	-- Whoever is holding the mob is not on their way to taking it off
	-- themselves, whatever the arithmetic says about the last half second.
	if slot.tanking or slot.rate <= 0 or pct >= 100 then
		slot.eta = nil
		return
	end
	local seconds = (100 - pct) / slot.rate
	slot.eta = (seconds <= HORIZON) and seconds or nil
end

function ThreatMeter.Update()
	if not ThreatMeter.Ready() then
		return
	end

	local guid = UnitGUID("target")
	if guid ~= target then
		target = guid
		Forget()
	end
	if not ThreatMeter.Watching() then
		return
	end

	local now = GetTime()
	tanking = nil
	local units = ns.Unit.Roster.Units()
	for index = 1, #units do
		Sample(units[index], now)
	end
end

--------------------------------------------------------------------------
-- Reading it back
--------------------------------------------------------------------------

local function Higher(a, b)
	if a.pct == b.pct then
		return a.guid < b.guid
	end
	return a.pct > b.pct
end

-- The members with threat on this mob, highest first. Same contract as
-- Meter.Rank: an array this file already owns, filled and sorted in place.
function ThreatMeter.Rank()
	local count = 0
	local units = ns.Unit.Roster.Units()
	for index = 1, #units do
		local slot = slots[UnitGUID(units[index]) or ""]
		if slot and slot.live then
			count = count + 1
			ranked[count] = slot
		end
	end
	for index = #ranked, count + 1, -1 do
		ranked[index] = nil
	end
	table.sort(ranked, Higher)
	return ranked
end

function ThreatMeter.Tanking()
	return tanking
end

-- Whoever takes the mob next and how long that is, or nil where nobody is
-- converging. This is the line the pane header carries, because it is the one
-- thing on the pane you would want shouted at you.
function ThreatMeter.Soonest()
	local soonest, when = nil, nil
	local rows = ThreatMeter.Rank()
	for index = 1, #rows do
		local slot = rows[index]
		if slot.eta and (when == nil or slot.eta < when) then
			soonest, when = slot, slot.eta
		end
	end
	return soonest, when
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent", function()
	target = UnitGUID("target")
	Forget()
end)
