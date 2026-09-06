local ADDON, ns = ...

local Column = {}
ns.QuestColumn = Column

local UI = ns.UI
local C = ns.UI.Color
local M = ns.UI.Metric
local Log = ns.QuestLog

--------------------------------------------------------------------------
-- The addon's own quest tracker
--
-- A column over the world: the name of every quest you are standing in the
-- middle of, what each one still wants under it, and a gold bar down the left
-- of the ones you have pinned. It is placeable, it is the third thing this
-- addon draws over the world after the loot feed and the experience rails, and
-- the ground under it was settled by those two: UI/Placeable.lua owns the drag,
-- UI/Stack.lua owns the rows and UI.Wash is what makes text legible over grass
-- without a panel round it.
--
-- Not to be confused with Quests/Tracker.lua, which is next door and is about
-- somebody else's tracker: that file points Questie's clicks at this addon's
-- window. This file is the tracker.
--
-- **It draws from ns.QuestLog's zones and nothing else.** Quests/Log.lua turns
-- the client's flat run of rows into zones holding quests and caches the
-- answer, and until now the quest window's left column was its only reader.
-- Log.Zones() is the one door this file goes through. A tracker that read the
-- client's log itself would be the sheet and the loot feed again: two pictures
-- of one thing, drifting apart in the details nobody looks at until they are
-- side by side. One reading, two drawings.
--
-- **It scopes on the client's log header.** zone.name is the string the client
-- filed the quest under, ns.QuestHere.Now().name is C_Map's name for the map
-- you are standing on, and both come out of the same client in the same
-- language, which is what makes comparing them safe. It is the only name
-- comparison in the addon and Core/Here.lua's header says why every other join
-- in that file is on a number. The name is taken off ns.QuestHere and never off
-- a second probe of the client.
--
-- The header is a sort category rather than a place: a dungeon quest is filed
-- under the dungeon and a class quest under the class, and neither says where
-- the thing you still have to do is standing. Item 93 is that argument and it
-- is a different item. Nothing here asks Where.Nearest, which walks hundreds of
-- coordinate transforms per quest and has exactly one caller.
--
-- **Nothing is on a ticker.** The log changes on events and this redraws on
-- them. Questie's own quest updates are not wanted here either, and that is
-- worth saying because Quests/Window.lua hangs a second redraw off them: what
-- that callback buys that file is the order its right column is drawn in, since
-- two of its three lines are Questie's answers and the client's event arrives
-- before Questie has finished thinking. Nothing on this column is Questie's.
-- The name and the objectives are the client's own, so the client's own events
-- are already the right grain, and a second source registered for a redraw that
-- would say the same thing is one more thing to keep in step.
--
-- **It follows ns.QuestTrackerOff.Wanted().** One switch, one tracker: the box
-- that takes Questie's tracker off the screen is the box that puts this one up,
-- so there is never a moment where both are drawn and no rule about which one a
-- quest name belongs to. It is not questsHideBlizz, which is about the client's
-- own window and the L key.
--------------------------------------------------------------------------

-- The column's width, in design units. Wide enough for a quest name at twelve
-- and no wider: this stands over the middle of somebody's game all evening, and
-- every pixel of it is a pixel of the world they do not get.
local WIDTH = 220

-- A quest's name, and one row under it per thing the quest still wants.
-- Furniture sizes, the chat window's argument: a window you open, read and shut
-- is aimed at once, and this is read at a glance a hundred times a night.
local TITLE = 16
local LINE = 14
local TITLE_TEXT = 12
local LINE_TEXT = 11

-- The mark on a pinned quest: a bar down the left edge of its name, in the
-- addon's heading gold. Two pixels, which is the width UI.List draws the
-- selected row's mark at, so the two read as one interface.
--
-- A bar rather than a glyph, and that is not a compromise. Media/Glyphs.ttf is
-- a subset of seventeen marks and none of them is a pin, so a glyph here would
-- mean rebaking the font and moving the list scripts/check.sh holds it to. A
-- gold edge says "yours" at a glance over grass, which is the whole job.
local PIN = 2

--------------------------------------------------------------------------

local frame, stack, place, wash
local heads, lines = {}, {}
local built = false

--------------------------------------------------------------------------
-- The model
--------------------------------------------------------------------------

-- Where you are standing, as this client's own name for it.
--
-- ns.QuestHere memoises on the map id, so this is a table lookup on a paint
-- path and a fresh reading the first time after you walk into somewhere new.
local function Standing()
	local here = ns.QuestHere.Now()
	return here and here.name or nil
end

-- Whether a quest carries the player's own mark.
--
-- One line and it is a seam. Item 95 moves the pin off the client's five watch
-- slots onto a store of this addon's own, keyed on the quest id, and renames the
-- field; this is the only place the tracker reads it.
local function Pinned(quest)
	return quest.pinned and true or false
end

-- What colour a quest's name is drawn in. Ready to hand in and about to kill
-- you are the two things a tracker is read for at a glance, so both of them get
-- a colour and everything else is body text.
local function Tone(quest)
	if quest.complete then
		return C.heading
	end
	if quest.failed then
		return C.loss
	end
	return C.text
end

-- The quests on the tracker right now: the ones the client filed under the
-- place you are standing in, in the log's own order.
--
-- Item 96 adds the other half of this. A pinned quest is on the tracker
-- wherever you stand, which is the exception the pin exists to buy, and it
-- appends here rather than anywhere in the drawing below.
function Column.Quests()
	local out = {}
	local name = Standing()
	if not name then
		return out
	end
	for _, zone in ipairs(Log.Zones()) do
		if zone.name == name then
			for _, quest in ipairs(zone.quests) do
				out[#out + 1] = quest
			end
		end
	end
	return out
end

--------------------------------------------------------------------------
-- The rows
--------------------------------------------------------------------------

-- Clicking a row opens the quest log on that quest.
--
-- Quests/Tracker.lua already wrote this: it is the swap that made a click in
-- Questie's tracker open this addon's window instead of the one in the attic,
-- and Tracker.Open is the whole of it. So a click here is one call and no new
-- path, and a quest the client cannot place answers false rather than opening
-- the window on whatever it showed last.
--
-- An objective row carries the id of the quest above it, so clicking the line
-- that says how many trappers are left opens the quest those trappers are for.
local function Press(row)
	if row.quest then
		ns.QuestTracker.Open(row.quest)
	end
end

-- One row of the column, made once and reused for whatever lands on it next.
--
-- Two pools rather than one, because a quest's name and one of its objectives
-- are drawn at different sizes and a shared pool would set the font object on
-- every row of every paint.
--
-- Shadowed rather than outlined, which is what UI/Feed.lua's rows over the
-- world are and for the same reason: the wash under this column is a gradient
-- and the right of it is the world, so there is no surface here whose colour
-- the addon can promise. An outline would be honest too and it has a fourteen
-- pixel floor, which is a tracker half again as tall for a rim nothing needs
-- over a wash.
local function Take(pool, at, size, indent)
	local row = pool[at]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, stack.frame)
	row.mark = ns.Fill(row, "ARTWORK", C.heading[1], C.heading[2], C.heading[3], 1)
	row.mark:SetPoint("TOPLEFT")
	row.mark:SetPoint("BOTTOMLEFT")
	row.mark:SetWidth(PIN)
	row.mark:Hide()

	row.text = UI.Label(row, size, C.text, "LEFT", UI.SHADOW)
	row.text:SetPoint("LEFT", indent, 0)
	row.text:SetPoint("RIGHT", -M.rowGap, 0)

	-- The left button and the up edge, written out rather than left to the
	-- widget's default. A row is a Button and a Button that registers nothing
	-- answers the left button on the up edge already, so this changes no
	-- behaviour and says what the behaviour is, which is the thing that goes
	-- wrong first in this addon when nobody writes it down.
	row:RegisterForClicks("LeftButtonUp")
	row:SetScript("OnClick", Press)

	-- The right button and the middle one to the camera, on a client that will
	-- take the call. 2.5.6 will not: SetPassThroughButtons arrived in 10.1.5,
	-- UI.PassCamera pcalls it and answers false here, and the rows keep every
	-- button they are given. So a right drag begun on this column stops dead on
	-- the live client, which is the trade UI/Window.lua's list already writes
	-- out and refused to take for the quest log's two hundred pixel left
	-- column. It is worth taking here and it is a narrower column: the rows are
	-- the whole of the feature, a tracker you cannot click is a picture, and
	-- the frame is one you drag to wherever your camera hand is not.
	UI.PassCamera(row)

	pool[at] = row
	return row
end

-- Every row the pool is holding past the end of this paint. This client cannot
-- destroy a frame, so a column that shrank has rows to put away by hand.
local function Spare(pool, used)
	for at = used + 1, #pool do
		pool[at]:Hide()
	end
end

-- Whether the rows answer the pointer at all. They give it up while the frame
-- is unlocked, for the reason Progress/Rails.lua gives: a row that took the
-- press would swallow the drag that is the whole point of unlocking.
local function Mouse(pool, on)
	for _, row in ipairs(pool) do
		row:EnableMouse(on)
	end
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

-- The column, filled in from the model. Answers how many quests went on it.
local function Fill()
	stack.cells = {}

	local quests = Column.Quests()
	local head, line = 0, 0
	for _, quest in ipairs(quests) do
		head = head + 1
		local row = Take(heads, head, TITLE_TEXT, M.rowGap + PIN + M.rowGap)
		local tone = Tone(quest)
		row.quest = quest.id
		row.text:SetText(quest.title or "")
		row.text:SetTextColor(tone[1], tone[2], tone[3])
		row.mark:SetShown(Pinned(quest))
		row:Show()
		stack:Add(row, { height = TITLE })

		for _, step in ipairs(Log.Objectives(quest.key) or {}) do
			line = line + 1
			local under = Take(lines, line, LINE_TEXT,
				M.rowGap + PIN + M.rowGap + M.indent)
			local shade = step.done and C.quiet or C.dim
			under.quest = quest.id
			under.text:SetText(step.text or "")
			under.text:SetTextColor(shade[1], shade[2], shade[3])
			under:Show()
			stack:Add(under, { height = LINE })
		end
	end

	-- Item 98's line goes on the foot of this stack, here, after the quests and
	-- before the two Spare calls: one more cell, naming one thing that is close
	-- to you, and the pools below are what it takes its row from.
	Spare(heads, head)
	Spare(lines, line)
	return #quests
end

-- Everything the tracker draws, from the model rather than from the client.
--
-- The log is read here. That is a second Log.Read in the sessions where the
-- quest window is also open, and it is the price of a tracker that is up while
-- the window is shut: the window reads only while it is showing, so with it
-- closed nobody else would have read at all. Both drawings still come off the
-- one set of zones that read leaves behind, which is the part that matters.
function Column.Paint()
	if not built then
		return false
	end
	Log.Read()

	local count = Fill()
	stack:SetWidth(WIDTH)
	local height = stack:Reflow()
	frame:SetHeight(math.max(height, 1))
	-- A tracker with nothing on it is a rectangle of shade over the world
	-- saying you are not on a quest here, which is a thing you already know.
	frame:SetShown(count > 0)
	-- Last, and over whatever the pool now holds. A row made on this paint has
	-- taken no side in the lock yet, and a row that answers the pointer while
	-- the frame is being placed swallows the drag that is the point of
	-- unlocking.
	Column.Lock()
	return count > 0
end

--------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------

function Column.Build()
	if built then
		return frame
	end

	frame = CreateFrame("Frame", "WarriorKitQuestColumn", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetSize(WIDTH, 1)
	UI.Adopt(frame, ns.Zoom("questsZoom"))

	-- No background and no hairline, because this is not a window. The wash is
	-- the whole of the ground: solid shadow at the left edge where the words
	-- start, gone by the right edge where they end, so the column has something
	-- to be read against without a panel cut out of the world.
	wash = UI.Wash(frame, C.shadow, "LEFT", "BACKGROUND")
	wash:SetAllPoints(frame)

	stack = UI.Stack(frame, WIDTH)

	place = UI.Placeable(frame, {
		name = "WarriorKit quest tracker",
		moved = function(anchor)
			ns.db.questsColumnPoint = anchor
		end,
	})

	frame:Hide()
	built = true
	return frame
end

-- Whether the tracker should be on the screen right now.
--
-- The switch that takes Questie's tracker off, and no switch of its own. Two
-- trackers on one screen is the thing item 90 went to the trouble of a reload
-- to avoid, and a second box that could put ours up beside theirs would hand
-- that straight back.
function Column.Wanted()
	return ns.QuestTrackerOff.Wanted()
end

-- Everything a setting can move: where it sits, how big it is drawn, whether it
-- is there at all, and then what is on it.
function Column.Apply()
	if not ns.db then
		return false
	end
	if not Column.Wanted() then
		if built then
			frame:Hide()
		end
		return false
	end

	Column.Build()
	place:Place(ns.db.questsColumnPoint)
	UI.Rezoom(frame, ns.Zoom("questsZoom"))
	return Column.Paint()
end

function Column.Lock()
	if not built then
		return
	end
	local unlocked = not ns.db.locked
	place:Lock(unlocked)
	Mouse(heads, not unlocked)
	Mouse(lines, not unlocked)
end

-- Redrawn only while it is on the screen, which is the rule the quest window's
-- own refresh follows: reading sixty rows to update something nobody is looking
-- at is the waste this addon has a gate for.
function Column.Refresh()
	if not built or not Column.Wanted() then
		return false
	end
	return Column.Paint()
end

--------------------------------------------------------------------------

-- Short enough for a reading on the options page, which never wraps.
function Column.Describe()
	if not ns.db.quests then
		return "off with the quest log"
	end
	if not Column.Wanted() then
		return "off, and Questie's tracker has the screen"
	end
	local name = Standing()
	if not name then
		return "waiting to hear where you are standing"
	end
	local count = #Column.Quests()
	if count == 0 then
		return ("nothing in your log is in %s"):format(name)
	end
	if count == 1 then
		return ("one quest, in %s"):format(name)
	end
	return ("%d quests, in %s"):format(count, name)
end

--------------------------------------------------------------------------

-- The client's own quest events, and the three that say you have walked
-- somewhere new.
--
-- QUEST_LOG_UPDATE is the client saying it looked rather than the log changing,
-- several times a second while you are killing things, and each one is a read
-- and a repaint of a handful of rows. That is the same cost the quest window
-- already pays while it is open, taken by a frame that is open more often. If
-- it ever turns out to be the stutter Quests/Where.lua warns about, the fix is a
-- stamp on ns.QuestLog that both readers check, not a second model here.
--
-- The zone events do not empty ns.QuestHere. That answer is held on the map id
-- and re-derived when the id moves, so walking into Duskwood is a fresh reading
-- without anything having to say so.
local function OnEvent(_, event)
	if event == "PLAYER_LOGIN" then
		Column.Apply()
		return
	end
	Column.Refresh()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_WATCH_UPDATE")
events:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", OnEvent)

-- A resolution change moves every size in this file at once, the same way it
-- moves the experience rails and the swing bars.
UI.OnRescale(function()
	Column.Apply()
end)
