-- The layout engine
--
-- ns.UI.Flow, on its own, before anything that is built out of it. Every
-- number below is a rectangle the engine worked out, read back off the offsets
-- it wrote, because that is the whole of what it promises: hand it a tree and
-- every frame in it lands where the tree says.
--
-- Worth gating separately from the widgets. A layout bug inside the enemy bars
-- shows up as one failing assertion about a debuff square and takes an hour to
-- trace back to the arithmetic; the same bug here names itself.

local H = ...
local region, ns, check = H.region, H.ns, H.check

local function Cell()
	return region("frame", _G.UIParent)
end

local root = Cell()
ns.UI.Adopt(root)
local px = ns.UI.Pixel(root)
local Flow = ns.UI.Flow

-- Where a frame ended up, in root units, from the offset Flow wrote on it.
local function At(frame)
	local _, _, _, x, y = frame:GetPoint()
	return (x or 0) / px, -(y or 0) / px
end

local function near(got, want, what)
	check(math.abs(got - want) < 1e-9,
		("flow: %s is %.2f, expected %.2f"):format(what, got, want))
end

-- A column, stretched across, which is the shape of every stacked readout
-- in the addon.
do
	local a, b, c = Cell(), Cell(), Cell()
	Flow.Arrange(root, {
		direction = "column", gap = 2 * px, align = "stretch", width = 100 * px,
		{ frame = a, height = 10 * px },
		{ frame = b, height = 20 * px },
		{ frame = c, height = 5 * px },
	})
	near(root:GetHeight() / px, 39, "the column's height")
	near(select(2, At(a)), 0, "the first row's top")
	near(a:GetWidth() / px, 100, "a stretched row's width")
	near(select(2, At(b)), 12, "the second row's top")
	near(select(2, At(c)), 34, "the third row's top")
end

-- One child growing into what the others left, which is how a label takes
-- the room beside a fixed control.
do
	local a, b = Cell(), Cell()
	Flow.Arrange(root, {
		direction = "row", gap = 4 * px, width = 100 * px, height = 20 * px,
		{ frame = a, width = 10 * px, grow = 1 },
		{ frame = b, width = 30 * px },
	})
	near(a:GetWidth() / px, 66, "the growing child took the slack")
	near(At(b), 70, "the fixed child sits after it")
end

-- Packed to the far end, and run backwards, which is what mirroring a
-- layout is and nothing else.
do
	local a, b = Cell(), Cell()
	Flow.Arrange(root, {
		direction = "row", gap = 4 * px, width = 100 * px, height = 20 * px,
		justify = "end",
		{ frame = a, width = 10 * px },
		{ frame = b, width = 20 * px },
	})
	near(At(a), 66, "justify end: the first child")
	near(At(b), 80, "justify end: the last child ends flush")

	local c, d = Cell(), Cell()
	Flow.Arrange(root, {
		direction = "row", gap = 4 * px, width = 100 * px, height = 20 * px,
		reverse = true,
		{ frame = c, width = 10 * px },
		{ frame = d, width = 20 * px },
	})
	near(At(d), 0, "reversed: the last child leads")
	near(At(c), 24, "reversed: the first child follows")
end

-- Centred across the axis its container runs along.
do
	local a = Cell()
	Flow.Arrange(root, {
		direction = "row", width = 100 * px, height = 20 * px,
		{ frame = a, width = 10 * px, height = 6 * px, align = "center" },
	})
	near(select(2, At(a)), 7, "a centred child's top")
end

-- The wrapping row, right aligned, growing upwards, which is the debuff row
-- on an enemy bar. Five 20 wide squares with a 4 gap in a 70 wide row: three
-- fit on the line nearest the gauge and two wrap above it.
do
	local squares = {}
	local icons = { direction = "row", wrap = true, justify = "end",
		lineOrder = "up", gap = 4 * px, width = 70 * px, alignY = "end" }
	for index = 1, 5 do
		squares[index] = Cell()
		icons[index] = { frame = squares[index], width = 20 * px, height = 20 * px }
	end

	local lines = Flow.Lines(icons)
	check(#lines == 2, ("flow: the row broke into %d lines, expected 2"):format(#lines))
	near(lines[1].main / px, 68, "the first line's width")

	-- The line nearest the gauge is full and the tail hangs above it, so a
	-- text node beside it is sized against the first line and not the row.
	local text = Cell()
	Flow.Arrange(root, {
		direction = "stack", width = 70 * px,
		{ frame = text, width = 70 * px - lines[1].main, height = 20 * px,
			alignX = "start", alignY = "end" },
		icons,
	})
	near(root:GetHeight() / px, 44, "the stack is as tall as its tallest child")
	near(select(2, At(text)), 24, "the text sits on the line nearest the gauge")
	near(select(2, At(squares[1])), 24, "and so does the first square")
	near(At(squares[1]), 2, "the full line is packed right")
	near(At(squares[3]) + 20, 70, "the last square on it ends flush")
	near(select(2, At(squares[4])), 0, "the wrapped line is above")
	near(At(squares[4]) + 20 + 4 + 20, 70, "and is packed right too")
end

-- The same shape said as one direction rather than three fields. "left up" is
-- reverse, justify end and lineOrder up: the first square sits at the right
-- edge, the line runs leftward from it, and the tail hangs above, starting
-- from the right edge too. That last part is the half reverse on its own got
-- wrong, and it is the player's buff row. "right down" is the target's.
do
	local function build(flow)
		local squares = {}
		local icons = { direction = "row", wrap = true, flow = flow,
			gap = 4 * px, width = 70 * px }
		for index = 1, 5 do
			squares[index] = Cell()
			icons[index] = { frame = squares[index], width = 20 * px, height = 20 * px }
		end
		Flow.Arrange(root, icons)
		return squares, icons
	end

	local squares, icons = build("left up")
	check(icons.reverse == true and icons.justify == "end" and icons.lineOrder == "up",
		"flow: left up did not write the three fields it stands for")
	near(select(2, At(squares[1])), 24, "flow left up: the first square is on the bottom line")
	near(At(squares[1]) + 20, 70, "flow left up: the first square starts at the right edge")
	near(At(squares[3]), 2, "flow left up: the third square ends the line on the left")
	near(select(2, At(squares[4])), 0, "flow left up: the tail is above")
	near(At(squares[4]) + 20, 70, "flow left up: the tail starts at the right edge too")
	near(At(squares[5]), 26, "flow left up: the tail's second square follows leftward")

	squares = build("right down")
	near(select(2, At(squares[1])), 0, "flow right down: the first square is on the top line")
	near(At(squares[1]), 0, "flow right down: the full line starts at the left edge")
	near(At(squares[3]), 48, "flow right down: the third square follows")
	near(select(2, At(squares[4])), 24, "flow right down: the tail is below")
	near(At(squares[4]), 0, "flow right down: the tail is packed left")

	-- A word the axis cannot take is a mistake at the call site, and it is
	-- said there rather than drawn as a row that runs the default way.
	check(not pcall(Flow.Arrange, root, { direction = "column", flow = "left" }),
		"flow: a column was allowed to flow left")
	check(not pcall(Flow.Arrange, root, { direction = "row", flow = "left up" }),
		"flow: a row that does not wrap was allowed to say which way its lines stack")
end

-- A node that is not drawn takes no room, which is what every setting that
-- hides one row of a widget relies on.
do
	local a, b, c = Cell(), Cell(), Cell()
	Flow.Arrange(root, {
		direction = "column", gap = 2 * px, width = 50 * px,
		{ frame = a, height = 10 * px },
		{ frame = b, height = 20 * px, skip = true },
		{ frame = c, height = 10 * px },
	})
	near(root:GetHeight() / px, 22, "the height ignores the skipped node")
	near(select(2, At(c)), 12, "the row after it moved up")
end

print("flow   column, row, grow, justify, reverse, align, wrap up, flow, stack, skip")
