local ADDON, ns = ...

local Readout = {}
ns.CharReadout = Readout

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- A column of headed rows, repainted rather than rebuilt
--
-- Three of the five tabs in the character window are the same picture: a
-- heading, some rows under it, each row a name on the left and a value on the
-- right, some of them with a sentence underneath and some with a bar. Stats,
-- skills and reputation differ in what they put in that shape and in nothing
-- else, so they hand this pane the same table and it draws all three.
--
-- **The lines are a pool.** This client cannot destroy a frame, so a pane that
-- built its rows when it was handed a list would leak a frame for every skill
-- every time anything moved. There is one frame per line the pane has ever
-- needed, every region either kind of line can want is on all of them, and a
-- repaint shows the regions this line uses and hides the rest. It is the same
-- argument the quest window's two right-hand columns make.
--
-- **Nothing here is laid out by UI/Stack.lua**, which is the other thing in the
-- addon that puts rows in a column, and the reason is that a stack's cells are
-- added once and this list is handed a different number of rows every time it
-- is filled. A stack would need a way to forget its cells, which is a method
-- that exists for one caller and would then have to be right for the options
-- window as well. Placing the rows here costs eight lines.
--
-- A row measures itself the same way a stack cell does, and for the same
-- reason: the sentence under a weapon skill wraps, and how tall it wraps to is
-- not known until the pane has been given its width.
--------------------------------------------------------------------------

-- The bar under a row that has a fraction, and the air around it. Short,
-- because a row is a line of text and this is a mark beside it rather than a
-- gauge: five pixels says how far along you are without turning a list of
-- thirty skills into thirty progress bars stacked up the window.
local BAR = 5

-- How much of the row's width the value on the right may take before the name
-- on the left starts being clipped. Values here are short, "300 of 300" and
-- "Honored, 5400 of 12000" being the two longest shapes, and the name is what
-- you are reading down the column, so the split favours the name.
local VALUE = 150

local Pane = {}
Pane.__index = Pane

local function Line(pane)
	local frame = CreateFrame("Frame", nil, pane.view.canvas)

	frame.title = UI.Label(frame, M.heading, C.heading, "LEFT", UI.FLAT)
	UI.Wrap(frame.title, false)
	frame.title:SetPoint("TOPLEFT")
	frame.rule = UI.Rule(frame, C.hairline)
	frame.rule:SetPoint("TOPLEFT", 0, -(M.heading + M.rowGap))
	frame.rule:SetPoint("TOPRIGHT", 0, -(M.heading + M.rowGap))

	frame.label = UI.Label(frame, M.font, C.text, "LEFT", UI.FLAT)
	UI.Wrap(frame.label, false)
	frame.label:SetPoint("TOPLEFT")

	frame.value = UI.Label(frame, M.font, C.accent, "RIGHT", UI.FLAT)
	UI.Wrap(frame.value, false)
	frame.value:SetPoint("TOPRIGHT")

	frame.note = UI.Label(frame, M.small, C.dim, "LEFT", UI.FLAT)
	UI.Wrap(frame.note, true)
	frame.note:SetSpacing(2)

	frame.track = UI.Box(frame, C.sunken, nil)
	frame.track:SetHeight(BAR)
	frame.fill = ns.Fill(frame.track, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
	frame.fill:SetPoint("TOPLEFT")
	frame.fill:SetPoint("BOTTOMLEFT")

	frame:Hide()
	pane.lines[#pane.lines + 1] = frame
	return frame
end

local function Blank(frame)
	frame.title:Hide()
	frame.rule:Hide()
	frame.label:Hide()
	frame.value:Hide()
	frame.note:Hide()
	frame.track:Hide()
end

-- One heading. Its own height, because a heading is a rule with a word over it
-- and has nothing to measure.
local function PaintTitle(frame, text)
	Blank(frame)
	frame.title:SetText(text)
	frame.title:Show()
	frame.rule:Show()
	return M.heading + M.rowGap + M.hairline
end

-- One row, and the height it came out at. The note is given its width before it
-- is measured, which is the rule every wrapping string in the addon is written
-- against: a height taken against the last layout's width is the overflow bug.
local function PaintRow(frame, row, width)
	Blank(frame)
	frame.label:SetText(row.label or "")
	frame.label:SetWidth(math.max(width - VALUE - M.gutter, 1))
	frame.label:Show()
	frame.value:SetText(row.value or "")
	frame.value:SetWidth(VALUE)
	frame.value:Show()

	local height = M.row

	if row.fraction then
		frame.track:ClearAllPoints()
		frame.track:SetPoint("TOPLEFT", 0, -height)
		frame.track:SetWidth(width)
		frame.fill:SetWidth(math.max(UI.Round(frame, width * row.fraction), 1))
		UI.Tint(frame.fill, row.tone or C.accent)
		frame.track:Show()
		height = height + BAR + M.rowGap
	end

	if row.note then
		frame.note:ClearAllPoints()
		frame.note:SetPoint("TOPLEFT", 0, -height)
		frame.note:SetWidth(math.max(width, 1))
		frame.note:SetText(row.note)
		frame.note:Show()
		height = height + UI.TextHeight(frame.note, M.small) + M.rowGap
	end

	return height
end

--------------------------------------------------------------------------

function Readout.New(parent)
	local pane = setmetatable({ lines = {}, groups = {} }, Pane)
	pane.frame = CreateFrame("Frame", nil, parent)
	pane.view = UI.ScrollView(pane.frame)
	pane.view.frame:SetPoint("TOPLEFT")
	return pane
end

function Pane:Resize(width, height)
	self.width = self.view:Resize(width, height)
	self.frame:SetSize(width, height)
	return self:Paint()
end

-- What to draw next time. Kept rather than drawn, because the tab you are not
-- looking at is handed its groups on the same refresh as the one you are, and
-- measuring a font string on a hidden frame is the one thing this client will
-- not answer honestly.
function Pane:Set(groups)
	self.groups = groups or {}
	return self:Paint()
end

-- Nothing is drawn while the pane is hidden, and that is a measurement rule
-- rather than a saving. A font string on a hidden frame is not obliged to
-- report the height it wraps to on this client, so a tab painted while it was
-- behind another one would lay every sentence out one line tall and keep that
-- height when you opened it. The window paints the tab it has just shown.
function Pane:Paint()
	if not self.width or self.width <= 0 or not self.frame:IsShown() then
		return 0
	end
	local width = self.width
	local at, y = 0, 0

	for index = 1, #self.groups do
		local group = self.groups[index]
		at = at + 1
		local frame = self.lines[at] or Line(self)
		local height = PaintTitle(frame, group.title)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", self.view.canvas, "TOPLEFT", 0, -y)
		frame:SetSize(width, height)
		frame:Show()
		y = y + height + M.rowGap

		for slot = 1, #group.rows do
			at = at + 1
			local row = self.lines[at] or Line(self)
			-- Placed and sized before it is painted, so the note inside it is
			-- measured against the width it will be drawn at.
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", self.view.canvas, "TOPLEFT", M.indent, -y)
			row:SetSize(math.max(width - M.indent, 1), M.row)
			row:Show()
			local tall = PaintRow(row, group.rows[slot], width - M.indent)
			row:SetHeight(tall)
			y = y + tall + M.rowGap
		end
		y = y + M.gutter
	end

	for index = at + 1, #self.lines do
		self.lines[index]:Hide()
	end

	self.view:Update(y)
	return y
end

function Pane:Show()
	self.frame:Show()
	return self:Paint()
end

function Pane:Hide()
	self.frame:Hide()
end

function Pane:Lines()
	return #self.lines
end
