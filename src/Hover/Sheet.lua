local ADDON, ns = ...

local Sheet = {}
ns.HoverSheet = Sheet

--------------------------------------------------------------------------
-- The list of what you bound, on screen
--
-- A mouseover binding is invisible. There is no icon, no cooldown swipe and no
-- keybind text in a corner, which is the whole reason Clique users forget half
-- of what they set up and the reason a second monitor with the options window
-- open is not an answer. This is the list, drawn over the world: one line per
-- binding, the key on the left, the spell's own icon and name beside it, tinted
-- by who the key is allowed to land on.
--
-- Red is an enemy, green is a friend, grey is anything. Those are the three
-- colours the addon already uses for a number that went the wrong way, a tick
-- and a disabled control, borrowed rather than added, because a fourth palette
-- entry for a thing that is already said three times is how a palette stops
-- meaning anything.
--
-- No ticker. What is bound changes when you bind something, so the row is
-- written on a change and never again. That is also why this file names no
-- function in check.sh's HOT list: there is no path here an OnUpdate reaches.
--------------------------------------------------------------------------

local FRAME_NAME = "WarriorKitHoverSheet"

-- Design pixels, multiplied by the frame's unit. The row is the icon plus a
-- pixel above and below, so a column of them reads as a list rather than as a
-- strip of art.
local ICON, ROW, PAD, GAP = 14, 16, 5, 6

local frame, place, ground
local rows = {}
local unit = 1
local count = 0
local built

-- One line of the sheet. Built at the ceiling at login and shown only while the
-- list is that long, for the reason UnitFrames/Panel.lua builds its debuff rows
-- that way: a row that appears when you bind a key has to already exist.
local function BuildRow(index)
	local row = CreateFrame("Frame", nil, frame)
	row:SetHeight(ROW * unit)

	row.key = ns.UI.Label(row, ns.UI.OutlineFloor(), ns.UI.Color.text,
		"LEFT", ns.UI.OUTLINE)
	row.key:SetPoint("LEFT")

	row.art = ns.UI.Icon(row, "ARTWORK")
	row.art:SetSize(ICON * unit, ICON * unit)

	row.name = ns.UI.Label(row, ns.UI.OutlineFloor(), ns.UI.Color.text,
		"LEFT", ns.UI.OUTLINE)

	row:Hide()
	rows[index] = row
	return row
end

-- The widest key and the widest name, measured off the strings themselves.
--
-- Measured rather than guessed at a column width, because a key reads
-- CTRL-SHIFT-BUTTON4 or it reads F1 and a column sized for the first wastes
-- half the sheet for anybody whose keys are short. Two passes: write every
-- string, ask each one how wide it came out, then place them.
local function Columns(list)
	local keyWidth, nameWidth = 0, 0
	for index = 1, count do
		local row, bind = rows[index], list[index]
		row.key:SetText(bind.key)
		row.name:SetText(bind.name)
		keyWidth = math.max(keyWidth, row.key:GetStringWidth())
		nameWidth = math.max(nameWidth, row.name:GetStringWidth())
	end
	return ns.UI.Round(frame, keyWidth), ns.UI.Round(frame, nameWidth)
end

local function Place(list, keyWidth, nameWidth)
	local C = ns.UI.Color
	for index = 1, count do
		local row, bind = rows[index], list[index]
		local who = ns.Hover.Who(bind.who)
		local tone = C[who.tone]

		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD * unit,
			-(PAD + (index - 1) * ROW) * unit)
		row:SetHeight(ROW * unit)
		row:SetWidth(keyWidth + GAP * unit + ICON * unit + GAP * unit + nameWidth)

		row.key:SetWidth(keyWidth)
		row.key:SetTextColor(tone[1], tone[2], tone[3])

		row.art:ClearAllPoints()
		row.art:SetPoint("LEFT", row, "LEFT", keyWidth + GAP * unit, 0)
		row.art:SetSize(ICON * unit, ICON * unit)
		row.art:SetTexture(bind.icon)
		row.art:SetShown(bind.icon and true or false)

		row.name:ClearAllPoints()
		row.name:SetPoint("LEFT", row.art, "RIGHT", GAP * unit, 0)
		row.name:SetWidth(nameWidth)
		row:Show()
	end
	for index = count + 1, ns.Hover.MAX do
		rows[index]:Hide()
	end
end

-- Whether the sheet has anything to say. Off with the part off, off with the
-- setting off, and off with nothing bound, because an empty box floating over
-- the world is furniture that teaches nobody anything.
local function Wanted()
	return ns.db.hover and ns.db.hoverSheet and #ns.Hover.List() > 0
end

function Sheet.Rebuild()
	if not built then
		return
	end

	local list = ns.Hover.List()
	count = math.min(#list, ns.Hover.MAX)
	if not Wanted() then
		frame:Hide()
		return
	end

	local keyWidth, nameWidth = Columns(list)
	Place(list, keyWidth, nameWidth)

	frame:SetWidth(keyWidth + nameWidth + (GAP * 2 + ICON + PAD * 2) * unit)
	frame:SetHeight((count * ROW + PAD * 2) * unit)
	ground:SetAlpha((ns.db.hoverSheetAlpha or 0) / 100)
	frame:Show()
end

function Sheet.Apply()
	if not built then
		return
	end
	local point = ns.db.hoverSheetPoint
	frame:ClearAllPoints()
	frame:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	ns.UI.Rezoom(frame, ns.db.hoverSheetZoom)
	unit = ns.UI.Unit(frame)
	Sheet.Lock()
	Sheet.Rebuild()
end

-- Mouse only while unlocked, which is the rule every draggable frame in the
-- addon follows: a mouse enabled frame swallows every button that lands on it,
-- including the right button drag that turns the camera.
function Sheet.Lock()
	if not built then
		return
	end
	place:Lock(not ns.db.locked)
end

function Sheet.Reset()
	ns.db.hoverSheetPoint = ns.DefaultCopy("hoverSheetPoint")
	ns.db.hoverSheetZoom = ns.DefaultCopy("hoverSheetZoom")
	ns.db.hoverSheetAlpha = ns.DefaultCopy("hoverSheetAlpha")
	Sheet.Apply()
end

-- One row, for scripts/harness.lua, handed out for the reason Cooldowns/Row.lua
-- hands its own out: the harness has to measure what was drawn and there is no
-- honest way to do that from outside.
function Sheet.Row(index)
	return rows[index]
end

function Sheet.Shown()
	return frame ~= nil and frame:IsShown() and count or 0
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	frame = CreateFrame("Frame", FRAME_NAME, UIParent)
	ns.UI.Adopt(frame, ns.db.hoverSheetZoom)
	unit = ns.UI.Unit(frame)
	place = ns.UI.Placeable(frame, {
		name = "WarriorKit mouseover keys",
		moved = function(anchor)
			ns.db.hoverSheetPoint = anchor
			Sheet.Apply()
		end,
	})

	ground = ns.Fill(frame, "BACKGROUND", ns.UI.Color.window[1],
		ns.UI.Color.window[2], ns.UI.Color.window[3], 1)
	ground:SetAllPoints()

	for index = 1, ns.Hover.MAX do
		BuildRow(index)
	end

	built = true
	Sheet.Apply()
end)
