local ADDON, ns = ...

local Panel = {}
ns.CooldownPanel = Panel

--------------------------------------------------------------------------
-- Arranging the row, on the page
--
-- The row as it will look, at the size it will be drawn, with the squares that
-- are off it underneath. What you do to it is what anybody does to a row of
-- icons and has done since the first action bar: drag a spell out of your
-- spellbook onto a line, drag a square from one line to the other, drag one off
-- to stop counting it.
--
-- This replaced twenty-three rows of controls, five per entry: a tick box that
-- said whether the square was on the row, two buttons that walked it one place
-- along its line, a third that sent it to the other line, and a cross. Every
-- one of them described a picture instead of being one, and the picture was on
-- the other side of the screen. Nobody arranging a row of icons wants to read
-- the row out as a list and then edit the list.
--
-- Three things follow from drawing the row rather than listing it.
--
-- The sizes come off Row.lua rather than out of this file. A big square is a
-- press you are waiting for right now and a small one is a press you are
-- waiting for this fight, and that difference is carried by nothing but how big
-- they are. A page that picked its own ratio would be teaching the wrong
-- reading of the thing it exists to arrange.
--
-- The line wraps here and does not wrap in the game. The row on screen is as
-- wide as it needs to be; the page is under four hundred pixels. Eleven squares
-- on the top line have to be shown somewhere, so the wrap is the page saying it
-- cannot draw the line at the width the game will.
--
-- And what is off the row is drawn too. A square you dragged off that appeared
-- nowhere would be one you could not put back: a trinket cannot be dragged out
-- of your spellbook, and neither can a spell you have not trained.
--------------------------------------------------------------------------

local M, C = ns.UI.Metric, ns.UI.Color

-- The column the words "off the row" sit in, to the left of the squares that
-- are. Wide enough for the caption at the small face and nothing more, because
-- every pixel of it is a pixel the squares beside it do not get.
local CAPTION = 76

-- The two pools, built once at login at the ceiling, because a frame cannot be
-- destroyed on these clients and a pool sized to the list would leak a square
-- every time you dragged one.
--
-- One pool for both lines rather than one each. A square is a place on the row
-- and not an entry: which line it stands on and how far along it is are written
-- every time the page is laid out, so the top line taking six squares and the
-- docked line taking four is one pool of ten and not two of twenty-three.
--
-- Two past the ceiling, for the empty square at the end of each line that a
-- drop lands on.
local squares, shelved = {}, {}

-- Which square a button belongs to, for the one drag the cursor cannot carry.
-- Kept here rather than on the button, because a field written onto a widget is
-- a field the client may one day have its own meaning for.
local owner = {}

-- The square being dragged, and it is only ever set for one whose contents
-- would not go on the cursor. Set when the drag starts and read when the button
-- comes up, which is inside one gesture and never outside one.
local pending

--------------------------------------------------------------------------
-- What the cursor is holding
--------------------------------------------------------------------------

-- A refusal is said once per reason rather than once per ask. The square puts
-- the same question to this on the way in as it does on a drop, so a cursor
-- carrying something the row cannot count passes through here every time the
-- mouse crosses a square. Keyed by the sentence, the way Hover/Panel.lua keys
-- its own, so a second thing going wrong still gets said.
local told = {}

local function Say(line)
	if told[line] then
		return
	end
	told[line] = true
	ns.Print(line)
end

-- Which spell is on the cursor, as an id.
--
-- Three readings, the same three Hover/Hover.lua takes and for the same reason:
-- this client answers a dragged spell with a spellbook index and the book it
-- came out of, newer builds put the id in a fourth slot, and nothing installed
-- on this machine proves which of those 2.5.6 hands back.
--
-- The id is what the row counts by, so the book reading goes through
-- GetSpellBookItemInfo, which is where Buttons/Ranks.lua reads its own ids
-- from. The bare first value is tried last and only where the second is not a
-- book: a spellbook index is a small number and every small number names some
-- spell, so that reading taken first would put Charge on the row for anything
-- dragged out of the top of the book.
local function Cursor(a, b, c)
	if type(c) == "number" and ns.SpellName(c) then
		return c
	end

	if type(a) == "number" and type(b) == "string"
		and type(_G.GetSpellBookItemInfo) == "function" then
		local ok, kind, id = pcall(_G.GetSpellBookItemInfo, a, b)
		if ok and kind == "SPELL" and type(id) == "number" then
			return id
		end
	end

	if type(a) == "number" and type(b) ~= "string" and ns.SpellName(a) then
		return a
	end
	return nil
end

-- What a square will take off the cursor, handed to the widget layer, which
-- knows what a square is and nothing about a spell.
local function Take(kind, a, b, c)
	if kind == "spell" then
		local id = Cursor(a, b, c)
		if id then
			return id
		end
		Say("this client would not say which spell that was.")
		return nil
	end

	if kind then
		Say(("a %s is not something the row counts down. It counts spells and the"
			.. " two trinkets you are wearing."):format(kind))
	end
	return nil
end

--------------------------------------------------------------------------
-- The two ends of a drag
--
-- A drag out of a square goes one of two ways and the page picks between them
-- once, at the start, on whether the cursor took what was in it.
--
-- A spell rides the cursor, which is how every icon in the game moves and is
-- why one dragged off the row can be dropped on an action bar. The drop is then
-- an ordinary drop and the square it lands on reads it off the cursor.
--
-- A trinket cannot. Picking up an equipped item unequips it, which is not what
-- the drag meant, so nothing goes on the cursor and the square is remembered
-- instead. Where the button comes up is what the client is asked at the end,
-- and a drag that ended over nothing leaves the square off the row, which is
-- what dragging it off means.
--
-- The two cannot both fire for one drag, because `pending` is set only when the
-- cursor came up empty. That is what makes the order the client fires them in
-- something this file does not have to know.
--------------------------------------------------------------------------

-- Off the row. One act whichever kind of entry it is and whoever put it there:
-- a square you are not counting is a square you are not counting, and it goes
-- under the row where you can drag it back.
local function Off(entry)
	if entry then
		ns.Cooldowns.SetWatched(entry.key, false)
	end
end

local function Lift(w)
	local entry = w.entry
	pending = nil
	if not entry then
		return
	end

	Off(entry)
	if entry.id and ns.CarrySpell(entry.id) then
		return
	end
	pending = entry.key
end

local function Landed()
	local key = pending
	pending = nil
	if not key then
		return
	end

	-- Both names, through the shim, because this client answers this question
	-- under one of two and nothing installed here proves which. Asked under one
	-- name only, a trinket dragged from one line to the other came off the row
	-- and landed nowhere, which looks exactly like a square that cannot be
	-- dragged at all.
	local focus = ns.MouseFocus()
	local w = focus and owner[focus] or nil
	if w and w.line then
		ns.Cooldowns.Place(key, w.line, w.at)
	end
end

-- A drop, or a right click, on one square.
--
-- The right click is the drag said in one press, and it goes the way the square
-- is facing: off the row from a square on it, back onto the row from one under
-- it, at the end of the line that square belongs to. It is here for the hurry
-- and it is here for the client that answers neither name for the frame under
-- the cursor, because whatever else is true a square has to be able to come off
-- the row and go back on.
--
-- Forgetting one you added yourself is not this gesture and deliberately not.
-- Off the row and gone for good look identical the moment after you press, and
-- the one that cannot be undone by dragging is the one that does not get the
-- easy button. `/wk cooldowns drop <id>` is where that lives.
local function Drop(w, spellID)
	if spellID == nil then
		if w.line then
			Off(w.entry)
		elseif w.entry then
			ns.Cooldowns.Place(w.entry.key, w.entry.layer,
				ns.Cooldowns.Count() + 1)
		end
		return false
	end

	-- Dropped under the row rather than on it, which is where a square goes when
	-- you stop counting it. A spell nothing on the row has heard of is not
	-- refused here, it is simply not on the row, which is the state the drop was
	-- asking for.
	if not w.line then
		local entry = ns.Cooldowns.Owner(spellID)
		Off(entry)
		return entry ~= nil
	end

	local ok, message = ns.Cooldowns.Put(spellID, w.line, w.at)
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

	if not w.line then
		return { kind = "note", title = entry.name or entry.key,
			lines = { "Off the row and not counted.",
				"Drag it onto a line, or right click to put it back." } }
	end

	local line = "On the docked line, where a square is a press you are waiting"
		.. " for this fight."
	if w.line == ns.Cooldowns.ROTATION then
		line = "On the top line, where a square is a press you are waiting for now."
	end

	return { kind = "note", title = entry.name or entry.key,
		lines = { line, "Drag it where you want it. Right click takes it off the row." } }
end

-- One square, and the whole of what it knows about itself is written by the
-- layout below. `entry` is what is under it right now, `line` is which of the
-- two it stands on, and a square with no line is one of the ones off the row.
local function Square(frame)
	local _, icon = ns.CooldownRow.Metrics()
	local w
	w = ns.UI.DropSquare(frame, icon, function()
		return w.entry and w.entry.texture, w.entry and w.entry.name
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

-- One line of squares, from a place in the pool, and how tall it came out.
--
-- `count` is what is drawn on that line plus one, and the one is the empty
-- square on the end. It is what a drop lands on to put something at the end of
-- a line, and it is the whole of a line with nothing on it: a top line that
-- vanished when you took the last square off it would be a line you could not
-- put anything back onto.
local function Lay(pool, band, count, edge, width, top)
	local _, _, gap = ns.CooldownRow.Metrics()
	local across = math.max(1, math.floor((width - band.left + gap) / (edge + gap)))
	local rows = 1

	for index = 1, count do
		local w = pool[band.from + index - 1]
		local column, row = (index - 1) % across, math.floor((index - 1) / across)
		rows = row + 1

		w.line, w.at = band.line, index
		if band.line then
			w.entry = ns.Cooldowns.OnRow(band.line, index)
		else
			w.entry = ns.Cooldowns.Shelved(index)
		end

		w:SetSize(edge, edge)
		w:ClearAllPoints()
		w:SetPoint("TOPLEFT", band.left + column * (edge + gap),
			-(top + row * (edge + gap)))
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

-- Both lines, left aligned rather than centred on each other the way the row on
-- screen is. The row centres because it is a block over your character and the
-- eye reads it as one shape; the page is an editor, and a drop target that
-- moves sideways when the line above it grows is one you have to aim at twice.
local function Shape(width)
	local big, icon, _, dock = ns.CooldownRow.Metrics()
	local fast, long = ns.Cooldowns.Split()

	local top = Lay(squares, { from = 1, left = 0, line = ns.Cooldowns.ROTATION },
		fast + 1, big, width, 0)
	local under = Lay(squares,
		{ from = fast + 2, left = 0, line = ns.Cooldowns.LONG },
		long + 1, icon, width, top + dock)
	Rest(squares, fast + long + 3)
	return top + dock + under
end

--------------------------------------------------------------------------
-- The two rows on the page
--------------------------------------------------------------------------

-- One square, for scripts/harness.lua, handed out for the reason Row.Icon is:
-- what a drag does is a script on a widget, and there is no honest way to drive
-- one of those from outside. The squares on the row are numbered from the start
-- of the top line, which is the order the page walks them in.
function Panel.Square(index)
	return squares[index]
end

function Panel.Shelved(index)
	return shelved[index]
end

-- The row itself. Everything it draws is written in the measure rather than in
-- a refresh beside it, because the layout is the refresh here: which square
-- holds what, how big it is and where it sits all move together when anything
-- moves at all, and the width is only known once the stack has handed it over.
function Panel.Rows(ui)
	ui.Custom(function(frame)
		for index = 1, ns.Cooldowns.Ceiling() + 2 do
			squares[index] = Square(frame)
		end
		return function()
			return Shape(frame:GetWidth())
		end
	end, { height = M.control, label = "the two lines of the cooldown row" })
end

-- And what is off it, behind a caption, because a second row of squares under
-- the row with nothing said about it reads as a third line of the row.
--
-- Nothing off the row is no row at all rather than a caption over an empty
-- strip: zero height and no gap under it, which is what every list row in this
-- addon does with a slot nobody has filled.
function Panel.Tray(ui)
	local caption

	ui.Custom(function(frame)
		caption = ns.UI.Label(frame, M.small, C.dim, "LEFT", ns.UI.FLAT)
		caption:SetPoint("TOPLEFT")

		for index = 1, ns.Cooldowns.Ceiling() do
			shelved[index] = Square(frame)
		end

		return function(cell)
			local _, icon = ns.CooldownRow.Metrics()
			local count = ns.Cooldowns.ShelfCount()

			-- Emptied rather than hidden. A row with no height is a row with no
			-- room for the words in it, and a hidden string is still a string
			-- taller than the nothing it sits in.
			caption:SetText(count > 0 and "off the row" or "")
			cell.gap = count > 0 and M.rowGap or 0
			if count == 0 then
				Rest(shelved, 1)
				return 0
			end

			local tall = Lay(shelved, { from = 1, left = CAPTION },
				count, icon, frame:GetWidth(), 0)
			Rest(shelved, count + 1)
			return tall
		end
	end, { label = "the cooldowns that are off the row" })
end
