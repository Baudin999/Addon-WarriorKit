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
-- The name has two halves and both of them shipped wrong, one after the other.
--
-- The `*` in front is the modifier. The prefix is read off the keyboard at the
-- moment of the press, so a binding on ALT-BUTTON3 arrives looking for
-- `alt-type...`, and every key worth putting a mouseover spell on carries a
-- modifier. `*` is the wildcard the client falls back to when the modified name
-- holds nothing, which is why UnitFrames/Group.lua writes its click actions the
-- same way.
--
-- The dash behind it is the click name, and it is the one that was still wrong
-- after the modifier was fixed. The client turns the name a click arrives under
-- into an attribute suffix, and it only has five names it answers with a bare
-- number: LeftButton is `1`, RightButton is `2`, and so on to Button5. Every
-- other name is answered with a dash in front of it. So a click handed over as
-- `1` is not the button one at all, it is a name of its own, and the suffix the
-- client goes looking for is `-1`. The attributes were under `*type1`, the press
-- asked for `*type-1`, and the key bound, read back correctly, arrived at the
-- button and cast nothing.
--
-- Clique is where the shape came from. Every name it hands the binding layer is
-- a word rather than a number, and every attribute it writes for one carries the
-- dash: `type-cliquebuttonshiftF`. Buttons/Bars.lua is the same rule seen from
-- the other side, and is why its keys have always worked: it hands over the
-- literal `LeftButton`, which is one of the five, and reads `type1`.
--
-- So the click is called `wk<index>` and the attribute is `*type-wk<index>`.
--
-- Attributes rather than macro text, and the filter said as a second name rather
-- than as a conditional. Both of those are argued out where they are written,
-- below and in Hover.lua. The short of it is that macro text set by insecure code
-- and run off a keypress is the one thing the secure system exists to refuse, and
-- that `harmbutton` says what `[harm]` says without asking for a script.
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

-- One edge, and the attribute that names it beside it.
--
-- Buttons/Bars.lua settled this on a live client and its header carries the
-- proof: a key bound with SetOverrideBindingClick fires on whichever edge
-- useOnKeyDown names, and with the attribute unset that edge is the down one.
-- Charge/Icon.lua registers AnyDown, sets nothing, and its key has always
-- worked; the cloned bars registered AnyUp against an unset attribute and went
-- dark under the key while casting nothing.
--
-- So the two are set to agree rather than to cover each other. Both edges
-- registered against an unset attribute was the shape this file shipped, and it
-- is one dispatch either way: registering the edge that is never dispatched buys
-- nothing and hides which edge is live. Clique pairs the same two settings on
-- its own global button and ships them on the down edge, which is what a key
-- that casts should feel like.
button:RegisterForClicks("AnyDown")
button:SetAttribute("useOnKeyDown", true)

--------------------------------------------------------------------------
-- What one binding is called
--
-- The click name and the attribute names are one decision, so they are made
-- once and here, above everything that writes either of them. The reasoning is
-- in the header; this is the shape of it.
--------------------------------------------------------------------------

-- The name one binding's click arrives under, and what the binding layer stores.
-- A word rather than a number, for the reason in the header.
local function Name(index)
	return "wk" .. index
end

-- The tail of every attribute that answers a click called `name`. The dash is
-- the client's own and not this file's punctuation: it is what a click name that
-- is not one of the five real mouse buttons is turned into a suffix by.
local function Tail(name)
	return "-" .. name
end

-- The second name the filter sends the click to, or nil where it takes anyone.
-- `harmbutton` and `helpbutton` carry it and the action lives only under it, so
-- a press on the wrong sort of unit arrives on a name holding nothing.
local function Remap(index, who)
	return who.remap and (who.id .. Name(index)) or nil
end

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

-- PostClick, and installed only while the log is on. Both halves of that are the
-- repair for a mistake this file made and then spent four settings chasing.
--
-- It was a PreClick, set at load and left there, returning early when the log was
-- off. PreClick runs insecure Lua inside the click, before the secure handler,
-- and an insecure script in that path taints it, so the protected call at the end
-- is dropped. An early return does not help: the taint is the script running at
-- all, not what it does. So every press since the log was added arrived at the
-- button, read back perfectly, matched its conditional, and cast nothing, and the
-- log sat underneath saying the press was fine. The instrument was the fault.
--
-- PostClick runs after the secure handler has had its turn, so nothing written
-- here can take the cast away. It reports the same things one moment later.
--
-- Installed and cleared rather than left in place, because a debug hook that is
-- only inert when it returns early is not inert. With the log off there is no
-- script on this button at all and the click path is the client's own.
local function Trace(_, click, down)
	local index = tonumber(tostring(click):match("^wk(%d+)$") or "")
	local bind = index and ns.Hover.List()[index]
	Log("arrived on %s, down %s", tostring(click), tostring(down))
	if not bind then
		Log("  no binding at %s, so the button carries nothing for it", tostring(click))
		return
	end
	Log("  %s", Cast.Macro(index) or "|cffff5555the button carries nothing under that name|r")
	Log("  %s", ns.Hover.Sight())
	Log("  %s", ns.Hover.Would(bind))

	-- The client's own reading of the same conditional, one form at a time. Every
	-- line saying matches, with no cast behind it, is what said the macro was
	-- never the problem.
	for _, form in ipairs(ns.Hover.Forms(bind)) do
		local knows = ns.Hover.Understands(form, bind.name)
		Log("  %s %s", form,
			knows == nil and "cannot be asked on this client"
				or (knows and "matches" or "|cffff5555does not match|r"))
	end
end

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
	return (pcall(SetOverrideBindingClick, button, true, key, BUTTON_NAME, Name(index)))
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
	return action == ("CLICK %s:%s"):format(BUTTON_NAME, Name(index))
end

--------------------------------------------------------------------------
-- What one binding writes on the button
--
-- Attributes naming a spell, not macro text, and this is the third thing that
-- shipped wrong. It is the one that was invisible the longest, because every
-- reading an addon can take of it comes back correct.
--
-- The button carried `type` = macro and `macrotext` = the whole conditional. The
-- click arrived, the attributes read back exactly as written, the client's own
-- parser agreed the conditional matched the thing under the cursor, and no spell
-- was ever sent. Macro text set by insecure code and run off a keypress is the
-- automation the secure system exists to refuse, so the handler read it, declined
-- it, and said nothing. There is no error for this and no readback that shows it.
--
-- Clique never sets macrotext from outside a secure snippet. What it writes for a
-- key that casts on the mouseover is three attributes:
--
--     unit  = "mouseover"
--     type  = "spell"
--     spell = the name
--
-- and that is what is written here. All three are things insecure code is allowed
-- to say, because none of them is a script: they name a spell and a unit and let
-- the client decide the rest.
--
-- The filter is the part with no obvious shape in attributes, and the answer is
-- not a conditional, it is a second name. `helpbutton` says: when the unit under
-- the cursor can be helped, deliver this click as `friend1` instead of `1`. The
-- action lives only under `friend1`. A press on an enemy arrives as `1`, finds no
-- type at all, and does nothing, which is the same silence a conditional would
-- have produced and is reached without one.
--
-- `nodead` is gone with the conditional and cannot be got back this way. A key
-- pressed on a corpse now casts and the client refuses it out loud, which is a
-- worse manner than the old silence and a better one than not casting at all.
--------------------------------------------------------------------------

-- The attribute that carries the thing being cast, which is named after it.
local function Verb(bind)
	return bind.kind == "item" and "item" or "spell"
end

-- Every name any binding has ever been given, cleared before the live ones go
-- back on. A binding taken off the list leaves its attributes behind otherwise,
-- and the key it was on is free again while the action sits there waiting for a
-- click that will never come, which is the kind of leftover that only shows up
-- when a later binding lands on the same index.
--
-- Both names for every filter, because a binding that was on `a friend` and is
-- now on `anything` left `*type-friendwk1` behind, and that name still answers
-- the moment the unit under the cursor can be helped.
local function Wipe()
	for index = 1, ns.Hover.MAX do
		local names = { Name(index) }
		for _, who in ipairs(ns.Hover.WHO) do
			if who.remap then
				names[#names + 1] = who.id .. Name(index)
				button:SetAttribute("*" .. who.remap .. Tail(Name(index)), nil)
			end
		end
		for _, name in ipairs(names) do
			local tail = Tail(name)
			button:SetAttribute("*type" .. tail, nil)
			button:SetAttribute("*unit" .. tail, nil)
			button:SetAttribute("*spell" .. tail, nil)
			button:SetAttribute("*item" .. tail, nil)
			-- The shape this used to be. A button that kept it would still be
			-- carrying the macro that never cast anything.
			button:SetAttribute("*macrotext" .. tail, nil)
		end
	end
end

local function Write(index, bind)
	local who = ns.Hover.Who(bind.who)
	local name = Name(index)
	local under = Remap(index, who) or name

	-- On the name the click arrives under, because the filter is a question about
	-- a unit and this is the attribute that says which unit to ask about.
	button:SetAttribute("*unit" .. Tail(name), "mouseover")
	if who.remap then
		button:SetAttribute("*" .. who.remap .. Tail(name), under)
		button:SetAttribute("*unit" .. Tail(under), "mouseover")
	end
	button:SetAttribute("*type" .. Tail(under), Verb(bind))
	button:SetAttribute("*" .. Verb(bind) .. Tail(under), bind.name)
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
			Write(index, bind)
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

-- What one binding is carrying, read back off the button rather than built again.
-- `/wk hover show` prints these, and a line that came from the same place the
-- press comes from is the only line worth printing.
--
-- Read under the name the action actually lives on, which is the name the filter
-- chose, so a row whose remap was never written comes back nil and prints as the
-- key that carries nothing.
function Cast.Macro(index)
	local bind = ns.Hover.List()[index]
	if not bind then
		return nil
	end
	local who = ns.Hover.Who(bind.who)
	local tail = Tail(Remap(index, who) or Name(index))
	local what = button:GetAttribute("*" .. Verb(bind) .. tail)
	if not what then
		return nil
	end
	return ("%s %s on %s"):format(
		button:GetAttribute("*type" .. tail) or "?", what,
		button:GetAttribute("*unit" .. tail) or "?")
end

--------------------------------------------------------------------------
-- Did the client do anything with it
--
-- The one question the two logs above cannot answer between them. PostClick says
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
	local on = ns.db and ns.db.hoverDebug
	button:SetScript("PostClick", on and Trace or nil)
	if on then
		events:RegisterEvent("UNIT_SPELLCAST_SENT")
	else
		events:UnregisterEvent("UNIT_SPELLCAST_SENT")
	end
end
