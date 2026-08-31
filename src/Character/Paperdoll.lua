local ADDON, ns = ...

local Paperdoll = {}
ns.Paperdoll = Paperdoll

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The gear page
--
-- Nineteen slots in the arrangement the client uses, the player standing
-- between the two columns, and on the glass over him the four numbers the
-- client's own sheet has never drawn: what your gear averages, how worn it is,
-- how many slots are empty and how often you miss.
--
-- **The model is the middle.** This page used to give that space to the four
-- numbers and leave the model out, on the argument that a picture of your back
-- answers nothing the nineteen squares have not already answered. That is a
-- true sentence and the wrong conclusion. You open a character sheet to look at
-- your character, and a sheet that will not show it is a spreadsheet wearing
-- slot art. The numbers lost nothing by moving: they are four cells along the
-- foot of the portrait, in the same place every time, each with its sentence in
-- its hover, and the window's own footer says all four in a line anyway.
--
-- **The readings are on the model rather than beside it.** Two bands of the
-- theme's shadow, one along the top for who you are and one along the bottom
-- for what you are wearing, both at frame level over the model so the client
-- draws them on top of it. That is what makes the middle one panel instead of
-- three boxes stacked up, and it is why the durability line is the bottom edge
-- of the portrait rather than a bar in a list.
--
-- **A square carries the durability of what is in it.** One line along the
-- bottom edge, drawn only where the piece is worn at all, green through to red.
-- Durability is the one fact about your gear that changes while you play and
-- the one the client hides behind a hover, and a repair bill you can see coming
-- is a repair bill that never surprises you in a doorway.
--
-- **A square is a secure button, and it has to be.** The client's own sheet
-- answers a left click with the cursor swap and a right click with the use call
-- that takes a piece off or fires it. Only half of that is open to an addon:
-- the swap is an ordinary call, and using what is in a slot is protected. A
-- page that called it got the dialog saying WarriorKit has been blocked from an
-- action only available to the Blizzard UI, and so did a page that tried to
-- finish a spell the client was holding until it was told which item it was
-- for. That is a sharpening stone, an oil, an enchanting scroll or a poison,
-- and it is the bug that put this square on a secure template.
--
-- So the right button carries `/use <slot>` as a macro, written once at build,
-- and the client runs it on the path a macro runs on. The left button is left
-- alone: `target-slot` is the secure template's own answer to "a spell is
-- waiting for an item and this button is about to be clicked", and it uses the
-- slot after any click that finds one waiting. Nothing is armed, so nothing has
-- to be disarmed and nothing has to stand down in a fight. A left click with
-- nothing waiting reaches PostClick and is still the swap.
--
-- **The edge is named.** A secure button does not act on the edge it registered
-- for: it asks its own `useOnKeyDown` attribute, and a button that does not
-- answer gets the player's ActionButtonUseKeyDown setting instead, which is on
-- by default here. Registered for the release and acting on the press, the
-- square drew, hovered and did nothing at all, which is the same bug the action
-- bars shipped once already. The attribute is written, so the answer is this
-- addon's and not a setting's.
--
-- **Nothing here hands the right button to the camera.** UI.PassCamera is on
-- every other hoverable frame in the addon and it is deliberately not on these:
-- a square whose right click is an action cannot also pass the right button
-- through, and a square that did would draw and hover perfectly while its right
-- click went to the camera and nowhere else.
--------------------------------------------------------------------------

-- The client draws its slots at thirty-six and this draws them at thirty-six,
-- for the reason UI/Widgets.lua borrows the client's slot ring: a square you
-- drag a helmet into should be the size of the square the helmet came out of.
local SQUARE = 36
local INSET = 2
local WEAR = 2

-- How far apart two squares in a column sit, and the air between a column and
-- the portrait.
local GAP = 4

-- The widest the portrait is allowed to get, and the whole of what stops this
-- page spreading. A model is a figure standing up, so a panel much past this is
-- not a bigger portrait, it is the same figure on a wider stage, and it pushes
-- the two columns of squares a window apart. Given more room than the block
-- needs, the block is centred and the rest is left as margin.
local PORTRAIT = 260

-- The portrait's two bands. The top one is a line of text and is sized like
-- one; the bottom one is a number over a word, twice, plus the air round them.
local RIBBON = M.row
local CELL = M.heading + M.small + 12
local BAR = 4
local CELLPAD = 4

-- Three quarters on, which is how the client poses the model on its own sheet
-- and is the angle a shoulder actually reads at. Dead ahead is a chest and two
-- arms.
local FACING = 0.5

local Pane = {}
Pane.__index = Pane

--------------------------------------------------------------------------
-- One slot
--------------------------------------------------------------------------

local function Subject(entry)
	local link = ns.Worn.Link(entry.slot)
	if link then
		return { kind = "inventory", unit = "player", slot = entry.slot }
	end
	return { kind = "note", title = entry.label,
		lines = { { "empty", color = C.dim } } }
end

local function Act(entry)
	local ok, why = ns.Worn.Swap(entry.slot)
	if not ok and why then
		ns.Print(why)
	end
	return ok
end

local function Square(pane, entry)
	local box = UI.Box(pane.frame, C.sunken, C.edge)
	box:SetSize(SQUARE, SQUARE)

	box.icon = UI.Icon(box, "ARTWORK")
	box.icon:SetPoint("TOPLEFT", INSET, -INSET)
	box.icon:SetPoint("BOTTOMRIGHT", -INSET, INSET)

	-- The client's own silhouette for an empty slot, uncropped: it is already
	-- the shape it draws at, and cropping it the way an item icon is cropped
	-- eats its own border.
	box.empty = box:CreateTexture(nil, "ARTWORK")
	box.empty:SetPoint("TOPLEFT", INSET, -INSET)
	box.empty:SetPoint("BOTTOMRIGHT", -INSET, INSET)
	box.empty:SetVertexColor(1, 1, 1, 0.3)

	box.wear = ns.Fill(box, "OVERLAY", C.tick[1], C.tick[2], C.tick[3], 1)
	box.wear:SetPoint("BOTTOMLEFT", INSET, INSET)
	box.wear:SetHeight(WEAR)
	box.wear:Hide()

	-- The line the client already knows. `/use 16` is what every sharpening
	-- stone macro in the game carries, and it is the same line for all nineteen
	-- slots with the number changed.
	local use = ("/use %d"):format(entry.slot)

	local button = CreateFrame("Button", nil, pane.frame, "SecureActionButtonTemplate")
	button:SetAllPoints(box)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	-- Which edge the secure half acts on, said out loud rather than left to the
	-- player's settings. The client works it out from `useOnKeyDown`, falls back
	-- to the ActionButtonUseKeyDown setting when the button does not answer, and
	-- that setting is on by default on this client: a square registered for the
	-- release alone was then asked to act on a press it never receives, so it
	-- drew, hovered and did nothing. The client's own action buttons answer this
	-- by registering both edges. A gear square is not an action bar and answers
	-- it by naming the edge, which keeps one click one click.
	button:SetAttribute("useOnKeyDown", false)

	button:SetAttribute("type2", "macro")
	button:SetAttribute("macrotext2", use)

	-- Where a spell that is waiting for an item lands. The secure template looks
	-- this up itself after every click and uses the slot, which is the one path
	-- a sharpening stone, an oil, an enchanting scroll or a poison can take from
	-- a button an addon built. Written once at build, so there is nothing to arm
	-- on the way past and it holds in a fight, where an attribute cannot be
	-- written at all.
	button:SetAttribute("target-slot", entry.slot)

	-- Before the secure half of the click, because the secure half is what
	-- consumes the waiting spell: asked afterwards the client says nothing is
	-- waiting, and the swap below would answer a stone by picking the weapon up.
	button:SetScript("PreClick", function(self, which, down)
		UI.CloseDropdown()
		self.armed = which == "LeftButton" and ns.Worn.Targeting()
		ns.CharTrace.Press(self, which, down)
	end)

	-- After it. A left click with nothing waiting is the swap, and the square is
	-- left disarmed either way.
	button:SetScript("PostClick", function(self, which)
		local swapped = false
		if which == "LeftButton" and not self.armed then
			swapped = Act(entry)
		end
		self.armed = nil
		ns.CharTrace.Release(self, which, swapped)
		if swapped or which == "RightButton" then
			pane:Paint()
		end
	end)

	button:SetScript("OnReceiveDrag", function()
		if Act(entry) then
			pane:Paint()
		end
	end)

	-- The other direction, which a click alone does not cover. A left click on
	-- a full slot already picks the piece up, but nobody takes a helmet off by
	-- clicking it: they press on it and pull it into a bag, and that gesture
	-- never becomes a click at all, so a square without this is a square you
	-- can drop into and not out of. Same call as the click, so a drag out and a
	-- click are the same swap and refuse for the same reason.
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function(self)
		local swapped = Act(entry)
		ns.CharTrace.Drag(self, swapped)
		if swapped then
			pane:Paint()
		end
	end)
	button:SetScript("OnEnter", function(self)
		UI.Tint(box.bg, C.control)
		ns.Tip.Open(self, Subject(entry))
	end)
	button:SetScript("OnLeave", function()
		UI.Tint(box.bg, C.sunken)
		ns.Tip.Close()
	end)

	-- What the trace needs and cannot ask for: this client has no call that
	-- answers which edges a button registered, so the file that registered them
	-- says so here.
	ns.CharTrace.Watch(button, entry, "LeftButtonUp", "RightButtonUp")

	box.button = button
	box.entry = entry
	return box
end

-- What colour a durability line is at a given fraction. Three stops rather than
-- a gradient: green while it is fine, amber once a repair is worth planning,
-- red once a piece is about to stop working. A continuous blend between them
-- would be a colour nobody can read a number off.
local function WearTone(fraction)
	if fraction <= 0.2 then
		return C.loss
	end
	if fraction <= 0.5 then
		return C.heading
	end
	return C.tick
end

local function PaintSquare(box)
	local entry = box.entry
	local icon = ns.Worn.Icon(entry.slot)
	box.icon:SetTexture(icon)
	box.icon:SetShown(icon and true or false)

	local empty = (not icon) and ns.Worn.Art(entry) or nil
	box.empty:SetTexture(empty)
	box.empty:SetShown(empty and true or false)

	local link = icon and ns.Worn.Link(entry.slot) or nil
	local quality = link and ns.ItemValue(link) or nil
	ns.Recolor(box.edges, (quality and UI.Quality[quality]) or C.edge)

	local has, of = ns.Worn.Durability(entry.slot)
	if has then
		local fraction = has / of
		box.wear:SetWidth(math.max(UI.Round(box, (SQUARE - INSET * 2) * fraction), 1))
		UI.Tint(box.wear, WearTone(fraction))
		box.wear:Show()
	else
		box.wear:Hide()
	end
end

--------------------------------------------------------------------------
-- The four readings
--
-- Four cells along the foot of the portrait, in this order, always. A number
-- that moves is a number you have to read the label of; these four never move,
-- so after a week you read the second cell rather than the word durability.
--------------------------------------------------------------------------

local LABELS = { "item level", "durability", "empty", "miss" }

local function Readings()
	local level, empty = ns.Worn.Level()
	local wear, worst, fraction = ns.Worn.Wear()
	local read = {}

	read[1] = {
		value = level and ("%.1f"):format(level) or "none",
		note = "Averaged over what you are wearing. Shirt and tabard are left out, because neither carries a level worth counting.",
	}

	read[2] = {
		value = wear and ("%d%%"):format(math.floor(wear * 100 + 0.5)) or "none",
		fraction = wear,
		tone = wear and WearTone(wear) or nil,
		note = worst and ("Your %s is the worst of it, at %d%%.")
			:format(worst.label, math.floor((fraction or 0) * 100 + 0.5))
			or "Nothing you are wearing wears out.",
	}

	read[3] = {
		value = ("%d"):format(empty or 0),
		note = "Shirt and tabard are not counted, and neither is an off hand your two hander already fills.",
	}

	read[4] = {
		value = ("%.2f%%"):format(ns.CharStats.MeleeMiss(3)),
		note = "Against a boss, before any hit off your gear. The stats tab takes that off and says what is left.",
	}

	return read
end

--------------------------------------------------------------------------
-- The portrait
--------------------------------------------------------------------------

-- One band of shadow over the model. A frame rather than a texture on the
-- panel, because a texture belongs to the panel's own layers and the client
-- draws a model over every one of them. Frame level is the only thing a model
-- is behind.
local function Band(panel, level)
	local band = CreateFrame("Frame", nil, panel)
	band:SetFrameLevel(level)
	band.bg = ns.Fill(band, "BACKGROUND",
		C.shadow[1], C.shadow[2], C.shadow[3], C.shadow[4])
	band.bg:SetAllPoints()
	return band
end

-- One reading. The number, the word under it, a hairline off its left where
-- there is a cell before it, and the sentence in the hover.
local function Cell(foot, index, level)
	local cell = CreateFrame("Frame", nil, foot)
	cell:SetFrameLevel(level)
	cell:EnableMouse(true)

	cell.value = UI.Label(cell, M.heading, C.accent, "CENTER", UI.SHADOW)
	UI.Wrap(cell.value, false)
	cell.value:SetPoint("TOPLEFT", 0, -CELLPAD)
	cell.value:SetPoint("TOPRIGHT", 0, -CELLPAD)

	cell.label = UI.Label(cell, M.small, C.dim, "CENTER", UI.SHADOW)
	UI.Wrap(cell.label, false)
	cell.label:SetPoint("TOPLEFT", cell.value, "BOTTOMLEFT", 0, -2)
	cell.label:SetPoint("TOPRIGHT", cell.value, "BOTTOMRIGHT", 0, -2)
	cell.label:SetText(LABELS[index])

	if index > 1 then
		cell.rule = UI.Rule(cell, C.edge, true)
		cell.rule:SetPoint("TOPLEFT", 0, -CELLPAD)
		cell.rule:SetPoint("BOTTOMLEFT", 0, CELLPAD)
	end

	cell:SetScript("OnEnter", function(self)
		ns.Tip.Open(self, { kind = "note", title = LABELS[index],
			lines = { { self.note or "", color = C.dim } } }, true)
	end)
	cell:SetScript("OnLeave", function()
		ns.Tip.Close()
	end)

	return cell
end

-- The model, the two bands and the durability line along the foot. Everything
-- inside the panel is placed against its own edges, so the only thing Resize
-- has to hand it is a size.
local function Portrait(parent)
	local panel = UI.Box(parent, C.sunken, C.edge)
	local level = (panel:GetFrameLevel() or 0) + 5

	-- PlayerModel is a frame type rather than a template, so it costs nothing
	-- to exist on either client, and both calls on it are probed. A client that
	-- will not draw a model leaves the panel empty and every square around it
	-- still works, which is the honest degradation.
	local model = CreateFrame("PlayerModel", nil, panel)
	model:SetPoint("TOPLEFT", INSET, -INSET)
	model:SetPoint("BOTTOMRIGHT", -INSET, INSET)
	local function Dress()
		if model.SetUnit then
			pcall(model.SetUnit, model, "player")
		end
		if model.SetRotation then
			pcall(model.SetRotation, model, FACING)
		end
	end
	-- Once now and once on the way back up, never on a refresh: SetUnit reloads
	-- the model and a refresh is every click anywhere in the window.
	model:SetScript("OnShow", Dress)
	Dress()
	panel.model = model

	panel.top = Band(panel, level)
	panel.top:SetPoint("TOPLEFT", INSET, -INSET)
	panel.top:SetPoint("TOPRIGHT", -INSET, -INSET)
	panel.top:SetHeight(RIBBON)

	panel.name = UI.Label(panel.top, M.heading, C.heading, "LEFT", UI.SHADOW)
	UI.Wrap(panel.name, false)
	panel.name:SetPoint("LEFT", CELLPAD, 0)
	panel.level = UI.Label(panel.top, M.small, C.text, "RIGHT", UI.SHADOW)
	UI.Wrap(panel.level, false)
	panel.level:SetPoint("RIGHT", -CELLPAD, 0)

	panel.foot = Band(panel, level)
	panel.foot:SetPoint("BOTTOMLEFT", INSET, INSET)
	panel.foot:SetPoint("BOTTOMRIGHT", -INSET, INSET)
	panel.foot:SetHeight(CELL + BAR)

	panel.track = ns.Fill(panel.foot, "ARTWORK",
		C.sunken[1], C.sunken[2], C.sunken[3], 1)
	panel.track:SetPoint("BOTTOMLEFT")
	panel.track:SetPoint("BOTTOMRIGHT")
	panel.track:SetHeight(BAR)
	panel.fill = ns.Fill(panel.foot, "OVERLAY", C.tick[1], C.tick[2], C.tick[3], 1)
	panel.fill:SetPoint("BOTTOMLEFT")
	panel.fill:SetHeight(BAR)

	panel.cells = {}
	for index = 1, #LABELS do
		panel.cells[index] = Cell(panel.foot, index, level + 1)
	end
	return panel
end

--------------------------------------------------------------------------

function Paperdoll.New(parent)
	local pane = setmetatable({ squares = {}, left = {}, right = {}, hands = {} },
		Pane)
	pane.frame = CreateFrame("Frame", nil, parent)

	-- Sorted into the three groups once, because which group a slot is in is a
	-- fact about the slot and not about the width the page came out at.
	for _, entry in ipairs(ns.Worn.Slots()) do
		local box = Square(pane, entry)
		pane.squares[#pane.squares + 1] = box
		local group = pane[entry.side] or pane.hands
		group[#group + 1] = box
	end

	pane.panel = Portrait(pane.frame)
	return pane
end

-- Left column down the left, right column down the right, the portrait between
-- them, the three weapons centred under it. Placed rather than stacked, because
-- this is one arrangement of a fixed number of squares and a layout engine
-- would be a layer between the numbers and the picture.
function Pane:Resize(width, height)
	self.frame:SetSize(width, height)

	-- The portrait takes what the two columns leave, up to its own limit, and
	-- the three of them are centred together in whatever the page was given.
	-- The margin is worked out once and used on both sides, so the block cannot
	-- drift off centre as the window is resized.
	local column = SQUARE + GAP * 2
	self.width = math.max(math.min(width - column * 2, PORTRAIT), 1)
	local margin = math.max(math.floor((width - self.width - column * 2) / 2), 0)

	for index = 1, #self.left do
		self.left[index]:ClearAllPoints()
		self.left[index]:SetPoint("TOPLEFT", margin, -((index - 1) * (SQUARE + GAP)))
	end
	for index = 1, #self.right do
		self.right[index]:ClearAllPoints()
		self.right[index]:SetPoint("TOPRIGHT", -margin, -((index - 1) * (SQUARE + GAP)))
	end

	self.panel:ClearAllPoints()
	self.panel:SetPoint("TOPLEFT", margin + column, 0)
	self.panel:SetSize(self.width, math.max(height - SQUARE - GAP, 1))
	self.inner = self:Cells()

	local span = #self.hands * SQUARE + math.max(#self.hands - 1, 0) * GAP
	for index = 1, #self.hands do
		self.hands[index]:ClearAllPoints()
		self.hands[index]:SetPoint("TOP", self.panel, "BOTTOM",
			(index - 1) * (SQUARE + GAP) + (SQUARE - span) / 2, -GAP)
	end

	return self:Paint()
end

-- The four cells across the foot of the portrait, an equal slice each. The last
-- one takes the remainder, so the row ends on the panel's edge rather than a
-- rounding error short of it.
function Pane:Cells()
	local cells = self.panel.cells
	local inner = math.max(self.width - INSET * 2, 1)
	local slice = math.floor(inner / #cells)

	for index = 1, #cells do
		local last = (index == #cells)
		cells[index]:ClearAllPoints()
		cells[index]:SetPoint("TOPLEFT", (index - 1) * slice, 0)
		cells[index]:SetSize(last and (inner - slice * (#cells - 1)) or slice, CELL)
	end
	return inner
end

function Pane:PaintPortrait()
	local panel = self.panel
	panel.name:SetText(UnitName("player") or "You")
	panel.level:SetText(("level %d %s")
		:format(UnitLevel("player") or 0, ns.Class.Label()))

	local read = Readings()
	for index = 1, #panel.cells do
		local cell = panel.cells[index]
		local tone = read[index].tone or C.accent
		cell.value:SetText(read[index].value)
		cell.value:SetTextColor(tone[1], tone[2], tone[3])
		cell.note = read[index].note
	end

	local wear = read[2]
	if wear.fraction then
		panel.fill:SetWidth(math.max(
			UI.Round(panel, (self.inner or 1) * wear.fraction), 1))
		UI.Tint(panel.fill, wear.tone)
		panel.fill:Show()
	else
		panel.fill:Hide()
	end
end

function Pane:Paint()
	for index = 1, #self.squares do
		PaintSquare(self.squares[index])
	end
	if self.inner then
		self:PaintPortrait()
	end
	return true
end

function Pane:Show()
	self.frame:Show()
	return self:Paint()
end

function Pane:Hide()
	self.frame:Hide()
end
