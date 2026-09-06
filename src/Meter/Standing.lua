local ADDON, ns = ...

local C = ns.UI.Color
local Shade = ns.Unit.Color.threat
local Threat = ns.Unit.Threat

--------------------------------------------------------------------------
-- Where you stand on it, on any tooltip in the addon
--
-- The threat pane in Meter/Window.lua answers this for one mob: the one you
-- have targeted, as a table of everybody in the group, updated on a ticker. It
-- is the right readout for the pull you are in and it is the wrong one for the
-- question you ask by pointing at something across the room, which is not "how
-- fast is everyone gaining" but "if I look away from what I am holding and
-- swing at that instead, whose is it".
--
-- So this is one line, on every hover of a creature, wherever the pointer found
-- it: out in the world, on a nameplate, on the target frame. It is registered
-- against UI/Tip.lua's unit kind rather than written into the part that opens
-- that box, which is the whole point of the registry. World/World.lua knows how
-- to put a tooltip on a mob and knows nothing about threat; this file knows
-- about threat and nothing about hovering. Feeds/Worth.lua is the same shape
-- one kind over, and for the same reason: the loot feed used to be the only
-- place in the game the addon would tell you what a drop was worth.
--
-- **The two clients answer two different questions and the line says which.**
-- TBC has a threat API and the answer is a percentage of whoever is holding the
-- mob. Classic Era has nothing at all: no call in that client computes threat,
-- which is why every Era threat meter parses the combat log. What is left there
-- is who the mob is actually swinging at, which cannot warn you before it turns
-- and can only tell you after. Both are true sentences and neither is dressed
-- up as the other.
--------------------------------------------------------------------------

-- What the mob is doing, on a client that will not say who is winning.
local function Swinging(unit)
	local tone, victim, mine = Threat.Swinging(unit)
	if not victim then
		return { "Threat", "not swinging at anybody", tone = C.quiet }
	end
	if mine then
		return { "Threat", "swinging at you", tone = tone }
	end
	return { "Threat", "swinging at " .. (UnitName(victim) or "somebody"), tone = tone }
end

-- The percentage, on a client that keeps one.
--
-- Four states and the colour carries the same meaning it carries on an enemy
-- bar, because Unit/Threat.lua decides it for both and a hover that put amber
-- somewhere a bar put green would be the addon disagreeing with itself.
--
-- The idle colour is compared by identity rather than asked for, because
-- Threat.State answers a percentage of nil for two different reasons: you hold
-- the mob and nobody is near you, and the mob has never heard of you. Those are
-- the same two returns and opposite sentences.
local function Standing(unit)
	local tone, percent, challenger = Threat.State(unit)
	if not tone then
		return nil
	end
	if tone == Shade.idle then
		return { "Threat", "nothing on it yet", tone = C.quiet }
	end
	if not percent then
		return { "Threat", "yours, and nobody is close", tone = tone }
	end
	if challenger then
		return { "Threat", ("%s is at %d%%"):format(UnitName(challenger) or "somebody", percent),
			tone = tone }
	end
	return { "Threat", ("theirs, you are at %d%%"):format(percent), tone = tone }
end

ns.Tip.Source({
	name = "where you stand on it",
	kind = "unit",
	band = "extra",
	order = 20,
	-- Nothing at all about a unit you cannot fight. Threat on a quest giver is
	-- not a number that means anything, and a line reading "not swinging at
	-- anybody" under every innkeeper in the game is the sort of noise that makes
	-- a player turn the whole hover off.
	fill = function(subject)
		local unit = subject.unit
		if type(unit) ~= "string" or not UnitExists(unit) then
			return nil
		end
		if not UnitCanAttack("player", unit) then
			return nil
		end
		if not Threat.Ready() then
			return Swinging(unit)
		end
		return Standing(unit)
	end,
	-- What makes this line move, for UI/Fresh.lua. It is the only line in the
	-- addon that changes on its own while you are reading it: a pull runs for
	-- half a minute and the percentage under the pointer was true on the frame
	-- you arrived and false a second later.
	--
	-- Floored to the whole percent because that is what the line prints. Threat
	-- wanders continuously and `%d%%` does not, so a mob whose share drifts
	-- between 61.2 and 61.8 is one stamp and no rebuild, and the box is built
	-- again exactly as often as a digit on screen changes.
	--
	-- The two states with no percentage are numbers of their own rather than a
	-- shared nil, because "nothing on it yet" and "yours, and nobody is close"
	-- are opposite sentences that both come back without a figure, and a stamp
	-- that could not tell them apart would leave the wrong one on screen for as
	-- long as you looked at the mob.
	--
	-- On Era it is who the mob is swinging at, by GUID, which is exactly what
	-- that client's half of the line says. What neither half catches is a
	-- challenger changing while their share rounds to the same whole number:
	-- the name moves and the digit does not. A stamp catches what it names.
	stamp = function(subject)
		local unit = subject.unit
		if type(unit) ~= "string" or not UnitExists(unit) then
			return nil
		end
		if not UnitCanAttack("player", unit) then
			return nil
		end
		if not Threat.Ready() then
			local _, victim = Threat.Swinging(unit)
			return victim and UnitGUID(victim) or false
		end
		local tone, percent = Threat.State(unit)
		if not tone or tone == Shade.idle then
			return -1
		end
		if not percent then
			return -2
		end
		return math.floor(percent)
	end,
})
