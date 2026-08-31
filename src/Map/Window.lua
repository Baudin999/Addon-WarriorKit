local ADDON, ns = ...

local Window = {}
ns.MapWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric
local Chart, Zones, Pins = UI.Chart, ns.MapZones, ns.MapPins

--------------------------------------------------------------------------
-- The world map
--
-- A column of every zone in the game down the left, the zone you picked drawn
-- beside it, Questie's markers on top of it, and a line along the bottom saying
-- who that zone is for.
--
-- **The zone list is the point.** The client's world map navigates by clicking
-- a continent, reading the shapes, and clicking the piece of coastline you
-- think is the place you meant. That is a fine way to learn a world and a bad
-- way to answer "show me Desolace", which is the question anybody who has
-- played for a week is actually asking. A column of names answers it in one
-- click and never needs the continent map at all.
--
-- The column is a fold, one group per continent, one row per zone, alphabetical
-- inside each. Alphabetical rather than by level, and that is a real choice: a
-- list sorted by level is a better list to plan an evening with and a worse one
-- to find a name in, and the level is on the screen anyway, in the footer,
-- which is the half you cannot get any other way.
--
-- **The picture is the same widget the quest log's map is.** UI/Chart.lua draws
-- a zone out of the client's own tiles and puts points on it, and the wheel
-- zooms it at the cursor. Nothing about it is new here. What is new is what
-- goes on top.
--
-- **The markers are Questie's own, read off Questie's own frames.** Map/Pins.lua
-- carries the argument in full: Questie has already decided which quests you
-- can take and drawn a frame per marker, and this reads the frames rather than
-- asking the database the same question again and getting a different answer.
-- So the map shows exactly what Questie shows, in the same art, with the same
-- colours, and a Questie setting turned off turns them off here too.
--
-- **The footer says who the zone is for.** It is the one fact the client has
-- never put on its own map and the one everybody wants from a world map before
-- level sixty: not where Desolace is, but whether Desolace is where you should
-- be. Map/Zones.lua carries the table and the reason it has to be a table.
--
-- **Everything is built once.** The rail holds sixty rows and the chart holds
-- a pool of tiles and markers, and this client cannot destroy a frame, so a
-- window that rebuilt either on a click would leak a zone's worth of frames per
-- click all evening. It is the same argument the quest log's two scrolling
-- columns make one file across.
--------------------------------------------------------------------------

-- How big the map itself is drawn.
--
-- The client's own zone art is 1002 by 668, which is the size Blizzard's world
-- map draws a zone at, and it is the size this draws one at: the ask was a map
-- the same size as the one it replaces, and the honest way to hold that is to
-- draw the art at its own size rather than to measure somebody else's frame at
-- a scale this window is not on.
--
-- The zone column is extra width rather than width taken off the picture. A
-- selector that made the map smaller would be paying for navigation with the
-- thing being navigated.
local BOARD, SHAPE = 1002, 668 / 1002

-- The window that holds it: the picture, the column, and the same margin on all
-- four sides that every other window in the addon uses.
local WIDTH = BOARD + M.rail + M.pad * 3
local HEIGHT = SHAPE * BOARD + M.title + M.footer + M.pad * 2

local window, rail, board, level, tally
local at, section = 1, 1

-- Whether the column has been built out of a tree yet. It is read in three
-- places and it is the one piece of state the rest of the file turns on: the
-- rail's rows are the tree's rows, in the tree's order, so a walk taken again
-- after the column is filled would renumber what the column is pointing at.
local filled = false

--------------------------------------------------------------------------
-- What is on the board
--------------------------------------------------------------------------

-- Which zone the column is pointing at, or nothing at all on a client that
-- would not walk its own map tree.
local function Chosen()
	local held = Zones.Tree()[at]
	return held and held.zones[section] or nil
end

-- Everything that goes on the picture: Questie's markers, and you on top of
-- them. How many of them are markers comes back as well, because you are not
-- one and the line under the map counts markers.
--
-- You last, so the arrow is drawn over the icons rather than under them. There
-- is nowhere on a quest map you are more likely to be standing than on top of
-- the thing you are looking for. Over the cap as well as over the icons: a zone
-- busy enough to fill the pool is exactly the zone where losing yourself would
-- matter.
local function Points(map)
	local points = Pins.Of(map)
	local markers = #points
	local here = Pins.You(map)
	if here then
		points[#points + 1] = here
	end
	return points, markers
end

-- The line along the bottom. The level range on the left, because that is what
-- the footer is for, and what the map is actually showing on the right.
local function Footer(zone, markers, drawn)
	if not zone then
		level:SetText("no zone")
		tally:SetText(Zones.Describe())
		return false
	end
	level:SetText(("%s, %s"):format(zone.name, Zones.Says(zone.map)))
	if drawn == 0 then
		tally:SetText("this client has no map picture for that zone")
	elseif markers == 0 then
		tally:SetText(Pins.Describe())
	elseif markers >= Pins.Crowd() then
		tally:SetText(("%d markers, which is as many as one zone gets"):format(markers))
	else
		tally:SetText(("%d markers"):format(markers))
	end
	return true
end

function Window.Paint()
	if not window then
		return false
	end
	local zone = Chosen()
	local points, markers = {}, 0
	if zone then
		points, markers = Points(zone.map)
	end
	Footer(zone, markers, board:Draw(zone and zone.map or nil, points))
	return true
end

--------------------------------------------------------------------------
-- The column
--------------------------------------------------------------------------

-- The rail, filled from the tree once there is a tree to fill it from.
--
-- Built on the first open rather than at login, because the client has not
-- finished building its own map tree when this file loads and a rail filled
-- from an empty walk is a rail that stays empty for the session.
local function Fill()
	if filled then
		return false
	end
	local tree = Zones.Tree()
	if #tree == 0 then
		return false
	end
	for _, held in ipairs(tree) do
		local group = rail:Add(held.name)
		for _, zone in ipairs(held.zones) do
			rail:AddChild(group, zone.name)
		end
	end
	filled = true
	return true
end

-- Open the column on the zone you are standing in, which is the one zone a map
-- can guess right. Anywhere the client will not say, or a zone the tree has no
-- row for, opens on the first zone of the first continent.
local function Landing()
	local here = Chart.Here()
	if type(here) ~= "number" then
		return 1, 1
	end
	local group, index = Zones.Find(here)
	return group or 1, index or 1
end

local function Chose(group, index)
	at, section = group, index
	Window.Paint()
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

-- Every part sized off the window, in one place rather than five, because a
-- resolution change has to be able to call it again.
function Window.Fit()
	if not window then
		return false
	end
	local body = window:Body()
	local wide = window.width - M.rail - M.pad * 3

	rail.frame:ClearAllPoints()
	rail.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT", M.pad, -M.pad)
	rail:Resize(M.rail, body - M.pad * 2)

	board.frame:ClearAllPoints()
	board.frame:SetPoint("TOPLEFT", window.content, "TOPLEFT",
		M.pad * 2 + M.rail, -M.pad)
	-- The whole of the body is spare height, because there is nothing under the
	-- map inside the content frame: the level line lives in the window's own
	-- footer. So the wheel can take the picture to the bottom of the window.
	board:Fit(wide, body - M.pad * 2)
	return true
end

local function Chrome()
	level = UI.Label(window.footer, M.font, C.text, "LEFT", UI.FLAT)
	level:SetPoint("LEFT")
	UI.Wrap(level, false)

	tally = UI.Label(window.footer, M.small, C.quiet, "RIGHT", UI.FLAT)
	tally:SetPoint("RIGHT")
	UI.Wrap(tally, false)
end

function Window.Build()
	if window then
		return window
	end

	window = UI.Window({
		name = "WarriorKitMap",
		title = "Map",
		width = WIDTH,
		height = HEIGHT,
	})

	rail = UI.Rail(window.content, { onSelect = Chose })
	-- Named for the reason the quest log's board is: what it draws is twelve
	-- tiles of the client's own art with somebody else's icons over them, and a
	-- map with a seam through it or a marker in the wrong place is only findable
	-- from outside if the tiles and the pins can be walked one at a time.
	board = Chart.New(window.content, "WarriorKitMapChart")
	Chrome()
	Window.Fit()
	return window
end

-- The column filled and pointed at where you are standing, done once per time
-- the window is opened rather than once per session.
--
-- Once per open, because the tree is walked off a client that answers nothing
-- useful until the world is in, and because the zone you are standing in is the
-- right place to open on every time and not only the first.
local function Land()
	Fill()
	if not filled then
		return false
	end
	return rail:Select(Landing())
end

function Window.Show()
	Window.Build()
	if not Land() then
		Window.Paint()
	end
	window:Show()
	return true
end

function Window.Hide()
	if not window then
		return false
	end
	window:Hide()
	return true
end

function Window.Shown()
	return window ~= nil and window:IsShown()
end

function Window.Toggle()
	if Window.Shown() then
		return Window.Hide()
	end
	return Window.Show()
end

-- Redrawn only while it is up. Questie redraws its markers whenever your log
-- changes, and reading two registers to repaint a window nobody has open is the
-- waste this addon has a gate for.
function Window.Refresh()
	if Window.Shown() then
		return Window.Paint()
	end
	return false
end

--------------------------------------------------------------------------

-- One notch of the wheel, from outside. Handed out for the reason the quest
-- log's is: a zoom that did not move, or moved past its own far end, is a claim
-- scripts/harness.lua has to be able to make, and the alternative is this file
-- handing out a reference to the chart's own pools.
function Window.Zoom(delta)
	if not board then
		return 1
	end
	if delta then
		board:Zoom(delta, 0.5, 0.5)
	end
	return board:Level()
end

-- How much of the zone you have uncovered, as the number of pieces drawn over
-- the tiles, and the arrow: what it is drawn as, how big, and where it points.
--
-- Handed out for the reason Zoom is. Both come off the client's own tables
-- through the chart, and a map that drew a dark zone or a north-facing arrow
-- all evening looks exactly like one that drew them right.
function Window.Uncovered()
	return board and board:Seen() or 0
end

function Window.Arrow()
	if not board then
		return nil
	end
	return board:Arrow()
end

-- The arrow taken again, which the board does on its own tick while it is up
-- and nothing outside a running client can drive.
function Window.Locate()
	return board ~= nil and board:Locate()
end

-- How many markers are on the board, and how big it came out.
function Window.Drawn()
	if not board then
		return 0, 0, 0
	end
	return board:Drawn()
end

-- What the two lines along the bottom say.
--
-- Handed out for the reason Zoom is. The level range is the one thing on this
-- window that comes from a table rather than from the client, so a claim about
-- it has to be makeable from outside, and the alternative is this file handing
-- over its own font strings.
function Window.Says()
	if not level then
		return "", ""
	end
	return level:GetText() or "", tally:GetText() or ""
end

-- Which zone is up, as the map id rather than the name, because a name is a
-- localisation and a map id is a fact.
function Window.Showing()
	local zone = Chosen()
	return zone and zone.map or nil
end

-- Where the column is pointing, so a caller outside can move it. Its own
-- function rather than a reference to the rail, for the reason Zoom is.
function Window.Select(map)
	local group, index = Zones.Find(map)
	if not group or not window then
		return false
	end
	return rail:Select(group, index)
end

function Window.Describe()
	if not ns.db.worldMap then
		return "off"
	end
	if not window then
		return "not built yet"
	end
	return Window.Shown() and "open" or "closed"
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("QUEST_LOG_UPDATE")
-- Walking into somewhere you have not been repaints the map, because what the
-- client uncovered is drawn from its own tables and it has just changed them.
-- The border crossing is here for the same reason one layer down: the zone you
-- are standing in decides whether the arrow is on this picture at all, and the
-- tick that moves the arrow cannot put one on a board that was drawn without.
--
-- Probed rather than assumed, the way every other call into the client in this
-- part is. An event name this build has never heard of raises out of
-- RegisterEvent, and the one taken down with it would be the whole window.
pcall(events.RegisterEvent, events, "MAP_EXPLORATION_UPDATED")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		if ns.db.worldMap then
			Window.Build()
		end
		-- The cage and the key go on at login rather than when this window is
		-- first opened, for the reason Quests/Blizzard.lua gives: Blizzard's map
		-- has to be gone before anything can put it on the screen, and M has to
		-- open this one before the first press.
		ns.MapBlizzard.Apply()
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		-- The tree walked again on the far side of a loading screen, and only
		-- while the column has not been built out of one. It is built out of a
		-- client that answers nothing useful until the world is in, so an early
		-- walk is worth throwing away; a later one is not, because the rail's
		-- rows are that tree's rows and a second walk would renumber them under
		-- a column that is already pointing at one.
		if not filled then
			Zones.Forget()
		end
		return
	end
	Window.Refresh()
end)

-- The grid moved: the screen changed size, combat let go of a frame, or the
-- player dragged the UI size slider. The window is taken back onto the grid at
-- the new zoom and then laid out again, in that order, because every number Fit
-- uses is in the window's own units and those units are what just changed.
UI.OnRescale(function()
	if not window then
		return
	end
	UI.Rezoom(window.frame, UI.WindowZoom())
	window.zoom = UI.WindowZoom()
	Window.Fit()
	Window.Refresh()
end)
