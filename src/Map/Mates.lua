local ADDON, ns = ...

local Mates = {}
ns.MapMates = Mates

--------------------------------------------------------------------------
-- Everyone else in your group, on the map
--
-- The one thing on a world map that no database can answer and no addon can
-- work out: where the four people you are playing with are standing right now.
-- Blizzard's own map has drawn it since the first client, this one had a column
-- of every zone in the game and no way to see that the healer is still at the
-- flight master, and a party map that cannot say where the party is is a map
-- you go back to the client's own for.
--
-- **The client places them, not this file.** It answers where a member is
-- standing in the continent's own yards, and it turns those yards into a
-- fraction of whatever map it is handed; both calls answer for your party and
-- your raid. That is the whole mechanism, and it is two calls rather than the
-- one the arrow uses because this client answers that one for you alone. The
-- alternative is what the libraries do: read the yards and carry a table of
-- every zone's rectangle to divide them by. That table is the thing that goes
-- stale, and there is no reason to keep one when the client will do the
-- arithmetic. UI/Chart.lua carries the calls and the order the yards go in.
--
-- It is also what makes the continent picture work for nothing. Ask about a
-- zone and you get the people standing in that zone; ask about Kalimdor and you
-- get everybody who is anywhere on Kalimdor, each at their place on it. Neither
-- case is written here.
--
-- **A member the client will not place is a mark with nowhere to be, not a
-- mark that does not exist.** There are four ordinary ways to be unplaceable:
-- in an instance, on another continent, on a map that is not the one being
-- drawn, and offline. All four come back the same way, as no answer.
--
-- The point is still handed over, with no place on it, and the board hides it
-- until there is one. That is what makes the picture live in both directions.
-- The board takes every point carrying a unit again ten times a second, so a
-- member who walks out of the zone loses their mark within the tick, and one
-- who walks in gets theirs the same way. Handing over only the members who
-- happened to be here at the moment the map was painted made the first of those
-- work and the second wait for the next repaint, which on a window you have
-- open and are watching is the whole of what you opened it for.
--
-- Mates.Describe is what tells you the difference between "nobody is here" and
-- "this client would not say", because those look identical on the map and are
-- not the same fault.
--
-- **Class colour, because the question is which one of them.** A row of five
-- identical dots says the party is spread out, which you knew. The colour is
-- what makes the mark answer "the healer has not moved", and it is the same
-- colour the party frames, the meter and the chat use for the same person.
--------------------------------------------------------------------------

local Chart = ns.UI.Chart
local Color = ns.Unit.Color

-- How big a person is drawn.
--
-- Two pixels over the nine a quest camp gets. A camp is one of forty things on
-- a busy zone and a person is one of four, and the two want different weights:
-- the point of a party mark is that you find it without looking for it. Still
-- well under Questie's fourteen pixel icons, because a mark that is bigger than
-- the art it is standing on is a mark that hides the place it is answering
-- about.
local FRIEND = 11

-- The most people one map is drawn with. A full raid, which is the most the
-- client will ever answer for.
local CROWD = 40

--------------------------------------------------------------------------

-- One member, where the client will place them and not otherwise.
--
-- You are skipped, because you are already on the picture as the client's own
-- arrow and a square drawn under it would only say where the arrow is. Asked by
-- token rather than by name: UnitIsUnit is the one call that answers "is this
-- row me" in a raid, where you are a numbered token like everybody else.
local function Take(into, unit, map)
	if not UnitExists(unit) or UnitIsUnit(unit, "player") then
		return false
	end
	local x, y = Chart.Spot(map, unit)
	into[#into + 1] = {
		x = x, y = y, kind = Chart.MATE, unit = unit,
		tint = Color.OfUnit(unit), size = FRIEND,
		name = UnitName(unit) or "somebody in your group",
		-- The coordinate, for the reason every other mark on this map carries
		-- one rather than a distance: a distance is the number that goes stale
		-- the moment either of you walks, and a coordinate is what you type into
		-- the thing everybody already has open.
		--
		-- The line for somebody with nowhere to be is never read, because the
		-- board hides a mark with no place. It is written anyway: the mark is
		-- shown by the tick rather than by a repaint, and the tick writes a
		-- coordinate and nothing else.
		note = x and ("%.1f, %.1f"):format(x, y) or "not on this map",
	}
	return x ~= nil
end

-- Everybody in your group, as points the chart draws, and how many of them the
-- client put somewhere on this map.
--
-- An empty list means you are on your own. A list with nothing placed in it has
-- three readings: they are all somewhere else, they are all in an instance, or
-- this client will not place a party member at all. Mates.Describe separates
-- the last from the other two.
function Mates.On(map)
	local out, placed = {}, 0
	if type(map) ~= "number" then
		return out, placed
	end
	local raid = IsInRaid()
	local held = raid and math.min(GetNumGroupMembers() or 0, CROWD) or 4
	for index = 1, held do
		if Take(out, (raid and "raid" or "party") .. index, map) then
			placed = placed + 1
		end
	end
	return out, placed
end

-- How many people are with you, you not counted.
function Mates.Held()
	if IsInRaid() then
		return math.max((GetNumGroupMembers() or 0) - 1, 0)
	end
	local held = 0
	for index = 1, 4 do
		if UnitExists("party" .. index) then
			held = held + 1
		end
	end
	return held
end

function Mates.Describe()
	local held = Mates.Held()
	if held == 0 then
		return "you are on your own, so there is nobody else to draw"
	end
	local here = Chart.Here()
	local _, placed = Mates.On(here)
	if placed == 0 then
		return ("%d with you, and the client placed none of them on the zone you are in")
			:format(held)
	end
	return ("%d with you, %d of them on the zone you are in"):format(held, placed)
end
