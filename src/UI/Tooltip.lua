local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The tooltip
--
-- Every hover in this addon went to the client's own tooltip until this
-- existed, and that was always the wrong box for it. Blizzard's is a
-- parchment: a tiled background asset, a gold border drawn from a corner sheet, Friz
-- Quadrata at whatever size the client's own tooltip scale says, and a shape
-- this addon has spent its whole life replacing everywhere else. A window with
-- a one pixel edge and a flat sans on it that raises a parchment scroll when
-- you hover a row is a window with two designs in it.
--
-- So this is the addon's own. Same palette, same metrics, same font cache,
-- same pixel grid. Nothing in it is a template and nothing in it is an asset.
--
-- **One tooltip, not one per owner.** A hover puts up one box, so there is one
-- frame with a pool of lines in it, refilled on every open. A tooltip per
-- hoverable row would be a frame and a dozen font strings per row in a feed
-- that holds four hundred of them.
--
-- A gear comparison is the one hover that needs more than one box, and it is
-- still not one per owner: it is a small pool of the same box, hung off the
-- side of the first, built by the same code and filled from the same data
-- shape. That is why a box is a value in this file rather than a set of
-- locals. See NewBox, and see `alongside` on Tooltip.Show.
--
-- **It is one size, and that size is the addon's.** Every box this file draws
-- comes out at the size the hover setting asks for, whatever it was opened on.
--
-- It used to take the owner's zoom instead, on the argument that a box six
-- hundred pixels across cannot explain a row thirty pixels tall. What that
-- bought in practice was a tooltip whose text changed size as the cursor
-- crossed the screen. The missing buff row ships at 2x, because four squares
-- over your character have to be readable from across a fight, and a square on
-- it opened a box in text twice the size of the one the action bar under it
-- opened. Neither box was wrong about its owner. The pair of them was wrong
-- about the addon, which has one body size and one heading size and had been
-- drawing both at whatever scale the widget under the cursor happened to want.
--
-- A tooltip is not part of the thing you hovered. It is a paragraph about it,
-- and how big the addon's paragraphs are is the size slider's answer, the same
-- answer every window here takes. So the size of a HUD widget is now about how
-- far away you read it from, and the size of text is one setting.
--
-- **It sits where the client's own tooltip sits.** The bottom right corner,
-- clear of the bags and of whatever action bars are switched on, read off the
-- client's own two clearances rather than written down here. A box that opens
-- beside the row under the cursor is a box covering the next row, and every
-- hover in this addon is over the middle of the screen where the fighting is.
-- Beside is still there behind a switch, because on a very wide screen the
-- corner is a long way from what you are reading.
--
-- **A caller hands over data, not a run of calls.** See the schema below. The
-- imperative writers this file used to publish are still here as locals and
-- are no longer a surface: five ways to write a line is five things a caller
-- can do in the wrong order, and the one that mattered, whether a title had
-- been written, was bookkeeping every caller had to get right.
--
-- **It draws, and it decides nothing.** What a tooltip says about the thing you
-- hovered is UI/Tip.lua's, and the client's own text for that thing is
-- UI/Scan.lua's. This file takes the finished description and puts it on the
-- screen. Three files rather than one because they change for different
-- reasons: the box changes when the theme does, the registry changes when a
-- part has something new to say, and the scanner changes when a client does.
--------------------------------------------------------------------------

local FRAME_NAME = "WarriorKitTooltip"

-- Every number here is a unit, which is one physical pixel inside a frame
-- ns.UI.Adopt has taken onto the grid, and a whole block of them above zoom 1.
--
-- These were half as generous again and it showed. A tooltip is not a dialog:
-- it is a label that follows the cursor, it is read in the half second before
-- you move on, and every unit of air in it is a unit of the game it is
-- covering. The wrap width is the number that does the most work, because it
-- alone decides the shape of the box: it holds about forty characters, which is
-- a sentence you take in without tracking back to the left edge and is narrower
-- than every item name in the game bar a few.
--
-- Forty characters is the number, not the pixels. 210 bought forty of Arial
-- Narrow at twelve; the face is Noto Sans now and 210 buys thirty six, so a box
-- kept at 210 answers a question about air with a different sentence shape than
-- the one the paragraph above argues for. 266 buys the forty back. It is more
-- of the fight covered and that is the trade this whole comment is about.
local PAD = 6       -- the edge to the first glyph
local GAP = 2       -- one line to the next
local COLUMN = 16   -- the least air between a label and its value
local RULE = 3      -- the air either side of the hairline under a title
local SPACER = 4    -- a blank line, which is air rather than an empty line
local MAX = 266     -- the widest a line is drawn before it wraps
local OFFSET = 4    -- the owner to the tooltip
-- The pointer's hotspot to the tooltip, which is a different number from the
-- one above and has to be. A frame has an edge to open clear of; a cursor has
-- art that hangs down and to the right of the hotspot, so a box four units off
-- the hotspot opens underneath the arrow that opened it.
local POINTER = 20

-- Where the client parks its own tooltip when nothing has anchored it: the
-- bottom right corner of the screen, held clear of the bags and of however many
-- rows of action bar are switched on. The client keeps that clearance in two
-- globals it rewrites whenever the bags open or a bar appears, and its own
-- default anchor puts thirteen more units between the box and the right edge.
-- Reading them is what "where the client has it" means. A pair of numbers
-- written here would be that corner on one layout and the wrong corner on the
-- next.
local DOCK = 13
-- What those two are before anything has moved them, for a client that defines
-- neither. The bare corner and one bag bar, which is the layout every value the
-- client writes into them is a variation on.
local DOCK_X, DOCK_Y = 0, 70

-- Two sizes and no more. A title that is the body size is not a title, and a
-- third size in a box this small is a typeface competition.
--
-- Both come off UI.Metric rather than being written here. They were 13 and 11,
-- and the 11 was the mistake: it is UI.Metric.small, the size the panel keeps
-- for a hint under a control, and a tooltip is not a footnote. Every line of a
-- tooltip is the thing you opened it to read, so its body is the addon's body
-- size and the panel it hangs over no longer has larger text than the box
-- describing it.
--
-- One pixel now separates the title from the body, which on its own would not
-- be a title. It does not carry that on its own: the title is the heading gold
-- against C.text below it, and it has a hairline under it that no other line
-- gets.
--
-- **And both of them move together.** How big a tooltip reads is a preference
-- the same way the zoom under it is one, and for the same reason: a box you read in
-- the half second before you move on is a box whose text you should not be
-- leaning in for. So the body is a number the player sets and the title is that
-- number plus the one pixel that separates them, which keeps the pair a pair at
-- every size. The zoom is not the answer to this question. It scales the whole
-- box, air and all, and a tooltip that grew its padding to buy a readable
-- sentence would cover twice as much of the fight.
local TITLE_LEAD = M.heading - M.font

-- The floor and the ceiling on that number, and the two sizes as they stand.
--
-- Eight is where the face stops resolving its own counters and eighteen is
-- where a five line box is a quarter of the screen. Neither end is a size
-- anybody should want; they are there so a saved variable edited by hand cannot
-- draw a tooltip nobody can read or one nobody can see past.
local FONT_LOW, FONT_HIGH = 8, 18
local BODY = M.font
local TITLE = M.heading

local Tooltip = {}
UI.Tooltip = Tooltip

-- The cursor, handed to Show in place of an owner.
--
-- Everything else this box opens on is a frame: a feed row, a nag square, an
-- action slot, a filter chip. A creature in the 3D world is not one. There is
-- no OnEnter, nothing to hang an anchor off and nothing to take a zoom from, so
-- the box follows the pointer the way the client's own tooltip does.
--
-- A table rather than a string because an owner is compared with == and asked
-- for its anchor, and a table nobody else holds cannot collide with a frame or
-- be produced by accident at a call site that meant something else.
Tooltip.CURSOR = {}

-- One box, as a value.
--
-- **The frame and everything measured on it used to be file locals**, because
-- there was one box and a second one was not a thing that could happen. Gear
-- comparison is that thing: shift held over an item puts what you are wearing
-- beside what you are pointing at, and a ring is two boxes rather than one.
--
-- So a box is a table now and every function below takes one. Nothing else
-- changed and that is the point of doing it this way: the box beside the box is
-- drawn by the same code, in the same chrome, off the same data shape, and
-- there is no second implementation to keep in step with the first.
--
--   frame, shadow, rule   the widgets
--   rows                  the pooled lines, never freed
--   count, widest, titled what the last open put in it
--   zoom                  the size that open drew at, per box because a box
--                         made after the slider moved has not been through
--                         Match yet
local function NewBox()
	return { rows = {}, count = 0, widest = 0, titled = false, zoom = 1 }
end

-- The box under the cursor, and the ones alongside it.
--
-- `besides` is a pool and `beside` is how many of it are up. Two is the most
-- the game can ask for, a ring or a trinket against the pair you are wearing,
-- and the pool is never trimmed for the reason the row pool is not: a frame
-- that has been built once costs nothing to leave hidden.
local main
local besides = {}
local beside = 0
local opened
local raised = false
-- The placement the open box asked for, or nil for one that took the setting.
-- Held for the same reason `raised` is: the setting can change while a box is
-- up, and re-anchoring it has to put it back where the hover wanted it rather
-- than where the slider now points.
local wanted
-- Which way the last open grew, so a re-anchor from the settings window puts
-- the compare boxes back on the side the main box left them room on.
local away = true

-- Where the box opens, which is one of three answers. Held here rather than
-- read out of ns.db for the reason UI.Size is: this layer is not allowed to
-- know the name of a setting, so Settings/Settings.lua reads the saved value
-- and pushes it in.
--
--   dock     the corner the client keeps its own tooltip in
--   beside   next to whatever you hovered, and on the cursor out in the world
--   anchor   a corner of the screen you put there yourself
--
-- Docked to start with, because that is where fifteen years of playing this
-- game has put the box and because a tooltip that opens under the cursor is a
-- tooltip covering the row you were about to click.
--
-- **The third is the one the other two cannot do.** The corner is read off the
-- client and moves when the bags do, which is right and is also the whole of
-- what is wrong with it: on an ultrawide monitor it is a foot away from the
-- fight, and there is no argument that gets it nearer. Beside puts the box
-- where you are looking and covers what is under it. The anchor is the answer
-- to both, and it costs a marker you drag once with the frames unlocked.
Tooltip.DOCK = "dock"
Tooltip.BESIDE = "beside"
Tooltip.ANCHOR = "anchor"

local PLACES = { dock = true, beside = true, anchor = true }
local place = Tooltip.DOCK

-- **And a hover may name its own, which the setting does not overrule.**
--
-- The three words above answer one question: where does a box go when there is
-- nothing on the screen to put it next to. A creature out in the world is not a
-- frame, a row of text in a feed is one but is the width of the window, and for
-- both of those the corner is right and is what the setting is for.
--
-- It is the wrong answer for a box about an object you are pointing at. An item
-- in a bag, a pin on the map, a button on the minimap, a worn piece on the
-- character panel: the box there is that object's own label, and a label that
-- opens a foot away in the corner of the screen is a label for nothing. You
-- read it, look back, and have to find the square again to be sure it was the
-- one you were on.
--
-- So an owner that *is* the thing being described says so at the call site and
-- stops caring what the slider says. That is a placement per hover rather than a
-- second setting, because it is not a preference: nobody wants their bag
-- tooltips in the corner, and a player who moves the box for the world hover has
-- not asked for the squares to move with it.

-- The frame the anchor mode hangs off, handed over by whoever owns the setting
-- that says where it is. Nil until then, and the anchor mode falls back to the
-- corner while it is: a placement with nothing to place against is worse than
-- the default, not better.
local marker

-- How long the box stays up after the thing it describes stops being hovered,
-- and how much of that is left.
--
-- **A tooltip that vanishes on the frame you leave the row is a tooltip you
-- cannot read.** Every hoverable thing in this addon is small and most of them
-- are in a column, so the pointer crosses two of them on the way to the one you
-- meant, and a box that opens and closes twice on the way is noise. Worse, the
-- box itself is not hoverable: a sentence that names a number you wanted to
-- read twice is gone the moment you move to look at something beside it.
--
-- So leaving a thing starts a countdown rather than closing the box, and the
-- countdown is the player's number. Hovering anything else cancels it outright
-- and draws the new box on the spot, because the one thing a linger must never
-- do is make the next hover wait for the last one.
--
-- **And the number ships at nought.** The countdown was the default for a
-- while and the argument above is the argument for it. The argument against it
-- is what the client's own tooltip has always done, and it won: a box that
-- outlives the hover by a second is a box over the row under the pointer on
-- every pass down a column, and a player who has stopped reading it sees it as
-- a thing in the way rather than a thing that waited. The linger is a setting
-- for whoever reads slowly; the shipped behaviour is the client's.
local LINGER_LOW, LINGER_HIGH = 0, 10
local ttl = 0
local linger = 0

-- What the countdown runs on. Hidden is the ordinary state and means nothing is
-- counting: this frame is shown for at most a second at a time, once per hover
-- you leave, and never while a box is up under the pointer.
local ticker = CreateFrame("Frame")
ticker:Hide()

-- The countdown, cancelled. Every open calls it, which is the whole of "hover a
-- second thing and the box is replaced at once": a new box is not a box waiting
-- on the last one's clock.
local function Stop()
	if linger <= 0 then
		return false
	end
	linger = 0
	ticker:Hide()
	return true
end

--------------------------------------------------------------------------
-- The lines
--
-- A row is two font strings, one anchored left and one anchored right, and a
-- line that is not a pair simply leaves the right one empty. Pooled and never
-- freed: a tooltip that has once drawn twenty lines can draw twenty again for
-- nothing, and twenty font strings is what one hover of an epic costs.
--------------------------------------------------------------------------

local function Row(box, index)
	local row = box.rows[index]
	if row then
		return row
	end

	-- Neither string is anchored here. Where a line sits is decided in Layout,
	-- and it is cleared and set again on every open rather than written over,
	-- because a line's height is a whole number of physical pixels and a
	-- physical pixel is a different number of units at every zoom. A tooltip
	-- that has been opened at 2x and then at 1x would otherwise be carrying an
	-- anchor from each.
	row = {}
	row.left = UI.Label(box.frame, BODY, C.text, "LEFT", UI.FLAT)
	UI.Wrap(row.left, true)
	row.right = UI.Label(box.frame, BODY, C.text, "RIGHT", UI.FLAT)

	box.rows[index] = row
	return row
end

-- Everything a line needs, as loose values rather than a table. Colours arrive
-- as three numbers because half of them come out of the scanner that way, and
-- a table built per line to carry them would be garbage on a path that already
-- builds a formatted string or two.
local function Add(box, size, left, lr, lg, lb, right, rr, rg, rb)
	box.count = box.count + 1
	local row = Row(box, box.count)

	local font = UI.Font(size, UI.FLAT)
	row.left:SetFontObject(font)
	row.left:SetText(left or "")
	row.left:SetTextColor(lr, lg, lb)
	row.left:SetWidth(0)
	row.left:Show()

	if right then
		row.right:SetFontObject(font)
		row.right:SetText(right)
		row.right:SetTextColor(rr, rg, rb)
		row.right:Show()
	else
		row.right:SetText("")
		row.right:Hide()
	end

	row.size = size
	row.paired = right ~= nil
	row.spacer = false
	-- What the line wants if nothing stops it. Measured before any width is
	-- written, because a font string that has been given a width answers that
	-- width rather than its own.
	row.natural = row.left:GetStringWidth() or 0
	if right then
		row.natural = row.natural + COLUMN + (row.right:GetStringWidth() or 0)
	end
	if row.natural > box.widest then
		box.widest = row.natural
	end
	return row
end

-- Air between two groups of lines, rather than an empty line of text.
--
-- It used to be a blank string at the small size, which cost thirteen units of
-- height to say nothing and made the gap between two groups taller than either
-- group's own line spacing. A spacer carries no text and no width, so it
-- widens nothing and reads as the pause it is.
local function Spacer(box)
	box.count = box.count + 1
	local row = Row(box, box.count)
	row.left:SetText("")
	row.left:SetWidth(0)
	row.left:Hide()
	row.right:SetText("")
	row.right:Hide()
	row.size, row.paired, row.natural, row.spacer = BODY, false, 0, true
	return row
end

-- The client's own text, redrawn in this chrome.
--
-- The lines arrive from UI/Scan.lua already read off the client, in the shape
-- Add takes. Every line keeps the colour the client gave it, because on an item
-- that colour is information: the name is the quality, the red line is the
-- requirement you do not meet, and the green is the enchant.
--
-- False where there is nothing to draw, so the caller's own title stands
-- instead of a box with nothing in it.
local function ScanText(box, lines)
	if type(lines) ~= "table" or #lines < 1 then
		return false
	end
	for index = 1, #lines do
		local line = lines[index]
		Add(box, index == 1 and TITLE or BODY,
			line[1] or "", line[2] or C.text[1], line[3] or C.text[2], line[4] or C.text[3],
			line[5], line[6], line[7], line[8])
		if index == 1 then
			box.titled = true
		end
	end
	return true
end

--------------------------------------------------------------------------
-- What a caller hands over
--
-- One table describing the whole tooltip. The head of it is the heading:
--
--   title  the first line, in the heading size, with a hairline under it
--   color  what colour that line is, C.heading where absent
--   scan   the client's own lines, from UI/Scan.lua. Drawn instead of the
--          title where there are any, and the title stands where there are
--          none.
--
-- The array part is the body, in order, one table per line:
--
--   { "a sentence" }                 a plain line
--   { "a sentence", color = C.dim }  the same, in a colour of its own
--   { "Label", "value" }             the two pushed to opposite edges
--   { "Label", "value", tone = X }   the same, with the value in its own colour
--   { blank = true }                 air between two groups
--
-- Data rather than a run of calls because a tooltip is a description of one
-- thing and a description is a value. A caller that built one imperatively had
-- to know that Title comes first, that Blank is a line, and that writing
-- nothing means drawing nothing; all three of those are this file's business
-- and none of them was enforceable. It costs one table and one per line on a
-- hover, which is a moment and can afford it, and the path that reopens a
-- tooltip without a hover is guarded in UI/Feed.lua for exactly this reason.
--
-- Almost nothing writes this table by hand any more. UI/Tip.lua builds it from
-- a subject, so the order of the bands and the air between them is decided
-- once rather than per caller. Show stays public for the one case that has no
-- subject, which is the harness proving what this file draws.
--------------------------------------------------------------------------

-- One line of the body, as the caller described it.
--
-- There used to be a third kind here, a blue line naming the switch that turns
-- the thing off or the word that prints the rest. It is gone, and the reason is
-- worth keeping: it was drawn on every box in the addon, it said the same six
-- things, and a footnote you have read four hundred times is not a footnote any
-- more. A tooltip says what the thing under the cursor is. Where the settings
-- are is what the settings window is for.
local function Line(box, spec)
	if spec.blank then
		return Spacer(box)
	end

	local color = spec.color or (spec[2] and C.dim) or C.text
	if spec[2] == nil then
		return Add(box, BODY, spec[1] or "", color[1], color[2], color[3])
	end

	local tone = spec.tone or C.text
	return Add(box, BODY, spec[1] or "", color[1], color[2], color[3],
		spec[2], tone[1], tone[2], tone[3])
end

local function Render(box, data)
	if not ScanText(box, data.scan) and data.title then
		local color = data.color or C.heading
		box.titled = true
		Add(box, TITLE, data.title, color[1], color[2], color[3])
	end

	for index = 1, #data do
		Line(box, data[index])
	end
end

--------------------------------------------------------------------------
-- Putting it on screen
--------------------------------------------------------------------------

-- What the player asked a hover box to be drawn at, on top of the screen's own
-- step. Pushed in by Settings/Settings.lua rather than read out of
-- ns.db for the reason UI.Size is, and the same as the place, the linger and
-- the font above it: this layer is not allowed to know the name of a setting.
-- Tooltip.SetZoom is below, beside the walk that takes the boxes already built
-- to a new size. Named chosen rather than scale, the same as UI/Window.lua's,
-- because a frame's effective scale is a different number this file also asks
-- for and one of them shadowing the other is how they get confused.
local chosen = 1

-- The number the player chose, not a box's effective zoom: Tooltip.Zoom below
-- answers that and answers it per box. Named apart because the two differ by
-- the screen's own step and a reader who conflated them would be off by 2x on
-- a 4K panel.
function Tooltip.Scale()
	return chosen
end

-- The current zoom, asked for rather than remembered, because a box built after
-- the setting moved has to arrive at the size the boxes beside it are already
-- drawn at.
local function Wanted()
	return ((UI.ScreenZoom and UI.ScreenZoom()) or 1) * chosen
end

-- One box built. `name` is nil for every box but the first: a frame's own name
-- is only load bearing on the hidden scanner in UI/Scan.lua, whose lines are
-- reachable as globals built from it, and none of these is that. The main box
-- keeps a name anyway because other addons and a player typing /framestack look
-- for it.
local function Build(name)
	local box = NewBox()
	box.zoom = Wanted()

	local frame = CreateFrame("Frame", name, UIParent)
	-- Above everything the addon draws and above the world, which is what a
	-- tooltip is for. TOOLTIP is the client's own name for that layer and
	-- Blizzard's own sits on it, so this lands beside it rather than under it.
	frame:SetFrameStrata("TOOLTIP")
	frame:SetClampedToScreen(true)
	frame:Hide()
	box.frame = frame

	UI.Adopt(frame, box.zoom)

	-- Drawn before the background and one sublevel under it, so what shows is
	-- the two units of it that stick out past the bottom and the right. A
	-- tooltip floats over whatever it was opened on top of and needs to look
	-- like it does; every other surface in the addon sits in a window and does
	-- not.
	box.shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	box.shadow:SetColorTexture(C.shadow[1], C.shadow[2], C.shadow[3], C.shadow[4])
	box.shadow:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
	box.shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)

	frame.bg = ns.Fill(frame, "BACKGROUND", C.window[1], C.window[2], C.window[3], 1)
	frame.bg:SetAllPoints()
	frame.edges = ns.Outline(frame, C.edge[1], C.edge[2], C.edge[3], C.edge[4])
	ns.EdgeSize(frame.edges, ns.Pixel(frame))

	box.rule = UI.Rule(frame, C.hairline)
	box.rule:Hide()
	return box
end

-- The hairlines, which are the one part of this box measured in physical pixels
-- rather than in units. One physical pixel is 1/zoom units, so both of them
-- have to be rewritten whenever the zoom moves under the frame.
local function Hairlines(box)
	ns.EdgeSize(box.frame.edges, ns.Pixel(box.frame))
	box.rule:SetHeight(ns.Pixel(box.frame))
end

-- Every box that has been built, whether or not it is up. Walked by the two
-- things that are the frame's business rather than the open's: the rescale and
-- the close.
local function Each(fn)
	if not main then
		return
	end
	fn(main)
	for index = 1, #besides do
		fn(besides[index])
	end
end

-- Named rather than written as a closure at the two call sites, because one of
-- them is Tooltip.Sweep and a ticker may not allocate. See the gate in
-- scripts/check.sh.
local function Hide(box)
	box.frame:Hide()
end

-- Take the addon's own size, which is what every window is drawn at and now
-- what every tooltip is drawn at. Guarded, because the answer only moves when
-- the player moves the slider and a rezoom is a SetScale on a frame the client
-- has already laid out.
--
-- Nothing about the owner reaches it any more, which is the whole change: the
-- argument is gone rather than accepted and ignored, so a reader cannot come
-- away thinking the box still measures the thing it is describing.
local function Match(box)
	local want = Wanted()
	if want == box.zoom then
		return false
	end
	box.zoom = want
	UI.Rezoom(box.frame, want)
	Hairlines(box)
	return true
end

-- Answered as whether anything moved, which is the shape every setter in this
-- file has. Every box already built is taken to the new size on the spot,
-- because a hover is the one control in the addon you are looking at while you
-- change it: the row on the zoom page has a hover of its own.
function Tooltip.SetZoom(value)
	value = tonumber(value) or 1
	if value == chosen then
		return false
	end
	chosen = value
	Each(Match)
	return true
end

-- Where the pointer is, in physical pixels, measured from the bottom left of
-- the screen. That is the client's own answer and it is left alone here,
-- because it is the one number in this file that belongs to the screen rather
-- than to a frame.
--
-- Nil where this client has no such call, which is the honest answer and not a
-- guess at the middle of the screen.
local function CursorPixels()
	if type(GetCursorPosition) ~= "function" then
		return nil, nil
	end
	local x, y = GetCursorPosition()
	if not x or not y then
		return nil, nil
	end
	return x, y
end

-- The box beside the pointer rather than beside a frame.
--
-- Two conversions and both are easy to miss. An anchor offset is in the
-- anchored frame's own units, and this box is drawn on the addon's pixel grid
-- at a scale of its own, so the pointer's pixels are divided by that frame's
-- effective scale and not by UIParent's. The side is decided in pixels, where
-- the pointer already is, so the screen's middle is converted the other way
-- rather than the reading being converted twice.
--
-- POINTER is the distance from the hotspot, which is the arrow's top left
-- corner: the art hangs down and to the right of it, so a box pinned to the
-- hotspot opens under the pointer that opened it. The side is picked the way it
-- is picked for a frame, so a mob on the right of the screen throws its box
-- left rather than into the clamp.
--
-- False where the client will not say where the pointer is. The caller then
-- puts the box in the middle of the screen rather than drawing nothing, because
-- a box in the wrong place still says what the mob is.
local function AtCursor(box)
	local x, y = CursorPixels()
	local scale = box.frame:GetEffectiveScale()
	if not x or not scale or scale == 0 then
		return nil
	end

	local centre = UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2
	local ox, oy = x / scale, y / scale
	local far = x > centre

	box.frame:ClearAllPoints()
	if far then
		box.frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", ox - POINTER, oy - POINTER)
	else
		box.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ox + POINTER, oy - POINTER)
	end
	return far
end

-- A distance the client measured, in the units this frame's anchors are read
-- in, and on the grid.
--
-- Two conversions and both are easy to miss. The client's clearances are in
-- UIParent's units and an anchor offset is read in the anchored frame's own,
-- and this box sits on the addon's pixel grid at a scale of its own, so a dock
-- written without UI.Convert lands half way up the screen at double zoom and
-- inside the bags at half. What comes out of that is a fraction of a unit,
-- because the client's numbers were never on this grid, and an offset that is
-- not a whole number of pixels puts the box's own hairline border half on a
-- pixel and half off. UI.Round is the second conversion, and it costs at most
-- half a pixel of a clearance that is measured in tens.
local function Units(box, value)
	return UI.Round(box.frame, UI.Convert(value, UIParent, box.frame))
end

-- The corner, which is the one anchor that does not care what was hovered.
--
-- Same corner for a feed row, a filter chip and a creature out in the world:
-- the box is a place on the screen you look at rather than a label on the thing
-- under the cursor. That is the whole of what docking buys, and it is why the
-- owner is not an argument here.
local function Dock(box)
	local x = (tonumber(CONTAINER_OFFSET_X) or DOCK_X) + DOCK
	local y = tonumber(CONTAINER_OFFSET_Y) or DOCK_Y
	box.frame:ClearAllPoints()
	box.frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT",
		-Units(box, x), Units(box, y))
end

-- The corner you put there yourself.
--
-- The marker is a point rather than a box, so what it decides is which corner
-- of the tooltip lands on it and which way the box grows from there. That is
-- read off where the marker is: a marker in the bottom left of the screen grows
-- the box up and to the right, one in the top right grows it down and to the
-- left, and either way the box goes away from the nearest edge rather than into
-- it. A single fixed corner would have been a marker you cannot use in three
-- quarters of the screen.
--
-- Which quarter is decided against the middle of UIParent as UIParent itself
-- reports it, rather than against half its width and half its height. The two
-- are the same number only where the screen's own origin is its bottom left
-- corner, which is a fact about the client rather than a fact about anchors,
-- and reading both ends of the screen is the same work either way.
--
-- The marker's edges are in the marker's own units and UIParent's are in
-- UIParent's, so the middle is converted before the comparison. This is the
-- same trap Dock is written around: this box and everything the addon puts on
-- the grid sit at a scale of their own, and a comparison that skipped the
-- conversion would pick the right corner at one UI scale and the wrong one at
-- the next. The anchor itself needs no conversion at all, because SetPoint
-- reads an offset of zero the same way at every scale.
local function Middle(box)
	local left = ns.Measure(UIParent, "GetLeft")
	local right = ns.Measure(UIParent, "GetRight")
	local top = ns.Measure(UIParent, "GetTop")
	local bottom = ns.Measure(UIParent, "GetBottom")
	if not left or not right or not top or not bottom then
		return nil, nil
	end
	return UI.Convert((left + right) / 2, UIParent, box.frame),
		UI.Convert((top + bottom) / 2, UIParent, box.frame)
end

local function Marked(box)
	local left = ns.Measure(marker, "GetLeft")
	local right = ns.Measure(marker, "GetRight")
	local top = ns.Measure(marker, "GetTop")
	local bottom = ns.Measure(marker, "GetBottom")
	local midX, midY = Middle(box)
	if not left or not right or not top or not bottom or not midX then
		return nil
	end

	local far = UI.Convert((left + right) / 2, marker, box.frame) > midX
	local high = UI.Convert((top + bottom) / 2, marker, box.frame) > midY
	local corner = (high and "TOP" or "BOTTOM") .. (far and "RIGHT" or "LEFT")

	box.frame:ClearAllPoints()
	box.frame:SetPoint(corner, marker, corner, 0, 0)
	return far
end

-- Which side of the owner it opens on, and which corner of itself it hangs
-- from. Right of the owner normally, and left of it once the owner is past the
-- middle of the screen, because a tooltip clamped to the screen edge is one
-- that covers the thing you are hovering.
--
-- **And above it where the caller asks.** Beside is right for anything the
-- width of a row: the cursor is somewhere in the middle of a wide thing and the
-- box opens clear of it. It is wrong for anything small. The cursor's hotspot
-- is the pointer's top left corner and the arrow hangs down and to the right
-- from there, so a box pinned to the top right of a sixteen pixel square opens
-- underneath the arrow that opened it and you read it round the pointer. That
-- is the loot feed's filter chips, and it was the first thing anybody said
-- about them.
--
-- Above still picks a side, and picks it the same way, so a chip on a feed the
-- player has dragged to the right of the screen throws its box left rather than
-- off the edge.
--
-- **And on the pointer itself where there is no owner at all.** That is
-- Tooltip.CURSOR, and it is the world hover: a creature is not a frame, so
-- there is nothing to sit beside and the box follows the arrow instead.
--
-- **None of which happens in the other two placements.** Every side, every
-- corner and every clearance below is the answer to one question, which is how
-- to put a box next to a thing without covering it, and both the corner and the
-- marker answer that question by not being next to the thing at all.
--
-- **And where the call site named a placement, that one rather than the
-- setting.** See the override above. A word this file does not know falls
-- through to the setting, for the reason SetPlace takes one: the caller is
-- allowed to be wrong without costing the player a tooltip.
-- **And it answers which way the box grew**, which is a side rather than a
-- placement: true where the box ended up on the right of the screen and threw
-- itself left, false where it went the other way. That is the one thing a box
-- alongside this one has to know, and every branch below has already worked it
-- out for its own reasons. Answering it is cheaper and steadier than measuring
-- the frame afterwards, which on the open that built it has not been laid out
-- yet and reads nil.
local function Anchor(box, owner, above, where)
	where = PLACES[where] and where or place

	if where == Tooltip.ANCHOR and marker then
		local far = Marked(box)
		if far ~= nil then
			return far
		end
	end

	if where ~= Tooltip.BESIDE then
		Dock(box)
		-- The corner the client keeps its tooltip in is the bottom right one,
		-- so there is no room on that side and never a reading to take.
		return true
	end

	if owner == Tooltip.CURSOR then
		local far = AtCursor(box)
		if far == nil then
			box.frame:ClearAllPoints()
			box.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
			return true
		end
		return far
	end

	local centre = UIParent:GetWidth() / 2
	local left = ns.Measure(owner, "GetLeft")
	local right = ns.Measure(owner, "GetRight")
	local far = (left and right and (left + right) / 2 > centre) and true or false

	box.frame:ClearAllPoints()
	if above then
		if far then
			box.frame:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, OFFSET)
		else
			box.frame:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, OFFSET)
		end
	elseif far then
		box.frame:SetPoint("TOPRIGHT", owner, "TOPLEFT", -OFFSET, 0)
	else
		box.frame:SetPoint("TOPLEFT", owner, "TOPRIGHT", OFFSET, 0)
	end
	return far
end

-- One compare box hung off the one before it, on the side the main box left
-- room on.
--
-- The tops are flush rather than the bottoms. Two item tooltips are rarely the
-- same height, and what you are reading across is the first few lines of each:
-- the name, the type, the armour. Aligning the bottoms would put those lines at
-- different heights and make the pair harder to read than either alone.
local function Alongside(box, previous, far)
	box.frame:ClearAllPoints()
	if far then
		box.frame:SetPoint("TOPRIGHT", previous.frame, "TOPLEFT", -OFFSET, 0)
	else
		box.frame:SetPoint("TOPLEFT", previous.frame, "TOPRIGHT", OFFSET, 0)
	end
end

-- Two passes over the lines, because the width of the box and the height of a
-- wrapped line each depend on the other. The first pass has already run: every
-- Add recorded what its line wants and kept the widest. This decides the box
-- from that, then gives every line the width it now has and asks how tall it
-- came out.
local function Layout(box)
	local frame = box.frame
	local content = box.widest
	if content > MAX then
		content = MAX
	end
	content = UI.Round(frame, content)

	local y = PAD
	for index = 1, box.count do
		local row = box.rows[index]
		local height
		if row.spacer then
			height = SPACER
		else
			-- A paired line never wraps. Its right hand side is a number or a
			-- word and its left is a label, and a label that folded onto a
			-- second line would put the value beside the wrong half of it.
			if row.paired then
				row.left:SetWidth(math.max(content - COLUMN - (row.right:GetStringWidth() or 0), 1))
			else
				row.left:SetWidth(content)
			end
			height = UI.Round(frame, UI.TextHeight(row.left, row.size + 2))
			row.left:ClearAllPoints()
			row.left:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
			if row.paired then
				row.right:ClearAllPoints()
				row.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
			end
		end

		y = y + height
		if index == 1 and box.titled and box.count > 1 then
			box.rule:ClearAllPoints()
			box.rule:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + RULE))
			box.rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(y + RULE))
			box.rule:Show()
			y = y + RULE * 2 + ns.Pixel(frame)
		elseif index < box.count and not row.spacer then
			y = y + GAP
		end
	end

	frame:SetSize(content + PAD * 2, y + PAD)
end

-- Everything from the last hover, put away. The rows keep their font strings,
-- because one with nothing in it costs nothing to leave lying about and one
-- that has to be rebuilt costs a frame. They do not keep their anchors: a row
-- the next tooltip does not use would otherwise sit hidden at a position from a
-- box that is gone, at whatever zoom that box was drawn at.
local function Reset(box)
	for index = 1, box.count do
		box.rows[index].left:Hide()
		box.rows[index].left:ClearAllPoints()
		box.rows[index].right:Hide()
		box.rows[index].right:ClearAllPoints()
	end
	box.count, box.widest, box.titled = 0, 0, false
	box.rule:Hide()
end

-- One box filled from one description, measured and sized, and whether anything
-- went in it.
--
-- Nothing is anchored here and nothing is shown. Where a box goes depends on
-- how tall it came out and on where the box before it landed, so the placement
-- is the caller's second pass rather than this one's last line.
local function Draw(box, data)
	Reset(box)
	if type(data) ~= "table" then
		return false
	end
	Match(box)
	Render(box, data)
	if box.count == 0 then
		return false
	end
	Layout(box)
	return true
end

-- The box that is up, put back where it belongs.
--
-- Called when the setting that decides where boxes go moves under one, which
-- happens more often than it sounds: the control is in the settings window and
-- has a hover of its own, so the box demonstrating the setting is usually the
-- one on screen while you change it.
--
-- The compare boxes move with it and have to. They hang off the main box's
-- side, and which side that is comes out of the same reading the main box's own
-- anchor does, so a box re-anchored from the corner to a marker on the left of
-- the screen would otherwise leave its comparisons stacked off the wrong edge.
local function Reanchor()
	if not main or not main.frame:IsShown() or not opened then
		return false
	end
	away = Anchor(main, opened, raised, wanted)
	local previous = main
	for index = 1, beside do
		Alongside(besides[index], previous, away)
		previous = besides[index]
	end
	return true
end

-- Open on an owner, from a table describing what to say.
--
-- Nothing is drawn for data that is nil or has nothing in it. That is the
-- honest answer to a row whose entry has gone and to a nag square with nothing
-- to nag about: an empty box the size of its own padding is worse than no box,
-- and without the refusal the last hover's sentence stays on screen pointing at
-- this one.
-- `above` opens the box over the owner rather than beside it, which is what
-- anything smaller than the cursor has to ask for. See Anchor.
--
-- `where` is one of the three placement words, for a hover that knows where its
-- box belongs better than the setting does. That is every hover over an icon
-- standing for an object. See the override beside PLACES.
--
-- `alongside` is an array of further descriptions, each drawn as its own box off
-- the side of this one. That is the gear comparison and it is the only caller:
-- what you have on, beside what you are pointing at. A list rather than one
-- because a ring is two rings and a trinket is two trinkets.
--
-- Nothing about it is decided here. Which hovers get one, what goes in one and
-- how many there are is UI/Tip.lua's business the same way the lines are; all
-- this file knows is that some boxes have boxes beside them, and that they are
-- drawn by the same code as the box they sit next to.
--
-- A description in that list that comes out empty is skipped rather than drawn
-- as a blank, which is what an empty worn slot is: nothing to compare against,
-- and a box the size of its own padding would say so worse than no box does.
function Tooltip.Show(owner, data, above, where, alongside)
	if not main then
		main = Build(FRAME_NAME)
	end
	-- Before anything is drawn and before the refusals below, so a hover that
	-- describes nothing takes the lingering box down with it rather than
	-- leaving the last one on screen for another second pointing at this one.
	Stop()

	for index = 1, beside do
		Reset(besides[index])
		besides[index].frame:Hide()
	end
	beside = 0

	if not Draw(main, data) then
		main.frame:Hide()
		return false
	end

	-- After Layout, and it has to be. Above hangs the box's bottom edge off the
	-- owner's top, so where its top lands is its own height, and its height is
	-- not known until the lines have been measured and wrapped.
	away = Anchor(main, owner, above, where)
	opened, raised, wanted = owner, above, where
	main.frame:Show()

	if type(alongside) == "table" then
		local previous = main
		for index = 1, #alongside do
			local box = besides[beside + 1]
			if not box then
				box = Build(nil)
				besides[beside + 1] = box
			end
			if Draw(box, alongside[index]) then
				beside = beside + 1
				Alongside(box, previous, away)
				box.frame:Show()
				previous = box
			end
		end
	end
	return true
end

-- Where the box opens, as one of the three words above.
--
-- Pushed in by Settings/Settings.lua rather than read, and answered as whether
-- anything moved, which is the shape UI.SetSize has. A box that is up when the
-- setting changes is re-anchored on the spot: the control is in the settings
-- window and has a hover of its own, so the box that demonstrates the setting
-- is usually the one on screen while you change it.
--
-- A word this file does not know is the corner, rather than an error. The value
-- comes out of an account file a player may have edited, and a tooltip in the
-- wrong place is a better answer to that than no tooltip at all.
function Tooltip.SetPlace(word)
	if not PLACES[word] then
		word = Tooltip.DOCK
	end
	if word == place then
		return false
	end
	place = word
	Reanchor()
	return true
end

function Tooltip.Place()
	return place
end

-- Where the box that is up actually went, which is the hover's own answer where
-- it had one and the setting's otherwise. Handed out for the reason Frame and
-- Owner are: "the bag square's box ignored the corner" is a claim about a box
-- that is on screen, and there is no answering it from the outside.
function Tooltip.Placed()
	return PLACES[wanted] and wanted or place
end

-- The frame the anchor mode hangs the box off.
--
-- Handed over rather than made here, because where it sits is a saved setting
-- and this layer may not name one. What this file does with it is read its
-- corners; who drags it, who draws a rim on it and who writes down where it was
-- let go is the caller's business entirely.
function Tooltip.SetAnchor(frame_)
	marker = frame_
	Reanchor()
	return marker ~= nil
end

function Tooltip.Anchored()
	return marker
end

-- How long a box stays up after the pointer leaves what it describes.
--
-- Clamped rather than refused, for the reason SetPlace takes a word it does not
-- know: the number arrives from an account file. Zero is a real answer and
-- means the box goes the instant you look away, which is what the client's own
-- tooltip does and is what somebody who finds the linger annoying will set.
function Tooltip.SetLinger(seconds)
	seconds = tonumber(seconds) or 0
	if seconds < LINGER_LOW then
		seconds = LINGER_LOW
	elseif seconds > LINGER_HIGH then
		seconds = LINGER_HIGH
	end
	if seconds == ttl then
		return false
	end
	ttl = seconds
	-- A countdown already running keeps the number it started with. Shortening
	-- the linger from the panel while the panel's own hover is on screen would
	-- otherwise take that box down under the cursor that is still over it.
	return true
end

function Tooltip.Linger()
	return ttl
end

-- How big the box reads.
--
-- One number, and the title takes the same number plus the pixel that separates
-- the two. Clamped rather than refused for the reason the linger is, and
-- rounded to a whole pixel because SetFont refuses a fraction outright: the
-- symptom of that is a font object that comes back nil and a box with no text
-- in it at all, which is a defect this addon has already shipped once.
--
-- Nothing is redrawn here. Every line takes its size in Add, the box is built
-- from nothing on every open, and the next hover is the next open. A box on
-- screen while the slider moves keeps the size it was drawn at until you hover
-- something else, which is the same deal the zoom slider offers and for the
-- same reason.
function Tooltip.SetFont(size)
	size = math.floor((tonumber(size) or M.font) + 0.5)
	if size < FONT_LOW then
		size = FONT_LOW
	elseif size > FONT_HIGH then
		size = FONT_HIGH
	end
	if size == BODY then
		return false
	end
	BODY, TITLE = size, size + TITLE_LEAD
	return true
end

function Tooltip.Font()
	return BODY
end

-- The two ends of that range, so the panel and the slash word draw the same
-- slider without either of them writing the numbers down a second time.
function Tooltip.FontRange()
	return FONT_LOW, FONT_HIGH
end

-- And the two ends of the linger, for the same reason.
function Tooltip.LingerRange()
	return LINGER_LOW, LINGER_HIGH
end

-- What is left of the current countdown, for scripts/harness.lua. Zero when
-- nothing is counting, which is both "up and staying up" and "already gone":
-- the two are told apart by IsShown, and there is no third state to report.
function Tooltip.Lingering()
	return linger
end

-- The pointer left the thing the box describes.
--
-- The box does not go with it. It stays for as long as the linger says, and the
-- owner is dropped at once because the thing it was describing is no longer
-- under the cursor and nothing may re-anchor to it.
--
-- `now` takes the box down on the spot. That is for the caller who knows the
-- box is describing something that no longer exists at all rather than
-- something you looked away from: a loading screen, a feature switched off. A
-- linger there is a sentence about a mob in a zone you have left.
function Tooltip.Close(now)
	opened, wanted = nil, nil
	if not main then
		return true
	end
	if now or ttl <= 0 or not main.frame:IsShown() then
		Stop()
		Each(Hide)
		return true
	end
	linger = ttl
	ticker:Show()
	return true
end

-- The countdown, run down. One question and one write, which is why the ticker
-- is hidden whenever nothing is counting: an OnUpdate that answers "no" sixty
-- times a second for a whole evening is the shape of every addon that costs a
-- frame and cannot say where it went.
function Tooltip.Sweep(elapsed)
	if linger <= 0 then
		return false
	end
	linger = linger - (tonumber(elapsed) or 0)
	if linger > 0 then
		return false
	end
	linger = 0
	ticker:Hide()
	Each(Hide)
	return true
end

UI.Ticker(ticker, 0, "tip", Tooltip.Sweep)

-- What it is currently open on. Handed out because "the tooltip came up beside
-- the thing you hovered" is a claim scripts/harness.lua has to be able to make,
-- and reading it back off the anchor would be asserting the client's own
-- bookkeeping rather than this file's.
-- The box itself, so scripts/harness.lua can measure where it opened. Handed
-- out for the reason Owner is: "the tooltip sits above the chip rather than
-- beside it" is a claim about two rectangles, and there is no answering it from
-- the outside without one of them.
-- **Every reader below takes an optional box.** One is the box under the
-- cursor and two upwards are the ones beside it, in the order they were drawn,
-- which is the order the caller listed them in. Absent means one, so every call
-- written before there was a second box still asks about the box it meant.
--
-- A number past what is up answers nil rather than the main box, which is the
-- whole reason the argument is a number and not a boolean: a section asserting
-- that a hover put up no comparison has to be able to ask for the second box
-- and be told there isn't one.
local function Which(index)
	if index == nil or index == 1 then
		return main
	end
	if type(index) ~= "number" or index < 1 or index > beside + 1 then
		return nil
	end
	return besides[index - 1]
end

function Tooltip.Frame(which)
	local box = Which(which)
	return box and box.frame or nil
end

function Tooltip.Owner()
	return opened
end

function Tooltip.IsShown(which)
	local box = Which(which)
	return box ~= nil and box.frame:IsShown() and true or false
end

-- How many boxes are up beside the one under the cursor. Zero for every hover
-- in the addon that is not an item you could put on, and the number a gear
-- comparison actually drew for the ones that are: one for a helmet, two for a
-- ring, and none at all for a slot you have nothing in.
function Tooltip.Alongside()
	return beside
end

-- What zoom the last open drew at. Handed out for the same reason Owner is:
-- "the tooltip is the size of the thing it is describing" is the whole of the
-- fix above and it cannot be asserted from the outside any other way.
function Tooltip.Zoom(which)
	local box = Which(which)
	return box and box.zoom or nil
end

-- How many lines the last open drew, for scripts/harness.lua and for anything
-- else that has to prove a hover said something without this file handing out
-- its pool.
function Tooltip.Lines(which)
	local box = Which(which)
	return box and box.count or 0
end

-- One line of one box, as text. Same reason.
local function At(index, which)
	local box = Which(which)
	if not box then
		return nil, nil
	end
	local row = box.rows[index]
	if not row or index > box.count then
		return nil, nil
	end
	return row, box
end

function Tooltip.Text(index, which)
	local row = At(index, which)
	if not row then
		return nil
	end
	return row.left:GetText(), row.paired and row.right:GetText() or nil
end

-- What colour the value on one of those lines was drawn in.
--
-- Handed out for the reason the rest of these are. A price you cannot meet and
-- a token count you have not got are drawn in the loss colour, that colour is
-- the whole of what those two lines say beyond the number, and there is no
-- reading it from outside without this file handing out its pool.
function Tooltip.Tone(index, which)
	local row = At(index, which)
	if not row or not row.paired then
		return nil
	end
	return { row.right:GetTextColor() }
end

-- And what size it was drawn at. Handed out for the reason the rest of these
-- are: the tooltip's body has to be the addon's body size, that claim is the
-- whole of the fix for a box whose text was smaller than the panel under it,
-- and reading it off the font string from outside would mean this file handing
-- out its pool.
function Tooltip.Size(index, which)
	local row = At(index, which)
	if not row then
		return nil
	end
	local _, size = row.left:GetFont()
	return size
end

-- The grid moved under the frame: a resolution change, or combat letting go of
-- one. The screen's own step is half of what a box is drawn at, so the zoom is
-- taken again here rather than left for the next open, and Match rewrites the
-- hairlines for the boxes it moved. Hairlines runs on all of them regardless,
-- because on a client with no SetIgnoreParentScale a physical pixel is a
-- fraction of a unit that moves with the UI scale whether the zoom did or not.
UI.OnRescale(function()
	Each(Match)
	Each(Hairlines)
end)
