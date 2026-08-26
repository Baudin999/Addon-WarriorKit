local ADDON, ns = ...

local Window = {}
ns.BreakdownWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The table
--
-- One row per ability, biggest first, drawn into the settings panel rather than
-- into a window of its own.
--
-- That is the decision worth arguing. Every other readout in this addon that
-- has a frame has it because you read it during a fight: the meters, the swing
-- bars, the nag row, the feeds. This is the opposite kind of thing. It is a
-- month of play summed up, it does not change while you look at it, and the
-- question it answers is asked between sessions rather than during a pull. A
-- window for it would be another movable frame to place, another anchor to
-- save and another thing on screen during the fight it is describing.
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

-- The most rows drawn. A character with more abilities than this has them
-- counted and simply does not see the tail, which is a readout decision rather
-- than a storage one: past twenty rows every share is under a percent and the
-- question has stopped being "what am I doing" and started being "what have I
-- ever done".
local MAX_ROWS = 20

-- Three text lines and a pixel of air, all whole units because the panel is on
-- the pixel grid.
local ROW = 40
local LINE1, LINE2, LINE3 = 1, 15, 27
local INSET = 2

-- How solid the share bar is. The same argument as the meter's bar opacity and
-- a smaller number, because this sits on an opaque panel rather than over the
-- world: on a dark surface a fifth of the accent is a tint you can rank rows by
-- and anything more is a block of colour with text on it.
local BAR = 0.20

local rows = {}
local blank
local shown = 0
local width = 1

--------------------------------------------------------------------------

-- Thousands from ten thousand up. Below that the digits are the point: an
-- ability that has done 8,412 damage and one that has done 8.4k are the same
-- row, and the first one can be compared with the row under it.
local function Short(value)
	value = value or 0
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

--------------------------------------------------------------------------
-- The three lines of one row
--------------------------------------------------------------------------

-- What landed, and how hard. Built only for a row that is being drawn, which is
-- at most twenty of them and only while the pane is open, so a formatted string
-- here costs nothing the way one on a ticker would.
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
-- every time the pane refreshed.
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

local function BuildRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW)

	row.bar = ns.Fill(row, "BACKGROUND", C.accent[1], C.accent[2], C.accent[3], BAR)
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetWidth(1)

	row.name = UI.Label(row, M.font, C.text, "LEFT", UI.FLAT)
	row.name:SetPoint("TOPLEFT", row, "TOPLEFT", INSET, -LINE1)

	row.damage = UI.Label(row, M.font, C.text, "RIGHT", UI.FLAT)
	row.damage:SetPoint("TOPRIGHT", row, "TOPRIGHT", -INSET, -LINE1)

	row.landed = UI.Label(row, M.small, C.dim, "LEFT", UI.FLAT)
	row.landed:SetPoint("TOPLEFT", row, "TOPLEFT", INSET, -LINE2)

	row.share = UI.Label(row, M.small, C.heading, "RIGHT", UI.FLAT)
	row.share:SetPoint("TOPRIGHT", row, "TOPRIGHT", -INSET, -LINE2)

	row.stopped = UI.Label(row, M.small, C.quiet, "LEFT", UI.FLAT)
	row.stopped:SetPoint("TOPLEFT", row, "TOPLEFT", INSET, -LINE3)

	-- The name gives way to the number on the first line, the same rule
	-- Meter/Window.lua and UI/Feed.lua both follow: a clipped ability is still
	-- recognisable and a clipped number is a lie.
	row.name:SetPoint("RIGHT", row.damage, "LEFT", -M.gutter, 0)
	row.landed:SetPoint("RIGHT", row.share, "LEFT", -M.gutter, 0)
	row.stopped:SetPoint("RIGHT", row, "RIGHT", -INSET, 0)

	row:Hide()
	return row
end

-- Everything a setting or a fight can move. Not on a ticker: this runs when the
-- panel refreshes, which is when it is opened and when something on it is
-- clicked.
function Window.Paint()
	if #rows == 0 then
		return false
	end

	local ranked, total = ns.Breakdown.Rank(ns.db.breakdownSort, ns.Breakdown.Band())
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

			-- Against the top row rather than against the total, because what a
			-- bar is for here is ranking the rows against each other, and
			-- against the total the top bar is a third of the width and
			-- everything under it is a sliver.
			local share = (top > 0) and (entry.damage / top) or 0
			row.bar:SetWidth(math.max(1, UI.Round(row, share * width)))
		end
	end

	if blank then
		blank:SetText(ns.Breakdown.Describe())
		if shown == 0 then
			blank:Show()
		else
			blank:Hide()
		end
	end
	return true
end

-- Added to whichever page the feature puts it on. One Custom row holding the
-- whole table rather than one stack row per ability, because the stack lays out
-- what it was given at build time and the number of abilities is not known
-- then and changes as you play.
function Window.Build(ui)
	ui.Custom(function(frame)
		for index = 1, MAX_ROWS do
			rows[index] = BuildRow(frame, index)
		end

		blank = UI.Label(frame, M.small, C.quiet, "LEFT", UI.FLAT)
		blank:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET, -LINE1)

		-- Measured rather than fixed, so a fresh character does not open a page
		-- with twenty rows of empty space on it. Options.Refresh paints before
		-- it reflows, so `shown` is this refresh's answer and not the last
		-- one's.
		-- The width is read off the row rather than off the stack, and that is
		-- not a shortcut. UI/Stack.lua stretches a cell to the column width
		-- before it asks the cell how tall it is, on purpose and with a comment
		-- saying why, so by the time this runs the frame already carries this
		-- layout's width. Asking the stack instead would mean this file holding
		-- a reference to it, which UI.Kit deliberately does not hand out.
		return function(cell)
			width = math.max(1, cell.frame:GetWidth())
			for index = 1, MAX_ROWS do
				rows[index]:SetWidth(width)
			end
			if shown == 0 then
				return M.row
			end
			return shown * ROW
		end
	end, {
		indent = M.indent,
		refresh = Window.Paint,
	})
end

-- The same table, printed. What the panel says in three lines per row this says
-- in one, because a slash word's answer scrolls past in a chat frame and the
-- thing you want from it is the ranking rather than the detail.
function Window.Print(limit)
	local ranked, total = ns.Breakdown.Rank(ns.db.breakdownSort, ns.Breakdown.Band())
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
-- else that has to prove the pane filled without this file handing out its pool.
function Window.Shown()
	return shown
end

function Window.Row(index)
	return rows[index]
end
