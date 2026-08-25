local ADDON, ns = ...

local ChargeMarker = {}
ns.ChargeMarker = ChargeMarker

-- The icon that rides above the mob the Charge macro would pick, which out of
-- combat is the mob you are aiming at, so you aim the ability by looking
-- rather than by targeting. Out of combat only, because that is the only time
-- Charge fires.

local UPDATE_INTERVAL = 0.05 -- this one tracks the camera, so it runs hotter than the HUD icon
local PLATE_GAP = 8
local FALLBACK_TEXTURE = "Interface\\Icons\\Ability_Warrior_Charge"

local frame, icon, border, cooldown, timerText
local shownStart, shownDuration = 0, 0
local attachedPlate, attachedAnchor, appliedSize, appliedOffset, appliedScale
local shownColor, shownGrey, shownAlpha
local warnedSoftTarget
local warnedNameplates = false

local function Build()
	frame = CreateFrame("Frame", "WarriorKitChargeMarker", UIParent)
	frame:EnableMouse(false) -- never steal a click meant for the nameplate underneath
	frame:Hide()

	border = frame:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0, 0, 0, 1)

	icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", -2, 2)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetTexture(ns.Charge.Texture("charge") or FALLBACK_TEXTURE)

	cooldown = CreateFrame("Cooldown", "WarriorKitChargeMarkerCooldown", frame, "CooldownFrameTemplate")
	cooldown:SetAllPoints(icon)
	if cooldown.SetHideCountdownNumbers then
		cooldown:SetHideCountdownNumbers(true) -- the addon draws its own timer
	end

	timerText = frame:CreateFontString(nil, "OVERLAY")
	timerText:SetPoint("CENTER")
	timerText:SetFont((GameFontNormal:GetFont()), 14, "OUTLINE")
end

local function Detach()
	if not frame then
		return
	end
	if not frame:IsShown() and not attachedPlate then
		return
	end
	frame:Hide()
	frame:ClearAllPoints()
	frame:SetParent(UIParent)
	attachedPlate, attachedAnchor = nil, nil
end

-- Enemy bars ride on the plate too, so sit above them when one is there and on
-- the plate itself when it is not.
local function AnchorFor(plate, unit)
	local widget = ns.EnemyBars and ns.EnemyBars.WidgetFor and ns.EnemyBars.WidgetFor(unit)
	if widget and widget:IsShown() then
		return widget
	end
	return plate
end

local function AttachTo(plate, unit)
	local db = ns.db
	if attachedPlate ~= plate then
		frame:SetParent(plate)
		frame:SetFrameStrata(plate:GetFrameStrata())
		-- One above the enemy bar widget, which takes plate level + 5.
		frame:SetFrameLevel(math.min(plate:GetFrameLevel() + 6, 100))
		if frame.SetIgnoreParentAlpha then
			frame:SetIgnoreParentAlpha(true) -- plates fade with distance, the marker should not
		end
		attachedPlate = plate
		attachedAnchor = nil
	end

	-- The plate lives under WorldFrame, so cancel its scale out and the size in
	-- the settings stays the size you see.
	--
	-- Guarded, because SetScale dirties the layout of this frame and of all
	-- four regions inside it, this runs twenty times a second, and the answer
	-- changes when you change UI scale rather than when the ticker fires.
	local plateScale, uiScale = ns.Measure(plate, "GetEffectiveScale"), UIParent:GetEffectiveScale()
	if plateScale and plateScale > 0 and uiScale and uiScale > 0 then
		local scale = uiScale / plateScale
		if scale ~= appliedScale then
			appliedScale = scale
			frame:SetScale(scale)
		end
	end

	local anchor = AnchorFor(plate, unit)
	if anchor ~= attachedAnchor or appliedSize ~= db.chargeMarkerSize or appliedOffset ~= db.chargeMarkerOffset then
		frame:SetSize(db.chargeMarkerSize, db.chargeMarkerSize)
		frame:ClearAllPoints()
		frame:SetPoint("BOTTOM", anchor, "TOP", 0, PLATE_GAP + db.chargeMarkerOffset)
		attachedAnchor, appliedSize, appliedOffset = anchor, db.chargeMarkerSize, db.chargeMarkerOffset
	end
end

local function WarnIfNameplatesOff()
	if warnedNameplates then
		return
	end
	if not C_NamePlate or (GetCVarBool and not GetCVarBool("nameplateShowEnemies")) then
		warnedNameplates = true
		ns.Print("the charge marker needs enemy nameplates to have something in the world to sit on. Press V.")
	end
end

-- Said once, and only when it is switched off rather than merely unproven,
-- because off is the one state you can do something about. Silent while
-- SoftTarget owns the CVar: there off out of combat means a write the client
-- refused, which that file has already said, and telling you to set a CVar the
-- addon is driving is advice that fights itself.
local function WarnIfSoftTargetOff()
	if warnedSoftTarget or ns.db.softAuto then
		return
	end
	if ns.Charge.SoftTargetState() == "off" then
		warnedSoftTarget = true
		ns.Print("action targeting is off, so the marker only follows your target and your cursor. /wk charge soft on hands it to the addon, which turns it on out of combat and off in it.")
	end
end

function ChargeMarker.Update()
	if not frame then
		return
	end
	local db = ns.db

	if not db.charge or not db.chargeMarker or not ns.Charge.Known("charge") then
		Detach()
		return
	end

	local key, unit, plate = ns.Charge.Pick()
	-- This ticker is the fast one, so it drives the button too. The marker and
	-- the macro then name the same mob in the same frame.
	ns.ChargeIcon.SyncMacro()

	-- An aiming aid for the pull. In combat the button switches to Intervene or
	-- Intercept, both aimed with the cursor, so there is nothing for a world
	-- icon to add and the HUD icon carries that state instead.
	if key ~= "charge" then
		Detach()
		return
	end
	if not unit or not plate then
		Detach()
		WarnIfNameplatesOff()
		WarnIfSoftTargetOff()
		return
	end

	local status, start, duration = ns.Charge.State(key, unit)
	local ready = status == "ready"
	if db.chargeMode == "ready" and not ready then
		Detach()
		return
	end

	AttachTo(plate, unit)

	if status == "cooldown" then
		if start ~= shownStart or duration ~= shownDuration then
			cooldown:SetCooldown(start, duration)
			shownStart, shownDuration = start, duration
		end
		local remaining = start + duration - GetTime()
		timerText:SetText(remaining >= 10 and ("%d"):format(remaining) or ("%.1f"):format(remaining))
	else
		if shownDuration ~= 0 then
			cooldown:SetCooldown(0, 0)
			shownStart, shownDuration = 0, 0
			timerText:SetText("")
		end
	end

	-- One shared look, so the icon in the world and the icon on the HUD say the
	-- same thing: colour when the charge lands, grey when it does not.
	--
	-- Guarded together on the colour table's identity, because they are the
	-- three module constants in Charge.lua and this is the fast ticker. Three
	-- writes twenty times a second is what a mob standing still used to cost.
	local color, grey, alpha = ns.Charge.Look(status)
	if color ~= shownColor or grey ~= shownGrey or alpha ~= shownAlpha then
		shownColor, shownGrey, shownAlpha = color, grey, alpha
		border:SetColorTexture(color[1], color[2], color[3], 1)
		icon:SetDesaturated(grey)
		frame:SetAlpha(alpha)
	end
	frame:Show()
end

-- Nothing to lay out or lock: the marker lives on a nameplate, not on a spot
-- you drag. Both exist so the slash handler can drive every module the same.
function ChargeMarker.ApplyLayout()
	appliedSize = nil -- force the next Update to re-anchor at the new size
end

function ChargeMarker.ApplyLock()
end

local events = CreateFrame("Frame")
local elapsed = 0

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		Detach()
		return
	end

	Build()
	ChargeMarker.Update()
	-- The ticker hangs off this frame, which is never hidden. On the marker
	-- itself it would stop the moment the marker hid and never come back.
	events:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed >= UPDATE_INTERVAL then
			elapsed = 0
			ChargeMarker.Update()
		end
	end)
end)
