local ADDON, ns = ...

local Switch = {}
ns.Switch = Switch

--------------------------------------------------------------------------
-- Switching target and swinging at it
--
-- TAB picks the next enemy and stops there. In a fight that costs a second
-- press, because the swing does not follow the target, and the mob you just
-- switched to stands there untouched until you notice. This is one key that
-- does both, in that order and inside one macro, so the attack lands on the
-- mob the cycle just picked rather than on whatever was targeted a moment
-- before.
--
-- It is a secure action button carrying a macro rather than Lua calling the
-- two functions, for the reason Charge/Icon.lua is one: starting an attack is
-- protected, and a macro run off a hardware key press is the path that is
-- allowed to do it. The macro is a constant, which the charge macro is not, so
-- nothing here is ever rewritten and combat can refuse only a rebind.
--
-- Bind it in /wk or with `/wk switch <key>`, or put
-- `/click WarriorKitSwitchButton` in a normal macro and drag that to a bar.
--------------------------------------------------------------------------

local BUTTON_NAME = "WarriorKitSwitchButton"
Switch.BUTTON_NAME = BUTTON_NAME

-- The two the binding system must never lose, refused here for the reason
-- Marking/Keys.lua refuses them: a bare mouse button binding eats plain
-- targeting and the camera drag. The panel's key field refuses them too, so
-- this is the slash word's guard.
local BARE = { BUTTON1 = true, BUTTON2 = true }

-- /targetenemy is TAB's own binding, TARGETNEARESTENEMY, said as a macro
-- command, so this cycles exactly the way TAB does and honours the same
-- settings. /startattack carries harm and nodead because the cycle can land on
-- nothing at all when there is nothing in range to land on, and a bare
-- /startattack then answers back in chat for a key press that did nothing.
--
-- The conditional belongs on the attack line and nowhere else. A bare
-- [harm,nodead] tests the target you already have, not the one the cycle is
-- about to pick, so on /targetenemy it would decide whether the cycle runs at
-- all: your mob dies, the corpse fails nodead, and the key does nothing on the
-- one press it exists for. Nothing filters what TargetNearestEnemy picks, and
-- TAB skips corpses on its own anyway.
local MACRO = table.concat({
	"/targetenemy",
	"/startattack [harm,nodead]",
}, "\n")

-- No size and no anchor, the shape Marking/Keys.lua uses and Clique uses for
-- its own global button. It is never meant to be hit by a real cursor, and a
-- frame with no size cannot be. It is left shown, because a click delivered by
-- the binding system is only proven to arrive on a shown frame.
local button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
button:RegisterForClicks("AnyDown")
button:SetAttribute("type", "macro")
button:SetAttribute("macrotext", MACRO)

-- An override binding, never a real one, the same as the charge key.
-- SetBindingClick would write the key into the live binding set and the next
-- SaveBindings, which the Key Bindings panel calls when you click Okay, would
-- make that permanent and lose whatever you had on the key. An override sits
-- on top of the set instead, so TAB stays TAB in your bindings file even while
-- this holds it.
--
-- That is also why this key is set here and not in Bindings.xml: a binding
-- listed there runs ordinary Lua, and ordinary Lua may not start an attack.
function Switch.Apply()
	if InCombatLockdown() then
		return false
	end
	ClearOverrideBindings(button)
	local key = ns.db.switchKey or ""
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
-- plus a reason when the key cannot be taken. The displaced action is read
-- with our own override dropped, so it reports the real binding rather than
-- the click binding this file left there last time, and it is kept so the
-- panel can go on showing what is being shadowed.
function Switch.Bind(key)
	if InCombatLockdown() then
		return nil, "keys cannot be rebound in combat."
	end
	key = key or ""
	if BARE[key] then
		return nil, ("%s belongs to targeting and the camera. Hold a modifier."):format(key)
	end

	ns.db.switchKey = ""
	Switch.Apply()

	local displaced = key ~= "" and GetBindingAction(key) or ""
	ns.db.switchKey = key
	ns.db.switchKeyDisplaced = displaced
	Switch.Apply()

	if key ~= "" and Holds(key) == false then
		return nil, ("this client would not take %s."):format(key)
	end
	return displaced
end

function Switch.Describe()
	local key = ns.db.switchKey or ""
	if key == "" then
		return "unbound"
	end
	if Holds(key) == false then
		return key .. " (the client did not take it)"
	end
	return key
end

-- PLAYER_LOGIN rather than ADDON_LOADED, because the binding set the override
-- lands on top of is not built until then. Nothing else moves the key: Bind is
-- the only writer and it refuses in combat, so there is no deferred work to
-- pick up when a fight ends.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	Switch.Apply()
end)
