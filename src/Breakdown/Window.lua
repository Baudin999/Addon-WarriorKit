local ADDON, ns = ...

local Window = {}
ns.BreakdownWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The table
--
-- One row per ability, biggest first, in a window of its own.
--
-- It lived on a settings page first, and the argument for that was that this is
-- read between sessions rather than during a pull, so it did not need a frame
-- to place or an anchor to save. That argument was about where the numbers are
-- kept. It said nothing about how you get to them, and the way you got to them
-- was six clicks into a settings tree, which is where a readout goes to be
-- forgotten. The meter is the thing you are looking at when the question occurs
-- to you, so the meter is what opens this, and a window is what a thing opened
-- from the world has to be.
--
-- It costs nothing when it is shut. There is no frame until the first open, no
-- ticker at all, and the only repaint that is not a click is the one when you
-- drop combat with the window already up.
--
-- Three lines per row, because the numbers only mean something together. The
-- name and the damage are what you scan; the hit count and the crit rate say
-- whether the sample is worth anything yet; the miss breakdown is the line a
-- warrior actually acts on, because dodge is about where you were standing.
--
-- The bar behind a row is that ability's share of your damage, drawn the way
-- Meter/Window.lua draws its share bars and for the same reason: a column of
-- percentages is a column you have to read, and a bar is one you can rank at a
-- glance without reading anything.
--------------------------------------------------------------------------

-- The most rows the pool holds. Past this an ability is counted and simply not
-- drawn, which is a readout decision rather than a storage one: forty rows into
-- the ranking every share is a rounding error and the question has stopped
-- being "what am I doing" and started being "what have I ever done".
local MAX_ROWS = 40

-- How many are on screen before the list scrolls. It is what sets the window's
-- height, so it is the one number here you would change to make the window a
-- different shape.
local ROWS_DRAWN = 10

local WIDTH = 560

-- The row. 27 for the icon because that is the second entry in ns.UI.IconSizes
-- and the only size near this one where a stored texel lands on a whole pixel;
-- everything else follows from it. Seven above and seven below puts it in the
-- middle of a 41 unit row without landing an edge on a half pixel, which is
-- what centring an odd difference would do.
local ROW = 41
local ICON = 27
local ICON_TOP = 7
local INSET = 4
local TEXT_X = INSET + ICON + M.gutter

-- Three text lines, measured from the top of the row.
local LINE1, LINE2, LINE3 = 4, 17, 29

-- The two right hand columns, given fixed widths so they line up down the list
-- rather than each ending wherever its own digits ran out.
local DAMAGE_W = 62
local SHARE_W = 38

-- How solid the share bar is. The same argument as the meter's bar opacity and
-- a smaller number, because this sits on an opaque window rather than over the
-- world: on a dark surface a fifth of the accent is a tint you can rank rows by
-- and anything more is a block of colour with text on it.
local BAR = 0.20

-- The head of the window: the total, the sentence saying what has been counted,
-- and the row of controls under both.
local BIG = 17
local BAND_W = 140
local LABEL_W = 46
local HEAD_Y = M.pad
local CHIP_Y = HEAD_Y + BIG + M.rowGap
local RULE_Y = CHIP_Y + M.row + M.rowGap
local LIST_Y = RULE_Y + M.hairline + M.rowGap

local HEIGHT = M.title + LIST_Y + ROWS_DRAWN * ROW + M.footer

-- The band chip cycles through these, "every band" first. The four words after
-- it come from Breakdown.lua rather than being typed here, so this window and
-- the slash word cannot describe the same band differently.
local EVERY = "every band"

local window
local rows = {}
local view
local head, note, blank
local bandChip
local shown = 0
local width = 1

--------------------------------------------------------------------------

-- Thousands from ten thousand up, millions from a million. Below ten thousand
-- the digits are the point: an ability that has done 8,412 damage and one that
-- has done 8.4k are the same row, and the first one can be compared with the
-- row under it. A lifetime total goes past a million in a week of play, and
-- seven digits in the corner of a window is a number nobody reads.
local function Short(value)
	value = value or 0
	if value >= 1000000 then
		return ("%.2fm"):format(value / 1000000)
	end
	if value >= 10000 then
		return ("%.1fk"):format(value / 1000)
	end
	return ("%d"):format(value + 0.5)
end

local function Percent(fraction)
	if not fraction then
		return nil
	end
	return ("%d%%"):format(fraction * 100 + 0.5)
end

-- The picture on a row. A white swing has no spell id of its own and is filed
-- under zero, so it borrows the icon of spell 6603, which is where
-- Breakdown/Breakdown.lua takes its name from and where Feeds/Combat.lua takes
-- its swing icon from. One place decides what a melee swing looks like.
local MELEE_ICON = 6603

local function IconFor(key)
	if key == nil then
		return nil
	end
	if key == ns.Breakdown.MeleeKey() then
		key = MELEE_ICON
	end
	return ns.SpellTexture(key)
end

--------------------------------------------------------------------------
-- The three lines of one row
--------------------------------------------------------------------------

-- What landed, and how hard. Built only for a row that is being drawn, which is
-- at most forty of them and only while the window is open, so a formatted
-- string here costs nothing the way one on a ticker would.
local function Landed(row)
	local parts = ("%d hits"):format(row.landed)

	local crit = ns.Breakdown.CritRate(row)
	if crit then
		parts = parts .. ", " .. Percent(crit) .. " crit"
	end

	local average = ns.Breakdown.AverageHit(row)
	if average then
		parts = parts .. ", avg " .. Short(average)
	end

	-- The average crit, next to the average hit it is not. Keeping crit damage
	-- apart from the rest is the whole reason four counters are stored rather
	-- than two, and until this line the second of them was computed and never
	-- shown anywhere.
	local critAverage = ns.Breakdown.AverageCrit(row)
	if critAverage then
		parts = parts .. ", crits for " .. Short(critAverage)
	end

	if row.max > 0 then
		parts = parts .. ", best " .. Short(row.max)
	end
	return parts
end

-- What stopped it, and what you pressed.
--
-- The miss types are named one by one rather than summed into a single figure.
-- That is the whole reason the store keeps them apart: a dodge says you were in
-- front of it and a parry says something about the target, and one pooled
-- "missed" number teaches you neither. Only the ones that actually happened are
-- drawn, so a spell nothing has ever dodged does not carry a zero.
local MISS_WORDS = {
	MISS = "missed", DODGE = "dodged", PARRY = "parried", BLOCK = "blocked",
	ABSORB = "absorbed", IMMUNE = "immune", RESIST = "resisted",
	EVADE = "evaded", DEFLECT = "deflected", REFLECT = "reflected",
}

-- A stable order, because pairs over the miss table would reorder the line
-- every time the window refreshed.
local MISS_ORDER = {
	"DODGE", "PARRY", "MISS", "BLOCK", "RESIST", "ABSORB", "IMMUNE",
	"EVADE", "DEFLECT", "REFLECT",
}

local function Stopped(row)
	local parts

	if row.casts > 0 then
		parts = ("%d casts"):format(row.casts)
	end

	local missed = ns.Breakdown.MissRate(row)
	if missed and row.misses > 0 then
		local line = Percent(missed) .. " stopped"
		local detail
		for _, kind in ipairs(MISS_ORDER) do
			local rate = ns.Breakdown.MissRateOf(row, kind)
			if rate then
				local word = ("%s %s"):format(Percent(rate), MISS_WORDS[kind] or kind:lower())
				detail = detail and (detail .. ", " .. word) or word
			end
		end
		if detail then
			line = line .. ": " .. detail
		end
		parts = parts and (parts .. ", " .. line) or line
	end

	return parts or ""
end

--------------------------------------------------------------------------
-- The chips
--
-- A push button that knows whether it is the one in force. The selected shade
-- and the accent bar under it are the tab strip's, on purpose: a control that
-- picks one of a set should look the same everywhere in the addon, and a chip
-- is a tab that did not get a page of its own.
--------------------------------------------------------------------------

local function PaintChip(chip)
	if chip.active then
		UI.Tint(chip.bg, C.selected)
		chip.text:SetTextColor(C.heading[1], C.heading[2], C.heading[3])
	elseif chip.hovered then
		UI.Tint(chip.bg, C.hover)
		chip.text:SetTextColor(C.text[1], C.text[2], C.text[3])
	else
		UI.Tint(chip.bg, C.control)
		chip.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
	end
	chip.mark:SetShown(chip.active and true or false)
end

local function Chip(parent, label, chipWidth, onClick)
	local chip = UI.Button(parent, {
		label = label,
		width = chipWidth,
		height = M.row,
		onClick = onClick,
	})
	chip.mark = ns.Fill(chip, "OVERLAY", C.accent[1], C.accent[2], C.accent[3], 1)
	chip.mark:SetPoint("BOTTOMLEFT")
	chip.mark:SetPoint("BOTTOMRIGHT")
	chip.mark:SetHeight(2)

	-- UI.Button paints its own hover, and a chip has three states rather than
	-- two, so both scripts are replaced rather than added to.
	chip:SetScript("OnEnter", function(self)
		self.hovered = true
		PaintChip(self)
	end)
	chip:SetScript("OnLeave", function(self)
		self.hovered = nil
		PaintChip(self)
	end)

	PaintChip(chip)
	return chip
end

--------------------------------------------------------------------------
-- The band the window is reading
--------------------------------------------------------------------------

local function BandWord()
	local band = ns.Breakdown.Band()
	return band and ns.Breakdown.BandWord(band) or EVERY
end

-- The next band round, with zero for all four added together. A cycle rather
-- than a dropdown because there are five of them and every one is one click
-- away either direction of the list you would have opened.
local function NextBand()
	local bands = ns.Breakdown.Bands()
	local current = ns.db.breakdownBand or 0
	if current <= 0 then
		return bands[1]
	end
	for index = 1, #bands do
		if bands[index] == current then
			return bands[index + 1] or 0
		end
	end
	return 0
end

--------------------------------------------------------------------------
-- One row
--------------------------------------------------------------------------

local function BuildRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW)

	row.bar = ns.Fill(row, "BACKGROUND", C.accent[1], C.accent[2], C.accent[3], BAR)
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetWidth(1)

	-- The hairline under a row, not between rows: a line drawn on the row it
	-- belongs to is one that disappears with it when the list gets shorter.
	row.rule = ns.Fill(row, "ARTWORK", C.hairline[1], C.hairline[2], C.hairline[3], 1)
	row.rule:SetPoint("BOTTOMLEFT")
	row.rule:SetPoint("BOTTOMRIGHT")
	row.rule:SetHeight(M.hairline)

	row.glow = ns.Fill(row, "BACKGROUND", C.hover[1], C.hover[2], C.hover[3], 0.5)
	row.glow:SetAllPoints()
	row.glow:Hide()

	row.icon = UI.Icon(row, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", INSET, -ICON_TOP)

	row.name = UI.Label(row, M.font, C.text, "LEFT", UI.FLAT)
	row.name:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_X, -LINE1)

	row.damage = UI.Label(row, M.font, C.text, "RIGHT", UI.FLAT)
	row.damage:SetPoint("TOPRIGHT", row, "TOPRIGHT", -INSET, -LINE1)
	row.damage:SetWidth(DAMAGE_W)

	row.share = UI.Label(row, M.font, C.heading, "RIGHT", UI.FLAT)
	row.share:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(INSET + DAMAGE_W + M.gutter), -LINE1)
	row.share:SetWidth(SHARE_W)

	row.landed = UI.Label(row, M.small, C.dim, "LEFT", UI.FLAT)
	row.landed:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_X, -LINE2)

	row.stopped = UI.Label(row, M.small, C.quiet, "LEFT", UI.FLAT)
	row.stopped:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_X, -LINE3)

	-- The name gives way to the number on the first line, the same rule
	-- Meter/Window.lua and UI/Feed.lua both follow: a clipped ability is still
	-- recognisable and a clipped number is a lie.
	row.name:SetPoint("RIGHT", row.share, "LEFT", -M.gutter, 0)
	row.landed:SetPoint("RIGHT", row, "RIGHT", -INSET, 0)
	row.stopped:SetPoint("RIGHT", row, "RIGHT", -INSET, 0)

	row:SetScript("OnEnter", function(self)
		self.glow:Show()
	end)
	row:SetScript("OnLeave", function(self)
		self.glow:Hide()
	end)

	row:Hide()
	return row
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function Build()
	window = UI.Window({
		name = "WarriorKitBreakdown",
		title = "Breakdown",
		width = WIDTH,
		height = HEIGHT,
	})
	ns.Remember(window)

	local body = window.content

	-- What the whole table adds up to, which is the one number the rows do not
	-- carry between them.
	head = UI.Label(body, BIG, C.text, "LEFT", UI.FLAT)
	head:SetPoint("TOPLEFT", M.pad, -HEAD_Y)

	-- Bounded on the left by the total rather than left to grow across it. The
	-- sentence gets a clause on the end when the store has started refusing
	-- abilities, and a right anchored string with nothing to its left would run
	-- under the number instead of clipping.
	note = UI.Label(body, M.small, C.dim, "RIGHT", UI.FLAT)
	note:SetPoint("TOPRIGHT", -M.pad, -(HEAD_Y + math.floor((BIG - M.small) / 2)))
	note:SetPoint("LEFT", head, "RIGHT", M.gutter, 0)

	-- The one control on the row, at the left margin where the ranking chips
	-- were. There were three of those, damage, casts and hits, and a table with
	-- one ranking does not need a control saying which one. Ranked by press
	-- count Battle Shout sits above Mortal Strike, which is not a view of your
	-- damage that anybody was asking for.
	local bandLabel = UI.Label(body, M.small, C.quiet, "LEFT", UI.FLAT)
	bandLabel:SetPoint("TOPLEFT", M.pad, -(CHIP_Y + math.floor((M.row - M.small) / 2)))
	bandLabel:SetWidth(LABEL_W)
	bandLabel:SetText("targets")

	bandChip = Chip(body, EVERY, BAND_W, function()
		ns.db.breakdownBand = NextBand()
		Window.Paint()
		ns.Options.Refresh()
	end)
	bandChip:SetPoint("TOPLEFT", M.pad + LABEL_W + M.gutter, -CHIP_Y)

	local rule = UI.Rule(body, C.hairline)
	rule:SetPoint("TOPLEFT", M.pad, -RULE_Y)
	rule:SetPoint("TOPRIGHT", -M.pad, -RULE_Y)

	-- The list. Forty rows in the pool and ten on screen, so a character with
	-- more abilities than fit scrolls rather than losing the tail.
	view = UI.ScrollView(body)
	view.frame:SetPoint("TOPLEFT", M.pad, -LIST_Y)
	width = view:Resize(WIDTH - M.pad * 2, ROWS_DRAWN * ROW)

	for index = 1, MAX_ROWS do
		rows[index] = BuildRow(view.canvas, index)
		rows[index]:SetWidth(width)
	end

	blank = UI.Label(view.canvas, M.font, C.quiet, "LEFT", UI.FLAT)
	blank:SetPoint("TOPLEFT", INSET, -LINE1)
	blank:SetPoint("RIGHT", view.canvas, "RIGHT", -INSET, 0)

	local hint = UI.Label(window.footer, M.small, C.quiet, "LEFT", UI.FLAT)
	hint:SetPoint("LEFT")
	hint:SetText("Escape closes this. /wk breakdown prints the same table to chat.")

	local close = UI.Button(window.footer, { label = "close", width = 90, height = M.row,
		onClick = function() Window.Close() end })
	close:SetPoint("RIGHT")

	UI.OnRescale(function()
		if window then
			UI.Rezoom(window.frame, UI.WindowZoom())
			window.zoom = UI.WindowZoom()
		end
	end)
end

--------------------------------------------------------------------------

-- Everything a setting or a fight can move. Not on a ticker: this runs when the
-- window opens, when a chip on it is clicked, and when you drop combat with it
-- already up.
function Window.Paint()
	if #rows == 0 then
		return false
	end

	local ranked, total = ns.Breakdown.Rank(ns.Breakdown.Band())
	local top = ranked[1] and ranked[1].damage or 0

	shown = 0
	for index = 1, MAX_ROWS do
		local row = rows[index]
		local entry = ranked[index]
		if not entry then
			row:Hide()
		else
			shown = index
			row:Show()
			row.name:SetText(entry.name)
			row.damage:SetText(Short(entry.damage))
			row.landed:SetText(Landed(entry))
			row.stopped:SetText(Stopped(entry))
			row.share:SetText((total > 0) and Percent(entry.damage / total) or "")

			local texture = IconFor(entry.key)
			row.icon:SetTexture(texture or "")
			row.icon:SetShown(texture and true or false)

			-- Against the top row rather than against the total, because what a
			-- bar is for here is ranking the rows against each other, and
			-- against the total the top bar is a third of the width and
			-- everything under it is a sliver.
			local share = (top > 0) and (entry.damage / top) or 0
			row.bar:SetWidth(math.max(1, UI.Round(row, share * width)))
		end
	end

	head:SetText(("%s damage"):format(Short(total)))
	note:SetText(ns.Breakdown.Describe())

	bandChip.text:SetText(BandWord())
	bandChip.active = ns.Breakdown.Band() ~= nil
	PaintChip(bandChip)

	if shown == 0 then
		blank:SetText(ns.Breakdown.Ready()
			and "Nothing counted in this band yet. Swing at something."
			or "This client has no combat log API, so there is nothing to count.")
		blank:Show()
	else
		blank:Hide()
	end

	view:Update(shown * ROW)
	return true
end

function Window.Open()
	if not window then
		Build()
	end
	window:Show()
	Window.Paint()
	return true
end

function Window.Close()
	if window then
		window:Hide()
	end
end

function Window.IsShown()
	return window ~= nil and window:IsShown()
end

function Window.Toggle()
	if Window.IsShown() then
		Window.Close()
		return false
	end
	Window.Open()
	return true
end

-- The one repaint nobody clicked for. A lifetime table does not move while you
-- read it, except across the fight you just had, so the window catches up when
-- you drop combat and never asks the client anything in between.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
	if Window.IsShown() then
		Window.Paint()
	end
end)

-- The same table, printed. What the window says in three lines per row this
-- says in one, because a slash word's answer scrolls past in a chat frame and
-- the thing you want from it is the ranking rather than the detail.
function Window.Print(limit)
	local ranked, total = ns.Breakdown.Rank(ns.Breakdown.Band())
	if #ranked == 0 then
		ns.Print("nothing counted yet.")
		return 0
	end

	ns.Print(("what this character does, %s:"):format(ns.Breakdown.Describe()))
	local count = math.min(limit or 10, #ranked)
	for index = 1, count do
		local row = ranked[index]
		local share = (total > 0) and Percent(row.damage / total) or "0%"
		local crit = Percent(ns.Breakdown.CritRate(row)) or "no hits"
		local missed = Percent(ns.Breakdown.MissRate(row)) or "0%"
		ns.Print(("  %s  %s  %s of it, %s crit, %s stopped, %d hits")
			:format(row.name, Short(row.damage), share, crit, missed, row.landed))
	end
	return count
end

-- How many rows the table is drawing, for scripts/harness.lua and for anything
-- else that has to prove the window filled without this file handing out its
-- pool.
function Window.Shown()
	return shown
end

function Window.Row(index)
	return rows[index]
end
