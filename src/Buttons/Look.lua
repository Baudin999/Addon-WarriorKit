local ADDON, ns = ...

local Look = {}
ns.BarLook = Look

local UI = ns.UI

--------------------------------------------------------------------------
-- What one bar looks like, and when it is up
--
-- The third question about a cloned bar. Buttons/Which.lua answers which bars
-- there are and which of them you want, Buttons/Placing.lua answers where one
-- goes, and this answers what shape it is, what colour it is drawn in and
-- whether it is on the screen at all right now.
--
-- Its own file for the reason those two are theirs. Buttons/Bars.lua is what a
-- bar is made of: twelve secure buttons, the slots they press, the keys they
-- answer to and the client's own buttons hidden behind them. None of that
-- changes when you ask for three rows instead of one, and none of what is in
-- here knows what an action slot is.
--
-- Every setting is per bar and every one of them has a default that is not a
-- setting. The shape's default is the plan's `columns` in Which.lua, the
-- colour's is the window colour every other surface in the addon is painted
-- in, and both visibility answers default to no. So a bar nobody has touched
-- carries no record at all, `ns.db.barLook` is empty on a fresh install, and
-- `actionbars plain` is a deletion rather than a write. That is the shape
-- Which.lua already uses for the tick boxes and the argument is the same one:
-- the shipping state travels with a clone of the repo, and a saved variable
-- that merely restates it is a saved variable that can drift from it.
--
-- Two of the five cannot be done from Lua at all, which is why they are here
-- rather than in a switch somewhere.
--
--   Hiding a bar in combat. Everything inside a bar is a secure button, and a
--   frame with one of those under it cannot be shown or hidden while the
--   client is in lockdown. Combat starting is exactly the moment you would
--   want to, so the only path is a visibility state driver: the client
--   evaluates the macro conditions itself, inside the restricted environment,
--   and does the hiding on its own account. Same machinery as the page driver
--   in Bars.lua and the charge key's binder, and probed the same way, because
--   nothing installed here proves it is on 2.5.6.
--
--   Showing a bar while a key is held. The same driver, on `[mod:shift]`
--   rather than on `[combat]`. A key held is not an event Lua is told about
--   often enough to drive a frame off, and hiding on the up edge would be a
--   protected call again the moment you were in a fight.
--------------------------------------------------------------------------

-- Twelve, the same twelve Buttons/Bars.lua lays out. Written here as well
-- because this file loads first and the shape arithmetic is the whole of what
-- it does: the rows below are the ways twelve breaks into a rectangle.
local SLOTS = 12

-- The shapes twelve buttons make. Every one of these divides twelve, because a
-- last row with a gap on the end of it is not a bar, it is a bar and a stump.
-- One row is the bar every client ships, twelve rows is the column down the
-- side of the screen, and the four between them are the same twelve buttons
-- folded.
Look.ROWS = { 1, 2, 3, 4, 6, 12 }

-- Ninety five rather than the ninety seven the window colour carries, because
-- the opacity control is in fives and a stop the panel cannot reach is a
-- number nobody can put back. Two hundredths of an alpha on a background is
-- not a look anybody has ever seen.
local DEFAULT_ALPHA = 95

-- What a bar can be painted. Eight, named rather than mixed, for the reason the
-- geometry in Which.lua is source code: this is an addon for one person who
-- wants the same interface on every install, and a colour you dialled in with
-- three sliders is a colour that lives in one WTF folder.
--
-- The first two are the theme's own, so a bar left alone matches every other
-- surface the addon paints. The six after them are deliberately dark and
-- deliberately flat: this is the ground under twelve pieces of Blizzard icon
-- art, and anything with saturation in it fights the art rather than holding
-- it.
Look.PALETTE = {
	{ key = "window", label = "window", color = UI.Color.window },
	{ key = "black", label = "black", color = { 0, 0, 0 } },
	{ key = "slate", label = "slate", color = UI.Color.control },
	{ key = "steel", label = "steel", color = UI.Color.edge },
	{ key = "blue", label = "blue", color = { 0.07, 0.11, 0.20 } },
	{ key = "green", label = "green", color = { 0.06, 0.15, 0.09 } },
	{ key = "red", label = "red", color = { 0.19, 0.06, 0.06 } },
	{ key = "purple", label = "purple", color = { 0.14, 0.08, 0.20 } },
}

-- Which key holds a bar on the screen. `none` is the shipping answer and means
-- the bar is up on its own account; the other three are the modifiers the
-- client's macro conditionals name, which is what the driver below is written
-- in. There is no fourth: `[mod:shift]` and its two siblings are the whole of
-- what a state driver can ask about the keyboard.
Look.KEYS = {
	{ key = "none", label = "no key" },
	{ key = "shift", label = "shift" },
	{ key = "ctrl", label = "ctrl" },
	{ key = "alt", label = "alt" },
}

--------------------------------------------------------------------------
-- The record
--------------------------------------------------------------------------

-- One bar's decisions, or nil where it has none. `make` builds one, and only a
-- setter passes it, so reading a bar never writes to the saved variables.
local function Record(def, make)
	if not (ns.db and ns.db.barLook) then
		return nil
	end
	local record = ns.db.barLook[def.key]
	if not record and make then
		record = {}
		ns.db.barLook[def.key] = record
	end
	return record
end

local function Field(def, name)
	local record = Record(def)
	return record and record[name]
end

-- One field written, or dropped where it is the default again.
--
-- Dropped rather than stored, so "no record" and "the plan" stay the same
-- sentence. Stored, a bar you folded and unfolded would carry a row count that
-- says what the plan says, `Decided` would count it, and the button that puts
-- every bar back to plain would offer to undo nothing. A record with nothing
-- left in it goes with it, for the same reason.
local function Write(def, name, value, fallback)
	local record = Record(def, value ~= fallback)
	if not record then
		return ns.db ~= nil and ns.db.barLook ~= nil
	end
	record[name] = value ~= fallback and value or nil
	if next(record) == nil then
		ns.db.barLook[def.key] = nil
	end
	return true
end

--------------------------------------------------------------------------
-- The shape
--------------------------------------------------------------------------

-- How many rows the twelve are laid out in. The plan's own columns are the
-- default, so bar 1 ships as one row of twelve and the two side bars as six
-- rows of two, which is what the client draws them as.
function Look.Rows(def)
	return Field(def, "rows") or (SLOTS / def.columns)
end

function Look.Columns(def)
	return SLOTS / Look.Rows(def)
end

-- Whether a row count is one of the six. Not a clamp: a number that is not a
-- shape has to be refused where it was typed, because rounding 5 to 6 quietly
-- is how a macro comes to say something it does not do.
function Look.IsShape(rows)
	for index = 1, #Look.ROWS do
		if Look.ROWS[index] == rows then
			return true
		end
	end
	return false
end

function Look.SetRows(def, rows)
	if not Look.IsShape(rows) then
		return false
	end
	return Write(def, "rows", rows, SLOTS / def.columns)
end

-- The panel's stepper counts in ones and only six of the twelve numbers it can
-- reach are a shape, so the direction of travel is what decides rather than
-- which number was landed on. Up takes the next shape above the one you are
-- standing in, down takes the next below. Without that, +1 from four lands on
-- five, five snaps to the nearest, and the nearest is four again: a control
-- that does nothing on every second press.
function Look.StepRows(def, value)
	local current = Look.Rows(def)
	local rows = current
	if value > current then
		for index = 1, #Look.ROWS do
			if Look.ROWS[index] > current then
				rows = Look.ROWS[index]
				break
			end
		end
	elseif value < current then
		for index = #Look.ROWS, 1, -1 do
			if Look.ROWS[index] < current then
				rows = Look.ROWS[index]
				break
			end
		end
	end
	return Look.SetRows(def, rows)
end

--------------------------------------------------------------------------
-- The paint
--------------------------------------------------------------------------

function Look.Color(def)
	return Field(def, "color") or Look.PALETTE[1].key
end

-- The three components that colour name stands for, and the window colour for
-- a name that is not in the palette, which is what a saved variable written by
-- an older version of this file would carry.
function Look.Tint(def)
	local wanted = Look.Color(def)
	for index = 1, #Look.PALETTE do
		if Look.PALETTE[index].key == wanted then
			return Look.PALETTE[index].color
		end
	end
	return Look.PALETTE[1].color
end

function Look.SetColor(def, key)
	for index = 1, #Look.PALETTE do
		if Look.PALETTE[index].key == key then
			return Write(def, "color", key, Look.PALETTE[1].key)
		end
	end
	return false
end

function Look.Alpha(def)
	return Field(def, "alpha") or DEFAULT_ALPHA
end

function Look.SetAlpha(def, alpha)
	if alpha < UI.ALPHA_LOW or alpha > UI.ALPHA_HIGH then
		return false
	end
	return Write(def, "alpha", alpha, DEFAULT_ALPHA)
end

-- Paint one built bar with what the two above say.
--
-- The hairline follows the background, which is Feeds/Stream.lua's rule and is
-- right for the same reason: at nothing the player has asked for squares over
-- the world, and a rectangle of hairline round nothing is a window frame with
-- no window in it.
function Look.Paint(entry)
	local frame = entry.frame
	if not (frame and frame.bg) then
		return false
	end
	local color = Look.Tint(entry.def)
	local alpha = Look.Alpha(entry.def) / 100
	frame.bg:SetColorTexture(color[1], color[2], color[3], alpha)
	if frame.edges then
		for index = 1, 4 do
			frame.edges[index]:SetAlpha(alpha > 0 and 1 or 0)
		end
	end
	return true
end

--------------------------------------------------------------------------
-- When it is up
--------------------------------------------------------------------------

function Look.Combat(def)
	return Field(def, "combat") and true or false
end

function Look.SetCombat(def, value)
	return Write(def, "combat", value and true or false, false)
end

function Look.Key(def)
	return Field(def, "key") or Look.KEYS[1].key
end

function Look.KeyLabel(def)
	local wanted = Look.Key(def)
	for index = 1, #Look.KEYS do
		if Look.KEYS[index].key == wanted then
			return Look.KEYS[index].label
		end
	end
	return Look.KEYS[1].label
end

function Look.SetKey(def, key)
	for index = 1, #Look.KEYS do
		if Look.KEYS[index].key == key then
			return Write(def, "key", key, Look.KEYS[1].key)
		end
	end
	return false
end

-- The macro conditions the client evaluates for itself, or nil where the bar is
-- simply up.
--
-- A key beats the combat switch rather than being read alongside it, and that
-- is a decision rather than a shortcut. A bar you hold a key for is off unless
-- you are holding the key, in a fight or out of one, so there is nothing left
-- for a combat rule to decide: `[mod:shift] show; [combat] hide; show` would
-- mean a bar that is up all the time except in combat, which is the other
-- setting wearing this one's name.
function Look.Visibility(def)
	local key = Look.Key(def)
	if key ~= Look.KEYS[1].key then
		return ("[mod:%s] show; hide"):format(key)
	end
	if Look.Combat(def) then
		return "[combat] hide; show"
	end
	return nil
end

-- Whether this client can hide a bar on its own account at all. Probed rather
-- than assumed, the way Bars.lua probes the page driver: on a client with no
-- state driver a bar is simply always up, and Describe says so rather than the
-- two switches quietly doing nothing.
function Look.CanDrive()
	return type(RegisterStateDriver) == "function"
		and type(UnregisterStateDriver) == "function"
end

function Look.Unwatch(entry)
	if entry.watching and Look.CanDrive() then
		pcall(UnregisterStateDriver, entry.frame, "visibility")
	end
	entry.watching = nil
end

-- Hand one bar's visibility to the client, or take it back. Returns the macro
-- that is now driving it, or nil where nothing is.
--
-- Always through Unwatch first, because a driver registered twice on one frame
-- is two answers to the same question and the client keeps both.
function Look.Watch(entry)
	Look.Unwatch(entry)
	local macro = Look.Visibility(entry.def)
	if not macro or not Look.CanDrive() then
		return nil
	end
	if not pcall(RegisterStateDriver, entry.frame, "visibility", macro) then
		return nil
	end
	entry.watching = macro
	return macro
end

--------------------------------------------------------------------------
-- What has been decided
--------------------------------------------------------------------------

-- How many bars carry a look of their own rather than the plan's.
function Look.Decided()
	local count = 0
	if ns.db and ns.db.barLook then
		for _ in pairs(ns.db.barLook) do
			count = count + 1
		end
	end
	return count
end

-- Drop every one of them, so all five bars are the plan again. The counterpart
-- of Which.Follow, and a deletion for the same reason.
function Look.Plain()
	if not (ns.db and ns.db.barLook) then
		return 0
	end
	local dropped = 0
	for key in pairs(ns.db.barLook) do
		ns.db.barLook[key] = nil
		dropped = dropped + 1
	end
	return dropped
end

-- The palette and the modifiers as a typed list, for the two slash words that
-- refuse a value. Built rather than written out, because a list in a message
-- that does not match the table above is a message that lies.
function Look.Colours()
	local names = {}
	for index = 1, #Look.PALETTE do
		names[index] = Look.PALETTE[index].key
	end
	return table.concat(names, ", ")
end

function Look.Keys()
	local names = {}
	for index = 1, #Look.KEYS do
		names[index] = Look.KEYS[index].key
	end
	return table.concat(names, ", ")
end

-- Which bar a typed word means: the plan's own key, or the label a tab in the
-- panel carries. Both, because `actionbars rows bottomleft 3` is what a macro
-- says and "bottom left" is what the panel calls it.
function Look.Find(word)
	if type(word) ~= "string" or word == "" then
		return nil
	end
	local wanted = word:lower()
	for index = 1, #ns.WhichBars.PLAN do
		local def = ns.WhichBars.PLAN[index]
		if def.key:lower() == wanted or def.tab:lower() == wanted
			or def.label:lower() == wanted then
			return def
		end
	end
	return nil
end

-- What shape one bar is, in a phrase. One of the two readouts on the panel's
-- page and the first line of the tooltip on a bar's drag handle.
function Look.Shape(def)
	local rows = Look.Rows(def)
	return ("%d row%s of %d, %s at %d%%"):format(rows, rows == 1 and "" or "s",
		Look.Columns(def), Look.Color(def), Look.Alpha(def))
end

-- And when it is on the screen, which is the other readout and is a different
-- question with a different answer. Split because a reading on that page is one
-- line that never wraps, and because the two are set by different controls.
function Look.Hours(def)
	local key = Look.Key(def)
	local line = "always up"
	local driven = true
	if key ~= Look.KEYS[1].key then
		line = ("up only while %s is held"):format(key)
	elseif Look.Combat(def) then
		line = "down in combat"
	else
		driven = false
	end
	if driven and not Look.CanDrive() then
		line = line .. ", except this client cannot, so it stays up"
	end
	return line
end

-- The same across every bar that is standing, for /wk status and the panel's
-- one line on the clone. nil where none of them has been given hours, which is
-- the shipping state and the common one.
function Look.Summary(order)
	local keyed, hidden = 0, 0
	for index = 1, #order do
		local def = order[index].def
		if Look.Key(def) ~= Look.KEYS[1].key then
			keyed = keyed + 1
		elseif Look.Combat(def) then
			hidden = hidden + 1
		end
	end
	if keyed == 0 and hidden == 0 then
		return nil
	end
	local parts = {}
	if keyed > 0 then
		parts[#parts + 1] = ("%d wait%s on a key"):format(keyed, keyed == 1 and "s" or "")
	end
	if hidden > 0 then
		parts[#parts + 1] = ("%d go%s down in combat"):format(hidden, hidden == 1 and "es" or "")
	end
	if not Look.CanDrive() then
		parts[#parts + 1] = "and this client has no state driver, so neither happens"
	end
	return table.concat(parts, ", ")
end

--------------------------------------------------------------------------
-- Which bar the panel is showing, said on the screen
--
-- A tab strip that says "bottom left bar" names a bar you then have to find by
-- counting, and the two on the right of the screen are a pair of identical
-- columns. So while the options window is open, whichever bar its strip is on
-- wears an accent rim, in the colour the selected tab is marked in, so the two
-- read as one thing.
--
-- Outside the bar rather than on it. A rim drawn on the bar's own edge covers
-- the hairline already there and reads as the bar having changed colour, which
-- is the row above pretending to have moved.
--
-- It goes down with the window. A mark that outlived the panel would be an
-- accent rectangle round one bar for the rest of the session with nothing on
-- screen to say why, and the buttons feature's `showing` hook is what takes it
-- off.
--------------------------------------------------------------------------

-- Two physical pixels and two out from the bar. Every other line this addon
-- draws is a hairline, which is right for a border and wrong for a highlight: a
-- highlight you have to look for is not one.
local RIM, RIM_GAP = 2, 2

local marking = false

local function Rim(entry)
	if entry.rim then
		return entry.rim
	end
	local accent = UI.Color.accent
	local rim = CreateFrame("Frame", nil, entry.frame)
	rim:SetPoint("TOPLEFT", -RIM_GAP, RIM_GAP)
	rim:SetPoint("BOTTOMRIGHT", RIM_GAP, -RIM_GAP)
	rim.edges = ns.Outline(rim, accent[1], accent[2], accent[3], 1)
	ns.EdgeSize(rim.edges, ns.Pixel(rim) * RIM)
	rim:Hide()
	entry.rim = rim
	return rim
end

-- Whether the window that does the marking is up.
function Look.Marking(open)
	marking = open and true or false
	return marking
end

function Look.Marked()
	return marking
end

-- The rim on the bar the page is on and off every other one. Called when the
-- window opens or closes, when the strip picks another bar, and on every apply,
-- because a bar built while the window was open has to arrive marked or not on
-- its own account.
--
-- Built on demand, so a player who never opens that page never pays for five
-- frames, and asked for at all only where there is one already or one is
-- wanted.
function Look.Mark(order)
	local chosen = Look.Chosen()
	for index = 1, #order do
		local entry = order[index]
		local wanted = marking and entry.def == chosen
		if wanted or entry.rim then
			Rim(entry):SetShown(wanted)
		end
	end
end

--------------------------------------------------------------------------
-- Which bar the panel is showing
--
-- Not a saved setting. It is which tab is in front while the window is open,
-- which is the same thing ns.People.Shown answers and is kept the same way.
--------------------------------------------------------------------------

local shown = 1

function Look.Shown()
	if shown > #ns.WhichBars.PLAN then
		shown = 1
	end
	return shown
end

function Look.Show(index)
	if index >= 1 and index <= #ns.WhichBars.PLAN then
		shown = index
	end
	return shown
end

function Look.Chosen()
	return ns.WhichBars.PLAN[Look.Shown()]
end
