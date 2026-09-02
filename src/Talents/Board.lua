local ADDON, ns = ...

local Board = {}
ns.TalentBoard = Board
Board.__index = Board

local UI = ns.UI
local C, M = UI.Color, UI.Metric
local Read = ns.TalentRead

--------------------------------------------------------------------------
-- One tree, drawn
--
-- A heading with the tree's icon, its name and the points in it, and under it
-- a grid of squares: one per talent, at the tier and column the client places
-- it, with the lines between a talent and whatever it needs first.
--
-- **It is the bag window's square.** UI/Slot.lua's, with the count in the
-- corner reading `3/5` rather than a stack, because a talent is a picture with
-- a number on it the same as an item is and a window where the two differ by a
-- pixel of inset is the defect that file exists to stop. The rim carries the
-- state: gold once every rank is in, green while a point would land here, the
-- theme's edge for a talent half filled and nothing to fill it with, and the
-- hairline for one you cannot reach yet, whose picture is greyed the way the
-- client greys it.
--
-- **The lines are drawn, not pasted.** Blizzard's are cut from a sheet of
-- textures, thirty of them per frame, walked by a routine that keeps a grid of
-- which cell has which stub of art. This draws each requirement as one or two
-- flat rectangles, two pixels wide, in the tick colour when the requirement is
-- met and the quiet grey when it is not. The routing is the client's own: down
-- the column for a talent under its requirement, along the row for one beside
-- it, and for a diagonal pair over first and then down, unless a talent is in
-- the way, in which case down first and then over. Nothing points: every line
-- runs from a talent to the one it opens, and that is always downward or
-- sideways, so an arrowhead would be saying what the geometry already says.
--
-- **The requirement is worked out here, off the ranks.** The client answers a
-- flag for it, in a different slot on each of the two builds this addon runs
-- on, and a flag read from the wrong slot is a rim the wrong colour on every
-- square in the window. The board already holds every square in the tree, so
-- it asks which square a talent needs and whether that square is full, which
-- cannot be in the wrong slot.
--
-- **Everything is built once and pooled.** Squares are made as the tree first
-- needs them and hidden past the count on every paint after; the lines are a
-- second pool on the same grid. This client cannot destroy a frame, and a
-- board that rebuilt on every point spent would leak a tree per level.
--
-- Nothing here is on a ticker. A board is painted when the window opens, when
-- a point is spent, when a level lands and when the other spec is chosen, and
-- not otherwise.
--------------------------------------------------------------------------

-- One square, the air between two, and how many across. Thirty one is the bag
-- window's square and the argument for it is in UI/Slot.lua: twenty seven
-- pixels of picture inside a two pixel inset is one of the two sizes an icon
-- is drawn at exactly. Sixteen between them is room for a line and for the
-- lines not to read as a rim on the square below.
local SQUARE, GAP, COLUMNS = UI.SLOT, 16, 4
local PITCH = SQUARE + GAP

-- The heading row: the tree's icon, at the other exact icon size, and the name
-- beside it.
local HEAD = 27

-- A line between two talents, in pixels.
local LINE = 2

Board.SQUARE, Board.GAP, Board.PITCH, Board.HEAD = SQUARE, GAP, PITCH, HEAD

function Board.Width()
	return COLUMNS * SQUARE + (COLUMNS - 1) * GAP
end

-- How tall a board with this many tiers is, heading included.
function Board.Height(tiers)
	tiers = math.max(1, tiers or 1)
	return HEAD + M.gutter + tiers * SQUARE + (tiers - 1) * GAP
end

--------------------------------------------------------------------------
-- Geometry, in the grid's own units. Every y is negative going down, which is
-- the way an anchor off TOPLEFT counts.
--------------------------------------------------------------------------

local function CellX(column)
	return (column - 1) * PITCH
end

local function CellY(tier)
	return -(tier - 1) * PITCH
end

-- Where a line through the middle of a column or a tier sits: the square's
-- edge plus half of what is left once the line's own width is taken off.
local function LineX(column)
	return CellX(column) + math.floor((SQUARE - LINE) / 2)
end

local function LineY(tier)
	return CellY(tier) - math.floor((SQUARE - LINE) / 2)
end

--------------------------------------------------------------------------
-- The hover and the press
--------------------------------------------------------------------------

-- What this square has to say beyond the client's own description, which is
-- the state: full, reachable, or what stands in the way. One line, worded as
-- the thing to do where there is one.
local function State(square)
	local board = square.board
	if square.max > 0 and square.rank >= square.max then
		return { "Every rank learned", color = C.heading }
	end
	if not board.live then
		return { "Points go into the spec you are standing in. Activate this one to spend here.", color = C.dim }
	end
	if not square.unlocked then
		return { ("Needs %d points in %s first"):format((square.tier - 1) * Read.PER_TIER, board.treeName or "this tree"),
			color = C.dim }
	end
	if not square.met then
		local names = {}
		for index = 1, #square.needs do
			names[#names + 1] = square.needs[index].name
		end
		return { ("Needs every rank of %s first"):format(table.concat(names, " and ")), color = C.dim }
	end
	if board.unspent < 1 then
		return { "No points to spend", color = C.dim }
	end
	return { "Click to put a point here", color = C.hint }
end

local function Subject(square)
	local board = square.board
	local first, second = Read.TipArgs(board.tab, square.index, square.id, square.name)
	local lines = { { ("Rank %d of %d"):format(square.rank, square.max) }, State(square) }
	return { kind = "talent", tab = first, index = second, title = square.name, lines = lines }
end

local function OnEnter(square)
	UI.Tint(square.bg, C.hover)
	ns.Tip.Open(square, Subject(square), nil, UI.Tooltip.BESIDE)
end

local function OnLeave(square)
	UI.Tint(square.bg, C.sunken)
	ns.Tip.Close()
end

-- A press spends a point, and only where one would land. Everything the
-- tooltip says stands in the way is refused here without a word, because the
-- word is already on the hover and a square that argues back on every press is
-- the client's own error text drawn twice.
local function OnClick(square)
	if not square.learnable then
		return false
	end
	local board = square.board
	return Read.Learn(board.tab, square.index, board.group)
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

function Board.New(parent)
	local board = setmetatable({ squares = {}, lines = {}, cells = {}, tiers = 1 }, Board)

	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(Board.Width(), Board.Height(1))
	board.frame = frame

	board.icon = UI.Icon(frame, "ARTWORK")
	board.icon:SetSize(HEAD, HEAD)
	board.icon:SetPoint("TOPLEFT")

	board.name = UI.Label(frame, M.heading, C.heading, "LEFT", UI.FLAT)
	UI.Wrap(board.name, false)
	board.name:SetPoint("LEFT", board.icon, "RIGHT", M.gutter, 0)

	board.points = UI.Label(frame, M.font, C.dim, "RIGHT", UI.FLAT)
	UI.Wrap(board.points, false)
	board.points:SetPoint("RIGHT", frame, "TOPRIGHT", 0, -math.floor(HEAD / 2))

	board.grid = CreateFrame("Frame", nil, frame)
	board.grid:SetPoint("TOPLEFT", 0, -(HEAD + M.gutter))
	board.grid:SetSize(Board.Width(), SQUARE)

	return board
end

local function Square(board, index)
	local square = board.squares[index]
	if square then
		return square
	end
	square = CreateFrame("Button", nil, board.grid)
	square:SetSize(SQUARE, SQUARE)
	UI.Dress(square, SQUARE)
	square.board = board
	square.needs = {}
	square:RegisterForClicks("LeftButtonUp")
	square:SetScript("OnEnter", OnEnter)
	square:SetScript("OnLeave", OnLeave)
	square:SetScript("OnClick", OnClick)
	UI.PassCamera(square)
	board.squares[index] = square
	return square
end

-- One flat rectangle out of the pool, placed and coloured.
local function Segment(board, used, x, y, width, height, met)
	used = used + 1
	local line = board.lines[used]
	if not line then
		line = ns.Fill(board.grid, "ARTWORK", 1, 1, 1, 1)
		board.lines[used] = line
	end
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", x, y)
	line:SetSize(math.max(1, width), math.max(1, height))
	UI.Tint(line, met and C.tick or C.quiet)
	line:Show()
	return used
end

-- Whether a talent sits in any cell of one tier strictly between two columns,
-- plus the corner cell itself, which is the client's own test for a line that
-- cannot take the short way round.
local function Blocked(cells, tier, from, to, corner)
	local row = cells[tier]
	if not row then
		return false
	end
	local left, right = math.min(from, to), math.max(from, to)
	for column = left + 1, right - 1 do
		if row[column] then
			return true
		end
	end
	return row[corner] ~= nil
end

-- The route from a requirement to the talent it opens, as one or two segments.
local function Route(board, used, from, to, met)
	local pt, pc = from.tier, from.column
	local tt, tc = to.tier, to.column
	if pc == tc then
		-- Straight down the column, from under one square to the top of the
		-- other.
		return Segment(board, used, LineX(pc), CellY(pt) - SQUARE, LINE,
			(tt - pt) * PITCH - SQUARE, met)
	end
	if pt == tt then
		-- Along the tier, between the two squares.
		local left, right = math.min(pc, tc), math.max(pc, tc)
		return Segment(board, used, CellX(left) + SQUARE, LineY(pt),
			(right - left) * PITCH - SQUARE, LINE, met)
	end
	-- Diagonal. Over along the requirement's tier to the talent's column, then
	-- down to the talent, unless a talent sits on that row in the way; then
	-- down the requirement's column to the talent's tier and over.
	if not Blocked(board.cells, pt, pc, tc, tc) then
		local x, width
		if pc < tc then
			x = CellX(pc) + SQUARE
			width = LineX(tc) + LINE - x
		else
			x = LineX(tc)
			width = CellX(pc) - x
		end
		used = Segment(board, used, x, LineY(pt), width, LINE, met)
		return Segment(board, used, LineX(tc), LineY(pt), LINE,
			(tt - pt) * PITCH - math.floor((SQUARE - LINE) / 2), met)
	end
	used = Segment(board, used, LineX(pc), CellY(pt) - SQUARE, LINE,
		(tt - pt) * PITCH - SQUARE + math.floor((SQUARE - LINE) / 2) + LINE, met)
	local x, width
	if pc < tc then
		x = LineX(pc)
		width = CellX(tc) - x
	else
		x = CellX(tc) + SQUARE
		width = LineX(pc) + LINE - x
	end
	return Segment(board, used, x, LineY(tt), width, LINE, met)
end

-- The rim, the count and the picture, off what the square now knows about
-- itself.
local function Paint(square)
	local full = square.max > 0 and square.rank >= square.max
	local edge
	if full then
		edge = C.heading
	elseif square.learnable then
		edge = C.tick
	elseif square.rank > 0 then
		edge = C.edge
	else
		edge = C.hairline
	end
	ns.Recolor(square.edges, edge)

	if square.rank > 0 then
		square.tally:SetText(("%d/%d"):format(square.rank, square.max))
	else
		square.tally:SetText("")
	end
	local ink = full and C.heading or C.text
	square.tally:SetTextColor(ink[1], ink[2], ink[3])

	local dim = square.rank == 0 and not square.learnable
	square.art:SetDesaturated(dim)
	square.art:SetAlpha(dim and 0.55 or 1)
	square.dim = dim
end

-- What one square needs first, read off the grid rather than off the client's
-- flag, and the line to each of them drawn. Answers whether every requirement
-- is full and how many line segments the board has used so far.
local function Needs(board, square, used)
	local needs = Read.Prereqs(board.tab, square.index, board.group)
	local met = true
	wipe(square.needs)
	for at = 1, #needs, 2 do
		local row = board.cells[needs[at]]
		local from = row and row[needs[at + 1]]
		if from then
			local full = from.max > 0 and from.rank >= from.max
			if not full then
				met = false
			end
			square.needs[#square.needs + 1] = from
			used = Route(board, used, from, square, full)
		else
			met = false
		end
	end
	return met, used
end

--------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------

local function Points(points)
	if not points or points < 1 then
		return "no points"
	end
	if points == 1 then
		return "1 point"
	end
	return ("%d points"):format(points)
end

-- One tree onto the board. `live` is whether the group being drawn is the one
-- the character is standing in, which is the only one a point can go into.
-- Answers how many squares were drawn and how many tiers they span, which is
-- what the window sizes itself by.
function Board:Set(tab, group, unspent, live)
	self.tab, self.group, self.unspent, self.live = tab, group, unspent or 0, live and true or false

	local name, icon, points = Read.Tree(tab, group)
	self.treeName = name
	self.name:SetText(name or ("Tree %d"):format(tab))
	self.icon:SetTexture(icon)
	self.icon:SetShown(icon ~= nil)
	self.points:SetText(Points(points))
	self.spent = points or 0

	-- First pass: where everything is. The second needs the whole grid before it
	-- can say what any one square needs.
	local count = Read.Count(tab)
	local cells, tiers, shown = {}, 1, 0
	for index = 1, count do
		local talent, art, tier, column, rank, max, id = Read.Talent(tab, index, group)
		if talent then
			local square = Square(self, index)
			square.index, square.name, square.id = index, talent, id
			square.tier, square.column, square.rank, square.max = tier, column, rank, max
			square:ClearAllPoints()
			square:SetPoint("TOPLEFT", CellX(column), CellY(tier))
			square.art:SetTexture(art)
			square.art:SetShown(art ~= nil)
			cells[tier] = cells[tier] or {}
			cells[tier][column] = square
			if tier > tiers then
				tiers = tier
			end
			square:Show()
			shown = shown + 1
		elseif self.squares[index] then
			self.squares[index]:Hide()
		end
	end
	for index = count + 1, #self.squares do
		self.squares[index]:Hide()
	end
	self.cells, self.tiers = cells, tiers

	-- Second pass: what each one needs, whether it has it, and the lines.
	local used = 0
	for index = 1, count do
		local square = self.squares[index]
		if square and square:IsShown() then
			local met
			met, used = Needs(self, square, used)
			square.unlocked = self.spent >= (square.tier - 1) * Read.PER_TIER
			square.met = met
			square.learnable = self.live and square.unlocked and met
				and square.rank < square.max and self.unspent > 0
			Paint(square)
		end
	end
	for index = used + 1, #self.lines do
		self.lines[index]:Hide()
	end
	self.drawn = used

	self.grid:SetSize(Board.Width(), tiers * SQUARE + (tiers - 1) * GAP)
	self.frame:SetHeight(Board.Height(tiers))
	return shown, tiers
end

-- The square at one tier and column, or the one at an index, handed out for
-- the harness and the window rather than answered about. What is checked is
-- the picture: which rim it wears, whether the count reads `3/5`, where the
-- line to it starts. None of that is a boolean this file could compute
-- without computing it the same way twice.
function Board:Square(index)
	return self.squares[index]
end

function Board:At(tier, column)
	local row = self.cells[tier]
	return row and row[column] or nil
end

function Board:Lines()
	return self.drawn or 0
end

function Board:Line(index)
	return self.lines[index]
end
