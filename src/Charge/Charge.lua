local ADDON, ns = ...

local Charge = {}
ns.Charge = Charge

-- Three abilities that all close distance, driven by one button. Which one
-- applies is a function of combat, the stance you stand in, what you have
-- trained and what the cursor is over, and every display reads that single
-- answer. Anything that would let the icon, the world marker and the button
-- disagree belongs in here.

local GCD = 1.5

--------------------------------------------------------------------------
-- The three openers
--
-- Which abilities this button casts is a fact about your class and lives in
-- Class\<yours>.lua as `charge`. Nil for a class that closes distance some
-- other way or not at all, and nil is the whole gate: Feature.lua builds no
-- page, Icon.lua builds no secure button and Marker.lua scans no nameplates.
--
-- Action targeting is not gated on this and used to be. It is a pair of client
-- settings about how you pick a mob, so they are Targeting/Aim.lua's now and
-- they run on every class; what is still here is only whether the token they
-- switch on resolves, which is a question about this button's aiming.
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

-- Whether each of the three is trained, held rather than walked.
--
-- The answer is a fact about your spellbook and it changes at a trainer, which
-- is an event. Asked straight it is one IsSpellKnown per rank per call, the
-- rank list is nine long for Charge, and both displays ask it on every tick.
-- Wiped with the names below, on the one event that can make it wrong.
local knows = {}

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
	local held = knows[key]
	if held ~= nil then
		return held
	end
	local found = false
	local info = Charge.Ability(key)
	if info then
		for _, id in ipairs(info.ranks) do
			if IsSpellKnown(id) then
				found = true
				break
			end
		end
	end
	knows[key] = found
	return found
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
-- separately: Pick wants the second, and SoftTargetState wants the first, so
-- the panel's reading can prove the token against a critter or a corpse rather
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

-- Whether you stand in the stance an opener needs. A client that will not say
-- which stance you are in counts as standing in the right one, for the reason
-- Answer gives below: IsUsableSpell knows the stance rule too and gets the last
-- word there.
local function Stands(key)
	local info = Charge.Ability(key)
	if not info then
		return false
	end
	local form = ns.Stance.Current()
	return form == nil or form == info.stance
end

-- The opener a stance owns, when you have trained it. Nil when you have not,
-- or when the stance owns none, which is the whole of Battle Stance in a
-- fight: Charge is out of combat only.
local function Own(key)
	if Stands(key) and Charge.Known(key) then
		return key
	end
	return nil
end

-- What the fight's half of the button shows with nothing under the cursor.
-- Your own stance's opener first, because that is the one a press lands
-- without a swap; then Intercept, the one that takes a mob; then Intervene;
-- then Charge, greyed as in combat, for a warrior who has trained nothing
-- else yet. A level twenty warrior used to see Intervene here, an ability
-- fifty levels away, drawn as unknown.
local function Idle()
	return Own("intervene") or Own("intercept")
		or (Charge.Known("intercept") and "intercept")
		or (Charge.Known("intervene") and "intervene")
		or "charge"
end

local cachedKey, cachedUnit, cachedPlate, cachedAt = "charge", nil, nil, -1

-- The one decision every display reads. Returns the ability key, the unit it
-- would take, and that unit's nameplate when there is one.
--
-- Out of combat the stance decides the opener. Berserker Stance has one of
-- its own, Intercept, and a fury warrior lives there, so the button reaches
-- for it rather than spending the press and the rage on a swap to Battle
-- Stance. Every other stance means Charge, with the swap the macro carries.
-- Either way the mob you are aiming at wins, because aiming by looking is the
-- whole point of the marker. When the camera has no answer it falls back to
-- the target you chose on purpose, even a friendly one that will make the
-- charge fail, then the mob under the cursor, then nothing and the macro's
-- /targetenemy takes the press.
--
-- Soft targeting resolves to your own target while you hold one, so the
-- reorder only bites when the two differ, which is exactly when the camera is
-- the answer you wanted.
--
-- In combat the cursor decides. A party member under it means Intervene, a mob
-- means Intercept, and nothing under it shows what Idle says.
--
-- An opener you have not trained is never picked. The macro writes no line
-- for it either, so what the icon shows and what a press does agree on a
-- character who is still levelling.
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
		if Attackable("mouseover") and Charge.Known("intercept") then
			cachedKey, cachedUnit = "intercept", "mouseover"
		elseif Assistable("mouseover") and Charge.Known("intervene") then
			cachedKey, cachedUnit = "intervene", "mouseover"
		else
			cachedKey, cachedUnit = Idle(), nil
		end
		return cachedKey, cachedUnit, cachedPlate
	end

	cachedKey = Own("intercept") or "charge"
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
-- start and duration when there is one. Order is deliberate: what you cannot
-- fix at all comes first, then what a stance swap or a few seconds of rage
-- fixes, then range.
local function Answer(key, unit)
	local info = Charge.Ability(key)
	local name = Charge.Name(key)
	if not info or not name or not Charge.Known(key) then
		return "unknown"
	end

	local start, duration, enabled = ns.SpellCooldown(name)
	if enabled and duration > GCD and start > 0 then
		return "cooldown", start, duration
	end

	-- Charge is the one of the three with a combat rule, and it is the only
	-- rule IsUsableSpell does not know. Intercept and Intervene take a press
	-- on either side of the pull.
	if info.outOfCombat and UnitAffectingCombat("player") then
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

local stateKey, stateUnit, stateAt = nil, nil, -1
local stateStatus, stateStart, stateDuration

-- Memoised per frame the way Pick is, and for the same reason: GetTime is
-- frame-constant, the world icon and the HUD icon ask the identical question
-- off the identical pick, and a dozen client calls is what two used to cost.
--
-- Keyed on the pick as well as the clock, because the two displays part company
-- in combat: the marker detaches and the icon asks about Intervene.
function Charge.State(key, unit)
	local now = GetTime()
	if now == stateAt and key == stateKey and unit == stateUnit then
		return stateStatus, stateStart, stateDuration
	end
	stateAt, stateKey, stateUnit = now, key, unit
	stateStatus, stateStart, stateDuration = Answer(key, unit)
	return stateStatus, stateStart, stateDuration
end

--------------------------------------------------------------------------
-- When to ask again
--------------------------------------------------------------------------

-- A number that changes when anything Charge.State reads might have. Both
-- displays hold the number they last drew at and compare, so a tick where
-- nothing moved costs a comparison instead of a status.
--
-- Cooldown, usable, stance and target all announce themselves and all four are
-- registered at the foot of this file. Combat shows up in Pick's key, which
-- both displays already compare against what they drew.
--
-- Range announces nothing. You walk into it and the client says so only when
-- asked, and range is the whole question you are asking the marker while you
-- run at a mob, so it is asked here at one call rather than left to go stale
-- until something else moves. Item 39 named the four events and left this one
-- out; it is the same carve-out the 20 Hz tick already gets for softenemy, and
-- for the same reason.
--
-- Asked only while the last answer was one that range can move. "ready" and
-- "range" are the two sides of that line and every other status is settled
-- before Answer reaches the range check, so asking outside those two would feed
-- nils to ns.OutOfRange for units the spell was never going to take, and forty
-- of those print a sentence about a client fault that is not one.
local epoch = 0
local beyond, epochAt = nil, -1

function Charge.StateEpoch(key, unit)
	local now = GetTime()
	if now == epochAt then
		return epoch
	end
	epochAt = now

	if unit and key == stateKey and unit == stateUnit
		and (stateStatus == "ready" or stateStatus == "range") then
		local far = ns.OutOfRange(ns.SpellInRange(Charge.Name(key), unit))
		if far ~= beyond then
			beyond = far
			epoch = epoch + 1
		end
	else
		beyond = nil
	end
	return epoch
end

local events = CreateFrame("Frame")

-- Everything the client will say about the four inputs above, plus the two
-- edges of combat, because a status that reads the combat rule is a status
-- that moved when the fight started.
local function Moved(_, event)
	if event == "SPELLS_CHANGED" then
		-- A new rank changes nothing, but a locale reload would.
		wipe(names)
		wipe(textures)
		wipe(knows)
		nameEpoch = nameEpoch + 1
	end
	epoch = epoch + 1
	stateAt = -1 -- the memo above is this frame's and is now a frame out of date
end

events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterEvent("SPELL_UPDATE_USABLE")
events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", Moved)
