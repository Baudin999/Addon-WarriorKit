local ADDON, ns = ...

local Hover = {}
ns.Hover = Hover

--------------------------------------------------------------------------
-- Casting on what the mouse is over
--
-- One key, one spell, and the mob or the party member under the cursor. It is
-- what Clique does and it is why Clique is installed on nearly every healer in
-- the game, and this is the addon's own so the bindings live beside every other
-- setting rather than in a second addon's saved variables.
--
-- The mechanism is already proven here. Marking/Keys.lua binds modified mouse
-- buttons through SetOverrideBindingClick and marks `mouseover`, out in the
-- world and on a nameplate both, and the whole of the reasoning for that is in
-- its header. The one thing marking did not need is the one thing this needs:
-- casting is protected, so the click has to land on a SecureActionButtonTemplate
-- rather than on a plain button running Lua.
--
-- This file is the model and nothing else. What a binding is, what the cursor is
-- carrying, which key is free, and what macro one binding turns into. Cast.lua
-- owns the button and the keys, Sheet.lua draws the list on screen, and neither
-- of them decides anything.
--
-- The filter is a macro conditional rather than a unit attribute, because a
-- unit attribute cannot say "only when it is an enemy". `[@mouseover,harm]` can,
-- it is what every hand written mouseover macro in the game is built on, and it
-- costs nothing at the moment of the press: a conditional that does not match
-- casts nothing and says nothing. That also means a binding survives combat
-- without being rewritten, which an attribute would not, because attributes
-- cannot be touched once lockdown is up.
--------------------------------------------------------------------------

-- Twelve, which is a full action bar's worth of keys and more than anybody
-- holds in their hands at once. The ceiling exists because the sheet and the
-- panel both build their rows once at login and show the ones that are used:
-- a row that appears when you bind a key has to already be there.
local MAX = 12

Hover.MAX = MAX

-- Who a press is allowed to land on, and the macro conditional that says so.
--
-- `nodead` is on all three. A dead mouseover is a corpse you are looting or a
-- party member waiting on a resurrection, and a heal or a Rend aimed at one is
-- a press that reports an error back at you for nothing.
--
-- The order is the order the picker offers them in and the order the sheet
-- sorts by, so enemy first: this addon's own class is a warrior and the enemy
-- binding is the one that gets made first.
Hover.WHO = {
	{ id = "enemy",  label = "an enemy",     clause = "harm,nodead", tone = "loss" },
	{ id = "friend", label = "a friend",     clause = "help,nodead", tone = "tick" },
	{ id = "any",    label = "anything",     clause = "exists,nodead", tone = "dim" },
}

-- The two the binding system must never lose, refused here for the reason
-- Marking/Keys.lua refuses them: an unmodified mouse button binding eats plain
-- targeting and the camera drag. Every writer of a key in this addon holds the
-- same rule, and each holds it where the key is written rather than trusting
-- the one above it.
local BARE = { BUTTON1 = true, BUTTON2 = true }

function Hover.Bare(key)
	return BARE[key] == true
end

function Hover.Who(id)
	for _, who in ipairs(Hover.WHO) do
		if who.id == id then
			return who
		end
	end
	return Hover.WHO[1]
end

function Hover.List()
	return (ns.dbc and ns.dbc.hoverBinds) or {}
end

--------------------------------------------------------------------------
-- What is on the cursor
--
-- The slot in the options page is filled by dropping a spell on it, which means
-- reading GetCursorInfo, which is the one call in this file that cannot be
-- written from the documentation with any confidence.
--
-- For an item it answers the kind, the id and the link, and UI/Widgets.lua has
-- been reading it that way since the loadout page shipped. For a spell it
-- answers the spellbook index and which book it is in, and newer builds put the
-- spell id in a fourth slot. Nothing installed on this machine proves which of
-- those 2.5.6 hands back, so all three readings are tried and the first one that
-- names a spell wins. A select(4) written straight would be right on one client
-- and silently nil on the other.
--
-- A wrong reading is visible before it costs anything. The name and the icon go
-- into the slot, and the key is not pressed until you have looked at them.
--------------------------------------------------------------------------

local function BookName(index, book)
	if type(_G.GetSpellBookItemName) ~= "function" then
		return nil
	end
	local ok, name = pcall(_G.GetSpellBookItemName, index, book)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	return nil
end

local function SpellOnCursor(a, b, c)
	if type(c) == "number" then
		local name = ns.SpellName(c)
		if name then
			return name
		end
	end
	if type(a) == "number" and type(b) == "string" then
		local name = BookName(a, b)
		if name then
			return name
		end
	end
	if type(a) == "number" then
		return ns.SpellName(a)
	end
	return nil
end

-- A pick, or nil and the sentence to print. A pick is what the slot holds and
-- what a binding is made out of: the verb it needs, the name a macro casts by,
-- and the picture the sheet draws.
--
-- The name rather than the id, because `/cast Thunder Clap` with no rank named
-- casts the best one you know. Buttons/Ranks.lua exists to keep a plain spell on
-- an action bar up to date after a trainer visit; a binding made here never goes
-- stale in the first place.
function Hover.Carry(kind, a, b, c)
	if kind == "spell" then
		local name = SpellOnCursor(a, b, c)
		if not name then
			return nil, "this client would not say which spell that was."
		end
		return { kind = "spell", name = name, icon = ns.SpellTexture(name) }
	end

	if kind == "item" then
		local name, icon = ns.ItemInfo(b)
		if not name then
			return nil, "this client would not say what that item is."
		end
		return { kind = "item", name = name, icon = icon }
	end

	if kind then
		return nil, ("a %s cannot be bound to a key here. Drop a spell or an item."):format(kind)
	end
	return nil
end

--------------------------------------------------------------------------
-- The slot
--
-- What you dropped, held until a key is pressed on it. One at a time, because
-- the gesture is a pair: fill the slot, press the key, the slot empties.
--------------------------------------------------------------------------

local held

function Hover.Held()
	return held
end

function Hover.Hold(pick)
	held = pick
end

--------------------------------------------------------------------------
-- The bindings
--------------------------------------------------------------------------

-- Which binding already owns a key, or nil. Two bindings on one key is the
-- mistake nothing can show you afterwards: the second override wins and the
-- first spell simply stops casting, which is exactly why Marking/Keys.lua
-- carries the same check.
function Hover.Owner(key)
	for _, bind in ipairs(Hover.List()) do
		if bind.key == key then
			return bind
		end
	end
	return nil
end

-- Everything a change has to reach. Called by every writer below rather than by
-- the panel and the slash word separately, because a binding written and not
-- applied is a key that does nothing until the next login.
function Hover.Changed()
	ns.HoverCast.Apply()
	ns.HoverSheet.Rebuild()
end

-- Returns true, or false and the sentence to print. The slot has to be full,
-- because the key is the second half of the gesture and a key bound to nothing
-- is a key that has been taken away from whatever it used to do.
function Hover.Bind(key)
	key = key or ""
	if key == "" then
		return false, "nothing was pressed."
	end
	if BARE[key] then
		return false, ("%s belongs to targeting and the camera. Hold a modifier."):format(key)
	end
	if not held then
		return false, "drop a spell on the slot first, then press the key."
	end

	local owner = Hover.Owner(key)
	if owner then
		return false, ("%s already casts %s."):format(key, owner.name)
	end

	local list = Hover.List()
	if #list >= MAX then
		return false, ("%d keys is the most this holds. Take one off first."):format(MAX)
	end

	list[#list + 1] = {
		key = key, who = ns.db.hoverWho,
		kind = held.kind, name = held.name, icon = held.icon,
	}
	held = nil
	Hover.Changed()
	return true
end

-- Returns the name that came off, or nil where that slot held nothing. Indexed
-- rather than keyed, because the panel and the sheet both draw the list in
-- order and the row you pressed remove on is the row you meant.
function Hover.Remove(index)
	local list = Hover.List()
	local bind = list[index]
	if not bind then
		return nil
	end
	table.remove(list, index)
	Hover.Changed()
	return bind.name
end

function Hover.Clear()
	local list = Hover.List()
	local count = #list
	for index = count, 1, -1 do
		list[index] = nil
	end
	Hover.Changed()
	return count
end

--------------------------------------------------------------------------
-- What one binding casts
--
-- Built here rather than in Cast.lua, because it is the whole of what a binding
-- means and none of it is about a button or a key.
--
-- The fallback clause is the same conditional with the `@mouseover` taken off,
-- which tests the target you already have. Off by default: a key that quietly
-- hits your target when you meant to hover something is worse than a key that
-- does nothing, and the sheet has no way to draw the difference.
--------------------------------------------------------------------------

function Hover.Macro(bind)
	local who = Hover.Who(bind.who)
	local verb = bind.kind == "item" and "/use" or "/cast"
	local clause = ("[@mouseover,%s]"):format(who.clause)
	if ns.db.hoverFallback then
		clause = clause .. ("[%s]"):format(who.clause)
	end
	return ("%s %s %s"):format(verb, clause, bind.name)
end

-- One binding, said in one line, for the sheet and for /wk status both.
function Hover.Line(bind)
	return ("%s  %s on %s"):format(bind.key, bind.name, Hover.Who(bind.who).label)
end

function Hover.Describe()
	local list = Hover.List()
	if #list == 0 then
		return "nothing bound"
	end
	return ("%d bound, %s"):format(#list, ns.HoverCast.Describe())
end
