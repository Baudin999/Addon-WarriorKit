-- WoW addon environment. Run ./check.sh, which runs this plus a syntax pass.
std = "lua51"
max_line_length = false
self = false

-- Every file opens `local ADDON, ns = ...` because that is the shape the game
-- hands the vararg in, and most files only need ns. Naming the first slot is
-- the house convention from the README, so the unused-local warning on it is
-- allowed here rather than worked around per file.
ignore = { "211/ADDON" }

globals = {
	-- written by this addon. Two saved variable tables: the account's and this
	-- character's, both declared in every TOC.
	"WarriorKitDB", "WarriorKitCharDB",
	-- frames created with a name write a global of that name
	"WarriorKitChargeBinder",
	"WarriorKitMarkButton",
	"WarriorKitOptions",
	"WarriorKitChargeButton",
	"WarriorKitSwitchButton",
	-- one per stance, each a secure button carrying that stance's macro
	"WarriorKitStanceBattleButton",
	"WarriorKitStanceDefensiveButton",
	"WarriorKitStanceBerserkerButton",
	"WarriorKitChargeCooldown",
	"WarriorKitChargeMarker",
	"WarriorKitChargeMarkerCooldown",
	"WarriorKitEnemyBarsAnchor",
	-- the block the skin draws over each of the three Blizzard unit frames.
	-- Named so a block that lands in the wrong place can be measured from a
	-- macro or from scripts/harness.lua without Skin.lua handing out a
	-- reference to its own entry tables. Built by concatenation in SPECS, so
	-- luacheck never sees the write; listed here because the game makes the
	-- global and the README says every one of those is written down.
	"WarriorKitSkinPlayer",
	"WarriorKitSkinTarget",
	"WarriorKitSkinToT",
	"WarriorKit_MarkSkull",
	"WarriorKit_MarkCross",
	"WarriorKit_MarkMoon",
	"BINDING_HEADER_WARRIORKIT",
	"BINDING_NAME_WARRIORKIT_MARK_SKULL",
	"BINDING_NAME_WARRIORKIT_MARK_CROSS",
	"BINDING_NAME_WARRIORKIT_MARK_MOON",
	"SLASH_WARRIORKIT1",
	"SLASH_WARRIORKIT2",
	"SlashCmdList",
}

read_globals = {
	"CreateFrame", "UIParent", "WorldFrame", "GameFontNormal", "DEFAULT_CHAT_FRAME",
	"GameTooltip", "GameFontHighlightSmall", "GetBindingAction",
	"RegisterStateDriver", "SetOverrideBindingClick", "ClearOverrideBindings",
	"UISpecialFrames", "tinsert", "pcall",
	"IsAltKeyDown", "GetShapeshiftForm",
	"UnitPlayerOrPetInParty", "UnitPlayerOrPetInRaid", "UnitIsPlayer",
	"C_NamePlate", "C_Spell",
	-- the pixel grid in UI/Pixel.lua. GetPhysicalScreenSize is the only honest
	-- source for the monitor's real height; it is probed by name and falls back
	-- to the resolution CVar, because nothing installed here proves it is on
	-- 2.5.6. CreateFont backs the shared font objects in UI/Text.lua.
	"GetPhysicalScreenSize", "CreateFont",
	-- action bar and macro writing, used by the Buttons part. None of these is
	-- confirmed to exist on 2.5.6 by an installed addon calling it, so Layout
	-- probes for them before it writes anything.
	"PickupSpell", "PickupMacro", "PickupItem", "PlaceAction", "PickupAction",
	"ClearCursor", "GetCursorInfo", "GetActionInfo",
	"CreateMacro", "DeleteMacro", "EditMacro", "GetMacroInfo",
	"GetMacroIndexByName", "GetNumMacros", "GetBonusBarOffset",
	"HasAction",
	-- the spellbook, read by Buttons/Ranks.lua to find the best rank you know
	"GetNumSpellTabs", "GetSpellTabInfo",
	"GetSpellBookItemInfo", "GetSpellBookItemName",
	"GetSpellInfo", "GetSpellTexture", "GetSpellCooldown", "IsUsableSpell",
	"IsSpellInRange", "IsSpellKnown",
	"GetTime", "GetRaidTargetIndex", "SetRaidTarget",
	-- items, for the weapon the charge button equips. The container API is
	-- C_Container on one client and loose globals on the other, so both are
	-- probed in Core rather than named anywhere else.
	"GetInventoryItemLink", "GetContainerNumSlots", "GetContainerItemLink",
	"GetItemInfo", "GetItemInfoInstant", "C_Container",
	-- the empty-slot art each hand draws when nothing is set, and whether the
	-- cursor is carrying something as it arrives over a slot. Baganator calls
	-- GetInventorySlotInfo unguarded on the TBC client and TitanAmmo calls it on
	-- both; CursorHasItem is read through an existence test in UI/Widgets.lua
	-- rather than trusted, because nothing installed here calls it.
	"GetInventorySlotInfo", "CursorHasItem",
	"UnitExists", "UnitGUID", "UnitClass", "UnitAffectingCombat", "UnitCanAttack",
	"UnitIsDead", "UnitIsGroupLeader", "UnitIsGroupAssistant", "IsInRaid",
	"IsControlKeyDown", "IsShiftKeyDown",
	"UnitHealth", "UnitHealthMax", "UnitName", "UnitIsUnit", "UnitCanAttack",
	-- power, for the second gauge on the skinned unit frames. All three are
	-- called unguarded by TitanRegen, which is loaded on this client, so they
	-- are entries here rather than shims in Core.
	"UnitPowerType", "UnitPower", "UnitPowerMax",
	-- levels, for the XP colour on the enemy bars. UnitLevel is called by
	-- Questie and OPie unguarded; GetQuestGreenRange and UnitClassification are
	-- reached through _G in Core, so they are shims rather than entries here.
	"UnitLevel",
	-- hostile or neutral, for the reaction stripe. Details calls it unguarded
	-- and tests it the same way, reaction <= 4 is something you can attack.
	"UnitReaction",
	"UnitDetailedThreatSituation", "UnitAura", "C_UnitAuras",
	"GetNumGroupMembers", "SetRaidTargetIconTexture",
	-- SoftTargetEnemy is read and written by Charge/SoftTarget.lua, which owns
	-- the CVar out of combat and hands it back in. Both calls are pcalled: no
	-- addon here proves SetCVar takes that name on 2.5.6.
	"GetCVarBool", "GetCVar", "SetCVar",
	"RAID_CLASS_COLORS", "wipe", "InCombatLockdown",
	"date", "GetBuildInfo",
	-- Edit Mode. Titan calls EditModeManagerFrame:GetActiveLayoutInfo()
	-- unguarded, which is what proves the frame is here. The methods the
	-- EditMode part uses past that one are probed by name before every call.
	"EditModeManagerFrame", "Enum",
}
