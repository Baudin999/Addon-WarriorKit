local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

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
-- **What it cannot do, and what it does about it.** An item's text is the
-- client's: the stats, the requirements, the sell price and the six coloured
-- lines under them are computed inside the game and there is no API that hands
-- them over as data. The supported way to read them is to point a tooltip of
-- your own at the link and read the font strings it filled in, which is what
-- Tip:Item does. That tooltip needs GameTooltipTemplate, which is the one
-- template this file touches and the reason it is probed rather than assumed:
-- a client that refuses it costs the redraw and falls the caller back to
-- GameTooltip itself, because Blizzard's tooltip in the wrong style is a great
-- deal better than an item with no text at all.
--------------------------------------------------------------------------

local FRAME_NAME = "WarriorKitTooltip"

-- The scanner's name is load bearing. A GameTooltip's lines are reachable only
-- as globals built from the frame's own name, so a nameless one has text on it
-- that nothing can read.
local SCAN_NAME = "WarriorKitTooltipScan"

-- Every number here is a unit, which is one physical pixel inside a frame
-- ns.UI.Adopt has taken onto the grid.
local PAD = 8       -- the edge to the first glyph
local GAP = 3       -- one line to the next
local COLUMN = 14   -- the left column to the right one on a paired line
local RULE = 4      -- the air either side of the hairline under a title
local MAX = 300     -- the widest a line is drawn before it wraps
local OFFSET = 6    -- the owner to the tooltip

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

	row = {}
	row.left = UI.Label(frame, M.font, C.text, "LEFT", UI.FLAT)
	row.left:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, 0)
	UI.Wrap(row.left, true)

	row.right = UI.Label(frame, M.font, C.text, "RIGHT", UI.FLAT)
	row.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, 0)

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

--------------------------------------------------------------------------
-- What a caller writes
--
-- The five below are the whole surface. Each takes a colour as the three
-- component array the theme and the unit palette both hand out, so a caller
-- says ns.UI.Color.dim rather than three numbers.
--------------------------------------------------------------------------

-- The first line, in the heading size. Drawn with a hairline under it, which
-- is what separates a name from the facts about it.
function Tooltip.Title(text, color)
	color = color or C.heading
	titled = true
	return Add(M.heading, text, color[1], color[2], color[3])
end

function Tooltip.Line(text, color)
	color = color or C.text
	return Add(M.font, text, color[1], color[2], color[3])
end

-- A label and its value, pushed to opposite edges. This is the shape most of
-- what a feed says about an entry takes: where it came from, what it hit, how
-- much of it there was.
function Tooltip.Pair(left, right, leftColor, rightColor)
	leftColor = leftColor or C.dim
	rightColor = rightColor or C.text
	return Add(M.font, left, leftColor[1], leftColor[2], leftColor[3],
		right, rightColor[1], rightColor[2], rightColor[3])
end

-- The line that says what to type, or what a click would do.
--
-- Its own writer rather than a colour a caller passes, because it is the shape
-- Buffs/Nag.lua invented and the reason it invented it generalises: a square
-- that nags you about a sharpening stone has to carry the name of the switch
-- that silences it, or somebody tired of that square reads the whole panel
-- looking for it. Anything in this addon you can hover and be annoyed by owes
-- the hover that sentence.
function Tooltip.Hint(text)
	return Add(M.font, text, C.hint[1], C.hint[2], C.hint[3])
end

function Tooltip.Blank()
	return Add(M.small, " ", C.text[1], C.text[2], C.text[3])
end

-- The client's own text for an item, redrawn in this chrome.
--
-- False where the scan is not available or the link is one the client will not
-- resolve, so a caller can fall back rather than draw a box with a name in it
-- and nothing else. Every line keeps the colour the client gave it, because on
-- an item that colour is information: the name is the quality, the red line is
-- the requirement you do not meet, and the green is the enchant.
function Tooltip.Item(link)
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
			Add(index == 1 and M.heading or M.font,
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

	zoom = UI.WindowZoom and UI.WindowZoom() or 1
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
		-- A paired line never wraps. Its right hand side is a number or a word
		-- and its left is a label, and a label that folded onto a second line
		-- would put the value beside the wrong half of it.
		if row.paired then
			row.left:SetWidth(math.max(content - COLUMN - (row.right:GetStringWidth() or 0), 1))
		else
			row.left:SetWidth(content)
		end

		local height = UI.Round(frame, UI.TextHeight(row.left, row.size + 2))
		row.left:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
		if row.paired then
			row.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
		end

		y = y + height
		if index == 1 and titled and count > 1 then
			rule:ClearAllPoints()
			rule:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + RULE))
			rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(y + RULE))
			rule:Show()
			y = y + RULE * 2 + ns.Pixel(frame)
		elseif index < count then
			y = y + GAP
		end
	end

	frame:SetSize(content + PAD * 2, y + PAD)
end

-- Everything from the last hover, put away. The rows keep their font strings
-- and their anchors; only the text and the accounting are cleared, because a
-- font string with nothing in it costs nothing to leave lying about and one
-- that has to be rebuilt costs a frame.
local function Reset()
	for index = 1, count do
		rows[index].left:Hide()
		rows[index].right:Hide()
	end
	count, widest, titled = 0, 0, false
	rule:Hide()
end

-- Open on an owner, filled by a function that calls the five writers above.
--
-- Nothing is drawn for a fill that wrote no lines. That is the honest answer
-- to a row whose entry has gone: an empty box the size of its own padding is
-- worse than no box.
function Tooltip.Open(owner, fill)
	if not frame then
		Build()
	end
	Reset()

	fill(Tooltip)

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

-- How many lines the last open drew, for scripts/harness.lua and for anything
-- else that has to prove a hover said something without this file handing out
-- its pool.
function Tooltip.Lines()
	return count
end

-- One line of one of those lines, as text. Same reason.
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
-- mouse is a tooltip. A caller that also wants to paint on the way in and out,
-- which every row in a feed does, hangs its own scripts and calls Open and
-- Close from inside them, and calls UI.PassCamera itself.
--
-- A fill that writes no lines draws nothing, which is how a square with nothing
-- to say refuses rather than leaving the last frame's sentence on screen
-- pointing at this one.
function UI.Tip(owner, fill)
	owner:SetScript("OnEnter", function(self)
		Tooltip.Open(self, fill)
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

-- The grid moved, so the frame's own hairline and its zoom have to move with
-- it. Nothing is laid out here: the box is rebuilt on every open and the next
-- hover is the next open.
UI.OnRescale(function()
	if not frame then
		return
	end
	local want = UI.WindowZoom and UI.WindowZoom() or 1
	if want ~= zoom then
		zoom = want
		UI.Rezoom(frame, zoom)
	end
	ns.EdgeSize(frame.edges, ns.Pixel(frame))
end)
