local ADDON, ns = ...

local Rails = {}
ns.ProgressRails = Rails

--------------------------------------------------------------------------
-- Two rails at the bottom of the screen
--
-- The experience bar and the reputation bar, drawn by this addon. They were the
-- last thing on the screen still wearing Blizzard's art: Artwork/Artwork.lua
-- strips the gryphons and the metal strip off the action bars and leaves these
-- two alone on purpose, because an experience bar is not furniture, it is a
-- reading. So the art came off the bars around it and the reading stayed in the
-- 2007 frame, which is the mismatch this file closes.
--
-- **One frame, up to two rails.** The experience rail is on top and the
-- reputation rail under it, which is the order the client has always drawn them
-- in and is the one thing about this widget nobody has to learn. A rail with
-- nothing to say is not drawn small or drawn empty, it is not there: at the
-- level cap the frame is the reputation rail alone, with no faction watched it
-- is the experience rail alone, and with neither there is no frame on the
-- screen at all. That is the same rule Buffs/Nag.lua ships, and it is worth
-- more here than a tidy rectangle: what is on the screen is what is true.
--
-- **Nothing here is on a ticker.** Experience moves when you kill something and
-- reputation moves when the client says it did, so this file draws on five
-- events and on nothing else. That is why no function in it is in check.sh's
-- HOT list and why the writes below are not guarded against the value already
-- on the widget: a guard is worth one comparison against a write that happens
-- on every frame, and these happen a few times a minute.
--
-- **The rested pool is drawn rather than written.** The section of the rail
-- between where you are and where the rested bonus runs out is a second fill in
-- the blue this game has used for it since it shipped. It is the one number on
-- the bar that changes what a kill is worth, and a player who is about to spend
-- an evening's rest should be able to see it without hovering anything.
--
-- **Twenty segments.** The marks across the experience rail are the bubbles the
-- client has drawn since 2004, and they are still the unit people count in.
-- They come off below 160 pixels of width, where twenty of anything is a
-- texture every eight pixels and the rail reads as hatching.
--------------------------------------------------------------------------

local Progress = ns.Progress
local Gauge = ns.UI.Gauge
local Color = ns.Unit.Color

local FRAME_NAME = "WarriorKitProgress"

-- One rail to the next. Two pixels, the same as the swing bars: one would put
-- two hairlines against each other and read as a single thick line.
local GAP = 2

local PAD = 5
local TEXT_FLOOR = 7
local TEXT_CEILING = 12

-- The glyph's share of a rail's height, under the height less two hairlines at
-- every size the rail is allowed to be.
local TEXT_SHARE = 0.62

-- What the rails are allowed to be, shared with the panel and the slash word so
-- all three clamp to the same numbers.
local WIDTH_LOW, WIDTH_HIGH = 120, 900
local HEIGHT_LOW, HEIGHT_HIGH = 6, 32

-- The client's own bubbles: twenty segments, which is nineteen marks.
local SEGMENTS = 20

-- Under this much width the marks come off on their own, whatever the setting
-- says. Eight design pixels a segment is where a rail stops reading as a bar
-- with divisions in it and starts reading as a fence, and it is inside the
-- widths the rail is allowed to be, so the floor is a state you can reach with
-- the slider rather than a number nothing can get under.
local BUBBLE_FLOOR = SEGMENTS * 8

local XP_FILL = Color.progress.experience
local RESTED_FILL = Color.progress.rested
local IDLE_FILL = Color.reaction.idle
local EDGE = Color.frame.idle
local MARK = { 0, 0, 0, 0.35 }

local NAME_TEXT = Color.text.name
local VALUE_TEXT = Color.text.value

local frame, xp, faction, grab, title
local built = false

-- One design pixel in this frame's units, which is exactly 1 once ns.UI.Adopt
-- has taken the frame onto the grid. Read again on every layout pass, because
-- off the grid it is a fraction of the screen height and a monitor swap moves
-- it.
local unit = 1

-- Which rails the current layout was built for. Compared on every refresh: a
-- faction you started watching mid session changes the height of the frame, and
-- that is a layout rather than a value.
local shape = { xp = false, faction = false }

local function Whole(value)
	return math.floor(value + 0.5)
end

-- Whether each rail has anything to draw. Unlocked, both are drawn whatever the
-- client says, because a frame you are dragging has to be a rectangle you can
-- see and a rail that is not there is not one.
local function Wanted()
	if not ns.db or not ns.db.progress then
		return false, false
	end
	local unlocked = not ns.db.locked
	local hasXP = Progress.Experience() ~= nil
	local hasFaction = Progress.Faction() ~= nil
	return hasXP or unlocked,
		ns.db.progressFaction and (hasFaction or unlocked) or false
end

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

local function BuildRail(bubbles)
	local rail = { bar = Gauge.New(frame) }
	local bar = rail.bar
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)

	-- The rested pool, drawn between where you are and where the bonus runs
	-- out. A texture of its own rather than a second status bar: it starts at
	-- the fill's edge rather than at the rail's, so it is placed by hand.
	--
	-- One sublevel above the spent track and still under the fill's own layer,
	-- which is the ordering ns.UI.Gauge's head sets out. Inside one frame layer
	-- beats level, so nothing a caller writes later can move it.
	if bubbles then
		rail.rested = ns.Fill(bar, "BACKGROUND",
			RESTED_FILL[1], RESTED_FILL[2], RESTED_FILL[3], 1)
		rail.rested:SetDrawLayer("BACKGROUND", 1)
		rail.rested:Hide()

		rail.marks = {}
		for index = 1, SEGMENTS - 1 do
			local mark = ns.Fill(bar, "OVERLAY", MARK[1], MARK[2], MARK[3], MARK[4])
			mark:Hide()
			rail.marks[index] = mark
		end
	end

	-- Made after the fill and after the marks, because within one draw layer the
	-- order is the order the textures were made and the rim has to stay on top
	-- of both.
	bar.edges = ns.Outline(bar, EDGE[1], EDGE[2], EDGE[3], 1, "OVERLAY")

	-- Both strings on the bar rather than on the frame, so they sit over the
	-- fill. Flat and unshadowed: this is an opaque surface the addon painted
	-- itself, which is the whole of what ns.UI.FLAT means.
	rail.left = ns.UI.Label(bar, TEXT_CEILING, NAME_TEXT, "LEFT", ns.UI.FLAT)
	rail.right = ns.UI.Label(bar, TEXT_CEILING, VALUE_TEXT, "RIGHT", ns.UI.FLAT)

	-- Everything the rail drew, hung off the gauge, for the reason
	-- PlayerCast.Bar hands its two strings over the same way: what was written
	-- on a bar has to be readable from scripts/harness.lua and from a macro,
	-- and the alternative is this file handing out its own state table.
	bar.left, bar.right = rail.left, rail.right
	bar.rested, bar.marks = rail.rested, rail.marks
	return rail
end

--------------------------------------------------------------------------
-- What a hover says
--
-- Two boxes, one per rail, through the addon's own tooltip. Everything on them
-- is a number the rail itself cannot carry: what is left of this level, what
-- the rested pool is worth, and what the session says the rest of the level
-- will cost you in minutes.
--------------------------------------------------------------------------

-- Each line is a table, which is what UI/Tip.lua reads as one line: a label on
-- the left and the number on the right, or a single string where there is no
-- pair to make. An array of plain strings is one line with a label and three
-- values, which is the mistake this comment exists to stop.
local function ExperienceLines()
	local level, value, max, rested = Progress.Experience()
	if not level then
		return { { "Nothing to count. This character is at the level cap, has"
			.. " experience switched off, or is on a client that will not say." } }
	end
	local lines = {
		{ ("Level %d"):format(level),
			("%d%% of the way to %d"):format(math.floor(value / max * 100), level + 1) },
		{ "To go", ("%s of %s"):format(ns.Thousands(max - value), ns.Thousands(max)) },
	}
	if rested then
		lines[#lines + 1] = { "Rested",
			("%s, worth double until it is spent"):format(ns.Thousands(math.floor(rested))) }
	end
	local rate, eta = Progress.Rate(), Progress.Eta()
	if rate and eta then
		lines[#lines + 1] = { "This session",
			("%s an hour, so level %d in %s"):format(ns.Thousands(math.floor(rate)),
				level + 1, Progress.Clock(eta)) }
	else
		lines[#lines + 1] = { "This session",
			"not long enough yet to say what you are earning an hour" }
	end
	return lines
end

local function FactionLines()
	local name, standing, into, span = Progress.Faction()
	if not name then
		return { { "No faction watched. Pick one in the client's own reputation"
			.. " pane and it turns up here." } }
	end
	local label = Progress.Standing(standing)
	if span <= 0 then
		return { { label, "there is no further to go" } }
	end
	return {
		{ label, ("%s of %s"):format(ns.Thousands(into), ns.Thousands(span)) },
		{ ("To %s"):format(Progress.Standing(standing + 1)), ns.Thousands(span - into) },
	}
end

local function Hover(rail, title_, lines, hint)
	ns.Tip.Hang(rail.bar, function()
		return { kind = "note", title = title_, lines = lines(), hint = hint }
	end)
end

local function Build()
	frame = CreateFrame("Frame", FRAME_NAME, UIParent)
	ns.UI.Adopt(frame, ns.db.progressZoom)
	unit = ns.UI.Unit(frame)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetScript("OnDragStart", function(self)
		if not ns.db.locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint()
		-- Rounded, because a drag lands wherever the cursor was and this frame
		-- is on the grid, where a fractional offset rasterises every edge inside
		-- it across two rows of pixels.
		ns.db.progressPoint = { point, "UIParent", relativePoint, Whole(x), Whole(y) }
		Rails.Apply()
	end)

	grab = ns.UI.Box(frame, nil, ns.UI.Color.edge)
	grab:SetAllPoints(frame)
	grab:Hide()

	-- At the outline floor rather than the panel's body size, the same as the
	-- swing bars' own label: this sits over the world while the frame is being
	-- placed, so it has to carry a rim.
	title = ns.UI.Label(frame, ns.UI.OutlineFloor(), ns.UI.Color.heading,
		"LEFT", ns.UI.OUTLINE)
	title:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2 * unit)
	title:SetText("WarriorKit experience")
	title:Hide()

	xp = BuildRail(true)
	faction = BuildRail(false)
	Gauge.Paint(xp.bar, xp.bar.track, XP_FILL)
	xp.look = XP_FILL

	Hover(xp, "Experience", ExperienceLines, "/wk xp off takes both rails off the screen.")
	Hover(faction, "Reputation", FactionLines,
		"/wk xp faction off leaves the experience rail on its own.")

	frame:Hide()
	built = true
end

--------------------------------------------------------------------------
-- Laying out
--------------------------------------------------------------------------

local function Marks(width, height)
	local on = ns.db.progressBubbles and width >= BUBBLE_FLOOR
	for index = 1, SEGMENTS - 1 do
		local mark = xp.marks[index]
		if on then
			mark:ClearAllPoints()
			mark:SetPoint("TOPLEFT", xp.bar, "TOPLEFT",
				Whole(width * index / SEGMENTS) * unit, 0)
			mark:SetSize(ns.Pixel(xp.bar), height * unit)
			mark:Show()
		else
			mark:Hide()
		end
	end
end

local function SizeRail(rail, width, height, offset)
	local bar = rail.bar
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -offset * unit)
	bar:SetSize(width * unit, height * unit)
	-- One screen pixel, and one at every zoom, which is what ns.Pixel answers
	-- and ns.UI.Unit does not.
	ns.EdgeSize(bar.edges, ns.Pixel(bar))

	-- Taken off the rail's height rather than fixed, because the height is a
	-- setting and the same code draws a six pixel line and a thirty two pixel
	-- block. Raw pixels, not units: inside a frame ns.UI.Adopt has taken onto
	-- the grid a font size already is a pixel height.
	local size = math.max(TEXT_FLOOR,
		math.min(TEXT_CEILING, math.floor(height * TEXT_SHARE)))
	local font = ns.UI.Font(size, ns.UI.FLAT)
	rail.left:SetFontObject(font)
	rail.right:SetFontObject(font)

	rail.right:ClearAllPoints()
	rail.right:SetPoint("RIGHT", bar, "RIGHT", -PAD * unit, 0)
	-- Pinned to the number rather than given a width, so a long faction name
	-- yields to the count beside it. The count is the half that moves.
	rail.left:ClearAllPoints()
	rail.left:SetPoint("LEFT", bar, "LEFT", PAD * unit, 0)
	rail.left:SetPoint("RIGHT", rail.right, "LEFT", -PAD * unit, 0)
end

-- Everything a setting can move. Called at login, whenever a number in the
-- panel changes, whenever the grid moves under the frame, and whenever a rail
-- appears or disappears.
function Rails.Apply()
	if not built or not ns.db then
		return
	end

	local point = ns.db.progressPoint
	frame:ClearAllPoints()
	frame:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	ns.UI.Rezoom(frame, ns.db.progressZoom)
	unit = ns.UI.Unit(frame)

	local width, height = ns.db.progressWidth, ns.db.progressHeight
	shape.xp, shape.faction = Wanted()

	local rows = 0
	if shape.xp then
		SizeRail(xp, width, height, 0)
		Marks(width, height)
		rows = 1
	end
	if shape.faction then
		SizeRail(faction, width, height, rows * (height + GAP))
		rows = rows + 1
	end
	xp.bar:SetShown(shape.xp)
	faction.bar:SetShown(shape.faction)

	local total = rows * height + math.max(0, rows - 1) * GAP
	frame:SetSize(width * unit, math.max(1, total) * unit)
	frame:SetShown(rows > 0)

	Rails.Lock()
	Rails.Paint()
end

--------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------

local function PaintXP()
	local level, value, max, rested = Progress.Experience()
	if not level then
		xp.bar:SetMinMaxValues(0, 1)
		xp.bar:SetValue(0)
		xp.left:SetText("experience")
		xp.right:SetText("nothing left to earn")
		xp.rested:Hide()
		return
	end

	xp.bar:SetMinMaxValues(0, max)
	xp.bar:SetValue(value)
	xp.left:SetText(("level %d"):format(level))
	xp.right:SetText(("%s / %s  %d%%"):format(ns.Thousands(value),
		ns.Thousands(max), math.floor(value / max * 100)))

	-- The rested pool, from the fill's edge to wherever the bonus runs out,
	-- clamped at the end of the level. A pool bigger than the level is a real
	-- state after a week away, and drawn unclamped it would hang off the end of
	-- the rail.
	local width = ns.db.progressWidth
	local left = Whole(value / max * width)
	local span = Whole(math.min(rested or 0, max - value) / max * width)
	if span < 1 then
		xp.rested:Hide()
		return
	end
	xp.rested:ClearAllPoints()
	xp.rested:SetPoint("TOPLEFT", xp.bar, "TOPLEFT", left * unit, 0)
	xp.rested:SetSize(span * unit, ns.db.progressHeight * unit)
	xp.rested:Show()
end

local function PaintFaction()
	local name, standing, into, span = Progress.Faction()
	if not name then
		if faction.look ~= IDLE_FILL then
			faction.look = IDLE_FILL
			Gauge.Paint(faction.bar, faction.bar.track, IDLE_FILL)
		end
		faction.bar:SetMinMaxValues(0, 1)
		faction.bar:SetValue(0)
		faction.left:SetText("reputation")
		faction.right:SetText("nothing watched")
		return
	end

	local fill = Color.reaction[Progress.Band(standing)]
	if faction.look ~= fill then
		faction.look = fill
		Gauge.Paint(faction.bar, faction.bar.track, fill)
	end

	local label = Progress.Standing(standing)
	faction.left:SetText(name)
	if span <= 0 then
		-- Exalted, where the client answers a band no wide. A full rail and the
		-- word on its own, because a count of nothing out of nothing is the one
		-- reading that would be worse than no reading.
		faction.bar:SetMinMaxValues(0, 1)
		faction.bar:SetValue(1)
		faction.right:SetText(label)
		return
	end
	faction.bar:SetMinMaxValues(0, span)
	faction.bar:SetValue(into)
	faction.right:SetText(("%s  %s / %s"):format(label, ns.Thousands(into),
		ns.Thousands(span)))
end

-- Every number on both rails, written again. Called from the layout and from
-- the client saying something moved, and never from a ticker.
function Rails.Paint()
	if not built or not ns.db then
		return
	end
	if shape.xp then
		PaintXP()
	end
	if shape.faction then
		PaintFaction()
	end
end

-- The client said something moved. A rail that has appeared or gone is a layout
-- rather than a value, so the shape is compared first and the whole frame is
-- laid out again where it differs.
function Rails.Refresh()
	if not built or not ns.db then
		return
	end
	local wantXP, wantFaction = Wanted()
	if wantXP ~= shape.xp or wantFaction ~= shape.faction then
		Rails.Apply()
		return
	end
	Rails.Paint()
end

--------------------------------------------------------------------------

-- Locked is the normal state, and it is the state the hovers work in. Unlocked
-- the frame takes the mouse and the rails give it up, because a rail that
-- answered the pointer would swallow the drag that is the whole point of
-- unlocking.
function Rails.Lock()
	if not built then
		return
	end
	local unlocked = not ns.db.locked
	frame:EnableMouse(unlocked)
	xp.bar:EnableMouse(not unlocked)
	faction.bar:EnableMouse(not unlocked)
	if unlocked then
		frame:RegisterForDrag("LeftButton")
		grab:Show()
		title:Show()
	else
		frame:RegisterForDrag()
		grab:Hide()
		title:Hide()
	end

	-- Unlocking changes what is drawn, not only what takes the mouse: a
	-- character at the cap with no faction watched has no frame at all, and
	-- "unlock the frames and drag it" would otherwise mean dragging nothing.
	-- Safe from the layout, which sets the shape before it calls this, so the
	-- refresh finds nothing to lay out again and only repaints.
	Rails.Refresh()
end

function Rails.Reset()
	ns.db.progressPoint = ns.DefaultCopy("progressPoint")
	Rails.Apply()
end

-- What the rails are allowed to be. One source for the panel's two sliders and
-- for the clamp the slash word goes through, because two copies of a range is
-- two chances for one of them to accept a number the other would refuse.
function Rails.SizeRange()
	return WIDTH_LOW, WIDTH_HIGH, HEIGHT_LOW, HEIGHT_HIGH
end

-- One rail, for scripts/harness.lua and for a macro. Handed out rather than
-- kept private for the reason SwingGauges.Bar is: the harness has to measure
-- what was drawn, and there is no other way to reach it.
function Rails.Bar(which)
	if not built then
		return nil
	end
	return (which == "faction") and faction.bar or xp.bar
end

-- One line for /wk status and for the panel.
function Rails.Describe()
	if not ns.db.progress then
		return "off, and the client's own bars are wherever `/wk hide xp` left them"
	end
	local rows = {}
	if shape.xp then
		rows[#rows + 1] = "experience"
	end
	if shape.faction then
		rows[#rows + 1] = "reputation"
	end
	if #rows == 0 then
		return "on, and drawing nothing: no experience to count and no faction watched"
	end
	return ("on, %d by %d pixels, drawing %s"):format(ns.db.progressWidth,
		ns.db.progressHeight, table.concat(rows, " and "))
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		Build()
	end
	Rails.Apply()
end)

-- Every experience and reputation change, through the one accumulator that is
-- watching them anyway.
Progress.OnChange(function()
	Rails.Refresh()
end)

-- A resolution change moves every size in this file at once, the same way it
-- moves the swing bars and the cast bar.
ns.UI.OnRescale(function()
	Rails.Apply()
end)
