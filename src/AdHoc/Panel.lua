local ADDON, ns = ...

local Panel = {}
ns.AdHocPanel = Panel

--------------------------------------------------------------------------
-- Designing a bar, on the page
--
-- One bar at a time, picked off a strip of tabs with a plus on the end, the
-- way the loadout page picks a loadout. Under the strip: the name, the key,
-- and the bar itself drawn as a line of squares you drop things onto, with an
-- empty square on the end for the next one. Drag a spell out of the book or an
-- item out of a bag onto the empty square to add it, onto a full one to
-- replace it, from one square to another to reorder, and off the line to take
-- it away. A right click takes it away too.
--
-- The line here and the bar on the screen are two pictures of one list.
-- Nothing on this page draws a cooldown or a colour, because this is where you
-- decide what is on the bar and the bar is where you read what it is doing.
--
-- Nothing here names a setting. AdHoc.lua owns the list and Bars.lua owns the
-- keys; this file asks which record is where and tells them where a drop
-- landed.
--------------------------------------------------------------------------

local M = ns.UI.Metric

-- A square on the page, and the air between two. The size of a square on the
-- bar itself at zoom one, so the page shows the bar the size it is.
local EDGE, GAP = 27, 4

-- The pool, built once at the width of a bar plus the empty square on the end,
-- because a frame cannot be destroyed on these clients.
local squares = {}

-- Which square a button belongs to, for the drag the cursor does not carry.
local owner = {}

-- The square being dragged. Set when the drag starts and read when the button
-- comes up, which is inside one gesture and never outside one.
local lifted = nil

local function Shown()
	return ns.AdHoc.Shown()
end

local function Current()
	return ns.AdHoc.Get(Shown())
end

--------------------------------------------------------------------------
-- What the cursor is holding
--------------------------------------------------------------------------

-- A refusal is said once per reason rather than once per ask, because the
-- widget asks on hover as well as on drop and a loaded cursor crossing the
-- line would print a line per square.
local told = {}

local function Say(line)
	if told[line] then
		return
	end
	told[line] = true
	ns.Print(line)
end

local function Take(kind, a, b, c)
	if not kind then
		return nil
	end
	local record, why = ns.AdHoc.Carry(kind, a, b, c)
	if not record and why then
		Say(why)
	end
	return record
end

--------------------------------------------------------------------------
-- The two ends of a drag
--------------------------------------------------------------------------

local function Lift(w)
	lifted = nil
	if w.record then
		lifted = w.at
	end
end

-- Where the button came up. On another square of the line, the record moves
-- there. On the square it came from, nothing happened. Anywhere else, it comes
-- off the bar.
local function Landed()
	local from = lifted
	lifted = nil
	if not from then
		return
	end
	local focus = ns.MouseFocus()
	local w = focus and owner[focus] or nil
	if w and w.at == from then
		return
	end
	if w then
		ns.AdHoc.Move(Shown(), from, w.at)
	else
		ns.AdHoc.Take(Shown(), from)
	end
end

-- A drop, or a right click, on one square.
local function Drop(w, record)
	if record == nil then
		return ns.AdHoc.Take(Shown(), w.at) ~= nil
	end
	local ok, why = ns.AdHoc.Put(Shown(), w.at, record)
	if not ok and why then
		ns.Print(why)
	end
	return ok
end

--------------------------------------------------------------------------
-- One square
--------------------------------------------------------------------------

local function Says(w)
	local record = w.record
	if not record then
		return { kind = "note", title = "the next square",
			lines = { "Drag a spell out of your book, an item out of a bag or a macro onto it." } }
	end
	return { kind = "note", title = record.name,
		lines = { "Drag it onto another square to move it, or off the line to take it away.",
			"Right click takes it away too." } }
end

local function Square(frame)
	local w
	w = ns.UI.DropSquare(frame, EDGE, function()
		return w.record and w.record.icon, w.record and w.record.name
	end, function(record)
		return Drop(w, record)
	end, {
		take = Take,
		after = ns.Options.Refresh,
		drag = function() Lift(w) end,
		landed = Landed,
		describe = function() return Says(w) end,
	})
	owner[w.button] = w
	return w
end

--------------------------------------------------------------------------
-- The line
--------------------------------------------------------------------------

-- The squares of the shown bar and one empty after them, wrapped to the
-- page's width, and how tall that came out.
local function Lay(width)
	local records = ns.AdHoc.Squares(Shown())
	local count = records and math.min(#records + 1, ns.AdHoc.PER_BAR) or 0
	local across = math.max(1, math.floor((width + GAP) / (EDGE + GAP)))
	local rows = 0

	for at = 1, #squares do
		local w = squares[at]
		if at <= count then
			local column, row = (at - 1) % across, math.floor((at - 1) / across)
			rows = row + 1
			w.at = at
			w.record = records[at]
			w:SetSize(EDGE, EDGE)
			w:ClearAllPoints()
			w:SetPoint("TOPLEFT", column * (EDGE + GAP), -(row * (EDGE + GAP)))
			w:Show()
			w.Refresh()
		else
			w.at, w.record = nil, nil
			w:Hide()
		end
	end

	if rows == 0 then
		return 0
	end
	return rows * (EDGE + GAP) - GAP
end

function Panel.Square(at)
	return squares[at]
end

--------------------------------------------------------------------------

function Panel.Build(ui)
	ui.Section("Ad hoc bars", "Action bars")
	ui.Lede("A bar of your own on a key: hidden until you press it, gone again after a press.")

	ui.Tabs(
		function()
			local labels = {}
			for index, bar in ipairs(ns.AdHoc.All()) do
				labels[index] = bar.name
			end
			return labels
		end,
		Shown,
		function(index) ns.AdHoc.Show(index) end,
		{
			onAdd = function()
				local index, why = ns.AdHoc.Add()
				if not index then
					ns.Print(why)
				end
			end,
		})

	ui.Reading("bars", function()
		local count = ns.AdHoc.Count()
		if count == 0 then
			return "none yet, press +"
		end
		return ("%d of %d"):format(count, ns.AdHoc.MAX)
	end)

	ui.TextField("name",
		function()
			local bar = Current()
			return bar and bar.name or ""
		end,
		function(value) ns.AdHoc.Rename(Shown(), value) end)

	ui.KeyField("key",
		function()
			local bar = Current()
			if bar and bar.key ~= "" then
				return bar.key
			end
			return "|cff808080not bound|r"
		end,
		function(combo)
			local ok, why = ns.AdHocBars.Bind(Shown(), combo)
			if not ok then
				ns.Print(why)
			end
		end,
		function() ns.AdHocBars.Bind(Shown(), "") end)
	ui.Hint("Press it to show the bar, again to put it away.")

	ui.Reading("this key", function()
		local bar = Current()
		if not bar or bar.key == "" then
			return "not bound"
		end
		if bar.displaced ~= "" then
			return "shadows " .. bar.displaced
		end
		return "nothing else wanted it"
	end)

	ui.Gap()

	ui.Custom(function(frame)
		for at = 1, ns.AdHoc.PER_BAR do
			squares[at] = Square(frame)
		end
		return function()
			return Lay(frame:GetWidth())
		end
	end, { height = M.control, label = "the squares on this bar" })
	ui.Hint("Drop a spell, an item or a macro on the empty square. Drag the strip on the bar's left edge to move it.")

	ui.Count("columns", 1, ns.AdHoc.PER_BAR,
		function() return ns.AdHoc.Columns(Shown()) end,
		function(value) ns.AdHoc.SetColumns(Shown(), value) end)

	ui.Check("put the bar away after a press", function()
		return ns.AdHoc.Closes(Shown())
	end, function(value)
		ns.AdHoc.SetCloses(Shown(), value)
	end)

	ui.Reading("on screen", function()
		local index = Shown()
		if index == 0 then
			return "no bar"
		end
		if not ns.db.adhoc then
			return "the bars are off"
		end
		local visible = ns.AdHocBars.Visible(index)
		if visible == nil then
			return "not built yet"
		end
		return visible and "up" or "hidden, hold the key"
	end)

	ui.Action(
		function()
			local bar = Current()
			return bar and ("delete " .. bar.name) or "delete"
		end,
		function() ns.AdHoc.Remove(Shown()) end,
		function() return Current() ~= nil end)
end
