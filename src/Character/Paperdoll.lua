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
-- **The stats and the skills are the right hand column.** Both were tabs of
-- their own, which meant the two halves of one question lived on two pages: the
-- squares say what you are wearing and the numbers say what wearing it does, and
-- swapping a ring to see the second one move is a tab press away from the first.
-- The skills went the same way and for a sharper version of the same reason: the
-- miss badge at the head of this column is computed from your weapon skill. So
-- the readout is a column down the right of this page, filled from
-- Character/Stats.lua and Character/Skills.lua and drawn by the same
-- Character/Readout.lua that drew both tabs.
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
-- **The figure is yours to turn.** Left drag turns him, the wheel walks him
-- nearer and further, and a mark in his bottom corner puts his weapons in his
-- hands. All three are remembered per character, so the sheet opens the way you
-- left it, and the two the wheel drives stop at both ends: the page is half a
-- monitor with no reset on it, and a figure wound out of that half is a bug the
-- player can only undo by winding the wheel back. The right button is the
-- camera's throughout, by the rule the rows keep.
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

-- The socket discs. Three because three is the most holes anything in this
-- expansion has, and that has not changed.
--
-- Twelve pixels and not five. Five was the width of a mark that says a socket
-- is there, and a mark is all it could be while the disc was flat colour. It
-- carries the gem's own icon now, and a gem icon at five pixels is four
-- coloured dots and a rounding error. At twelve it is a picture you can name
-- across a row, and it is still shorter than the name above it.
local DOTS = 3
local DOT = 12

-- How much of the disc the ring round the gem keeps for itself, which is the
-- same bargain RIM strikes on the thirty-six pixel face and cannot be the same
-- number: three of twelve is a quarter of the disc gone to its own edge. Two
-- leaves a band of colour all the way round and eight pixels of gem inside it.
local BAND = 2

-- How far apart two rows in a column sit.
local GAP = 4

--------------------------------------------------------------------------
-- The line under a name
--
-- It said the item level and nothing else. On a character at the level cap
-- every piece is enchanted, and the sheet is where you go to find out which one
-- you forgot: an unenchanted pair of boots is invisible on the figure, absent
-- from every number on the page, and worth as much as the difference between
-- two tiers of the same slot.
--
-- So the line carries three things now and they read near end first: the item
-- level, how long is left on the stone or the oil, and what is enchanted on it.
--
-- **The order mirrors with the column.** The right hand rows are justified to
-- their own disc, so the string ends at the disc rather than starting there,
-- and printing the three in the same order on both sides would put the level
-- against the disc on the left and against the middle of the page on the right.
-- Narcissus swaps the pair at Main.lua:1621 for the same reason on the same
-- line, and what it buys is that the number you scan a column for is always the
-- one nearest the picture.
--
-- **The enchant is the half that gives way.** Something long, like the name of
-- a two hander's spell damage enchant, is at the far end in both columns, where
-- a row that is too narrow for it clips it. The level and the time are short
-- and never lose a digit.
--
-- The two spaces are the gap between them. A separator would be a third thing
-- on a line that already carries three, and the strings are three different
-- colours already.
local SPACE = "  "

-- A palette entry as the escape the client colours part of a string with.
--
-- One string of three, so the escapes rather than three font strings. Three
-- strings would each need an anchor to the end of the one before it, which is a
-- width nothing knows until the repaint has set the text, and the wash under
-- the row is measured off the note's own width: it would have to add three of
-- them up and get the gaps right as well. The client already colours a run
-- inside a font string and counts none of it in GetStringWidth.
local function Ink(color)
	return ("|cff%02x%02x%02x"):format(
		math.floor(color[1] * 255), math.floor(color[2] * 255), math.floor(color[3] * 255))
end

-- Green for the enchant, because green is what the client's own tooltip writes
-- that line in and the page is not going to teach a second colour for it. The
-- level and a healthy time keep the note's own dim, so the enchant is the only
-- thing on the line that asks to be read.
local ENCHANT_INK = Ink(C.tick)

-- And red once there is not enough left to be worth planning around. A stone
-- runs an hour, so five minutes is the point where the answer stops being "it
-- is fine" and starts being "do it before the pull".
local LAPSING_INK = Ink(C.loss)
local LAPSING = 5

-- How often the time left is looked at again, and it is the smallest useful
-- number rather than the cheapest.
--
-- The line counts in whole minutes for an hour and in whole seconds for the
-- last one, so a tick slower than a second would show a stale figure through
-- the part of the countdown anybody is watching. What it costs is one pass over
-- three rows a second while the sheet is open, and the write behind it happens
-- fifty nine times an hour rather than once a second.
local LAPSE = 1

-- The wash under a row's two strings: how much taller it is than the pair of
-- them, and how much wider than the longer of them.
--
-- Eighteen is a line of air over the name and the same under the item level,
-- which is what stops the shadow reading as an underline. Forty-eight is the
-- disc and its gutter at the near end, where the wash is solid, plus what is
-- left over at the far end, where it has already faded to nothing.
--
-- Forty-eight is also why nothing clamps the total to the row. The name is
-- measured clamped to the room it had, which is the row less the disc and the
-- gutter, so the widest this can come out is the row plus twelve less that
-- gutter of eight: four pixels, at the transparent end.
local WASH_TALL = 18
local WASH_WIDE = 48

--------------------------------------------------------------------------
-- Everything else on this page is a share of the page's own width
--
-- Width, and it used to be height. Height was the right answer while the page
-- was the monitor: the sheet was handed whatever ratio the player's panel
-- happened to be, and the width of a monitor says nothing about how much room a
-- figure has to stand in, so the figure and the columns beside him were sized
-- off the one number that meant something.
--
-- The page is not the monitor any more. It is half of it at four by three, so
-- its shape is fixed and known here, and the number the three columns and the
-- figure are actually competing for is the width. Splitting the width is what
-- that competition is, and doing it in the units it happens in is what stops
-- three columns adding up to more page than there is.
--
-- The shares are bounded at both ends, because a share of a page is not a share
-- of a name. A column has to hold "Bloodfang Spaulders of the Underworld" and
-- there is no point in it holding twice that, so the ceiling is the longest
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
local COLUMN, COLUMN_MIN, COLUMN_MAX = 0.225, 130, 280

-- The stats column. Read as the row added up: a scroll bar, the widest name the
-- page prints beside a number, the gutter, and the room the value is pinned
-- into.
local READING, READING_MIN, READING_MAX = 0.27, 165, 320

-- The narrowest the figure is ever squeezed to. Under this the page is not a
-- character sheet, it is two lists with a keyhole between them, and the two
-- columns are what give way.
local STAGE_MIN = 150

-- A share of a number, held between the two widths it is worth having.
local function Share(room, fraction, least, most)
	return math.max(math.min(math.floor(room * fraction), most), least)
end

-- The head of that column, top to bottom: your name, the line under it saying
-- what you are, the air before the badges, the badges themselves and the word
-- under each one.
local NAME = M.heading + 5
local BADGE = 44
local BADGERIM = 2
local HEAD = NAME + 2 + M.small + M.gutter + BADGE + 2 + M.small

-- The mark in the corner of the figure. Wide enough for the longer of its two
-- words at eleven pixels and no wider, because it stands on the figure and
-- every pixel of it is a pixel of him.
local SHEATHE = 52

--------------------------------------------------------------------------
-- The pose
--
-- Three numbers: which way he is facing, how near he stands, and whether his
-- weapons are in his hands. They live in this character's own saved variables
-- and Character/Feature.lua declares them, because a pose is not an account
-- wide preference: the angle that reads on a tauren warrior is not the angle
-- that reads on a gnome, and one number serving both is one of them wrong.
--
-- 0.010 radians to the pixel is Blizzard's own MODELFRAME_DRAG_ROTATION_CONSTANT
-- out of the FrameXML this client ships. Matching it means a drag on this figure
-- and a drag in the client's own dressing room move the same amount, which is
-- the whole of what a player has already learnt about turning a model.
local TURN = 0.010
local TWOPI = math.pi * 2

-- One notch of the wheel, and the two calls the number it writes turns into.
--
-- `near` runs from nothing to one and stops dead at both ends. The sheet is
-- half the screen and there is no reset on the page, so a figure wound past
-- either end is a camera inside his chest or a dot in the middle of a page,
-- and neither is undone by anything except winding the wheel back.
--
-- Both calls, because one on its own does the wrong thing. SetCamDistanceScale
-- brings the camera in on the model's own origin, which on a character is
-- between his feet, so half distance on its own is a close look at a pair of
-- boots. SetPosition moves the model, and positive z is up: Blizzard's own pan
-- in ModelFrames.lua adds the cursor's rise to z and the figure follows it
-- upward. So he sinks by as much as the camera comes in, and what fills the
-- panel at the near end is a man rather than the ground he is standing on.
local STEP = 0.1
local CLOSEST = 0.5
local SINK = -0.35

local Pane = {}
Pane.__index = Pane

-- The one gear page there is, so the tick that counts the oil down can find it.
--
-- A file local rather than the frame the tick hangs off, which is how the turn
-- above reaches its model and how every other instance-owned tick in the addon
-- reaches its instance. This one hangs off ns.UI.Forever instead: three rows
-- once a second is not worth a frame of its own, and a tick on a frame of its
-- own owes scripts/check.sh an entry defending a frame that can hide. The
-- visibility test at the top of Lapse is what that entry would have said,
-- written as one comparison a second.
--
-- Character/Window.lua builds exactly one of these and never takes it down,
-- because the page holds nineteen secure buttons and hiding one of those in a
-- fight is a protected act. A second page would be a second thing this pointed
-- at and the sheet has no way to grow one.
local page

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

	-- The ground the two strings are read on, because the page has none. Solid
	-- at the disc and gone by the far end of the name, so it is a shadow the
	-- size of the thing casting it rather than a panel behind the row.
	--
	-- Its direction is the row's. A left hand row reads outward from the disc on
	-- the left, a right hand row reads inward from the disc on the right, and a
	-- wash pinned to one of those runs backwards under the other: solid where
	-- there is no text and clear under every letter.
	--
	-- On the row itself and on BACKGROUND, so it passes under the disc's frame,
	-- under the strings and under the durability rule without anything having to
	-- be raised over it. Made here and sized by the repaint, because how wide it
	-- has to be is how wide the name came out.
	box.wash = UI.Wash(box, C.shadow, near)
	box.wash:SetPoint(near, box, near)

	box.name = UI.Label(box, M.font, C.text, near, UI.SHADOW)
	UI.Wrap(box.name, false)
	box.name:SetPoint("TOP" .. near, box.face, "TOP" .. far, sign * M.gutter, -2)
	box.name:SetPoint("TOP" .. far, box, "TOP" .. far, 0, -2)

	-- Under the name and under the rule that goes under the name. The two used
	-- to share a line: the rule was hung across the name's own bottom edge and
	-- the level was hung one pixel under it, so a full piece had a green line
	-- drawn through the foot of its own letters and a number sitting on top of
	-- the line. Everything below the name drops by the height of the rule and
	-- the row has the pixels to spare.
	box.note = UI.Label(box, M.small, C.dim, near, UI.SHADOW)
	UI.Wrap(box.note, false)
	box.note:SetPoint("TOP" .. near, box.name, "BOTTOM" .. near, 0, -(WEAR + 3))
	box.note:SetPoint("TOP" .. far, box.name, "BOTTOM" .. far, 0, -(WEAR + 3))

	-- One per socket a piece in this slot could carry, and each is two textures:
	-- the disc, which is the ring, and the gem's own icon laid over it inset by
	-- BAND so that a band of the disc shows all the way round. Both are made at
	-- build and shown by the repaint, because a texture made on a repaint is a
	-- texture made nineteen times every time anything you are wearing moves.
	--
	-- The icon is clipped to the same circle. A gem icon is a square picture and
	-- the file has corners in it, and a square in a row of discs is the one that
	-- reads as broken rather than as square.
	box.dots = {}
	for index = 1, DOTS do
		local dot = UI.Disc(box, "OVERLAY")
		dot:SetSize(DOT, DOT)
		-- One point and not two. The far edge used to be pinned to the row and the
		-- top to the item level under the name, which is one constraint on the
		-- disc's middle and another on its top edge: over-constrained in y, so the
		-- height the anchors imply wins over SetSize and a disc twelve wide came
		-- out an ellipse twenty-two tall. The row's own far edge is the note's far
		-- edge, because the note is anchored across the full width, so one point
		-- on the note says both things and the disc keeps the size it was given.
		dot:SetPoint(far, box.note, far, sign * -((index - 1) * (DOT + 2)), 0)
		dot:Hide()

		dot.gem = box:CreateTexture(nil, "OVERLAY", nil, 1)
		dot.gem:SetSize(DOT - BAND * 2, DOT - BAND * 2)
		dot.gem:SetPoint("CENTER", dot, "CENTER", 0, 0)
		UI.Clip(dot.gem)
		dot.gem:Hide()

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
	box.wear:SetPoint("TOP" .. (entry.side == "right" and "RIGHT" or "LEFT"),
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
	--
	-- UI.HoverOnly and not EnableMouse with the camera's buttons handed back:
	-- this client has no SetPassThroughButtons, so that pair was a row two hundred
	-- and eighty pixels wide swallowing the drag, nineteen times, on a sheet the
	-- size of the monitor. UI/Tip.lua carries which call the client actually has.
	UI.HoverOnly(box)
	box:SetScript("OnEnter", Enter)
	box:SetScript("OnLeave", Leave)

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

-- The discs under a name, and what is sitting in each one.
--
-- A filled socket is the gem: its own icon, clipped round, in a ring of its
-- quality colour. A hole is the same disc with nothing in it and the ring at
-- half strength, which is the difference between a thing and a place for one
-- without either of them needing a label.
--
-- Filled first and holes after, which is the order the client can actually
-- answer: a link says what is in it and how many are open, and never which
-- position an open one is.
--
-- A hole is drawn neutral, and that is the data rather than a preference. A
-- socket is meta, red, yellow or blue, and that colour is a fact about the
-- item; an item link carries the gem sitting in each filled hole and says
-- nothing whatever about the empty ones. There is no call that recovers it and
-- guessing it from the slot is a colour the page would be making up. So the
-- ring takes the gem's colour where there is a gem and the panel's edge where
-- there is not, and the hover is where a socket gets named: the client writes
-- "Yellow Socket" into the tooltip for the slot, and that tooltip is the one
-- the row already opens.
local function PaintDots(box, link)
	local filled, open = ns.ItemSockets(link)
	local count = filled and #filled or 0
	for index = 1, DOTS do
		local dot = box.dots[index]
		local gem = filled and filled[index]
		local icon = gem and select(2, ns.ItemInfo(gem)) or nil
		local tone = gem and UI.Quality[ns.ItemValue(gem) or 1] or C.edge
		dot:SetVertexColor(tone[1], tone[2], tone[3], gem and 1 or 0.5)
		dot:SetShown(index <= count + open)
		dot.gem:SetTexture(icon)
		dot.gem:SetShown(icon and index <= count and true or false)
	end
end

-- The line under one row's name, out of the three things that row might have.
--
-- Every join sits behind the test for the piece it joins. That is the rule
-- every function a tick can reach is held to, and here it costs nothing to
-- keep: sixteen of the nineteen rows have a level and nothing else, and on
-- those this allocates the level's own string and stops.
local function Note(box)
	local named
	if box.enchant then
		named = ENCHANT_INK .. box.enchant .. "|r"
	end

	-- Coloured first and ordered after, because the two are swapped and the
	-- escape belongs to the enchant rather than to the end of the line it lands
	-- on. Swapping the two before either is dressed puts the green on the item
	-- level in one of the two columns, which is a page that reads perfectly and
	-- says the wrong thing on half of it.
	local first, last = box.level, named
	if box.entry.side == "right" then
		first, last = named, box.level
	end

	local line = first or ""
	if box.oil then
		local time = box.oil .. box.oilUnit
		if box.oilUnit == "s" or box.oil <= LAPSING then
			time = LAPSING_INK .. time .. "|r"
		end
		line = line ~= "" and (line .. SPACE .. time) or time
	end
	if last then
		line = line ~= "" and (line .. SPACE .. last) or last
	end
	return line
end

-- One weapon row's time left, written only where the figure on it moved.
--
-- The count and its unit are kept apart rather than the string being kept,
-- because the comparison has to be on the number. A tick that builds its label
-- and then compares the label has already paid for the label, and the
-- comparison reads as a guard while letting every tick through; that is item
-- 34, found on the threat percentage and the same shape here.
--
-- Whole minutes for the hour a stone runs and whole seconds for the last one.
-- Minutes alone would spend the last minute saying 1 through the part of it
-- anybody is watching, and seconds alone are four digits nobody reads.
local function Lapsed(box)
	local left = ns.Worn.Oil(box.entry.slot)
	local count, unit
	if left then
		if left < 60 then
			count, unit = math.floor(left), "s"
		else
			count, unit = math.floor(left / 60), "m"
		end
	end
	if count ~= box.oil or unit ~= box.oilUnit then
		box.oil, box.oilUnit = count, unit
		box.note:SetText(Note(box))
		return true
	end
	return false
end

-- The three weapon rows, once a second, and only while the sheet is on screen.
--
-- The page's own frame is shown from the moment it is built and never hidden
-- again, so its flag says nothing about whether anybody can see it. What can be
-- seen is the window above it, which is why this asks the question the whole way
-- up the chain rather than of the row it is about to write on.
local function Lapse()
	if not page or not page.frame:IsVisible() then
		return false
	end
	local hands = page.hands
	local moved = false
	for index = 1, #hands do
		if Lapsed(hands[index]) then
			moved = true
		end
	end
	return moved
end

UI.Ticker(UI.Forever, LAPSE, "oil", Lapse)

-- How much of a string the row actually draws.
--
-- Every string on a row is anchored at both ends so it can clip rather than
-- wrap, which makes its frame the width of the column every time and makes its
-- own measurement the full length of the text however much of that is cut off.
-- Neither number on its own is the answer: what the rule under a name and the
-- shadow under the pair of them are as wide as is the part you can see, and
-- that is the smaller of the two.
--
-- One function because it was one idea written twice. The name has been clamped
-- since the rule under it was drawn across the whole row; the line under it was
-- two digits then and could not reach the end of the shortest row on the page.
-- It carries an enchant's name now, which is longer than plenty of item names,
-- and the second copy of this is the one that would have been left out.
local function Drawn(text)
	local letters = text:GetStringWidth() or 0
	local room = text:GetWidth() or 0
	if room > 0 and letters > room then
		return room
	end
	return letters
end

-- The shadow the row's two strings are read on, sized now that both have their
-- text.
--
-- Every string on this page is a string over the world, so the size is the
-- whole of the answer: a wash wider than the letters is a smear beside the
-- name, and one narrower is a name half on the shadow and half on the grass.
--
-- Not drawn at all on an empty slot. The row still says what the slot is for,
-- dimmed, and a shadow under the word trinket is a shadow under nothing; eight
-- of the nineteen rows are empty on most characters and nineteen of them would
-- be a second page laid over the first.
--
-- The name's width is handed in rather than measured again, because the rule
-- under the name wants the same number and two readings of one measurement are
-- two things to get wrong.
local function PaintWash(box, link, letters)
	if not link then
		box.wash:Hide()
		return false
	end
	box.wash:SetSize(math.max(letters, Drawn(box.note)) + WASH_WIDE,
		UI.TextHeight(box.name, M.font) + UI.TextHeight(box.note, M.small) + WASH_TALL)
	box.wash:Show()
	return true
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
	box.level = level and level > 0 and ("%d"):format(level) or nil

	-- And the enchant, on the repaint that found the link changed and on no
	-- other.
	--
	-- A name for an enchant costs a tooltip scan, because the link carries the
	-- id and no client call turns one into a word. Nineteen of those on every
	-- repaint is nineteen tooltips filled and read back every time you loot a
	-- grey, and UI/Scan.lua does not cache on purpose: an item's text is the
	-- client's and a cache between the two is one more thing that can be stale
	-- while the page says otherwise.
	--
	-- So the question is asked where the answer can have changed, and Redress
	-- above already knows where that is. It compares the nineteen links against
	-- what the page drew last, for the figure, and the same comparison answers
	-- this: an enchant is part of the link, so a link that did not move carries
	-- the enchant it carried before.
	if box.fresh then
		box.fresh = false
		box.enchant = link and ns.Worn.Enchant(link) or nil
	end

	box.note:SetText(Note(box))
	PaintDots(box, link)

	-- The rule under the name is an underscore, so it is as wide as the letters
	-- and never as wide as the row. Read once here rather than inside the branch
	-- below, because the wash wants the same number.
	local letters = Drawn(box.name)

	local has, of = ns.Worn.Durability(entry.slot)
	if has then
		local fraction = has / of
		box.wear:SetWidth(math.max(UI.Round(box, letters * fraction), 1))
		UI.Tint(box.wear, WearTone(fraction))
		box.wear:Show()
	else
		box.wear:Hide()
	end

	return PaintWash(box, link, letters)
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
	UI.HoverOnly(badge)

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

-- The pose put on the model, and the only place in this file that writes one.
--
-- Every call is probed and then pcalled, which is the shape Dress already used
-- for the two it makes and is here for the same reason: a client that will not
-- draw a model has to leave the page working rather than raise in the middle of
-- a drag. All three of SetRotation, SetPosition and SetCamDistanceScale are on
-- 2.5.6: AdventureGuideClassic ships `## Interface: 20506` and calls the last
-- two unguarded on a model frame. SetSheathed is the one even Narcissus asks
-- for before it makes.
local function Pose(model)
	local near = ns.dbc.figureNear
	if model.SetRotation then
		pcall(model.SetRotation, model, ns.dbc.figureFacing)
	end
	if model.SetCamDistanceScale then
		pcall(model.SetCamDistanceScale, model, 1 - near * (1 - CLOSEST))
	end
	if model.SetPosition then
		pcall(model.SetPosition, model, 0, 0, near * SINK)
	end
	if model.SetSheathed then
		pcall(model.SetSheathed, model, ns.dbc.figureSheathed)
	end
	return near
end

-- The turn itself, one frame at a time while the button is down. Where the
-- cursor is now against where it was when the drag began, which is how the
-- client's own Model_OnUpdate does it.
--
-- A ticker rather than an OnUpdate of its own, because ns.UI.Ticker is what the
-- guard scan walks out from, and it hangs off the model rather than off
-- ns.UI.Forever so that a sheet shut mid drag stops turning a figure nobody can
-- see. The write is behind the comparison for the rule every tick in the addon
-- keeps: a SetRotation costs the same whether or not the angle moved.
local function Turn(_, model)
	local grab = model.grabbed
	if not grab then
		return false
	end
	local x = GetCursorPosition()
	local facing = (grab.facing + (x - grab.x) * TURN) % TWOPI
	if facing ~= ns.dbc.figureFacing then
		ns.dbc.figureFacing = facing
		Pose(model)
	end
	return true
end

-- Left drag turns him and the right button is the camera's.
--
-- ns.UI.PassCamera is how every row on this page hands back the two buttons it
-- does not want, and it is the most this client offers: SetPassThroughButtons
-- arrived in 10.1.5, so on 2.5.6 the probe fails and a right drag begun on the
-- figure still stops at him, exactly the way it stops at the model on Blizzard's
-- own sheet. What is not left to that call is the half this file owns. A right
-- press arms nothing, so the drag the player is making with it is not also
-- spinning the figure underneath.
local function Grab(model, button)
	if button and button ~= "LeftButton" then
		return false
	end
	model.grabbed = { x = GetCursorPosition(), facing = ns.dbc.figureFacing }
	model.turning:Start()
	return true
end

-- The way out, which is the button coming up or the sheet going down. One more
-- pass through Turn before the tick stops, because the last one ran a frame
-- before the button did and the figure would land a frame short of where it was
-- let go.
local function Drop(model, button)
	if button and button ~= "LeftButton" then
		return false
	end
	Turn(0, model)
	model.grabbed = nil
	model.turning:Stop()
	return true
end

-- The wheel walks him nearer and further, between the two ends the head of this
-- file argues for.
local function Walk(model, delta)
	local near = math.max(0, math.min(1, ns.dbc.figureNear + delta * STEP))
	if near ~= ns.dbc.figureNear then
		ns.dbc.figureNear = near
		Pose(model)
	end
	return near
end

-- What the mark says. The word is what pressing it does rather than what the
-- figure is doing, because a button is a verb.
local function Wield(sheathed)
	return sheathed and "draw" or "sheathe"
end

local function Bared(mark)
	ns.dbc.figureSheathed = not ns.dbc.figureSheathed
	mark.text:SetText(Wield(ns.dbc.figureSheathed))
	return Pose(mark.model)
end

-- The weapons, and a mark in the corner of the figure rather than a row on a
-- settings page. Putting a sword in his hands is the only way to look at a
-- weapon you are wearing: a model with its weapons away hides the one piece of
-- gear anybody actually chose behind his back, and nobody goes to a settings
-- window to look at a sword.
local function Mark(panel, model)
	local mark = UI.Button(panel, {
		width = SHEATHE, height = M.control,
		label = Wield(ns.dbc.figureSheathed),
		tip = "put your weapons in his hands, or back where they live",
		onClick = Bared,
	})
	mark.model = model
	mark:SetPoint("BOTTOMRIGHT")
	-- Over the figure rather than under him, by the rule the rows are placed by:
	-- a model is drawn over every texture layer of the frame holding it, so a
	-- frame level is the only thing that puts anything in front of one.
	mark:SetFrameLevel(panel:GetFrameLevel() + 5)
	return mark
end

-- The figure and nothing else. It used to be a sunken box with a hairline round
-- it and two bands of shadow laid over it, and all three went when the sheet
-- stopped being a window: a panel behind a model standing on the world is a
-- rectangle of paint cut out of the scenery, and a band of shadow across the
-- figure is a smear on the one thing the page is built around.
local function Portrait(parent)
	local panel = CreateFrame("Frame", nil, parent)

	-- PlayerModel is a frame type rather than a template, so it costs nothing
	-- to exist on either client, and every call on it is probed. A client that
	-- will not draw a model leaves the panel empty and every square around it
	-- still works, which is the honest degradation.
	local model = CreateFrame("PlayerModel", nil, panel)
	model:SetAllPoints()
	local function Dress()
		if model.SetUnit then
			pcall(model.SetUnit, model, "player")
		end
		Pose(model)
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
	--
	-- The pose goes on after the unit and on every reload, not once at login.
	-- SetUnit builds the figure again from nothing, so an angle applied when the
	-- panel was made would be gone the first time you put a ring on.
	model:SetScript("OnShow", Dress)
	-- And once more when the client says the figure is actually there. SetUnit
	-- loads a model asynchronously, so a pose written in the same frame is a
	-- pose written on nothing, and AdventureGuideClassic reapplies its own
	-- preset off this script on this client for that reason.
	model:SetScript("OnModelLoaded", Pose)

	model:EnableMouse(true)
	model:EnableMouseWheel(true)
	UI.PassCamera(model)
	-- Armed and immediately stopped, because a ticker starts running and this
	-- one has nothing to do until a button is down on the figure.
	model.turning = UI.Ticker(model, 0, "figure", Turn)
	model.turning:Stop()
	model:SetScript("OnMouseDown", Grab)
	model:SetScript("OnMouseUp", Drop)
	model:SetScript("OnHide", Drop)
	model:SetScript("OnMouseWheel", Walk)

	panel.model = model
	panel.Dress = Dress
	panel.mark = Mark(panel, model)
	return panel
end

--------------------------------------------------------------------------

function Paperdoll.New(parent)
	local pane = setmetatable({ squares = {}, left = {}, right = {},
		hands = {}, worn = {} }, Pane)
	pane.frame = CreateFrame("Frame", nil, parent)

	-- Sorted into the two columns once, because which column a slot is in is a
	-- fact about the slot and not about the width the page came out at.
	--
	-- And the three that can carry a stone into a third list, so the tick that
	-- counts one down walks three rows rather than nineteen. Which three is
	-- Character/Worn.lua's word, marked on the slot beside the column it is in,
	-- because both are facts about the slot.
	for _, entry in ipairs(ns.Worn.Slots()) do
		local box = Square(pane, entry)
		pane.squares[#pane.squares + 1] = box
		local group = pane[entry.side]
		group[#group + 1] = box
		if entry.hand then
			pane.hands[#pane.hands + 1] = box
		end
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

	page = pane
	return pane
end

-- Ten rows down the left, nine down the right, the figure standing between
-- them, and the readings and the stats down the far right. Placed rather than
-- stacked, because this is one arrangement of a fixed number of rows and a
-- layout engine would be a layer between the numbers and the picture.
--
-- The three columns and the stage between them are shares of the width, held
-- between the two widths each is worth having, and what is left over is margin
-- split evenly. The order they are cut in is the order they give way in: the
-- stats come off the right first because they are the one fixed shape on the
-- page, then a column each side, and the figure takes what is left, because a
-- name clipped in half is worse than a smaller character.
--
-- It was shares of the height, which was the right answer for a page that was
-- the whole monitor and the wrong one for a page with a shape of its own. The
-- head of the metrics block carries that argument.
function Pane:Resize(width, height)
	self.frame:SetSize(width, height)

	-- The stats column comes off the right first, because it is the one thing on
	-- the page that is a fixed shape: a name, a number, and the gutter between
	-- them. Then the two columns, then whatever the figure is left with, and only
	-- the figure gives way, because a name clipped in half is worse than a
	-- smaller character.
	local reading = Share(width, READING, READING_MIN, READING_MAX)
	local gear = math.max(width - reading - M.gutter, 1)
	local column = math.min(Share(width, COLUMN, COLUMN_MIN, COLUMN_MAX),
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
-- The row is told as well as the model, because the same comparison answers a
-- second question. PaintSquare has to scan a tooltip to name what is enchanted
-- on a piece, and an enchant is part of the link: a row whose link did not move
-- is a row whose enchant did not either. The flag is set here and cleared by
-- the repaint that reads it, so nineteen scans happen on the paint that found
-- something moved and none at all on the eight a minute that did not.
function Pane:Redress()
	local changed = false
	for index = 1, #self.squares do
		local box = self.squares[index]
		local slot = box.entry.slot
		local link = ns.Worn.Link(slot)
		if self.worn[slot] ~= link then
			self.worn[slot] = link
			box.fresh = true
			changed = true
		end
	end
	if changed and self.panel and self.panel.Dress then
		self.panel.Dress()
	end
	return changed
end

-- The stats, and then the skills under them, as one list.
--
-- Skills were a tab. They are a group in this column now, and the fold is one
-- list appended to another because Character/Skills.lua and Character/Stats.lua
-- already hand back the same shape: a title and a list of rows. The readout
-- draws whatever it is given and did not change.
--
-- They belong here rather than on a page of their own for the same reason the
-- stats do. The miss badge at the head of this column is computed from your
-- weapon skill, and the two had been on separate pages since the sheet was
-- built, so the number and what it is made of were one press apart.
local function Column()
	local groups = ns.CharStats.Groups()
	local skills = ns.CharSkills.Groups()
	for index = 1, #skills do
		groups[#groups + 1] = skills[index]
	end
	return groups
end

function Pane:Paint()
	self:Redress()
	for index = 1, #self.squares do
		PaintSquare(self.squares[index])
	end
	-- And the three hands again, straight after, rather than waiting for the
	-- tick. A sheet opened after an evening shut would otherwise show the figure
	-- the tick last wrote for up to a second, and the one it wrote is an hour
	-- old. Lapsed is asked directly rather than through Lapse, because Lapse
	-- refuses to run on a page nobody can see and this is the paint that puts one
	-- up.
	for index = 1, #self.hands do
		Lapsed(self.hands[index])
	end
	self:PaintHead()
	-- Only while the page is up, and that is a measurement rule rather than a
	-- saving: a sentence under a row is measured against the width it wraps to,
	-- and a font string on a page nobody has shown yet is not obliged to answer
	-- honestly. Character/Readout.lua keeps the other half of the same rule.
	if self.frame:IsShown() then
		self.stats:Set(Column())
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
