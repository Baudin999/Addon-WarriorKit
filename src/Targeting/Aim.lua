local ADDON, ns = ...

local Aim = {}
ns.Aim = Aim

-- Action targeting: the camera picks the enemy, and the enemy it picks becomes
-- the one you are actually targeting.
--
-- That second half is a separate CVar and leaving it out is what made this
-- feature look broken. SoftTargetEnemy alone gives you a soft target, which is
-- not a target: `softenemy` resolves, a macro written against it casts, and
-- then the cast lands on a mob you have not selected. Auto attack has nothing,
-- your bar has nothing, and the fight is over before it starts.
--
-- SoftTargetForce is the half that was missing. "Auto-set target to match soft
-- target", 1 for enemies and 2 for friends, and 1 is what this writes. The
-- client's own default is 1 as well, which is exactly why it was never noticed:
-- the feature reads as working on a client that happens to be at the default
-- and as broken on one that is not, and nothing in either case says which.
-- An addon that owns half a mechanism owns all of it.
--
-- What stops the target then wandering as you look around is the client's, not
-- ours. SoftTargetMatchLocked defaults to 1, "match appropriate soft target to
-- locked target", so once you hold a target the soft one is pinned to it and
-- the camera stops choosing. That is why there is no longer a combat split
-- here.
--
-- The split there used to be turned SoftTargetEnemy off at PLAYER_REGEN_DISABLED,
-- on the argument that a client re-aiming at whatever you glance at is the last
-- thing you want while holding a mob. The argument was right and the mechanism
-- was wrong: MatchLocked already prevents that, and switching soft targeting
-- off one second into a fight takes the target that was forced from it with it.
-- The symptom was a mob you had just charged and could no longer attack.
--
-- What is still Charge's: whether the token resolves at all. Charge.SoftUnit
-- probes it and Charge.SoftTargetState reports it, because that is a question
-- about the marker's aiming rather than about the CVars underneath it.
--
-- So the addon owns these two while the setting is on, and puts back whatever
-- it found when you turn the setting off. Both are scoped per character, so the
-- remembered values are too.

-- In write order, because a client that takes the first and refuses the second
-- should leave the more useful half standing. A list rather than a map so the
-- order is a fact of this file and not of the hash.
local OWNED = {
	-- 0 off, 1 gamepad, 2 keyboard and mouse, 3 always.
	{ cvar = "SoftTargetEnemy", value = "3" },
	-- Enemies only. A player who had set 2 for friends gets it back on the way
	-- out, which is the whole reason the prior value is kept; a warrior kit has
	-- no business forcing a friendly target on their behalf in the meantime.
	{ cvar = "SoftTargetForce", value = "1" },
}

local applied = {}  -- what this addon last wrote, so a no-op pass writes nothing
local pending       -- a write the client refused, retried when combat drops
local warned, warnedIgnored

local function Read(cvar)
	if type(GetCVar) ~= "function" then
		return nil
	end
	local ok, value = pcall(GetCVar, cvar)
	if not ok then
		return nil
	end
	return value
end

-- pcalled because nothing in this install proves SetCVar will take these names
-- on 2.5.6, and because a CVar the client marks protected refuses in combat. A
-- refusal is a deferral, never an error on screen.
local function Write(cvar, value)
	if type(SetCVar) ~= "function" then
		return false
	end
	return (pcall(SetCVar, cvar, value))
end

-- Taken the first time the addon touches a CVar on this character, so turning
-- the setting off can put back what was actually there rather than a guess. A
-- key absent from the table is one not remembered yet; the CVars themselves
-- only ever answer a number as a string.
local function Remember()
	if not ns.dbc then
		return
	end
	for _, owned in ipairs(OWNED) do
		if ns.dbc.aimPrior[owned.cvar] == nil then
			ns.dbc.aimPrior[owned.cvar] = Read(owned.cvar) or "0"
		end
	end
end

-- Returns false when the client refused or ignored any of them, so the caller
-- can say so. No combat branch: this is one state, held whenever the setting is
-- on, and the client's own MatchLocked is what keeps the camera off a target
-- you are already holding.
function Aim.Apply()
	if not ns.db.softAuto then
		return true
	end
	Remember()

	local ok = true
	for _, owned in ipairs(OWNED) do
		local cvar, want = owned.cvar, owned.value
		if applied[cvar] ~= want or Read(cvar) ~= want then
			if not Write(cvar, want) then
				pending, ok = true, false
				if not warned then
					warned = true
					ns.Print("this client would not change action targeting just now. It will be set again when you leave combat.")
				end
			-- Read it back. A SetCVar that raises is caught above, but a client
			-- that accepts the call and ignores the name leaves no trace at
			-- all, and the difference between the setting working and the
			-- setting only intending to is the whole reason this file exists.
			elseif Read(cvar) ~= want then
				ok = false
				if not warnedIgnored then
					warnedIgnored = true
					ns.Print(("this client accepted the action targeting change and did not make it, so %s is not a CVar it honours. /wk aim off stops the addon trying."):format(cvar))
				end
			else
				applied[cvar] = want
			end
		end
	end

	if ok then
		pending = nil
	end
	return ok
end

-- Put the character's own values back. Called when the setting is turned off,
-- because a setting that leaves a CVar wherever it happened to land is a
-- setting that quietly edits your client config.
function Aim.Restore()
	if ns.dbc then
		for _, owned in ipairs(OWNED) do
			local prior = ns.dbc.aimPrior[owned.cvar]
			if prior ~= nil then
				Write(owned.cvar, prior)
			end
			ns.dbc.aimPrior[owned.cvar] = nil
		end
	end
	applied = {}
end

local function On(cvar)
	return (tonumber(Read(cvar)) or 0) > 0
end

-- Always reports what the CVars actually say, never what this file meant to set
-- them to. A status line that echoes intent cannot witness anything, and this
-- one is the only witness there is until someone reads config-cache.wtf.
--
-- The two are reported apart because they fail apart, and the half that is
-- worth naming is the one that was missing for a release: soft targeting on
-- with forcing off is the state where the camera aims, the cast lands and you
-- still have nothing selected.
function Aim.Describe()
	if Read("SoftTargetEnemy") == nil then
		return "this client will not say"
	end
	local aiming, forcing = On("SoftTargetEnemy"), On("SoftTargetForce")

	if not ns.db.softAuto then
		return ("manual, aiming %s and the target %s"):format(
			aiming and "on" or "off", forcing and "follows" or "does not follow")
	end
	if not aiming then
		return "on, but the client is holding soft targeting off"
	end
	if not forcing then
		return "aiming, but the client is not letting the target follow"
	end
	return "aiming, and the target follows what the camera picks"
end

-- PLAYER_REGEN_ENABLED is the retry and not a transition: the only write that
-- can be refused is one attempted in combat, and leaving one is the moment it
-- can be attempted again.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event ~= "PLAYER_REGEN_ENABLED" or pending then
		Aim.Apply()
	end
end)
