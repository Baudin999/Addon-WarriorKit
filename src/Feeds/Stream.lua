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

-- The seven settings a stream owns beyond the one named after its prefix, as
-- the words that follow it. Named here so Feeds/Feature.lua registers the same
-- list this file reads and neither can drift without the other failing to find
-- a key.
local KEYS = { "Rows", "Width", "Zoom", "Alpha", "Mouse", "Shown", "Point" }

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
--------------------------------------------------------------------------

function Stream.New(spec)
	local stream = setmetatable({
		prefix = spec.prefix,
		name = spec.name,
		title = spec.title,
		empty = spec.empty,
		note = spec.note,
		onTooltip = spec.onTooltip,
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
function Stream.Defaults(prefix, point)
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
	self.caption = UI.Label(frame, 14, C.heading, "LEFT")
	self.caption:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2 * self.unit)
	self.caption:SetText(self.title)
	self.caption:Hide()

	self.feed = UI.Feed(frame, {
		unit = self.unit,
		title = self.title,
		empty = self.empty,
		note = self.note,
		onTooltip = self.onTooltip,
	})
	self.feed.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	-- Told here rather than left to Apply. Apply resizes before it shows, and a
	-- resize repaints, so a feed the player has hidden would draw its whole
	-- column once at every login for nobody.
	self.feed:Awake(self:Visible())

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

	local width, height = self.feed:Resize(self:Setting("width"), self:Setting("rows"))
	self.frame:SetSize(width, height)

	-- The edge follows the background. At zero opacity the player has asked for
	-- rows over the world, and a hairline rectangle round nothing is a window
	-- frame with no window in it.
	local alpha = self:Setting("alpha") / 100
	self.bg:SetColorTexture(C.window[1], C.window[2], C.window[3], alpha)
	for index = 1, 4 do
		self.edges[index]:SetAlpha(alpha > 0 and 1 or 0)
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
