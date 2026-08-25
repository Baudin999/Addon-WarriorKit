local ADDON, ns = ...

local UI = ns.UI

--------------------------------------------------------------------------
-- The stack
--
-- A column of rows laid out top down, in whole pixels, where every row is asked
-- how tall it is rather than told.
--
-- Asking is the whole point. The panel this replaced ran a cursor down the page
-- and gave each row the height its constructor guessed, which works until a row
-- contains prose. A note is as tall as its text wraps, its text changes while
-- the window is open because it reports live state, and its width is not known
-- until it has been placed. A height decided before any of that is a height the
-- row overflows, and the row under it is what gets written on.
--
-- So a cell may carry a measure function. Reflow calls it, snaps the answer to
-- a whole pixel, sets the row to exactly that, and only then places the row
-- under it. Reflow is cheap, it is safe to call again after anything changes,
-- and it returns the total so the thing holding the stack can decide whether it
-- now needs to scroll.
--
-- A stack owns a frame of its own rather than laying out into its parent. That
-- is what makes a section: seven stacks parented to one canvas, one shown, and
-- switching between them is two Show calls and a reflow rather than a rebuild.
--------------------------------------------------------------------------

local Stack = {}
Stack.__index = Stack

function UI.Stack(parent, width)
	local stack = setmetatable({ cells = {}, height = 0 }, Stack)
	stack.frame = CreateFrame("Frame", nil, parent)
	stack.frame:SetPoint("TOPLEFT")
	stack.width = width or 0
	stack.frame:SetSize(math.max(stack.width, 1), 1)
	return stack
end

-- Rows are stretched to the stack's width when they are added, so a width that
-- arrives late, which is every width that comes off a viewport, has to reach
-- the rows that were added before it.
function Stack:SetWidth(width)
	if width == self.width then
		return false
	end
	self.width = width
	self.frame:SetWidth(math.max(width, 1))
	return true
end

-- opts.height   a fixed height, used when there is nothing to measure
-- opts.measure  function(cell) returning the height this row needs right now
-- opts.indent   pixels in from the left edge of the stack
-- opts.gap      pixels of air under this row, on top of the usual row gap
-- opts.stretch  false to leave the row's own width alone
function Stack:Add(frame, opts)
	opts = opts or {}
	local cell = {
		frame = frame,
		height = opts.height or UI.Metric.row,
		indent = opts.indent or 0,
		gap = opts.gap or UI.Metric.rowGap,
		measure = opts.measure,
		stretch = opts.stretch ~= false,
	}
	self.cells[#self.cells + 1] = cell
	return cell
end

-- Air. A gap is a cell with no frame rather than padding on the row above it,
-- because the row above it does not know what follows.
function Stack:Space(height)
	return self:Add(nil, { height = height or UI.Metric.row, gap = 0 })
end

function Stack:Reflow()
	local y = 0
	local width = self.width
	for index = 1, #self.cells do
		local cell = self.cells[index]
		-- Width first, height second, and never the other way round. A row that
		-- measures itself measures the text inside it, the text is only as tall
		-- as its width lets it wrap, and a measurement taken against last
		-- layout's width is the whole overflow bug in one line.
		if cell.frame and cell.stretch and width > cell.indent then
			cell.frame:SetWidth(width - cell.indent)
		end

		local height = cell.measure and cell.measure(cell) or cell.height
		height = UI.Round(self.frame, math.max(height or 0, 0))
		cell.height = height

		if cell.frame then
			cell.frame:ClearAllPoints()
			cell.frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", cell.indent, -y)
			cell.frame:SetHeight(math.max(height, 1))
		end

		y = y + height
		if index < #self.cells then
			y = y + cell.gap
		end
	end

	self.height = y
	self.frame:SetHeight(math.max(y, 1))
	return y
end

function Stack:Show()
	self.frame:Show()
end

function Stack:Hide()
	self.frame:Hide()
end

function Stack:IsShown()
	return self.frame:IsShown()
end
