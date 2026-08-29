local ADDON, ns = ...

local Stream = {}
ns.Stream = Stream

local UI = ns.UI
local C = UI.Color

--------------------------------------------------------------------------
-- A feed, put on the screen
--
-- UI/Feed.lua draws a column of things that happened and knows nothing else:
-- not where it sits, not whether it is switched on, not how big the player
-- asked for it. This is the seam between that widget and the addon around it.
-- One frame on UIParent, on the pixel grid, movable while the addon is
-- unlocked, with one feed filling it and a block of settings behind it.
--
-- It exists because there are two of these and there will be more. The loot
-- stream and the combat log differ in what they capture and in what a row says;
-- they do not differ in any of the twelve things below, and two copies of
-- twelve things is two places to fix a drag that saves the wrong anchor.
--
-- **Settings are found by name, not passed in.** A stream is built with a
-- prefix and every setting it reads is that prefix and a word: lootFeed,
-- lootFeedRows, lootFeedWidth. The names are resolved once here rather than
-- concatenated at each read, so nothing builds a string to look a setting up,
-- and Feature.lua registers exactly the eight keys this file will ask for.
--
-- **On and shown are two settings, not one.** They were one, called after the
-- prefix, and it meant the only way to get a feed off the screen was to stop it
-- recording: hide it and it stopped collecting, so what came back when you
-- wanted it again was an empty column. Hiding a feed and switching it off are
-- different requests and now they are different keys. `lootFeed` is whether it
-- collects, which is what the capture files read before they do any work, and
-- `lootFeedShown` is whether you can see it. Off implies hidden, because a
-- frozen list left on screen reads as a bug rather than as a setting.
--
-- **Locked is the normal state.** Unlocked draws an outline and a name above
-- it, which is Meter/Window.lua's trade and is here for the same reason: a feed
-- that has nothing in it yet is otherwise a piece of empty screen you have to
-- find from memory.
--------------------------------------------------------------------------

-- The eleven settings a stream owns beyond the one named after its prefix, as
-- the words that follow it. Named here so Feeds/Feature.lua registers the same
-- list this file reads and neither can drift without the other failing to find
-- a key.
--
-- The last four arrived together and are all one subject: how much of a window
-- a feed is. Icon is the size of the picture on a row and therefore the height
-- of the row. Header is the word over the column. Edge is the hairline round
-- the whole thing. Filters is the strip of chips, which is the loot feed's and
-- which a stream with no chips ignores rather than special cases.
local KEYS = {
	"Rows", "Width", "Zoom", "Alpha", "Mouse", "Shown", "Point",
	"Icon", "Header", "Edge", "Filters",
}

--------------------------------------------------------------------------
-- The status strip
--
-- An optional row along the bottom of a stream, under a hairline, holding three
-- short readings: one at each end and one in the middle. A stream that is given
-- no onStatus has none of it and is the frame it always was.
--
-- **Why the strip has a beat and the feed does not.** Everything above it
-- changes when something happens to you, and the header of UI/Feed.lua refuses
-- a ticker on exactly that ground. A reading is the other kind of number: gold
-- an hour moves because the clock moved, and nothing fires an event when a
-- minute passes. So the strip carries the only OnUpdate in this part, one
-- second apart, and it is a child of the stream frame, which means the client
-- stops calling it the moment the feed is hidden.
--------------------------------------------------------------------------

local STATUS = 20     -- the strip's own height
local STATUS_RULE = 1 -- the hairline over it
local STATUS_INSET = 4
-- UI.OutlineFloor(), and the strip is 20 to hold it. This was 12 in a 17 tall
-- strip and it is what the report about the purse's font was looking at: an
-- outlined glyph spends a pixel of every stroke on its rim, so at 12 the hole
-- in a 6 closed and the waist of an 8 filled in, on the one line in the window
-- that is nothing but digits. Written as the floor rather than as 14, because
-- the two numbers are the same rule and only one of them should be edited.
local STATUS_TEXT = 14

-- One second. The three readings behind this change about once a minute
-- between them, so a faster beat would be four comparisons a frame to write
-- nothing, and a slower one would leave a gold figure visibly behind the coin
-- you just picked up.
local BEAT = 1

local Instance = {}
Instance.__index = Instance

local streams = {}

--------------------------------------------------------------------------
-- Building
--
-- spec.prefix    the setting that switches it collecting, and the stem of the
--                other seven
-- spec.name      the global the frame is made under, so a stream that has
--                wandered off the screen can be found from a macro
-- spec.title     the word over the column, and the name shown while unlocked
-- spec.empty     what stands where the rows would be before anything happens
-- spec.note      how wide the dim middle column is, in units, and nothing for a
--                stream whose rows are a name and a number
-- spec.onTooltip function(entry), answering the table UI/Tooltip.lua renders
-- spec.chips     the filter strip over the rows, or nothing for a stream with
--                none. See UI/Feed.lua's own header for one chip's shape
-- spec.filter    function(entry), whether an entry is drawn, and nothing at all
--                for a stream that draws everything it holds
-- spec.onStatus  function(), answering the three readings along the bottom and
--                the colour of the last one, or nothing at all for a stream
--                whose strip is switched off. Absent for a stream with no strip
-- spec.onStatusTooltip function(), the table hovering that strip renders
--------------------------------------------------------------------------

function Stream.New(spec)
	local stream = setmetatable({
		prefix = spec.prefix,
		name = spec.name,
		title = spec.title,
		empty = spec.empty,
		note = spec.note,
		onTooltip = spec.onTooltip,
		chips = spec.chips,
		filter = spec.filter,
		onStatus = spec.onStatus,
		onStatusTooltip = spec.onStatusTooltip,
		keys = { on = spec.prefix },
	}, Instance)

	for _, word in ipairs(KEYS) do
		stream.keys[word:lower()] = spec.prefix .. word
	end

	streams[#streams + 1] = stream
	return stream
end

-- The defaults for one stream's seven shaped settings, merged by Feature.lua into
-- the table it registers. Written here rather than there so the file that reads
-- a setting is the file that says what it means.
--
-- Ten rows of a 29 pixel row is a column about the height of a chat window and
-- roughly a pull's worth of drops. 260 wide holds a 27 pixel icon, a fixed
-- number column and an item name that is not clipped to three words.
--
-- It was 220 and that was measured against a row of two columns. Three columns
-- need the width back and then some, and a loot feed narrower than the combat
-- feed sitting in the opposite corner reads as a mistake rather than as a
-- decision, so both moved.
--
-- `chrome` is whether this stream ships with a word over it and a line round
-- it. It is an argument rather than a constant because the two feeds answer it
-- differently and both answers are right: the loot feed's rows are an icon, a
-- name in the item's own colour and a count, with a row of quality chips over
-- them, and none of that needs the word "Loot" written above it. A combat feed
-- is three columns of numbers and does.
function Stream.Defaults(prefix, point, chrome)
	return {
		[prefix] = true,
		[prefix .. "Rows"] = 10,
		[prefix .. "Width"] = 260,
		[prefix .. "Zoom"] = 1,
		-- Not the meter's zero. A meter is three columns of outlined text you
		-- read out of the corner of your eye during a pull; a feed is a list you
		-- lean in and read, with a scrollbar down one side, and a scrollbar over
		-- bare world is a control with nothing behind it. 70 is a surface you
		-- can read a grey item name on and still see the floor through.
		[prefix .. "Alpha"] = 70,
		[prefix .. "Mouse"] = true,
		-- Shown by default, and separate from the switch above it. A feed you
		-- have hidden goes on collecting, so bringing it back shows the last few
		-- hundred things that happened rather than a blank column; a feed you
		-- have switched off collects nothing and is hidden with it.
		[prefix .. "Shown"] = true,
		[prefix .. "Point"] = point,

		-- The picture on a row, and the row height that follows it. 27 is the
		-- size at which the client's own icon art draws one stored texel per
		-- screen pixel, which is why it is the default and why the panel says
		-- so when you move off it.
		[prefix .. "Icon"] = ns.UI.FEED_ICON,

		[prefix .. "Header"] = chrome and true or false,
		[prefix .. "Edge"] = chrome and true or false,

		-- On for the stream that has chips, and read by the one that has none
		-- without either of them knowing about the other.
		[prefix .. "Filters"] = true,
	}
end

-- When an entry happened, on the wall clock.
--
-- GetTime counts from when the client started, which is the right clock to
-- record on and an unreadable one to show, so the difference between then and
-- now is taken off the current time of day. Built on a hover rather than stored
-- on the entry, because Feed:Push runs on the path a raid drives and a hover is
-- a moment that can afford a string.
--
-- Here rather than in either capture file because both of them want it and the
-- second copy is the one that drifts.
function Stream.Clock(at)
	if not at then
		return "?"
	end
	return date("%H:%M:%S", time() - (GetTime() - at))
end

function Instance:Setting(word)
	return ns.db[self.keys[word]]
end

--------------------------------------------------------------------------
-- The strip, written
--
-- On the strip's own beat, which is why every write here is behind a
-- comparison. A SetText costs a measure and a relayout whether or not the
-- string changed, and two of these three change about once a minute; the
-- colour changes when the rate crosses zero, which is a handful of times an
-- evening.
--
-- Colours are compared by identity rather than by component, which is the same
-- bargain UI/Feed.lua strikes and the reason Feeds/Purse.lua hands back stable
-- tables instead of building one per reading.
--------------------------------------------------------------------------

local function Refresh(stream)
	local held, hoard, rate, tone = stream.onStatus()
	if not held then
		return false
	end

	if stream.heldAt ~= held then
		stream.heldAt = held
		stream.held:SetText(held)
	end
	if stream.hoardAt ~= hoard then
		stream.hoardAt = hoard
		stream.hoard:SetText(hoard)
	end
	if stream.rateAt ~= rate then
		stream.rateAt = rate
		stream.rate:SetText(rate)
	end
	if stream.toneAt ~= tone then
		stream.toneAt = tone
		stream.rate:SetTextColor(tone[1], tone[2], tone[3])
	end
	return true
end

-- The strip itself, built once. Three font strings and a hairline, and the one
-- ticker in this part.
function Instance:BuildStatus()
	local frame, unit = self.frame, self.unit

	local strip = CreateFrame("Frame", nil, frame)
	self.status = strip
	strip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	strip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	strip:SetHeight(STATUS * unit)
	strip.since = 0

	self.statusRule = ns.Fill(frame, "ARTWORK", C.hairline[1], C.hairline[2],
		C.hairline[3], 1)
	self.statusRule:SetPoint("BOTTOMLEFT", strip, "TOPLEFT", 0, 0)
	self.statusRule:SetPoint("BOTTOMRIGHT", strip, "TOPRIGHT", 0, 0)
	self.statusRule:SetHeight(STATUS_RULE * unit)

	-- Yours in the addon's heading gold, the account's dim in the middle
	-- because it is context rather than news, and the rate on the right in
	-- whatever colour the rate has earned.
	--
	-- Outlined, like every row of the feed above, and for the same reason: the
	-- background under all of it is a slider that reaches zero, and at zero
	-- this strip is three numbers over the world.
	self.held = UI.Label(strip, STATUS_TEXT, C.heading, "LEFT", UI.OUTLINE)
	self.held:SetPoint("LEFT", strip, "LEFT", STATUS_INSET * unit, 0)

	self.hoard = UI.Label(strip, STATUS_TEXT, C.dim, "CENTER", UI.OUTLINE)
	self.hoard:SetPoint("CENTER", strip, "CENTER", 0, 0)

	self.rate = UI.Label(strip, STATUS_TEXT, C.quiet, "RIGHT", UI.OUTLINE)
	self.rate:SetPoint("RIGHT", strip, "RIGHT", -STATUS_INSET * unit, 0)

	strip:SetScript("OnUpdate", function(this, elapsed)
		this.since = this.since + elapsed
		if this.since < BEAT then
			return
		end
		this.since = 0
		Refresh(self)
	end)

	if self.onStatusTooltip then
		strip:SetScript("OnEnter", function()
			ns.Tip.Open(strip, self.onStatusTooltip())
		end)
		strip:SetScript("OnLeave", function()
			ns.Tip.Close()
		end)
	end
	return true
end

-- The strip, sized to the feed above it, and the height the frame has to add to
-- the feed's own for it. Zero for a stream with no strip and for one whose
-- reading says it has nothing to report, which is how the setting behind the
-- strip reaches the geometry rather than only the paint.
function Instance:Dress()
	if not self.status then
		return 0
	end

	local unit = self.unit
	if not (self.onStatus and self.onStatus()) then
		self.status:Hide()
		self.statusRule:Hide()
		return 0
	end

	-- Three cells across the width, so the middle reading stays in the middle
	-- and the two ends clip rather than run into it. A feed at its narrowest is
	-- still three cells; what it loses is the tail of the longest number, and
	-- the tooltip is where the whole of it lives.
	local cell = math.max(math.floor((self:Setting("width") - STATUS_INSET * 2) / 3), 1)
	self.held:SetWidth(cell * unit)
	self.hoard:SetWidth(cell * unit)
	self.rate:SetWidth(cell * unit)

	self.status:SetHeight(STATUS * unit)
	self.statusRule:SetHeight(STATUS_RULE * unit)
	-- Whether it takes the mouse is Lock's alone, which Apply calls after this.
	self.status:Show()
	self.statusRule:Show()
	Refresh(self)
	return (STATUS + STATUS_RULE) * unit
end

function Instance:Build()
	if self.frame then
		return false
	end

	local frame = CreateFrame("Frame", self.name, UIParent)
	self.frame = frame
	UI.Adopt(frame, self:Setting("zoom"))
	self.unit = UI.Unit(frame)

	-- Under the tooltip and above the world. A feed is furniture, the same as
	-- the chat window, and it must not sit over a dialog the client puts up.
	frame:SetFrameStrata("MEDIUM")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetScript("OnDragStart", function(this)
		if not ns.db.locked then
			this:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(this)
		this:StopMovingOrSizing()
		local point, _, relativePoint, x, y = this:GetPoint()
		ns.db[self.keys.point] = { point, "UIParent", relativePoint, x, y }
	end)

	self.bg = ns.Fill(frame, "BACKGROUND", C.window[1], C.window[2], C.window[3], 1)
	self.bg:SetAllPoints()
	self.edges = ns.Outline(frame, C.edge[1], C.edge[2], C.edge[3], C.edge[4])
	ns.EdgeSize(self.edges, ns.Pixel(frame))

	-- The two things that exist only while the addon is unlocked, built once and
	-- shown and hidden rather than made and unmade.
	self.grab = UI.Box(frame, nil, C.accent)
	self.grab:SetAllPoints()
	self.grab:Hide()
	-- The outline floor rather than a 14 written here, which is the same number
	-- and the same rule as the drag captions on the swing bars and the buff
	-- row. This one was already tall enough; it just was not saying why.
	self.caption = UI.Label(frame, UI.OutlineFloor(), C.heading, "LEFT",
		UI.OUTLINE)
	self.caption:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2 * self.unit)
	self.caption:SetText(self.title)
	self.caption:Hide()

	self.feed = UI.Feed(frame, {
		unit = self.unit,
		title = self.title,
		empty = self.empty,
		note = self.note,
		onTooltip = self.onTooltip,
		chips = self.chips,
		filter = self.filter,
	})
	self.feed.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	-- Told here rather than left to Apply. Apply resizes before it shows, and a
	-- resize repaints, so a feed the player has hidden would draw its whole
	-- column once at every login for nobody.
	self.feed:Awake(self:Visible())

	if self.onStatus then
		self:BuildStatus()
	end

	return true
end

--------------------------------------------------------------------------
-- Everything a setting can move
--
-- Called at login and again whenever a number in the panel changes, never from
-- a tick, because nothing in a feed is on a tick.
--------------------------------------------------------------------------

function Instance:Apply()
	if not self.frame then
		return false
	end

	local point = self:Setting("point")
	self.frame:ClearAllPoints()
	self.frame:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	UI.Rezoom(self.frame, self:Setting("zoom"))

	-- What the column is dressed in, before what size it is. The strip over the
	-- rows is either there or not and everything below it is measured off that
	-- answer, so a resize that ran first would place every row against the last
	-- answer and then be told the new one.
	self.feed:Chrome(self:Setting("header"), self:Setting("filters"))

	local width, height = self.feed:Resize(self:Setting("width"), self:Setting("rows"),
		self:Setting("icon"))
	-- The strip is measured after the feed and before the frame, because it is
	-- the only thing in here whose height is a decision rather than a setting.
	self.frame:SetSize(width, height + self:Dress())

	-- The edge follows the background and its own switch, and it needs both. At
	-- zero opacity the player has asked for rows over the world, and a hairline
	-- rectangle round nothing is a window frame with no window in it; with the
	-- switch off they have asked for a surface with no line round it, which is
	-- what the loot feed ships as.
	local alpha = self:Setting("alpha") / 100
	local edged = (alpha > 0 and self:Setting("edge")) and 1 or 0
	self.bg:SetColorTexture(C.window[1], C.window[2], C.window[3], alpha)
	for index = 1, 4 do
		self.edges[index]:SetAlpha(edged)
	end
	-- The strip's hairline goes with them, for the same reason. Over bare world
	-- a line under the last row is a rule dividing nothing from nothing.
	if self.statusRule then
		self.statusRule:SetAlpha(alpha > 0 and 1 or 0)
	end

	self.feed:Mouse(self:Setting("mouse"))
	self:Lock()
	self:Show()
	return true
end

function Instance:Lock()
	if not self.frame then
		return false
	end
	local unlocked = not ns.db.locked
	-- The frame itself takes the mouse only while it is being placed. Locked,
	-- the only things on it that answer the mouse are the rows, and only when
	-- the player has left that setting on.
	self.frame:EnableMouse(unlocked)
	-- And the strip lets go of it while the feed is being placed. It sits along
	-- the bottom edge, which is where a hand reaches for a window, so a strip
	-- still taking the mouse is a corner of the frame you cannot drag by.
	if self.status then
		self.status:EnableMouse((not unlocked and self.onStatusTooltip
			and self:Setting("mouse")) and true or false)
	end
	if unlocked then
		self.frame:RegisterForDrag("LeftButton")
		self.grab:Show()
		self.caption:Show()
	else
		self.frame:RegisterForDrag()
		self.grab:Hide()
		self.caption:Hide()
	end
	return true
end

-- On screen or not, and the feed told either way.
--
-- The frame being hidden is not on its own enough. UI/Feed.lua repaints every
-- drawn row on every arrival whether or not anybody can see the result, and a
-- hidden feed still collecting would do all of that drawing into nothing. It is
-- most of what a row costs: about four fifths of the work of putting a combat
-- log event on the screen is the repaint, so the same answer goes to the
-- widget, which stops painting and paints once when it comes back.
-- Whether anybody can see this, which is both settings and neither one on its
-- own. Off implies hidden: there is nothing to look at in a column nothing is
-- being written to, and a frozen list left on screen reads as a bug.
function Instance:Visible()
	return (self:Setting("on") and self:Setting("shown")) and true or false
end

function Instance:Show()
	if not self.frame then
		return false
	end
	local visible = self:Visible()
	self.frame:SetShown(visible)
	self.feed:Awake(visible)
	return true
end

function Instance:Reset(point)
	ns.db[self.keys.point] = point
	return self:Apply()
end

function Instance:Feed()
	return self.feed
end

-- The status strip and the three readings on it, for the panel and for
-- scripts/harness.lua. Handed out for the reason UI/Feed.lua hands out a row:
-- "the strip is 17 units tall and the frame grew by 18" is a claim the harness
-- has to be able to make, and reaching into a stream's own fields to make it
-- would be asserting this file's spelling rather than its arithmetic.
function Instance:Strip()
	return self.status, self.held, self.hoard, self.rate
end

function Instance:Describe()
	if not self:Setting("on") then
		return "off"
	end
	if not self.feed then
		return "not built yet"
	end
	local line = self.feed:Describe()
	if not self:Setting("shown") then
		line = line .. ", hidden but still collecting"
	end
	if not self:Setting("mouse") then
		line = line .. ", not taking the mouse, so no tooltips"
	end
	return line
end

--------------------------------------------------------------------------
-- Every stream at once
--
-- The three hooks Core walks the registry for are per feature rather than per
-- stream, so Feeds/Feature.lua calls these and never names either stream.
--------------------------------------------------------------------------

function Stream.Each(method, ...)
	for index = 1, #streams do
		local stream = streams[index]
		stream[method](stream, ...)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	Stream.Each("Build")
	Stream.Each("Apply")
end)

-- A resolution change or a UI size change moves every number in a stream at
-- once, the same way it moves the meters.
UI.OnRescale(function()
	Stream.Each("Apply")
end)
