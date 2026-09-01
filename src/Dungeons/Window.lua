local ADDON, ns = ...

local Window = {}
ns.DungeonWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric
local Chart = UI.Chart
local Book, Places, Loot = ns.DungeonBook, ns.DungeonPlaces, ns.DungeonLoot
local Shelf = ns.DungeonShelf

--------------------------------------------------------------------------
-- The adventure guide
--
-- Two pages in one window. The front page is a shelf of cards, one per dungeon,
-- each wearing a painting of the place; click one and the window becomes that
-- dungeon, in the three columns a log has always had. Right click anywhere and
-- you are back on the shelf.
--
-- **Why two pages and not one column.** This window used to be a single page
-- with every boss in the game down its left edge: forty headers and two hundred
-- and thirty seven rows, drawn all at once on the argument that the question
-- anybody opens it with is "what should I be running now", and that is a
-- question about the whole list rather than about one dungeon.
--
-- The argument was right and the column was the wrong answer to it. Four
-- screens of scrolling, of which the thirty six lines that answer the question
-- are headers and the rest are names of bosses inside dungeons nobody has
-- chosen yet. A name is the thinnest description of a place there is, and the
-- middle and right columns spent the whole time showing one boss out of two
-- hundred that you had to reach the row of before you could see.
--
-- So the whole list is still the front page, and it is now a page of pictures.
-- Dungeons/Shelf.lua carries that argument in full.
--
-- **The second page is the window this used to be, minus the part that was
-- wrong.** Same three columns, same widths, the same scrolling list on the left
-- and the same item rows on the right, which is the quest log's shape and is
-- deliberate: a player who has learned one window has learned this one. What
-- changed is that the left column holds one dungeon's bosses instead of every
-- dungeon's, because the page you are on has already said which dungeon.
--
-- **The middle is the client's own map with the bosses on it.** The picture is
-- UI/Chart.lua, the same widget the quest log's map and the world map are drawn
-- on, and the marks are numbered squares matching the numbers down the left. A
-- dungeon is cut into floors and the strip under the map steps between them,
-- which is the same strip the quest log puts under a quest that spans two
-- zones.
--
-- **Nothing on the picture is invented, and that is the one thing to know about
-- this window.** No database on either client says where a boss stands inside
-- an instance; Questie, which knows where every creature in the outdoor world
-- is, files them all at {-1, -1}. So a mark appears the first time you loot
-- that boss, from where you were standing, and a dungeon you have never run
-- draws its map with no marks on it and a line underneath saying so.
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
-- **Right click is the way back, and it is not the only way back.** The gesture
-- is the world map's own: UI/Chart.lua has always stepped out of a picture on a
-- right click, and this window is the second reader of that. But a gesture
-- nothing on the screen mentions is a gesture half the people who use this will
-- never find, so there is also a button that says what it does. The gesture is
-- the shortcut and the button is the affordance, which is the way round those
-- two belong.
--
-- **Everything is built once.** The shelf holds a pool of cards, the list a
-- pool of rows, the board a pool of tiles and marks, and this client cannot
-- destroy a frame, so a window that rebuilt any of them on a click would leak a
-- dungeon's worth of frames per click all evening. It is the same argument the
-- quest log's two scrolling columns make one file across.
--------------------------------------------------------------------------

-- The window, sized for the picture in the middle of it.
--
-- It was 860 by 540, and at that size the two fixed columns and the four
-- margins took 518 of the width and the map got the 342 that were left. A
-- dungeon's art is 1002 by 668, so the picture was drawn at a third of the size
-- it was painted at: a room was about forty pixels across and the numbered mark
-- standing in it was sixteen. The one thing on the page you cannot read the
-- answer off in words was the smallest thing on it.
--
-- These numbers are what it takes for the map to be 662 wide, which is two
-- thirds of the art and close to twice what it was. The height is set to just
-- over what that shape asks for so the wheel still has a notch or two of room
-- to spend, and Window.Fit does that arithmetic rather than this comment: the
-- board is handed what is left after the heading, the floor strip and the two
-- lines of the sentence underneath.
--
-- Wider than the quest log at 810 and narrower than the world map at 1218,
-- which is the right place for it: the quest log's middle column is text, and
-- the world map draws a zone at the full size Blizzard draws one.
local WIDTH, HEIGHT = 1180, 660

-- The two fixed columns of the second page, the same numbers the quest log
-- uses. The middle takes whatever is left, which is the way round it has to be:
-- a dungeon name and an item name have a length the font decides, and a map
-- does not.
local LIST, DROPS = 250, 220

-- The button that goes back to the shelf, over the left column.
--
-- A word rather than a mark. Media/Glyphs.ttf carries a chevron pointing right
-- and none pointing left, and a back button is not worth re-cutting a font
-- over: "All dungeons" says where the press lands, which no arrow does.
local BACK, BACK_LABEL = 96, "All dungeons"

-- How much of the left column the button and the air under it take.
local UNDER = M.control + M.rowGap

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
local shelf, sheet

-- Which dungeon is open, as the table out of the book, and which of its bosses
-- is selected, as the creature id in a string. Both nothing while the shelf is
-- the page, which is what says which page is up: a window with no dungeon open
-- is the shelf, and there is no second flag to disagree with it.
local place = nil
local showing = nil

-- Which floor of that dungeon the map is on.
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
-- and the enemy bars colour a mob with. A column that says "this one will kill
-- you" in colour is a column you can read without reading.
--
-- WorthOf rather than Worth, because a boss in a book is a level and not a unit
-- standing anywhere. Unit/Level.lua's header carries the split.
local function Tint(boss)
	return ns.Unit.Level.WorthOf(boss.level)
end

-- What the heading over the map says: the dungeon's name and the levels it is
-- for. The same line the card on the shelf carried, so that clicking a card
-- lands on a page that still says what you clicked.
local function Header(dungeon)
	if dungeon.low == dungeon.high then
		return ("%s  %d"):format(dungeon.name, dungeon.low)
	end
	return ("%s  %d-%d"):format(dungeon.name, dungeon.low, dungeon.high)
end

-- What the left column holds, as the rows UI.List draws: the bosses of the
-- dungeon that is open, in the order they are fought, and nothing at all while
-- the shelf is the page.
--
-- Public for the reason the quest log's are: the harness has to be able to
-- measure what was drawn, and the alternative is this file handing out a
-- reference to the list widget itself.
function Window.Rows()
	local rows = {}
	if not place then
		return rows
	end
	for order, boss in ipairs(place.bosses) do
		local placed = Book.Where(boss.id) ~= nil
		rows[#rows + 1] = {
			id = Book.Key(boss),
			label = Label(order, boss),
			color = Tint(boss),
			-- The tick says you have looted this one, which is the same thing
			-- as saying it is on the map. It keeps its own colour through the
			-- selection, for the reason the quest log's does: the row you are
			-- reading must not be the row that says least.
			mark = placed and TICK or nil,
			markColor = C.tick,
		}
	end
	return rows
end

--------------------------------------------------------------------------
-- The middle
--------------------------------------------------------------------------

-- Which dungeon and which boss the column is pointing at.
local function Chosen()
	if not place or not showing then
		return place, nil, nil
	end
	local boss, dungeon, order = Book.Found(showing)
	return dungeon or place, boss, order
end

-- Every floor of the dungeon being drawn, each one a map id, a name and a
-- picture.
--
-- Nothing at all where nothing has a picture for the place, which is a real
-- answer rather than a failure: the left and right columns are the whole of
-- what a dungeon page is for and both work without one.
local function Sheets(dungeon)
	if not dungeon then
		return {}
	end
	return Places.Floors(dungeon.name)
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
		return ("There is no picture of %s, so its bosses are the column on the left.")
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
		local floor = sheets[index]
		floors:SetLabel(index, floor and floor.name or "")
		floors:SetShown(index, floor ~= nil)
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

	local floor = sheets[floorAt]
	local points = (dungeon and floor)
		and Points(dungeon, floor.map, boss and boss.id or -1) or {}
	local drawn = board:Draw(floor and floor.map, points, floor and floor.sheet)
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

	-- A row with a link answers the mouse, which means it is also the thing
	-- under the cursor when somebody right clicks to leave the page. So it
	-- carries the way back too, for the reason every other mouse-enabled part
	-- of this page does: a gesture that works on three quarters of a window is
	-- a gesture nobody trusts.
	row:SetScript("OnMouseUp", function(_, which)
		if which == "RightButton" then
			Window.Back()
		end
	end)

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
-- The front page
--------------------------------------------------------------------------

function Window.PaintShelf()
	if not shelf then
		return false
	end
	shelf.view:Update(Shelf.Paint(shelf.view.width or 0))
	return true
end

--------------------------------------------------------------------------
-- Which page is up
--------------------------------------------------------------------------

-- Which boss a dungeon's page lands on, which is the first one it lists.
--
-- The first rather than the one you have not killed. A boss list is the order
-- you fight them in, the page is read from the top, and "where you got to last
-- time" is a guess this addon would have to be right about every time to be
-- worth making once.
local function First(dungeon)
	local boss = dungeon and dungeon.bosses[1]
	return boss and Book.Key(boss) or nil
end

-- Open one dungeon's page. The first boss is selected rather than none, because
-- a page whose middle and right columns both say "nothing selected" is a page
-- that looks like it failed to load.
function Window.Open(dungeon)
	if not dungeon then
		return false
	end
	place = dungeon
	showing = First(dungeon)
	floorAt = 1
	Window.Paint()
	return true
end

-- Open the dungeon you are standing in, on the floor you are standing on.
--
-- A window that opens on the shelf while you are in the Deadmines is a window
-- asking you which dungeon you are in. The world map has landed on the zone you
-- are in since it was written and this is the same move, one floor further
-- down; Dungeons/Here.lua is the part that answers where you are, and it
-- answers nothing at all outdoors and nothing at all on the vanilla client.
--
-- The floor is set after the page is drawn rather than before, because opening
-- a dungeon selects its first boss and the page then steps to the floor that
-- boss was looted on. Where you are standing is the better answer of the two,
-- so it is the one that lands last.
function Window.Land()
	local dungeon, floor = ns.DungeonHere.Dungeon()
	if not dungeon then
		return false
	end
	Window.Open(dungeon)
	if floor then
		floorAt = floor
		Window.PaintMap()
	end
	return true
end

-- Back to the shelf. Nothing about the dungeon is kept, which is deliberate:
-- coming back to a page you left is a nice thing for a window you leave by
-- accident, and this one is left on purpose, by a gesture that means "show me
-- the others".
function Window.Back()
	if not place then
		return false
	end
	place = nil
	showing = nil
	floorAt = 1
	Window.Paint()
	return true
end

-- Which page is up, as a word, so that everything else in this file and the
-- harness can ask one question rather than test a variable for nil.
function Window.Page()
	return place and "dungeon" or "shelf"
end

--------------------------------------------------------------------------
-- The whole window
--------------------------------------------------------------------------

local function Select(key)
	if painting then
		return
	end
	showing = key
	-- The floor goes back to the first, because floor three of the last boss's
	-- map is nothing at all under this one. It is moved again below to whichever
	-- floor the boss was last seen on, where there is one.
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
	for index, floor in ipairs(Sheets(dungeon)) do
		if floor.map == map then
			return index
		end
	end
	return 1
end

local function Chrome()
	local HALF = M.pad / 2

	sheet.leftRule = UI.Rule(sheet, C.hairline, true)
	sheet.leftRule:SetPoint("TOPLEFT", list.frame, "TOPRIGHT", HALF, 0)
	sheet.leftRule:SetPoint("BOTTOMLEFT", list.frame, "BOTTOMRIGHT", HALF, 0)

	sheet.rightRule = UI.Rule(sheet, C.hairline, true)
	sheet.rightRule:SetPoint("TOPRIGHT", drops.frame, "TOPLEFT", -HALF, 0)
	sheet.rightRule:SetPoint("BOTTOMRIGHT", drops.frame, "BOTTOMLEFT", -HALF, 0)

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

	-- The shelf takes the whole content area. It is one thing rather than three
	-- columns, so there is nothing here to divide up: the card width comes out
	-- of the view's own width in Dungeons/Shelf.lua, which is where the
	-- arithmetic that decides how many fit belongs.
	shelf.frame:SetSize(WIDTH - M.pad * 2, body)
	shelf.view:Resize(WIDTH - M.pad * 2, body)

	-- The list starts under the button, so the button's height and the gap over
	-- it come out of the column's own height rather than off the bottom of the
	-- window. Its anchor is set once where it is built; a point written again on
	-- every resize is a second point, not a moved one.
	list:Resize(LIST, body - UNDER)

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

-- The second page, built once. Everything on it is parented to one frame so
-- that changing page is two calls rather than nine, and so that a part added
-- here later cannot be the one somebody forgets to hide.
local function BuildSheet()
	sheet = CreateFrame("Frame", nil, window.content)
	sheet:SetAllPoints()

	-- Named for the reason the two scrolling columns and the board are: a
	-- button that draws correctly and answers no press is invisible to
	-- everything except a person clicking it, and scripts/harness.lua has to be
	-- able to press this one.
	local button = UI.Button(sheet, { name = "WarriorKitDungeonBack",
		label = BACK_LABEL, width = BACK,
		onClick = function() Window.Back() end })
	button:SetPoint("TOPLEFT", M.pad, -M.pad)

	list = UI.List(sheet, {
		name = "WarriorKitDungeonList",
		onSelect = Select,
		onBack = function() Window.Back() end,
		marks = true,
	})
	list.frame:SetPoint("TOPLEFT", M.pad, -(M.pad + UNDER))

	heading = UI.Label(sheet, M.heading, C.heading, "LEFT", UI.FLAT)
	heading:SetPoint("TOPLEFT", list.frame, "TOPRIGHT", M.pad, 0)
	UI.Wrap(heading, false)

	-- Named for the reason the quest log's board is: what it draws is twelve
	-- tiles of the client's own art with numbered marks over them, and a map
	-- with a seam through it or a mark in the wrong place is only findable from
	-- outside if the tiles and the marks can be walked one at a time.
	--
	-- The fourth argument is the map's own step-out gesture, which every other
	-- board in the addon uses to leave a zone for the continent it is on. Here
	-- it leaves a dungeon for the shelf, which is the same move.
	board = Chart.New(sheet, "WarriorKitDungeonChart", nil, function()
		Window.Back()
	end)
	board.frame:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -M.rowGap)

	-- The strip is anchored under the board rather than measured, so a floor
	-- whose art is a different shape moves the line below it without anything
	-- here having to know the height.
	floors = UI.TabStrip(sheet, { onSelect = function(index)
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

	note = UI.Label(sheet, M.small, C.quiet, "LEFT", UI.FLAT)
	note:SetPoint("TOPLEFT", floors.frame, "BOTTOMLEFT", 0, -M.gutter)
	UI.Wrap(note, true)
	note:SetSpacing(2)

	drops = { pool = {}, at = 0 }
	drops.frame = CreateFrame("Frame", "WarriorKitDungeonDrops", sheet)
	drops.view = UI.ScrollView(drops.frame)
	drops.view.frame:SetPoint("TOPLEFT")
	drops.stack = UI.Stack(drops.view.canvas)
	drops.frame:SetPoint("TOPRIGHT", -M.pad, -M.pad)
end

function Window.Build()
	if window then
		return window
	end

	window = UI.Window({
		name = "WarriorKitDungeons",
		title = "Adventure Guide",
		width = WIDTH,
		height = HEIGHT,
	})
	ns.Remember(window)

	-- The way back, over whatever part of the window the pointer happens to be
	-- on. Every mouse-enabled thing inside it carries the gesture too, because a
	-- frame that answers the mouse is a frame the window behind it never hears
	-- from; this is what covers the margins, the air between the columns and the
	-- footer. On the way up rather than the way down, so a press that turned
	-- into a drag of the window is not also a page change.
	window.frame:SetScript("OnMouseUp", function(_, which)
		if which == "RightButton" then
			Window.Back()
		end
	end)

	shelf = { frame = CreateFrame("Frame", "WarriorKitDungeonShelf", window.content) }
	shelf.frame:SetPoint("TOPLEFT", M.pad, -M.pad)
	shelf.view = UI.ScrollView(shelf.frame)
	shelf.view.frame:SetPoint("TOPLEFT")
	Shelf.Attach(shelf.view.canvas, Window.Open)

	BuildSheet()
	Chrome()
	Window.Fit()
	return window
end

--------------------------------------------------------------------------

function Window.Paint()
	if not window or painting then
		return false
	end
	painting = true

	local open = place ~= nil
	shelf.frame:SetShown(not open)
	sheet:SetShown(open)

	list:Set(Window.Rows())
	if open then
		if not showing or not Book.Found(showing) then
			showing = First(place)
		end
		list:Select(showing)
	end

	local dungeon, boss = Chosen()
	heading:SetText(dungeon and Header(dungeon) or "")
	if dungeon and floorAt == 1 then
		floorAt = FloorOf(dungeon, boss)
	end

	painting = false
	if open then
		Window.PaintMap()
		Window.PaintDrops()
	else
		Window.PaintShelf()
	end
	Window.PaintFooter()
	return true
end

function Window.PaintFooter()
	local dungeons, bosses, held = Book.Count()
	tally:SetText(("%d dungeons, %d bosses, %d drops"):format(dungeons, bosses, held))
	if not place then
		reading:SetText("Pick a dungeon.")
		return true
	end
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

-- Landing first, and only painting where nothing was landed on, which is the
-- shape Map/Window.lua opens in: Window.Land draws the page it lands on, and a
-- second paint over the top of it would be a dungeon's worth of work to arrive
-- at the picture already on the screen.
function Window.Show()
	Window.Build()
	if not Window.Land() then
		Window.Paint()
	end
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

-- Where the column is pointing, so a caller outside can move it. Opens the
-- dungeon that boss is in where the shelf is the page, because a caller asking
-- for a boss is asking for the page that boss is on.
function Window.Select(id)
	if not window then
		return false
	end
	local boss, dungeon = Book.Boss(id)
	if not boss then
		return false
	end
	if place ~= dungeon then
		Window.Open(dungeon)
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
	if not Window.Shown() then
		return "closed"
	end
	if not place then
		return "open on the shelf"
	end
	return ("open on %s"):format(place.name)
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
		-- The floors built again on the far side of a loading screen. They come
		-- out of a baked table and cannot have changed, so this costs a repaint
		-- and is kept for the one thing that can: a reload with a different
		-- table under it.
		Places.Forget()
		-- The loading screen you have just come through may have been the way
		-- into a dungeon, and a window left open across one is a window on the
		-- place you were standing before it. So it lands again, for the reason
		-- it lands when it opens: the page you want is the one you are in.
		if Window.Shown() and Window.Land() then
			return
		end
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
