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
-- **Two mechanisms, and only one of them has a CVar.**
--
-- The numbers over whatever you are hitting are the world's. They are four
-- CVars, set up in Blizzard_SettingsDefinitions_Frame's
-- CombatOverrides.AdjustCombatSettings: a parent for damage on the target and
-- two children under it for periodic spells and for a pet's melee, with healing
-- beside them. Those four are exactly what this part redraws, so those four are
-- what it takes.
--
-- The `_v2` on the end of three of them is why this list was read off the
-- client's own source on the live install rather than typed. The names without
-- it are the retail spelling, they resolve to nothing here, and a CVar the
-- client does not recognise fails the way this file exists to catch: silently,
-- with the setting looking like it worked.
--
-- The column that scrolls up beside your character is Blizzard_CombatText, and
-- it is a different thing wearing the same words. `enableFloatingCombatText` is
-- its master switch and taking it is still the wrong move: it carries your
-- dodges and parries, aura gains and fades, entering and leaving combat, combo
-- points, energy, honour and reputation, and this part draws none of those.
--
-- What it also carries is every heal that lands on you and every hit that
-- lands on you, and those are drawn twice: once rising beside your character in
-- the client's own font, once by this part. That was reported as "healing shows
-- up twice", and the reason no CVar fixed it is that there is no CVar for it.
-- Blizzard_CombatText's own table, read off Shared/CombatTextConstants.lua,
-- gives HEAL, HEAL_CRIT, PERIODIC_HEAL, DAMAGE, DAMAGE_CRIT and SPELL_DAMAGE
-- `show = 1` and no `cvar` field at all, while a dodge, a combo point and an
-- energy gain each name one. The client's own settings page cannot turn these
-- off either; it never offered a control for them.
--
-- So the `show` field is what this file takes, on those types alone, and puts
-- back what it found. UpdateDisplayedMessages rewrites `show` only for the
-- types that name a CVar, so a type with none keeps whatever it was last set
-- to and the client never argues. Everything the master switch carries stays
-- exactly as the player left it.
--
-- **What was there is remembered before anything is written**, per character
-- and once, so turning this off puts a player's own choice back rather than the
-- default. That is the shape Targeting/Aim.lua already uses and the reason
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

-- The scrolling column's message types this part redraws, and nothing else it
-- draws. Every one of these is a hit or a heal on you, which is what the two
-- right hand streams and the heal stream are; a dodge, an aura, a reputation
-- tick and a combo point are the client's and stay the client's.
--
-- SPLIT_DAMAGE, DAMAGE_SHIELD and the absorb shapes are left alone. The
-- client's own table gives none of them a `show`, so it is already drawing none
-- of them and taking them would be a line that reads as work and does nothing.
local SCROLLED = {
	"HEAL", "HEAL_CRIT", "PERIODIC_HEAL", "PERIODIC_HEAL_CRIT",
	"DAMAGE", "DAMAGE_CRIT", "SPELL_DAMAGE",
}

local OFF = "0"

-- Nothing remembered yet. The CVars themselves only ever answer a number as a
-- string, so an empty string is a sentinel none of them can produce.
local UNSET = ""

local applied
local warned

-- What each scrolled type's `show` was before this file cleared it, keyed by
-- type. Session scoped rather than saved: these are code defaults rewritten
-- every time Blizzard_CombatText loads, so remembering them past a reload would
-- be remembering a value the client is about to set for itself.
local shown = {}

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

-- Blizzard_CombatText's own table of message types, or nil.
--
-- It loads on demand, so this is nil at login on a character who has never had
-- the scrolling column on and answers a table the moment the client loads it.
-- Named bare rather than probed through _G because it is a table and not a
-- call: a global that is not there reads as nil, which is the answer.
local function Types()
	local types = CombatTextTypeInfo
	if type(types) ~= "table" then
		return nil
	end
	return types
end

-- The scrolling column's heals and hits, off.
--
-- What is remembered is what was there rather than a one, so a player who
-- already had a type off gets it back off. A second pass writes nothing:
-- `shown` is only filled in on the pass that clears a type, and a type already
-- in it is one this file has already taken.
local function Hush()
	local types = Types()
	if not types then
		return false
	end
	for index = 1, #SCROLLED do
		local name = SCROLLED[index]
		local entry = types[name]
		if entry and shown[name] == nil then
			shown[name] = entry.show or false
			entry.show = nil
		end
	end
	return true
end

-- And back to whatever each of them was. `false` is the sentinel for a type
-- that was already off, because nil is what "this file has not taken it" means
-- and the two have to be different answers.
local function Unhush()
	local types = Types()
	for name, was in pairs(shown) do
		local entry = types and types[name]
		if entry then
			entry.show = was or nil
		end
		shown[name] = nil
	end
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
	Hush()

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
	Unhush()
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
	local down, all = Blizzard.Hushed()
	if all == 0 then
		-- Nothing to take. Either the column has never loaded, which is the
		-- ordinary answer on a character who has it switched off, or the table
		-- is there under a name this file does not know. The master switch is
		-- what tells those two apart, and it is worth saying out loud: a name
		-- that stopped resolving is exactly the silent failure the CVar read
		-- back above exists to catch, wearing a different hat.
		if (tonumber(Read("enableFloatingCombatText") or 0) or 0) > 0 then
			return "the client's own damage numbers are off, and it may still be scrolling hits and heals beside you"
		end
		return "the client's own damage numbers are off"
	end
	if down < all then
		return ("the client's own damage numbers are off, and %d of the %d it scrolls beside you are still drawn")
			:format(all - down, all)
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

-- How many of the scrolling column's types are down, and how many there are to
-- take. Read off the client's own table rather than off `shown`, for the reason
-- Describe reads the CVar: a count of what this file meant to do witnesses
-- nothing. Nought and nought on a client that has not loaded the column, which
-- is a character who has never turned it on and is not a failure.
function Blizzard.Hushed()
	local types = Types()
	if not types then
		return 0, 0
	end
	local down, all = 0, 0
	for index = 1, #SCROLLED do
		local entry = types[SCROLLED[index]]
		if entry then
			all = all + 1
			if not entry.show then
				down = down + 1
			end
		end
	end
	return down, all
end

--------------------------------------------------------------------------

-- The scrolling column arriving after this part was applied.
--
-- Blizzard_CombatText is LoadOnDemand and the client loads it inside its own
-- handler for the event that opens a session, which is after this addon has put
-- the numbers away. Apply returns early on a pass where the setting did not
-- move, so the table cannot be taken by calling it again: the pass that would
-- do the work is the pass that decides it has none. The same shape
-- Core/BlizzAdapter.lua uses for every client window that arrives late.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, _, name)
	if name == "Blizzard_CombatText" and applied then
		Hush()
	end
end)
