local ADDON, ns = ...

local Paperdoll = {}
ns.Paperdoll = Paperdoll

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The gear page
--
-- Nineteen slots in two columns, the player standing full height in the gap
-- between them, and against the right edge who you are, what your gear adds up
-- to and every number the client knows about you.
--
-- **This page is the screen, not a page in a window.** The sheet it is drawn on
-- has no title bar, no border, no ground and no saved point: it is the size of
-- the monitor, fixed to it, and sits at the floor of the frame pile so
-- everything the player opens flows over the top. UI/Window.lua carries that as
-- `screen`, and its own comment says why each piece of chrome came off. What it
-- costs this file is that nothing here may assume a surface behind it. Every
-- string takes the rim rather than the flat face, and the only ground on the
-- page is the band under a stat row, which is a tint rather than a panel.
--
-- **The width is whatever the monitor is.** There is no fixed page any more, so
-- the two columns and the readings take the room they need and the figure gets
-- the rest, which on any screen worth playing on is most of it. That is the one
-- number this layout is built on: a column is as wide as an item's name wants
-- to be, and the middle is everything left over.
--
-- **The stats are the right hand column.** They were a tab of their own, which
-- meant the two halves of one question lived on two pages: the squares say what
-- you are wearing and the numbers say what wearing it does, and swapping a ring
-- to see the second one move is a tab press away from the first. So the stats
-- readout is a column down the right of this page, filled from the same
-- Character/Stats.lua and drawn by the same Character/Readout.lua that drew the
-- tab.
--
-- **The four readings are badges at the head of that column, over your name.**
-- They were four cells along the foot of the portrait, drawn on a band of
-- shadow laid over the model, and both of those went with the panel: a band of
-- shadow across a figure standing on the world is a smear, and the numbers
-- belong with the other numbers rather than on the picture. Each is a disc with
-- the value in it and the word under it, in the same order every time, so after
-- a week you read the second badge rather than the word durability. The
-- sentence each of them is worth is still in its hover and the window's own
-- footer still says all four in a line.
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
-- **The action is the size of the icon, and the rest of the row is the
-- camera's.** A square whose right click is an action cannot also pass the
-- right button through: it would draw and hover perfectly while its right click
-- went to the camera and nowhere else. That is a fair price on thirty-six
-- pixels and a bad one on a row two hundred wide, and this page is the whole
-- monitor now, so two columns of full width buttons is most of the left and
-- right of the screen with no camera in it. So the button is the disc, which is
-- where the client puts a slot's button and where a bag puts an item's, and the
-- row it sits on is an ordinary frame that takes the mouse for the hover and
-- hands the camera back with UI.PassCamera.
--
-- What that costs: a left click, a drag out and a drop in all want the icon
-- rather than the item's name beside it. That is what every other item in the
-- game already wants.
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
local WEAR = 2

-- How far inside the ring the icon sits, which is also how wide the band of
-- quality colour showing round it is.
local RIM = 3

-- How bright that band is with nothing pointing at it. Nineteen quality colours
-- at full strength is a page of coloured lights; at this they are a tint you
-- read without being shouted at, and the hover is what takes one to full.
local REST = 0.55

-- The socket dots. Three because three is the most holes anything in this
-- expansion has, and five pixels because a dot on the same line as an eleven
-- pixel number is a dot, and at seven it is a button.
local DOTS = 3
local DOT = 5

-- How far apart two rows in a column sit.
local GAP = 4

--------------------------------------------------------------------------
-- Everything else on this page is a share of the page's own height
--
-- Height and not width, and that is the whole of the layout. A character sheet
-- is a person standing up with two lists beside him: how tall he can be decides
-- how big he is, and everything drawn next to him should be the size it is
-- against him. Sized off the width instead, an ultrawide gets a sheet with a
-- giant on it and a four by three panel gets one with a doll, because the width
-- of a monitor says nothing about how much room a figure has to stand in.
--
-- The shares are bounded at both ends, because a share of a screen is not a
-- share of a name. A column has to hold "Bloodfang Spaulders of the Underworld"
-- and there is no point in it holding twice that, so the ceiling is the longest
-- name the game has and the floor is a disc with enough of a name beside it to
-- be worth printing.
--------------------------------------------------------------------------

-- How much of the page's height the figure stands in, and how wide the frame
-- around him has to be for that to be his whole height.
--
-- The client scales a model to the width of the frame holding it, so the width
-- is what decides how big the figure comes out and the height is only whether
-- there is room for all of him. A landscape frame is therefore a giant cropped
-- at the crown and the knees, which is what filling the page with him produced.
--
-- BUILD is narrower than a person is, deliberately. A standing humanoid is
-- about one wide to two tall, so a frame at that ratio is a figure that exactly
-- fills it and crops on the first tabard that hangs low or headdress that
-- stands up. Under it, the height has room to spare and the air is above his
-- head and under his feet where it belongs.
local FIGURE = 0.80
local BUILD = 0.46

-- One column of rows: the disc, a gutter and the name.
local COLUMN, COLUMN_MIN, COLUMN_MAX = 0.26, 170, 280

-- The stats column. Read as the row added up: a scroll bar, the widest name the
-- page prints beside a number, the gutter, and the room the value is pinned
-- into.
local READING, READING_MIN, READING_MAX = 0.28, 220, 320

-- The narrowest the figure is ever squeezed to. Under this the page is not a
-- character sheet, it is two lists with a keyhole between them, and the two
-- columns are what give way.
local STAGE_MIN = 160

-- A share of the height, held between the two widths it is worth having.
local function Share(height, fraction, least, most)
	return math.max(math.min(math.floor(height * fraction), most), least)
end

-- The head of that column, top to bottom: your name, the line under it saying
-- what you are, the air before the badges, the badges themselves and the word
-- under each one.
local NAME = M.heading + 5
local BADGE = 44
local BADGERIM = 2
local HEAD = NAME + 2 + M.small + M.gutter + BADGE + 2 + M.small

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
-- line. Every slot has one, weapons included: the three that used to sit under
-- the figure as bare discs are rows in the left column now, for the reason
-- Character/Worn.lua gives where the arrangement is written down.
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
	Words(box, entry)

	-- Under the name. Durability is the one fact about a piece that changes while
	-- you play, so it belongs on the line you are already reading, and a two pixel
	-- rule under an item's name is that line's own underscore rather than a bar
	-- competing with it.
	box.wear = ns.Fill(box, "OVERLAY", C.tick[1], C.tick[2], C.tick[3], 1)
	box.wear:SetHeight(WEAR)
	box.wear:SetPoint("BOTTOM" .. (entry.side == "right" and "RIGHT" or "LEFT"),
		box.name, "BOTTOM" .. (entry.side == "right" and "RIGHT" or "LEFT"), 0, -1)
	box.wear:Hide()

	-- The line the client already knows. `/use 16` is what every sharpening
	-- stone macro in the game carries, and it is the same line for all nineteen
	-- slots with the number changed.
	local use = ("/use %d"):format(entry.slot)

	-- The disc and not the row. See the note at the head of the file: the row is
	-- the camera's and the button is the thirty-six pixels of icon in it.
	local button = CreateFrame("Button", nil, pane.frame, "SecureActionButtonTemplate")
	button:SetAllPoints(box.face)
	button:SetFrameLevel(box:GetFrameLevel() + 1)
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
	-- Two frames answer the mouse over one row, the row and the disc on it, and
	-- a hover is the same hover on either. Anchored to the box rather than to
	-- whichever frame the cursor is in, so crossing onto the icon does not move
	-- the tooltip.
	--
	-- On the square rather than in the corner. A worn piece is an object you are
	-- pointing at, and comparing two of them means reading one box against the
	-- square beside it.
	local function Enter()
		box.lit = true
		Ring(box, box.tone)
		ns.Tip.Open(box, Subject(entry), nil, ns.UI.Tooltip.BESIDE)
	end

	local function Leave()
		box.lit = nil
		Ring(box, box.tone)
		ns.Tip.Close()
	end

	button:SetScript("OnEnter", Enter)
	button:SetScript("OnLeave", Leave)

	-- The row. It answers nothing but the hover, so every button that lands on
	-- it goes to the world and the right drag turns the camera.
	box:EnableMouse(true)
	box:SetScript("OnEnter", Enter)
	box:SetScript("OnLeave", Leave)
	UI.PassCamera(box)

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
	local tone = quality and UI.Quality[quality] or C.dim
	box.name:SetText(link and (ns.ItemInfo(link)) or entry.label)
	box.name:SetTextColor(tone[1], tone[2], tone[3])
	local level = link and ns.ItemLevel(link)
	box.note:SetText(level and level > 0 and ("%d"):format(level) or "")
	PaintDots(box, link)

	local has, of = ns.Worn.Durability(entry.slot)
	if has then
		local fraction = has / of
		box.wear:SetWidth(math.max(
			UI.Round(box, box.name:GetWidth() * fraction), 1))
		UI.Tint(box.wear, WearTone(fraction))
		box.wear:Show()
	else
		box.wear:Hide()
	end
end

--------------------------------------------------------------------------
-- The four readings
--
-- Four badges at the head of the stats column, in this order, always. A number
-- that moves is a number you have to read the label of; these four never move,
-- so after a week you read the second badge rather than the word durability.
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
-- The head of the stats column
--
-- Your name, what you are, and the four readings as discs under it. It is the
-- top of the right hand column rather than anything drawn on the figure,
-- because a page with no ground has nowhere to put a caption except beside the
-- other captions, and because these four numbers are read against the stats
-- under them rather than against the picture.
--------------------------------------------------------------------------

-- One reading. A disc with the number in it, a ring of colour round the disc,
-- the word under it, and the sentence in the hover.
--
-- Discs rather than the cells this was, for the same reason a gear slot is a
-- disc: the page has one shape on it and a rectangle in the middle of nineteen
-- circles is the one thing on it that looks borrowed.
local function Badge(head, index)
	local badge = CreateFrame("Frame", nil, head)

	-- The mouse for the hover and every button back to the world. A reading
	-- answers no click, and a disc that ate the right button would be a hole in
	-- the middle of the screen the camera will not turn in.
	badge:EnableMouse(true)
	UI.PassCamera(badge)

	badge.ring = UI.Disc(badge, "BACKGROUND")
	badge.ring:SetSize(BADGE, BADGE)
	badge.ring:SetPoint("TOP")

	-- The dark inside the ring, so the number is read against the theme's own
	-- sunken rather than against whatever the player is standing on. It is the
	-- one opaque shape on the page and it is forty-four pixels across.
	badge.face = UI.Disc(badge, "ARTWORK")
	badge.face:SetPoint("TOPLEFT", badge.ring, "TOPLEFT", BADGERIM, -BADGERIM)
	badge.face:SetPoint("BOTTOMRIGHT", badge.ring, "BOTTOMRIGHT", -BADGERIM, BADGERIM)
	badge.face:SetVertexColor(C.sunken[1], C.sunken[2], C.sunken[3], 0.85)

	badge.value = UI.Label(badge, M.font, C.accent, "CENTER", UI.SHADOW)
	UI.Wrap(badge.value, false)
	badge.value:SetPoint("LEFT", badge.ring, "LEFT", 2, 0)
	badge.value:SetPoint("RIGHT", badge.ring, "RIGHT", -2, 0)

	-- Anchored to the badge rather than to the disc, because "item level" is
	-- wider than forty-four pixels and the cell it sits in is not.
	badge.label = UI.Label(badge, M.small, C.dim, "CENTER", UI.SHADOW)
	UI.Wrap(badge.label, false)
	badge.label:SetPoint("TOPLEFT", 0, -(BADGE + 2))
	badge.label:SetPoint("TOPRIGHT", 0, -(BADGE + 2))
	badge.label:SetText(LABELS[index])

	badge:SetScript("OnEnter", function(self)
		ns.Tip.Open(self, { kind = "note", title = LABELS[index],
			lines = { { self.note or "", color = C.dim } } }, true)
	end)
	badge:SetScript("OnLeave", function()
		ns.Tip.Close()
	end)

	return badge
end

-- The level is handed in and set before anything is put on the head, because a
-- frame takes its parent's level at the moment it is created and the badges
-- have to come out over the figure rather than under it.
local function Head(parent, level)
	local head = CreateFrame("Frame", nil, parent)
	head:SetFrameLevel(level)

	head.name = UI.Label(head, NAME, C.heading, "CENTER", UI.SHADOW)
	UI.Wrap(head.name, false)
	head.name:SetPoint("TOPLEFT")
	head.name:SetPoint("TOPRIGHT")

	head.level = UI.Label(head, M.small, C.text, "CENTER", UI.SHADOW)
	UI.Wrap(head.level, false)
	head.level:SetPoint("TOPLEFT", head.name, "BOTTOMLEFT", 0, -2)
	head.level:SetPoint("TOPRIGHT", head.name, "BOTTOMRIGHT", 0, -2)

	head.badges = {}
	for index = 1, #LABELS do
		head.badges[index] = Badge(head, index)
	end
	return head
end

--------------------------------------------------------------------------
-- The portrait
--------------------------------------------------------------------------

-- The figure and nothing else. It used to be a sunken box with a hairline round
-- it and two bands of shadow laid over it, and all three went when the sheet
-- stopped being a window: a panel behind a model standing on the world is a
-- rectangle of paint cut out of the scenery, and a band of shadow across the
-- figure is a smear on the one thing the page is built around.
local function Portrait(parent)
	local panel = CreateFrame("Frame", nil, parent)

	-- PlayerModel is a frame type rather than a template, so it costs nothing
	-- to exist on either client, and both calls on it are probed. A client that
	-- will not draw a model leaves the panel empty and every square around it
	-- still works, which is the honest degradation.
	local model = CreateFrame("PlayerModel", nil, panel)
	model:SetAllPoints()
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
	return panel
end

--------------------------------------------------------------------------

function Paperdoll.New(parent)
	local pane = setmetatable({ squares = {}, left = {}, right = {},
		worn = {} }, Pane)
	pane.frame = CreateFrame("Frame", nil, parent)

	-- Sorted into the two columns once, because which column a slot is in is a
	-- fact about the slot and not about the width the page came out at.
	for _, entry in ipairs(ns.Worn.Slots()) do
		local box = Square(pane, entry)
		pane.squares[#pane.squares + 1] = box
		local group = pane[entry.side]
		group[#group + 1] = box
	end

	pane.panel = Portrait(pane.frame)

	-- Everything on the page sits over the figure, and that is what putting the
	-- model behind the page costs. A model is drawn over every texture layer of
	-- the frame that holds it, so frame level is the only thing it goes behind.
	-- The secure button goes one higher than its row, because a click has to
	-- reach it through the name as well as through the disc.
	local level = pane.panel:GetFrameLevel() + 5
	for index = 1, #pane.squares do
		pane.squares[index]:SetFrameLevel(level)
		pane.squares[index].button:SetFrameLevel(level + 1)
	end

	-- Who you are and what your gear adds up to, at the top of the right hand
	-- column. Over the figure by the same rule as the rows: the model is wider
	-- than the gap it stands in on a narrow screen, and a name drawn under it
	-- would be a name that vanishes when the sheet is opened on a laptop.
	pane.head = Head(pane.frame, level)

	-- The same readout the stats tab was, hosted here instead and drawn compact:
	-- a line a row, with the sentence under it moved into the hover. It keeps
	-- its own scroll view, so a long sheet on a short screen scrolls beside a
	-- figure that does not move.
	pane.stats = ns.CharReadout.New(pane.frame, { compact = true })
	return pane
end

-- Ten rows down the left, nine down the right, the figure standing between
-- them, and the readings and the stats down the far right. Placed rather than
-- stacked, because this is one arrangement of a fixed number of rows and a
-- layout engine would be a layer between the numbers and the picture.
--
-- Nothing here is measured against the width it is handed. The page is the
-- screen, so that width is a different number on every machine and says nothing
-- about how much room the page needs: the three columns and the stage between
-- them are shares of the height, held between the two widths each is worth
-- having, and what is left over is margin split evenly. A wider monitor is a
-- sheet with more air round it and the same sheet in the middle, which is the
-- only answer that does not put the name of your helmet a third of a screen
-- away from the helmet.
function Pane:Resize(width, height)
	self.frame:SetSize(width, height)

	-- The stats column comes off the right first, because it is the one thing on
	-- the page that is a fixed shape: a name, a number, and the gutter between
	-- them. Then the two columns, then whatever the figure is left with, and only
	-- the figure gives way, because a name clipped in half is worse than a
	-- smaller character.
	local reading = Share(height, READING, READING_MIN, READING_MAX)
	local gear = math.max(width - reading - M.gutter, 1)
	local column = math.min(Share(height, COLUMN, COLUMN_MIN, COLUMN_MAX),
		math.max(UI.Round(self.frame, (gear - STAGE_MIN) / 2), SQUARE))

	-- How much room the figure has and how much of it he uses. The panel is a
	-- portrait rather than the whole page: the client fits a model to the frame
	-- it is in, so a frame as wide as the gear area is a figure whose head and
	-- feet are off the top and bottom of it.
	local tall = UI.Round(self.frame, height * FIGURE)
	local stage = math.max(
		math.min(UI.Round(self.frame, tall * BUILD), gear - column * 2), STAGE_MIN)
	local block = column * 2 + stage
	local edge = math.max(UI.Round(self.frame, (gear - block) / 2), 0)
	self.width = gear

	-- The rows are centred down the height rather than stacked from the top.
	-- On a screen this tall a column pinned to the top edge is ten rows and
	-- half a monitor of nothing under them, and the eye reads a column against
	-- the figure beside it rather than against the ceiling.
	local rows = math.max(#self.left, #self.right)
	local top = math.max(UI.Round(self.frame,
		(height - (rows * SQUARE + (rows - 1) * GAP)) / 2), 0)

	for index = 1, #self.left do
		self.left[index]:SetSize(column, SQUARE)
		self.left[index]:ClearAllPoints()
		self.left[index]:SetPoint("TOPLEFT", edge, -(top + (index - 1) * (SQUARE + GAP)))
	end
	for index = 1, #self.right do
		self.right[index]:SetSize(column, SQUARE)
		self.right[index]:ClearAllPoints()
		self.right[index]:SetPoint("TOPRIGHT", self.frame, "TOPLEFT",
			edge + block, -(top + (index - 1) * (SQUARE + GAP)))
	end

	-- The figure in the gap the two columns leave, centred on it, with the air
	-- the page's height did not give him split above his head and under his feet.
	self.panel:ClearAllPoints()
	self.panel:SetPoint("TOPLEFT", edge + column,
		-UI.Round(self.frame, (height - tall) / 2))
	self.panel:SetSize(stage, math.max(tall, 1))

	self.head:ClearAllPoints()
	self.head:SetPoint("TOPRIGHT")
	self.head:SetSize(reading, HEAD)
	self:Badges(reading)
	self.stats.frame:ClearAllPoints()
	self.stats.frame:SetPoint("TOPRIGHT", self.head, "BOTTOMRIGHT", 0, -M.gutter)
	self.stats:Resize(reading, math.max(height - HEAD - M.gutter, 1))

	-- Sized, not painted. This runs at login on a window nobody has opened, and
	-- the paint behind it walked nineteen slots, every stat and the durability of
	-- each piece for a page nothing could show. Character/Window.lua paints the
	-- tab that is up when the window comes up, and every other caller of Fit
	-- refreshes straight after it.
	return true
end

-- The four badges across the head of the stats column, an equal slice each. The
-- last one takes the remainder, so the row ends on the column's own edge rather
-- than a rounding error short of it.
function Pane:Badges(width)
	local badges = self.head.badges
	local slice = math.floor(width / #badges)

	for index = 1, #badges do
		local last = (index == #badges)
		badges[index]:ClearAllPoints()
		badges[index]:SetPoint("TOPLEFT", self.head, "TOPLEFT",
			(index - 1) * slice, -(NAME + 2 + M.small + M.gutter))
		badges[index]:SetSize(last and (width - slice * (#badges - 1)) or slice,
			BADGE + 2 + M.small)
	end
	return width
end

-- Your name, what you are, and the four readings. The tone is on the ring as
-- well as on the number, because a durability badge that has gone amber is a
-- thing you want to catch out of the corner of an eye while you are reading
-- something else, and eleven pixels of coloured text is not that.
function Pane:PaintHead()
	local head = self.head
	head.name:SetText(UnitName("player") or "You")
	head.level:SetText(("level %d %s")
		:format(UnitLevel("player") or 0, ns.Class.Label()))

	local read = Readings()
	for index = 1, #head.badges do
		local badge = head.badges[index]
		local tone = read[index].tone or C.accent
		badge.value:SetText(read[index].value)
		badge.value:SetTextColor(tone[1], tone[2], tone[3])
		badge.ring:SetVertexColor(tone[1], tone[2], tone[3], 1)
		badge.note = read[index].note
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
	self:PaintHead()
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
