local ADDON, ns = ...

local Window = {}
ns.DungeonWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric
local Chart = UI.Chart
local Book, Places, Loot = ns.DungeonBook, ns.DungeonPlaces, ns.DungeonLoot

--------------------------------------------------------------------------
-- The dungeon log
--
-- Three columns: every boss in the game down the left, the dungeon you picked
-- drawn in the middle with the bosses marked on it, and what the one you are
-- reading drops on the right.
--
-- **It is the quest log's shape on purpose.** The same three columns, the same
-- widths, the same scrolling list on the left and the same item rows on the
-- right. A player who has learned one window has learned this one, and the two
-- answer the two halves of the same question: what am I doing, and what is it
-- for.
--
-- **The left column is every dungeon at once.** Forty of them, one header per
-- dungeon carrying the levels it is for, one row per boss under it in the order
-- they are fought. That is two hundred and thirty seven rows, and drawing all
-- of them is the point: the question anybody opens this window with is "what
-- should I be running now", and it is a question about the whole list. A
-- dropdown of dungeon names would answer "show me Uldaman" and nothing else.
--
-- The list is in level order because a dungeon is a thing you do at a level.
-- The world map's column is alphabetical and that is the right choice there,
-- because a zone is a place you look up by name; a dungeon is a place you go
-- when you are twenty six.
--
-- **The middle is the client's own map with the bosses on it.** The picture is
-- UI/Chart.lua, the same widget the quest log's map and the world map are drawn
-- on, and the marks are numbered squares matching the numbers down the left. A
-- dungeon is cut into floors and the strip under the map steps between them,
-- which is the same strip the quest log puts under a quest that spans two
-- zones.
--
-- **Nothing on the picture is invented, and that is the one thing to know
-- about this window.** No database on either client says where a boss stands
-- inside an instance; Questie, which knows where every creature in the outdoor
-- world is, files them all at {-1, -1}. So a mark appears the first time you
-- loot that boss, from where you were standing, and a dungeon you have never
-- run draws its map with no marks on it and a line underneath saying so.
-- Dungeons/Seen.lua carries the argument in full. The alternative was a
-- coordinate somebody remembered, which is a mark that is wrong on the one
-- screen you opened to find out where something is.
--
-- **The right column is what the boss drops, checked against the client.** The
-- book carries an item as an id and the name it had when it was baked, and a
-- row whose id resolves to a different name is dropped rather than drawn.
-- Dungeons/Loot.lua carries that; it is the difference between a window that
-- shows you the wrong sword and one that shows you one fewer.
--
-- **Everything is built once.** The list holds two hundred and thirty seven
-- rows, the board holds a pool of tiles and marks, and this client cannot
-- destroy a frame, so a window that rebuilt either on a click would leak a
-- dungeon's worth of frames per click all evening. It is the same argument the
-- quest log's two scrolling columns make one file across.
--------------------------------------------------------------------------

local WIDTH, HEIGHT = 860, 540

-- The two fixed columns, the same numbers the quest log uses. The middle takes
-- whatever is left, which is the way round it has to be: a dungeon name and an
-- item name have a length the font decides, and a map does not.
local LIST, DROPS = 250, 220

-- One drop's picture, which is the width the right column reserves before the
-- words start so the names line up down one edge.
local SLOT = 22

-- The tick against a boss you have looted. A `V` because that is the letter
-- Media/Glyphs.ttf cuts the Font Awesome check onto, and a `V` is what a client
-- that refuses the font draws instead.
local TICK = "V"

-- How big a boss's mark is drawn on the picture, and how much bigger the one
-- you are reading is.
--
-- Bigger than a quest's camp because it carries a number, and the number is
-- what joins the mark to the row in the left column. Fourteen pixels of Arial
-- Narrow needs about sixteen of square around it before the figure stops
-- touching the edge.
local MARK, PICKED = 16, 20

-- The most floors the strip under the map will offer. Blackrock Depths is the
-- deepest dungeon in the game at about ten, and a strip that wrapped onto a
-- second line would take the map's own height to say where the map could be.
local FLOORS = 12

local window, list
local board, drops
local floors, heading, note
local tally, reading

-- Which boss is selected, as the creature id in a string, and which floor of
-- its dungeon the map is on.
local showing = nil
local floorAt = 1

-- Whether Paint is the thing that moved the selection. The list calls back on
-- every Select that changes the id, the callback repaints, and the repaint
-- selects. It is the same latch the quest log keeps between its list and its
-- own paint.
local painting = false

--------------------------------------------------------------------------
-- The left column
--------------------------------------------------------------------------

-- What one boss's row says. The number first, because the number is what the
-- mark on the map carries and the two have to be readable as the same thing.
local function Label(order, boss)
	return ("%d. %s"):format(order, boss.name)
end

-- What one row is drawn in. The client's own experience ladder, against the
-- boss's own level, which is the same ladder the quest log colours a quest with
-- and the enemy bars colour a mob with. A column of two hundred rows that says
-- "this one will kill you" in colour is a column you can read without reading.
--
-- WorthOf rather than Worth, because a boss in a book is a level and not a unit
-- standing anywhere. Unit/Level.lua's header carries the split.
local function Tint(boss)
	return ns.Unit.Level.WorthOf(boss.level)
end

-- What the header over one dungeon says: its name and the levels it is for.
local function Header(dungeon)
	if dungeon.low == dungeon.high then
		return ("%s  %d"):format(dungeon.name, dungeon.low)
	end
	return ("%s  %d-%d"):format(dungeon.name, dungeon.low, dungeon.high)
end

-- What the left column holds, as the rows UI.List draws.
--
-- Public for the reason the quest log's are: the harness has to be able to
-- measure what was drawn, and the alternative is this file handing out a
-- reference to the list widget itself.
function Window.Rows()
	local rows = {}
	for _, dungeon in ipairs(Book.All()) do
		rows[#rows + 1] = { header = Header(dungeon) }
		for order, boss in ipairs(dungeon.bosses) do
			local placed = Book.Where(boss.id) ~= nil
			rows[#rows + 1] = {
				id = Book.Key(boss),
				label = Label(order, boss),
				color = Tint(boss),
				-- The tick says you have looted this one, which is the same
				-- thing as saying it is on the map. It keeps its own colour
				-- through the selection, for the reason the quest log's does:
				-- the row you are reading must not be the row that says least.
				mark = placed and TICK or nil,
				markColor = C.tick,
			}
		end
	end
	return rows
end

--------------------------------------------------------------------------
-- The middle
--------------------------------------------------------------------------

-- Which dungeon and which boss the column is pointing at.
local function Chosen()
	if not showing then
		return nil
	end
	local boss, dungeon, order = Book.Found(showing)
	return dungeon, boss, order
end

-- Every floor of the dungeon being drawn, and which of them the map is on.
--
-- Nothing at all where the client has no map for the place, which is a real
-- answer rather than a failure: the left and right columns are the whole of
-- what a dungeon log is for and both work without a picture.
local function Sheets(dungeon)
	if not dungeon then
		return {}
	end
	local map = Places.Of(dungeon.name)
	if not map then
		return {}
	end
	return Places.Floors(map)
end

-- The marks that go on one floor: one numbered square per boss this addon has
-- watched you loot on this map, and the one you are reading drawn bigger and in
-- the heading colour.
--
-- A boss with no position is not on the picture and is not faked onto it. The
-- line under the map is where that is said.
local function Points(dungeon, map, picked)
	local points = {}
	for order, boss in ipairs(dungeon.bosses) do
		local held, x, y = Book.Where(boss.id)
		if held == map then
			local mine = boss.id == picked
			points[#points + 1] = {
				x = x, y = y,
				kind = Chart.MARK,
				label = tostring(order),
				size = mine and PICKED or MARK,
				tint = mine and C.heading or C.accent,
				name = boss.name,
				note = { ("%d of %d in %s"):format(order, #dungeon.bosses, dungeon.name) },
			}
		end
	end
	return points
end

-- How many of a dungeon's bosses this addon has a position for, on any floor.
local function Placed(dungeon)
	local held = 0
	for _, boss in ipairs(dungeon.bosses) do
		if Book.Where(boss.id) then
			held = held + 1
		end
	end
	return held
end

-- The line under the map. It has one job and it is the honest one: say why the
-- picture looks the way it does.
local function Note(dungeon, sheets, drawn)
	if not dungeon then
		return "Nothing selected."
	end
	if #sheets == 0 then
		return ("This client has no map for %s, so its bosses are the column on the left.")
			:format(Places.Place(dungeon.name))
	end
	if drawn == 0 then
		return "This client has no picture for that floor."
	end
	local placed, total = Placed(dungeon), #dungeon.bosses
	if placed == 0 then
		return "No bosses marked here yet. Each one is marked where you loot it, because nothing on either client will say where a boss stands."
	end
	return ("%d of %d bosses marked, each one where you looted it."):format(placed, total)
end

-- The floor strip, filled from the client's own floor names.
--
-- Drawn only where there is a choice, the same as the quest log's zone strip
-- and for the same reason: most dungeons are one map, and with one map the name
-- on the strip is already the heading over the picture.
local function Steps(sheets)
	for index = 1, FLOORS do
		local sheet = sheets[index]
		floors:SetLabel(index, sheet and Places.Floor(sheet, index) or "")
		floors:SetShown(index, sheet ~= nil)
	end
	floors.frame:SetShown(#sheets > 1)
	if floorAt > math.max(#sheets, 1) then
		floorAt = 1
	end
	floors:Resize(board.width or 1)
	floors:Select(floorAt)
end

function Window.PaintMap()
	if not window then
		return false
	end
	local dungeon, boss = Chosen()
	local sheets = Sheets(dungeon)

	local was = painting
	painting = true
	Steps(sheets)
	painting = was

	local map = sheets[floorAt]
	local points = (dungeon and map) and Points(dungeon, map, boss and boss.id or -1) or {}
	local drawn = board:Draw(map, points)
	note:SetText(Note(dungeon, sheets, drawn))
	return true
end

--------------------------------------------------------------------------
-- The right column
--------------------------------------------------------------------------

-- One row of the loot column, made once and reused for whatever drop lands on
-- it next. This client cannot destroy a frame, and a boss's table is between
-- none and fifteen rows long, so a column that built what it needed on each
-- click would leak a boss's worth of frames per click all evening.
local function Cell(index)
	local row = drops.pool[index]
	if row then
		return row
	end

	row = CreateFrame("Frame", nil, drops.stack.frame)

	row.icon = UI.Icon(row, "ARTWORK")
	row.icon:SetSize(SLOT, SLOT)
	row.icon:SetPoint("TOPLEFT")

	row.text = UI.Label(row, M.font, C.text, "LEFT", UI.FLAT)
	row.text:SetPoint("TOPLEFT", SLOT + M.rowGap, 0)
	UI.Wrap(row.text, true)
	row.text:SetSpacing(2)

	-- The hover is hung once and reads whatever link the row is carrying now,
	-- rather than being re-hung per repaint. A row with no link answers nothing
	-- and no box opens, which is what stops the last boss's sword staying on
	-- screen over a row that is now something else.
	--
	-- The subject names a kind and nothing else, which is the whole of what this
	-- file has to know about tooltips: the stats come off the client through
	-- UI/Scan.lua and the prices arrive from Feeds/Worth.lua without this file
	-- asking, because both registered against the item kind at load.
	ns.Tip.Hang(row, function(self)
		if not self.link then
			return nil
		end
		return { kind = "item", link = self.link, title = self.name }
	end)

	drops.pool[index] = row
	return row
end

local function Line(opts)
	drops.at = drops.at + 1
	local row = Cell(drops.at)
	local size = opts.size or M.font
	local left = opts.icon and (SLOT + M.rowGap) or 0

	row.icon:SetShown(opts.icon and true or false)
	if opts.icon then
		row.icon:SetTexture(opts.icon)
	end

	row.text:ClearAllPoints()
	row.text:SetPoint("TOPLEFT", left, 0)
	row.text:SetFontObject(UI.Font(size, UI.FLAT))
	local color = opts.color or C.text
	row.text:SetTextColor(color[1], color[2], color[3])
	row.text:SetText(opts.text or "")

	row.link, row.name = opts.link, opts.name
	row:EnableMouse(opts.link and true or false)
	row:Show()

	local stack = drops.stack
	stack:Add(row, {
		gap = opts.gap or M.rowGap,
		measure = function(cell)
			row.text:SetWidth(math.max(stack.width - cell.indent - left, 1))
			local height = UI.TextHeight(row.text, size)
			return opts.icon and math.max(SLOT, height) or height
		end,
	})
	return row
end

local function Start()
	drops.at = 0
	drops.stack.cells = {}
end

local function Finish()
	for index = drops.at + 1, #drops.pool do
		drops.pool[index]:Hide()
	end
	drops.stack:SetWidth(drops.view.width or 0)
	drops.view:Update(drops.stack:Reflow())
end

function Window.PaintDrops()
	Start()
	local _, boss = Chosen()
	if not boss then
		Line({ text = "Nothing selected.", color = C.quiet })
		Finish()
		return false
	end

	Line({ text = boss.name, size = M.heading, color = C.heading, gap = M.gutter })

	local rows = Loot.Rows(boss)
	if #rows == 0 then
		Line({ text = "Nothing recorded off this one. What it drops is written down the first time you loot it.",
			color = C.quiet })
		Finish()
		return true
	end

	for _, row in ipairs(rows) do
		Line({
			text = row.name,
			icon = row.icon,
			color = Loot.Tint(row),
			link = row.link,
			name = row.name,
		})
	end
	Finish()
	return true
end

--------------------------------------------------------------------------
-- The whole window
--------------------------------------------------------------------------

local function Select(key)
	if painting then
		return
	end
	showing = key
	-- The floor goes back to the first, because floor three of the last dungeon
	-- is nothing at all in this one. It is moved again below to whichever floor
	-- the boss was last seen on, where there is one.
	floorAt = 1
	Window.Paint()
end

-- Which floor a boss stands on, as an index into that dungeon's floors.
--
-- Selecting a boss whose mark is on the second floor and drawing the first is a
-- map with nothing on it beside a row that says the mark exists, which reads as
-- a broken window rather than as a floor you have to step to.
local function FloorOf(dungeon, boss)
	local map = boss and Book.Where(boss.id)
	if not map then
		return 1
	end
	local sheets = Sheets(dungeon)
	for index, sheet in ipairs(sheets) do
		if sheet == map then
			return index
		end
	end
	return 1
end

local function Chrome()
	local HALF = M.pad / 2

	window.leftRule = UI.Rule(window.content, C.hairline, true)
	window.leftRule:SetPoint("TOPLEFT", list.frame, "TOPRIGHT", HALF, 0)
	window.leftRule:SetPoint("BOTTOMLEFT", list.frame, "BOTTOMRIGHT", HALF, 0)

	window.rightRule = UI.Rule(window.content, C.hairline, true)
	window.rightRule:SetPoint("TOPRIGHT", drops.frame, "TOPLEFT", -HALF, 0)
	window.rightRule:SetPoint("BOTTOMRIGHT", drops.frame, "BOTTOMLEFT", -HALF, 0)

	tally = UI.Label(window.footer, M.small, C.quiet, "LEFT", UI.FLAT)
	tally:SetPoint("LEFT", 0, 0)
	UI.Wrap(tally, false)

	reading = UI.Label(window.footer, M.small, C.quiet, "RIGHT", UI.FLAT)
	reading:SetPoint("RIGHT", 0, 0)
	UI.Wrap(reading, false)
end

-- Every column sized off the window, in one place rather than nine, because a
-- resolution change has to be able to call it again. The same margin on all
-- four sides and the same gutter between the columns as every other window in
-- the addon.
function Window.Fit()
	if not window then
		return false
	end
	local body = window:Body() - M.pad * 2
	local middle = WIDTH - LIST - DROPS - M.pad * 4

	list:Resize(LIST, body)

	heading:SetWidth(middle)
	note:SetWidth(middle)

	-- What the map is allowed to grow into when the wheel is turned. Everything
	-- under it is subtracted rather than measured, the strip included and
	-- whether or not it is showing: most dungeons have one floor, and a box that
	-- took the strip's height back on those would be a map that changes size
	-- when you click a dungeon. Two lines are reserved for the sentence at the
	-- bottom, which is the longest that sentence gets.
	board:Fit(middle, body - (M.heading + M.rowGap)
		- (M.gutter + floors:Resize(middle)) - (M.gutter + M.row * 2))

	drops.frame:SetSize(DROPS, body)
	drops.view:Resize(DROPS, body)
	return true
end

function Window.Build()
	if window then
		return window
	end

	window = UI.Window({
		name = "WarriorKitDungeons",
		title = "Dungeon Log",
		width = WIDTH,
		height = HEIGHT,
	})
	ns.Remember(window)

	list = UI.List(window.content, {
		name = "WarriorKitDungeonList",
		onSelect = Select,
		marks = true,
	})
	list.frame:SetPoint("TOPLEFT", M.pad, -M.pad)

	heading = UI.Label(window.content, M.heading, C.heading, "LEFT", UI.FLAT)
	heading:SetPoint("TOPLEFT", list.frame, "TOPRIGHT", M.pad, 0)
	UI.Wrap(heading, false)

	-- Named for the reason the quest log's board is: what it draws is twelve
	-- tiles of the client's own art with numbered marks over them, and a map
	-- with a seam through it or a mark in the wrong place is only findable from
	-- outside if the tiles and the marks can be walked one at a time.
	board = Chart.New(window.content, "WarriorKitDungeonChart")
	board.frame:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -M.rowGap)

	-- The strip is anchored under the board rather than measured, so a floor
	-- whose art is a different shape moves the line below it without anything
	-- here having to know the height.
	floors = UI.TabStrip(window.content, { onSelect = function(index)
		if painting then
			return
		end
		floorAt = index
		Window.PaintMap()
	end })
	floors.frame:SetPoint("TOPLEFT", board.frame, "BOTTOMLEFT", 0, -M.gutter)
	for _ = 1, FLOORS do
		floors:Add("")
	end

	note = UI.Label(window.content, M.small, C.quiet, "LEFT", UI.FLAT)
	note:SetPoint("TOPLEFT", floors.frame, "BOTTOMLEFT", 0, -M.gutter)
	UI.Wrap(note, true)
	note:SetSpacing(2)

	drops = { pool = {}, at = 0 }
	drops.frame = CreateFrame("Frame", "WarriorKitDungeonDrops", window.content)
	drops.view = UI.ScrollView(drops.frame)
	drops.view.frame:SetPoint("TOPLEFT")
	drops.stack = UI.Stack(drops.view.canvas)
	drops.frame:SetPoint("TOPRIGHT", -M.pad, -M.pad)

	Chrome()
	Window.Fit()
	return window
end

--------------------------------------------------------------------------

-- Which boss the window opens on: the first one in the first dungeon you have
-- not outlevelled. It is the one guess a dungeon log can make and get right,
-- because a dungeon is a thing you do at a level and the list is in level
-- order. A character past the last of them opens on the last.
local function Landing()
	local level = (type(UnitLevel) == "function" and UnitLevel("player")) or 1
	local last = nil
	for _, dungeon in ipairs(Book.All()) do
		local boss = dungeon.bosses[1]
		if boss then
			last = Book.Key(boss)
			if dungeon.high >= level then
				return last
			end
		end
	end
	return last
end

function Window.Paint()
	if not window or painting then
		return false
	end
	painting = true

	list:Set(Window.Rows())
	if not showing or not Book.Found(showing) then
		showing = Landing()
	end
	list:Select(showing)

	local dungeon, boss = Chosen()
	heading:SetText(dungeon and Header(dungeon) or "")
	if dungeon and floorAt == 1 then
		floorAt = FloorOf(dungeon, boss)
	end

	painting = false
	Window.PaintMap()
	Window.PaintDrops()
	Window.PaintFooter()
	return true
end

function Window.PaintFooter()
	local dungeons, bosses, held = Book.Count()
	tally:SetText(("%d dungeons, %d bosses, %d drops"):format(dungeons, bosses, held))
	local refused, waiting = Loot.Tally()
	if refused > 0 then
		reading:SetText(("%d drops the client refused"):format(refused))
	elseif waiting > 0 then
		reading:SetText(("%d drops not cached yet"):format(waiting))
	else
		reading:SetText(ns.DungeonSeen.Describe())
	end
	return true
end

--------------------------------------------------------------------------

function Window.Show()
	Window.Build()
	Window.Paint()
	window:Show()
	return true
end

function Window.Hide()
	if not window then
		return false
	end
	window:Hide()
	return true
end

function Window.Shown()
	return window ~= nil and window:IsShown()
end

function Window.Toggle()
	if Window.Shown() then
		return Window.Hide()
	end
	return Window.Show()
end

-- Redrawn only while it is up. The ledger changes every time you open a loot
-- window, and repainting three columns for a window nobody has open is the
-- waste this addon has a gate for.
function Window.Refresh()
	if Window.Shown() then
		return Window.Paint()
	end
	return false
end

--------------------------------------------------------------------------

-- One notch of the wheel, from outside. Handed out for the reason the quest
-- log's is: a zoom that did not move, or moved past its own far end, is a claim
-- scripts/harness.lua has to be able to make, and the alternative is this file
-- handing out a reference to the chart's own pools.
function Window.Zoom(delta)
	if not board then
		return 1
	end
	if delta then
		board:Zoom(delta, 0.5, 0.5)
	end
	return board:Level()
end

-- How many marks are on the board, and how big it came out.
function Window.Drawn()
	if not board then
		return 0, 0, 0
	end
	return board:Drawn()
end

-- Which boss is selected, as the creature id, and which dungeon holds it.
function Window.Showing()
	local dungeon, boss, order = Chosen()
	if not boss then
		return nil
	end
	return boss.id, dungeon.name, order
end

-- Where the column is pointing, so a caller outside can move it.
function Window.Select(id)
	if not window then
		return false
	end
	local boss = Book.Boss(id)
	if not boss then
		return false
	end
	Select(Book.Key(boss))
	return true
end

-- Which floor the map is on, and how many there are. Handed out for the reason
-- Zoom is: the floors come out of the client's own group tables, so a strip
-- that offered one floor where the dungeon has four looks exactly like a
-- dungeon that has one.
function Window.Floor(index)
	if index then
		floorAt = index
		Window.PaintMap()
	end
	local dungeon = (Chosen())
	return floorAt, #Sheets(dungeon)
end

-- What the two lines along the bottom and the line under the map say. Handed
-- out for the reason the world map's are: the sentence under the picture is the
-- one thing on this window that is a claim rather than a drawing, and a claim
-- has to be checkable from outside.
function Window.Says()
	if not note then
		return "", "", ""
	end
	return note:GetText() or "", tally:GetText() or "", reading:GetText() or ""
end

function Window.Built()
	return window ~= nil
end

function Window.Describe()
	if not ns.db.dungeons then
		return "off"
	end
	if not window then
		return "not built yet"
	end
	return Window.Shown() and "open" or "closed"
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
-- An item the client had not cached when the column was drawn, arriving. The
-- right hand column is mostly items you have never seen, so on the first open
-- of a dungeon this fires a dozen times and each one is a row that stops being
-- the quiet colour.
pcall(events.RegisterEvent, events, "GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		if ns.db.dungeons then
			Window.Build()
		end
		ns.DungeonKey.Apply()
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		-- The tree walked again on the far side of a loading screen. It is
		-- built out of a client that answers nothing useful until the world is
		-- in, and unlike the world map's column nothing here is numbered by it:
		-- the rows are the book's rows, so a second walk costs a repaint and
		-- renumbers nothing.
		Places.Forget()
	end
	Window.Refresh()
end)

UI.OnRescale(function()
	if not window then
		return
	end
	-- The two lines every window in the addon carries, and todo.md item 19 is
	-- the note asking for them to move into UI.Window. Written the same way as
	-- the other four so that when they do move, five identical pairs come out
	-- rather than four and an exception.
	UI.Rezoom(window.frame, UI.WindowZoom())
	window.zoom = UI.WindowZoom()
	Window.Fit()
	Window.Refresh()
end)
