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
-- a one pixel edge and Arial Narrow on it that raises a parchment scroll when
-- you hover a row is a window with two designs in it.
--
-- So this is the addon's own. Same palette, same metrics, same font cache,
-- same pixel grid. Nothing in it is a template and nothing in it is an asset.
--
-- **One tooltip, not one per owner.** At most one is on screen at a time, so
-- there is one frame with a pool of lines in it, refilled on every open. A
-- tooltip per hoverable row would be a frame and a dozen font strings per row
-- in a feed that holds four hundred of them.
--
-- **It is the size of whatever it was opened on.** One frame serving forty
-- owners has to take its zoom from the owner rather than carry one of its own,
-- and the version of this file that carried one took it from UI.WindowZoom,
-- which is the settings window's. A player with the UI size slider above 1 got
-- a tooltip drawn at the settings window's scale beside a feed drawn at the
-- feed's: a box six hundred pixels across explaining a row thirty pixels tall.
-- UI.ZoomOf answers what the owner is actually drawn at, and UI.Rezoom moves
-- this frame to it on the way in. The cost is one comparison per hover, and it
-- is the only correct answer, because "how big is a tooltip" is a question only
-- the thing being described can answer.
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
-- alone decides the shape of the box: 210 is about forty characters of Arial
-- Narrow, which is a sentence you take in without tracking back to the left
-- edge and is narrower than every item name in the game bar a few.
local PAD = 6       -- the edge to the first glyph
local GAP = 2       -- one line to the next
local COLUMN = 16   -- the least air between a label and its value
local RULE = 3      -- the air either side of the hairline under a title
local SPACER = 4    -- a blank line, which is air rather than an empty line
local MAX = 210     -- the widest a line is drawn before it wraps
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
local TITLE = M.heading
local BODY = M.font

local Tooltip = {}
UI.Tooltip = Tooltip

-- The cursor, handed to Show in place of an owner.
--
-- Everything else this box opens on is a frame: a feed row, a nag square, an
-- action slot, a filter chip. A creature in the 3D world is not one. There is
-- no OnEnter, nothing to hang an anchor off and nothing to take a zoom from, so
-- the box follows the pointer the way the client's own tooltip does.
--
-- A table rather than a string because an owner is compared with == and handed
-- to UI.ZoomOf, and a table nobody else holds cannot collide with a frame or be
-- produced by accident at a call site that meant something else.
Tooltip.CURSOR = {}

local frame, shadow, rule
local opened
local raised = false
local rows = {}
local count = 0
local widest = 0
local titled = false
local zoom = 1

-- Whether the box sits in the corner the client keeps its own tooltip in
-- rather than beside the thing you hovered. Held here rather than read out of
-- ns.db for the reason UI.Size is: this layer is not allowed to know the name
-- of a setting, so Settings/Settings.lua reads the saved value and pushes it
-- in.
--
-- Docked to start with, because that is where fifteen years of playing this
-- game has put the box and because a tooltip that opens under the cursor is a
-- tooltip covering the row you were about to click. Beside is still there, and
-- it is the better answer on a wide screen where the corner is a long way from
-- what you are reading.
local docked = true

--------------------------------------------------------------------------
-- The lines
--
-- A row is two font strings, one anchored left and one anchored right, and a
-- line that is not a pair simply leaves the right one empty. Pooled and never
-- freed: a tooltip that has once drawn twenty lines can draw twenty again for
-- nothing, and twenty font strings is what one hover of an epic costs.
--------------------------------------------------------------------------

local function Row(index)
	local row = rows[index]
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
	row.left = UI.Label(frame, BODY, C.text, "LEFT", UI.FLAT)
	UI.Wrap(row.left, true)
	row.right = UI.Label(frame, BODY, C.text, "RIGHT", UI.FLAT)

	rows[index] = row
	return row
end

-- Everything a line needs, as loose values rather than a table. Colours arrive
-- as three numbers because half of them come out of the scanner that way, and
-- a table built per line to carry them would be garbage on a path that already
-- builds a formatted string or two.
local function Add(size, left, lr, lg, lb, right, rr, rg, rb)
	count = count + 1
	local row = Row(count)

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
	if row.natural > widest then
		widest = row.natural
	end
	return row
end

-- Air between two groups of lines, rather than an empty line of text.
--
-- It used to be a blank string at the small size, which cost thirteen units of
-- height to say nothing and made the gap between two groups taller than either
-- group's own line spacing. A spacer carries no text and no width, so it
-- widens nothing and reads as the pause it is.
local function Spacer()
	count = count + 1
	local row = Row(count)
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
local function ScanText(lines)
	if type(lines) ~= "table" or #lines < 1 then
		return false
	end
	for index = 1, #lines do
		local line = lines[index]
		Add(index == 1 and TITLE or BODY,
			line[1] or "", line[2] or C.text[1], line[3] or C.text[2], line[4] or C.text[3],
			line[5], line[6], line[7], line[8])
		if index == 1 then
			titled = true
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
--   { hint = "what to type" }        the quiet blue line that names a switch
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

-- The line that says what to type, or what a click would do.
--
-- Its own kind rather than a colour a caller passes, because it is the shape
-- Buffs/Nag.lua invented and the reason it invented it generalises: a square
-- that nags you about a sharpening stone has to carry the name of the switch
-- that silences it, or somebody tired of that square reads the whole panel
-- looking for it. Anything in this addon you can hover and be annoyed by owes
-- the hover that sentence.
local function Line(spec)
	if spec.blank then
		return Spacer()
	end
	if spec.hint then
		return Add(BODY, spec.hint, C.hint[1], C.hint[2], C.hint[3])
	end

	local color = spec.color or (spec[2] and C.dim) or C.text
	if spec[2] == nil then
		return Add(BODY, spec[1] or "", color[1], color[2], color[3])
	end

	local tone = spec.tone or C.text
	return Add(BODY, spec[1] or "", color[1], color[2], color[3],
		spec[2], tone[1], tone[2], tone[3])
end

local function Render(data)
	if not ScanText(data.scan) and data.title then
		local color = data.color or C.heading
		titled = true
		Add(TITLE, data.title, color[1], color[2], color[3])
	end

	for index = 1, #data do
		Line(data[index])
	end
end

--------------------------------------------------------------------------
-- Putting it on screen
--------------------------------------------------------------------------

local function Build()
	frame = CreateFrame("Frame", FRAME_NAME, UIParent)
	-- Above everything the addon draws and above the world, which is what a
	-- tooltip is for. TOOLTIP is the client's own name for that layer and
	-- Blizzard's own sits on it, so this lands beside it rather than under it.
	frame:SetFrameStrata("TOOLTIP")
	frame:SetClampedToScreen(true)
	frame:Hide()

	UI.Adopt(frame, zoom)

	-- Drawn before the background and one sublevel under it, so what shows is
	-- the two units of it that stick out past the bottom and the right. A
	-- tooltip floats over whatever it was opened on top of and needs to look
	-- like it does; every other surface in the addon sits in a window and does
	-- not.
	shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	shadow:SetColorTexture(C.shadow[1], C.shadow[2], C.shadow[3], C.shadow[4])
	shadow:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
	shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)

	frame.bg = ns.Fill(frame, "BACKGROUND", C.window[1], C.window[2], C.window[3], 1)
	frame.bg:SetAllPoints()
	frame.edges = ns.Outline(frame, C.edge[1], C.edge[2], C.edge[3], C.edge[4])
	ns.EdgeSize(frame.edges, ns.Pixel(frame))

	rule = UI.Rule(frame, C.hairline)
	rule:Hide()
end

-- The hairlines, which are the one part of this box measured in physical pixels
-- rather than in units. One physical pixel is 1/zoom units, so both of them
-- have to be rewritten whenever the zoom moves under the frame.
local function Hairlines()
	ns.EdgeSize(frame.edges, ns.Pixel(frame))
	rule:SetHeight(ns.Pixel(frame))
end

-- Take the owner's size. Guarded, because most hovers in a row are on frames
-- at the zoom the last one was and a rezoom is a SetScale on a frame the
-- client has already laid out.
local function Match(owner)
	local want
	if owner == Tooltip.CURSOR then
		-- Nothing under the pointer was drawn by this addon, so there is no zoom
		-- to take from it. The box takes the addon's own, which is what every
		-- window it could be sitting beside is drawn at.
		want = (UI.WindowZoom and UI.WindowZoom()) or 1
	else
		want = UI.ZoomOf(owner) or (UI.WindowZoom and UI.WindowZoom()) or 1
	end
	if want == zoom then
		return false
	end
	zoom = want
	UI.Rezoom(frame, want)
	Hairlines()
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
local function AtCursor()
	local x, y = CursorPixels()
	local scale = frame:GetEffectiveScale()
	if not x or not scale or scale == 0 then
		return false
	end

	local centre = UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2
	local ox, oy = x / scale, y / scale

	frame:ClearAllPoints()
	if x > centre then
		frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", ox - POINTER, oy - POINTER)
	else
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ox + POINTER, oy - POINTER)
	end
	return true
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
local function Units(value)
	return UI.Round(frame, UI.Convert(value, UIParent, frame))
end

-- The corner, which is the one anchor that does not care what was hovered.
--
-- Same corner for a feed row, a filter chip and a creature out in the world:
-- the box is a place on the screen you look at rather than a label on the thing
-- under the cursor. That is the whole of what docking buys, and it is why the
-- owner is not an argument here.
local function Dock()
	local x = (tonumber(CONTAINER_OFFSET_X) or DOCK_X) + DOCK
	local y = tonumber(CONTAINER_OFFSET_Y) or DOCK_Y
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -Units(x), Units(y))
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
-- **None of which happens while the box is docked.** Every side, every corner
-- and every clearance below is the answer to one question, which is how to put
-- a box next to a thing without covering it, and docking answers that question
-- by not being next to the thing at all.
local function Anchor(owner, above)
	if docked then
		Dock()
		return
	end

	if owner == Tooltip.CURSOR then
		if not AtCursor() then
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		end
		return
	end

	local centre = UIParent:GetWidth() / 2
	local left = ns.Measure(owner, "GetLeft")
	local right = ns.Measure(owner, "GetRight")
	local far = left and right and (left + right) / 2 > centre

	frame:ClearAllPoints()
	if above then
		if far then
			frame:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, OFFSET)
		else
			frame:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, OFFSET)
		end
	elseif far then
		frame:SetPoint("TOPRIGHT", owner, "TOPLEFT", -OFFSET, 0)
	else
		frame:SetPoint("TOPLEFT", owner, "TOPRIGHT", OFFSET, 0)
	end
end

-- Two passes over the lines, because the width of the box and the height of a
-- wrapped line each depend on the other. The first pass has already run: every
-- Add recorded what its line wants and kept the widest. This decides the box
-- from that, then gives every line the width it now has and asks how tall it
-- came out.
local function Layout()
	local content = widest
	if content > MAX then
		content = MAX
	end
	content = UI.Round(frame, content)

	local y = PAD
	for index = 1, count do
		local row = rows[index]
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
		if index == 1 and titled and count > 1 then
			rule:ClearAllPoints()
			rule:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + RULE))
			rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(y + RULE))
			rule:Show()
			y = y + RULE * 2 + ns.Pixel(frame)
		elseif index < count and not row.spacer then
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
local function Reset()
	for index = 1, count do
		rows[index].left:Hide()
		rows[index].left:ClearAllPoints()
		rows[index].right:Hide()
		rows[index].right:ClearAllPoints()
	end
	count, widest, titled = 0, 0, false
	rule:Hide()
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
function Tooltip.Show(owner, data, above)
	if not frame then
		Build()
	end
	Reset()

	if type(data) ~= "table" then
		frame:Hide()
		return false
	end

	Match(owner)
	Render(data)

	if count == 0 then
		frame:Hide()
		return false
	end

	Layout()
	-- After Layout, and it has to be. Above hangs the box's bottom edge off the
	-- owner's top, so where its top lands is its own height, and its height is
	-- not known until the lines have been measured and wrapped.
	Anchor(owner, above)
	opened, raised = owner, above
	frame:Show()
	return true
end

-- Dock the box in the corner, or put it back beside what it describes.
--
-- Pushed in by Settings/Settings.lua rather than read, and answered as whether
-- anything moved, which is the shape UI.SetSize has. A box that is up when the
-- switch flips is re-anchored on the spot: the switch is a checkbox in the
-- settings window with a hover of its own, so the box that demonstrates the
-- setting is usually the one on screen while you change it.
function Tooltip.SetDocked(on)
	on = on and true or false
	if on == docked then
		return false
	end
	docked = on
	if frame and frame:IsShown() and opened then
		Anchor(opened, raised)
	end
	return true
end

function Tooltip.Docked()
	return docked
end

function Tooltip.Close()
	opened = nil
	if frame then
		frame:Hide()
	end
	return true
end

-- What it is currently open on. Handed out because "the tooltip came up beside
-- the thing you hovered" is a claim scripts/harness.lua has to be able to make,
-- and reading it back off the anchor would be asserting the client's own
-- bookkeeping rather than this file's.
-- The box itself, so scripts/harness.lua can measure where it opened. Handed
-- out for the reason Owner is: "the tooltip sits above the chip rather than
-- beside it" is a claim about two rectangles, and there is no answering it from
-- the outside without one of them.
function Tooltip.Frame()
	return frame
end

function Tooltip.Owner()
	return opened
end

function Tooltip.IsShown()
	return frame ~= nil and frame:IsShown() and true or false
end

-- What zoom the last open drew at. Handed out for the same reason Owner is:
-- "the tooltip is the size of the thing it is describing" is the whole of the
-- fix above and it cannot be asserted from the outside any other way.
function Tooltip.Zoom()
	return zoom
end

-- How many lines the last open drew, for scripts/harness.lua and for anything
-- else that has to prove a hover said something without this file handing out
-- its pool.
function Tooltip.Lines()
	return count
end

-- One of those lines, as text. Same reason.
function Tooltip.Text(index)
	local row = rows[index]
	if not row or index > count then
		return nil
	end
	return row.left:GetText(), row.paired and row.right:GetText() or nil
end

-- And what size it was drawn at. Handed out for the reason the rest of these
-- are: the tooltip's body has to be the addon's body size, that claim is the
-- whole of the fix for a box whose text was smaller than the panel under it,
-- and reading it off the font string from outside would mean this file handing
-- out its pool.
function Tooltip.Size(index)
	local row = rows[index]
	if not row or index > count then
		return nil
	end
	local _, size = row.left:GetFont()
	return size
end

-- The grid moved under the frame. Nothing is laid out here and the zoom is not
-- touched: the box is rebuilt on every open, the next hover is the next open,
-- and what the zoom should be is the owner's business rather than this file's.
-- What does have to be rewritten is the two hairlines, because on a client with
-- no SetIgnoreParentScale a physical pixel is a fraction of a unit that moves
-- with the UI scale.
UI.OnRescale(function()
	if frame then
		Hairlines()
	end
end)
