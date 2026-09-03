local ADDON, ns = ...

local Bars = {}
ns.Bars = Bars

local UI = ns.UI
local Ability, Flow = UI.Ability, UI.Flow

-- The plan, and the question of which of it you want, both in Which.lua.
local Which = ns.WhichBars

--------------------------------------------------------------------------
-- The bars
--
-- A clone of whichever action bars you already have, drawn as squares this
-- addon owns, reading the same action slots and answering the same keys.
-- Blizzard's own buttons are hidden underneath, and the off switch puts them
-- back without a reload.
--
-- Three things it deliberately does not invent.
--
--   Slots. Every square reads a Blizzard action slot, the one the button it
--   replaced was reading. Buttons/Layout.lua writes those slots and your saved
--   keybindings already point at them, so a clone with a slot space of its own
--   would need both rewritten to say the same thing twice.
--
--   Keys. Every key is read off the binding set with GetBindingKey and put
--   back on top of it with SetOverrideBindingClick. Nothing here calls
--   SetBinding or SaveBindings, which is the README's hard rule and is what
--   makes the off switch free: an override is a layer, not a write, and
--   dropping it leaves the binding set exactly as it was found.
--
--   Which bars exist. Buttons/Which.lua holds the plan of what this client can
--   have and answers which of them you want, and the shipping answer is read
--   off your own bars: one you have on is one we clone. This file builds what
--   that question returns and hands back what it does not.
--
-- Where a bar sits and what shape it is are two different answers and neither
-- is in this file. Buttons/Placing.lua owns the position, because a position is
-- the one thing you cannot sensibly type. Buttons/Look.lua owns the rest of the
-- bar you can see: how many rows the twelve break into, what colour the ground
-- under them is, how much of it there is, and whether the bar is on screen in
-- combat or only while a key is held. This file asks that one what to draw and
-- draws it.
--
-- What the client will not let this file do, and how each is answered:
--
--   Rewrite an attribute in combat. A stance change happens mid-fight, and
--   pointing bar 1 at the next twelve slots is an attribute write, so it
--   cannot be done from Lua at all. It is done by a snippet running inside a
--   SecureHandlerStateTemplate off RegisterStateDriver, which is the same
--   machinery Charge/Icon.lua already uses to drop its key in combat, and it is
--   probed the same way, because nothing installed here proves it is on 2.5.6.
--   Bars.CanPage says which path came up.
--
--   Bind, unbind, hide or show a protected frame in combat. Every one of those
--   is in Bars.Apply, which refuses in lockdown, sets pending and is run again
--   at PLAYER_REGEN_ENABLED. That is Charge/Icon.lua's ApplySecure shape.
--
-- What a square deliberately is not: a Blizzard action button. It casts, it
-- draws what the slot is doing, it carries its key, it names what is on it when
-- you hover it, and you can drag a spell onto it. Filling a slot is
-- Buttons/Layout.lua's job or the spellbook's, and both write the same slots
-- these squares read, so the picture updates on the next tick either way.
--
-- What one square answers to the mouse is Buttons/Square.lua, which is where
-- the tooltip and the drag live and where the argument for both is written
-- down. This file builds the squares and points them at slots; that one hangs
-- the scripts.
--------------------------------------------------------------------------

-- Ten a second, which is what the charge icon runs at and is the rate a
-- cooldown timer has to be redrawn at for the tenths under ten seconds to
-- count down rather than jump. Every square is walked on every pass, and a
-- square nothing has happened to costs one read and a comparison rather than
-- the twelve to sixteen reads the whole ladder is.
local UPDATE_INTERVAL = 0.1

-- Twelve is every action bar the client has ever had, and the stride between
-- one bar's slots and the next.
local PER_BAR = 12


--------------------------------------------------------------------------
-- The plan
--------------------------------------------------------------------------

-- How big a square is is a setting now, in Buttons/Look.lua, which is also
-- where the argument for the 27 it defaults to is written down and where the
-- harness asserts that default is a size this client can draw sharp.
--
-- The gap between two squares and the pad round the twelve are not settings.
-- They are two pixels and three, they are what makes a bar look like one thing
-- rather than twelve, and nothing is answered by asking a player for them.
local GAP = 2
local PAD = 3


--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------

local order = {}       -- one entry per cloned bar, in draw order
local built = {}       -- bar key to entry, so a second look adds rather than repeats
local squares = {}     -- every square on every bar, flat, walked by the tick
local pool = 0         -- next name out of the button pool

-- What the last look at one square found, one record per square, built when the
-- square joins the walk above and written in place after that.
--
--   dirty     something says the picture may have moved, so the next pass draws
--   harmful   what is in the slot is aimed at an enemy, so the pass asks about
--             range; false for a heal, a totem or an empty square
--   counting  a real cooldown is running, so the number over it has to be
--             written again on every pass
--   range     the last range answer a pass read, so a flip can be seen
--   count     the last stack a pass read, for the same reason
local seen = {}

local live = false     -- the squares are up and the tick should draw them
local tick             -- the action ticker, armed once and kept, see the foot
local pending          -- work combat refused, retried at PLAYER_REGEN_ENABLED
local paging           -- true once a state driver has been accepted
local binding          -- re-entrancy latch, see Bars.ApplyBindings
local proven           -- nil until the override readback has answered once
local keysHeld = 0     -- how many keys the override layer took, last pass

--------------------------------------------------------------------------
-- The key, shortened
--
-- A hotkey label is drawn at seven pixels in the corner of a 27 pixel square,
-- so "SHIFT-BUTTON3" is not a label, it is a smear. The full string still does
-- the binding; this is only what gets printed on the art, and it follows the
-- convention every bar addon settled on years ago because it is the one people
-- can already read: modifiers collapse to a lower case letter each, and the
-- long device names collapse to one or two capitals.
--------------------------------------------------------------------------

local MODIFIER = { ALT = "a", CTRL = "c", SHIFT = "s" }

local NAMED = {
	BUTTON1 = "M1", BUTTON2 = "M2", BUTTON3 = "M3",
	MOUSEWHEELUP = "WU", MOUSEWHEELDOWN = "WD",
	PAGEUP = "PU", PAGEDOWN = "PD",
	INSERT = "In", DELETE = "De", HOME = "Hm", END = "En",
	SPACE = "Sp", BACKSPACE = "BS", ESCAPE = "Esc", ENTER = "Ent", TAB = "Tab",
}

function Bars.Short(key)
	if type(key) ~= "string" or key == "" then
		return ""
	end

	local prefix, rest = "", key
	while true do
		local head, tail = rest:match("^(%u+)%-(.+)$")
		if not head or not MODIFIER[head] then
			break
		end
		prefix = prefix .. MODIFIER[head]
		rest = tail
	end

	if NAMED[rest] then
		return prefix .. NAMED[rest]
	end
	-- NUMPAD7 to n7 and BUTTON4 to M4. Anything else is already short, or is a
	-- key nobody binds and is better half readable than absent.
	rest = (rest:gsub("^NUMPAD", "n"):gsub("^BUTTON", "M"))
	return prefix .. rest
end

-- Both keys the binding set holds for one command. Two, because the client
-- allows a primary and a secondary and losing the secondary is losing a key the
-- player set on purpose.
local function KeysFor(command)
	if type(GetBindingKey) ~= "function" then
		return nil
	end
	local ok, first, second = pcall(GetBindingKey, command)
	if not ok then
		return nil
	end
	return first, second
end

-- What the binding set holds for a key, under every override on it. Read this
-- way round rather than GetBindingKey walked for the key, because a key with
-- an override on it stops answering to its command from that side, and every
-- key this is asked about has one.
local function Under(key)
	if type(GetBindingAction) ~= "function" or type(key) ~= "string" or key == "" then
		return nil
	end
	local ok, action = pcall(GetBindingAction, key)
	if ok and type(action) == "string" and action ~= "" then
		return action
	end
	return nil
end

-- The key the mouseover part holds over this command, or nil. Two things follow
-- from one being there. The bar does not bind it, because two overrides on one
-- key is whichever was set last, and that part's button presses the square
-- itself when nothing under the cursor fits. And the square still draws it,
-- because the key still presses the square.
local function Lent(command)
	for _, bind in ipairs(ns.Hover.List()) do
		if ns.Hover.Holds(bind.key) and Under(bind.key) == command then
			return bind.key
		end
	end
	return nil
end

-- Which edge a button fires on, in the shape `/click` takes it. The attribute
-- where the button has one, the player's setting where it does not, which is
-- the client's own order of asking.
local function Edge(frame)
	local set = frame and frame.GetAttribute and frame:GetAttribute("useOnKeyDown")
	if set == nil then
		set = type(GetCVarBool) == "function" and GetCVarBool("ActionButtonUseKeyDown")
	end
	return set and true or false
end

-- What a key presses under every override, for the mouseover part to put on
-- the second line of its macro: the button's name, the mouse button to press
-- it with, and whether it fires on the down edge. Nil for a key that presses
-- nothing.
--
-- A standing square first, because that is what the key was pressing before
-- the part took it and the square carries the slot's paging. Then the client's
-- own button for the command, for a bar this file has not cloned or for the
-- clone being off, read off the plan so the two names are written down once.
function Bars.Beneath(key)
	local action = Under(key)
	if not action then
		return nil
	end
	for index = 1, live and #order or 0 do
		local entry = order[index]
		for slot = 1, PER_BAR do
			if entry.def.command:format(slot) == action then
				local w = entry.buttons[slot]
				return w:GetName(), "LeftButton", Edge(w)
			end
		end
	end
	for index = 1, #Which.PLAN do
		local def = Which.PLAN[index]
		local slot = action:match("^" .. def.command:gsub("%%d", "(%%d+)") .. "$")
		if slot then
			local name = def.buttons:format(tonumber(slot))
			return name, "LeftButton", Edge(_G[name])
		end
	end
	local name, mouse = action:match("^CLICK ([^:]+):(.+)$")
	if name then
		return name, mouse, Edge(_G[name])
	end
	return nil
end

--------------------------------------------------------------------------
-- Building one bar
--------------------------------------------------------------------------

-- The snippet that re-points bar 1 at a stance's twelve slots.
--
-- It runs inside the restricted environment, where the only things reachable
-- are the header's own attributes and the frames it was handed a reference to.
-- Everything it needs is therefore an attribute: the page bases as page1 to
-- page3 and how many buttons to walk as count. Nothing is seeded through
-- Execute, so a header that lost its environment still works from what the
-- attributes say.
local PAGE_SNIPPET = [[
	local base = self:GetAttribute("page" .. newstate) or self:GetAttribute("page1")
	if base then
		local count = self:GetAttribute("count") or 0
		for index = 1, count do
			local square = self:GetFrameRef("button" .. index)
			if square then
				square:SetAttribute("action", base + index - 1)
			end
		end
	end
]]

-- nostance is what a warrior out of all three stances answers, and what every
-- other class answers always. It maps to page one rather than to nothing,
-- because a bar with no page is a bar of twelve empty squares.
local PAGE_MACRO = "[stance:1] 1; [stance:2] 2; [stance:3] 3; [nostance] 1"

local function BuildBar(entry)
	-- Two frames rather than one, and not for tidiness. UI.Box is what gives
	-- the bar a background and a hairline, and SecureHandlerStateTemplate is
	-- what the state driver needs; a frame cannot be built from both templates,
	-- so the header sits inside the box and covers it exactly.
	local bar = UI.Box(UIParent, UI.Color.window, UI.Color.hairline)
	UI.Adopt(bar, 1)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	bar:Hide()
	entry.frame = bar

	-- pcalled for Charge/Icon.lua's reason: the template is not proven to be on
	-- 2.5.6 by anything installed here, and a client without it should lose the
	-- paging and keep the bar rather than lose the addon.
	local ok, header = pcall(CreateFrame, "Frame", nil, bar, "SecureHandlerStateTemplate")
	if not ok or not header then
		header = CreateFrame("Frame", nil, bar)
	end
	header:SetAllPoints(bar)
	entry.header = header

	-- Depth is a position, so Buttons/Placing.lua owns it. Called here rather
	-- than in Arrange because it is settled once at build and never again, and
	-- called after the header exists because the header is half of what it
	-- stands up.
	ns.BarPlace.Stand(entry)

	entry.buttons = {}
	for index = 1, PER_BAR do
		pool = pool + 1
		local w = Ability.New(header, ("WarriorKitBarButton%d"):format(pool),
			"SecureActionButtonTemplate", Ability.QUIET)
		-- Two edges, and they are two separate switches. The registration is
		-- what the mouse obeys, and it is the up edge because that is what this
		-- client's own action buttons register and because a square you can
		-- drop a spell onto must not cast on the press that starts the drag.
		--
		-- Which edge a bound key fires on is the attribute, and a binding made
		-- with SetOverrideBindingClick reads it. With nothing to read it
		-- dispatches on the down edge, which is where the two disagreed and is
		-- what a dead square looked like: the client pushes a button on the
		-- down edge whichever edge it dispatches, so the square went dark under
		-- the key and the click that would have cast was thrown away by AnyUp
		-- on the way past. Pressed, and inert.
		--
		-- Charge/Icon.lua is the other half of the proof. It registers AnyDown,
		-- sets nothing here, and its key has always worked.
		w:RegisterForClicks("AnyUp")
		w:SetAttribute("useOnKeyDown", false)
		w:SetAttribute("type", "action")
		ns.Square.Handle(w)
		entry.buttons[index] = w
	end

	ns.BarPlace.Handle(entry)
	ns.BarLook.Paint(entry)
end

-- Lay one bar out and put it where the plan says. Called at build and again on
-- a rescale, never on a tick.
--
-- The rows are written out rather than left to Flow's wrap, because wrapping
-- needs a width to wrap against and a width here would be the same arithmetic
-- stated a second time, in a second place, ready to disagree.
local function Arrange(entry)
	-- The shape is a setting, so it is asked for on every layout rather than
	-- read off the plan once. Buttons/Look.lua answers the plan's own columns
	-- for a bar nobody has reshaped, which is what makes this the same call in
	-- both cases.
	local columns = ns.BarLook.Columns(entry.def)
	local size = ns.BarLook.Size(entry.def)
	local rows = { direction = "column", gap = GAP, pad = PAD }
	local row

	for index = 1, PER_BAR do
		if (index - 1) % columns == 0 then
			row = { direction = "row", gap = GAP }
			rows[#rows + 1] = row
		end
		-- Sized here rather than at build, because how big a square is is a
		-- setting and this is the one function that runs on every change to it.
		-- Ability.Size re-places every region on the square, so it is the whole
		-- of what a resize is.
		Ability.Size(entry.buttons[index], size)
		row[#row + 1] = { frame = entry.buttons[index], width = size, height = size }
	end

	Flow.Arrange(entry.frame, rows)
	ns.BarPlace.Put(entry)
end

--------------------------------------------------------------------------
-- Which slot each square presses
--------------------------------------------------------------------------

-- Hand the header everything the snippet reads, then let the client drive it.
-- Returns false when this client has no state driver, which is the state
-- Bars.CanPage reports and Bars.Page then covers from Lua.
local function DrivePages(entry)
	local header = entry.header
	if not entry.pages or type(header.Execute) ~= "function"
		or type(RegisterStateDriver) ~= "function" then
		return false
	end

	header:SetAttribute("count", PER_BAR)
	for index = 1, ns.Layout.PAGES do
		header:SetAttribute("page" .. index, entry.pages[index])
	end
	for index = 1, PER_BAR do
		header:SetFrameRef("button" .. index, entry.buttons[index])
	end
	header:SetAttribute("_onstate-page", PAGE_SNIPPET)

	return (pcall(RegisterStateDriver, header, "page", PAGE_MACRO))
end

-- Point every square at the slot a press should reach right now.
--
-- Written from Lua as well as from the snippet on purpose. The snippet is the
-- only thing that can do this in combat and it is the one piece of the file
-- nothing installed here proves works. This is what makes the bar right the
-- rest of the time, and on a client with no state driver it is the whole of
-- what makes it right at all.
function Bars.Page()
	if InCombatLockdown() then
		return false
	end

	for index = 1, #order do
		local entry = order[index]
		local base = entry.base
		if entry.pages then
			local form = GetShapeshiftForm and GetShapeshiftForm() or 0
			base = entry.pages[form] or entry.pages[1] or base
		end
		for slot = 1, PER_BAR do
			entry.buttons[slot]:SetAttribute("action", base + slot - 1)
		end
	end
	return true
end

-- How many keys the clone is holding. A count rather than a boolean, because
-- "the keys work" and "some of the keys work" are different bugs.
function Bars.Keys()
	return keysHeld
end

function Bars.CanPage()
	return paging == true
end

--------------------------------------------------------------------------
-- The keys
--
-- Override bindings, never real ones, for the reason Charge/Icon.lua and
-- Marking/Keys.lua both state: SetBindingClick writes into the live binding
-- set, and the next SaveBindings, which the Key Bindings panel calls when you
-- press Okay, makes that permanent and loses whatever the key was carrying.
-- An override sits on top and is dropped by one call.
--
-- Every override is cleared before any is set, so a rebind cannot leave the old
-- key still pressing a square.
--------------------------------------------------------------------------

local function ClaimKey(owner, key, name)
	if type(SetOverrideBindingClick) ~= "function" or not key or key == "" then
		return false
	end
	if not pcall(SetOverrideBindingClick, owner, true, key, name, "LeftButton") then
		return false
	end

	-- Read the layer back rather than believe the call. A client that accepts
	-- the call and does nothing with it leaves no other trace, and the whole
	-- feature is worth nothing if the keys do not arrive.
	if type(GetBindingAction) == "function" then
		local ok, action = pcall(GetBindingAction, key, true)
		if ok and type(action) == "string" and action ~= "" then
			proven = action == ("CLICK %s:LeftButton"):format(name)
		end
	end
	return true
end

-- Walked over everything ever built rather than over what is up, because a bar
-- you have just unticked is exactly the bar whose keys have to go back and is
-- exactly the bar that is no longer in `order`.
local function DropKeys()
	if type(ClearOverrideBindings) ~= "function" then
		return
	end
	for index = 1, #Which.PLAN do
		local entry = built[Which.PLAN[index].key]
		if entry then
			pcall(ClearOverrideBindings, entry.header)
		end
	end
end

-- Returns false when combat deferred the work, so the caller can say so.
function Bars.ApplyBindings()
	if #order == 0 then
		return true
	end
	if InCombatLockdown() then
		pending = true
		return false
	end
	-- SetOverrideBindingClick fires UPDATE_BINDINGS, which is the event that
	-- calls this function. Without the latch the first key would set the second
	-- pass running and the client would recurse until it gave up.
	if binding then
		return true
	end
	binding = true

	DropKeys()
	local claimed = 0

	for index = 1, #order do
		local entry = order[index]
		for slot = 1, PER_BAR do
			local w = entry.buttons[slot]
			local command = entry.def.command:format(slot)
			local first, second = KeysFor(command)
			local lent = Lent(command)
			if first ~= lent and ClaimKey(entry.header, first, w:GetName()) then
				claimed = claimed + 1
			end
			if second ~= lent and ClaimKey(entry.header, second, w:GetName()) then
				claimed = claimed + 1
			end
			-- The primary key is the one drawn, because two strings in a seven
			-- pixel corner is one string nobody can read. A key lent to the
			-- mouseover part is drawn when it is the only one, because it
			-- still presses this square.
			Ability.Bind(w, Bars.Short(first or lent))
		end
	end

	keysHeld = claimed
	binding = nil
	return true
end


-- Every Blizzard button the bars this file cloned are standing in for. Built
-- on demand rather than held, because it is asked for once when the clone goes
-- up and never on a tick.
local function Covered()
	local names = {}
	for index = 1, #order do
		local def = order[index].def
		for slot = 1, PER_BAR do
			names[#names + 1] = def.buttons:format(slot)
		end
	end
	return names
end

-- Forwarded rather than reached for directly, so the panel, the status line and
-- the harness all ask the bars how many of Blizzard's buttons are down and none
-- of them has to know which file did it. The three below forward to
-- Buttons/Placing.lua for the same reason: `order` is this file's, and a caller
-- that had to be handed it would be a caller that could hold a stale one.
function Bars.Hidden()
	return ns.TheirBars.Count()
end

function Bars.ApplyLock()
	ns.BarPlace.Lock(order)
end

-- The accent rim on whichever bar the options page is showing. Forwarded for
-- the reason the lock above is: `order` is this file's.
function Bars.ApplyMark()
	ns.BarLook.Mark(order)
end

-- Whether one bar is up right now, which is a different question from whether
-- it is wanted: a bar you have ticked is not standing until an apply has run.
function Bars.Standing(def)
	for index = 1, #order do
		if order[index].def == def then
			return true
		end
	end
	return false
end

-- One bar's middle put on the middle of the screen, in one axis, leaving the
-- other where it is. Buttons/Placing.lua does the arithmetic; this finds the
-- bar and answers for combat.
--
-- Refused in lockdown for the reason the drag is: the bar carries twelve secure
-- buttons and moving what they hang off in a fight is not something this addon
-- does. Nothing is written either, so a refusal leaves the bar exactly as it
-- was rather than saving a position it did not take.
function Bars.Centre(def, axis)
	if not Bars.Standing(def) then
		return false, "that bar is not up"
	end
	if InCombatLockdown() then
		return false, "combat"
	end
	ns.BarPlace.Centre(built[def.key], axis)
	return true
end

function Bars.Where()
	return ns.BarPlace.Where(order)
end

function Bars.ResetPlacing()
	return ns.BarPlace.Reset(order)
end

-- Every standing bar drawn again to what Buttons/Look.lua now says: the twelve
-- folded into their rows, the ground under them repainted, and the client told
-- again when each of them is allowed on the screen.
--
-- Refused in lockdown for the reason every other entry point in this file is.
-- Laying a bar out moves twelve secure buttons, and a state driver is not
-- something this addon registers in combat either. It comes back at
-- PLAYER_REGEN_ENABLED with the rest of the deferred work.
function Bars.Restyle()
	if InCombatLockdown() then
		pending = true
		return false
	end
	for index = 1, #order do
		local entry = order[index]
		Arrange(entry)
		ns.BarLook.Paint(entry)
		ns.BarLook.Watch(entry)
	end
	-- A bar the client has just taken off the screen must not leave a drag
	-- handle floating where it was.
	ns.BarPlace.Lock(order)
	ns.BarLook.Mark(order)
	return true
end

--------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------

-- Build whatever is out there and is not built yet.
--
-- Run on every apply, because discovery is a race this used to lose. At
-- PLAYER_LOGIN bar 1 answers and every other bar is still hidden, so a build
-- taken there cloned bar 1 alone; the old guard then refused to look again on
-- the grounds that something had been built, and the answer to "which bars do
-- you have" was fixed for the session at the one moment it was wrong.
--
-- Each bar is still built exactly once, which is the rule that mattered. What
-- changed is that a bar seen later gets its twelve squares when it is seen.
local function Build()
	local found = Which.Discover()

	for index = 1, #found do
		local entry = found[index]
		local have = built[entry.def.key]
		if have then
			-- Which.lua is asked again on every pass, so a box ticked in the
			-- panel arrives here as a bar that changes side.
			have.wanted = entry.wanted
			-- The one answer that can arrive late on a bar already standing.
			-- Bar1Bases refuses while the client says you are in no stance,
			-- which is what it says at login, and a bar 1 that came up without
			-- its pages would page from Lua for the rest of the session.
			if have.def.pages and not have.pages and entry.pages then
				have.pages = entry.pages
				if DrivePages(have) then
					paging = true
				end
			end
		elseif entry.wanted then
			-- Nothing is built for a bar you do not want, so a clone of two
			-- bars costs twenty-four secure buttons and not sixty.
			built[entry.def.key] = entry
			BuildBar(entry)
			Arrange(entry)
			if DrivePages(entry) then
				paging = true
			end
		end
	end

	-- What is up, in the plan's own order rather than the order it was built
	-- in. Both lists are emptied rather than replaced, because Bars.All hands
	-- `order` out and a caller holding the old table would be holding a list
	-- that stopped changing.
	--
	-- `squares` is derived from this rather than filled as buttons are made,
	-- so a bar you untick leaves the tick as well as the screen.
	wipe(order)
	wipe(squares)
	wipe(seen)
	for index = 1, #Which.PLAN do
		local entry = built[Which.PLAN[index].key]
		if entry and entry.wanted then
			order[#order + 1] = entry
			for slot = 1, PER_BAR do
				squares[#squares + 1] = entry.buttons[slot]
				-- A record rather than a reused one, because the walk is
				-- rebuilt in the plan's order and a bar unticked shifts every
				-- square below it onto a different index. Sixty small tables on
				-- an apply, and none on a tick.
				seen[#squares] = { dirty = true }
			end
		end
	end
	-- Place.Handle makes every handle hidden, so a bar that arrived while the
	-- frames were unlocked needs telling, and a bar that arrived while its own
	-- page was open needs marking.
	ns.BarPlace.Lock(order)
	ns.BarLook.Mark(order)
end

-- Returns false when combat deferred part of the work.
function Bars.Apply()
	-- The house rule: every entry point tolerates being called before the saved
	-- variables exist.
	if not ns.db then
		return true
	end

	if InCombatLockdown() then
		pending = true
		return false
	end
	pending = nil

	local want = ns.db.actionBars and true or false
	if want then
		Build()
	end

	-- Everything ever built goes out of sight first, and what is wanted comes
	-- back below. A bar you untick keeps its twelve secure buttons, because
	-- secure buttons cannot be destroyed and must never be made twice; what it
	-- loses is the screen, its keys and its claim on Blizzard's buttons, and
	-- that is the whole of what turning a bar off means here.
	for index = 1, #Which.PLAN do
		local entry = built[Which.PLAN[index].key]
		if entry then
			-- The client holds a bar's visibility while a driver is on it, so
			-- the driver is handed back before the frame goes down. Left on, the
			-- next time its macro changed its mind the client would show a bar
			-- this addon had already taken away.
			ns.BarLook.Unwatch(entry)
			entry.frame:Hide()
		end
	end
	DropKeys()

	if not want then
		live = false
		return ns.TheirBars.Show()
	end

	live = #order > 0
	for index = 1, #order do
		local entry = order[index]
		entry.frame:Show()
		-- Shown first and driven second. Registering the driver is what asks
		-- the client to decide, so a bar that is only up while a key is held is
		-- put up here and taken down again by the client on the same pass,
		-- rather than being left up by us until the first time you press one.
		ns.BarLook.Watch(entry)
	end

	-- Exactly the buttons the bars that are up stand over, and every other one
	-- handed back. One call rather than a hide and a show, so a bar that
	-- changed side cannot leave Blizzard's twelve hidden behind nothing.
	local complete = ns.TheirBars.Only(Covered())
	Bars.Page()
	if not Bars.ApplyBindings() then
		complete = false
	end
	Bars.Update()
	-- What a key presses underneath has just changed, from a square to
	-- Blizzard's button or back, and Hover/Cast.lua wrote the old answer into
	-- its macro. Every part that takes a key is run again rather than that one
	-- named, because the question is Core's and so is the list of who asks it.
	ns.Retake()
	return complete
end

--------------------------------------------------------------------------
-- The tick
--
-- One ticker for every square on every bar, on a frame that is never hidden,
-- because a hidden frame's OnUpdate stops and never starts again. Everything
-- below runs against sixty squares ten times a second, so nothing allocates and
-- nothing writes a value already on the widget. check.sh's HOT list holds the
-- tick and everything under it to both.
--
-- What a pass no longer does is ask the client what every square is doing.
-- Reading one square is twelve to sixteen calls, and at five bars that was
-- eight thousand calls a second spent redrawing a bar that had not moved. So an
-- event raises a bit on the squares it could have changed and the pass draws
-- those. That is what Blizzard's own ActionButton does on this client: it
-- carries a stateDirty flag set out of its event handler, applies it at the top
-- of its OnUpdate, and spends the rest of the pass on the range check.
--
-- Three things move with nothing sent to say so, and all three are on the pass.
--
--   Range. One IsActionInRange per square holding an attack, and only while
--   something is targeted, which is the one call Blizzard keeps on its own tick.
--
--   The stack on an item. One GetActionCount per square.
--
--   A reaction window shutting. Buttons/Reaction.lua answers that for the whole
--   bar in one clock read, because a window running out is the one thing on the
--   ladder the client sends nothing at all for.
--
-- A square counting down is drawn on every pass as well. The tenths under ten
-- seconds are a number this addon prints in Lua rather than a swipe the client
-- animates, so a frozen square is a frozen number.
--
-- The slot is read back off the button's own action attribute rather than
-- worked out from the stance again. That attribute is what a press actually
-- reaches, whether Lua wrote it or the secure snippet did, so the square draws
-- what the button does by construction rather than by two pieces of code
-- agreeing.
--------------------------------------------------------------------------

-- Raise the bit on every square, or on the ones pointing at one action slot.
--
-- Nothing is drawn here. The handler says what moved and the next pass draws
-- it, which is at most a tenth of a second later and is the rate the squares
-- were being drawn at anyway. Drawing from the handler instead would put a
-- sixty square repaint inside ACTIONBAR_UPDATE_USABLE, which fires on every
-- point of rage a warrior gains.
--
-- A slot of zero is the client saying it changed something and not which, which
-- is the same reading Blizzard's own button takes off ACTIONBAR_SLOT_CHANGED,
-- and it means every square.
function Bars.Soil(slot)
	if not live then
		return
	end
	if slot == 0 then
		slot = nil
	end
	for index = 1, #squares do
		if not slot or squares[index]:GetAttribute("action") == slot then
			seen[index].dirty = true
		end
	end
end

-- One square drawn from what the client says its slot is doing, and what was
-- found written down so the next pass can tell whether anything moved.
local function Paint(index, w, slot)
	local mark = seen[index]
	local status, start, duration, texture, harmful = ns.Slot.State(slot)
	local count = ns.Slot.Count(slot)
	Ability.Draw(w, texture, status, start, duration, count,
		ns.Slot.Active(slot), ns.Slot.Equipped(slot))
	mark.dirty = nil
	mark.harmful = harmful
	mark.counting = status == "cooldown"
	mark.count = count
end

-- Every square drawn from scratch whatever the bits say. What an apply ends
-- with, because an apply has just changed which slot every square is on.
function Bars.Update()
	if not live then
		return
	end
	for index = 1, #squares do
		local w = squares[index]
		Paint(index, w, w:GetAttribute("action"))
	end
end

function Bars.Tick()
	if not live then
		return
	end
	if ns.Reaction.Moved() then
		Bars.Soil()
	end

	local aiming = ns.Slot.Aiming()
	for index = 1, #squares do
		local w = squares[index]
		local slot = w:GetAttribute("action")
		local mark = seen[index]

		-- Read before the bit is tested, because reading them is what raises
		-- it. Both are compared against what the last pass read rather than
		-- against what was drawn: the ladder can stop above either of them, so
		-- the picture does not say what the answer was.
		if aiming and mark.harmful then
			local out = ns.Slot.Range(slot)
			if out ~= mark.range then
				mark.range = out
				mark.dirty = true
			end
		end
		if ns.Slot.Count(slot) ~= mark.count then
			mark.dirty = true
		end

		if mark.dirty or mark.counting then
			Paint(index, w, slot)
		end
	end
end

function Bars.Count()
	return live and #squares or 0
end

--------------------------------------------------------------------------

function Bars.Describe()
	if not (ns.db and ns.db.actionBars) then
		return "off, your own bars are where they were"
	end
	if #order == 0 then
		if Which.Decided() > 0 then
			return "on, and every bar is unticked, so your own bars are where they were"
		end
		return "on, but no action bar answered, so there was nothing to clone"
	end

	local names = {}
	for index = 1, #order do
		names[#names + 1] = order[index].def.label
	end

	local line = ("%s, %d squares, %d keys taken"):format(
		table.concat(names, ", "), #squares, keysHeld)

	if not ns.Slot.CanRead() then
		line = line .. "; " .. ns.Slot.Describe()
	end
	-- Whether a square can be filled by hand, which is a different question
	-- from whether it can be read and has a different answer. A client that
	-- draws every bar perfectly and refuses every drop is a client where
	-- learning a spell means turning the clone off, and the status line is
	-- where that has to be said. Combat is left out: it clears on its own, and
	-- Buttons/Square.lua does not report it either.
	local canCarry, whyCarry = ns.Layout.CanCarry()
	if not canCarry and whyCarry ~= ns.Layout.BUSY_COMBAT then
		line = line .. "; nothing can be dropped on a square: " .. whyCarry
	end
	if proven == false then
		line = line .. "; this client accepted the keys and did not bind them"
	end
	if pending then
		line = line .. "; the rest follows when combat drops"
	end
	if order[1].def.pages and not paging then
		line = line .. "; no state driver, so bar 1 pages only out of combat"
	end
	local hours = ns.BarLook.Summary(order)
	if hours then
		line = line .. "; " .. hours
	end
	if Which.Decided() > 0 then
		line = line .. ("; %d bar%s picked by hand rather than off your own"):format(
			Which.Decided(), Which.Decided() == 1 and "" or "s")
	end
	return line
end

-- The bars this file built, for the panel and for scripts/harness.lua. Handed
-- out read only, the way ns.Loadouts.All is: nothing outside this file writes an
-- entry, and nothing outside this file knows a square's name.
function Bars.All()
	return order
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")


-- A rescale moves the grid under every adopted frame. On this client that
-- changes the scale and not the numbers, because a square's size is written in
-- units and a unit stays a pixel; on a client with no SetIgnoreParentScale the
-- units are fractions of a pixel and the whole layout has to be run again.
-- Refused in lockdown, because every square is a protected frame.
UI.OnRescale(function()
	if #order == 0 or InCombatLockdown() then
		return
	end
	for index = 1, #order do
		Arrange(order[index])
	end
end)

-- The events a square's picture moves on, none of which says which square.
--
-- Read off Blizzard's own ActionButton on this client rather than guessed at.
-- ACTIONBAR_UPDATE_COOLDOWN, ACTIONBAR_SLOT_CHANGED and UPDATE_SHAPESHIFT_FORM
-- are on the frame every one of their buttons listens to, and
-- ACTIONBAR_UPDATE_STATE, ACTIONBAR_UPDATE_USABLE and PLAYER_TARGET_CHANGED are
-- on the one only a button with something in it listens to. Their newest file
-- has swapped two of those for ACTION_USABLE_CHANGED and
-- ACTION_RANGE_CHECK_UPDATE, which are a subscription per slot rather than a
-- broadcast; the broadcasts are still sent and are what this reads.
--
-- SPELL_UPDATE_USABLE is the same answer arriving at the spell rather than at
-- the slot, and it is here because five of the warrior plan's twelve bar 1 keys
-- are macros: what a macro would cast is resolved to a spell and the rungs above
-- ask about the spell, so the slot's own event is not always the one that fires.
--
-- ACTIONBAR_SLOT_CHANGED is not in this table because it names the slot and is
-- the one event that raises the bit on one square rather than on all of them.
local PAINT = {
	ACTIONBAR_UPDATE_COOLDOWN = true,
	ACTIONBAR_UPDATE_STATE = true,
	ACTIONBAR_UPDATE_USABLE = true,
	SPELL_UPDATE_USABLE = true,
	PLAYER_TARGET_CHANGED = true,
}

events:RegisterEvent("PLAYER_LOGIN")
-- PLAYER_ENTERING_WORLD as well as PLAYER_LOGIN, and it is not belt and braces.
-- The client puts its own bars up and fills in ActionButton1.action on entering
-- the world, which is after login, so login sees a fraction of what is there.
-- Build costs a walk of five names once everything is standing.
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
events:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
events:RegisterEvent("UPDATE_BINDINGS")
-- The three the client repaints its bars on. Nothing here needs them for the
-- squares; they exist so a button we hid that the controller has just shown
-- again goes back out of sight. See the header of Buttons/Blizzard.lua.
events:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
events:RegisterEvent("ACTIONBAR_SHOWGRID")
events:RegisterEvent("ACTIONBAR_HIDEGRID")
-- The six a square's picture moves on. Nothing is drawn from any of them; each
-- raises a bit and the next pass of the tick spends it.
events:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
events:RegisterEvent("ACTIONBAR_UPDATE_STATE")
events:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
events:RegisterEvent("SPELL_UPDATE_USABLE")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		Bars.Apply()
		ns.TheirBars.Recheck()
		-- The ticker lives on this frame, which is never hidden. On a bar it
		-- would stop the moment the bar hid and never come back.
		--
		-- Armed once and then kept, because this branch runs on login and again
		-- on every loading screen after it, and UI.Ticker appends. Three
		-- instance doors in there were four action tickers walking every square
		-- forty times a second, and nothing on screen said so. UI.Ticker refuses
		-- the second one now as well, so the two halves of this cannot drift.
		if not tick then
			tick = ns.UI.Ticker(events, UPDATE_INTERVAL, "action", Bars.Tick)
		end
		return
	end

	if PAINT[event] then
		Bars.Soil()
		return
	end

	if event == "ACTIONBAR_SLOT_CHANGED" then
		Bars.Soil(arg1)
		return
	end

	if event == "UPDATE_BINDINGS" then
		Bars.ApplyBindings()
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		if pending then
			Bars.Apply()
		end
		return
	end

	-- Every event left here is one the client repaints its bars on, so any of
	-- them can have put a hidden button back and any of them can have changed
	-- what a square is pointing at.
	Bars.Soil()
	ns.TheirBars.Recheck()

	-- A stance change and a page change both re-point bar 1. The snippet has
	-- already done it where the state driver came up; this is the client that
	-- had none.
	if not paging then
		Bars.Page()
	end
end)
