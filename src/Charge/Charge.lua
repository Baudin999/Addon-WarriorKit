local ADDON, ns = ...

local Charge = {}
ns.Charge = Charge

-- Three abilities that all close distance, driven by one button. Which one
-- applies is a function of combat and what the cursor is over, and every
-- display reads that single answer. Anything that would let the icon, the
-- world marker and the button disagree belongs in here.

local GCD = 1.5

--------------------------------------------------------------------------
-- The three openers
--
-- Which abilities this button casts is a fact about your class and lives in
-- Class\<yours>.lua as `charge`. Nil for a class that closes distance some
-- other way or not at all, and nil is the whole gate: Feature.lua builds no
-- page, Icon.lua builds no secure button, Marker.lua scans no nameplates and
-- SoftTarget.lua leaves the client's own CVar exactly as it found it.
--
-- Asked on demand rather than held at load. The class is not reliably known
-- while the files load, and a nil taken then would leave a warrior without the
-- button until they reloaded.
--------------------------------------------------------------------------

function Charge.Abilities()
	return ns.Class.Of("charge")
end

function Charge.Available()
	return Charge.Abilities() ~= nil
end

function Charge.Ability(key)
	local set = Charge.Abilities()
	return set and set[key] or nil
end

-- The palette both charge displays draw in. One icon on the HUD and one in the
-- world, each on its own with nothing beside it to compare against, so ready is
-- worth a colour here in a way it is not on a bar of twenty-four squares.
--
-- The looks themselves are UI/Ability.lua's now. This file used to hold three
-- of them privately and map every status onto one of the three, and the loss
-- in moving them out is real and is worth naming: out of range and out of rage
-- used to be the same grey as a cooldown, on the argument that the reason
-- differs and the answer does not. That argument was right for a display that
-- only ever answered "would a press put Charge on that mob". It was wrong
-- about the one question you ask the icon while you are running at something,
-- which is whether to keep running. Range is its own colour now.
local PALETTE = ns.UI.Ability.SHOUT

-- The one look every display reads, so the HUD icon and the world icon cannot
-- disagree about what green means. Returns the whole look table rather than
-- its three fields, because both callers guard on it and one identity
-- comparison is what three used to be.
function Charge.Look(status)
	return ns.UI.Ability.Look(PALETTE, status)
end

local names, textures = {}, {}

-- Bumped whenever the name caches below are dropped, which is the only thing
-- that can change the text of the generated macro without the unit changing.
-- Icon.lua guards its macro rebuild on this rather than on the built string,
-- because building the string was the cost it was trying to avoid.
local nameEpoch = 0

--------------------------------------------------------------------------
-- Spells
--------------------------------------------------------------------------

-- Resolved lazily rather than at PLAYER_LOGIN so no other file has to load
-- after this one for it to work.
function Charge.Name(key)
	if not names[key] then
		local info = Charge.Ability(key)
		names[key] = info and ns.SpellName(info.ranks[1])
	end
	return names[key]
end

function Charge.Texture(key)
	if not textures[key] then
		local info = Charge.Ability(key)
		textures[key] = info and ns.SpellTexture(info.ranks[1])
	end
	return textures[key]
end

-- Forwarded rather than resolved here. The three stances are shared knowledge
-- now: this part swaps into them on the way to an ability and the stance keys
-- are the whole of what they do, so ns.Stance owns the ids and the names and
-- the two cannot disagree about what stance 2 is called.
function Charge.StanceName(index)
	return ns.Stance.Name(index)
end

-- A number that changes when any name this file hands out might have. The
-- only caller is the macro guard, and what it needs is not the names but the
-- answer to "could they have moved since I last looked".
function Charge.NameEpoch()
	return nameEpoch + ns.Stance.Epoch()
end

-- Said once here so the panel, the slash word and the status line all give the
-- same reason, rather than three sentences that have to be kept in step.
function Charge.Refusal()
	return ("the charge button is built on three openers and a %s has none")
		:format(ns.Class.Label())
end

function Charge.Known(key)
	local info = Charge.Ability(key)
	if not info then
		return false
	end
	for _, id in ipairs(info.ranks) do
		if IsSpellKnown(id) then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------
-- Which unit
--------------------------------------------------------------------------

local function PlateUnit(plate)
	return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

local function Attackable(unit)
	return UnitExists(unit) and not UnitIsDead(unit) and UnitCanAttack("player", unit)
end

-- Matches the `help` macro conditional closely enough to colour by. An
-- Intervene the game refuses shows as out of range rather than as ready,
-- because IsSpellInRange answers nil for a unit the spell cannot take.
local function Assistable(unit)
	if not UnitExists(unit) or UnitIsDead(unit) or UnitCanAttack("player", unit) then
		return false
	end
	if UnitIsUnit(unit, "player") then
		return false -- Intervene needs someone else
	end
	if UnitPlayerOrPetInParty then
		return UnitPlayerOrPetInParty(unit)
			or (UnitPlayerOrPetInRaid and UnitPlayerOrPetInRaid(unit)) or false
	end
	return true -- cannot check group membership here, let the game refuse it
end

-- Soft targeting, which the game's own options call action targeting, is the
-- answer to "which mob am I aiming at". The client computes it from the camera
-- and hands it over as a unit token, so it needs no measurement and it is the
-- game's real cone rather than a heuristic over nameplate positions.
--
-- It replaced a scoring pass over plate screen positions, which cannot work
-- here: plate frames are restricted regions and GetCenter raises rather than
-- answering. See the README. This is strictly the better mechanism anyway.
--
-- Whether the token exists on 2.5.6 is not settled. SoftTargetEnemy is
-- definitely a live CVar, it persists to config-cache.wtf on this install, but
-- no installed addon reads the token and the wiki marks it Dragonflight. So
-- probe rather than assume, the same way BuildBinder probes for the state
-- driver: the first time the token answers, it is supported, and until then
-- the pick falls through to the cursor. Both paths are correct, so a client
-- without it loses camera aiming rather than breaking.
local softProven = false

-- Whether the token resolves at all. That is a different question from whether
-- the unit under it is one Charge could take, and both are worth asking
-- separately: Pick wants the second, and the reticle in SoftTarget.lua wants
-- the first, so it can prove the token against a critter or a corpse rather
-- than staying dark and looking like a client that has no token.
--
-- pcalled because an unknown unit token is not guaranteed to be a polite nil on
-- every build, and this is called 20 times a second.
function Charge.SoftUnit()
	local ok, exists = pcall(UnitExists, "softenemy")
	if not ok or not exists then
		return nil
	end
	softProven = true
	return "softenemy"
end

local function SoftEnemy()
	if not Charge.SoftUnit() then
		return nil
	end
	if Attackable("softenemy") then
		return "softenemy"
	end
	return nil
end

-- "on" once the token has answered, "off" when the CVar is switched off, and
-- "unproven" while neither has happened. Only "off" is worth telling anyone
-- about, because only "off" is something they can fix.
function Charge.SoftTargetState()
	if softProven then
		return "on"
	end
	-- Anything that is not a positive number counts as off, nil included. A
	-- character that never touched the CVar reads as unset, and calling that
	-- "unproven" would have swallowed the one message worth printing.
	local value = GetCVar and tonumber(GetCVar("SoftTargetEnemy") or "")
	if not value or value <= 0 then
		return "off"
	end
	return "unproven"
end

function Charge.PlateFor(unit)
	if not C_NamePlate or not unit then
		return nil
	end
	if C_NamePlate.GetNamePlateForUnit then
		-- pcalled because the marker's ticker calls this 20 times a second
		-- against unit tokens the client may not accept, and a ticker that
		-- raises hits the error ceiling in about a minute.
		local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
		return (ok and plate) or nil
	end

	-- Only where the client has no GetNamePlateForUnit, which is neither of the
	-- two this addon targets. It used to run as a fallback whenever that call
	-- came back empty, which is the ordinary answer for a mob with no plate up,
	-- so a scan that could not succeed ran twenty times a second and allocated
	-- a table each time: GetNamePlates builds a fresh one on every call.
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do -- allocates: unreachable on a client with GetNamePlateForUnit, and the early return above is the guard the scan cannot see
		local plateUnit = PlateUnit(plate)
		if plateUnit and UnitIsUnit(plateUnit, unit) then
			return plate
		end
	end
	return nil
end

local cachedKey, cachedUnit, cachedPlate, cachedAt = "charge", nil, nil, -1

-- The one decision every display reads. Returns the ability key, the unit it
-- would take, and that unit's nameplate when there is one.
--
-- Out of combat it is Charge, and the mob you are aiming at wins, because
-- aiming by looking is the whole point of the marker. When the camera has no
-- answer it falls back to the target you chose on purpose, even a friendly one
-- that will make the charge fail, then the mob under the cursor, then nothing
-- and the macro's /targetenemy takes the press.
--
-- Soft targeting resolves to your own target while you hold one, so the
-- reorder only bites when the two differ, which is exactly when the camera is
-- the answer you wanted.
--
-- In combat the cursor decides. A party member under it means Intervene, a mob
-- means Intercept, and nothing under it shows Intervene greyed out, since that
-- is the one a tank reaches for.
--
-- Memoised per frame because GetTime is frame-constant, so three callers cost
-- one nameplate scan.
function Charge.Pick()
	local now = GetTime()
	if now == cachedAt then
		return cachedKey, cachedUnit, cachedPlate
	end
	cachedAt = now

	if UnitAffectingCombat("player") then
		cachedPlate = nil
		if Attackable("mouseover") then
			cachedKey, cachedUnit = "intercept", "mouseover"
		elseif Assistable("mouseover") then
			cachedKey, cachedUnit = "intervene", "mouseover"
		else
			cachedKey, cachedUnit = "intervene", nil
		end
		return cachedKey, cachedUnit, cachedPlate
	end

	cachedKey = "charge"
	local soft = SoftEnemy()
	if soft then
		cachedUnit, cachedPlate = soft, Charge.PlateFor(soft)
	elseif UnitExists("target") and not UnitIsDead("target") then
		cachedUnit, cachedPlate = "target", Charge.PlateFor("target")
	elseif Attackable("mouseover") then
		cachedUnit, cachedPlate = "mouseover", Charge.PlateFor("mouseover")
	else
		cachedUnit, cachedPlate = nil, nil
	end
	return cachedKey, cachedUnit, cachedPlate
end

--------------------------------------------------------------------------
-- Status
--------------------------------------------------------------------------

-- Returns a status, which Charge.Look turns into a colour, plus the cooldown
-- start and duration when there is one. Order is deliberate: what you cannot fix at all comes first,
-- then what a stance swap or a few seconds of rage fixes, then range.
function Charge.State(key, unit)
	local info = Charge.Ability(key)
	local name = Charge.Name(key)
	if not info or not name or not Charge.Known(key) then
		return "unknown"
	end

	local start, duration, enabled = ns.SpellCooldown(name)
	if enabled and duration > GCD and start > 0 then
		return "cooldown", start, duration
	end

	if info.inCombat ~= UnitAffectingCombat("player") then
		return "combat"
	end

	local valid = unit and (info.hostile and Attackable(unit) or (not info.hostile and Assistable(unit)))
	if not valid then
		return "notarget"
	end

	-- The macro swaps stance for you, so a stance mismatch clears itself on the
	-- next press rather than blocking. IsUsableSpell knows the stance rule too,
	-- and is the only thing that knows about rage.
	local form = ns.Stance.Current()
	if form and form ~= info.stance then
		return "stance"
	end
	local usable, noPower = ns.SpellUsable(name)
	if not usable then
		return noPower and "cost" or "stance"
	end

	-- ns.OutOfRange owns what a nil answer means and says so once a session.
	-- Buttons/Slot.lua asks the identical question of an action slot, and two
	-- copies of the counter would be two thresholds and the sentence twice.
	if ns.OutOfRange(ns.SpellInRange(name, unit)) then
		return "range"
	end

	return "ready"
end

local events = CreateFrame("Frame")
events:RegisterEvent("SPELLS_CHANGED")
events:SetScript("OnEvent", function()
	-- A new rank changes nothing, but a locale reload would.
	wipe(names)
	wipe(textures)
	nameEpoch = nameEpoch + 1
end)
