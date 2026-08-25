local ADDON, ns = ...

local SoftTarget = {}
ns.SoftTarget = SoftTarget

-- Action targeting, held on out of combat and off in it.
--
-- Soft targeting is what makes the `softenemy` token resolve, and that token is
-- what lets the charge button aim by camera. It is worth having for the pull
-- and worth not having once the pull has landed: in combat Charge.Pick reads
-- the cursor rather than the camera, so the token buys nothing there, and a
-- client quietly re-aiming at whatever you glance at is the last thing you want
-- while holding a mob.
--
-- The split is the same one the rest of the Charge part already draws. Charge
-- is an out of combat ability, the world marker hides at PLAYER_REGEN_DISABLED,
-- and the macro's target line carries `nocombat`. This is that line moved down
-- into the client setting underneath it.
--
-- So the addon owns the CVar while the setting is on: it writes it on every
-- combat transition and puts back whatever it found when you turn the setting
-- off. SoftTargetEnemy is scoped per character, so the remembered value is too.

local ON = "3"
local OFF = "0"

local applied  -- what this addon last wrote, so a no-op transition writes nothing
local pending  -- a write the client refused, retried when combat drops
local warned, warnedIgnored

local function Read()
	if type(GetCVar) ~= "function" then
		return nil
	end
	local ok, value = pcall(GetCVar, "SoftTargetEnemy")
	if not ok then
		return nil
	end
	return value
end

-- pcalled because nothing in this install proves SetCVar will take this name on
-- 2.5.6, and because a CVar the client marks protected refuses in combat. A
-- refusal is a deferral, never an error on screen.
local function Write(value)
	if type(SetCVar) ~= "function" then
		return false
	end
	return (pcall(SetCVar, "SoftTargetEnemy", value))
end

-- Taken the first time the addon touches the CVar on this character, so turning
-- the setting off can put back what was actually there rather than a guess.
-- Empty is the sentinel for "not remembered yet"; the CVar itself only ever
-- answers a number as a string.
local function Remember()
	if not ns.dbc or ns.dbc.softPrior ~= "" then
		return
	end
	ns.dbc.softPrior = Read() or OFF
end

-- Nil when the setting is off, which means the CVar is the player's again and
-- this file must not touch it.
local function Wanted()
	if not ns.db.softAuto then
		return nil
	end
	return UnitAffectingCombat("player") and OFF or ON
end

-- Returns false when the client refused, so the caller can say so.
function SoftTarget.Apply()
	local want = Wanted()
	if not want then
		return true
	end
	Remember()

	if applied == want and Read() == want then
		return true
	end

	if not Write(want) then
		pending = true
		if not warned then
			warned = true
			ns.Print("this client would not change action targeting just now. It will be set again when you leave combat.")
		end
		return false
	end

	-- Read it back. A SetCVar that raises is caught above, but a client that
	-- accepts the call and ignores the name leaves no trace at all, and the
	-- difference between the setting working and the setting only intending to
	-- is the whole reason this file exists.
	if Read() ~= want then
		if not warnedIgnored then
			warnedIgnored = true
			ns.Print("this client accepted the action targeting change and did not make it, so SoftTargetEnemy is not a CVar it honours. /wk charge soft off stops the addon trying.")
		end
		return false
	end

	applied, pending = want, nil
	return true
end

-- Put the character's own value back. Called when the setting is turned off,
-- because a setting that leaves the CVar wherever it happened to land is a
-- setting that quietly edits your client config.
function SoftTarget.Restore()
	if not ns.dbc or ns.dbc.softPrior == "" then
		applied = nil
		return
	end
	Write(ns.dbc.softPrior)
	ns.dbc.softPrior = ""
	applied = nil
end

-- Always reports what the CVar actually says, never what this file meant to set
-- it to. A status line that echoes intent cannot witness anything, and this one
-- is the only witness there is until someone reads config-cache.wtf.
function SoftTarget.Describe()
	local value = Read()
	if value == nil then
		return "this client will not say"
	end
	local on = (tonumber(value) or 0) > 0

	if not ns.db.softAuto then
		return ("manual, currently %s"):format(on and "on" or "off")
	end

	local want = Wanted()
	if want and on ~= (want == ON) then
		return ("auto, but the client is holding it %s"):format(on and "on" or "off")
	end
	return ("auto, %s %s"):format(on and "on" or "off",
		UnitAffectingCombat("player") and "for this fight" or "out of combat")
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" and pending then
		pending = nil
	end
	SoftTarget.Apply()
end)
