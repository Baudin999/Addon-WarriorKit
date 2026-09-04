local ADDON, ns = ...

local Key = {}
ns.PerfKey = Key

--------------------------------------------------------------------------
-- Ctrl-R
--
-- The key the client already puts a frame rate on, taken for a window that
-- says rather more.
--
-- **This is a key taken off Blizzard, and that is the argument for it.** The
-- dungeon log asks for a key of its own because there is no adventure guide on
-- these clients to replace. Here there is something to replace: TOGGLEFPS draws
-- one averaged number in a corner, an average is the one figure that cannot
-- show a stutter, and the muscle memory for "how is this machine doing" is
-- already on Ctrl-R. Putting the answer somewhere else would leave the worse
-- answer on the key everyone reaches for.
--
-- **An override binding, never a real one.** SetBindingClick writes into the
-- live binding set and the next SaveBindings, which the client's own Key
-- Bindings panel calls when you press Okay, would make that permanent. An
-- override sits on top of the set: TOGGLEFPS is shadowed while this holds the
-- key and comes straight back the moment the switch goes off or the key is
-- rebound. Nothing in a binding file is touched. It is the same mechanism
-- Dungeons/Key.lua, Charge/Icon.lua and Targeting/Switch.lua all use, and the
-- displaced binding is kept for the same reason: the panel can say what is
-- being shadowed rather than the player finding out.
--
-- **The button is not secure and does not need to be.** Opening a window is
-- ordinary Lua, so the key works in combat, which for a window you open to find
-- out why a pull stuttered is the whole point of it.
--------------------------------------------------------------------------

local BUTTON_NAME = "WarriorKitPerfButton"
Key.BUTTON_NAME = BUTTON_NAME

-- The two the binding system must never lose, refused here for the reason
-- Marking/Keys.lua refuses them: a bare mouse button binding eats plain
-- targeting and the camera drag.
local BARE = { BUTTON1 = true, BUTTON2 = true }

-- No size and no anchor, the shape every other global button in the addon has.
-- Left shown, because a click delivered by the binding system is only proven to
-- arrive on a shown frame.
local button = CreateFrame("Button", BUTTON_NAME, UIParent)
button:RegisterForClicks("AnyUp")
button:SetScript("OnClick", function()
	ns.PerfHud.Toggle()
end)

function Key.Apply()
	if type(SetOverrideBindingClick) ~= "function" then
		return false
	end
	ClearOverrideBindings(button)
	local key = ns.db.perfKey or ""
	if key ~= "" then
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

	ns.db.perfKey = ""
	Key.Apply()

	local displaced = key ~= "" and GetBindingAction(key) or ""
	ns.db.perfKey = key
	ns.db.perfKeyDisplaced = displaced
	Key.Apply()

	if key ~= "" and Holds(key) == false then
		return nil, ("this client would not take %s."):format(key)
	end
	return displaced
end

function Key.Describe()
	local key = ns.db.perfKey or ""
	if key == "" then
		return "unbound"
	end
	if Holds(key) == false then
		return key .. " (the client did not take it)"
	end
	local displaced = ns.db.perfKeyDisplaced or ""
	if displaced ~= "" then
		return ("%s, shadowing %s"):format(key, displaced)
	end
	return key
end

-- The client rebuilds its binding set and drops every override with it, so the
-- key is taken again each time it does. See ns.Rebind in Core/Core.lua.
ns.Rebind(Key.Apply)

-- Taken at login as well as on every rebuild of the binding set, because the
-- rebuild that matters happens once during login and a key nobody took cannot
-- be put back by it.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	Key.Apply()
end)
