local ADDON, ns = ...

local Window = {}
ns.MapWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric
local Chart, Zones, Pins, Mates = UI.Chart, ns.MapZones, ns.MapPins, ns.MapMates

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
-- **The edges of the picture step to the next zone, the way the client's map
-- does.** A zone's art does not stop at the border: it runs a little way into
-- whatever is next to it, and the client keeps a table saying which strip of
-- the picture belongs to which neighbour. That table is what makes a click on
-- the top of Elwynn open Westfall on Blizzard's map, and C_Map will answer it
-- for any point of any map, so it is one call here rather than a list of
-- borders written down. The column is how you cross the world; the edges are
-- how you walk next door, which is the move a map is actually for.
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
-- **The right button steps out to the continent.** The column reaches a zone in
-- one click and the picture reaches the zone next door on a click at its edge,
-- and between them there was no way at all to look at Kalimdor. So every
-- continent has a row of its own at the top of its group, the picture draws it
-- like any other map, and the right button on any zone goes to the one it is
-- on. Left goes in, right goes out, which is the client's own gesture.
--
-- **Your group is on the picture, in their own class colours.** Map/Mates.lua
-- carries that in full. The short of it is that the client will say where a
-- party member is standing on any map you hand it, so the marks cost one call
-- each and nothing is worked out here.
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
-- Your group between the two, so a person is drawn over a camp and under you.
-- Your corpse over all three but under the arrow, because it is the one mark on
-- the picture you are walking towards and losing it under a kobold is losing
-- the only thing the map is being read for.
-- Over a camp because a mark for somebody who is moving is the one on the
-- picture worth not losing under a static one; under you for the reason the
-- arrow is last.
local function Points(map)
	local points = Pins.Of(map)
	local markers = #points
	local mates, placed = Mates.On(map)
	for index = 1, #mates do
		points[#points + 1] = mates[index]
	end
	local dead = Pins.Corpse(map)
	if dead then
		points[#points + 1] = dead
	end
	local here = Pins.You(map)
	if here then
		points[#points + 1] = here
	end
	return points, markers, placed
end

-- The right hand end of the line: what the picture is actually showing.
--
-- A continent gets its own sentence rather than the marker count, because the
-- count would be nought on every one of them and would read as Questie being
-- broken. Questie draws a zone at a time and its frames say which zone, so
-- there is nothing of its to put on a picture of a whole continent.
local function Counted(zone, markers, drawn)
	if drawn == 0 then
		return "this client has no map picture for that zone"
	end
	if zone.whole then
		return "a whole continent, and Questie's markers are drawn a zone at a time"
	end
	if markers == 0 then
		return Pins.Describe()
	end
	if markers >= Pins.Crowd() then
		return ("%d markers, which is as many as one zone gets"):format(markers)
	end
	return ("%d markers"):format(markers)
end

-- And your group on the end of it, where any of them are on this picture.
--
-- A count rather than a list. Which of them is where is on the marks
-- themselves, in the colours they wear everywhere else in the addon, and the
-- number is the half you want without moving the pointer.
local function WithYou(said, mates)
	if mates == 0 then
		return said
	end
	if mates == 1 then
		return said .. ", and one of your group"
	end
	return ("%s, and %d of your group"):format(said, mates)
end

-- The line along the bottom. The level range on the left, because that is what
-- the footer is for, and what the map is actually showing on the right.
local function Footer(zone, markers, mates, drawn)
	if not zone then
		level:SetText("no zone")
		tally:SetText(Zones.Describe())
		return false
	end
	if zone.whole then
		level:SetText(("%s, the whole continent"):format(zone.name))
	else
		level:SetText(("%s, %s"):format(zone.name, Zones.Says(zone.map)))
	end
	tally:SetText(WithYou(Counted(zone, markers, drawn), mates))
	return true
end

function Window.Paint()
	if not window then
		return false
	end
	local zone = Chosen()
	local points, markers, mates = {}, 0, 0
	if zone then
		points, markers, mates = Points(zone.map)
	end
	Footer(zone, markers, mates, board:Draw(zone and zone.map or nil, points))
	return true
end

--------------------------------------------------------------------------
-- The edges
--------------------------------------------------------------------------

-- What map is at that point of this one, which is the client's own answer.
--
-- The same call Blizzard's map makes on a click, and the reason nothing here
-- writes down which zones touch: a zone answers a neighbour where its art runs
-- over the border into one, and a continent answers the zone you pointed at.
-- Probed and pcalled like every other reach into C_Map in this part, because a
-- client that has never heard of the call has to leave a working map behind
-- rather than an error under every click.
local function Beneath(map, x, y)
	local api = _G.C_Map
	if type(api) ~= "table" or type(api.GetMapInfoAtPosition) ~= "function"
		or type(map) ~= "number" then
		return nil
	end
	local ok, info = pcall(api.GetMapInfoAtPosition, map, x, y)
	if not ok or type(info) ~= "table" or type(info.mapID) ~= "number" then
		return nil
	end
	return info.mapID
end

-- A click on the picture, and the zone it moved to.
--
-- Three answers are nothing happening, and each is deliberate. The middle of a
-- zone answers the zone itself, which is most of the map and has to stay a
-- click that does not move you. A dungeon or a micro map has no row in the
-- column, and a window whose picture and column disagreed would be worse than
-- one that ignored the click. And a client that will not answer the call leaves
-- the map exactly as it was.
--
-- The move goes through the column rather than straight to the board, so the
-- name down the left is the zone you are looking at.
local function Stepped(map, x, y)
	local into = Beneath(map, x, y)
	if not into or into == map or not Zones.Find(into) then
		return nil
	end
	return Window.Select(into) and into or nil
end

-- The right button, and the continent it stepped out to.
--
-- Nothing on a continent, because the column has no row above one: the tree is
-- a world of continents of zones and this window draws the bottom two floors of
-- it. A world map of the whole of Azeroth is a picture with three shapes on it
-- and no question it answers that the column does not answer better.
--
-- Through the column, for the reason a click on an edge goes through it: the
-- name down the left is what says where you are, and a picture that had moved
-- without it would be a window disagreeing with itself.
local function Outward(map)
	local above = Zones.Above(map)
	if not above then
		return nil
	end
	return Window.Select(above) and above or nil
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
		zoom = function() return ns.Zoom("mapZoom") end,
		-- The window takes itself back onto the grid and then this lays it out
		-- again, in that order, because every number Fit uses is in the window's
		-- own units and those units are what just changed.
		rescale = function(apply)
			apply()
			Window.Fit()
			Window.Refresh()
		end,
	})
	ns.Remember(window)

	rail = UI.Rail(window.content, { onSelect = Chose })
	-- Named for the reason the quest log's board is: what it draws is twelve
	-- tiles of the client's own art with somebody else's icons over them, and a
	-- map with a seam through it or a marker in the wrong place is only findable
	-- from outside if the tiles and the pins can be walked one at a time.
	board = Chart.New(window.content, "WarriorKitMapChart", Stepped, Outward)
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

-- How many marks are drawn on their side. One is the arrow on a zone you are
-- standing in; anything more is a mark that came out of the pool still turned.
--
-- Handed out for the reason Arrow is, and for a sharper one: the defect it
-- catches is invisible to every other reading. The art is right, the place is
-- right, the zone is right, and the exclamation mark is upside down.
function Window.Turned()
	return board and board:Turned() or 0
end

-- The picture dragged by so many units right and so many up, and how far into
-- it the box is looking afterwards.
--
-- Handed out for the reason Zoom is. What a drag does is invisible from
-- anywhere else: the picture is one canvas inside one box and both of them are
-- the chart's own frames, so a drag that moved nothing, moved the wrong way, or
-- pushed the zone off the edge of its own box all look alike from here.
function Window.Drag(across, up)
	if not board then
		return false
	end
	return board:Drag(across, up)
end

function Window.Where()
	if not board then
		return 0, 0, false
	end
	return board:Where()
end

-- Your corpse: what it is drawn as, how big, and which cell of the sheet it
-- took. Handed out for the reason Arrow is.
function Window.Grave()
	if not board then
		return nil
	end
	return board:Grave()
end

-- A click on the picture, given as two fractions of the zone, and the zone it
-- moved to. Handed out for the reason Zoom is: where the borders of a zone are
-- comes out of a table inside the client, so a click that stepped into the
-- wrong zone or into none at all looks exactly like one that worked, and a
-- harness has no cursor to point at an edge with.
function Window.Tap(x, y)
	if not board then
		return nil
	end
	return board:Tap(x, y)
end

-- The right button on the picture, and the map it stepped out to. Handed out
-- for the reason Tap is: what a step out does is a claim scripts/harness.lua
-- has to be able to make, and a harness has no cursor to press a button with.
function Window.TapOut()
	if not board then
		return nil
	end
	return board:Back()
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
-- Somebody joined or left, which is a mark appearing or going for good. Where
-- they are while they are with you is the board's own tick and not this.
events:RegisterEvent("GROUP_ROSTER_UPDATE")
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
-- Your corpse appearing, moving and going again. The first is the client's own
-- event for it, which is what Blizzard's map registers for its own corpse pin
-- on this build; the other two are release and resurrection, which are the two
-- moments the mark has to go without any position having changed.
events:RegisterEvent("CORPSE_POSITION_UPDATE")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_UNGHOST")
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
