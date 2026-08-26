local ADDON, ns = ...

local Bars = {}
ns.Bars = Bars

local UI = ns.UI
local Ability, Flow = UI.Ability, UI.Flow

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
--   Which bars exist. BARS below is what this client can have. What you
--   actually have is read off the frames at build time, so a right bar you
--   never turned on is a bar this file never makes and never hides.
--
-- The geometry is source code and not a setting. This is a personal addon for
-- one person who wants the same interface on every install, so the plan is a
-- table in git exactly the way Layout.BAR1 is, and changing it is an edit and a
-- reload. The one saved setting is the master switch, because a feature with no
-- setting has no status line and no panel row.
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
-- count down rather than jump. Every square is walked on every pass and every
-- write behind it is guarded, so the cost is a read per square.
local UPDATE_INTERVAL = 0.1

-- Twelve is every action bar the client has ever had, and the stride between
-- one bar's slots and the next.
local PER_BAR = 12

-- Stance one, two and three, in the order GetShapeshiftForm counts them, which
-- is also the order Layout.Bar1Bases keys its answer by.
local STANCES = { "battle", "defensive", "berserker" }

--------------------------------------------------------------------------
-- The plan
--------------------------------------------------------------------------

-- 27, and it is not a taste decision. UI.IconSizes answers { 54, 27 } on this
-- client: an icon is stored at 64 texels, the crop that takes the border baked
-- into every one of them off leaves 54, and the client keeps each copy at half
-- the size of the one above. Those two are the only drawn sizes where one
-- stored texel lands on one pixel. 32 and 36, which is what every bar addon
-- ships, are the client blending two copies, and halfway between two of them is
-- the worst place to stand. scripts/harness.lua asserts this number is on that
-- list, so an edit to it cannot quietly go soft.
local SIZE = 27
local GAP = 2
local PAD = 3

-- Every bar this client can have, in draw order.
--
--   buttons   the Blizzard button name the slot is read off and which then gets
--             hidden. Hiding the twelve buttons rather than the frame holding
--             them is deliberate: bar 1's buttons live on MainMenuBarArtFrame
--             along with the micro menu and the bag bar, and Artwork.lua
--             already carries the note about what hiding that frame costs.
--   command   the binding command its keys are saved under
--   frame     the Blizzard frame whose IsShown answers whether the bar is on at
--             all. nil for bar 1, which is always on
--   pages     bar 1 alone, which the client re-points at a different twelve
--             slots in each stance
--
-- The rest is geometry: how many columns the twelve break into, and where the
-- bar's corner lands on UIParent. Those offsets are in the bar's own units, and
-- every bar goes on the pixel grid, so they are whole screen pixels and mean
-- the same thing on a 1080p panel as on a 4K one.
local BARS = {
	{ key = "bar1", label = "bar 1", pages = true,
		buttons = "ActionButton%d", command = "ACTIONBUTTON%d",
		columns = 12, point = "BOTTOM", to = "BOTTOM", x = 0, y = 8 },

	{ key = "bottomleft", label = "bottom left bar",
		buttons = "MultiBarBottomLeftButton%d", command = "MULTIACTIONBAR1BUTTON%d",
		frame = "MultiBarBottomLeft",
		columns = 12, point = "BOTTOM", to = "BOTTOM", x = 0, y = 44 },

	{ key = "bottomright", label = "bottom right bar",
		buttons = "MultiBarBottomRightButton%d", command = "MULTIACTIONBAR2BUTTON%d",
		frame = "MultiBarBottomRight",
		columns = 12, point = "BOTTOM", to = "BOTTOM", x = 0, y = 80 },

	-- MultiBarRight is the client's "right bar" and MultiBarLeft is "right bar
	-- 2", which sits to its left. The names are the wrong way round and have
	-- been since 2005; the command numbers are what the binding set actually
	-- carries and those are right.
	{ key = "right", label = "right bar",
		buttons = "MultiBarRightButton%d", command = "MULTIACTIONBAR3BUTTON%d",
		frame = "MultiBarRight",
		columns = 2, point = "RIGHT", to = "RIGHT", x = -8, y = 0 },

	{ key = "right2", label = "right bar 2",
		buttons = "MultiBarLeftButton%d", command = "MULTIACTIONBAR4BUTTON%d",
		frame = "MultiBarLeft",
		columns = 2, point = "RIGHT", to = "RIGHT", x = -73, y = 0 },
}

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------

local order = {}       -- one entry per cloned bar, in draw order
local squares = {}     -- every square on every bar, flat, walked by the tick
local pool = 0         -- next name out of the button pool

local live = false     -- the squares are up and the tick should draw them
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

--------------------------------------------------------------------------
-- What is out there
--------------------------------------------------------------------------

-- Read off the bar frame rather than off its buttons, and read once. After the
-- clone is up this file has hidden every one of those buttons, so their own
-- IsShown is its own answer coming back; the frame holding them is what
-- MultiActionBar_Update actually toggles and is the only honest source left.
--
-- A bar turned on after the clone was built is not picked up, because a bar is
-- twelve secure buttons and secure buttons are made once at load in every part
-- of this addon that has them. Bars.Describe says so.
local function Discover()
	local found = {}
	for index = 1, #BARS do
		local def = BARS[index]
		local holder = def.frame and _G[def.frame]
		local on = def.frame == nil or (holder and holder:IsShown()) or false
		local base = on and ns.Layout.SlotOf(def.buttons:format(1)) or nil
		if base then
			local entry = { def = def, base = base }
			if def.pages then
				-- nil where this client does not page bar 1 by stance, which is
				-- every non-warrior and is a state Layout already reports.
				entry.pages = ns.Layout.Bar1Bases()
			end
			found[#found + 1] = entry
		end
	end
	return found
end

-- Both keys the binding set holds for one command. Two, because the client
-- allows a primary and a secondary and losing the secondary is losing a key the
-- player set on purpose.
local function KeysFor(command, index)
	if type(GetBindingKey) ~= "function" then
		return nil
	end
	local ok, first, second = pcall(GetBindingKey, command:format(index))
	if not ok then
		return nil
	end
	return first, second
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
	bar:SetFrameStrata("MEDIUM")
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

	entry.buttons = {}
	for index = 1, PER_BAR do
		pool = pool + 1
		local w = Ability.New(header, ("WarriorKitBarButton%d"):format(pool),
			"SecureActionButtonTemplate", Ability.QUIET)
		Ability.Size(w, SIZE)
		-- The up edge, which is what this client's own action buttons register
		-- in ActionButton_OnLoad. Casting on the down edge arrived with a
		-- later expansion and its CVar, and a button registered only for
		-- AnyDown on 2.5.6 draws perfectly and does nothing at all when you
		-- click it.
		--
		-- This said AnyDown, on the grounds that the charge button registers
		-- it. That is not the precedent it looks like: the charge button calls
		-- EnableMouse(false) on itself and says in its own note that the two
		-- ways to press it are the bound key and /click. Copying a click
		-- registration off a button that refuses the mouse is how a bar full
		-- of squares ended up inert.
		w:RegisterForClicks("AnyUp")
		w:SetAttribute("type", "action")
		ns.Square.Handle(w)
		entry.buttons[index] = w
		squares[#squares + 1] = w
	end

	ns.BarPlace.Handle(entry)
end

-- Lay one bar out and put it where the plan says. Called at build and again on
-- a rescale, never on a tick.
--
-- The rows are written out rather than left to Flow's wrap, because wrapping
-- needs a width to wrap against and a width here would be the same arithmetic
-- stated a second time, in a second place, ready to disagree.
local function Arrange(entry)
	local def = entry.def
	local rows = { direction = "column", gap = GAP, pad = PAD }
	local row

	for index = 1, PER_BAR do
		if (index - 1) % def.columns == 0 then
			row = { direction = "row", gap = GAP }
			rows[#rows + 1] = row
		end
		row[#row + 1] = { frame = entry.buttons[index], width = SIZE, height = SIZE }
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
	for index = 1, #STANCES do
		header:SetAttribute("page" .. index, entry.pages[STANCES[index]])
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
			base = entry.pages[STANCES[form] or ""] or entry.pages.battle or base
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

local function DropKeys()
	if type(ClearOverrideBindings) ~= "function" then
		return
	end
	for index = 1, #order do
		pcall(ClearOverrideBindings, order[index].header)
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
			local first, second = KeysFor(entry.def.command, slot)
			if ClaimKey(entry.header, first, w:GetName()) then
				claimed = claimed + 1
			end
			if ClaimKey(entry.header, second, w:GetName()) then
				claimed = claimed + 1
			end
			-- The primary key is the one drawn, because two strings in a seven
			-- pixel corner is one string nobody can read.
			Ability.Bind(w, Bars.Short(first))
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

function Bars.Where()
	return ns.BarPlace.Where(order)
end

function Bars.ResetPlacing()
	return ns.BarPlace.Reset(order)
end

--------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------

local function Build()
	order = Discover()
	for index = 1, #order do
		local entry = order[index]
		BuildBar(entry)
		Arrange(entry)
		if DrivePages(entry) then
			paging = true
		end
	end
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
	if want and #order == 0 then
		Build()
	end

	if not want then
		live = false
		for index = 1, #order do
			order[index].frame:Hide()
		end
		DropKeys()
		return ns.TheirBars.Show()
	end

	live = #order > 0
	for index = 1, #order do
		order[index].frame:Show()
	end

	local complete = ns.TheirBars.Hide(Covered())
	Bars.Page()
	if not Bars.ApplyBindings() then
		complete = false
	end
	Bars.Update()
	return complete
end

--------------------------------------------------------------------------
-- The tick
--
-- One ticker for every square on every bar, on a frame that is never hidden,
-- because a hidden frame's OnUpdate stops and never starts again. Everything
-- below runs sixty times a pass at ten passes a second, so nothing allocates
-- and nothing writes a value already on the widget. check.sh's HOT list holds
-- Bars.Update to both.
--
-- The slot is read back off the button's own action attribute rather than
-- worked out from the stance again. That attribute is what a press actually
-- reaches, whether Lua wrote it or the secure snippet did, so the square draws
-- what the button does by construction rather than by two pieces of code
-- agreeing.
--------------------------------------------------------------------------

function Bars.Update()
	if not live then
		return
	end
	for index = 1, #squares do
		local w = squares[index]
		local slot = w:GetAttribute("action")
		local status, start, duration = ns.Slot.State(slot)
		Ability.Draw(w, ns.Slot.Texture(slot), status, start, duration,
			ns.Slot.Count(slot), ns.Slot.Active(slot), ns.Slot.Equipped(slot))
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
	if proven == false then
		line = line .. "; this client accepted the keys and did not bind them"
	end
	if pending then
		line = line .. "; the rest follows when combat drops"
	end
	if order[1].def.pages and not paging then
		line = line .. "; no state driver, so bar 1 pages only out of combat"
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

local elapsed = 0
local function OnUpdate(_, delta)
	elapsed = elapsed + delta
	if elapsed >= UPDATE_INTERVAL then
		elapsed = 0
		ns.Perf.Start("action")
		Bars.Update()
		ns.Perf.Stop("action")
	end
end

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
		local entry = order[index]
		for slot = 1, PER_BAR do
			Ability.Size(entry.buttons[slot], SIZE)
		end
		Arrange(entry)
	end
end)

events:RegisterEvent("PLAYER_LOGIN")
-- PLAYER_ENTERING_WORLD as well as PLAYER_LOGIN, and it is not belt and braces.
-- Discovery reads ActionButton1.action, and the client's own bar controller
-- fills that field in on entering the world, which is after login. A build
-- taken at login alone would find nothing on a cold start and report having
-- nothing to clone. Bars.Apply only builds while nothing has been built, so a
-- second call after a successful one costs a comparison.
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
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		Bars.Apply()
		ns.TheirBars.Recheck()
		-- The ticker lives on this frame, which is never hidden. On a bar it
		-- would stop the moment the bar hid and never come back.
		events:SetScript("OnUpdate", OnUpdate)
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
	-- them can have put a hidden button back.
	ns.TheirBars.Recheck()

	-- A stance change and a page change both re-point bar 1. The snippet has
	-- already done it where the state driver came up; this is the client that
	-- had none.
	if not paging then
		Bars.Page()
	end
end)
