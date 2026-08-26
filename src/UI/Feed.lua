local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The feed
--
-- A column of things that happened, newest at the top, older below it, and the
-- older ones still there when you scroll down to look.
--
-- **Why this is not UI/Log.lua.** That file is a column of strings and the
-- client's own ScrollingMessageFrame draws it, which is exactly right for
-- conversation and cannot do this: a message frame holds text and nothing else,
-- so an icon per line is not something it can be asked for. A row here is an
-- icon, a name, a number and a coloured mark down its left edge, which is four
-- regions the client has no line type for.
--
-- **Why this is not UI/Stack.lua and UI/Scroll.lua.** Those lay a column out by
-- asking every row how tall it is and placing them one under the next, which
-- means a row arriving reflows the whole column. UI/Log.lua's header already
-- argues that case and refuses it, and a feed is the same argument again with a
-- worse constant: four hundred entries measured every time a mob drops
-- something.
--
-- **So the rows do not move.** There is one frame per visible row, built once,
-- anchored once, and never anchored again. What arrives is written into a ring
-- of entries, and scrolling is an offset into that ring: the rows keep their
-- positions and repaint from a different place in the list. Ten rows repaint
-- whether the feed holds ten entries or four hundred, so a scroll costs the
-- same as a drop and both cost ten guarded writes.
--
-- That also means there is no clipping to arrange, no canvas to move and no
-- ScrollFrame to probe. The rows exactly fill the space, so there is nothing
-- to clip.
--
-- **Nothing here is on a ticker.** A feed changes when something happens to
-- you, which is an event, and it changes when you scroll it, which is a
-- gesture. A relative timestamp on a row would be the one thing that has to be
-- redrawn while nothing is happening, which is why a row carries no clock and
-- the tooltip is where the time is: opening a tooltip is a moment, and a moment
-- can afford to build a string.
--------------------------------------------------------------------------

-- Every number is a unit, which is one physical pixel inside a frame
-- ns.UI.Adopt has taken onto the grid, and a whole block of them above zoom 1.
--
-- The icon is 27 for the reason Meter/Window.lua's is: the client stores a
-- spell or item icon at 64 texels, UI/Draw.lua's crop leaves 54 of them, and a
-- draw is one texel per pixel only at 54 and 27. Everything else on a row
-- follows from it.
local ICON = 27
local ROW = 29
local ROW_GAP = 1
local HEADER = 16
local RULE = 1
local INSET = 3     -- the stripe to the icon
local STRIPE = 2    -- the coloured mark down the left of a row
local GUTTER = 5    -- the icon to the name
local PAD = 4       -- the name to the number beside it

-- Outlined, so both sizes sit at or above ns.UI.OutlineFloor. A feed is drawn
-- over the world with whatever background the player asked for, and at zero
-- background that is outlined text on grass. Flat text does not get softer
-- there, it goes.
local ROW_TEXT = 14
local HEADER_TEXT = 14

-- How far one notch of the wheel moves. Three is what UI/Log.lua uses, what
-- UI/Scroll.lua uses, and what every window in the game uses.
local WHEEL_ROWS = 3

-- The most rows a feed will ever be asked to draw, and how many entries it
-- keeps behind them. A frame cannot be destroyed on this client, so the rows
-- are built once at this count and the setting decides how many are shown.
local MAX_ROWS = 24
local HELD = 400

-- What the bottom row fades to when there is more underneath it.
--
-- The one piece of decoration in this file, and it is carrying information
-- rather than atmosphere: it is the difference between a feed that has stopped
-- and a feed that continues past the bottom edge. The scrollbar says the same
-- thing and says it in eight pixels off to the side, which is not where you are
-- looking. Written once per row per paint, behind a guard, and it costs nothing
-- because it is a function of the row's position rather than of the clock.
local FADE = 0.45

local Feed = {}
Feed.__index = Feed

-- How many screen pixels of art a row icon draws at a given zoom, and whether
-- that is one stored texel per pixel.
--
-- Read out of ns.UI.IconSizes rather than typed, so changing the crop in
-- UI/Draw.lua moves this answer instead of leaving a stale number in a panel
-- note. Meter/Window.lua answers the same question about its own rows and the
-- two are deliberately separate: they are allowed to pick different icon sizes,
-- and a shared function would be a shared decision.
function UI.FeedIcons(zoom)
	local drawn = ICON * (zoom or 1)
	for _, exact in ipairs(UI.IconSizes()) do
		if exact == drawn then
			return drawn, true
		end
	end
	return drawn, false
end

--------------------------------------------------------------------------
-- One row
--------------------------------------------------------------------------

local function BuildRow(feed, index)
	local unit = feed.unit
	local row = CreateFrame("Frame", nil, feed.frame)
	row:SetSize(1, ROW * unit)
	row.index = index

	-- Behind everything, and only while the mouse is on it. A feed you can
	-- hover has to answer the hover with something other than a tooltip
	-- appearing off to one side, or there is no telling which row it is about.
	row.glow = ns.Fill(row, "BACKGROUND", C.hover[1], C.hover[2], C.hover[3], 0.5)
	row.glow:SetAllPoints()
	row.glow:Hide()

	-- The timeline itself. One segment per row, separated by the row gap, so a
	-- run of entries reads as a ribbon down the left edge broken into the
	-- things that made it. Its colour is the entry's, which for loot is the
	-- item's quality and for the combat log is what kind of event it was, and
	-- that is most of what you get from a feed at a glance without reading it.
	row.stripe = ns.Fill(row, "ARTWORK", C.edge[1], C.edge[2], C.edge[3], 1)
	row.stripe:SetPoint("TOPLEFT")
	row.stripe:SetPoint("BOTTOMLEFT")
	row.stripe:SetWidth(STRIPE * unit)

	row.icon = UI.Icon(row, "ARTWORK")
	row.icon:SetSize(ICON * unit, ICON * unit)
	row.icon:SetPoint("LEFT", row, "LEFT", (STRIPE + INSET) * unit, 0)

	row.name = UI.Label(row, ROW_TEXT, C.text, "LEFT")
	row.name:SetPoint("LEFT", row, "LEFT", (STRIPE + INSET + ICON + GUTTER) * unit, 0)

	row.amount = UI.Label(row, ROW_TEXT, C.text, "RIGHT")
	row.amount:SetPoint("RIGHT", row, "RIGHT", -INSET * unit, 0)

	-- The name gives way to the number. A clipped name is still the right item;
	-- a clipped number is a lie, which is Meter/Window.lua's rule and the same
	-- one applies to a stack size.
	row.name:SetPoint("RIGHT", row.amount, "LEFT", -PAD * unit, 0)

	row:SetScript("OnEnter", function(self)
		feed:Enter(self.index)
	end)
	row:SetScript("OnLeave", function()
		feed:Leave()
	end)
	UI.PassCamera(row)
	row:EnableMouse(false)

	row:Hide()
	return row
end

--------------------------------------------------------------------------
-- Standing one up
--
-- opts.title     the word over the column, and nothing drawn above the rows
--                when there is none
-- opts.empty     what is written where the rows would be before anything has
--                happened
-- opts.held      how many entries this feed keeps
-- opts.onTooltip function(entry, tip), filling the addon's own tooltip for the
--                row under the cursor
-- opts.unit      one design pixel in the parent's units, which the caller
--                already read off the frame it adopted
--------------------------------------------------------------------------

function UI.Feed(parent, opts)
	opts = opts or {}

	local feed = setmetatable({
		unit = opts.unit or UI.Unit(parent),
		title = opts.title,
		empty = opts.empty,
		onTooltip = opts.onTooltip,
		cap = opts.held or HELD,
		-- Every entry this feed will ever hold, made once. A ring rather than a
		-- list that is trimmed: the four hundred and first drop overwrites the
		-- first rather than allocating a table and dropping another, so a feed
		-- in its steady state allocates nothing at all.
		ring = {},
		written = 0,
		offset = 0,
		visible = 0,
		rows = {},
		hovered = nil,
		width = 1,
	}, Feed)

	feed.frame = CreateFrame("Frame", nil, parent)

	for index = 1, feed.cap do
		feed.ring[index] = {}
	end

	if feed.title then
		feed.heading = UI.Label(feed.frame, HEADER_TEXT, C.dim, "LEFT")
		feed.heading:SetPoint("TOPLEFT", feed.frame, "TOPLEFT", INSET * feed.unit, -INSET * feed.unit)
		feed.heading:SetText(feed.title)

		feed.tally = UI.Label(feed.frame, HEADER_TEXT, C.quiet, "RIGHT")
		feed.tally:SetPoint("TOPRIGHT", feed.frame, "TOPRIGHT", -INSET * feed.unit, -INSET * feed.unit)

		feed.rule = ns.Fill(feed.frame, "ARTWORK", C.hairline[1], C.hairline[2], C.hairline[3], 1)
		feed.rule:SetPoint("TOPLEFT", feed.frame, "TOPLEFT", 0, -HEADER * feed.unit)
		feed.rule:SetHeight(RULE * feed.unit)
	end

	feed.blank = UI.Label(feed.frame, ROW_TEXT, C.quiet, "LEFT")
	feed.blank:SetPoint("TOPLEFT", feed.frame, "TOPLEFT",
		(STRIPE + INSET) * feed.unit, -(feed.title and (HEADER + RULE + INSET) or INSET) * feed.unit)
	feed.blank:SetText(feed.empty or "")

	for index = 1, MAX_ROWS do
		feed.rows[index] = BuildRow(feed, index)
	end

	feed.bar = UI.ScrollBar(feed.frame, function(_, value)
		-- The bar is written back to on every arrival, and that write fires
		-- this. The latch is UI/Scroll.lua's and UI/Log.lua's, and it is here
		-- for the same reason: without it the write and the handler chase each
		-- other for a frame every time something drops.
		if feed.syncing then
			return
		end
		feed:ScrollTo(value)
	end)
	if feed.bar then
		feed.bar:SetPoint("TOPRIGHT", feed.frame, "TOPRIGHT",
			0, -(feed.title and (HEADER + RULE) or 0) * feed.unit)
		feed.bar:SetPoint("BOTTOMRIGHT")
		feed.bar:Hide()
	end

	return feed
end

--------------------------------------------------------------------------
-- What is in it
--
-- The ring counts from the newest backwards, because that is the only order a
-- feed is ever read in: row one is the newest, row two is the one before it,
-- and the offset is how many have been scrolled past.
--------------------------------------------------------------------------

function Feed:Count()
	return math.min(self.written, self.cap)
end

-- The nth newest entry, where zero is the newest. Nil past the end, which is
-- what a row with nothing to draw gets.
function Feed:At(n)
	if n < 0 or n >= self:Count() then
		return nil
	end
	return self.ring[((self.written - 1 - n) % self.cap) + 1]
end

-- The slot the next entry goes in, wiped and handed over for the caller to
-- fill. The feed owns it: filling it and then not calling Push leaves it to be
-- wiped again by the next caller, and holding on to it past a Push is holding a
-- table the ring will write over.
--
-- Two calls rather than one that takes the fields, because the fields differ
-- per feed. A loot row is an item and a stack size; a combat row is a spell, a
-- number and four things only the tooltip reads. Passing either as arguments
-- would fix one feed's shape into this file, and passing a table would
-- allocate one per event on a path the combat log drives.
function Feed:Entry()
	local slot = self.ring[(self.written % self.cap) + 1]
	for key in pairs(slot) do
		slot[key] = nil
	end
	return slot
end

-- Make the filled slot the newest, and redraw.
--
-- The offset moves with it when you are reading history. Everything below the
-- top has just been pushed one row down the list, so leaving the offset alone
-- would scroll the feed under your eyes every time a mob died. At the top,
-- where the offset is zero, the new entry simply arrives, which is the whole
-- point of being at the top.
function Feed:Push()
	local slot = self.ring[(self.written % self.cap) + 1]
	slot.at = GetTime()
	self.written = self.written + 1

	if self.offset > 0 and self.offset < self:Room() then
		self.offset = self.offset + 1
	end

	self:Paint()
	return slot
end

function Feed:Clear()
	self.written, self.offset = 0, 0
	self:Paint()
	return true
end

--------------------------------------------------------------------------
-- Where you are in it
--------------------------------------------------------------------------

-- How many entries are off the bottom of the view, which is how far the offset
-- is allowed to go.
function Feed:Room()
	return math.max(0, self:Count() - self.visible)
end

function Feed:Live()
	return self.offset <= 0
end

function Feed:Offset()
	return self.offset
end

-- One drawn row, for scripts/harness.lua and for a macro.
--
-- Handed out for the reason Meter/Window.lua hands out a pane: the harness has
-- to measure what was actually drawn, and the alternative is this file
-- publishing its whole pool or the harness asserting against the entry list,
-- which would be asserting that the data is right rather than that it reached
-- the screen. Those are different claims and the second one is the one a
-- screenshot would show.
function Feed:Row(index)
	return self.rows[index]
end

function Feed:ScrollTo(value)
	local room = self:Room()
	local want = math.max(0, math.min(math.floor((value or 0) + 0.5), room))
	if want == self.offset then
		return false
	end
	self.offset = want
	self:Paint()
	return true
end

function Feed:Scroll(rows)
	return self:ScrollTo(self.offset + rows)
end

function Feed:ToTop()
	return self:ScrollTo(0)
end

--------------------------------------------------------------------------
-- Size, and whether it answers the mouse
--------------------------------------------------------------------------

-- The bar column is reserved whether or not the bar is showing, which is the
-- rule UI/Scroll.lua and UI/Log.lua both state: handing the width back when the
-- content fits would rewrap the rows, which can make them not fit, which brings
-- the bar back. A layout that can argue with itself is a layout that flickers.
function Feed:Resize(width, rows)
	local unit = self.unit
	rows = math.max(1, math.min(rows or 1, MAX_ROWS))

	self.width = width
	self.visible = rows

	local top = self.title and (HEADER + RULE) or 0
	local height = top + rows * (ROW + ROW_GAP) - ROW_GAP
	self.frame:SetSize(width * unit, height * unit)

	local content = math.max(width - M.bar - M.gutter, 1)
	if self.rule then
		self.rule:SetWidth(width * unit)
	end

	for index = 1, MAX_ROWS do
		local row = self.rows[index]
		row:SetWidth(content * unit)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0,
			-(top + (index - 1) * (ROW + ROW_GAP)) * unit)
		if index > rows then
			row.shownEntry = nil
			row:Hide()
		end
	end

	-- The offset can be past the end after a shrink, which is a feed that draws
	-- a screen of nothing at the bottom of its own history.
	if self.offset > self:Room() then
		self.offset = self:Room()
	end

	self:MouseRows()
	self:Paint()
	return width * unit, height * unit
end

-- Whether the rows take the mouse at all.
--
-- A setting rather than always on, and the note in Meter/Window.lua is the
-- reason: a mouse enabled frame swallows every button that lands on it, and a
-- feed is a tall rectangle sitting where a right button drag to turn the camera
-- starts. ns.UI.PassCamera hands those two buttons back where the client will
-- take them, and where it will not this is the switch that gets the camera
-- back at the price of the tooltips.
-- Which rows take the mouse: the ones being drawn, and only while the setting
-- is on. Its own function because two things move it and each would otherwise
-- leave the other stale. Turning the setting off has to reach every row, and
-- so does growing the feed from eight rows to twelve, and a Mouse that returned
-- early because the setting had not changed would leave the four new rows
-- inert. That is a bug you find by hovering the bottom of a feed you have just
-- made taller, which is to say not for weeks.
function Feed:MouseRows()
	for index = 1, MAX_ROWS do
		self.rows[index]:EnableMouse(self.mouse and index <= self.visible or false)
	end
end

function Feed:Mouse(on)
	on = on and true or false
	if self.mouse == on then
		return false
	end
	self.mouse = on
	self:MouseRows()

	if type(self.frame.EnableMouseWheel) == "function" then
		self.frame:EnableMouseWheel(on)
		if on then
			self.frame:SetScript("OnMouseWheel", function(_, delta)
				-- Down the wheel is down the list, which is backwards in time.
				-- Shift is the whole way, the same shortcut UI/Log.lua keeps
				-- from the client's own chat.
				if IsShiftKeyDown and IsShiftKeyDown() then
					self:ScrollTo(delta > 0 and 0 or self:Room())
					return
				end
				self:Scroll(-delta * WHEEL_ROWS)
			end)
		else
			self.frame:SetScript("OnMouseWheel", nil)
		end
	end

	if not on then
		self:Leave()
	end
	return true
end

--------------------------------------------------------------------------
-- The mouse
--------------------------------------------------------------------------

function Feed:Enter(index)
	local row = self.rows[index]
	if not row then
		return false
	end
	self.hovered = index
	row.glow:Show()

	local entry = row.shownEntry
	if not entry or not self.onTooltip then
		return false
	end
	return UI.Tooltip.Open(row, function(tip)
		self.onTooltip(entry, tip)
	end)
end

function Feed:Leave()
	if self.hovered then
		local row = self.rows[self.hovered]
		if row then
			row.glow:Hide()
		end
		self.hovered = nil
	end
	UI.Tooltip.Close()
	return true
end

--------------------------------------------------------------------------
-- Painting
--
-- Every write is guarded on what the row already carries. This is not a ticker,
-- so the guards are not buying frames off a hot path; they are buying the case
-- a feed is actually in most of the time, which is one entry arriving at the
-- top of a column that is otherwise exactly what it already was. Without them
-- every drop would rewrite ten icons, twenty strings and ten colours to move
-- one row down by one.
--------------------------------------------------------------------------

local function Blank(row)
	if row.shownEntry ~= nil then
		row.shownEntry = nil
		row:Hide()
	end
end

local function PaintRow(row, entry, faded)
	if row.shownEntry ~= entry or not row:IsShown() then
		row.shownEntry = entry
		row:Show()
	end

	if row.shownIcon ~= entry.icon then
		row.shownIcon = entry.icon
		row.icon:SetTexture(entry.icon)
	end

	if row.shownName ~= entry.name then
		row.shownName = entry.name
		row.name:SetText(entry.name or "")
	end

	if row.shownAmount ~= entry.amount then
		row.shownAmount = entry.amount
		row.amount:SetText(entry.amount or "")
	end

	local color = entry.color or C.text
	if row.shownColor ~= color then
		row.shownColor = color
		row.name:SetTextColor(color[1], color[2], color[3])
	end

	local tone = entry.tone or C.text
	if row.shownTone ~= tone then
		row.shownTone = tone
		row.amount:SetTextColor(tone[1], tone[2], tone[3])
	end

	local stripe = entry.stripe or color
	if row.shownStripe ~= stripe then
		row.shownStripe = stripe
		row.stripe:SetColorTexture(stripe[1], stripe[2], stripe[3], stripe[4] or 1)
	end

	local alpha = faded and FADE or 1
	if row.shownAlpha ~= alpha then
		row.shownAlpha = alpha
		row:SetAlpha(alpha)
	end
end

function Feed:Paint()
	local count = self:Count()
	local room = self:Room()

	-- Show and Hide rather than SetShown. Every frame on both clients answers
	-- SetShown and this is a font string, which is a region rather than a frame,
	-- and nothing installed here proves a region takes it on 2.5.6. The two
	-- calls are the same write and cannot be refused.
	local blank = count == 0 and (self.empty or "") ~= ""
	if self.blank and self.shownBlank ~= blank then
		self.shownBlank = blank
		if blank then
			self.blank:Show()
		else
			self.blank:Hide()
		end
	end

	for index = 1, self.visible do
		local entry = self:At(self.offset + index - 1)
		if entry then
			-- The last row fades only while there is something under it to fade
			-- into. At the bottom of the history there is nothing below and a
			-- dimmed final row would be saying so falsely.
			PaintRow(self.rows[index], entry,
				index == self.visible and self.offset < room)
		else
			Blank(self.rows[index])
		end
	end
	for index = self.visible + 1, MAX_ROWS do
		Blank(self.rows[index])
	end

	if self.tally then
		local held = (count > 0) and tostring(count) or ""
		if self.shownTally ~= held then
			self.shownTally = held
			self.tally:SetText(held)
		end
	end

	-- The row under the cursor has just been repainted with a different entry
	-- on it, so the tooltip beside it is about something that has moved on. It
	-- is reopened rather than closed, because a tooltip vanishing when a mob
	-- dies somewhere else is worse than one that follows the row it is on.
	if self.hovered and self.hovered <= self.visible then
		self:Enter(self.hovered)
	end

	self:Sync()
end

-- Puts the bar back in step with the offset. Called after anything that could
-- move either, which is an arrival, a scroll and a resize.
function Feed:Sync()
	local bar = self.bar
	if not bar then
		return false
	end

	local room = self:Room()
	if room <= 0 then
		bar:Hide()
		return false
	end

	local height = self.visible * (ROW + ROW_GAP) - ROW_GAP
	local size = math.max(M.thumb,
		UI.Round(self.frame, height * self.unit * self.visible / math.max(self:Count(), 1)))
	bar.thumb:SetSize(M.bar, size)

	self.syncing = true
	bar:SetMinMaxValues(0, room)
	bar:SetValue(self.offset)
	self.syncing = nil
	bar:Show()
	return true
end

--------------------------------------------------------------------------

-- One line for a status command or a panel note. What is worth saying is where
-- you are in it, because a feed that looks stuck is nearly always a feed you
-- scrolled down an hour ago and left there.
function Feed:Describe()
	local count = self:Count()
	if count == 0 then
		return "empty"
	end
	if self:Live() then
		return ("%d held"):format(count)
	end
	return ("%d held, scrolled back %d"):format(count, self.offset)
end
