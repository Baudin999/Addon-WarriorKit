local ADDON, ns = ...

local SKULL, CROSS, MOON = 8, 7, 5
local DEDUPE_WINDOW = 0.5

local Marking = {}
ns.Marking = Marking

-- The three marks the addon binds, in the order they appear in the panel and in
-- /wk status. One list, read by Keys.lua for the override bindings and by
-- Feature.lua for the key fields, so adding a fourth mark is one entry here and
-- one Bindings.xml block rather than an edit in three files.
--
-- `id` is what SetOverrideBindingClick passes back to Marking.Key as the button
-- name, and what /wk markkey takes as its first word. `key` names the setting
-- inside ns.db.markBinds. Blizzard's own indices: 1 star, 2 circle, 3 diamond,
-- 4 triangle, 5 moon, 6 square, 7 cross, 8 skull.
Marking.MARKS = {
	{ id = "skull", icon = SKULL, label = "Skull" },
	{ id = "cross", icon = CROSS, label = "Cross" },
	{ id = "moon",  icon = MOON,  label = "Moon" },
}

local BY_ID = {}
for _, mark in ipairs(Marking.MARKS) do
	BY_ID[mark.id] = mark
end

local lastComplaint = 0
local lastGUID, lastIcon, lastMarkTime = nil, nil, 0

local function CanMark()
	if IsInRaid() then
		return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
	end
	return true
end

local function Mark(unit, icon)
	if not UnitExists(unit) then
		return
	end
	if not CanMark() then
		local now = GetTime()
		if now - lastComplaint > 5 then
			lastComplaint = now
			ns.Print("marks need raid leader or assistant.")
		end
		return
	end

	-- A nameplate click also changes your target, so both detection paths can
	-- fire for one physical click. First one through wins for half a second.
	--
	-- The icon is part of the key. Keyed on the GUID alone this swallowed a
	-- deliberate second click: mark a mob skull, decide within half a second it
	-- should be a cross, and the cross never landed.
	local now = GetTime()
	local guid = UnitGUID(unit)
	if guid and guid == lastGUID and icon == lastIcon and (now - lastMarkTime) < DEDUPE_WINDOW then
		return
	end
	lastGUID, lastIcon, lastMarkTime = guid, icon, now

	-- Clicking a unit that already carries the icon clears it.
	if GetRaidTargetIndex(unit) == icon then
		SetRaidTarget(unit, 0)
	else
		SetRaidTarget(unit, icon)
	end
end

-- "mouseover" is set whether the cursor sits on a mob in the world, a
-- nameplate, or a unit frame, so every entry point can share it.
local function MarkMouseover(icon)
	if UnitExists("mouseover") then
		Mark("mouseover", icon)
	elseif UnitExists("target") then
		Mark("target", icon)
	end
end

-- Nameplates and unit frames report which button was pressed. Shift is read on
-- the left button as well, so ctrl-shift means cross on a plate exactly as it
-- does out in the world. It used to mean skull here and cross there, on the
-- same mob, for the same keys.
function Marking.OnClick(_, button)
	if not ns.db.marking or not IsControlKeyDown() then
		return
	end
	if button == "LeftButton" then
		MarkMouseover(IsShiftKeyDown() and CROSS or SKULL)
	elseif button == "RightButton" then
		MarkMouseover(CROSS)
	end
end

-- The mouse button path, reached through the override bindings in Keys.lua.
-- The click name is the mark's id, so this stays one lookup however many marks
-- the list grows to.
--
-- Hover only, with no fall back to your target: a ctrl-click that lands on
-- terrain has nothing under it and must do nothing. The keybindings below fall
-- back on purpose, because a key pressed with the cursor nowhere in particular
-- still has an obvious subject.
function Marking.Key(click)
	if not ns.db.marking then
		return
	end
	local mark = BY_ID[click]
	if mark and UnitExists("mouseover") then
		Mark("mouseover", mark.icon)
	end
end

-- Keybinding entry points, see Bindings.xml. These are the panel's entries and
-- they are separate functions rather than one list walker because a Bindings.xml
-- block names a global directly and cannot be generated.
function WarriorKit_MarkSkull()
	MarkMouseover(SKULL)
end

function WarriorKit_MarkCross()
	MarkMouseover(CROSS)
end

function WarriorKit_MarkMoon()
	MarkMouseover(MOON)
end

BINDING_HEADER_WARRIORKIT = "WarriorKit"
BINDING_NAME_WARRIORKIT_MARK_SKULL = "Mark mouseover with skull"
BINDING_NAME_WARRIORKIT_MARK_CROSS = "Mark mouseover with cross"
BINDING_NAME_WARRIORKIT_MARK_MOON = "Mark mouseover with moon"

local hooked = {}

local function Hook(frame)
	if frame and frame.HookScript and not hooked[frame] then
		hooked[frame] = true
		frame:HookScript("OnMouseDown", Marking.OnClick)
	end
end

-- A frame this file did not know about, hooked from outside.
--
-- The party and raid blocks are the caller. Marking hooks frames by name and
-- PartyMemberFrame1 through 4 are on the list below, so hiding Blizzard's party
-- frames takes ctrl-click marking on a party member off the screen with them.
-- The blocks that replace them are made by a secure header at whatever moment
-- somebody joins, so there is no name to put on that list and no login at which
-- to look for one.
--
-- Called from UnitFrames/Feature.lua rather than from the file that makes the
-- button, because a behaviour file may not name a file outside its own folder.
function Marking.Watch(frame)
	Hook(frame)
end

-- Frames that handle their own clicks instead of passing them to the world.
local UNIT_FRAMES = {
	"PlayerFrame", "TargetFrame", "TargetFrameToT", "FocusFrame", "FocusFrameToT",
	"PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
	"PartyMemberFrame1PetFrame", "PartyMemberFrame2PetFrame",
	"PartyMemberFrame3PetFrame", "PartyMemberFrame4PetFrame",
	"PetFrame",
}

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
if C_NamePlate then
	events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
end
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		for _, name in ipairs(UNIT_FRAMES) do
			Hook(_G[name])
		end
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		local plate = C_NamePlate.GetNamePlateForUnit(arg1)
		if plate then
			Hook(plate.UnitFrame or plate)
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		-- The fallback for a client that will not take the ctrl-click override.
		-- Acquiring a target with ctrl held marks it, and shift picks the cross
		-- because no addon can see which mouse button did the targeting.
		--
		-- It only runs while the keys are not held. Both live at once is how
		-- ctrl-tab used to mark whatever it landed on, and how a ctrl-click that
		-- both marked and changed target needed a dedupe to survive.
		if ns.db.marking and ns.db.targetMark and not ns.MarkKeys.Active()
				and IsControlKeyDown() and UnitExists("target") then
			Mark("target", IsShiftKeyDown() and CROSS or SKULL)
		end
	end
end)
