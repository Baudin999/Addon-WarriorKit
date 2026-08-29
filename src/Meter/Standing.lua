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
})
