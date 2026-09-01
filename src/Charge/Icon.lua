local ADDON, ns = ...

local ChargeIcon = {}
ns.ChargeIcon = ChargeIcon

-- The HUD icon is also the button that casts. It is a secure action button
-- carrying a macro the addon rewrites out of combat, so the mob the marker
-- points at and the mob the button charges are the same mob by construction,
-- not by two pieces of code guessing alike.
--
-- Bind it with `/wk bind <key>`, or put `/click WarriorKitChargeButton` in a
-- normal macro and drag that to an action bar.

local BUTTON_NAME = "WarriorKitChargeButton"
ChargeIcon.BUTTON_NAME = BUTTON_NAME

local FALLBACK_TEXTURE = "Interface\\Icons\\Ability_Warrior_Charge"
local UPDATE_INTERVAL = 0.1

local frame, handle, binder
local lastMacro, securePending
local lastUnit, lastWeapon, lastEpoch

--------------------------------------------------------------------------
-- The macro the button runs
--------------------------------------------------------------------------

-- Attributes cannot be rewritten during combat, so everything the button does
-- in combat has to be a macro conditional rather than a decision the addon
-- makes. Only the out-of-combat Charge target is resolved in Lua, and it
-- carries `nocombat` because the unit token in it goes stale the moment combat
-- starts. Without that guard a stale token would rip your target off the mob
-- you are tanking.
local function MacroText(unit)
	local lines = { "#showtooltip" }

	if unit and unit ~= "target" then
		lines[#lines + 1] = ("/target [nocombat,@%s,harm,nodead]"):format(unit)
	end
	-- A backstop under the line above rather than an alternative to it.
	-- Whether @softenemy resolves inside a macro conditional on 2.5.6 is
	-- unproven, and if it silently does not, this is what stops a press with
	-- nothing targeted from being a press that does nothing. When the line
	-- above did work, the target exists and is alive, so this one is a no-op.
	lines[#lines + 1] = "/targetenemy [noexists][dead]"

	-- Out of combat: Charge the mob the marker is sitting on.
	local charge, battle = ns.Charge.Name("charge"), ns.Charge.StanceName(1)
	if charge then
		if battle then
			lines[#lines + 1] = "/cast [nocombat,nostance:1] " .. battle
		end
		lines[#lines + 1] = "/cast [nocombat] " .. charge
	end

	-- In combat the cursor decides. help and harm are exclusive, so only one of
	-- these two pairs can ever fire on a press.
	local intervene, defensive = ns.Charge.Name("intervene"), ns.Charge.StanceName(2)
	if intervene then
		if defensive then
			lines[#lines + 1] = "/cast [combat,@mouseover,help,nodead,nostance:2] " .. defensive
		end
		lines[#lines + 1] = "/cast [combat,@mouseover,help,nodead] " .. intervene
	end

	local intercept, berserker = ns.Charge.Name("intercept"), ns.Charge.StanceName(3)
	if intercept then
		if berserker then
			lines[#lines + 1] = "/cast [combat,@mouseover,harm,nodead,nostance:3] " .. berserker
		end
		lines[#lines + 1] = "/cast [combat,@mouseover,harm,nodead] " .. intercept
	end

	-- nocombat on the swap: pressing this mid-fight with the wrong weapon on
	-- would otherwise reset your swing timer for nothing.
	local weapon = ns.db.chargeWeapon
	if weapon and weapon ~= "" then
		lines[#lines + 1] = ("/equipslot [nocombat] %d %s"):format(ns.Gear.MAINHAND, weapon)
	end
	lines[#lines + 1] = "/startattack"

	return table.concat(lines, "\n")
end

-- Called from both tickers so the button never lags a frame behind the marker,
-- which between them is thirty calls a second.
--
-- Guarded on what MacroText reads rather than on the string it returns.
-- Comparing the returned string still built it: a fresh table, a dozen
-- formatted lines and a concat, thrown away on every call but the rare one
-- that changed anything. The three inputs are the unit, the weapon setting and
-- the spell name epoch, and nothing else in MacroText can move without one of
-- them moving.
--
-- Off when the feature is off, because ApplySecure clears the button's type
-- attribute in that state and a macro nothing can press is not worth writing.
function ChargeIcon.SyncMacro()
	if not frame or not ns.db.charge or InCombatLockdown() then
		return
	end
	local _, unit = ns.Charge.Pick()
	local weapon = ns.db.chargeWeapon
	local epoch = ns.Charge.NameEpoch()
	if lastMacro and unit == lastUnit and weapon == lastWeapon and epoch == lastEpoch then
		return
	end
	lastUnit, lastWeapon, lastEpoch = unit, weapon, epoch

	local text = MacroText(unit)
	if text ~= lastMacro then
		frame:SetAttribute("macrotext", text)
		lastMacro = text
	end
end

--------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------

local function Build()
	-- The square itself is UI/Ability.lua's now: the backing, the cropped icon,
	-- the cooldown swipe with the client's numbers off, the timer, and the four
	-- edge textures that carry the status colour. What is left in this file is
	-- what makes it a charge button rather than a square, which is the macro,
	-- the key and the drag handle.
	frame = ns.UI.Ability.New(UIParent, BUTTON_NAME, "SecureActionButtonTemplate",
		ns.UI.Ability.SHOUT)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForClicks("AnyDown")

	-- The drag handle, which is a plain frame laid over the button and shown
	-- only while the frames are unlocked.
	--
	-- It exists because the two jobs cannot share one frame. Placing the icon
	-- needs the mouse; casting from it must not fire on the press that starts
	-- a drag, and the button registers its clicks on the down edge. The old
	-- answer was to clear the button's type attribute while unlocked, which
	-- also killed the bound key: the override stayed on the key, the key
	-- clicked the button, and the button had no action. Charge silently did
	-- nothing until you locked the frames again, and nothing said so.
	--
	-- A separate frame over the top gives each job its own: this one takes
	-- every click while you are placing, the button keeps its action the whole
	-- time, and the key works in both states.
	handle = CreateFrame("Frame", nil, UIParent)
	handle:SetAllPoints(frame)
	handle:SetFrameStrata("HIGH")
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle:Hide()

	handle:SetScript("OnDragStart", function()
		if not ns.db.locked and not InCombatLockdown() then
			frame:StartMoving()
		end
	end)
	handle:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		local point, _, relativePoint, x, y = frame:GetPoint()
		ns.db.point = { point, "UIParent", relativePoint, x, y }
	end)

	ns.Tip.Hang(handle, function()
		local key, unit = ns.Charge.Pick()
		local at = "hover a party member or a mob"
		if unit and UnitExists(unit) then
			at = UnitName(unit) or "?"
		elseif key == "charge" then
			at = "nothing in view"
		end
		return {
			kind = "note",
			title = ns.Charge.Name(key) or key,
			lines = { at },
		}
	end)
end

--------------------------------------------------------------------------
-- Secure state
--
-- Everything a protected frame will not let you touch in combat lives in one
-- place. If combat is up the work is deferred to PLAYER_REGEN_ENABLED, which
-- is also why nothing below ever calls Show or Hide: visibility runs on alpha,
-- which is not protected, so the icon can appear and vanish mid-fight.
--------------------------------------------------------------------------

-- Returns false when combat deferred the work, so the caller can say so.
function ChargeIcon.ApplySecure()
	if not frame then
		return true
	end
	if InCombatLockdown() then
		securePending = true
		return false
	end
	securePending = nil

	local db = ns.db
	-- The button never takes the mouse, in either state. A mouse enabled frame
	-- swallows every button that lands on it, including the right button drag
	-- that turns the camera, and this icon sits near the middle of the screen
	-- where that drag starts. The two documented ways to press it are the
	-- bound key and /click, neither of which needs the mouse, and while you
	-- are placing it the handle above takes the clicks instead.
	frame:EnableMouse(false)
	frame:RegisterForDrag()
	-- Not conditioned on the lock. Whether the frames are locked is a question
	-- about dragging, and an unlocked frame that cannot cast is a charge key
	-- that quietly does nothing.
	frame:SetAttribute("type", db.charge and "macro" or nil)
	handle:SetShown(not db.locked)
	return true
end

--------------------------------------------------------------------------
-- The key
--
-- An override binding, never a real one. SetBindingClick would overwrite the
-- key in the live binding set, and the next SaveBindings, which the Key
-- Bindings panel calls when you click Okay, would make that permanent and lose
-- whatever you had on the key. Overrides sit on top of the binding set instead
-- and never touch what is saved.
--
-- The override is held only out of combat, so the key does its normal job
-- during the fight. That needs a secure state driver, because clearing an
-- override at PLAYER_REGEN_DISABLED is already too late: combat lockdown is up
-- by the time the event fires. A snippet running inside the restricted
-- environment has no such problem.
--------------------------------------------------------------------------

local BIND_SNIPPET = [[
	local key = self:GetAttribute("chargeKey")
	local release = self:GetAttribute("chargeKeyRelease")
	self:ClearBindings()
	if key and key ~= "" and not (release and state == "combat") then
		self:SetBindingClick(true, key, button, "LeftButton")
	end
]]

-- The state driver is the only way to release the key mid-fight, because
-- clearing an override at PLAYER_REGEN_DISABLED is already too late. It is
-- also the one piece of this file no addon in the install proves exists, so a
-- failed probe drops back to a plain override held the whole time, and
-- ChargeIcon.CanRelease() reports which path is live.
local function BuildBinder(button)
	if not _G.RegisterStateDriver then
		return
	end
	local ok, handler = pcall(CreateFrame, "Frame", "WarriorKitChargeBinder", UIParent,
		"SecureHandlerStateTemplate")
	if not ok or not handler or not handler.Execute then
		return
	end
	binder = handler
	binder:SetFrameRef("chargeButton", button)
	binder:Execute([[ button = self:GetFrameRef("chargeButton") ]])
	binder:SetAttribute("_onstate-combat", "state = newstate\n" .. BIND_SNIPPET)
	RegisterStateDriver(binder, "combat", "[combat] combat; [nocombat] free")
end

function ChargeIcon.CanRelease()
	return binder ~= nil
end

function ChargeIcon.ApplyBinding()
	if not frame or InCombatLockdown() then
		return false
	end
	local key = ns.db.chargeKey or ""

	-- Clear both paths every time, so switching between them cannot leave a
	-- stale override behind.
	ClearOverrideBindings(frame)
	if binder then
		binder:SetAttribute("chargeKey", key)
		binder:SetAttribute("chargeKeyRelease", ns.db.chargeKeyRelease and true or false)
		binder:Execute("state = 'free'\n" .. BIND_SNIPPET)
	elseif key ~= "" then
		SetOverrideBindingClick(frame, true, key, BUTTON_NAME, "LeftButton")
	end
	return true
end

-- Returns the binding the key was carrying, "" when it carried none, or nil
-- plus a reason when the key cannot be taken right now. The displaced action is
-- read with the override dropped, so it reports the real binding rather than
-- our own click binding, and it is kept so the UI can keep showing it.
function ChargeIcon.Bind(key)
	-- No button on another class, so there is nothing for a key to press. Said
	-- before the combat check, because "not in combat" is advice that would
	-- never come true here.
	if not frame then
		return nil, ns.Charge.Refusal() .. "."
	end
	if InCombatLockdown() then
		return nil, "keys cannot be rebound in combat."
	end
	key = key or ""
	ns.db.chargeKey = ""
	ChargeIcon.ApplyBinding()

	local displaced = key ~= "" and GetBindingAction(key) or ""
	ns.db.chargeKey = key
	ns.db.chargeKeyDisplaced = displaced
	ChargeIcon.ApplyBinding()
	return displaced
end

--------------------------------------------------------------------------

function ChargeIcon.ApplyLayout()
	if not frame then
		return
	end
	local db = ns.db
	-- The size is in this frame's own units and not in design pixels: the
	-- charge button rides UIParent's scale rather than the addon's grid, which
	-- is the state UI/Pixel.lua calls the honest degradation. Ability.Size
	-- takes it as given and only the hairline round the art is asked for in
	-- real pixels.
	ns.UI.Ability.Size(frame, db.size)
	frame:ClearAllPoints()
	frame:SetPoint(db.point[1], UIParent, db.point[3], db.point[4], db.point[5])
end

function ChargeIcon.ApplyLock()
	local applied = ChargeIcon.ApplySecure()
	ChargeIcon.Update()
	return applied
end

function ChargeIcon.Update()
	if not frame then
		return
	end
	local db = ns.db
	local Ability = ns.UI.Ability

	-- Unlocked means you are placing it, so it stays visible whatever the
	-- spell is doing. Written as a fade rather than as an alpha, because the
	-- look the status carries is the other half of the same number and
	-- Ability.Draw multiplies the two. Two writers on one SetAlpha is what
	-- this file used to be, and the second one won by being further down.
	local placing = not db.locked

	-- With the feature off there is no ability to ask about, so the square
	-- keeps Charge's own art at the status that greys it and fades to nothing
	-- unless you are placing it. Deliberately not ns.Charge.Texture(key) with
	-- a key from the last pass: an absent key raises on the table write inside
	-- Texture, and the last pass is not guaranteed to have had one.
	if not db.charge then
		frame.fade = placing and 1 or 0
		Ability.Draw(frame, ns.Charge.Texture("charge") or FALLBACK_TEXTURE, "unknown")
		return
	end

	-- The icon shows whichever of the three the button would cast right now,
	-- judged against the unit it would take.
	local key, unit = ns.Charge.Pick()
	local status, start, duration = ns.Charge.State(key, unit)

	-- Mode "ready" is the setting that keeps the icon off the screen until a
	-- press would land, and placing the frame overrides it, or you could not
	-- find the thing you were dragging.
	local hidden = not placing and db.chargeMode == "ready" and status ~= "ready"
	frame.fade = hidden and 0 or 1

	Ability.Draw(frame, ns.Charge.Texture(key) or FALLBACK_TEXTURE, status, start, duration)
end

local events = CreateFrame("Frame")

local elapsed = 0
local function OnUpdate(_, delta)
	elapsed = elapsed + delta
	if elapsed >= UPDATE_INTERVAL then
		elapsed = 0
		ns.Perf.Start("icon")
		ChargeIcon.SyncMacro()
		ChargeIcon.Update()
		ns.Perf.Stop("icon")
	end
end

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		-- Nothing here is built on another class. The button casts Charge,
		-- Intervene and Intercept and nothing else, so on a hunter it would be
		-- a secure frame sitting on a key override with a ten-a-second ticker
		-- behind it, all to draw an ability that cannot be cast. Unregister
		-- rather than return, so the file is silent for the rest of the
		-- session instead of waking on every SPELLS_CHANGED to decide again.
		if not ns.Charge.Available() then
			events:UnregisterAllEvents()
			return
		end
		Build()
		ChargeIcon.ApplyLayout()
		ChargeIcon.ApplySecure()
		BuildBinder(frame)
		ChargeIcon.ApplyBinding()
		frame:Show() -- the only Show there is, before any combat can block it
		-- The ticker lives on this frame, which is never hidden. On the button
		-- it would stop the moment the button hid and never come back.
		events:SetScript("OnUpdate", OnUpdate)
	elseif event == "PLAYER_REGEN_ENABLED" then
		if securePending then
			ChargeIcon.ApplySecure()
		end
		ChargeIcon.SyncMacro()
	end
	ChargeIcon.Update()
end)

-- The client rebuilds its binding set and drops every override with it, so the
-- key is taken again each time it does. See ns.Rebind in Core/Core.lua. Silent
-- on a class with no button, because ApplyBinding refuses without one.
ns.Rebind(ChargeIcon.ApplyBinding)
