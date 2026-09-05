local ADDON, ns = ...

local Unit = ns.Unit
local Role = {}
Unit.Role = Role

--------------------------------------------------------------------------
-- What role a unit is playing, on a client that has none
--
-- There is no role on 2.5.6 or on Era in the sense a later client means it.
-- Nothing on a character says "tank", the group finder's assignment is empty
-- for a group that formed itself, and a class is two or three answers at once.
-- So this is four sources read best first, and the last of them is a guess.
--
--   an override the player typed      wins over everything, because inspection
--                                     fails in the exact case where you already
--                                     know the answer: the friend standing next
--                                     to you who has just respecced
--   UnitGroupRolesAssigned            the group finder's own assignment, where
--                                     this client has the call and answers
--                                     something other than NONE
--   GetPartyAssignment("MAINTANK")    the raid's own main tank flag, which is
--                                     on both clients
--   the winning talent tree           through Unit/Spec.lua, mapped by the table
--                                     below
--   the class                         a warrior is damage, a priest is a healer
--
-- The floor is the part worth defending. A member with no slot until an inspect
-- lands is a frame that arrives late, and a frame that arrives late is a frame
-- that moves. Guessing from the class puts everybody somewhere at once and the
-- list settles over the first minute you are in a group.
--
-- Which is only true because of the rule in UnitFrames/Group.lua: the order is
-- recomputed out of combat and nowhere else. An inspect that resolves mid pull
-- is recorded here and changes nothing on the screen until the fight ends.
--------------------------------------------------------------------------

local TANK, HEALER, DPS = "tank", "healer", "dps"
Role.TANK, Role.HEALER, Role.DPS = TANK, HEALER, DPS

-- The order the bands are drawn in. Tanks first because they are the ones you
-- are standing behind, healers next because they are the ones you are covering,
-- damage last because there are the most of them and they are the band you look
-- at least.
local BAND = { [TANK] = 1, [HEALER] = 2, [DPS] = 3 }

-- Every talent tree in the game that is not damage, by class and by the index
-- the client files it under. Three trees per class and nine classes is twenty
-- seven entries, of which these seven are the only ones that need saying;
-- anything this table does not name is damage.
--
-- Indices rather than names, because a tree's name is localised and its index
-- is not, and Unit/Spec.lua already answers the index of whichever tree won.
--
-- SPEC-party.md's list said "shaman trees one and three". Tree one is Elemental
-- Combat, which is damage, so only tree three is here. Writing the tree's own
-- name beside each entry is what makes that kind of slip visible next time.
local TREES = {
	WARRIOR = { [3] = TANK },                    -- Protection
	PALADIN = { [1] = HEALER, [2] = TANK },      -- Holy, Protection
	PRIEST  = { [1] = HEALER, [2] = HEALER },    -- Discipline, Holy
	DRUID   = { [2] = TANK, [3] = HEALER },      -- Feral Combat, Restoration
	SHAMAN  = { [3] = HEALER },                  -- Restoration
}

-- What a class is before anyone has read its talents. One entry, because the
-- priest is the one class where the guess is worth making: most of them heal,
-- and a paladin or a druid at this point is as likely to be either. Everything
-- else is damage, which is the most common answer for every remaining class and
-- is the band with the most room in it.
local FLOOR = { PRIEST = HEALER }

-- The client's own words for an assigned role, in ours.
local ASSIGNED = { TANK = TANK, HEALER = HEALER, DAMAGER = DPS }

-- Blizzard's own art for the three, which is the art everyone in the group
-- already recognises. Cut as a grid of 67 pixel cells out of a 256 square
-- sheet, which is the grid GetTexCoordsForRole cuts the same file on: the
-- leader is the first cell, the tank is under it, the healer beside it and
-- damage on the diagonal.
--
-- 67 and not 75. The cell is 66 pixels of art with a gutter after it, so a 75
-- wide window keeps the whole icon and takes a slice of the two cells next to
-- it as well. On Anniversary the overspill lands on empty sheet and nobody
-- sees it; on Era there is art there, and a party tile came out as one role
-- icon with a sliver of two more beside and under it.
local SHEET = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
local CELL, SHEET_SIZE = 67, 256

local function Cell(column, row)
	return (column - 1) * CELL / SHEET_SIZE, column * CELL / SHEET_SIZE,
		(row - 1) * CELL / SHEET_SIZE, row * CELL / SHEET_SIZE
end

local ART = {
	[TANK] = { Cell(1, 2) },
	[HEALER] = { Cell(2, 1) },
	[DPS] = { Cell(2, 2) },
}

-- guid -> role, and only where the answer is settled.
--
-- The class floor is deliberately never written here. It is a guess standing in
-- until an inspect lands, and caching a guess is how a warrior stays in the
-- damage band for the rest of the session after the client finally said
-- Protection.
local settled = {}

local UnitClass = UnitClass
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local GetPartyAssignment = _G.GetPartyAssignment

--------------------------------------------------------------------------

-- The role the player typed for this name, or nothing.
--
-- Kept per character rather than per account, and by name rather than by GUID,
-- because the point of it is that you type it for the people you play with and
-- it is still right next week. A GUID would be right and unreadable.
function Role.Override(name)
	local roles = ns.dbc and ns.dbc.partyRoles
	if not roles or not name then
		return nil
	end
	return roles[name:lower()]
end

local function Assigned(unit)
	if type(UnitGroupRolesAssigned) ~= "function" then
		return nil
	end
	return ASSIGNED[UnitGroupRolesAssigned(unit)]
end

-- The raid's own main tank flag, which is set by the raid leader and is the one
-- source here that is both explicit and on both clients.
local function MainTank(unit)
	if type(GetPartyAssignment) ~= "function" then
		return false
	end
	local ok, flagged = pcall(GetPartyAssignment, "MAINTANK", unit)
	return ok and flagged and true or false
end

-- The role, and whether it is settled. Read best first, and every source is
-- allowed to answer nothing.
local function Decide(unit, guid)
	local role = Role.Override(UnitName(unit)) or Assigned(unit)
	if role then
		return role, true
	end
	if MainTank(unit) then
		return TANK, true
	end

	local _, class = UnitClass(unit)
	local tree = guid and Unit.Spec.Tree(guid)
	if tree then
		local byTree = TREES[class]
		return (byTree and byTree[tree]) or DPS, true
	end
	return FLOOR[class] or DPS, false
end

-- What this unit is playing. Damage for anything the client will not answer
-- about at all, because every caller needs a band and there is no fourth one.
function Role.Of(unit)
	if not unit then
		return DPS
	end
	local guid = UnitGUID(unit)
	local known = guid and settled[guid]
	if known then
		return known
	end
	local role, sure = Decide(unit, guid)
	if guid and sure then
		settled[guid] = role
	end
	return role
end

-- Where this role sorts. A number rather than the word, because the caller is a
-- comparator and a comparator on three strings would be sorting them
-- alphabetically, which puts damage first and the tank last.
function Role.Band(role)
	return BAND[role] or BAND[DPS]
end

-- The texture and its four crop coordinates, the same five returns
-- Unit/Spec.Icon hands back and for the same reason: this is asked once per
-- member whenever the list is laid out, and a table per member would be a table
-- to collect.
function Role.Art(role)
	local crop = ART[role] or ART[DPS]
	return SHEET, crop[1], crop[2], crop[3], crop[4]
end

--------------------------------------------------------------------------

-- One name given a role, or given none. Written straight into the saved table
-- and the cache dropped, because an override wins over everything above it and
-- a cached answer from a lower source would outlive it.
function Role.Set(name, role)
	if not ns.dbc or not name or name == "" then
		return false
	end
	if role and not BAND[role] then
		return false
	end
	-- `or nil` rather than the value as it arrived. A caller walking a name
	-- round the three bands hands over whatever came next, and false written
	-- into a saved table is a key that survives a logout, reads as no override
	-- everywhere it is asked and is counted as one by the line below.
	ns.dbc.partyRoles[name:lower()] = role or nil
	Role.Forget()
	return true
end

-- Every settled answer dropped. Called whenever something that decides one
-- moves: an override typed, an inspect answered, the raid leader flagging a
-- main tank. Cheap, and the next ask is one call per member on a list that is
-- rebuilt out of combat.
function Role.Forget()
	wipe(settled)
end

-- How many names carry an override, for the panel and the status line. A count
-- rather than the list, because the list is a picker's job and this is a line.
function Role.Overrides()
	local count = 0
	for _ in pairs((ns.dbc and ns.dbc.partyRoles) or {}) do
		count = count + 1
	end
	return count
end

-- Which of the four sources this client actually carries, said out loud rather
-- than assumed. Era answers NONE to the first of them all day and that is not
-- the same thing as the call being missing.
function Role.Describe()
	local sources = { "your own overrides" }
	if type(UnitGroupRolesAssigned) == "function" then
		sources[#sources + 1] = "the group finder's assignment"
	end
	if type(GetPartyAssignment) == "function" then
		sources[#sources + 1] = "the raid's main tank flag"
	end
	if Unit.Spec.Ready() then
		sources[#sources + 1] = "talent trees"
	end
	return ("roles from %s, then the class; %d name%s overridden"):format(
		table.concat(sources, ", "), Role.Overrides(),
		Role.Overrides() == 1 and "" or "s")
end

--------------------------------------------------------------------------

-- An inspect landing changes an answer that was a guess, and the raid leader
-- moving a main tank flag changes one that was settled. Both drop the cache;
-- neither redraws anything, because the order is UnitFrames/Group.lua's and it
-- is recomputed out of combat.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("INSPECT_READY")
events:RegisterEvent("CHARACTER_POINTS_CHANGED")
-- Retail's name for the group finder writing an assignment. Registered through
-- pcall because a client that has never heard of it refuses the registration
-- rather than raising, and loses nothing: GROUP_ROSTER_UPDATE reaches this too.
pcall(events.RegisterEvent, events, "PLAYER_ROLES_ASSIGNED")
events:SetScript("OnEvent", function()
	Role.Forget()
end)
