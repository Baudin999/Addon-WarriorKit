local ADDON, ns = ...

local UI = ns.UI
local Flow = {}
UI.Flow = Flow

--------------------------------------------------------------------------
-- Layout
--
-- A stack panel, in the sense XAML means it and CSS calls a flex container.
-- You describe what goes where and the file works out the offsets.
--
-- It exists because UnitFrames/EnemyBars.lua had a hundred and eighty lines
-- that did it by hand, and the hand-written version has the failure mode every
-- hand-written version has: each anchor is individually correct and the
-- relationship between them lives only in whoever wrote them. Moving the
-- threat line up by three pixels meant finding the four other offsets measured
-- from the same edge. Changing the icon row from four fixed squares to a list
-- that wraps meant re-deriving the widget's height from scratch.
--
--     Flow.Arrange(widget, {
--         direction = "column", reverse = true, gap = 4,
--         { frame = widget.box, height = 23, align = "stretch" },
--         { direction = "row", height = 16,
--             { frame = widget.threatText, grow = 1, align = "center" },
--             { direction = "row", wrap = true, justify = "end", ... },
--         },
--     })
--
-- Two passes, the same two XAML has. Measure asks every node how big it wants
-- to be, bottom up. Arrange hands every node the rectangle it actually got, top
-- down, and pins each frame to the root's top left corner at the offset that
-- came out. Pinning everything to one corner rather than chaining anchors is
-- deliberate: a chain can only align the run it starts, which is why the icon
-- row in the hand-written version had to be anchored square by square to the
-- gauge's corner with the row width subtracted.
--
-- Units. Everything here is in the units of the root frame, which for anything
-- ns.UI.Adopt has taken onto the grid means whole physical pixels. A caller
-- multiplies its design numbers by ns.UI.Unit once and hands them over. Offsets
-- are snapped through ns.UI.Round on the way out, because centring divides by
-- two and half of an odd number is half a pixel, which is what makes small
-- outlined text look like it has been breathed on.
--
-- What this does not do, and will not: content sizing. A node's size is a
-- number the caller knows before the layout runs. Two strings on an enemy bar
-- are sized by whatever the mob happens to be called, and they stay pinned to
-- each other with plain anchors, because a layout that had to re-run when a
-- name changed would be a layout running on the tick. The boundary is the same
-- one check.sh already enforces: nothing in here is reachable from an OnUpdate,
-- so this file is allowed to allocate and the files that call it are not.
--------------------------------------------------------------------------

-- Node fields, all optional:
--
--   frame       the frame this node places and sizes
--   direction   "row", "column" or "stack"; having one makes the node a
--               container and its array part its children. A stack gives every
--               child the whole rectangle and lets each one place itself in it,
--               which is XAML's single-cell Grid and is how two things share a
--               strip of screen without either reserving room from the other
--   alignX      in a stack: "start", "center", "end" or "stretch"
--   alignY      the same, down
--   width       fixed size across, in root units; measured from children if
--   height      fixed size down; measured from children if absent
--   grow        share of whatever main-axis room is left over
--   gap         between children
--   pad         inside the container's own edges, a number or {l, t, r, b}
--   justify     along the main axis: "start", "center", "end", "between"
--   align       across it: "start", "center", "end", "stretch"
--   wrap        break a row onto more lines when it runs out of width
--   lineOrder   with wrap: "down" (default) or "up", which edge line one is on
--   reverse     run the main axis backwards, which is what mirroring is
--   skip        this node is not drawn and takes no room
--
-- A node is a plain table written at the call site. Nothing is kept between
-- calls and nothing is pooled: a layout runs on a setting change, a resolution
-- change or a rebuild, never on a ticker, and a pool would be a cache to
-- invalidate in exchange for tables nobody is counting.

local function Pad(node)
	local pad = node.pad
	if not pad then
		return 0, 0, 0, 0
	end
	if type(pad) == "number" then
		return pad, pad, pad, pad
	end
	return pad[1] or 0, pad[2] or 0, pad[3] or 0, pad[4] or 0
end

local Measure

-- Break a wrapping row into lines, and remember them on the node so Arrange
-- does not have to work them out a second time and risk disagreeing.
--
-- The available width is the container's own, less its padding. A wrapping row
-- must be given a width: without one there is nothing to wrap against, and
-- measuring a row by its content and then wrapping it to that measurement is a
-- row that never wraps.
local function Wrap(node, avail)
	local gap = node.gap or 0
	local lines = {}
	local line = { main = 0, cross = 0 }
	lines[1] = line

	for index = 1, #node do
		local child = node[index]
		if not child.skip then
			local cw, ch = Measure(child)
			local run = (line.main > 0) and (line.main + gap + cw) or cw
			if line.main > 0 and run > avail then
				line = { main = cw, cross = ch }
				lines[#lines + 1] = line
				line[1] = child
			else
				line.main = run
				line.cross = (ch > line.cross) and ch or line.cross
				line[#line + 1] = child
			end
		end
	end

	node.rows = lines
	return lines
end

-- How big a node wants to be. Cached on the node, because a container's own
-- measurement asks each child once and Arrange asks again.
function Measure(node)
	if node.mw then
		return node.mw, node.mh
	end

	local l, t, r, b = Pad(node)

	if not node.direction then
		node.mw = node.width or 0
		node.mh = node.height or 0
		return node.mw, node.mh
	end

	if node.direction == "stack" then
		local w, h = 0, 0
		for index = 1, #node do
			local child = node[index]
			if not child.skip then
				local cw, ch = Measure(child)
				w = (cw > w) and cw or w
				h = (ch > h) and ch or h
			end
		end
		node.mw = node.width or (w + l + r)
		node.mh = node.height or (h + t + b)
		return node.mw, node.mh
	end

	local row = node.direction == "row"
	local gap = node.gap or 0
	local main, cross = 0, 0

	if node.wrap then
		assert(row, "a wrapping container must be a row")
		assert(node.width, "a wrapping row must be given a width to wrap against")
		local lines = Wrap(node, node.width - l - r)
		for index = 1, #lines do
			cross = cross + lines[index].cross
			if lines[index].main > main then
				main = lines[index].main
			end
		end
		cross = cross + math.max(#lines - 1, 0) * gap
	else
		local count = 0
		for index = 1, #node do
			local child = node[index]
			if not child.skip then
				local cw, ch = Measure(child)
				count = count + 1
				if row then
					main = main + cw
					cross = (ch > cross) and ch or cross
				else
					main = main + ch
					cross = (cw > cross) and cw or cross
				end
			end
		end
		main = main + math.max(count - 1, 0) * gap
	end

	if row then
		node.mw = node.width or (main + l + r)
		node.mh = node.height or (cross + t + b)
	else
		node.mw = node.width or (cross + l + r)
		node.mh = node.height or (main + t + b)
	end
	return node.mw, node.mh
end

--------------------------------------------------------------------------

local Place

-- Where a run of children starts, and how much room to leave between them,
-- given how much of the main axis they did not fill.
local function Justify(mode, slack, count, gap)
	if count < 1 then
		return 0, gap
	end
	if mode == "center" then
		return slack / 2, gap
	elseif mode == "end" then
		return slack, gap
	elseif mode == "between" and count > 1 then
		return 0, gap + slack / (count - 1)
	end
	return 0, gap
end

-- Where one child sits across the axis its container runs along, and how big it
-- is on that axis. Stretch is the only mode that changes the size.
local function Align(mode, size, avail)
	if mode == "stretch" then
		return 0, avail
	elseif mode == "center" then
		return (avail - size) / 2, size
	elseif mode == "end" then
		return avail - size, size
	end
	return 0, size
end

-- One run of children along a container's main axis, inside the rectangle it
-- was given. Shared by the plain case and by each line of a wrapping row.
local function Run(node, children, root, x, y, w, h)
	local row = node.direction == "row"
	local gap = node.gap or 0
	local avail = row and w or h

	-- Everything the run takes before growth, so the leftover can be shared out.
	local used, count, growth = 0, 0, 0
	for index = 1, #children do
		local child = children[index]
		if not child.skip then
			local cw, ch = Measure(child)
			used = used + (row and cw or ch)
			growth = growth + (child.grow or 0)
			count = count + 1
		end
	end
	used = used + math.max(count - 1, 0) * gap

	local slack = avail - used
	local start, step = Justify(node.justify, growth > 0 and 0 or slack, count, gap)
	local share = (growth > 0 and slack > 0) and (slack / growth) or 0

	-- Backwards means the run starts at the far edge and walks in. Mirroring a
	-- layout is this flag and nothing else.
	local at = start
	local order = node.reverse

	for step2 = 1, #children do
		local index = order and (#children - step2 + 1) or step2
		local child = children[index]
		if not child.skip then
			local cw, ch = Measure(child)
			local main = (row and cw or ch) + (child.grow or 0) * share
			local cross = row and ch or cw
			local off, size = Align(child.align or node.align, cross, row and h or w)

			if row then
				Place(child, root, x + at, y + off, main, size)
			else
				Place(child, root, x + off, y + at, size, main)
			end
			at = at + main + step
		end
	end
end

-- Put one node in the rectangle it was given, then its children inside that.
function Place(node, root, x, y, w, h)
	if node.frame then
		local px = UI.Round(root, x)
		local py = UI.Round(root, y)
		node.frame:ClearAllPoints()
		node.frame:SetPoint("TOPLEFT", root, "TOPLEFT", px, -py)
		node.frame:SetSize(math.max(UI.Round(root, w), UI.Pixel(root)),
			math.max(UI.Round(root, h), UI.Pixel(root)))
	end

	if not node.direction then
		return
	end

	local l, t, r, b = Pad(node)
	local ix, iy = x + l, y + t
	local iw, ih = w - l - r, h - t - b

	if node.direction == "stack" then
		for index = 1, #node do
			local child = node[index]
			if not child.skip then
				local cw, ch = Measure(child)
				local ox, sw = Align(child.alignX or "start", cw, iw)
				local oy, sh = Align(child.alignY or "start", ch, ih)
				Place(child, root, ix + ox, iy + oy, sw, sh)
			end
		end
		return
	end

	if node.wrap then
		local lines = node.rows or Wrap(node, iw)
		local gap = node.gap or 0

		-- Which line is drawn first. "up" puts line one against the bottom
		-- edge and grows away from it, which is what a debuff row above a
		-- health bar wants: the row nearest the gauge is the one that fills
		-- first and any partial row hangs off the top.
		local up = node.lineOrder == "up"
		local at = up and (ih - lines[1].cross) or 0
		for index = 1, #lines do
			local line = lines[index]
			Run(node, line, root, ix, iy + at, iw, line.cross)
			if up then
				at = at - (lines[index + 1] and (lines[index + 1].cross + gap) or 0)
			else
				at = at + line.cross + gap
			end
		end
		return
	end

	Run(node, node, root, ix, iy, iw, ih)
end

--------------------------------------------------------------------------

-- The lines a wrapping row breaks into, biggest index last, each carrying the
-- width it came to as `main`. For the one caller that has to size something
-- against the row it sits beside: it asks here rather than working the break
-- out again, so there is one rule for where a line ends and not two that agree
-- until somebody changes the gap.
--
-- Measuring is idempotent and cached on the node, so Flow.Arrange on the same
-- node afterwards does no work twice.
function Flow.Lines(node)
	Measure(node)
	return node.rows
end

-- Lay a tree out inside a frame, and size the frame to what came out unless the
-- tree was given a size of its own. Every offset below is measured from this
-- frame's top left corner, so every frame in the tree has to be a descendant of
-- it or share its scale.
--
-- Returns the measured size, because the two callers both want to know how tall
-- the thing they just laid out turned out to be.
function Flow.Arrange(root, node)
	node.frame = nil -- the root is placed by whoever owns it, not by its own tree
	local w, h = Measure(node)
	if not node.width then
		root:SetWidth(math.max(UI.Round(root, w), UI.Pixel(root)))
	end
	if not node.height then
		root:SetHeight(math.max(UI.Round(root, h), UI.Pixel(root)))
	end
	Place(node, root, 0, 0, node.width or w, node.height or h)
	return w, h
end
