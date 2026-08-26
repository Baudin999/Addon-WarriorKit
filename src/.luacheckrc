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
	"WarriorKitClutter",
	"WarriorKitChargeButton",
	"WarriorKitSwitchButton",
	-- one per loadout, each a secure button carrying that loadout's macro. All
	-- ten are made at load: a button cannot be given attributes in combat, and a
	-- name is what SetOverrideBindingClick binds to, so they are named and they
	-- exist before anyone needs one.
	"WarriorKitLoadout1Button", "WarriorKitLoadout2Button",
	"WarriorKitLoadout3Button", "WarriorKitLoadout4Button",
	"WarriorKitLoadout5Button", "WarriorKitLoadout6Button",
	"WarriorKitLoadout7Button", "WarriorKitLoadout8Button",
	"WarriorKitLoadout9Button", "WarriorKitLoadout10Button",
	"WarriorKitChargeCooldown",
	"WarriorKitChargeMarker",
	"WarriorKitChargeMarkerCooldown",
	"WarriorKitEnemyBarsAnchor",
	-- the meter frame. Named so the two panes can be found from a macro or from
	-- scripts/harness.lua without Meter/Window.lua handing out a reference to its
	-- own row pool.
	"WarriorKitMeter",
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
	-- what one action slot is doing, read by Buttons/Slot.lua on the bar's
	-- ticker. Probed by name in Slot.CanRead for the same reason the writers
	-- above are: nothing installed here proves any of them is on 2.5.6, and a
	-- bar that raises once per button per tick is worse than a grey bar.
	"HasAction", "GetActionTexture", "GetActionCooldown", "GetActionCount",
	"IsUsableAction", "IsActionInRange",
	-- the spellbook, read by Buttons/Ranks.lua to find the best rank you know
	"GetNumSpellTabs", "GetSpellTabInfo",
	"GetSpellBookItemInfo", "GetSpellBookItemName",
	"GetSpellInfo", "GetSpellTexture", "GetSpellCooldown", "IsUsableSpell",
	"IsSpellInRange", "IsSpellKnown",
	"GetTime", "GetRaidTargetIndex", "SetRaidTarget",
	-- items, for the weapon the charge button equips and the trash the Comfort
	-- part sells. The container API is C_Container on one client and loose
	-- globals on the other, so both are probed in Core rather than named
	-- anywhere else. C_Item is the newer home for the item lookups and is
	-- reached through _G in Core beside C_Container, so it is not an entry
	-- here.
	"GetInventoryItemLink", "GetContainerNumSlots", "GetContainerItemLink",
	"GetContainerItemInfo", "UseContainerItem",
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
	-- Looting, for the Comfort part. Leatrix Plus is loaded on both of these
	-- clients and calls all five unguarded inside its own faster-looting
	-- feature, which is the same feature and so the same proof;
	-- GetLootThreshold is also called unguarded by TitanLootType on both.
	-- GetLootMethod is the one that is not here: C_PartyInfo carries it on one
	-- client and the loose global on the other, so Comfort/Loot.lua probes for
	-- both and treats neither answering as "do not know" rather than "no".
	"IsModifiedClick", "GetNumLootItems", "GetLootSlotInfo", "LootSlot",
	"GetLootThreshold",
	-- The merchant, for the same part. MerchantFrame is read to prove the
	-- window is still up before anything is sold, because the container call
	-- behind it uses the item instead when it is not. Leatrix calls the frame
	-- and GetCoinText unguarded, Auctionator calls GetCoinText, and GetMoney is
	-- called unguarded by TitanGold, TitanRepair and Titan itself. The two
	-- ERR_ constants are reached through _G rather than named, because a client
	-- missing one would compare a message against nil and stop a sale that was
	-- fine.
	"MerchantFrame", "GetMoney", "GetCoinText",
	-- Repairing, for the same window. TitanRepair and Leatrix Plus are both
	-- installed on both of these clients and both call all four unguarded,
	-- inside their own auto-repair feature, which is the same feature and so
	-- the same proof. The guild bank trio is deliberately absent:
	-- CanGuildBankRepair, GetGuildBankMoney and GetGuildBankWithdrawMoney are
	-- only proven by TitanRepair calling them, and Classic Era has no guild
	-- bank at all, so Comfort/Repair.lua reaches all three through _G and
	-- pcalls them. A client without them loses guild funding and keeps the
	-- repair, which is the right way round to be wrong.
	"CanMerchantRepair", "GetRepairAllCost", "RepairAllItems",
	"GetInventoryItemDurability",
	-- The quest log, for the clutter scan. Questie calls both of these
	-- unguarded on both clients and reads the quest id out of the eighth value
	-- exactly as Clutter.lua does. IsQuestFlaggedCompleted is not here: it lives
	-- on the loose global on one client and under C_QuestLog on the other, so it
	-- is resolved through _G the way Questie resolves it.
	"GetNumQuestLogEntries", "GetQuestLogTitle",
	-- QuestieLoader, PickupContainerItem's loose fallback and DeleteCursorItem
	-- are deliberately absent. Questie is another addon and may not be
	-- installed; the container call goes through C_Container in Core; and
	-- nothing here calls DeleteCursorItem, Questie only hooks it, which proves
	-- the global exists and is not the same as proving the call is ours to make.
	-- All three are probed and pcalled at their use sites.
	-- profiling, read by the Perf part. Every one of these is called unguarded
	-- by an addon in this install: debugprofilestop by Details, Questie and
	-- Auctionator, the memory pair by Details, TitanPerformance and Leatrix,
	-- the CPU pair and GetFramerate by Details and TitanPerformance. The CPU
	-- pair is read only where someone else has already turned scriptProfile on.
	"debugprofilestop", "GetFramerate",
	"UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage",
	"UpdateAddOnCPUUsage", "GetAddOnCPUUsage",
	"RAID_CLASS_COLORS", "wipe", "InCombatLockdown",
	"date", "GetBuildInfo",
	-- Edit Mode. Titan calls EditModeManagerFrame:GetActiveLayoutInfo()
	-- unguarded, which is what proves the frame is here. The methods the
	-- EditMode part uses past that one are probed by name before every call.
	"EditModeManagerFrame", "Enum",
	-- Post-hooked onto a unit frame's own AnchorSelectionFrame, so Edit Mode's
	-- selection lands on the block rather than on the rectangle the frame used
	-- to be. Type-checked before it is called, like every other method the
	-- skin borrows from a client it cannot be sure of.
	"hooksecurefunc",
}
