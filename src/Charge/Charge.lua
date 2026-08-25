local ADDON, ns = ...

local Charge = {}
ns.Charge = Charge

-- Three abilities that all close distance, driven by one button. Which one
-- applies is a function of combat and what the cursor is over, and every
-- display reads that single answer. Anything that would let the icon, the
-- world marker and the button disagree belongs in here.

local GCD = 1.5

-- Stance index is what the `stance:` macro conditional uses, so the numbers
-- here are the numbers in the generated macro.
local STANCE_SPELLS = { 2457, 71, 2458 } -- 1 Battle, 2 Defensive, 3 Berserker

Charge.ABILITIES = {
	charge = {
		ranks = { 100, 6178, 11578 },
		stance = 1,
		hostile = true,
		inCombat = false, -- Charge only works out of combat
	},
	intervene = {
		ranks = { 3411 },
		stance = 2,
		hostile = false,
		inCombat = true,
	},
	intercept = {
		ranks = { 20252, 20616, 20617 },
		stance = 3,
		hostile = true,
		inCombat = true,
	},
}

-- Three looks, not eight. The question the icon answers is "would a press put
-- Charge on that mob", and there are only three honest answers to it, so a
-- colour per status was eight shades saying one of three things. Private,
-- because Charge.Look is the only way in.
local LOOKS = {
	go = { 0.16, 0.80, 0.32 },   -- the ability lands on that unit right now
	swap = { 0.96, 0.62, 0.16 }, -- the press spends itself on the stance swap
	no = { 0.38, 0.38, 0.43 },   -- nothing lands: cooldown, out of range, no unit
}

-- Which of the three a status means. Everything absent from here is "no",
-- which is the grey one, and grey is deliberately where out of range and
-- cooldown both land: the reason differs, the answer does not.
local OUTCOME = {
	ready = "go",
	stance = "swap",
}

-- The one look every display reads, so the HUD icon and the world icon cannot
-- disagree about what green means. Returns the border colour, whether the art
-- is greyed out, and the alpha to draw at.
function Charge.Look(status)
	local outcome = OUTCOME[status] or "no"
	return LOOKS[outcome], outcome == "no", outcome == "go" and 1 or 0.6
end

local names, textures, stanceNames = {}, {}, {}
local isWarrior -- nil until the class resolves, class data is not reliable while files load
local rangeAnswered, rangeSilent = false, 0

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
		local info = Charge.ABILITIES[key]
		names[key] = info and ns.SpellName(info.ranks[1])
	end
	return names[key]
end

function Charge.Texture(key)
	if not textures[key] then
		local info = Charge.ABILITIES[key]
		textures[key] = info and ns.SpellTexture(info.ranks[1])
	end
	return textures[key]
end

function Charge.StanceName(index)
	if not stanceNames[index] then
		stanceNames[index] = ns.SpellName(STANCE_SPELLS[index])
	end
	return stanceNames[index]
end

-- A number that changes when any name this file hands out might have. The
-- only caller is the macro guard, and what it needs is not the names but the
-- answer to "could they have moved since I last looked".
function Charge.NameEpoch()
	return nameEpoch
end

local function IsPlayerWarrior()
	if isWarrior == nil then
		local _, class = UnitClass("player")
		if class then
			isWarrior = (class == "WARRIOR")
		end
	end
	return isWarrior == true
end

function Charge.Known(key)
	if not IsPlayerWarrior() then
		return false
	end
	local info = Charge.ABILITIES[key]
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

-- Nil when the client will not say, which sends the verdict back to
-- IsUsableSpell rather than guessing a stance.
local function CurrentStance()
	if GetShapeshiftForm then
		return GetShapeshiftForm()
	end
	return nil
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
		-- raises hits the error ceiling in about a minute. The scan below is
		-- the real answer anyway.
		local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
		if ok and plate then
			return plate
		end
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
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
	local info = Charge.ABILITIES[key]
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
	local form = CurrentStance()
	if form and form ~= info.stance then
		return "stance"
	end
	local usable, noPower = ns.SpellUsable(name)
	if not usable then
		return noPower and "rage" or "stance"
	end

	local range = ns.SpellInRange(name, unit)
	if range == nil then
		-- Only a definite 0 blocks. A client that never answers should not pin
		-- every target at out-of-range, but it should say so once.
		rangeSilent = rangeSilent + 1
		if not rangeAnswered and rangeSilent == 40 then
			ns.Print("this client is not answering range checks, so out-of-range targets cannot be dimmed.")
		end
	else
		rangeAnswered = true
		if range == 0 then
			return "range"
		end
	end

	return "ready"
end

local events = CreateFrame("Frame")
events:RegisterEvent("SPELLS_CHANGED")
events:SetScript("OnEvent", function()
	-- A new rank changes nothing, but a locale reload would.
	wipe(names)
	wipe(textures)
	wipe(stanceNames)
	nameEpoch = nameEpoch + 1
end)
