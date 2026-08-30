local ADDON, ns = ...

-- One button that holds all the other addons' buttons.
--
-- Every addon that wants to be reachable puts a round icon on the edge of the
-- minimap, and with eight of them installed the map is a ring of icons with a
-- map in the middle. None of them is pressed more than twice an evening. They
-- belong behind one square rather than around the thing you are trying to
-- read.
--
-- Three rules shape the file.
--
--   A button is borrowed, not taken. Its parent, its points and its own
--   SetPoint are all put back on release, and nothing about the button itself
--   is changed: not its scripts, not its textures, not its size. Press it in
--   the tray and it does exactly what it did on the ring.
--
--   Blizzard's buttons are not addon buttons. The mail icon, the tracking
--   icon and the calendar are things you read at a glance without pressing,
--   and Minimap/Shape.lua has already put them on the corners. The deny list
--   below is the line between the two.
--
--   No ticker. Addons load late and put their button up whenever they please,
--   so the scan runs on the two edges that mean "something may have appeared",
--   which are an addon finishing loading and the tray being opened, and never
--   on a clock.

local Corral = {}
ns.Corral = Corral

local UI = ns.UI

-- What one held button is drawn in. The buttons themselves are whatever size
-- their addon made them, mostly 31 or 32, and they are not resized: a button
-- scaled to fit is a button whose own art goes soft, and the cell is sized to
-- the largest of them instead.
local CELL = 32
local COLUMNS = 4
local GAP = 4

-- The square you press. One cell, so it reads as one of the things it holds.
local FACE = CELL

--------------------------------------------------------------------------
-- Which buttons are addon buttons
--
-- This test shipped as "named, parented to the minimap, not Blizzard's and not
-- ours", and it collected 555 of them on the first real client it met. The
-- minimap is not only where addons hang their button. It is also where every
-- addon that draws a pin on the map hangs the pin, and Questie alone parents
-- several hundred quest icons to it. The corral took the lot, and because a
-- taken button has its SetPoint replaced with a no-op, Questie then could not
-- move its own pins.
--
-- So the test is four things now, and the last is the one that matters.
--
--   A Button. A pin is often a Frame and a minimap button is almost never one.
--   This alone is most of the fix and none of the safety.
--
--   Sized like a button. LibDBIcon draws at 31 and everything that rolls its
--   own lands within a few pixels of it. A pin is drawn at 12 to 16.
--
--   Not one of a family. This is the rule that would have caught the 555 on
--   its own, and it is the only one here that is about shape rather than about
--   numbers. Pins are pooled, and a pool is named by counter: QuestieFrame1,
--   QuestieFrame2, QuestieFrame3. A minimap button has one name and no
--   siblings. So candidates are grouped by their name with the trailing digits
--   taken off, and any group with more than two in it is a pool and is left
--   alone entirely.
--
--   And a ceiling, which is not a filter but a refusal. Past CEILING the scan
--   stops and says how many it walked away from, because a corral that has
--   quietly eaten something is exactly the failure this comment is about.
--------------------------------------------------------------------------

-- What a minimap button measures. LibDBIcon's own default is 31 and the window
-- is wide enough for the ones that pick their own number.
local SMALLEST, LARGEST = 18, 48

-- How many may share one name family before the family is read as a pool. Two,
-- because a pair of buttons from one addon is a thing that happens and three
-- generated names in a row is not.
local FAMILY = 2

-- The most the corral will ever hold. Nothing sane reaches it, and reaching it
-- is reported rather than swallowed.
local CEILING = 24

local BLIZZARD = {
	Minimap = true,
	MinimapCluster = true,
	MinimapBackdrop = true,
	MinimapZoneTextButton = true,
	MinimapZoomIn = true,
	MinimapZoomOut = true,
	MinimapNorthTag = true,
	MiniMapWorldMapButton = true,
	MiniMapTracking = true,
	MiniMapTrackingFrame = true,
	MiniMapTrackingButton = true,
	MiniMapMailFrame = true,
	MiniMapMailBorder = true,
	MiniMapBattlefieldFrame = true,
	MiniMapMeetingStoneFrame = true,
	MiniMapVoiceChatFrame = true,
	MiniMapInstanceDifficulty = true,
	MiniMapPing = true,
	MiniMapLFGFrame = true,
	QueueStatusMinimapButton = true,
	TimeManagerClockButton = true,
	GameTimeFrame = true,
}

-- The addon's own frames, which are all named this way, and the border
-- Shape.lua draws, which has no name at all and so never gets this far.
local MINE = "WarriorKit"

-- The name with its trailing digits taken off, which is what a pool of pins
-- has in common and what a button has to itself.
local function Family(name)
	return (name:gsub("%d+$", ""))
end

-- The name this frame would be collected under, or nil. Everything except the
-- family rule, which needs to see the whole minimap at once and so lives in
-- the scan.
local function Candidate(frame)
	if type(frame) ~= "table" or type(frame.GetName) ~= "function" then
		return nil
	end
	local name = frame:GetName()
	if type(name) ~= "string" or name == "" then
		return nil
	end
	if BLIZZARD[name] or name:sub(1, #MINE) == MINE then
		return nil
	end
	if ns.Measure(frame, "GetObjectType") ~= "Button" then
		return nil
	end

	local width = ns.Measure(frame, "GetWidth")
	local height = ns.Measure(frame, "GetHeight")
	if type(width) ~= "number" or type(height) ~= "number" then
		return nil
	end
	if width < SMALLEST or width > LARGEST or height < SMALLEST or height > LARGEST then
		return nil
	end

	return name
end

--------------------------------------------------------------------------
-- Borrowing a button
--
-- A minimap button is usually dragged around its ring by its own OnUpdate or
-- OnDragStop, which means it writes its own position back whenever it feels
-- like it. Reparenting it is not enough: it would sit in the tray for a second
-- and then jump back onto the arc.
--
-- So its SetPoint is replaced with a method that does nothing, the same trick
-- and for the same reason as ns.Strip replacing Show with Hide. The real one
-- is kept on the button and handed back on release. This is done to a frame
-- the addon does not own, which is why the release path is written first and
-- tested before anything is held.
--------------------------------------------------------------------------

local held = {}       -- name -> button, everything currently in the tray
local order = {}      -- names, in the order they were taken, so the grid is stable
local parked = {}     -- name -> what it looked like before it was taken

local function Pin(button)
	if button.wkPinned then
		return
	end
	button.wkPinned = true
	button.wkSetPoint = button.SetPoint
	button.SetPoint = function() end
end

local function Unpin(button)
	if not button.wkPinned then
		return
	end
	button.SetPoint = button.wkSetPoint
	button.wkSetPoint = nil
	button.wkPinned = nil
end

local tray, face, countText, place

local function Take(name, button)
	if held[name] then
		return false
	end

	local point, relativeTo, relativePoint, x, y = button:GetPoint()
	parked[name] = {
		parent = button:GetParent(),
		point = point and { point, relativeTo, relativePoint, x, y } or nil,
	}

	button:SetParent(tray)
	button:ClearAllPoints()
	Pin(button)

	held[name] = button
	order[#order + 1] = name
	return true
end

local function Release(name)
	local button = held[name]
	if not button then
		return
	end
	local was = parked[name]

	Unpin(button)
	if was then
		button:SetParent(was.parent)
		button:ClearAllPoints()
		if was.point then
			button:SetPoint(was.point[1], was.point[2], was.point[3], was.point[4], was.point[5])
		else
			-- It arrived with no point of its own, so it is handed back with
			-- none. Whatever positioned it will position it again; guessing a
			-- corner here would be this file deciding where somebody else's
			-- button lives.
			button:SetPoint("CENTER", _G.Minimap, "CENTER", 0, 0)
		end
	end

	held[name] = nil
	parked[name] = nil
	for index = #order, 1, -1 do
		if order[index] == name then
			table.remove(order, index)
		end
	end
end

function Corral.ReleaseAll()
	for index = #order, 1, -1 do
		Release(order[index])
	end
end

--------------------------------------------------------------------------
-- The tray
--------------------------------------------------------------------------

local function Layout()
	if not tray then
		return
	end
	local rows = math.max(1, math.ceil(#order / COLUMNS))
	local columns = math.min(COLUMNS, math.max(1, #order))
	tray:SetSize(columns * CELL + (columns + 1) * GAP,
		rows * CELL + (rows + 1) * GAP)

	for index, name in ipairs(order) do
		local button = held[name]
		local column = (index - 1) % COLUMNS
		local row = math.floor((index - 1) / COLUMNS)
		-- Through the kept method, because the one on the button is the no-op
		-- that stops it wandering back to the ring.
		local setPoint = button.wkSetPoint or button.SetPoint
		button:ClearAllPoints()
		setPoint(button, "TOPLEFT", tray, "TOPLEFT",
			GAP + column * (CELL + GAP), -(GAP + row * (CELL + GAP)))
	end
end

-- The number on the face, which is the only thing it has to say. Guarded on
-- the value already there, the way every other write in this addon that could
-- be reached more than once a second is.
local function Paint()
	if not countText then
		return
	end
	local text = tostring(#order)
	if countText:GetText() ~= text then
		countText:SetText(text)
	end
end

--------------------------------------------------------------------------
-- Scanning
--
-- Walks the minimap's children twice. The first pass counts name families,
-- because whether a candidate is a button or one pin of five hundred is a fact
-- about its siblings and cannot be decided one frame at a time. The second pass
-- takes what survived.
--
-- Two passes over a list this long is still nothing, and it runs on an addon
-- loading rather than on a clock.
--------------------------------------------------------------------------

local pooled, refused = 0, 0

function Corral.Scan()
	if not tray or not ns.db.minimapCorral then
		return 0
	end
	local map = _G.Minimap
	if type(map) ~= "table" or type(map.GetChildren) ~= "function" then
		return 0
	end

	local ok, children = pcall(function(frame)
		return { frame:GetChildren() }
	end, map)
	if not ok or not children then
		return 0
	end

	local names, families = {}, {}
	for index, frame in ipairs(children) do
		local name = Candidate(frame)
		if name then
			names[index] = name
			local family = Family(name)
			families[family] = (families[family] or 0) + 1
		end
	end

	local taken = 0
	pooled, refused = 0, 0
	for index, frame in ipairs(children) do
		local name = names[index]
		if name then
			if families[Family(name)] > FAMILY then
				pooled = pooled + 1
			elseif #order >= CEILING then
				refused = refused + 1
			elseif Take(name, frame) then
				taken = taken + 1
			end
		end
	end

	if taken > 0 then
		Layout()
		Paint()
	end
	return taken
end

-- What the last scan walked away from. Pins in a pool, and anything past the
-- ceiling. Both are read by the panel, because a corral that quietly declined
-- to collect something is the same defect as one that quietly ate it.
function Corral.Skipped()
	return pooled, refused
end

function Corral.Count()
	return #order
end

function Corral.Names()
	return order
end

--------------------------------------------------------------------------
-- The face
--------------------------------------------------------------------------

local function Toggle()
	if not tray then
		return
	end
	if tray:IsShown() then
		tray:Hide()
		return
	end
	-- Opening is one of the two moments something may have appeared since the
	-- last look, and it is the one the player can cause on purpose.
	Corral.Scan()
	Layout()
	tray:Show()
end

local function Build()
	local map = _G.Minimap
	if type(map) ~= "table" then
		return false
	end

	face = CreateFrame("Button", "WarriorKitCorral", _G.UIParent)
	face:SetSize(FACE, FACE)
	face.bg = ns.Fill(face, "BACKGROUND", UI.Color.control[1], UI.Color.control[2],
		UI.Color.control[3], 1)
	face.bg:SetAllPoints()
	face.edges = ns.Outline(face, UI.Color.edge[1], UI.Color.edge[2], UI.Color.edge[3], 1)
	ns.EdgeSize(face.edges, ns.Pixel(face))

	countText = UI.Label(face, UI.Metric.font, UI.Color.text, "CENTER", UI.FLAT)
	countText:SetPoint("CENTER")

	face:SetScript("OnClick", Toggle)
	face:SetScript("OnEnter", function(self)
		UI.Tint(self.bg, UI.Color.hover)
	end)
	face:SetScript("OnLeave", function(self)
		UI.Tint(self.bg, UI.Color.control)
	end)
	-- No name and no rim, for the reason a window passes none: this is a square
	-- with a number in it that you can see whether it is locked or not, and it
	-- answers the mouse all the time because clicking it is what opens the
	-- tray. The other ten placeable frames are chromeless and need both.
	place = ns.UI.Placeable(face, {
		moved = function(anchor)
			ns.db.corralPoint = anchor
			ns.Options.Refresh()
		end,
	})

	tray = CreateFrame("Frame", nil, _G.UIParent)
	tray.bg = ns.Fill(tray, "BACKGROUND", UI.Color.window[1], UI.Color.window[2],
		UI.Color.window[3], UI.Color.window[4])
	tray.bg:SetAllPoints()
	tray.edges = ns.Outline(tray, UI.Color.edge[1], UI.Color.edge[2], UI.Color.edge[3], 1)
	ns.EdgeSize(tray.edges, ns.Pixel(tray))
	tray:SetPoint("TOPRIGHT", face, "BOTTOMRIGHT", 0, -GAP)
	tray:SetFrameStrata("HIGH")
	tray:Hide()

	return true
end

-- Where the face sits. A dragged position wins; with none it hangs off the
-- bottom left corner of the map, which is under the frame rather than on it,
-- so it does not cover the piece of world the square was widened to show.
--
-- Empty rather than nil for the reason barPoints is empty: the absence of a
-- position is a real state that has to survive a merge with the defaults, and
-- a key whose default is nil is a key the defaults table never carries at all.
local function Place()
	if not face then
		return
	end
	face:ClearAllPoints()
	local saved = ns.db.corralPoint
	if saved and saved[1] then
		face:SetPoint(saved[1], _G.UIParent, saved[3], saved[4], saved[5])
	else
		face:SetPoint("TOPLEFT", _G.Minimap, "BOTTOMLEFT", 0, -GAP)
	end
end

--------------------------------------------------------------------------

function Corral.Apply()
	if not ns.db then
		return
	end
	if not tray and not Build() then
		return
	end

	if ns.db.minimapCorral then
		Place()
		face:Show()
		Corral.Scan()
		Layout()
		Paint()
	else
		Corral.ReleaseAll()
		tray:Hide()
		face:Hide()
		Paint()
	end
end

function Corral.Lock()
	if not face then
		return
	end
	place:Lock(not ns.db.locked)
end

function Corral.Reset()
	ns.db.corralPoint = {}
	Place()
end

-- Whether the face has been dragged off the corner it starts on. The panel
-- reads it so the reset button is only offered when there is something to
-- reset.
function Corral.Moved()
	local saved = ns.db.corralPoint
	return saved ~= nil and saved[1] ~= nil
end

function Corral.Describe()
	if not ns.db.minimapCorral then
		return "off, every addon button stays on the minimap"
	end
	local holding = #order
	local skipped = ""
	if pooled > 0 then
		skipped = (", %d map pins left where they were"):format(pooled)
	end
	if refused > 0 then
		skipped = skipped .. (", %d refused past the ceiling of %d"):format(refused, CEILING)
	end
	if holding == 0 then
		return "on, nothing found to collect yet" .. skipped
	end
	return ("on, holding %d button%s%s"):format(holding, holding == 1 and "" or "s", skipped)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		Corral.Apply()
		Corral.Lock()
		-- The other edge a button may have appeared on, registered only now.
		-- Before login this fires a hundred times and there is no tray to put
		-- anything in; after it, it fires when an on-demand addon loads, which
		-- is exactly when a new button turns up.
		self:RegisterEvent("ADDON_LOADED")
	else
		Corral.Scan()
	end
end)
