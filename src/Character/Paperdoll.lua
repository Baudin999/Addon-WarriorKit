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
-- **The stats are the right hand column.** They were a tab of their own, which
-- meant the two halves of one question lived on two pages: the squares say what
-- you are wearing and the numbers say what wearing it does, and swapping a ring
-- to see the second one move is a tab press away from the first. So the stats
-- readout is a column down the right of this page, filled from the same
-- Character/Stats.lua and drawn by the same Character/Readout.lua that drew the
-- tab. The block of squares and the portrait keep their own width and sit
-- against the left edge; the column takes everything the block does not want.
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
--
-- **Nineteen secure buttons are what closed this window in a fight, and the key
-- is what opened it again.** A secure button is a protected frame, showing a
-- window that has a protected frame inside it is itself protected, and an addon
-- may not do a protected thing in combat. So the sheet would not come up mid
-- pull, which is when the durability line is worth most. The answer was not to
-- give the squares up: Character/Window.lua has the key press run a snippet, a
-- snippet is allowed to show the window in combat, and the page underneath is
-- never hidden by a tab change. Nothing on this page changed for it.
--
-- **A click asks the slot about the fight, not the fight.** Armour cannot be
-- changed in combat and a weapon can, which is the client's own rule and the
-- one Blizzard's sheet plays by, so Character/Worn.lua answers per slot and the
-- three hands stay live mid pull. A stone is refused by the same rule: using
-- what is in a slot is protected, the secure half is what runs it, and it does
-- not run in a fight.
--------------------------------------------------------------------------

-- The client draws its slots at thirty-six and this draws them at thirty-six,
-- for the reason UI/Widgets.lua borrows the client's slot ring: a square you
-- drag a helmet into should be the size of the square the helmet came out of.
local SQUARE = 36
local INSET = 2
local WEAR = 2

-- How far inside the ring the icon sits, which is also how wide the band of
-- quality colour showing round it is.
local RIM = 3

-- How bright that band is with nothing pointing at it. Nineteen quality colours
-- at full strength is a page of coloured lights; at this they are a tint you
-- read without being shouted at, and the hover is what takes one to full.
local REST = 0.55

-- How wide the durability line under a weapon is. A chord rather than the width
-- of the square, because the square draws as a disc now and a line the full
-- width of it would stick out of both sides. The sixteen sided slots do not use
-- it: theirs runs the width of the item's name.
local WEARSPAN = 14

-- The socket dots. Three because three is the most holes anything in this
-- expansion has, and five pixels because a dot on the same line as an eleven
-- pixel number is a dot, and at seven it is a button.
local DOTS = 3
local DOT = 5

-- How much of the page's width the figure stands in, between the two columns.
-- The model is behind everything now rather than boxed between them, so this is
-- not the model's width: it is the gap the two columns leave in the middle,
-- which is the only part of the figure nothing is drawn over.
local MIDDLE = 190

-- How far apart two squares in a column sit, and the air between a column and
-- the portrait.
local GAP = 4

-- The narrowest the stats column may be and still be worth drawing, and it is
-- the row added up rather than a taste: a scroll bar, the indent, the widest
-- name the page prints beside a number, the gutter and the room the value is
-- pinned into. The window is built to hand the column exactly this, so the two
-- ends of a row sit as close as a right-aligned number can sit to its name.
-- Under it the name is what gets clipped, so a window too narrow to carry both
-- keeps the gear and drops the column rather than drawing half a word.
local READING = 220

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

-- What colour the ring behind an icon is, and how bright.
--
-- Two things decide it and they change at different times: a repaint sets the
-- colour when what you are wearing moves, and the hover sets the brightness
-- while the cursor is on the square. Either can happen while the other is
-- standing, so both go through here and neither writes the texture itself.
local function Ring(box, color)
	box.tone = color or C.edge
	box.ring:SetVertexColor(box.tone[1], box.tone[2], box.tone[3],
		box.lit and 1 or REST)
end

-- The disc and what is drawn on it, in a frame of its own so the row can put it
-- at either end. Everything on it is still reached as box.ring, box.icon and
-- box.empty, because a repaint has no business knowing there is a face frame.
local function Face(box)
	local face = CreateFrame("Frame", nil, box)
	face:SetSize(SQUARE, SQUARE)

	-- The disc, and the whole reason the icon over it can afford to go soft at
	-- its own edge. The icon is inset by RIM, so a band of this shows all the way
	-- round and the icon's last few texels fade onto purple or onto green rather
	-- than onto the panel. It carries the quality colour, which is what the box
	-- edges carried before there were no edges to carry it.
	box.ring = UI.Disc(face, "BACKGROUND")
	box.ring:SetAllPoints()
	Ring(box, nil)

	box.icon = UI.Clip(UI.Icon(face, "ARTWORK"))
	box.icon:SetPoint("TOPLEFT", RIM, -RIM)
	box.icon:SetPoint("BOTTOMRIGHT", -RIM, RIM)

	-- The client's own silhouette for an empty slot, uncropped: it is already
	-- the shape it draws at, and cropping it the way an item icon is cropped
	-- eats its own border. Rounded all the same, because a square silhouette in
	-- a round ring is the one slot on the page that looks like a mistake.
	box.empty = UI.Clip(face:CreateTexture(nil, "ARTWORK"))
	box.empty:SetPoint("TOPLEFT", RIM, -RIM)
	box.empty:SetPoint("BOTTOMRIGHT", -RIM, RIM)
	box.empty:SetVertexColor(1, 1, 1, 0.3)

	return face
end

-- The name of what is in the slot, the line under it, and the sockets on that
-- line. Only the sixteen sided slots get one: the three weapons sit centred
-- under the figure where a row of text has nowhere to go and would cross it.
--
-- Everything is anchored here rather than in Resize, off the face at one end and
-- the row's own far edge at the other, so a row that changes width takes its
-- text with it and Resize places nineteen frames and nothing inside one.
--
-- The dots run in from the far edge and the item level sits at the near one, so
-- the two never collide on a name long enough to clip: what gets cut is the
-- middle of the line, which is empty.
local function Words(box, entry)
	local near = entry.side == "right" and "RIGHT" or "LEFT"
	local far = entry.side == "right" and "LEFT" or "RIGHT"
	local sign = entry.side == "right" and -1 or 1

	box.name = UI.Label(box, M.font, C.text, near, UI.SHADOW)
	UI.Wrap(box.name, false)
	box.name:SetPoint("TOP" .. near, box.face, "TOP" .. far, sign * M.gutter, -2)
	box.name:SetPoint("TOP" .. far, box, "TOP" .. far, 0, -2)

	box.note = UI.Label(box, M.small, C.dim, near, UI.SHADOW)
	UI.Wrap(box.note, false)
	box.note:SetPoint("TOP" .. near, box.name, "BOTTOM" .. near, 0, -1)
	box.note:SetPoint("TOP" .. far, box.name, "BOTTOM" .. far, 0, -1)

	-- One per socket a piece in this slot could carry. Made at build and shown
	-- by the repaint, because a texture made on a repaint is a texture made
	-- nineteen times every time anything you are wearing moves.
	box.dots = {}
	for index = 1, DOTS do
		local dot = UI.Disc(box, "OVERLAY")
		dot:SetSize(DOT, DOT)
		dot:SetPoint(far, box, far, sign * -((index - 1) * (DOT + 2)), 0)
		dot:SetPoint("TOP", box.note, "TOP", 0, 0)
		dot:Hide()
		box.dots[index] = dot
	end
end

local function Square(pane, entry)
	local box = CreateFrame("Frame", nil, pane.frame)
	box:SetSize(SQUARE, SQUARE)
	box.face = Face(box)
	box.face:SetPoint("TOP" .. (entry.side == "right" and "RIGHT" or "LEFT"))

	-- The three weapons are a side of their own and get no words. They sit
	-- centred under the figure, where a line of text has nowhere to go and would
	-- be drawn across the model rather than beside it.
	if entry.side ~= "hands" then
		Words(box, entry)
	end

	-- Under the name where there is one, and a chord across the foot of the disc
	-- where there is not. Durability is the one fact about a piece that changes
	-- while you play, so it belongs on the line you are already reading, and a
	-- two pixel rule under an item's name is that line's own underscore rather
	-- than a bar competing with it.
	box.wear = ns.Fill(box, "OVERLAY", C.tick[1], C.tick[2], C.tick[3], 1)
	box.wear:SetHeight(WEAR)
	if box.name then
		local near = entry.side == "right" and "RIGHT" or "LEFT"
		box.wear:SetPoint("BOTTOM" .. near, box.name, "BOTTOM" .. near, 0, -1)
	else
		box.wear:SetPoint("BOTTOM")
		box.wear:SetWidth(WEARSPAN)
	end
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
		box.lit = true
		Ring(box, box.tone)
		-- On the square rather than in the corner. A worn piece is an object
		-- you are pointing at, and comparing two of them means reading one box
		-- against the square beside it.
		ns.Tip.Open(self, Subject(entry), nil, ns.UI.Tooltip.BESIDE)
	end)
	button:SetScript("OnLeave", function()
		box.lit = nil
		Ring(box, box.tone)
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

-- The dots under a name. Filled first, in the gem's own quality colour, then
-- the holes in the panel's edge colour, which is the order the client can
-- actually answer: a link says what is in it and how many are open, and never
-- which position an open one is.
local function PaintDots(box, link)
	local filled, open = ns.ItemSockets(link)
	local count = filled and #filled or 0
	for index = 1, DOTS do
		local dot = box.dots[index]
		local gem = filled and filled[index]
		local tone = gem and UI.Quality[ns.ItemValue(gem) or 1] or C.edge
		dot:SetVertexColor(tone[1], tone[2], tone[3], gem and 1 or 0.7)
		dot:SetShown(index <= count + open)
	end
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
	Ring(box, quality and UI.Quality[quality] or nil)

	-- The name of the thing, in the colour of the thing. An empty slot says what
	-- the slot is for instead, dimmed, because a blank line beside a silhouette
	-- is a row you have to work out and the label is already in the entry.
	if box.name then
		local tone = quality and UI.Quality[quality] or C.dim
		box.name:SetText(link and (ns.ItemInfo(link)) or entry.label)
		box.name:SetTextColor(tone[1], tone[2], tone[3])
		local level = link and ns.ItemLevel(link)
		box.note:SetText(level and level > 0 and ("%d"):format(level) or "")
		PaintDots(box, link)
	end

	local has, of = ns.Worn.Durability(entry.slot)
	if has then
		local fraction = has / of
		local span = box.name and box.name:GetWidth() or (SQUARE - INSET * 2)
		box.wear:SetWidth(math.max(UI.Round(box, span * fraction), 1))
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
		note = "Against a boss, before any hit off your gear. The missing group in the column beside you takes that off and says what is left.",
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
	-- On the way up, never on a refresh: SetUnit reloads the model and a refresh
	-- is every click anywhere in the window. Pane:Redress is the other caller and
	-- it asks first whether anything you are wearing actually moved, which is the
	-- only question that earns a reload.
	--
	-- And not once here, which is what it did. Loading a figure into a panel on a
	-- window nobody has opened is the most expensive call this file makes and the
	-- one nobody can see the result of. The first paint of the page dresses it,
	-- because Redress compares nineteen links against a table that is empty until
	-- then and finds all nineteen changed.
	model:SetScript("OnShow", Dress)
	panel.model = model
	panel.Dress = Dress

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
	local pane = setmetatable({ squares = {}, left = {}, right = {}, hands = {},
		worn = {} }, Pane)
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

	-- Every row sits over the figure, and that is what putting the model behind
	-- the page costs. A model is drawn over every texture layer of the frame that
	-- holds it, so frame level is the only thing it goes behind: this is the same
	-- sentence Band above is written for, applied to nineteen rows. The secure
	-- button goes one higher than its row, because a click has to reach it
	-- through the name as well as through the disc.
	local level = pane.panel:GetFrameLevel() + 5
	for index = 1, #pane.squares do
		pane.squares[index]:SetFrameLevel(level)
		pane.squares[index].button:SetFrameLevel(level + 1)
	end

	-- The same readout the stats tab was, hosted here instead and drawn compact:
	-- a line a row, with the sentence under it moved into the hover. It keeps
	-- its own scroll view, so a long sheet on a short window scrolls beside a
	-- portrait that does not move.
	pane.stats = ns.CharReadout.New(pane.frame, { compact = true })
	return pane
end

-- Left column down the left, right column beside the portrait, the portrait
-- between them, the three weapons centred under it, and the stats down the rest
-- of the width. Placed rather than stacked, because this is one arrangement of a
-- fixed number of squares and a layout engine would be a layer between the
-- numbers and the picture.
function Pane:Resize(width, height)
	self.frame:SetSize(width, height)

	-- The stats column takes what it needs off the right and the gear area is
	-- everything else. Inside that, the two columns of rows sit against its two
	-- edges and MIDDLE is the gap left between them, which is the strip of the
	-- figure nothing is drawn over.
	--
	-- There is no narrow arrangement to fall back to. This window's width is a
	-- constant in Character/Window.lua and its zoom scales the frame rather than
	-- resizing it, so the column is the same number of units on every screen the
	-- page is ever drawn on. A fallback here would be a second layout nothing
	-- exercises, which is a second layout nobody would notice going wrong.
	local stats = width - READING - M.gutter >= SQUARE * 2 + MIDDLE and READING or 0
	local gutter = stats > 0 and M.gutter or 0
	local gear = math.max(width - stats - gutter, 1)
	local column = math.max(UI.Round(self.frame, (gear - MIDDLE) / 2), SQUARE)
	self.width = gear

	-- Under the top band, not level with it. The band carries your name and it
	-- runs the full width now, so a first row starting at the top of the page
	-- would be drawn across it.
	local top = RIBBON + GAP

	for index = 1, #self.left do
		self.left[index]:SetSize(column, SQUARE)
		self.left[index]:ClearAllPoints()
		self.left[index]:SetPoint("TOPLEFT", 0, -(top + (index - 1) * (SQUARE + GAP)))
	end
	for index = 1, #self.right do
		self.right[index]:SetSize(column, SQUARE)
		self.right[index]:ClearAllPoints()
		self.right[index]:SetPoint("TOPRIGHT", self.frame, "TOPLEFT",
			gear, -(top + (index - 1) * (SQUARE + GAP)))
	end

	-- The figure is behind the whole gear area rather than boxed between the two
	-- columns, which is the change that makes this one picture instead of three
	-- panels in a row. Its two bands run the full width with it: the name along
	-- the top and the four readings along the foot are about the page, not about
	-- the middle third of it.
	self.panel:ClearAllPoints()
	self.panel:SetPoint("TOPLEFT")
	self.panel:SetSize(gear, math.max(height - SQUARE - GAP, 1))
	self.inner = self:Cells()

	self.stats.frame:ClearAllPoints()
	self.stats.frame:SetPoint("TOPRIGHT")
	if stats > 0 then
		self.stats.frame:Show()
		self.stats:Resize(stats, height)
	else
		self.stats.frame:Hide()
	end

	local span = #self.hands * SQUARE + math.max(#self.hands - 1, 0) * GAP
	for index = 1, #self.hands do
		self.hands[index]:SetSize(SQUARE, SQUARE)
		self.hands[index]:ClearAllPoints()
		self.hands[index]:SetPoint("TOP", self.panel, "BOTTOM",
			(index - 1) * (SQUARE + GAP) + (SQUARE - span) / 2, -GAP)
	end

	-- Sized, not painted. This runs at login on a window nobody has opened, and
	-- the paint behind it walked nineteen slots, every stat and the durability of
	-- each piece for a page nothing could show. Character/Window.lua paints the
	-- tab that is up when the window comes up, and every other caller of Fit
	-- refreshes straight after it.
	return true
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

-- The figure again, and only where what you are wearing actually moved.
--
-- The squares are repainted on six events and the model was redressed on none
-- of them, so a weapon swapped with the sheet open changed the square and left
-- the figure holding the old one. Switching tab used to take the page down and
-- put it back, which redressed it by accident; the page does not go down any
-- more, because taking it down in a fight is a protected act, so the accident
-- is gone and this is the deliberate version.
--
-- The nineteen links are compared rather than a count or an event trusted:
-- UNIT_INVENTORY_CHANGED fires on a bag moving as well, and a model that
-- reloaded on every looted grey would flicker all evening. Comparing costs
-- nineteen table lookups and allocates nothing.
function Pane:Redress()
	local changed = false
	for index = 1, #self.squares do
		local slot = self.squares[index].entry.slot
		local link = ns.Worn.Link(slot)
		if self.worn[slot] ~= link then
			self.worn[slot] = link
			changed = true
		end
	end
	if changed and self.panel and self.panel.Dress then
		self.panel.Dress()
	end
	return changed
end

function Pane:Paint()
	self:Redress()
	for index = 1, #self.squares do
		PaintSquare(self.squares[index])
	end
	if self.inner then
		self:PaintPortrait()
	end
	-- Only while the page is up, and that is a measurement rule rather than a
	-- saving: a sentence under a row is measured against the width it wraps to,
	-- and a font string on a page nobody has shown yet is not obliged to answer
	-- honestly. Character/Readout.lua keeps the other half of the same rule.
	if self.frame:IsShown() then
		self.stats:Set(ns.CharStats.Groups())
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
