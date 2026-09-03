local ADDON, ns = ...

local MeterWindow = {}
ns.MeterWindow = MeterWindow

--------------------------------------------------------------------------
-- The two panes
--
-- A clear background, on purpose and not as a default anyone is expected to
-- change. Details draws a window: a title bar, a frame, a backdrop, a resize
-- grip and a row of buttons, and the reason it needs all of that is that it is
-- a tool you go and use. This is not that. It is two columns of numbers you
-- read out of the corner of your eye during a pull, and every pixel of chrome
-- around them is a pixel of the fight it is standing on.
--
-- So there is no window. There are rows, each with a class coloured bar as
-- long as that player's share of the top one, and the bars are the only
-- surface drawn at all. The text is outlined rather than shadowed, which is
-- what UI/Text.lua's default flag is for and the reason it exists: these
-- glyphs sit over the world and a drop shadow disappears against a dark floor.
--
-- Both panes are children of one frame, so dragging either drags both and
-- there is one saved anchor rather than two to keep beside each other.
--
-- Mouse. The frame takes the mouse only while it is unlocked, for the same
-- reason the charge button does: a mouse enabled frame swallows every button
-- that lands on it, including the right button drag that turns the camera, and
-- this sits in the part of the screen where that drag starts. The one
-- exception is the damage pane's header, which opens the breakdown on the left
-- button and swaps DPS for HPS on the right, and is sixteen pixels tall. A
-- control you are meant to click has to be clickable while the frame it is on
-- is locked, or it is not a control.
--------------------------------------------------------------------------

local FRAME_NAME = "WarriorKitMeter"

-- Every one of these is a unit, and a unit is one physical pixel at zoom 1 and
-- a whole block of them at any higher whole zoom. Nothing here is multiplied by
-- ns.Pixel: the frame is on the grid, so the numbers below are what gets drawn.
-- The icon first, because every other number here follows it.
--
-- 27, and not a number anyone picked for looking right. The client stores a
-- spell icon at 64 texels, the crop in UI/Draw.lua takes the five texel border
-- off each edge, and 54 are left to sample. A draw is exact only where those 54
-- halve down onto whole pixels, which is 54 and 27 and nothing in between, and
-- ns.UI.IconSizes is where that list comes from. Drawn at 12, which is what
-- this shipped as for about an hour, the renderer blends the 27 copy and the
-- 13.5 copy and the result is mush.
--
-- At zoom 1 this draws 27 from the half size copy and at zoom 2 it draws 54
-- from the full one, which is the sharpest a spell icon gets. Zoom 3 draws 81
-- and is blended; the panel says so rather than pretending otherwise.
local ICON = 27

-- The row is the icon with one pixel above and below it, so the icon is what
-- decides the height rather than the text.
local ROW = 29
local ROW_GAP = 1
local HEADER = 16
local RULE = 1
local INSET = 1     -- the row edge to the icon
local GUTTER = 4    -- the icon to the name
local PANE_GAP = 8  -- the damage pane to the threat pane

-- Font sizes, in pixels, because inside a frame on the grid a font size is a
-- pixel height rather than a point.
--
-- Every string on the meter is outlined and every one of them has to be, which
-- is what sets the floor under both of these numbers.
--
-- The meter has no background. The outline is the only thing between a number
-- and a pale floor behind it, so unlike a timer on a debuff square this text
-- cannot trade the rim for a shadow: a shadow needs a known colour to be darker
-- than and the world is not one. ns.UI.NumberFont makes that trade at every
-- size and is deliberately not used here for that reason.
--
-- What that leaves is a hard minimum. An outline costs a pixel on every stroke,
-- and below ns.UI.OutlineFloor a 3 and an 8 stop being different shapes. Both
-- sizes below sit at the floor rather than near it, and the harness reads the
-- floor from UI/Text.lua rather than carrying its own copy of the number.
--
-- Both of these were under it at first, 11 on a row and 12 on a header, and the
-- report from the client was that the meter was not sharp. It was not soft. It
-- was closed up.
local ROW_TEXT = 14
local HEADER_TEXT = 14

local REFRESH = 0.2

-- The most rows either pane will ever draw, which is what the setting is
-- clamped to here as well as in Meter/Feature.lua: a pane is built to the
-- setting and a number from outside the panel must not build a pane taller than
-- the meter is allowed to be. A row that has been built is kept, because a
-- frame cannot be destroyed on this client and a pool that shrank with the
-- slider would leak a row every time it went back up.
local MAX_ROWS = 10

-- How faint a bar is, as a fraction, out of the whole percent the setting
-- holds. Low enough to read the world through and high enough to tell four
-- classes apart at a glance, which is the whole job.
--
-- It was a constant here, and the argument for the number it was set to still
-- stands and is now the default rather than the only answer. It was 0.32 first,
-- and 0.32 is a wash rather than a tint: the top row's bar is the full width of
-- the pane by definition, so whatever this number is, the number one player is
-- a solid rectangle of class colour across the meter every tick, and at a third
-- alpha that rectangle is the brightest thing on that part of the screen. At
-- 0.15 the rank still reads at a glance, because a bar is read against the bars
-- beside it and not against the world behind it, and the world behind it comes
-- through.
--
-- What made it a setting is the half of that the addon cannot see. The right
-- alpha depends on what is behind the meter, and what is behind the meter is
-- the zone: 15 over a night time crypt floor is the tint this was drawn for and
-- 15 over Tanaris at noon is nothing at all. No number this file picks is right
-- on both, and a player looking at one of them can tell in a second.
--
-- Called from the two places a bar's colour is written, never from a tick:
-- BuildRow runs once per row and PaintRow's write sits behind its class guard.
local function BarAlpha()
	return ns.db.meterBarAlpha / 100
end

local DIM = { 0.56, 0.56, 0.62 }
local WHITE = { 0.87, 0.87, 0.91 }
local WARN = { 0.94, 0.42, 0.35 }
local GREY = { 0.50, 0.50, 0.50 }

local frame, damage, threat, place
local built = false

-- The frame every event and the tick hang off, and the tick itself. Declared
-- here rather than at the foot of the file because MeterWindow.Apply is what
-- arms and stops the tick, and it is written above where they are made.
local events, tick

-- One pixel of the design, in the units the frame is drawn in. Exactly 1 once
-- ns.UI.Adopt has taken the frame onto the grid, which is the case on both
-- target clients, and a fraction on a client that refuses to take a frame off
-- its parent's scale. Every number above is multiplied by it, so the fallback
-- is the same layout drawn on fractional units rather than a layout at the
-- wrong size. Read once, after the adoption and before anything is built:
-- ns.UI.Rezoom keeps a frame on the grid, so this cannot move under a zoom
-- change.
local unit = 1

--------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------

local function ClassColor(class)
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if not color then
		return GREY[1], GREY[2], GREY[3]
	end
	return color.r, color.g, color.b
end

-- One row: the bar behind it, the icon, the name and the number. Nothing is
-- anchored to anything but the row itself, so a row can be moved by moving one
-- frame and the four regions come with it.
local function BuildRow(pane, index)
	local row = CreateFrame("Frame", nil, pane)
	row:SetSize(pane:GetWidth(), ROW * unit)
	row:SetPoint("TOPLEFT", pane, "TOPLEFT", 0,
		-(HEADER + RULE + (index - 1) * (ROW + ROW_GAP)) * unit)

	row.bar = ns.Fill(row, "BACKGROUND", 0.5, 0.5, 0.5, BarAlpha())
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetHeight(ROW * unit)
	row.bar:SetWidth(unit)

	row.icon = ns.UI.Icon(row, "ARTWORK")
	row.icon:SetSize(ICON * unit, ICON * unit)
	row.icon:SetPoint("LEFT", row, "LEFT", INSET * unit, 0)

	row.name = ns.UI.Label(row, ROW_TEXT, WHITE, "LEFT", ns.UI.OUTLINE)
	row.name:SetPoint("LEFT", row, "LEFT", (INSET + ICON + GUTTER) * unit, 0)

	row.value = ns.UI.Label(row, ROW_TEXT, WHITE, "RIGHT", ns.UI.OUTLINE)
	row.value:SetPoint("RIGHT", row, "RIGHT", -INSET * unit, 0)

	-- The name gives way to the number, not the other way round. A truncated
	-- name is still the right player; a truncated number is a lie.
	row.name:SetPoint("RIGHT", row.value, "LEFT", -GUTTER * unit, 0)

	-- Whether this row's number is a percentage. The threat pane's are, the
	-- damage pane's are not, and it is the one difference between the two kinds
	-- of row, so it is a flag rather than a second painter.
	row.percent = pane.percent

	row:Hide()
	return row
end

-- A pane is a header, a hairline under it, and a column of rows.
local function BuildPane(clickable, percent)
	local pane = CreateFrame("Frame", nil, frame)
	pane.percent = percent and true or false
	pane:SetSize(1, 1) -- both are set from the settings in MeterWindow.Apply

	pane.left = ns.UI.Label(pane, HEADER_TEXT, DIM, "LEFT", ns.UI.OUTLINE)
	pane.left:SetPoint("TOPLEFT", pane, "TOPLEFT", INSET * unit, -INSET * unit)

	pane.right = ns.UI.Label(pane, HEADER_TEXT, DIM, "RIGHT", ns.UI.OUTLINE)
	pane.right:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -INSET * unit, -INSET * unit)

	pane.rule = ns.Fill(pane, "ARTWORK", 0.5, 0.5, 0.55, 0.35)
	pane.rule:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -HEADER * unit)
	pane.rule:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -HEADER * unit)
	pane.rule:SetHeight(RULE * unit)

	if clickable then
		-- Only the header strip, and only this pane's. See the note at the top
		-- about what a mouse enabled frame costs.
		--
		-- Two clicks on the one strip, and which of them got the left button is
		-- worth arguing. The meter is where you are standing when you wonder
		-- what your own damage is made of, so the left button opens the
		-- breakdown, which is the answer, and the right button keeps the swap
		-- between damage and healing, which is a thing you set once an evening.
		local button = CreateFrame("Button", nil, pane)
		button:SetPoint("TOPLEFT")
		button:SetPoint("TOPRIGHT")
		button:SetHeight(HEADER * unit)
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnClick", function(_, click)
			if click == "RightButton" then
				MeterWindow.Toggle()
				return
			end
			ns.BreakdownWindow.Toggle()
		end)
		ns.Tip.Hang(button, function()
			return {
				kind = "note",
				title = "WarriorKit meters",
				lines = { "One row per player, as long as their share of the top row." },
			}
		end)
		pane.button = button
	end

	-- No rows yet. SizePane builds as many as the setting asks for, which ships
	-- at six of the ten this pane may ever draw.
	pane.rows = {}
	pane.visible = 0
	return pane
end

-- How wide and how tall this pane is now, and which of its rows are in play.
-- The rows past the setting are hidden here rather than left to the painter,
-- because the painter only ever walks as far as `visible` and would never
-- reach them again.
local function SizePane(pane, width, rows)
	pane:SetSize(width * unit, (HEADER + RULE + rows * (ROW + ROW_GAP) - ROW_GAP) * unit)
	pane.visible = rows
	-- The rows the setting asks for, built the first time it asks for that many.
	-- Ten were built per pane at login and the slider ships at six, so eight of
	-- the twenty were frames nothing would draw. A row that has been built
	-- is kept: a frame cannot be destroyed on this client, so a pool that shrank
	-- would leak a row every time the slider went back up.
	for index = #pane.rows + 1, rows do
		pane.rows[index] = BuildRow(pane, index)
	end
	for index = 1, #pane.rows do
		local row = pane.rows[index]
		row:SetWidth(width * unit)
		if index > rows then
			row.filled = false
			row:Hide()
		end
	end
end

-- Forget what every row on this pane last painted its colour at.
--
-- A row writes its bar and its name only when the player on it changes class,
-- which is the guard that turns thirty writes a second into none. The alpha is
-- not the class. Moved on the panel, it would sit behind that guard unread
-- until somebody on the meter changed class, which is never, and the slider
-- would look broken to anyone who was not in a fight while they dragged it. So
-- the guard is cleared here, where a setting changes, and the next tick paints
-- what the setting now says.
local function Forget(pane)
	if not pane then
		return
	end
	for index = 1, #pane.rows do
		pane.rows[index].shownClass = nil
	end
end

--------------------------------------------------------------------------
-- Layout
--
-- Everything a setting can move. Called at login and again whenever a number
-- in the panel changes, never from a tick.
--------------------------------------------------------------------------

-- The frame, the two panes and everything on them, made the first time the
-- meters are switched on.
--
-- They were made at login whatever the switch said: twenty rows over two panes,
-- four regions on each, and a ticker armed at five times a second whose first
-- line is a test for a setting that was off. The meters ship on, so most
-- sessions pay this either way; a session that has turned them off pays nothing
-- at all now, and neither does the threat pane on a character who has never
-- asked for it.
local function Build()
	frame = CreateFrame("Frame", FRAME_NAME, UIParent)
	ns.UI.Adopt(frame, ns.db.meterZoom)
	unit = ns.UI.Unit(frame)
	-- This was the one of the twelve that did not round the offsets it saved,
	-- and nothing said so because the other eleven agreed with each other rather
	-- than with a rule written down anywhere. It rounds now, along with all of
	-- them.
	place = ns.UI.Placeable(frame, {
		name = "WarriorKit meters",
		moved = function(anchor)
			ns.db.meterPoint = anchor
		end,
	})

	damage = BuildPane(true)
	damage:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	built = true
end

-- The threat pane, which is a switch of its own under the switch above. A
-- character who never ticks it never has a second pane.
local function BuildThreat()
	if threat then
		return
	end
	threat = BuildPane(false, true)
	threat:SetPoint("TOPLEFT", damage, "TOPRIGHT", PANE_GAP, 0)
end

-- The tick, armed by the switch going on and stopped by it going off.
--
-- It was armed at login and ran five times a second for the life of a session
-- with the meters off, reading a setting to find out it had nothing to do.
-- ns.UI.Ticker refuses a second running tick of one name on one frame, so the
-- tick is kept here and started again rather than made again.
local function Beat()
	if ns.db.meter then
		if not tick then
			tick = ns.UI.Ticker(ns.UI.Forever, REFRESH, "meter", MeterWindow.Update)
		elseif not tick:Running() then
			tick:Start()
		end
	elseif tick then
		tick:Stop()
	end
end

function MeterWindow.Apply()
	if not built then
		if not ns.db.meter then
			return
		end
		Build()
	end

	local db = ns.db
	local point = db.meterPoint
	frame:ClearAllPoints()
	frame:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	ns.UI.Rezoom(frame, db.meterZoom)

	-- Clamped here rather than trusted, because the panes are built to this
	-- number now: a setting from outside the panel that asked for forty rows
	-- would build forty frames a pane.
	local width = db.meterWidth
	local rows = math.max(1, math.min(db.meterRows, MAX_ROWS))
	local height = (HEADER + RULE + rows * (ROW + ROW_GAP) - ROW_GAP) * unit

	SizePane(damage, width, rows)
	Forget(damage)
	Forget(threat)

	local total = width
	if db.meterThreat then
		BuildThreat()
		SizePane(threat, width, rows)
		threat:Show()
		total = width * 2 + PANE_GAP
	elseif threat then
		threat:Hide()
		threat.visible = 0
	end

	frame:SetSize(total * unit, height)

	Beat()
	MeterWindow.Lock()
	MeterWindow.Show()
end

-- Locked is the normal state and unlocked is the two minutes you spend putting
-- it somewhere. Unlocked draws an outline and a name, because a frame with a
-- clear background and no rows in it is otherwise a piece of empty screen you
-- have to find by memory.
function MeterWindow.Lock()
	if not frame then
		return
	end
	place:Lock(not ns.db.locked)
end

function MeterWindow.Show()
	if not built then
		-- The switch just went on and this is the first thing it calls. Apply
		-- builds the panes, sizes them, arms the tick and ends by calling this
		-- again with something to show.
		if ns.db.meter then
			MeterWindow.Apply()
		end
		return
	end
	if ns.db.meter then
		frame:Show()
	else
		frame:Hide()
	end
end

function MeterWindow.Toggle()
	ns.db.meterMode = (ns.db.meterMode == "hps") and "dps" or "hps"
	MeterWindow.Update()
	ns.Options.Refresh()
end

function MeterWindow.Reset()
	ns.db.meterPoint = ns.DefaultCopy("meterPoint")
	MeterWindow.Apply()
end

--------------------------------------------------------------------------
-- Painting
--
-- Everything below runs five times a second, so every write is guarded on what
-- is already on the widget and nothing allocates. A SetText costs a measure and
-- a relayout whether or not the string changed; a comparison costs a
-- comparison.
--------------------------------------------------------------------------

-- Thousands from about ten thousand up, and whole numbers below it. A meter
-- that says 8.4k where it could say 8412 has rounded away the digit you were
-- comparing two rows on.
--
-- Every caller reaches this from inside a guard on the number, never on the
-- string it makes. A formatted string is an allocation, and a row whose number
-- has not moved since the last tick must not build one to discover that.
local function Short(value)
	if value >= 10000 then
		return ("%.1fk"):format(value / 1000)
	end
	return ("%d"):format(value) -- allocates: every caller compares the number against the one the row is showing before it asks for the words, as the note above says
end

local function Blank(pane, from)
	for index = from, pane.visible do
		local row = pane.rows[index]
		if row.filled then
			row.filled = false
			row:Hide()
		end
	end
end

-- One row, from whoever it is to what they did. Every field carries what it
-- last showed, which is what turns thirty writes a second per row into none.
--
-- The value arrives as a number rather than as text for the same reason: it is
-- compared as a number and only turned into a string on the tick it changes.
local function PaintRow(row, guid, class, label, value, color)
	if not row.filled then
		row.filled = true
		row:Show()
	end

	if row.shownGuid ~= guid then
		row.shownGuid = guid
		local texture, left, right, top, bottom = ns.Unit.Spec.Icon(guid, class)
		row.icon:SetTexture(texture)
		row.icon:SetTexCoord(left, right, top, bottom)
	end

	if row.shownClass ~= class then
		row.shownClass = class
		local r, g, b = ClassColor(class)
		row.bar:SetColorTexture(r, g, b, BarAlpha())
		row.name:SetTextColor(r, g, b)
	end

	if row.shownLabel ~= label then
		row.shownLabel = label
		row.name:SetText(label)
	end

	if row.shownValue ~= value then
		row.shownValue = value
		row.value:SetText(row.percent and (value .. "%") or Short(value))
	end

	if row.shownColor ~= color then
		row.shownColor = color
		row.value:SetTextColor(color[1], color[2], color[3])
	end
end

local function PaintBar(row, share, width)
	-- Clamped, because the threat percentage is the client's and nothing here
	-- promises it stops at 100. A share over one would draw a bar out of the
	-- pane and across whatever is beside it.
	if share > 1 then
		share = 1
	end
	local drawn = math.floor(share * width + 0.5) * unit
	if drawn < unit then
		drawn = unit
	end
	if row.shownWidth ~= drawn then
		row.shownWidth = drawn
		row.bar:SetWidth(drawn)
	end
end

local function SetLeft(pane, text)
	if pane.shownLeft ~= text then
		pane.shownLeft = text
		pane.left:SetText(text)
	end
end

-- Split from the text, because the threat header keeps the same words while it
-- changes colour: "held" in grey is a different state from "held" in red and
-- one guard could not say both.
local function SetRight(pane, text, color)
	if pane.shownRight ~= text then
		pane.shownRight = text
		pane.right:SetText(text)
	end
	if pane.shownColor ~= color then
		pane.shownColor = color
		pane.right:SetTextColor(color[1], color[2], color[3])
	end
end

local function PaintDamage()
	local mode = ns.db.meterMode
	local rows = ns.Meter.Rank(mode)
	local width = ns.db.meterWidth

	SetLeft(damage, (mode == "hps") and "HPS" or "DPS")

	-- Both halves of the header line are guarded as numbers, so the string
	-- itself is built on the tick the fight moves and not five times a second
	-- while it does not.
	local total = math.floor(ns.Meter.Total(mode) + 0.5)
	local seconds = math.floor(ns.Meter.Elapsed())
	if damage.shownTotal ~= total or damage.shownSeconds ~= seconds then
		damage.shownTotal, damage.shownSeconds = total, seconds
		SetRight(damage, Short(total) .. "  " .. seconds .. "s", DIM)
	end

	local top = (rows[1] and ns.Meter.Rate(rows[1], mode)) or 0
	local shown = 0
	for index = 1, damage.visible do
		local slot = rows[index]
		if slot then
			shown = index
			local row = damage.rows[index]
			local name, class = ns.Unit.Roster.Who(slot.guid)
			local rate = ns.Meter.Rate(slot, mode)
			PaintRow(row, slot.guid, class, name or "?", math.floor(rate + 0.5), WHITE)
			PaintBar(row, (top > 0) and (rate / top) or 0, width)
			ns.Unit.Spec.Request(slot.guid)
		end
	end
	Blank(damage, shown + 1)
end

local function PaintThreat()
	local width = ns.db.meterWidth

	SetLeft(threat, "Threat")

	-- Both of these leave by a different door from the one below, so what the
	-- header last showed has to be forgotten on the way out. Without this, a
	-- target that comes back with the same member converging at the same number
	-- of seconds would find the guard below already satisfied and the header
	-- would still be reading "no target" over a full list of rows.
	if not ns.MeterThreat.Ready() then
		threat.shownEta, threat.shownSoonest = nil, nil
		SetRight(threat, "no api", GREY)
		Blank(threat, 1)
		return
	end
	if not ns.MeterThreat.Watching() then
		threat.shownEta, threat.shownSoonest = nil, nil
		SetRight(threat, "no target", DIM)
		Blank(threat, 1)
		return
	end

	-- Only the projection is guarded on its own numbers, because only the
	-- projection has to build a string. "held" is a constant, so it goes
	-- straight to SetRight and that guard makes it free.
	--
	-- Written this way round on purpose. Guarding both branches on the eta and
	-- the member meant the quiet state, no eta and nobody converging, was
	-- indistinguishable from the state the pane starts in with nothing written
	-- to it at all, and the header stayed empty until somebody first pulled
	-- ahead. A guard whose "nothing changed" case matches "nothing has happened
	-- yet" is a guard that skips the first write.
	local soonest, when = ns.MeterThreat.Soonest()
	if not soonest then
		threat.shownEta, threat.shownSoonest = nil, nil
		SetRight(threat, "held", DIM)
	else
		local eta = math.floor(when + 0.5)
		if threat.shownEta ~= eta or threat.shownSoonest ~= soonest.guid then
			threat.shownEta, threat.shownSoonest = eta, soonest.guid
			local name = ns.Unit.Roster.Who(soonest.guid)
			SetRight(threat, (name or "?") .. " in " .. eta .. "s", WARN)
		end
	end

	local rows = ns.MeterThreat.Rank()
	local shown = 0
	for index = 1, threat.visible do
		local slot = rows[index]
		if slot then
			shown = index
			local row = threat.rows[index]
			local name, class = ns.Unit.Roster.Who(slot.guid)
			local color = slot.eta and WARN or (slot.tanking and WHITE or DIM)
			PaintRow(row, slot.guid, class, name or "?", math.floor(slot.pct + 0.5), color)
			PaintBar(row, slot.pct / 100, width)
			ns.Unit.Spec.Request(slot.guid)
		end
	end
	Blank(threat, shown + 1)
end

-- How many screen pixels of art a row icon draws at the current zoom, and
-- whether that is one stored texel per pixel. Read out of ns.UI.IconSizes
-- rather than typed, so changing the crop in UI/Draw.lua moves this answer
-- instead of leaving a stale number in a panel note.
function MeterWindow.IconAdvice(zoom)
	zoom = zoom or ns.db.meterZoom or 1
	local drawn = ICON * zoom
	for _, exact in ipairs(ns.UI.IconSizes()) do
		if exact == drawn then
			return drawn, true
		end
	end
	return drawn, false
end

-- The two panes, for scripts/harness.lua and for a macro. Handed out rather
-- than kept private because the harness has to measure what was drawn, and
-- measuring it any other way would mean this file publishing its row pool.
function MeterWindow.Pane(which)
	return (which == "threat") and threat or damage
end

function MeterWindow.Update()
	if not built or not ns.db.meter or not frame:IsShown() then
		return
	end
	ns.MeterThreat.Update()
	PaintDamage()
	if ns.db.meterThreat then
		PaintThreat()
	end
end

--------------------------------------------------------------------------

events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	-- Apply is the only way in. It builds nothing while the meters are off, and
	-- the switch going on is what calls it next.
	MeterWindow.Apply()
end)

-- A resolution change moves every size in this file at once, the same way it
-- moves the enemy bars.
ns.UI.OnRescale(function()
	MeterWindow.Apply()
end)
