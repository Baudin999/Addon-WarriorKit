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

local frame
local attachedPlate, attachedAnchor, appliedSize, appliedOffset, appliedScale
local warnedSoftTarget
local warnedNameplates = false

-- What the last drawn marker was drawn against. The tick runs at 20 Hz for
-- softenemy, which the client answers with no event of its own, and everything
-- past the pick is a redraw of the same square unless one of these five moved.
local drawnKey, drawnUnit, drawnPlate, drawnAnchor, drawnEpoch

-- Public because a setting is not an event. Feature.lua writes chargeMode and
-- then asks for a pass, and the pass has to be told that the answer it holds
-- was drawn under the old rule.
function ChargeMarker.Forget()
	drawnKey, drawnUnit, drawnPlate, drawnAnchor, drawnEpoch = nil, nil, nil, nil, nil
end

local function Build()
	-- The same square the HUD icon is, out of the same file, so the two cannot
	-- drift apart again. What is left here is where it sits: a nameplate the
	-- addon does not own, at a scale that has to be cancelled out.
	frame = ns.UI.Ability.New(UIParent, "WarriorKitChargeMarker", nil, ns.UI.Ability.SHOUT)
	frame:EnableMouse(false) -- never steal a click meant for the nameplate underneath
	frame:Hide()
end

local function Detach()
	if not frame then
		return
	end
	ChargeMarker.Forget()
	if not frame:IsShown() and not attachedPlate then
		return
	end
	frame:Hide()
	frame:ClearAllPoints()
	frame:SetParent(UIParent) -- unguarded: the two returns above leave only a marker that is up
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

-- The anchor is handed in rather than asked for again. Update has to know it to
-- decide whether this pass is worth making at all: an enemy bar appearing on a
-- plate moves the marker up and does it without changing the pick, so the
-- anchor is the fifth thing compared and this would be the second read of it.
local function AttachTo(plate, anchor)
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

	if anchor ~= attachedAnchor or appliedSize ~= db.chargeMarkerSize or appliedOffset ~= db.chargeMarkerOffset then
		-- The size is in this frame's own units. The marker rides a nameplate
		-- and cancels the plate's scale out above rather than joining the
		-- addon's pixel grid, so there is no design number to convert here and
		-- Ability.Size takes the setting as written.
		ns.UI.Ability.Size(frame, db.chargeMarkerSize)
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

	-- Everything below this line is the same square drawn again unless one of
	-- these moved. The pick above is what the 20 Hz is for: softenemy follows
	-- the camera and the client announces nothing when it changes. The status
	-- has four events behind it and a range watch, which is what the epoch is,
	-- and the anchor is the enemy bar arriving under the marker.
	local anchor = AnchorFor(plate, unit)
	local epoch = ns.Charge.StateEpoch(key, unit)
	if key == drawnKey and unit == drawnUnit and plate == drawnPlate
		and anchor == drawnAnchor and epoch == drawnEpoch then
		return
	end

	local status, start, duration = ns.Charge.State(key, unit)
	if db.chargeMode == "ready" and status ~= "ready" then
		Detach()
	else
		AttachTo(plate, anchor)

		-- The art, the swipe, the timer and the status colour, all of it guarded
		-- against what was drawn last. This was twenty-eight lines here and the
		-- same twenty-eight in Charge/Icon.lua, which is what UI/Ability.lua was
		-- extracted to end. The world icon and the HUD icon now say the same
		-- thing because they run the same code, not because two copies agree
		-- today.
		ns.UI.Ability.Draw(frame, ns.Charge.Texture(key) or FALLBACK_TEXTURE,
			status, start, duration)
		frame:Show()
	end

	-- Written last, and after the Detach above rather than before it, because
	-- Detach forgets. "Ready only, and it is not ready" is a pick this pass has
	-- already answered, and forgetting it would ask again twenty times a second
	-- for as long as the cooldown runs.
	drawnKey, drawnUnit, drawnPlate, drawnAnchor, drawnEpoch = key, unit, plate, anchor, epoch
end

-- Nothing to lay out or lock: the marker lives on a nameplate, not on a spot
-- you drag. Both exist so the slash handler can drive every module the same.
function ChargeMarker.ApplyLayout()
	-- All three, because the next Update now decides whether to run at all
	-- before AttachTo gets to compare anything. A settings change and a rescale
	-- move the size and the plate's scale without moving the pick, so the pass
	-- has to be told to make one.
	appliedSize, appliedScale = nil, nil
	ChargeMarker.Forget()
end

function ChargeMarker.ApplyLock()
end

local events = CreateFrame("Frame")
local tick -- the update ticker, armed once, see below

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		Detach()
		return
	end

	-- The marker aims a charge, so it is worth nothing to anyone who cannot
	-- cast one. Unregistered on another class rather than built and left
	-- hidden, because the cost this file carries is the twenty-a-second
	-- nameplate scan below and a hidden frame would still be paying it.
	if not ns.Charge.Available() then
		events:UnregisterAllEvents()
		return
	end

	Build()
	ChargeMarker.Update()
	-- The ticker hangs off this frame, which is never hidden. On the marker
	-- itself it would stop the moment the marker hid and never come back.
	--
	-- Armed once. UI.Ticker appends and refuses a second tick of this name on
	-- this frame, so a branch that arms one has to be a branch that runs once.
	if not tick then
		tick = ns.UI.Ticker(events, UPDATE_INTERVAL, "marker", ChargeMarker.Update)
	end
end)
