local ADDON, ns = ...

local Cast = {}
ns.HoverCast = Cast

--------------------------------------------------------------------------
-- The button every hover key presses
--
-- One secure button carrying one macro per binding, and one override binding
-- per key pointing at it.
--
-- One button rather than twelve. A secure button looks its action up under
-- `<modifiers>type<click>`, so the click name is the whole of what tells the
-- button which binding fired. SetOverrideBindingClick takes that name as its
-- last argument, which is what Marking/Keys.lua already uses it for: it hands
-- the mark's id over and reads it back out of the OnClick. The same mechanism,
-- one layer more secure.
--
-- The `*` in front is the part that had to be got right and was not. The
-- modifier prefix is read off the keyboard at the moment of the press, so a
-- binding on ALT-BUTTON3 arrives looking for `alt-type1`, and every key worth
-- putting a mouseover spell on carries a modifier. `*type1` is the wildcard the
-- client falls back to when the modified name holds nothing, which is why
-- UnitFrames/Group.lua writes its click actions the same way. Without it the
-- attributes were written under a name nothing ever asks for and every key was
-- a key that bound, read back correctly, and cast nothing.
--
-- A macro rather than a spell attribute, and the reasoning is in Hover.lua: the
-- filter is `[@mouseover,harm]` and there is no attribute that says that. The
-- second reason is combat. Attributes are refused once lockdown is up, so a
-- binding whose behaviour lived in attributes would be a binding that could not
-- change its mind mid-fight about whether the thing under the cursor is an
-- enemy. A conditional decides that at the moment of the press, every press.
--
-- Nothing here runs on a ticker and nothing here is rewritten in a fight. Apply
-- is called at login, when a binding changes, and when combat drops on a change
-- combat refused.
--------------------------------------------------------------------------

local BUTTON_NAME = "WarriorKitHoverButton"
Cast.BUTTON_NAME = BUTTON_NAME

-- No size and no anchor, the shape Marking/Keys.lua uses and Clique uses for its
-- own global button. It is never meant to be hit by a real cursor and a frame
-- with no size cannot be. It is left shown, because a click delivered by the
-- binding system is only proven to arrive on a shown frame.
--
-- The bare `type` is never set. A stray click that arrives with no name on it
-- finds nothing and does nothing, which is the right answer for a button whose
-- only real callers name themselves.
local button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")

-- `useOnKeyDown` is the second thing that shipped wrong, and it is invisible from
-- every side an addon can look at. The key bound, the readback agreed, the click
-- dispatched, and the spell did not go off.
--
-- RegisterForClicks decides whether the click is dispatched at all. The attribute
-- decides whether the secure handler acts on the press or throws it away and
-- waits for the release. Registered on down with the attribute unset, the click
-- arrives, every insecure thing about it looks correct, and the protected call
-- inside is discarded. That is the whole bug, and no PreClick, no readback and no
-- attribute dump can see it, because the half that fails is the half addons
-- cannot enter.
--
-- Clique is the proof rather than the documentation, and it is installed on this
-- machine. Its `CliqueSABButton` is this button: one global SecureActionButton,
-- bound by key through a click, casting on the mouseover. Its default direction
-- is `down`, and on that setting it sets both of these, in `UpdateGlobalButtonClicks`:
--
--     globutton:SetAttribute("useOnKeyDown", true)
--     globutton:RegisterForClicks("AnyDown")
--
-- and its click proxies, which are pinned to the release, set `useOnKeyDown` to
-- false beside `RegisterForClicks("AnyUp")` with the note that a down-mode proxy
-- would never fire. The two halves have to agree, and here only one of them was
-- being set.
--
-- Down rather than up because a key that casts when you press it is what a key
-- that casts feels like, and because that is the direction Clique ships.
button:SetAttribute("useOnKeyDown", true)
button:RegisterForClicks("AnyDown")

--------------------------------------------------------------------------
-- The debug log
--
-- Off by default and silent when off. It is here because this feature fails in
-- three places that all look the same from a chair: the key was never put on
-- the binding layer, the key was put there and the client is not delivering it,
-- or the press arrives and the conditional discards it. One of those is a
-- client that will not take the key, one is a client that takes it and lies,
-- and one is a filter set to `an enemy` on a healing spell. Nothing about the
-- three is distinguishable from the outside, and the third is by far the most
-- common.
--
-- So the log says one line where the binding is written, one line where the
-- press arrives, and one line for the verdict. A press with no `arrived` line
-- is the second case; a press with one and a verdict of nothing is the third.
--------------------------------------------------------------------------

local function Log(fmt, ...)
	if not (ns.db and ns.db.hoverDebug) then
		return
	end
	ns.Print("|cff808080hover|r " .. (select("#", ...) > 0 and fmt:format(...) or fmt))
end

-- PreClick rather than OnClick, and this is the whole reason the log can exist
-- at all: PreClick runs before the secure handler and outside it, so it may
-- print. A print from inside the protected call would be a taint on the frame
-- that casts, which is the debugging that breaks the thing being debugged.
--
-- It runs whether or not the attributes under that suffix hold anything, which
-- is what makes a click arriving on a suffix with no macro visible rather than
-- silent.
button:SetScript("PreClick", function(_, click)
	if not (ns.db and ns.db.hoverDebug) then
		return
	end
	local index = tonumber(click)
	local bind = index and ns.Hover.List()[index]
	Log("arrived on %s", tostring(click))
	if not bind then
		Log("  no binding at %s, so the button carries nothing for it", tostring(click))
		return
	end
	Log("  %s, %s", button:GetAttribute("*type" .. index) or "|cffff5555no type|r",
		button:GetAttribute("*macrotext" .. index) or "|cffff5555no macro|r")
	Log("  %s", ns.Hover.Sight())
	Log("  %s", ns.Hover.Would(bind))
end)

local held = {}   -- index -> the key currently on the override layer
local heldAny     -- true while at least one is up
local pending     -- a change combat refused, retried when the fight ends
local proven      -- nil until the readback has answered once
local warned

-- Override bindings, never real ones, for the reason every other key in this
-- addon uses them: SetBindingClick writes into the live binding set and the next
-- SaveBindings, which the Key Bindings panel calls when you click Okay, makes
-- that permanent and loses whatever the key was carrying.
--
-- pcalled because the call is refused under lockdown and because nothing here
-- proves it takes a mouse button name on 2.5.6.
local function Set(key, index)
	if type(SetOverrideBindingClick) ~= "function" then
		return false
	end
	return (pcall(SetOverrideBindingClick, button, true, key, BUTTON_NAME, tostring(index)))
end

-- Reads the override layer back. A client that accepts the call and does nothing
-- with it leaves no other trace, and the difference between the key working and
-- the call merely returning is the only question this file cannot answer by
-- inspection. Nil means the question could not be asked.
local function Reads(key, index)
	if type(GetBindingAction) ~= "function" then
		return nil
	end
	local ok, action = pcall(GetBindingAction, key, true)
	if not ok or type(action) ~= "string" or action == "" then
		return nil
	end
	return action == ("CLICK %s:%d"):format(BUTTON_NAME, index)
end

-- Every suffix the button has ever been given, cleared before the live ones go
-- back on. A binding taken off the list leaves its attributes behind otherwise,
-- and the key it was on is free again while the macro sits there waiting for a
-- click that will never come, which is the kind of leftover that only shows up
-- when a later binding lands on the same index.
local function Wipe()
	for index = 1, ns.Hover.MAX do
		button:SetAttribute("*type" .. index, nil)
		button:SetAttribute("*macrotext" .. index, nil)
	end
end

-- Returns false when combat deferred the work, so the caller can say so.
function Cast.Apply()
	if InCombatLockdown() then
		pending = true
		Log("in combat, so the keys are held until the fight ends")
		return false
	end
	pending = nil

	if type(ClearOverrideBindings) == "function" then
		pcall(ClearOverrideBindings, button)
	end
	Wipe()
	held, heldAny = {}, false

	if not ns.db.hover then
		Log("mouseover casting is off, so no key is up")
		return true
	end

	for index, bind in ipairs(ns.Hover.List()) do
		local key = bind.key
		if type(key) == "string" and key ~= "" and not ns.Hover.Bare(key) then
			button:SetAttribute("*type" .. index, "macro")
			button:SetAttribute("*macrotext" .. index, ns.Hover.Macro(bind))
			if Set(key, index) then
				held[index] = key
				heldAny = true
				local reads = Reads(key, index)
				if reads ~= nil then
					proven = reads
				end
				Log("%s is index %d, %s, %s", key, index,
					reads == nil and "the readback could not be asked"
						or (reads and "the binding layer agrees" or "|cffff5555the binding layer does not have it|r"),
					ns.Hover.Macro(bind))
			else
				Log("|cffff5555%s was refused by the client|r", key)
				if not warned then
					warned = true
					ns.Print("this client would not take a key for mouseover casting.")
				end
			end
		else
			Log("|cffff5555%s is not a key this can bind|r", tostring(key))
		end
	end

	if heldAny and proven == false and not warned then
		warned = true
		ns.Print("this client accepted the mouseover keys and did not bind them.")
	end
	return true
end

-- Whether a key this file put up is actually holding. The panel draws a bound
-- key in the quiet grey when this comes back false, so a key the client refused
-- looks different from a key that is doing its job.
function Cast.Holding(index)
	return held[index] ~= nil
end

-- Always reports what the binding layer says, never what this file meant to set.
function Cast.Describe()
	if InCombatLockdown() and pending then
		return "waiting for combat to drop"
	end
	if not heldAny then
		return "no key is up"
	end
	if proven == nil then
		return "unproven"
	end
	if not proven then
		return "the client did not take them"
	end
	return "the keys are up"
end

-- The macro one binding is carrying, read back off the button rather than built
-- again. `/wk hover show` prints these, and a line that came from the same place
-- the press comes from is the only line worth printing.
function Cast.Macro(index)
	return button:GetAttribute("*macrotext" .. index)
end

--------------------------------------------------------------------------
-- Did the client do anything with it
--
-- The one question the two logs above cannot answer between them. PreClick says
-- the press reached the button; nothing on this side of the secure handler says
-- whether the macro ran, because a conditional that does not match and a
-- protected call that was discarded are both silent and look identical.
--
-- UNIT_SPELLCAST_SENT is the client answering. A press with a verdict of `casts`
-- and no `the client sent` line under it is the press being thrown away, which
-- is exactly the failure the click registration above was.
--
-- Registered only while the log is on, and it fires once per cast rather than on
-- a ticker, so it costs nothing either way.
--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, unit, target, _, spell)
	if event == "UNIT_SPELLCAST_SENT" then
		if unit == "player" then
			Log("  the client sent %s at %s",
				ns.SpellName(spell) or tostring(spell), target or "nothing")
		end
		return
	end
	if event == "PLAYER_REGEN_ENABLED" and not pending then
		return
	end
	Cast.Apply()
	Cast.Watch()
end)

-- Called where the log is turned on and off, and once at login, because a log
-- that only starts watching at the next reload is a log that lies by omission.
function Cast.Watch()
	if ns.db and ns.db.hoverDebug then
		events:RegisterEvent("UNIT_SPELLCAST_SENT")
	else
		events:UnregisterEvent("UNIT_SPELLCAST_SENT")
	end
end
