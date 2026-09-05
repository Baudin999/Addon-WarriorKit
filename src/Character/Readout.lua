local ADDON, ns = ...

local Readout = {}
ns.CharReadout = Readout

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- A column of headed rows, repainted rather than rebuilt
--
-- Three places in the character window are the same picture: a heading, some
-- rows under it, each row a name on the left and a value on the right, some of
-- them with a sentence underneath and some with a bar. The skills tab, the
-- reputation tab and the stats column down the right of the gear page differ in
-- what they put in that shape and in nothing else, so they hand this pane the
-- same table and it draws all three.
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
--
-- **Compact is a mode, and it is what the stats column is drawn in.** A row
-- there is one line and nothing else: the sentence that would have wrapped
-- under it goes into the hover, along with the value, so a number clipped by a
-- narrow column is still readable by pointing at it. Thirty-five rows of prose
-- is a page you scroll past rather than read, and the stats are a column you
-- glance at while you swap a ring. The two tabs that are a page in their own
-- right, skills and reputation, keep their sentences on the page.
--
-- **A compact row is banded, and the band is doing two jobs.** It is what tells
-- one line of numbers from the line under it once the air between them has been
-- taken away, which is the whole of what compact did to them. And it is the
-- only ground the column has: the character sheet it is drawn on is a backdrop
-- over the game world with no panel behind it, so a stat printed on nothing is
-- a stat you read against grass. Two tones alternating, both of them the
-- palette's own, both low enough that the world still shows through.
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

-- The same split in a compact row, and it is measured rather than chosen: the
-- longest value the stats column ever prints is "3.60 seconds", and this is
-- that with a few pixels to spare. The value is pinned to the right edge, so
-- every pixel reserved here beyond what the number uses is white space between
-- a name and the number it belongs to. Anything that still does not fit is in
-- the hover, which is the whole bargain compact makes.
local TIGHT = 96

-- How tall a compact row is. Two over the font it draws, which is one pixel of
-- leading above the line and one below: the least air that still reads as
-- separate rows rather than a block. A control row is twenty because you aim a
-- mouse at it; nothing here is clicked, so none of that height is earned. At
-- thirty-odd rows the six pixels saved on each are two hundred of scrolling.
local DENSE = M.font + 2

local Pane = {}
Pane.__index = Pane

-- What a compact row says when you point at it: its own name, the value the
-- column may have clipped, and the sentence the column does not draw.
local function Hint(frame)
	local row = frame.hint
	if not row then
		return nil
	end
	local lines = { { row.value or "", color = C.accent } }
	if row.note then
		lines[#lines + 1] = { row.note, color = C.dim }
	end
	return { kind = "note", title = row.label, lines = lines }
end

local function Line(pane)
	local frame = CreateFrame("Frame", nil, pane.view.canvas)

	-- Under everything else on the row, and only on a compact one. It is sized
	-- and coloured by the repaint, because how tall a row came out and which of
	-- the two tones it takes are both facts about this paint rather than about
	-- the frame.
	if pane.compact then
		frame.band = ns.Fill(frame, "BACKGROUND", C.band[1], C.band[2], C.band[3], C.band[4])
		frame.band:SetPoint("TOPLEFT")
		frame.band:SetPoint("TOPRIGHT")
	end

	frame.title = UI.Label(frame, M.heading, C.heading, "LEFT",
		pane.compact and UI.SHADOW or UI.FLAT)
	UI.Wrap(frame.title, false)
	frame.title:SetPoint("TOPLEFT")
	frame.rule = UI.Rule(frame, C.hairline)
	frame.rule:SetPoint("TOPLEFT", 0, -(M.heading + M.rowGap))
	frame.rule:SetPoint("TOPRIGHT", 0, -(M.heading + M.rowGap))

	frame.label = UI.Label(frame, M.font, C.text, "LEFT",
		pane.compact and UI.SHADOW or UI.FLAT)
	UI.Wrap(frame.label, false)
	frame.label:SetPoint("TOPLEFT")

	frame.value = UI.Label(frame, M.font, C.accent, "RIGHT",
		pane.compact and UI.SHADOW or UI.FLAT)
	UI.Wrap(frame.value, false)
	frame.value:SetPoint("TOPRIGHT")

	frame.note = UI.Label(frame, M.small, C.dim, "LEFT",
		pane.compact and UI.SHADOW or UI.FLAT)
	UI.Wrap(frame.note, true)
	frame.note:SetSpacing(2)

	frame.track = UI.Box(frame, C.sunken, nil)
	frame.track:SetHeight(BAR)
	frame.fill = ns.Fill(frame.track, "ARTWORK", C.accent[1], C.accent[2], C.accent[3], 1)
	frame.fill:SetPoint("TOPLEFT")
	frame.fill:SetPoint("BOTTOMLEFT")

	-- Only the compact rows are hoverable, because they are the only ones
	-- keeping anything back. A row on the skills tab has its sentence under it
	-- already, and a hover that repeated it would cost the right button drag
	-- that turns the camera for nothing.
	if pane.compact then
		frame:EnableMouse(true)
		ns.Tip.Hang(frame, Hint)
	end

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
	if frame.band then
		frame.band:Hide()
	end
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
local function PaintRow(frame, row, width, compact, stripe)
	Blank(frame)
	-- What the hover reads, and nothing at all on a pane that draws its own
	-- sentences: a tooltip that repeats the line under the cursor is furniture.
	frame.hint = compact and row or nil

	local split = compact and TIGHT or VALUE
	frame.label:SetText(row.label or "")
	frame.label:SetWidth(math.max(width - split - M.gutter, 1))
	frame.label:Show()
	frame.value:SetText(row.value or "")
	frame.value:SetWidth(split)
	frame.value:Show()

	local height = compact and DENSE or M.row

	if row.fraction then
		frame.track:ClearAllPoints()
		frame.track:SetPoint("TOPLEFT", 0, -height)
		frame.track:SetWidth(width)
		frame.fill:SetWidth(math.max(UI.Round(frame, width * row.fraction), 1))
		UI.Tint(frame.fill, row.tone or C.accent)
		frame.track:Show()
		height = height + BAR + M.rowGap
	end

	if row.note and not compact then
		frame.note:ClearAllPoints()
		frame.note:SetPoint("TOPLEFT", 0, -height)
		frame.note:SetWidth(math.max(width, 1))
		frame.note:SetText(row.note)
		frame.note:Show()
		height = height + UI.TextHeight(frame.note, M.small) + M.rowGap
	end

	-- Last, because the band is the whole row's ground and the row's height is
	-- not known until everything on it has been placed.
	if frame.band then
		UI.Tint(frame.band, stripe and C.band or C.bandAlt)
		frame.band:SetHeight(height)
		frame.band:Show()
	end

	return height
end

--------------------------------------------------------------------------

-- `opts.compact` is the stats column: one line a row, the rest in the hover.
-- The two gaps come with it rather than being read at every site, because a
-- dense list is dense in its spacing as well as in its rows.
function Readout.New(parent, opts)
	local pane = setmetatable({ lines = {}, groups = {} }, Pane)
	pane.compact = opts and opts.compact and true or false
	pane.gap = pane.compact and 0 or M.rowGap
	pane.pad = pane.compact and M.rowGap or M.gutter
	-- The band runs the row's whole width, so a compact row starts at the
	-- pane's own edge. Indented, the stripe would begin twelve pixels in and the
	-- column would read as a list inside a box that is not drawn.
	pane.indent = pane.compact and 0 or M.indent
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
			row:SetPoint("TOPLEFT", self.view.canvas, "TOPLEFT", self.indent, -y)
			row:SetSize(math.max(width - self.indent, 1), M.row)
			row:Show()
			-- Odd rows take the stronger of the two tones, so a group always
			-- opens on one and the stripe restarts under every heading rather
			-- than running on from whatever the last group ended at.
			local tall = PaintRow(row, group.rows[slot], width - self.indent,
				self.compact, slot % 2 == 1)
			row:SetHeight(tall)
			y = y + tall + self.gap
		end
		y = y + self.pad
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
