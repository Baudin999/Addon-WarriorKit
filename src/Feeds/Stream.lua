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
-- and Feature.lua registers exactly the seven keys this file will ask for.
--
-- **Locked is the normal state.** Unlocked draws an outline and a name above
-- it, which is Meter/Window.lua's trade and is here for the same reason: a feed
-- that has nothing in it yet is otherwise a piece of empty screen you have to
-- find from memory.
--------------------------------------------------------------------------

-- The seven settings a stream owns, as the words that follow its prefix. Named
-- here so Feeds/Feature.lua registers the same list this file reads and neither
-- can drift without the other failing to find a key.
local KEYS = { "Rows", "Width", "Zoom", "Alpha", "Mouse", "Point" }

local Instance = {}
Instance.__index = Instance

local streams = {}

--------------------------------------------------------------------------
-- Building
--
-- spec.prefix    the setting that switches it on, and the stem of the other six
-- spec.name      the global the frame is made under, so a stream that has
--                wandered off the screen can be found from a macro
-- spec.title     the word over the column, and the name shown while unlocked
-- spec.empty     what stands where the rows would be before anything happens
-- spec.onTooltip function(entry, tip), filling the row's tooltip
--------------------------------------------------------------------------

function Stream.New(spec)
	local stream = setmetatable({
		prefix = spec.prefix,
		name = spec.name,
		title = spec.title,
		empty = spec.empty,
		onTooltip = spec.onTooltip,
		keys = { on = spec.prefix },
	}, Instance)

	for _, word in ipairs(KEYS) do
		stream.keys[word:lower()] = spec.prefix .. word
	end

	streams[#streams + 1] = stream
	return stream
end

-- The defaults for one stream's six shaped settings, merged by Feature.lua into
-- the table it registers. Written here rather than there so the file that reads
-- a setting is the file that says what it means.
--
-- Ten rows of a 29 pixel row is a column about the height of a chat window and
-- roughly a pull's worth of drops. 220 wide holds a 27 pixel icon, an item name
-- that is not clipped to three words and a stack size.
function Stream.Defaults(prefix, point)
	return {
		[prefix] = true,
		[prefix .. "Rows"] = 10,
		[prefix .. "Width"] = 220,
		[prefix .. "Zoom"] = 1,
		-- Not the meter's zero. A meter is three columns of outlined text you
		-- read out of the corner of your eye during a pull; a feed is a list you
		-- lean in and read, with a scrollbar down one side, and a scrollbar over
		-- bare world is a control with nothing behind it. 70 is a surface you
		-- can read a grey item name on and still see the floor through.
		[prefix .. "Alpha"] = 70,
		[prefix .. "Mouse"] = true,
		[prefix .. "Point"] = point,
	}
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
		onTooltip = self.onTooltip,
	})
	self.feed.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

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

function Instance:Show()
	if not self.frame then
		return false
	end
	self.frame:SetShown(self:Setting("on") and true or false)
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
