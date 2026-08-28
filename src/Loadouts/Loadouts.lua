local ADDON, ns = ...

local Loadouts = {}
ns.Loadouts = Loadouts

--------------------------------------------------------------------------
-- Loadouts
--
-- A loadout is a name, a pair of weapons, an optional stance and a key. One
-- press puts you in the stance and puts that pair in your hands.
--
-- Three are made for you, one per stance, because stance dancing is what this
-- started as and a warrior wants those three whatever else they want. Nothing
-- below treats them as special: they are rows in the same list as anything you
-- add, they can be renamed, unbound from their stance and deleted, and a
-- loadout with no stance at all is a weapon set with a key on it.
--
-- All of them are secure action buttons carrying a macro, for the reason
-- Targeting/Switch.lua is one and Charge/Icon.lua is one: putting a weapon in
-- your hand during a fight is something ordinary Lua may not do, and an
-- /equipslot line run off a hardware key press is the path that is allowed to.
-- Nothing in this file calls EquipItemByName, and nothing in it needs to.
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
-- the off hand for the line under it. The other way round it is the client that
-- clears the off hand, and the loadout has nothing in that slot to say.
--
-- What a loadout cannot say is "take that off". There is no /equipslot for an
-- empty hand, so a slot left blank means leave whatever is there alone rather
-- than strip it. The panel says so under the slot.
--
-- The macro is written out of combat and never on the press. Every decision a
-- press makes is a macro conditional, which is what lets a key work in a fight
-- at all: attributes cannot be rewritten under lockdown, so anything this file
-- changes during one is held and written at PLAYER_REGEN_ENABLED.
--------------------------------------------------------------------------

-- One secure button per loadout, all of them made at load. A button cannot be
-- given attributes in combat and a name is what SetOverrideBindingClick binds
-- to, so they are named and they exist before anyone needs one. Ten is the cap
-- because ten is already more keys than anyone dances across, and a cap that is
-- reached says so rather than silently dropping the eleventh.
local MAX = 10

-- The two the binding system must never lose, refused here for the reason
-- Marking/Keys.lua and Targeting/Switch.lua refuse them: a bare mouse button
-- binding eats plain targeting and the camera drag.
local BARE = { BUTTON1 = true, BUTTON2 = true }

Loadouts.MAX = MAX

local buttons = {}
local pending = false

local function ButtonName(index)
	return ("WarriorKitLoadout%dButton"):format(index)
end

for index = 1, MAX do
	-- No size and no anchor, the shape Marking/Keys.lua and Targeting/Switch.lua
	-- both use. A frame with no size cannot be hit by a real cursor, and it is
	-- left shown because a click delivered by the binding system is only proven
	-- to arrive on a shown frame.
	local button = CreateFrame("Button", ButtonName(index), UIParent, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyDown")
	buttons[index] = button
end

--------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------

-- Seeded on first read rather than in the defaults table, because ApplyDefaults
-- copies a default one level deep and a list of tables would hand every
-- character the same inner tables. A character that deletes them all gets an
-- empty list and keeps it: the seed runs once, recorded by loadoutsSeeded, so
-- deleting one does not bring it back on the next login.
--
-- One per form your class has, named by the client's own word for it, and none
-- at all for a class with no forms. Stance dancing is what this started as and
-- a warrior wants those three whatever else they want; a mage wants a weapon set
-- with a key on it and has nothing to dance between, so handing them three empty
-- rows bound to stances they cannot enter is three rows to delete.
--
-- The seed waits for the client to name the forms. A row seeded with an empty
-- name is a row nobody can tell from another, and the name is written once.
function Loadouts.All()
	local list = ns.dbc.loadouts
	if ns.dbc.loadoutsSeeded then
		return list
	end

	local forms = ns.Stance.Count()
	if forms == 0 then
		ns.dbc.loadoutsSeeded = true
		return list
	end

	for index = 1, forms do
		local name = ns.Stance.Name(index)
		if not name then
			return list
		end
	end

	ns.dbc.loadoutsSeeded = true
	for index = 1, forms do
		list[#list + 1] = {
			name = ns.Stance.Name(index), stance = index,
			main = "", off = "", key = "", displaced = "",
		}
	end
	return list
end

function Loadouts.Get(index)
	return Loadouts.All()[index]
end

function Loadouts.Count()
	return #Loadouts.All()
end

-- Which one the panel is showing. Clamped on read rather than on delete, so
-- nothing has to remember to fix it and a saved index from a longer list lands
-- somewhere real.
function Loadouts.Shown()
	local count = Loadouts.Count()
	if count == 0 then
		return 0
	end
	local index = ns.dbc.loadoutShown or 1
	if index < 1 or index > count then
		index = 1
	end
	return index
end

function Loadouts.Show(index)
	ns.dbc.loadoutShown = index
end

function Loadouts.Add(name)
	local list = Loadouts.All()
	if #list >= MAX then
		return nil, ("%d loadouts is the cap."):format(MAX)
	end
	list[#list + 1] = {
		name = name and name ~= "" and name or ("Loadout %d"):format(#list + 1),
		main = "", off = "", key = "", displaced = "",
	}
	Loadouts.Show(#list)
	Loadouts.Apply()
	return #list
end

-- The key is dropped before the row is, because a binding held by a button that
-- is about to carry somebody else's macro is a key that quietly does the wrong
-- thing. Apply rebuilds every binding from the list afterwards, so the shift in
-- indices below it needs nothing else.
function Loadouts.Remove(index)
	local list = Loadouts.All()
	if not list[index] then
		return false
	end
	table.remove(list, index)
	Loadouts.Apply()
	return true
end

function Loadouts.Rename(index, name)
	local loadout = Loadouts.Get(index)
	if not loadout then
		return false
	end
	loadout.name = (name and name ~= "") and name or loadout.name
	return true
end

-- Nil clears the stance, which leaves a loadout that is weapons and a key and
-- nothing else. That is the shape a custom one starts in.
function Loadouts.SetStance(index, stance)
	local loadout = Loadouts.Get(index)
	if not loadout then
		return false
	end
	loadout.stance = stance
	Loadouts.Apply()
	return true
end

--------------------------------------------------------------------------
-- The macro
--------------------------------------------------------------------------

local function MacroText(loadout)
	local lines = {}

	local name = loadout.stance and ns.Stance.Name(loadout.stance)
	if name then
		lines[#lines + 1] = ("/cast [nostance:%d] %s"):format(loadout.stance, name)
	end

	-- A swap mid fight costs a swing timer reset, which is a real price rather
	-- than a theoretical one. It is on by default because swapping mid fight is
	-- most of the point, and it is a setting because anyone who wants the stance
	-- without the price should be able to say so.
	local guard = ns.dbc.loadoutSwapCombat and "" or "[nocombat] "
	if loadout.main ~= "" then
		lines[#lines + 1] = ("/equipslot %s%d %s"):format(guard, ns.Gear.MAINHAND, loadout.main)
	end
	-- Dropped when the main hand holds a two hander, because both hands are
	-- already spoken for and the line would either be refused or take the two
	-- hander back off. Only when the client can be asked: a weapon in the bank
	-- has no equip type to read, and guessing at one would silently drop a line
	-- the player set on purpose.
	if loadout.off ~= "" and Loadouts.TwoHandedFor(loadout) ~= true then
		lines[#lines + 1] = ("/equipslot %s%d %s"):format(guard, ns.Gear.OFFHAND, loadout.off)
	end

	return table.concat(lines, "\n")
end

-- What the panel shows, so the thing you would paste into a bug report is the
-- thing the button is actually carrying.
function Loadouts.Macro(index)
	local loadout = Loadouts.Get(index)
	return loadout and MacroText(loadout) or ""
end

-- Everything protected in one function, the shape Charge/Icon.lua's ApplySecure
-- has. Attributes and override bindings are both refused under lockdown, so in
-- combat this sets pending and PLAYER_REGEN_ENABLED runs it for real. Changing
-- a loadout mid fight therefore lands when the fight ends, which is the honest
-- behaviour and is said in the panel.
--
-- Every button is rewritten from the list every time rather than the one that
-- moved, because deleting a row shifts every row under it onto a different
-- button and a partial pass would leave a key on the wrong macro.
function Loadouts.Apply()
	if InCombatLockdown() then
		pending = true
		return false
	end
	pending = false

	local list = Loadouts.All()
	for index = 1, MAX do
		local button = buttons[index]
		local loadout = list[index]
		local text = loadout and MacroText(loadout) or ""
		-- A button with no macro is left with no type, so a key still bound to it
		-- does nothing rather than doing something empty.
		button:SetAttribute("type", text ~= "" and "macro" or nil)
		button:SetAttribute("macrotext", text)

		ClearOverrideBindings(button)
		local key = loadout and loadout.key or ""
		if key ~= "" then
			SetOverrideBindingClick(button, true, key, ButtonName(index), "LeftButton")
		end
	end
	return true
end

-- Reads the override layer back rather than reporting what this file meant to
-- set. A client that takes the call and does nothing with it leaves no other
-- trace. Nil means the question could not be asked.
local function Holds(index, key)
	if type(GetBindingAction) ~= "function" then
		return nil
	end
	local ok, action = pcall(GetBindingAction, key, true)
	if not ok or type(action) ~= "string" then
		return nil
	end
	return action == ("CLICK %s:LeftButton"):format(ButtonName(index))
end

--------------------------------------------------------------------------
-- Weapons and keys
--------------------------------------------------------------------------

-- Takes an item link, or nil to clear the slot. Returns the name it saved, or
-- nil and the reason it would not, which is what the drop target reports back
-- to whoever dropped something in the wrong hand.
function Loadouts.SetItem(index, slot, link)
	local loadout = Loadouts.Get(index)
	if not loadout then
		return nil, "no such loadout."
	end
	local field = (slot == ns.Gear.OFFHAND) and "off" or "main"

	if link == nil then
		loadout[field] = ""
		Loadouts.Apply()
		return ""
	end

	local name, why = ns.Gear.Accepts(slot, link)
	if not name then
		return nil, why
	end
	loadout[field] = name
	Loadouts.Apply()
	return name
end

-- Whether this loadout's main hand fills both hands, which is what makes its
-- off hand slot meaningless. Nil when the item is not on this character right
-- now, because a weapon in the bank has no equip type to read and guessing at
-- one would grey out a slot for no reason.
function Loadouts.TwoHandedFor(loadout)
	if not loadout or loadout.main == "" then
		return false
	end
	local item = ns.Gear.Find(ns.Gear.MAINHAND, loadout.main)
	if not item then
		return nil
	end
	return item.equip == "INVTYPE_2HWEAPON"
end

function Loadouts.TwoHanded(index)
	return Loadouts.TwoHandedFor(Loadouts.Get(index))
end

-- Returns the binding the key was carrying, "" when it carried none, or nil
-- plus a reason when the key cannot be taken. Two loadouts on one key is the
-- one mistake the panel cannot show you afterwards, the same as two marks on
-- one key, so it is refused here rather than left to the last writer.
function Loadouts.Bind(index, key)
	local loadout = Loadouts.Get(index)
	if not loadout then
		return nil, "no such loadout."
	end
	if InCombatLockdown() then
		return nil, "keys cannot be rebound in combat."
	end

	key = key or ""
	if BARE[key] then
		return nil, ("%s belongs to targeting and the camera. Hold a modifier."):format(key)
	end
	if key ~= "" then
		for other, each in ipairs(Loadouts.All()) do
			if other ~= index and each.key == key then
				return nil, ("%s already switches to %s."):format(key, each.name)
			end
		end
	end

	-- The displaced action is read with our own override dropped, so it reports
	-- the real binding rather than the click binding this file left there last
	-- time. It is kept so the panel can go on showing what is being shadowed.
	loadout.key = ""
	Loadouts.Apply()

	local displaced = key ~= "" and GetBindingAction(key) or ""
	loadout.key = key
	loadout.displaced = displaced
	Loadouts.Apply()

	if key ~= "" and Holds(index, key) == false then
		return nil, ("this client would not take %s."):format(key)
	end
	return displaced
end

function Loadouts.Describe(index)
	local loadout = Loadouts.Get(index)
	if not loadout then
		return "unknown"
	end
	if loadout.key == "" then
		return "unbound"
	end
	if Holds(index, loadout.key) == false then
		return loadout.key .. " (the client did not take it)"
	end
	return loadout.key
end

function Loadouts.ButtonName(index)
	return ButtonName(index)
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
	Loadouts.Apply()
end)
