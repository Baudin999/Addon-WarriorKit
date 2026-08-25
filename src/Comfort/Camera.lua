local ADDON, ns = ...

-- How far the camera will pull back.
--
-- cameraDistanceMaxZoomFactor multiplies the base camera distance. The client
-- ships it at 1.9 and will take a good deal more, and the difference is the
-- difference between fighting a boss you can see and fighting its shins.
--
-- One CVar and no frame, so this part has no ticker and nothing to lock.

local Camera = {}
ns.Camera = Camera

local CVAR = "cameraDistanceMaxZoomFactor"

-- The far end. Leatrix Plus writes 4.0 into this CVar on both of these clients
-- and has done for years, which is what says the ceiling here is 4 rather than
-- the 2.6 a retail client clamps to.
--
-- Believed only as far as the readback below. A client that quietly clamps is
-- reported as clamping rather than as having taken the number.
local FURTHEST = 4.0

-- The documented default, and what Leatrix writes when its own setting goes
-- off. Only reached where the client will not state its own default.
local FALLBACK = 1.9

-- What this client says the default is, so turning the setting off hands the
-- CVar back at the client's number rather than parking it on one this addon
-- picked. Nothing installed here calls GetCVarDefault, so it is probed by name
-- rather than trusted.
local function Default()
	if type(_G.GetCVarDefault) == "function" then
		local value = tonumber(_G.GetCVarDefault(CVAR))
		if value then
			return value
		end
	end
	return FALLBACK
end

-- pcall for the same reason Charge/SoftTarget.lua pcalls its own SetCVar: a
-- client that does not carry this CVar name raises rather than refusing, and a
-- camera that will not zoom is worth less than an error at every login.
function Camera.Apply()
	pcall(SetCVar, CVAR, ns.db.maxZoom and FURTHEST or Default())
end

-- What the CVar says now, which is not always what Apply asked for.
function Camera.Current()
	return tonumber(GetCVar(CVAR))
end

function Camera.Describe()
	local current = Camera.Current()
	if not current then
		return "this client does not answer for " .. CVAR
	end
	if not ns.db.maxZoom then
		return ("off, factor %.1f, the client's own default"):format(current)
	end
	if current < FURTHEST then
		return ("asked for %.1f, this client kept %.1f"):format(FURTHEST, current)
	end
	return ("factor %.1f, the furthest this client goes"):format(current)
end

-- The CVar is the client's, not the addon's, and it survives a logout. So it is
-- written at every entry to the world rather than once at login: a reload, a
-- zone, or anything else that put it back leaves the setting saying one thing
-- and the camera doing another.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function()
	Camera.Apply()
end)
