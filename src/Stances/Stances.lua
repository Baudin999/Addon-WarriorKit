local ADDON, ns = ...

local Stances = {}
ns.Stances = Stances

--------------------------------------------------------------------------
-- Stance dancing
--
-- One key per stance. It swaps you into that stance and puts that stance's
-- pair of weapons in your hands, in one press, off one hardware event.
--
-- All three are secure action buttons carrying a macro, for the reason
-- Targeting/Switch.lua is one and Charge/Icon.lua is one: equipping an item is
-- something ordinary Lua may not do during a fight, and an /equipslot line run
-- off a key press is the path that is allowed to. Nothing in this file calls
-- EquipItemByName, and nothing in it needs to.
--
-- The macro is three lines at most:
--
--     /cast [nostance:2] Defensive Stance
--     /equipslot 16 Bloodspiller
--     /equipslot 17 Aegis of the Blood God
--
-- The stance line carries `nostance` so a press while you are already standing
-- there spends itself on the weapons rather than on a cast. The main hand line
-- comes before the off hand line and the order is load bearing: going from a
-- two hander to a one hander and a shield, the main hand line is what frees
-- the off hand for the line under it. The other way round it is the client
-- that clears the off hand, and the loadout has nothing in that slot to say.
--
-- What a loadout cannot say is "take that off". There is no /equipslot for an
-- empty hand, so a slot left blank means leave whatever is there alone rather
-- than strip it. The panel says so under the slot.
--------------------------------------------------------------------------

Stances.LIST = {
	{ id = 1, key = "battle",    label = "Battle",    button = "WarriorKitStanceBattleButton" },
	{ id = 2, key = "defensive", label = "Defensive", button = "WarriorKitStanceDefensiveButton" },
	{ id = 3, key = "berserker", label = "Berserker", button = "WarriorKitStanceBerserkerButton" },
}

-- The two the binding system must never lose, refused here for the reason
-- Marking/Keys.lua and Targeting/Switch.lua refuse them: a bare mouse button
-- binding eats plain targeting and the camera drag.
local BARE = { BUTTON1 = true, BUTTON2 = true }

local buttons = {}
local pending = false

function Stances.Entry(key)
	for _, entry in ipairs(Stances.LIST) do
		if entry.key == key then
			return entry
		end
	end
	return nil
end

-- The pair of names saved for one stance, created on first read rather than in
-- the defaults table, because ApplyDefaults copies a default one level deep and
-- a table of tables would hand every stance the same one.
function Stances.Gear(key)
	local all = ns.dbc.stanceGear
	local pair = all[key]
	if not pair then
		pair = { main = "", off = "" }
		all[key] = pair
	end
	return pair
end

function Stances.Key(key)
	return ns.dbc.stanceKeys[key] or ""
end

--------------------------------------------------------------------------
-- The macro
--------------------------------------------------------------------------

-- Built from the saved names rather than from anything live, so it is the same
-- string every time until you change a slot. Nothing here runs on a ticker:
-- Apply is called when a setting moves and at login, which is the whole list.
local function MacroText(entry)
	local lines = {}

	local name = ns.Stance.Name(entry.id)
	if name then
		lines[#lines + 1] = ("/cast [nostance:%d] %s"):format(entry.id, name)
	end

	-- A swap costs a swing timer reset, and in a fight that is a real price
	-- rather than a theoretical one. It is on by default because swapping mid
	-- fight is most of the point of stance dancing, and it is a setting because
	-- anyone who wants the stance without the price should be able to say so.
	local guard = ns.dbc.stanceSwapCombat and "" or "[nocombat] "
	local pair = Stances.Gear(entry.key)
	if pair.main ~= "" then
		lines[#lines + 1] = ("/equipslot %s%d %s"):format(guard, ns.Gear.MAINHAND, pair.main)
	end
	-- Dropped when the main hand holds a two hander, because both hands are
	-- already spoken for and the line would either be refused or take the two
	-- hander back off. Only when the client can be asked: a weapon in the bank
	-- has no equip type to read, and guessing at one would silently drop a line
	-- the player set on purpose.
	if pair.off ~= "" and Stances.TwoHanded(entry.key) ~= true then
		lines[#lines + 1] = ("/equipslot %s%d %s"):format(guard, ns.Gear.OFFHAND, pair.off)
	end

	return table.concat(lines, "\n")
end

-- What the panel shows, so the thing you would paste into a bug report is the
-- thing the button is actually carrying.
function Stances.Macro(key)
	local entry = Stances.Entry(key)
	return entry and MacroText(entry) or ""
end

--------------------------------------------------------------------------
-- The buttons
--------------------------------------------------------------------------

-- No size and no anchor, the shape Marking/Keys.lua and Targeting/Switch.lua
-- both use. A frame with no size cannot be hit by a real cursor, and it is
-- left shown because a click delivered by the binding system is only proven to
-- arrive on a shown frame.
for _, entry in ipairs(Stances.LIST) do
	local button = CreateFrame("Button", entry.button, UIParent, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyDown")
	buttons[entry.key] = button
end

-- Everything protected in one function, the shape Charge/Icon.lua's
-- ApplySecure has. Attributes and override bindings are both refused under
-- lockdown, so in combat this sets pending and PLAYER_REGEN_ENABLED runs it
-- for real. Changing a loadout mid fight therefore lands when the fight ends,
-- which is the honest behaviour and is said in the panel.
function Stances.Apply()
	if InCombatLockdown() then
		pending = true
		return false
	end
	pending = false

	for _, entry in ipairs(Stances.LIST) do
		local button = buttons[entry.key]
		local text = MacroText(entry)
		-- A button with no macro is left with no type, so a key still bound to
		-- it does nothing rather than doing something empty.
		button:SetAttribute("type", text ~= "" and "macro" or nil)
		button:SetAttribute("macrotext", text)

		ClearOverrideBindings(button)
		local key = Stances.Key(entry.key)
		if key ~= "" then
			SetOverrideBindingClick(button, true, key, entry.button, "LeftButton")
		end
	end
	return true
end

-- Reads the override layer back rather than reporting what this file meant to
-- set, the same as Switch.Holds. A client that takes the call and does nothing
-- with it leaves no other trace. Nil means the question could not be asked.
local function Holds(entry, key)
	if type(GetBindingAction) ~= "function" then
		return nil
	end
	local ok, action = pcall(GetBindingAction, key, true)
	if not ok or type(action) ~= "string" then
		return nil
	end
	return action == ("CLICK %s:LeftButton"):format(entry.button)
end

--------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------

-- Returns the binding the key was carrying, "" when it carried none, or nil
-- plus a reason when the key cannot be taken. Two stances on one key is the
-- one mistake the panel cannot show you afterwards, the same as two marks on
-- one key, so it is refused here rather than left to the last writer.
function Stances.Bind(stanceKey, key)
	local entry = Stances.Entry(stanceKey)
	if not entry then
		return nil, "no such stance."
	end
	if InCombatLockdown() then
		return nil, "keys cannot be rebound in combat."
	end

	key = key or ""
	if BARE[key] then
		return nil, ("%s belongs to targeting and the camera. Hold a modifier."):format(key)
	end
	for _, other in ipairs(Stances.LIST) do
		if other.key ~= stanceKey and key ~= "" and Stances.Key(other.key) == key then
			return nil, ("%s already switches to %s stance."):format(key, other.label:lower())
		end
	end

	-- The displaced action is read with our own override dropped, so it reports
	-- the real binding rather than the click binding this file left there last
	-- time. It is kept so the panel can go on showing what is being shadowed.
	ns.dbc.stanceKeys[stanceKey] = ""
	Stances.Apply()

	local displaced = key ~= "" and GetBindingAction(key) or ""
	ns.dbc.stanceKeys[stanceKey] = key
	ns.dbc.stanceKeysDisplaced[stanceKey] = displaced
	Stances.Apply()

	if key ~= "" and Holds(entry, key) == false then
		return nil, ("this client would not take %s."):format(key)
	end
	return displaced
end

-- Takes an item link, or nil to clear the slot. Returns the name it saved, or
-- nil and the reason it would not, which is what the drop target reports back
-- to whoever dropped something in the wrong hand.
function Stances.SetItem(stanceKey, slot, link)
	local pair = Stances.Gear(stanceKey)
	local field = (slot == ns.Gear.OFFHAND) and "off" or "main"

	if link == nil then
		pair[field] = ""
		Stances.Apply()
		return ""
	end

	local name, why = ns.Gear.Accepts(slot, link)
	if not name then
		return nil, why
	end
	pair[field] = name
	Stances.Apply()
	return name
end

-- Whether this stance's main hand is a two hander, which is what makes its off
-- hand slot meaningless. Nil when the item is not on this character right now,
-- because a weapon in the bank has no equip type to read and guessing at one
-- would grey out a slot for no reason.
function Stances.TwoHanded(stanceKey)
	local pair = Stances.Gear(stanceKey)
	if pair.main == "" then
		return false
	end
	local item = ns.Gear.Find(ns.Gear.MAINHAND, pair.main)
	if not item then
		return nil
	end
	return item.equip == "INVTYPE_2HWEAPON"
end

function Stances.Describe(stanceKey)
	local entry = Stances.Entry(stanceKey)
	if not entry then
		return "unknown"
	end
	local key = Stances.Key(stanceKey)
	if key == "" then
		return "unbound"
	end
	if Holds(entry, key) == false then
		return key .. " (the client did not take it)"
	end
	return key
end

--------------------------------------------------------------------------
-- Events
--
-- PLAYER_LOGIN rather than ADDON_LOADED, because the binding set the overrides
-- land on top of is not built until then. PLAYER_REGEN_ENABLED picks up
-- anything a fight refused.
--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" and not pending then
		return
	end
	Stances.Apply()
end)
