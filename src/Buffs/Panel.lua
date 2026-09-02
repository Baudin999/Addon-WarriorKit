local ADDON, ns = ...

local Panel = {}
ns.BuffPanel = Panel

--------------------------------------------------------------------------
-- Arranging the row, on the page
--
-- The row as it will look, twice: the line that is checked out of a fight and
-- the line that is checked in one, with the squares that are off both
-- underneath. What you do to it is what Cooldowns/Panel.lua already lets you do
-- to the cooldown row: drag a spell out of your spellbook onto a line, drag a
-- square from one line to the other, drag one off to stop watching it.
--
-- One difference from that page, and it is the whole of what the lines mean.
-- There a square is on one line or the other and a drag between them moves it.
-- Here the lines are disjoint sets: a shield belongs on both, so a drag from
-- one line onto the other puts the square there as well, and a drag off a line
-- takes it off that line only. Off its last line it goes under the row. So
-- nothing rides the cursor out of a square on this page: a drag is answered
-- entirely by where the button comes up, which is the one reading that can
-- tell "onto the other line" from "off this one".
--
-- The lines are captioned and the cooldown row's are not, because there the
-- size of a square says which line it is on and here both lines draw at one
-- size. "out of a fight" and "in a fight" are the two words that carry the whole
-- difference, so they sit to the left where the tray's caption already sits.
--
-- The tick boxes stay. They are what the request asked for, they are the row
-- said as a list for anyone who would rather read it, and they are one line
-- each. What this page replaced is the list of your own spells with a remove
-- button per row: a square you can drag off is that list, drawn.
--
-- Nothing here names a setting. Upkeep.lua owns the lines, the switches and
-- the list you keep; this file asks it which entry is where and tells it where
-- a drop landed.
--------------------------------------------------------------------------

local M, C = ns.UI.Metric, ns.UI.Color

-- The column the captions sit in, to the left of the squares. The same width
-- as the cooldown page's tray caption, because "out of a fight" is the longest
-- of the three and fits it at the small face.
local CAPTION = 76

-- The pools, built once at login at the ceiling, because a frame cannot be
-- destroyed on these clients. One pool for both lines: a square is a place on
-- the page and not an entry, and which line it stands on is written every time
-- the page is laid out. Two past the ceiling for the empty square at the end of
-- each line that a drop lands on.
local squares, shelved = {}, {}

-- Which square a button belongs to, for the one drag the cursor cannot carry.
local owner = {}

-- The square being dragged: which entry, and which line it was lifted off.
-- Set when the drag starts and read when the button comes up, which is inside
-- one gesture and never outside one.
local pendingKey, pendingLine

--------------------------------------------------------------------------
-- What the cursor is holding
--------------------------------------------------------------------------

-- A refusal is said once per reason rather than once per ask, the way the
-- cooldown page says its own.
local told = {}

local function Say(line)
	if told[line] then
		return
	end
	told[line] = true
	ns.Print(line)
end

local function Take(kind, a, b, c)
	if kind == "spell" then
		local id = ns.SpellIdOnCursor(a, b, c)
		if id then
			return id
		end
		Say("this client would not say which spell that was.")
		return nil
	end

	if kind then
		Say(("a %s is not something the row watches. It watches the auras a spell"
			.. " leaves on you, and the two hands you hold a weapon in."):format(kind))
	end
	return nil
end

--------------------------------------------------------------------------
-- The two ends of a drag
--------------------------------------------------------------------------

-- Off one line, or off the row from under it.
local function Off(entry, line)
	if entry and line then
		ns.Upkeep.Leave(entry.key, line)
	elseif entry then
		ns.Upkeep.SetWatched(entry.key, false)
	end
end

local function Lift(w)
	pendingKey, pendingLine = nil, nil
	if w.entry then
		pendingKey, pendingLine = w.entry.key, w.line
	end
end

-- Where the button came up. On the other line, the square goes there too. On
-- the line it came from, nothing happened. Anywhere else, the tray included,
-- it comes off the line it was lifted from.
local function Landed()
	local key, from = pendingKey, pendingLine
	pendingKey, pendingLine = nil, nil
	if not key then
		return
	end

	local focus = ns.MouseFocus()
	local w = focus and owner[focus] or nil
	if w and w.line == from then
		return
	end
	if w and w.line then
		local ok, why = ns.Upkeep.Place(key, w.line)
		if not ok and why then
			ns.Print(why)
		end
		return
	end
	if from then
		ns.Upkeep.Leave(key, from)
	end
end

-- A drop, or a right click, on one square. The right click is the drag said in
-- one press: off this line from a square on it, back onto the lines it shipped
-- on from one under the row.
local function Drop(w, spellID)
	if spellID == nil then
		if w.line then
			Off(w.entry, w.line)
		elseif w.entry then
			ns.Upkeep.Place(w.entry.key, nil)
		end
		return false
	end

	if not w.line then
		local entry = ns.Upkeep.Owner(spellID)
		Off(entry)
		return entry ~= nil
	end

	local ok, message = ns.Upkeep.Put(spellID, w.line)
	if not ok and message then
		ns.Print(message)
	end
	return ok
end

--------------------------------------------------------------------------
-- One square
--------------------------------------------------------------------------

local function Says(w)
	local entry = w.entry
	if not entry then
		return { kind = "note", title = "an empty square",
			lines = { "Drag a spell here out of your spellbook." } }
	end

	local title = entry.label or entry.key
	if not w.line then
		return { kind = "note", title = title,
			lines = { "Off the row and not watched.",
				"Drag it onto a line, or right click to put it back." } }
	end

	local line = "On the out line, checked between fights, which is when you"
		.. " can put it on."
	if w.line == ns.Upkeep.IN then
		line = "On the in line, checked during a fight, which is when it lapses."
	end
	local move = "Drag it onto the other line to check it there as well."
		.. " Drag it off, or right click, to take it off this line."
	if entry.racial then
		move = "Your racial stays on this line: a cooldown that is ready between"
			.. " fights is ready all afternoon. Right click takes it off the row."
	elseif ns.Upkeep.Lines(entry) == ns.Upkeep.BOTH then
		line = line .. " It is on the other line too."
	end

	return { kind = "note", title = title, lines = { line, move } }
end

local function Square(frame)
	local icon = ns.BuffNag.Metrics()
	local w
	w = ns.UI.DropSquare(frame, icon, function()
		return w.entry and w.entry.texture, w.entry and w.entry.label
	end, function(spellID)
		return Drop(w, spellID)
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
-- Laying it out
--------------------------------------------------------------------------

-- One line of squares from a place in the pool, wrapped to the page's width,
-- and how tall it came out. `count` is what is drawn plus one for the empty
-- square a drop lands on, which is also the whole of a line with nothing on it.
local function Lay(pool, band, count, width, top)
	local edge, gap = ns.BuffNag.Metrics()
	local across = math.max(1, math.floor((width - band.left + gap) / (edge + gap)))
	local rows = 1

	for index = 1, count do
		local w = pool[band.from + index - 1]
		local column, row = (index - 1) % across, math.floor((index - 1) / across)
		rows = row + 1

		w.line, w.at = band.line, index
		if band.line then
			w.entry = ns.Upkeep.OnLine(band.line, index)
		else
			w.entry = ns.Upkeep.Shelved(index)
		end

		w:SetSize(edge, edge)
		w:ClearAllPoints()
		w:SetPoint("TOPLEFT", band.left + column * (edge + gap), -(top + row * (edge + gap)))
		w:Show()
		w.Refresh()
	end

	return rows * (edge + gap) - gap
end

local function Rest(pool, from)
	for index = from, #pool do
		pool[index].line, pool[index].entry = nil, nil
		pool[index]:Hide()
	end
end

local function Shape(width)
	local _, gap = ns.BuffNag.Metrics()
	local out, fight = ns.Upkeep.Split()

	local top = Lay(squares, { from = 1, left = CAPTION, line = ns.Upkeep.OUT },
		out + 1, width, 0)
	local under = Lay(squares, { from = out + 2, left = CAPTION, line = ns.Upkeep.IN },
		fight + 1, width, top + gap)
	Rest(squares, out + fight + 3)
	return top, top + gap + under
end

--------------------------------------------------------------------------
-- The rows on the page
--------------------------------------------------------------------------

function Panel.Square(index)
	return squares[index]
end

function Panel.Shelved(index)
	return shelved[index]
end

-- The two lines, captioned. Everything they draw is written in the measure
-- rather than in a refresh beside it, because the layout is the refresh here.
function Panel.Rows(ui)
	local calm, fight

	ui.Custom(function(frame)
		calm = ns.UI.Label(frame, M.small, C.dim, "LEFT", ns.UI.FLAT)
		calm:SetPoint("TOPLEFT")
		calm:SetText("out of a fight")
		fight = ns.UI.Label(frame, M.small, C.dim, "LEFT", ns.UI.FLAT)
		fight:SetText("in a fight")

		for index = 1, ns.Upkeep.Ceiling() + 2 do
			squares[index] = Square(frame)
		end
		return function()
			local top, whole = Shape(frame:GetWidth())
			local _, gap = ns.BuffNag.Metrics()
			fight:ClearAllPoints()
			fight:SetPoint("TOPLEFT", 0, -(top + gap))
			return whole
		end
	end, { height = M.control, label = "the two lines of the missing-buff row" })
end

-- And what is off both, behind a caption. Nothing off the row is no row at all.
function Panel.Tray(ui)
	local caption

	ui.Custom(function(frame)
		caption = ns.UI.Label(frame, M.small, C.dim, "LEFT", ns.UI.FLAT)
		caption:SetPoint("TOPLEFT")

		for index = 1, ns.Upkeep.Ceiling() do
			shelved[index] = Square(frame)
		end

		return function(cell)
			local count = ns.Upkeep.ShelfCount()
			caption:SetText(count > 0 and "off the row" or "")
			cell.gap = count > 0 and M.rowGap or 0
			if count == 0 then
				Rest(shelved, 1)
				return 0
			end

			local tall = Lay(shelved, { from = 1, left = CAPTION }, count, frame:GetWidth(), 0)
			Rest(shelved, count + 1)
			return tall
		end
	end, { label = "the buffs that are off the row" })
end
