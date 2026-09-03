local ADDON, ns = ...

local Meter = {}
ns.Meter = Meter

--------------------------------------------------------------------------
-- Damage and healing, out of the combat log
--
-- Nothing in either client totals a fight for you. The combat log is the whole
-- source, one event per swing per mob per member of the group, and every meter
-- ever written for Classic is a loop over it. This is the small version of
-- that loop: two numbers per player, no spell breakdown, no per-target split
-- and no history past the fight you are in.
--
-- What a segment is. It opens when combat starts and closes when it drops, and
-- the numbers stay on screen after it closes until the next one opens. Opening
-- on the log rather than only on PLAYER_REGEN_DISABLED matters in a group: the
-- pull is often somebody else's, and a meter that starts its clock when *you*
-- get hit reads every puller as having done their first four seconds of damage
-- instantly.
--
-- What the denominator is. One clock for the whole segment, shared by every
-- row. Details gives each player their own activity time, which flatters
-- whoever stopped early and is the right answer for "how hard did they hit
-- while they were hitting"; this answers "what did they contribute to this
-- fight", which is the question a five second pull actually has. It is also
-- the only version where the rows add up to the total, and rows that do not
-- add up are rows that get argued about.
--
-- Effective healing only. Overheal is subtracted, because a healer who lands
-- 40k of heals into a full health bar has healed nothing, and a meter that
-- says otherwise is a meter people learn to ignore.
--
-- Effective damage only, for exactly the same reason. A 5,000 hit on a mob
-- with 100 health left does 100 damage and wastes 4,900, and the client hands
-- that 4,900 over as a separate number so it can be taken off. The usual
-- answer is to keep it, which is why in most meters the killing blow moves
-- somebody up the chart: they are being paid for health the mob did not have.
-- Overheal is not counted here and overkill is not either, because a meter
-- that runs one rule down the healing column and the opposite one down the
-- damage column cannot be read across.
--------------------------------------------------------------------------

-- The subevents that carry a number worth adding, and which slot it lands in.
-- A table lookup rather than a chain of comparisons: the log delivers a few
-- hundred of these a second in a raid and this is the first line of the
-- handler.
--
-- Overkill is always the slot after the amount, on every one of these and on
-- a heal's overheal too, so the table only has to carry the one index.
local DAMAGE = {
	SWING_DAMAGE = 12,
	RANGE_DAMAGE = 15,
	SPELL_DAMAGE = 15,
	SPELL_PERIODIC_DAMAGE = 15,
	SPELL_BUILDING_DAMAGE = 15,
	DAMAGE_SHIELD = 15,
	DAMAGE_SPLIT = 15,
}

local HEAL = {
	SPELL_HEAL = true,
	SPELL_PERIODIC_HEAL = true,
}

-- Reused for as long as the client runs, one per GUID that has ever appeared
-- in a segment. Zeroed at the start of the next one rather than thrown away,
-- so the steady state allocates nothing at all: a fight in the same group is
-- the same set of tables written over.
local slots = {}
local list = {}    -- every slot with something in it this segment
local ranked = {}  -- the same slots, sorted, handed to the window

local startedAt, endedAt
local running = false
local rankMode = "dps"

--------------------------------------------------------------------------

local function Slot(guid)
	local slot = slots[guid]
	if not slot then
		slot = { guid = guid, damage = 0, healing = 0, active = false }
		slots[guid] = slot
	end
	if not slot.active then
		slot.active = true
		list[#list + 1] = slot
	end
	return slot
end

function Meter.Start()
	for index = 1, #list do
		local slot = list[index]
		slot.damage, slot.healing, slot.active = 0, 0, false
		list[index] = nil
	end
	ns.Unit.Roster.Build()
	startedAt, endedAt = GetTime(), nil
	running = true
end

function Meter.Stop()
	if not running then
		return
	end
	running = false
	endedAt = GetTime()
end

function Meter.Running()
	return running
end

-- How long the segment on screen has been going, floored at a second so the
-- first swing of a fight is not divided by a hundredth and reported as four
-- million damage a second.
function Meter.Elapsed()
	if not startedAt then
		return 0
	end
	local stop = endedAt or GetTime()
	local taken = stop - startedAt
	return taken > 1 and taken or 1
end

-- Nothing has happened yet, which is a different state from a fight where
-- everyone did nothing: the window draws its headers either way but has no
-- rows to put under them.
function Meter.Idle()
	return startedAt == nil or #list == 0
end

--------------------------------------------------------------------------
-- The log
--------------------------------------------------------------------------

-- Whether anyone is actually fighting, asked of the player and of whoever the
-- damage belongs to. This is what stops a segment being opened by the tail of
-- the last one: a bleed that ticks twice after the mob is down would otherwise
-- wipe the fight you are still reading and replace it with two ticks.
--
-- Asking about the source as well as about yourself is the pull. Somebody else
-- opens, their arrow lands, they are in combat and you are not yet, and a meter
-- that waited for your own combat flag would start its clock late and read the
-- puller as having done four seconds of damage in no time at all.
local function Fighting(owner)
	if UnitAffectingCombat("player") then
		return true
	end
	local unit = ns.Unit.Roster.UnitFor(owner)
	return unit ~= nil and UnitAffectingCombat(unit)
end

local function Record(guid, damage, healing)
	local owner = ns.Unit.Roster.Owner(guid)
	if not owner then
		return
	end
	if not running then
		if not Fighting(owner) then
			return
		end
		Meter.Start()
	end
	local slot = Slot(owner)
	slot.damage = slot.damage + damage
	slot.healing = slot.healing + healing
end

-- The sixteen values this file reads, in the order ns.CombatLog hands them over,
-- which is the client's own. The blanks are on purpose: naming the values this
-- file does not use would be more chances to shift the ones it does.
local function OnLog(_, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _,
	arg12, arg13, _, arg15, arg16)
	local at = DAMAGE[subevent]
	if at then
		local amount = (at == 12) and arg12 or arg15
		-- The client sends minus one here on every hit that killed nothing,
		-- which is nearly every hit, so what is tested below is the sign and
		-- not just the type. Subtracting a minus one would hand back more
		-- damage than was dealt.
		local wasted = (at == 12) and arg13 or arg16
		if type(amount) == "number" and amount > 0 then
			if type(wasted) == "number" and wasted > 0 then
				amount = amount - wasted
			end
			if amount > 0 then
				Record(sourceGUID, amount, 0)
			end
		end
		return
	end

	if HEAL[subevent] then
		local amount = type(arg15) == "number" and arg15 or 0
		local overheal = type(arg16) == "number" and arg16 or 0
		local landed = amount - overheal
		if landed > 0 then
			Record(sourceGUID, 0, landed)
		end
		return
	end

	-- A totem, a Water Elemental, an Eye of Kilrogg. None of them is a pet unit
	-- and no unit token ever points at one, so the summon is the only place the
	-- client says whose it is.
	if subevent == "SPELL_SUMMON" then
		ns.Unit.Roster.Own(destGUID, sourceGUID)
	end
end

--------------------------------------------------------------------------
-- Reading it back
--------------------------------------------------------------------------

-- The divisor, and never zero.
--
-- Meter.Elapsed answers 0 before the first fight of the session, which is the
-- right answer to "how long has this been going" and a catastrophic one to
-- divide by. Lua's 0/0 is a nan, the nan survives math.floor, and the client's
-- string.format turns it into -9223372036854775808, which is what the damage
-- pane's header read at every login until this existed.
local function Seconds()
	local taken = Meter.Elapsed()
	return (taken > 0) and taken or 1
end

function Meter.Amount(slot, mode)
	if not slot then
		return 0
	end
	return (mode == "hps") and slot.healing or slot.damage
end

function Meter.Rate(slot, mode)
	return Meter.Amount(slot, mode) / Seconds()
end

-- What the whole group is doing, which is the figure the pane header carries.
-- Summed over the rows rather than counted separately, so the header and the
-- rows can never disagree.
function Meter.Total(mode)
	local total = 0
	for index = 1, #list do
		total = total + Meter.Amount(list[index], mode)
	end
	return total / Seconds()
end

local function Bigger(a, b)
	local left = (rankMode == "hps") and a.healing or a.damage
	local right = (rankMode == "hps") and b.healing or b.damage
	if left == right then
		return a.guid < b.guid -- a stable order, so equal rows do not swap
	end
	return left > right
end

-- The slots with something in them, biggest first. Fills and sorts an array it
-- already owns, so a tick that ranks eight players allocates nothing.
function Meter.Rank(mode)
	rankMode = mode
	local count = 0
	for index = 1, #list do
		local slot = list[index]
		local total = (mode == "hps") and slot.healing or slot.damage
		if total > 0 then
			count = count + 1
			ranked[count] = slot
		end
	end
	for index = #ranked, count + 1, -1 do
		ranked[index] = nil
	end
	table.sort(ranked, Bigger)
	return ranked
end

--------------------------------------------------------------------------

-- On the log while the switch is on and off it entirely while it is not.
--
-- This file used to register the event at load whatever the setting said, so a
-- player with the meters switched off paid an unpack of every combat log line
-- in the zone to total damage nothing was going to draw. Comfort/Thanks.lua is
-- the part that had this right first.
function Meter.Apply()
	if ns.db and ns.db.meter then
		ns.CombatLog.Subscribe(OnLog)
	else
		ns.CombatLog.Unsubscribe(OnLog)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		if not running then
			Meter.Start()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		Meter.Stop()
	else
		Meter.Apply()
	end
end)
