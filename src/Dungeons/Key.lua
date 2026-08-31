local ADDON, ns = ...

local Key = {}
ns.DungeonKey = Key

--------------------------------------------------------------------------
-- The key that opens the dungeon log
--
-- Shift-L out of the box, and any key you like in the settings window.
--
-- **It is a key of its own rather than a key taken off Blizzard.** The quest
-- log takes L and the world map takes M, because the client already has a
-- window for each of those and the honest thing to do is put the client's own
-- in the attic and stand in front of it. There is no adventure guide on either
-- of these clients. Nothing is being replaced, so nothing is being taken, and
-- the key is one this addon asks for.
--
-- Shift-L because L is the log key and this is the other log. A player who
-- knows L knows where to reach, and the modifier is what says which one.
--
-- **An override binding, never a real one.** SetBindingClick writes into the
-- live binding set, and the next SaveBindings, which the client's own Key
-- Bindings panel calls when you press Okay, would make that permanent and lose
-- whatever the player had on the key. An override sits on top of the set
-- instead, so a binding file is untouched even while this holds a key. It is
-- the same argument Charge/Icon.lua and Targeting/Switch.lua both make, and the
-- reason all three carry the displaced binding: the panel can then say what is
-- being shadowed rather than the player finding out.
--
-- **The button is not secure and does not need to be.** Opening a window is
-- ordinary Lua. The two keys above are on secure buttons because starting an
-- attack is protected and only a macro run off a hardware press may do it;
-- nothing here is. So this is a plain button with an OnClick, which also means
-- the key still works in combat, which for a window you open to read is the
-- whole point of it not being secure.
--------------------------------------------------------------------------

local BUTTON_NAME = "WarriorKitDungeonsButton"
Key.BUTTON_NAME = BUTTON_NAME

-- The two the binding system must never lose, refused here for the reason
-- Marking/Keys.lua refuses them: a bare mouse button binding eats plain
-- targeting and the camera drag.
local BARE = { BUTTON1 = true, BUTTON2 = true }

-- No size and no anchor, the shape every other global button in the addon has.
-- It is never meant to be hit by a real cursor, and a frame with no size cannot
-- be. Left shown, because a click delivered by the binding system is only
-- proven to arrive on a shown frame.
local button = CreateFrame("Button", BUTTON_NAME, UIParent)
button:RegisterForClicks("AnyUp")
button:SetScript("OnClick", function()
	ns.DungeonWindow.Toggle()
end)

function Key.Apply()
	if type(SetOverrideBindingClick) ~= "function" then
		return false
	end
	ClearOverrideBindings(button)
	local key = ns.db.dungeonKey or ""
	if key ~= "" and ns.db.dungeons then
		SetOverrideBindingClick(button, true, key, BUTTON_NAME, "LeftButton")
	end
	return true
end

-- Reads the override layer back rather than reporting what this file meant to
-- set. A client that takes the call and does nothing with it leaves no other
-- trace. Nil means the question could not be asked.
local function Holds(key)
	if type(GetBindingAction) ~= "function" then
		return nil
	end
	local ok, action = pcall(GetBindingAction, key, true)
	if not ok or type(action) ~= "string" then
		return nil
	end
	return action == ("CLICK %s:LeftButton"):format(BUTTON_NAME)
end

-- Returns the binding the key was carrying, "" when it carried none, or nil
-- plus a reason when the key cannot be taken. The displaced action is read with
-- our own override dropped, so it reports the real binding rather than the
-- click binding this file left there last time.
function Key.Bind(key)
	if InCombatLockdown() then
		return nil, "keys cannot be rebound in combat."
	end
	key = key or ""
	if BARE[key] then
		return nil, ("%s belongs to targeting and the camera. Hold a modifier."):format(key)
	end

	ns.db.dungeonKey = ""
	Key.Apply()

	local displaced = key ~= "" and GetBindingAction(key) or ""
	ns.db.dungeonKey = key
	ns.db.dungeonKeyDisplaced = displaced
	Key.Apply()

	if key ~= "" and Holds(key) == false then
		return nil, ("this client would not take %s."):format(key)
	end
	return displaced
end

function Key.Describe()
	local key = ns.db.dungeonKey or ""
	if key == "" then
		return "unbound"
	end
	if not ns.db.dungeons then
		return key .. " (the dungeon log is off, so the key is not held)"
	end
	if Holds(key) == false then
		return key .. " (the client did not take it)"
	end
	local displaced = ns.db.dungeonKeyDisplaced or ""
	if displaced ~= "" then
		return ("%s, shadowing %s"):format(key, displaced)
	end
	return key
end
