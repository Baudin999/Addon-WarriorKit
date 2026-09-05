local ADDON, ns = ...

local Blizzard = {}
ns.CombatTextBlizzard = Blizzard

--------------------------------------------------------------------------
-- The client's own damage numbers, put away
--
-- Two parts drawing the same hit is worse than either of them alone: the
-- numbers land in different places at different sizes and the eye reads a busy
-- screen twice to learn one thing. So switching this part on takes the client's
-- own numbers off, and switching it off puts them back exactly as they were.
--
-- **Four CVars and not the master.** `enableFloatingCombatText` looks like the
-- switch and is the wrong one. On 2.5.6 it gates the text that scrolls beside
-- your character, which is your dodges and parries, aura gains and fades,
-- entering and leaving combat, combo points, energy, honour and reputation.
-- This part draws none of those, and taking that switch would delete a dozen
-- readouts to stop one duplicate. Blizzard_CombatText registers eight events
-- behind it and not one of them is a damage event.
--
-- The damage numbers are a separate group, set up in
-- Blizzard_SettingsDefinitions_Frame's CombatOverrides.AdjustCombatSettings:
-- a parent for damage on the target and two children under it for periodic
-- spells and for a pet's melee, and healing beside them. Those four are exactly
-- what this part redraws, so those four are what it takes.
--
-- The `_v2` on the end of three of them is why this list was read off the
-- client's own source on the live install rather than typed. The names without
-- it are the retail spelling, they resolve to nothing here, and a CVar the
-- client does not recognise fails the way this file exists to catch: silently,
-- with the setting looking like it worked.
--
-- **What was there is remembered before anything is written**, per character
-- and once, so turning this off puts a player's own choice back rather than the
-- default. That is the shape Charge/SoftTarget.lua already uses and the reason
-- it uses it: a part that leaves a CVar wherever it happened to land is a part
-- that quietly edits your client config.
--
-- **Every call is pcalled and every write is read back.** A client that accepts
-- SetCVar and ignores the name leaves no trace at all, and the difference
-- between the setting working and the setting intending to work is the whole
-- reason this is a file rather than four lines in Numbers.lua.
--------------------------------------------------------------------------

-- The four, in the order the client's own options page lists them.
--
--   damage    the numbers over whatever you are hitting
--   periodic  a bleed or a damage over time tick, which is a child of damage
--   pet       a pet's melee, also a child of damage
--   healing   health going up, which stands on its own
--
-- Read off Blizzard_SettingsDefinitions_Frame/Classic/CombatOverrides.lua on
-- the 2.5.6 source rather than from memory.
local TAKEN = {
	"floatingCombatTextCombatDamage_v2",
	"floatingCombatTextCombatLogPeriodicSpells_v2",
	"floatingCombatTextPetMeleeDamage_v2",
	"floatingCombatTextCombatHealing_v2",
}

local OFF = "0"

-- Nothing remembered yet. The CVars themselves only ever answer a number as a
-- string, so an empty string is a sentinel none of them can produce.
local UNSET = ""

local applied
local warned

--------------------------------------------------------------------------

local function Read(name)
	if type(GetCVar) ~= "function" then
		return nil
	end
	local ok, value = pcall(GetCVar, name)
	if not ok then
		return nil
	end
	return value
end

-- pcalled because nothing on this install proves SetCVar will take these names,
-- and because a CVar the client marks protected refuses in combat. A refusal is
-- a refusal and never an error on screen.
local function Write(name, value)
	if type(SetCVar) ~= "function" then
		return false
	end
	return (pcall(SetCVar, name, value))
end

-- What each one was before this addon first touched it, taken once per
-- character. Written before the first write and never again, so a reload with
-- the numbers already on does not remember the zero this file put there.
local function Remember()
	local prior = ns.dbc.hitsPrior
	for index = 1, #TAKEN do
		local name = TAKEN[index]
		if prior[name] == nil or prior[name] == UNSET then
			prior[name] = Read(name) or "1"
		end
	end
end

--------------------------------------------------------------------------

-- Off while this part is drawing, and back to what the character chose the
-- moment it is not.
--
-- Idempotent on purpose: the panel calls this on every control it draws and a
-- pass that changes nothing has to write nothing, because SetCVar on a name the
-- client honours writes config-cache.wtf.
function Blizzard.Apply()
	local want = ns.db.hits and ns.db.hitsQuiet and true or false
	if want == applied then
		return want
	end

	if not want then
		Blizzard.Restore()
		return false
	end

	Remember()
	for index = 1, #TAKEN do
		Write(TAKEN[index], OFF)
	end

	-- Read back. A call that raises is caught above; a client that accepts the
	-- name and does nothing with it is invisible without this, and the symptom
	-- is every number on screen twice with the setting saying it is handled.
	if Read(TAKEN[1]) ~= OFF and not warned then
		warned = true
		ns.Print("this client accepted the change to its own damage numbers and did not make it, so they may still be drawn. /wk hits quiet off stops the addon trying.")
	end

	applied = true
	return true
end

-- Put the character's own values back, and forget them, so the next time the
-- part is switched on it remembers afresh.
function Blizzard.Restore()
	local prior = ns.dbc and ns.dbc.hitsPrior
	if prior then
		for index = 1, #TAKEN do
			local name = TAKEN[index]
			if prior[name] and prior[name] ~= UNSET then
				Write(name, prior[name])
			end
			prior[name] = nil
		end
	end
	applied = false
end

-- Always what the CVar actually says and never what this file meant to set it
-- to. A status line that echoes intent cannot witness anything.
function Blizzard.Describe()
	local value = Read(TAKEN[1])
	if value == nil then
		return "this client will not say"
	end
	if (tonumber(value) or 0) > 0 then
		return "the client is drawing its own damage numbers as well"
	end
	return "the client's own damage numbers are off"
end

-- How many of the four are down, for the harness.
function Blizzard.Quiet()
	local down = 0
	for index = 1, #TAKEN do
		if (tonumber(Read(TAKEN[index]) or 1) or 1) == 0 then
			down = down + 1
		end
	end
	return down, #TAKEN
end
