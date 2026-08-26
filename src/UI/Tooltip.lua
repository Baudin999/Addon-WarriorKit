local ADDON, ns = ...

local UI = ns.UI
local C = UI.Color

--------------------------------------------------------------------------
-- The tooltip
--
-- Every hover in this addon has gone to GameTooltip until now, and that was
-- always the wrong surface for it. GameTooltip is Blizzard's parchment: a
-- tiled background asset, a gold border drawn from a corner sheet, Friz
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
-- **A caller hands over data, not a run of calls.** See the schema below. The
-- imperative writers this file used to publish are still here as locals and
-- are no longer a surface: five ways to write a line is five things a caller
-- can do in the wrong order, and the one that mattered, whether a title had
-- been written, was bookkeeping every caller had to get right.
--
-- **What it cannot do, and what it does about it.** An item's text is the
-- client's: the stats, the requirements, the sell price and the six coloured
-- lines under them are computed inside the game and there is no API that hands
-- them over as data. The supported way to read them is to point a tooltip of
-- your own at the link and read the font strings it filled in, which is what
-- `item` in the schema does. That tooltip needs GameTooltipTemplate, which is
-- the one template this file touches and the reason it is probed rather than
-- assumed: a client that refuses it costs the redraw and falls back to the
-- title the caller gave, because a name in the right chrome is a great deal
-- better than an item with no text at all.
--------------------------------------------------------------------------

local FRAME_NAME = "WarriorKitTooltip"

-- The scanner's name is load bearing. A GameTooltip's lines are reachable only
-- as globals built from the frame's own name, so a nameless one has text on it
-- that nothing can read.
local SCAN_NAME = "WarriorKitTooltipScan"

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

-- Two sizes and no more. A title that is the body size is not a title, and a
-- third size in a box this small is a typeface competition.
local TITLE = 13
local BODY = 11

local Tooltip = {}
UI.Tooltip = Tooltip

local frame, shadow, rule
local opened
local rows = {}
local count = 0
local widest = 0
local titled = false
local zoom = 1

--------------------------------------------------------------------------
-- Reading an item out of the client
--
-- Probed once and remembered, because the answer cannot change inside a
-- session and the alternative is a pcall on a CreateFrame on every hover.
--------------------------------------------------------------------------

local scanner
local scannable

-- Whether a scan has ever actually come back with text on it. Three states and
-- all three are different: nil is nothing has been hovered, false is the frame
-- was made and answered nothing, true is it worked. Kept apart because
-- "refused" and "answered nothing" have different fixes and a Describe that
-- reported the probe rather than the outcome would claim the first was the
-- second.
local scanned

local function Scanner()
	if scannable ~= nil then
		return scanner
	end

	scannable = false
	local made, tip = pcall(CreateFrame, "GameTooltip", SCAN_NAME, UIParent, "GameTooltipTemplate")
	if made and tip and type(tip.SetHyperlink) == "function" and type(tip.NumLines) == "function" then
		-- ANCHOR_NONE and never shown. This frame exists to be written to and
		-- read back, and one that anchored itself to the cursor would flash a
		-- second tooltip on every hover.
		if type(tip.SetOwner) == "function" then
			tip:SetOwner(UIParent, "ANCHOR_NONE")
		end
		scanner, scannable = tip, true
	end
	return scanner
end

-- One side of one line the scanner filled in, as text and three colour
-- components. Nil for a line that is not there or came back empty, which is
-- every right hand side on most lines.
local function Scanned(index, side)
	local text = _G[SCAN_NAME .. "Text" .. side .. index]
	if not text or type(text.GetText) ~= "function" then
		return nil
	end
	local body = text:GetText()
	if not body or body == "" then
		return nil
	end
	if type(text.GetTextColor) ~= "function" then
		return body, C.text[1], C.text[2], C.text[3]
	end
	local r, g, b = text:GetTextColor()
	return body, r, g, b
end

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

-- The client's own text for an item, redrawn in this chrome.
--
-- False where the scan is not available or the link is one the client will not
-- resolve, so the caller's own title stands instead of a box with nothing in
-- it. Every line keeps the colour the client gave it, because on an item that
-- colour is information: the name is the quality, the red line is the
-- requirement you do not meet, and the green is the enchant.
local function ItemText(link)
	local tip = Scanner()
	if not tip or type(link) ~= "string" then
		return false
	end

	if type(tip.ClearLines) == "function" then
		tip:ClearLines()
	end
	-- A link somebody built by hand raises here rather than coming back empty,
	-- the same as it does in the chat log's hyperlink handler.
	if not pcall(tip.SetHyperlink, tip, link) then
		return false
	end

	local lines = tip:NumLines() or 0
	if lines < 1 then
		-- The scanner exists and produced nothing, which is not the same state
		-- as never having tried and is not the same state as the client
		-- refusing the frame. Recorded so Describe reports what actually
		-- happens rather than what the probe hoped for.
		scanned = false
		return false
	end
	scanned = true

	for index = 1, lines do
		local left, lr, lg, lb = Scanned(index, "Left")
		local right, rr, rg, rb = Scanned(index, "Right")
		if left or right then
			Add(index == 1 and TITLE or BODY,
				left or "", lr or C.text[1], lg or C.text[2], lb or C.text[3],
				right, rr, rg, rb)
			if index == 1 then
				titled = true
			end
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
--   item   an item link. The client's own text for it is drawn instead of the
--          title where this client will hand that text over, and the title
--          stands where it will not.
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
	if not (data.item and ItemText(data.item)) and data.title then
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
	-- GameTooltip sits on it, so this lands beside it rather than under it.
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
	local want = UI.ZoomOf(owner) or (UI.WindowZoom and UI.WindowZoom()) or 1
	if want == zoom then
		return false
	end
	zoom = want
	UI.Rezoom(frame, want)
	Hairlines()
	return true
end

-- Which side of the owner it opens on, and which corner of itself it hangs
-- from. Right of the owner normally, and left of it once the owner is past the
-- middle of the screen, because a tooltip clamped to the screen edge is one
-- that covers the thing you are hovering.
local function Anchor(owner)
	local centre = UIParent:GetWidth() / 2
	local left = ns.Measure(owner, "GetLeft")
	local right = ns.Measure(owner, "GetRight")

	frame:ClearAllPoints()
	if left and right and (left + right) / 2 > centre then
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
function Tooltip.Show(owner, data)
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
	Anchor(owner)
	opened = owner
	frame:Show()
	return true
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

--------------------------------------------------------------------------
-- Hanging one on a frame
--
-- A mouse enabled frame swallows every button that lands on it, and the right
-- button drag that turns the camera is one of those. Everything in this addon
-- you can hover sits over the middle of the screen, which is exactly where that
-- drag starts, so a tooltip bought at the price of a camera that will not turn
-- is a bad trade made silently.
--
-- SetPassThroughButtons hands the two the camera wants back. It arrived in
-- 1.14.4 and 10.0 and neither target client is proven to carry it, so it is
-- probed and then pcalled rather than trusted: a name that exists while
-- refusing these arguments would raise once per hoverable frame at login.
--
-- Where the client has neither, a right drag begun on one of these frames does
-- not turn the camera. That is the real price of every tooltip in the addon and
-- it is worth saying out loud rather than discovering. It was written once in
-- Buffs/Nag.lua for the four squares of a nag row; a feed of four hundred rows
-- is the same trap at forty times the area, which is what moved it here.
--------------------------------------------------------------------------

function UI.PassCamera(owner)
	if type(owner.SetPassThroughButtons) ~= "function" then
		return false
	end
	return pcall(owner.SetPassThroughButtons, owner, "RightButton", "MiddleButton")
end

-- The convenience for the ordinary case: a frame whose whole answer to the
-- mouse is a tooltip. `describe` is handed the frame and answers the table
-- above, or nothing at all for a frame that has nothing to say.
--
-- A caller that also wants to paint on the way in and out, which every row in a
-- feed does, hangs its own scripts and calls Show and Close from inside them,
-- and calls UI.PassCamera itself.
function UI.Tip(owner, describe)
	owner:SetScript("OnEnter", function(self)
		Tooltip.Show(self, describe(self))
	end)
	owner:SetScript("OnLeave", function()
		Tooltip.Close()
	end)
	UI.PassCamera(owner)
	return owner
end

function Tooltip.Describe()
	if scannable == false then
		return "this client refused a tooltip of its own, so an item's own text cannot be read"
	end
	if scanned == nil then
		return "no item has been hovered yet"
	end
	if not scanned then
		return "this client hands over no text for an item, so a row shows its name and nothing more"
	end
	return "drawing an item's own text in the addon's chrome"
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
