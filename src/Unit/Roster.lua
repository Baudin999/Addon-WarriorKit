local ADDON, ns = ...

local Unit = ns.Unit
local Roster = {}
Unit.Roster = Roster

--------------------------------------------------------------------------
-- Who is in the group
--
-- The meters and the enemy bars ask the same questions of it, and none of them
-- may ask the client directly, because the answers are wanted per row per tick
-- and some of them are not questions the client will answer at all.
--
--   is this GUID one of ours       the combat log names everyone in range,
--                                  including the other party fighting the
--                                  pack next door
--   whose pet is this              the log attributes a hunter's damage to
--                                  the pet, and a meter that files that
--                                  separately is a meter that reads a hunter
--                                  as half a hunter
--   what is this GUID called       and what class is it, which the log does
--                                  not carry at all
--
-- The last is why this table outlives the group. A member who leaves mid-fight
-- keeps their row until the segment ends, and their name and class have to
-- come from somewhere by then. `known` is written when someone is in the group
-- and never cleared; it is a few dozen entries a session.
--------------------------------------------------------------------------

-- guid -> unit token, this group only, rebuilt whenever the group changes.
local units = {}

-- guid -> owner guid, for pets. Rebuilt with the roster, because a pet unit is
-- something the client will answer for and the answer is current.
local owners = {}

-- guid -> owner guid, for anything a member summoned. Written by Meter.lua off
-- the summon in the log and deliberately not rebuilt with the roster, because
-- there is nothing to rebuild it from: no unit token points at a totem and the
-- summon is the only place the client ever says whose it is. Wiping this on a
-- roster change threw that away, and since a segment starts by rebuilding the
-- roster, every totem dropped before a pull had its damage land nowhere for
-- the whole fight. Pre-pull is when totems get dropped.
--
-- Bounded by pruning to the current group below rather than by wiping, so it
-- holds one entry per thing the people you are with have summoned since you
-- met them. A shaman retotemming all night is a few hundred short strings.
local summons = {}

-- guid -> { name, class }, kept for as long as the client runs.
local known = {}

-- The units in the group, player first, as a plain array so the threat sampler
-- and the enemy bars can walk it without pairs and without building anything.
local order = {}

local UnitClass = UnitClass
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitExists = UnitExists

--------------------------------------------------------------------------

-- Note who someone is, so a row survives them leaving the group. Two fields
-- rather than a table per call: this runs once per member per roster change,
-- and the entry is only built the first time a GUID is seen.
local function Note(guid, name, class)
	if not guid then
		return
	end
	local entry = known[guid]
	if not entry then
		entry = {}
		known[guid] = entry
	end
	entry.name = name or entry.name
	entry.class = class or entry.class
end

local function Add(unit, petUnit)
	local guid = UnitGUID(unit)
	if not guid then
		return
	end

	units[guid] = unit
	order[#order + 1] = unit
	local _, class = UnitClass(unit)
	Note(guid, UnitName(unit), class)

	if petUnit and UnitExists(petUnit) then
		local petGuid = UnitGUID(petUnit)
		if petGuid then
			owners[petGuid] = guid
			units[petGuid] = petUnit
		end
	end
end

-- Called at every GROUP_ROSTER_UPDATE and at the start of every segment. Not
-- on a ticker: the group changes when someone joins, and a meter that rescans
-- the raid five times a second to be told the same twenty names is the kind of
-- cost this addon has a whole tab for.
--
-- The enemy bars used to run their own copy of this walk on the tick, for the
-- unit list their threat comparison needs. That is eighty unit queries five
-- times a second in a forty man to be told what an event already knew, and it
-- is the reason this file now lives under Unit rather than under Meter.
function Roster.Build()
	wipe(units)
	wipe(owners)
	for index = #order, 1, -1 do
		order[index] = nil
	end

	Add("player", "pet")

	if IsInRaid() then
		for index = 1, GetNumGroupMembers() do
			local unit = "raid" .. index
			if UnitExists(unit) and not UnitIsUnit(unit, "player") then
				Add(unit, "raidpet" .. index)
			end
		end
	else
		for index = 1, 4 do
			local unit = "party" .. index
			if UnitExists(unit) then
				Add(unit, "partypet" .. index)
			end
		end
	end

	-- Everything summoned by somebody who is no longer here. Their totem is
	-- still burning and its damage is no longer ours to count, and this is the
	-- one place the table can be trimmed without losing a summon that is still
	-- live. Off the hot path by construction: this runs on a roster change and
	-- at the top of a segment, never on a tick.
	for guid, owner in pairs(summons) do
		if not units[owner] then
			summons[guid] = nil
		end
	end
end

-- The units in the group, player first. The array itself is handed out rather
-- than copied, because the only two callers walk it and neither writes to it.
function Roster.Units()
	return order
end

function Roster.UnitFor(guid)
	return units[guid]
end

-- Whose damage this is. A pet's is its owner's; anyone else's is their own.
-- Nil for a GUID that is not in the group and is not owned by anyone in it,
-- which is the whole of the filter: the combat log carries the other party's
-- fight, every mob in the pack, and both sides of the duel by the mailbox.
function Roster.Owner(guid)
	if not guid then
		return nil
	end
	local owner = owners[guid] or summons[guid]
	if owner then
		return owner
	end
	return units[guid] and guid or nil
end

-- What a member summoned belongs to them. Called from the combat log rather
-- than from a roster scan, because a totem, a Water Elemental and an
-- Eye of Kilrogg are not a pet unit and no unit token ever points at them.
function Roster.Own(guid, ownerGuid)
	if guid and ownerGuid and units[ownerGuid] then
		summons[guid] = ownerGuid
	end
end

-- Name and class for a GUID, from whenever it was last in the group. Both can
-- be nil for someone who was never in it, and every caller draws them dimmed
-- rather than refusing the row: a name with no class is a row that reads.
function Roster.Who(guid)
	local entry = known[guid]
	if not entry then
		return nil, nil
	end
	return entry.name, entry.class
end

-- The group's own size, which is what decides whether a meter is worth drawing
-- at all. Counts you, so it is never zero.
function Roster.Size()
	return #order
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("UNIT_PET")
events:SetScript("OnEvent", function()
	Roster.Build()
end)
