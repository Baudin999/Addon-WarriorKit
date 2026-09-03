local ADDON, ns = ...

local Swing = {}
ns.Swing = Swing

--------------------------------------------------------------------------
-- When the next swing lands
--
-- The client will tell you how long a swing takes and will not tell you where
-- in one you are standing. There is no event for a swing starting, no timer to
-- read and nothing on the player that moves with it. What there is is the
-- combat log: every landed swing and every missed one arrives as an event with
-- you as the source, and a swing landing is the same instant the next one
-- starts. So the log is the clock and UnitAttackSpeed is the length of a tick.
--
-- That is the whole mechanism and it has two consequences worth stating.
--
-- The timer is blind until you have swung once. A fight opens with the bar
-- empty and fills from the first white hit, which is correct rather than a
-- gap: before that swing there is no swing in progress to draw.
--
-- And a swing that is dodged, parried, missed or blocked still lands as far as
-- the timer is concerned, because SWING_MISSED is the server saying the swing
-- happened and did nothing. A timer that only listened for damage would stop
-- dead against a mob you cannot hit.
--
-- Which hand swung is a flag on the event and not a separate subevent. It is
-- the last value of SWING_DAMAGE and the second value of SWING_MISSED, which
-- are different positions for the same fact, so both are read by index and
-- neither is guessed. Reading the wrong slot gives an off hand timer that
-- never runs and a main hand timer that runs twice as fast, which looks like a
-- haste bug rather than like a parser bug.
--
-- Haste moves the length of the tick under a tick already in flight. The
-- server scales what is left of the swing by the ratio of the two speeds
-- rather than restarting it, so Flurry landing at the halfway mark leaves you
-- halfway through a shorter swing, and Retime does the same arithmetic. A
-- timer that ignored this is wrong for a warrior in every fight, because
-- Flurry is up for most of them.
--------------------------------------------------------------------------

-- Probed rather than named in .luacheckrc, the same way Meter/Spec.lua reaches
-- the talent API. Nothing installed on this machine calls either of these
-- unguarded, so neither is proven the way the README asks a read_globals entry
-- to be proven, and a swing timer that raises twenty times a second is worse
-- than a swing timer that says it cannot read the client.
local UnitAttackSpeed = _G.UnitAttackSpeed
local OffhandHasWeapon = _G.OffhandHasWeapon

Swing.MAIN = "main"
Swing.OFF = "off"

-- Two records, made once at load and written in place forever after. The tick
-- reads them forty times a second and a swing timer that built a table per
-- swing would be the shape check.sh's allocation gate exists to refuse.
--
--   at        when this swing started, on the client's own clock
--   duration  how long it is, which is the speed it started at
--   speed     what UnitAttackSpeed says now, which is not always the above
--   running   whether a swing has ever been seen for this hand this fight
local hands = {
	main = { at = 0, duration = 0, speed = 0, running = false },
	off  = { at = 0, duration = 0, speed = 0, running = false },
}

--------------------------------------------------------------------------
-- What the client says
--------------------------------------------------------------------------

function Swing.Ready()
	return type(UnitAttackSpeed) == "function"
end

-- The second return is nil on a client with nothing in the off hand and is
-- also nil with a shield there, which is the answer this wants: a shield does
-- not swing. OffhandHasWeapon is asked first where it exists, because it
-- answers the question directly rather than by implication.
function Swing.HasOffhand()
	if type(OffhandHasWeapon) == "function" then
		return OffhandHasWeapon() and true or false
	end
	if not Swing.Ready() then
		return false
	end
	local _, off = UnitAttackSpeed("player")
	return type(off) == "number" and off > 0
end

-- Whether there is anything in the main hand at all.
--
-- This is the gate on drawing the bars, and it is deliberately a weapon rather
-- than a class. A swing timer is worth the same to a rogue and to a hunter who
-- is standing in melee; what is warrior only is the Slam mark drawn on top of
-- it. Unarmed is a real 2.0 second swing and the client reports a speed for
-- it, so asking the speed would draw a bar for a hunter shooting from thirty
-- yards, which is a bar about nothing.
function Swing.HasMainhand()
	return GetInventoryItemLink("player", ns.Gear.MAINHAND) ~= nil
end

local function Speeds()
	if not Swing.Ready() then
		return nil, nil
	end
	local main, off = UnitAttackSpeed("player")
	if type(main) ~= "number" or main <= 0 then
		main = nil
	end
	if type(off) ~= "number" or off <= 0 or not Swing.HasOffhand() then
		off = nil
	end
	return main, off
end

--------------------------------------------------------------------------
-- Reading a hand back
--------------------------------------------------------------------------

function Swing.Speed(which)
	local hand = hands[which]
	return hand and hand.speed or 0
end

-- How long the swing being drawn is, which is not always what the client says
-- the weapon's speed is.
--
-- Fraction divides the time spent by hand.duration, and anything drawing a mark
-- on that bar has to divide by the same number or the mark and the fill are
-- answers to two different questions. Retime keeps duration equal to speed
-- today; this exists so that a caller in another file does not have to know
-- that, because the day the two come apart is the day the Slam mark lands a
-- pixel off and nothing says why.
--
-- Falls back to the speed while no swing is running, so a bar that has never
-- been armed still has a length to mark up.
function Swing.Duration(which)
	local hand = hands[which]
	if not hand then
		return 0
	end
	if hand.running and hand.duration > 0 then
		return hand.duration
	end
	return hand.speed
end

function Swing.Armed(which)
	local hand = hands[which]
	return hand ~= nil and hand.running and hand.duration > 0
end

-- Seconds until the swing lands, floored at zero. A swing whose time is up and
-- whose landing has not reached the log yet reads as zero rather than as a
-- negative number, because the bar behind this is drawn full at zero and would
-- be drawn past its own end at anything less.
function Swing.Remaining(which)
	if not Swing.Armed(which) then
		return 0
	end
	local hand = hands[which]
	local left = hand.at + hand.duration - GetTime()
	return left > 0 and left or 0
end

-- How much of the swing is spent, from 0 to 1, which is what the gauge draws.
function Swing.Fraction(which)
	if not Swing.Armed(which) then
		return 0
	end
	local hand = hands[which]
	local spent = (GetTime() - hand.at) / hand.duration
	if spent < 0 then
		return 0
	end
	return spent < 1 and spent or 1
end

--------------------------------------------------------------------------
-- Moving a hand
--------------------------------------------------------------------------

-- A swing landed, so the next one starts now. Public because two other things
-- start a main hand swing: a finished Slam, and scripts/harness.lua driving
-- the timer without a combat log to drive it with.
function Swing.Start(which)
	local hand = hands[which]
	if not hand then
		return false
	end
	if hand.speed <= 0 then
		Swing.Retime()
	end
	if hand.speed <= 0 then
		return false
	end
	hand.at, hand.duration, hand.running = GetTime(), hand.speed, true
	return true
end

-- The fight is over, or the hand is empty. The bar goes quiet rather than
-- running on: a swing timer still counting down after the mob is dead is a bar
-- telling you about a swing that is not coming.
function Swing.Stop(which)
	local hand = hands[which]
	if hand then
		hand.running = false
	end
end

-- Haste moved, or a weapon did. Both are the same arithmetic seen from
-- different ends and both come through here.
--
-- What is kept is the time left, scaled. A swing half spent at 3.4 seconds
-- that becomes a 2.4 second swing has 1.2 seconds left rather than 1.7, and a
-- timer that kept the elapsed instead would jump backwards every time Flurry
-- landed. Where the speed did not actually move, nothing is written at all, so
-- an aura event for somebody else's buff costs a comparison.
local function Rescale(hand, speed)
	if not speed then
		hand.speed, hand.duration, hand.running = 0, 0, false
		return
	end
	local was = hand.duration
	hand.speed = speed
	if not hand.running or was <= 0 then
		hand.duration = speed
		return
	end
	if was == speed then
		return
	end
	local now = GetTime()
	local left = (hand.at + was - now) * speed / was
	if left <= 0 then
		hand.running, hand.duration = false, speed
		return
	end
	hand.at, hand.duration = now + left - speed, speed
end

function Swing.Retime()
	local main, off = Speeds()
	Rescale(hands.main, main)
	Rescale(hands.off, off)
end

--------------------------------------------------------------------------
-- The log
--
-- Twenty-one values, because the off hand flag is the last of them on a
-- landed swing, and your own GUID after them, which is what ns.CombatLog adds
-- to the client's own list. Everything between is read as a blank on purpose:
-- naming the eight values this file does not use would be eight more chances to
-- shift the one it does.
--------------------------------------------------------------------------

local function OnLog(_, subevent, _, sourceGUID, _, _, _, _, _, _, _,
	_, missOffhand, _, _, _, _, _, _, _, damageOffhand, me)
	if sourceGUID ~= me then
		return
	end

	local offhand
	if subevent == "SWING_DAMAGE" then
		offhand = damageOffhand
	elseif subevent == "SWING_MISSED" then
		offhand = missOffhand
	else
		return
	end

	Swing.Start(offhand and Swing.OFF or Swing.MAIN)
end

--------------------------------------------------------------------------

-- On the log while the switch is on and off it entirely while it is not.
--
-- The swing bars ship off, and this file registered the event at load anyway,
-- so a player who never turned them on paid an unpack of every combat log line
-- in the zone to time a bar that was never drawn.
function Swing.Apply()
	if ns.db and ns.db.swing then
		ns.CombatLog.Subscribe(OnLog)
	else
		ns.CombatLog.Unsubscribe(OnLog)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
-- The three ways a swing changes length. The first is the client saying so and
-- is the one that ought to be enough. It is not: Flurry is an aura and the
-- attack speed event does not reliably follow one on these clients, which is
-- the single most common thing a warrior's swing timer gets wrong. So the
-- player's own aura changes are read too, and every one of them ends in a
-- comparison against the speed already held. The third is a weapon swap, which
-- this addon does itself from the loadout keys.
--
-- Filtered to the player where the client can filter, which is ns.RegisterUnitEvent
-- in Core. Unfiltered, UNIT_AURA is every aura on every unit in range, which in
-- a raid is thousands of events a fight reaching a handler that answers "not
-- you" to all but a handful.
ns.RegisterUnitEvent(events, "UNIT_ATTACK_SPEED", "player")
ns.RegisterUnitEvent(events, "UNIT_AURA", "player")
ns.RegisterUnitEvent(events, "UNIT_INVENTORY_CHANGED", "player")
events:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_REGEN_ENABLED" then
		Swing.Stop(Swing.MAIN)
		Swing.Stop(Swing.OFF)
		return
	end

	if event == "UNIT_ATTACK_SPEED" or event == "UNIT_AURA"
		or event == "UNIT_INVENTORY_CHANGED" then
		if unit == "player" then
			Swing.Retime()
		end
		return
	end

	Swing.Apply()
	Swing.Retime()
end)
