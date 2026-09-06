local ADDON, ns = ...

local Here = {}
ns.QuestHere = Here

--------------------------------------------------------------------------
-- Where you are standing
--
-- One question with one answer, asked once and held until you walk out of it:
-- which map you are on, what the client calls it, whether it is an instance,
-- and which area id Questie's database files it under. The quest tracker
-- scopes itself on it and the map window will read the same table rather than
-- asking the client a second time.
--
-- In Core rather than in Quests because two trees want it. A part may not name
-- a file outside its own tree, so an answer both Quests and Map need is either
-- a shared file down here or two files drifting apart, and two readings of
-- where you are standing is the shape that put the same zone in two windows
-- under two names once already.
--
-- **It is answered off the map id and never off a name.** Dungeons/Here.lua
-- argues this at length and is right about it: GetInstanceInfo hands back
-- Blizzard's own name for a place rather than the book's, and hands it back in
-- the player's language. Eight of the forty dungeons are filed under a
-- different name from the one the book uses, so matching English text is a
-- feature that works on one client in ten. Every join below is a number.
--
-- The name that does come back is for drawing and for the one match the client
-- itself makes: the quest log's header is the client's own zone string, so a
-- tracker comparing a header against this name is comparing two strings the
-- same client wrote, in the same language, on the same tick. That is the only
-- honest use of it, and nothing here decides anything on it.
--
-- **The dungeon flag is IsInInstance and not the book.** Dungeons/Here.lua
-- answers a narrower question: which of the forty dungeons the book has a
-- picture of you are standing in, which is nothing for a raid, nothing for a
-- battleground and nothing for an instance the book skipped. A caller that
-- wants to go quiet indoors wants all of those, and delegating there would go
-- quiet in Scholomance and speak in Karazhan.
--
-- It cannot delegate there either way. scripts/trees.lua closes the base: Core
-- is a tree everything may name, so Core may not name a feature back, and
-- Core -> ns.DungeonHere fails that rule with no allow-list entry able to
-- excuse it. The rule is right, and IsInInstance is the better answer anyway.
--
-- Questie's ZoneDB is the fallback, for the client that will not say. It knows
-- a dungeon by area id, off the same table the quest database is keyed on, and
-- it is a number as well.
--
-- **Questie may be absent, and every field but the map degrades to nothing.**
-- The database also compiles minutes after login rather than at load, so an
-- area id asked for too early comes back nothing and would otherwise be held
-- for as long as you stand still. An answer with no area id is therefore only
-- held for a few seconds, which heals when Questie finishes and costs one
-- table lookup a second in the worst case.
--------------------------------------------------------------------------

-- Long enough that standing in a zone is one question, short enough that a
-- database compiling behind you is picked up on the walk back to the flight
-- master.
local RETRY = 5.0

local held, heldMap, heldAt

-- Which map you are on, through the reader the map window and the chart column
-- already go through rather than a third probe of the client.
local function Map()
	local chart = ns.UI and ns.UI.Chart
	if not chart or type(chart.Here) ~= "function" then
		return nil
	end
	return (chart.Here())
end

-- The area id Questie's database keys on, and the zone above it, or nothing.
--
-- **The pcall is not decoration.** ZoneDB:GetAreaIdByUiMapId falls through to a
-- scan by name and then calls error() outright for a map it has no row for, so
-- a bare call on the wrong map id takes the whole frame down with it. Read the
-- function on disk before shortening this.
--
-- Both are colon methods on the module and take the module as self.
-- ZoneDB.IsDungeonZone below is not, which is the one place the three
-- disagree.
local function Join(map)
	local zones = ns.Questie("ZoneDB", "GetAreaIdByUiMapId", "GetParentZoneId")
	if not zones then
		return nil
	end
	local found, area = pcall(zones.GetAreaIdByUiMapId, zones, map)
	if not found or type(area) ~= "number" then
		return nil
	end
	local climbed, parent = pcall(zones.GetParentZoneId, zones, area)
	if not climbed or type(parent) ~= "number" then
		return area, nil
	end
	return area, parent
end

-- Whether the place around you is an instance. The client's own answer first,
-- because it is exact and needs nothing installed, and Questie's table for the
-- client that does not carry the call.
local function Instanced(area)
	if type(_G.IsInInstance) == "function" then
		local ok, inside = pcall(_G.IsInInstance)
		if ok and type(inside) == "boolean" then
			return inside
		end
	end
	if type(area) ~= "number" then
		return false
	end
	local zones = ns.Questie("ZoneDB", "IsDungeonZone")
	if not zones then
		return false
	end
	local ok, dungeon = pcall(zones.IsDungeonZone, area)
	return ok and dungeon == true
end

--------------------------------------------------------------------------

-- The place you are standing in, or nothing at all on a client that will not
-- say which map you are on.
--
--   map      the ui map id, always a number
--   name     what this client calls that map, in the player's own language,
--            or nothing where it will not name it
--   dungeon  whether you are inside an instance, always a boolean
--   area     Questie's area id for that map, or nothing without Questie
--   parent   the area id of the zone above it, or nothing for a zone that is
--            already the top of its own tree
--
-- The table is the held one and not a copy. Nothing writes to it, and a caller
-- that does is writing into everybody else's answer.
function Here.Now()
	local map = Map()
	if type(map) ~= "number" then
		return nil
	end
	if held and heldMap == map
		and (held.area ~= nil or (GetTime() - heldAt) < RETRY) then
		return held
	end
	local chart = ns.UI and ns.UI.Chart
	local area, parent = Join(map)
	held = {
		map = map,
		name = chart and chart.Name(map) or nil,
		dungeon = Instanced(area),
		area = area,
		parent = parent,
	}
	heldMap, heldAt = map, GetTime()
	return held
end

-- The held answer dropped, for the harness and for anything that has to see
-- the join happen. Nothing in the addon calls it: walking into a new map is
-- what expires it.
function Here.Forget()
	held, heldMap, heldAt = nil, nil, nil
end

function Here.Describe()
	local at = Here.Now()
	if not at then
		return "the client will not say which map you are standing on"
	end
	return ("standing in %s, map %d, %s%s"):format(
		at.name or "a place this client will not name", at.map,
		at.area and ("area " .. at.area)
			or "and Questie has no area id for it",
		at.dungeon and ", which is a dungeon" or "")
end
