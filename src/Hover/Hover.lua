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
-- The filter is a macro conditional and the whole macro is built here, because
-- it is the whole of what a binding means. Cast.lua puts it on the button as
-- macro text, the way Charge/Icon.lua has always put its own, and the argument
-- for that being text and not attributes is in Cast.lua's header.
--------------------------------------------------------------------------

-- Twelve, which is a full action bar's worth of keys and more than anybody
-- holds in their hands at once. The ceiling exists because the sheet and the
-- panel both build their rows once and show the ones that are used:
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
--
-- `clause` is the filter as the conditional the press is made under, and
-- `unless` is its negation, one clause per term, which is what sends the press
-- through to whatever the key did before when the thing under the cursor is
-- not `label`. Written out rather than derived, because the negation of two
-- terms is two clauses and deriving that from a string is a parser for three
-- rows.
Hover.WHO = {
	{ id = "enemy",  label = "an enemy",   clause = "harm,nodead",   unless = { "noharm", "dead" },   tone = "loss" },
	{ id = "friend", label = "a friend",   clause = "help,nodead",   unless = { "nohelp", "dead" },   tone = "tick" },
	{ id = "any",    label = "anything",   clause = "exists,nodead", unless = { "noexists", "dead" }, tone = "dim" },
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
-- been reading it that way since the first page took a drop. For a spell it
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
	-- A key this list gives back is the bar's again, and a key it takes is one
	-- the bar has to stop binding and keep drawing. The bars read the binding
	-- set for both, so they are told rather than left to UPDATE_BINDINGS,
	-- because nothing installed here proves that dropping an override fires it.
	ns.Bars.ApplyBindings()
	ns.HoverSheet.Rebuild()
end

-- Whether a press of this key is this part's, which is what Buttons/Bars.lua
-- asks before it binds one. A key held here still presses the square it was on,
-- through the second line of the macro, so the bar draws it and does not bind
-- it: two overrides on one key is whichever was set last.
function Hover.Holds(key)
	if not (ns.db and ns.db.hover) or type(key) ~= "string" or BARE[key] then
		return false
	end
	return Hover.Owner(key) ~= nil
end

-- Why a key cannot be written, or nil where it can. `mine` is the row already
-- allowed to hold it, which is what tells rebinding a row to its own key from
-- taking a key off its neighbour.
--
-- One function because the row on a page and the empty row above it write keys
-- through different calls and must refuse them in the same words. A rule that
-- lives in one of two writers is a rule the other one does not have.
local function Refuses(key, mine)
	if key == "" then
		return "nothing was pressed."
	end
	if BARE[key] then
		return ("%s belongs to targeting and the camera. Hold a modifier."):format(key)
	end
	local owner = Hover.Owner(key)
	if owner and owner ~= mine then
		return ("%s already casts %s."):format(key, owner.name)
	end
	return nil
end

-- Returns true, or false and the sentence to print. The slot has to be full,
-- because the key is the second half of the gesture and a key bound to nothing
-- is a key that has been taken away from whatever it used to do.
function Hover.Bind(key)
	key = key or ""
	local why = Refuses(key, nil)
	if why then
		return false, why
	end
	if not held then
		return false, "drop a spell on the slot first, then press the key."
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

--------------------------------------------------------------------------
-- Changing one that is already there
--
-- Three writers, one per column of the row, because a binding is three
-- decisions and a page that can only add and delete makes you delete a row to
-- correct the one of them you got wrong.
--
-- Each answers true, or false and the sentence to print, which is what Bind
-- answers and what the panel and the slash words already know how to say.
--------------------------------------------------------------------------

function Hover.Rebind(index, key)
	local bind = Hover.List()[index]
	if not bind then
		return false, "there is no such key."
	end
	key = key or ""
	local why = Refuses(key, bind)
	if why then
		return false, why
	end
	bind.key = key
	Hover.Changed()
	return true
end

-- The pick comes off the cursor through Hover.Carry, so what arrives here is
-- already a spell or an item this client could name.
function Hover.Respell(index, pick)
	local bind = Hover.List()[index]
	if not bind or not pick then
		return false, "drop a spell on the row to change what it casts."
	end
	bind.kind, bind.name, bind.icon = pick.kind, pick.name, pick.icon
	Hover.Changed()
	return true
end

function Hover.Retarget(index, who)
	local bind = Hover.List()[index]
	if not bind then
		return false, "there is no such key."
	end
	bind.who = Hover.Who(who).id
	Hover.Changed()
	return true
end

-- The next filter round, for the button on the row that cycles rather than
-- opens a list. Three entries is short enough that a press each is faster than
-- a dropdown, and the row has no width for one.
function Hover.NextWho(who)
	for index, entry in ipairs(Hover.WHO) do
		if entry.id == who then
			return Hover.WHO[index % #Hover.WHO + 1].id
		end
	end
	return Hover.WHO[1].id
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
-- means and none of it is about a button or a key. Cast.lua puts the text on
-- the button and `/wk hover show` reads it back off.
--
-- Two lines. The spell on the thing under the cursor when the filter passes,
-- and when it does not, a click on whatever the key was pressing before this
-- binding was put on top of it: the square on the bar, for the key a heal is
-- already on. That is what makes one key a heal on the party member under the
-- cursor and a heal on yourself with nothing there, and it is the whole of what
-- a key on both a bar and this list means.
--
-- `beneath` is that button, or nil for a key that pressed nothing, in which
-- case the press with nothing under the cursor does nothing. A key that quietly
-- hits your target when you meant to hover something is worse than a key that
-- does nothing, and the sheet has no way to draw the difference.
--
-- `@mouseover` once. Charge/Icon.lua has run that spelling on this client since
-- it shipped, so the `target=mouseover` this used to be doubled with was a
-- hedge against a build this addon does not run on.
--------------------------------------------------------------------------

function Hover.Macro(bind, beneath)
	local who = Hover.Who(bind.who)
	local verb = bind.kind == "item" and "/use" or "/cast"
	local cast = ("%s [@mouseover,%s] %s"):format(verb, who.clause, bind.name)
	if not beneath then
		return cast
	end
	local clauses = {}
	for index, term in ipairs(who.unless) do
		clauses[index] = ("[@mouseover,%s]"):format(term)
	end
	-- `true` on the end is the edge. A click delivered on the edge a button does
	-- not fire on is a click the button throws away, and which edge that is is
	-- the button's to say; Buttons/Bars.lua read it off the button.
	local click = ("/click %s %s %s%s"):format(table.concat(clauses), beneath.name,
		beneath.button or "LeftButton", beneath.down and " true" or "")
	return cast .. "\n" .. click
end

--------------------------------------------------------------------------
-- What the press finds
--
-- Said, never acted on. The conditional in the macro decides for real, at the
-- moment of the press, inside the secure call; everything below is a second
-- reading of the same three things taken beside it so the debug log can print
-- what the conditional was looking at.
--
-- It exists because this feature has exactly one failure that leaves no trace.
-- A key that is bound, arrives at the button and casts nothing looks identical
-- to a key that was never bound at all, and the usual reason is the filter: a
-- binding made without touching the target button carries `an enemy`, and a
-- heal aimed at a friend under `harm` is a press the client discards in
-- silence. Nothing here is called unless `/wk hover debug on`.
--------------------------------------------------------------------------

local function Look(unit)
	if not UnitExists(unit) then
		return nil
	end
	return {
		name = UnitName(unit) or "?",
		dead = UnitIsDeadOrGhost(unit) and true or false,
		harm = UnitCanAttack("player", unit) and true or false,
		help = type(UnitCanAssist) == "function"
			and (UnitCanAssist("player", unit) and true or false)
			or (UnitIsFriend("player", unit) and true or false),
	}
end

-- The same three tests the conditional makes, in the same order, so a verdict
-- printed here and a press that casts nothing disagree only where this file is
-- wrong about the client.
local function Matches(who, seen)
	if not seen or seen.dead then
		return false
	end
	if who.id == "enemy" then
		return seen.harm
	end
	if who.id == "friend" then
		return seen.help
	end
	return true
end

-- The filter's two spellings, one per line, for the debug log to ask the client
-- about separately. Hover.Macro presses the first; the log asks both, because a
-- build that carries `@mouseover` and not `target=mouseover` answers yes to one
-- and no to the other, and one line each is what shows which of the two this
-- client is on.
function Hover.Forms(bind)
	local who = Hover.Who(bind.who)
	return {
		("[@mouseover,%s]"):format(who.clause),
		("[target=mouseover,%s]"):format(who.clause),
	}
end

-- What the client's own parser makes of one form, or nil where it cannot be
-- asked. True where the conditional matched and the spell would have been sent,
-- which is the reading that says the filter was never the problem.
--
-- The parser is asked rather than reimplemented, because Matches above is this
-- file's opinion of the same three tests and the whole point of printing both is
-- to see them disagree.
function Hover.Understands(form, name)
	if type(_G.SecureCmdOptionParse) ~= "function" then
		return nil
	end
	local ok, said = pcall(_G.SecureCmdOptionParse, ("%s %s"):format(form, name))
	if not ok then
		return nil
	end
	return said == name
end

-- The raw reading, for the line above the verdict. Whether it is attackable and
-- whether it is assistable both, because a totem, a critter and a duelling
-- friend are each one and not the other and the verdict alone would not say so.
function Hover.Sight()
	local seen = Look("mouseover")
	if not seen then
		return "nothing under the cursor"
	end
	return ("%s under the cursor, %s, %s"):format(seen.name,
		seen.dead and "dead" or "alive",
		seen.harm and (seen.help and "attackable and assistable" or "attackable")
			or (seen.help and "assistable" or "neither attackable nor assistable"))
end

-- What one binding would do about that, in one sentence ending in the reason.
function Hover.Would(bind)
	local who = Hover.Who(bind.who)
	local over = Look("mouseover")

	if Matches(who, over) then
		return ("casts %s on %s"):format(bind.name, over.name)
	end
	if over then
		return ("%s is not %s, so nothing casts"):format(over.name, who.label)
	end
	return "nothing under the cursor, so nothing casts"
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
