-- The world map
--
-- Nine questions no amount of reading Map/ will answer.
--
-- Does the column come out of the client's own tree. Every zone in the game is
-- a walk over C_Map rather than a list written down, so a walk that stopped at
-- the wrong node draws a column that is empty, or one continent short, and
-- looks deliberate either way.
--
-- Is it sorted. The client hands its children over in whatever order its own
-- table is in, which is no order at all in a column of thirty names, and a sort
-- that quietly did nothing is invisible next to one that worked.
--
-- Do Questie's markers reach the picture, and only the right ones. This reads
-- another addon's frames, and four of the five things that can be wrong are
-- things that draw too much rather than too little: the minimap's copy of every
-- marker, the ones Questie has hidden, the ones in another zone, and the second
-- register nobody remembers exists.
--
-- Does the footer say who the zone is for. It is the one line on the window
-- that does not come from the client, so it is the one line that can be wrong
-- without anything else being wrong, and all three of its answers matter: a
-- range, a city, and a place the table has never heard of.
--
-- Does the wheel zoom, and does stepping to another zone throw the zoom away.
-- The picture is the same widget the quest log's map is and this is the second
-- caller of it, which is the point at which a widget's state stops being
-- private to one window.
--
-- Do the edges of the picture open the zone next door. The client keeps the
-- borders and this window asks for them on a click, so an edge that stepped
-- into the wrong zone, or into a map the column cannot show, or nowhere at all,
-- looks exactly like an edge that worked.
--
-- Does the right button step out to the continent, and is the continent a place
-- the window can actually draw. Left goes in and right goes out, and the row a
-- continent gets at the top of its own group is what the right button lands on:
-- a step out that moved the picture and not the column is a window disagreeing
-- with itself, and one that moved neither is the gesture doing nothing.
--
-- Is your group on the picture. The client places a party member on any map you
-- hand it, which is one call each and nothing worked out here, and everything
-- that can go wrong with it is silent: the wrong people, nobody at all, or a
-- mark that stays where somebody was standing when the map was painted.
--
-- And is Blizzard's map out of the way with the M key pointing here. A hidden
-- map with the key still bound to the client's own toggle is a map you cannot
-- open, which is worse than either window on its own.

local H = ...
local ns, check = H.ns, H.check
local worldmap, quests = H.worldmap, H.quests

local Window, Zones, Pins = ns.MapWindow, ns.MapZones, ns.MapPins

-- The ids the client stub's tree is built on, which are the ids these two
-- clients really use. Named here rather than written into every assertion,
-- because a number in a message is a number nobody can read.
local WESTFALL, ELWYNN, STORMWIND = 1436, 1429, 1453
local DUROTAR, NOWHERE = 1411, 9001
local KINGDOMS, COSMIC = 1415, 946

----------------------------------------------------------------------
-- The tree
----------------------------------------------------------------------

local continents, zones = Zones.Count()
check(continents == 2,
	("the walk found %d continents where the client has two"):format(continents))
check(zones == 5,
	("the walk found %d zones where the client has five"):format(zones))

local tree = Zones.Tree()
local first = tree[1] and tree[1].zones or {}
local names = {}
for index, zone in ipairs(first) do
	names[index] = zone.name
end
check(table.concat(names, ", ")
	== "Eastern Kingdoms, Elwynn Forest, Stormwind City, Westfall",
	("the first continent's rows came out as %q"):format(table.concat(names, ", ")))

-- The continent's own row, first, and marked as the thing the others are inside
-- rather than one of them. Everything that counts zones has to skip it: five is
-- what the client holds and seven is what the column shows.
check(first[1] and first[1].whole and first[1].map == KINGDOMS,
	"the first row of a continent's group is not the continent itself")

-- The client hands them over by id descending, which is none of the three
-- orders a reader could mistake for alphabetical.
check(first[2] and first[2].map == ELWYNN,
	"the column is in the order the client handed the zones over")

check(Zones.Above(WESTFALL) == KINGDOMS,
	("Westfall came back as being on %s"):format(tostring(Zones.Above(WESTFALL))))
check(Zones.Above(KINGDOMS) == nil,
	"a continent answered something above it, and the column has no row above one")

local group, index = Zones.Find(WESTFALL)
check(group == 1 and index == 4,
	("Westfall is at %s, %s in the column"):format(tostring(group), tostring(index)))
check(Zones.Find(90210) == nil, "a map id nothing holds was found in the column")

----------------------------------------------------------------------
-- Where it opens
----------------------------------------------------------------------

-- Standing in Westfall, which the tree holds, so the window has a zone to guess
-- and it is not the first one in the column.
quests.standing.map = WESTFALL
quests.standing.x, quests.standing.y = 48, 52

Window.Show()
check(Window.Shown(), "the map did not open")
check(Window.Showing() == WESTFALL,
	("the map opened on %s rather than on the zone you are standing in")
		:format(tostring(Window.Showing())))

----------------------------------------------------------------------
-- Questie's markers
----------------------------------------------------------------------

-- Five frames are registered and two of them belong on Westfall: one out of the
-- quest register and one out of the manual one. The other three are the three
-- ways to draw too much.
local points = Pins.Of(WESTFALL)
check(#points == 2,
	("Westfall took %d of Questie's markers where two of the five are its")
		:format(#points))

local seen = {}
for _, point in ipairs(points) do
	seen[point.name] = point
end
check(seen["Kobold Miner"] ~= nil, "the quest register's marker is not on the map")
check(seen["Thor"] ~= nil, "the manual register's marker is not on the map")
check(seen["Hidden Miner"] == nil, "a marker Questie has hidden was drawn")
check(seen["Hogger"] == nil, "a marker in another zone was drawn on this one")

-- Questie's own art and Questie's own colour, rather than a dot of this
-- addon's. Drawing them as squares would lose what the icon says, which is the
-- difference between a quest to pick up and a thing to kill.
local miner = seen["Kobold Miner"]
check(miner and miner.icon == "Questie/Icons/available",
	"the marker is not carrying Questie's own texture")
check(miner and miner.tint and miner.tint[1] == 1 and miner.tint[2] == 0.75,
	"the marker is not carrying the colour Questie tinted it")
check(miner and miner.note and miner.note[1] == "Kobold Camp",
	"the hover does not name the quest the marker came from")

-- You, on top of them, and only on the zone you are standing in.
check(Pins.You(WESTFALL) ~= nil, "you are not on the map of the zone you are in")
check(Pins.You(ELWYNN) == nil, "you were drawn on a zone you are not in")

local drawn = Window.Drawn()
check(drawn == 3,
	("the board is showing %d marks where it has two markers and you"):format(drawn))

----------------------------------------------------------------------
-- Where a mark's box opens
--
-- On the mark, whatever the tooltip setting says. Which camp a dot is is a
-- question about nine pixels of a picture of a zone, and an answer in the
-- bottom right corner of the screen is one you read with the cursor off the
-- map, having lost the dot you were on. Above the dot rather than beside it,
-- because a mark is half the size of the pointer and the arrow hangs down and
-- to the right of its own hotspot.
--
-- A board of its own rather than the window's, because the window will not hand
-- out the chart's pools and should not start. What is asserted is the chart's
-- pin, which is the same pin either board draws.
----------------------------------------------------------------------

do
	local Box = ns.UI.Tooltip
	local function pixels(region, method)
		return ns.Measure(region, method) * region:GetEffectiveScale()
	end

	check(Box.Place() == Box.DOCK,
		"the setting is not on the corner, so this claim proves nothing")

	local probe = ns.UI.Chart.New(_G.UIParent, "WarriorKitMapHoverProbe")
	probe:Fit(400, 300)
	probe:Draw(WESTFALL, points)
	check(probe:Hover(1), "the board would not put the pointer on its first mark")

	local mark, box = Box.Owner(), Box.Frame()
	check(mark ~= nil and box ~= nil and box:IsShown(),
		"hovering a mark on the map opened no box")
	check(Box.Placed() == Box.BESIDE,
		("a mark's box went %s rather than onto the mark"):format(tostring(Box.Placed())))
	check(pixels(box, "GetBottom") >= pixels(mark, "GetTop") - 1,
		"a mark's box opened over the dot rather than above it, under the pointer")
	Box.Close(true)
end

----------------------------------------------------------------------
-- You, and which way you are pointing
----------------------------------------------------------------------

-- The client's own arrow rather than a square of this addon's colour, at the
-- size Blizzard draws its own player pin. A square says where you are standing
-- and an arrow says that and which way you are facing, and the second half is
-- what the map was missing.
--
-- Scoped, for the reason every other block in harness/sections is: a chunk gets
-- two hundred names in this Lua and the budget in check.sh is what keeps the
-- count off that ceiling.
do
	local art, size, turn = Window.Arrow()
	check(art == "Interface\\WorldMap\\WorldMapArrow",
		("you are drawn as %q rather than as the client's own arrow")
			:format(tostring(art)))
	check(size == 16, ("the arrow came out %s pixels and Blizzard's is sixteen")
		:format(tostring(size)))
	check(turn == 0, ("the arrow opened turned %s and you are facing north")
		:format(tostring(turn)))

	-- Turned, and moved, without a repaint. This is the whole reason the board
	-- keeps a tick of its own: everything else on the picture is a fact about
	-- the zone and changes when somebody asks, and where you are standing
	-- changes because you walked.
	worldmap.Face(math.pi / 2)
	quests.standing.x, quests.standing.y = 70, 30
	check(Window.Locate(), "the board would not take the arrow again")
	local _, _, west = Window.Arrow()
	check(west == math.pi / 2,
		("a quarter turn west left the arrow at %s"):format(tostring(west)))
end

-- Off the board on a zone you are not in, and off it without a repaint, so
-- crossing a border with the map open takes the arrow with you rather than
-- leaving it at the crossing.
quests.standing.map = ELWYNN
check(Window.Locate(), "the board would not take the arrow again after the border")
check(Window.Arrow() == nil, "you are still on the map of a zone you have left")
check(Window.Drawn() == 2,
	("the board is showing %d marks where you have left the zone")
		:format(Window.Drawn()))

quests.standing.map = WESTFALL
quests.standing.x, quests.standing.y = 48, 52
worldmap.Face(0)
Window.Paint()

----------------------------------------------------------------------
-- What you have uncovered
----------------------------------------------------------------------

-- The zone is drawn twice: the tiles, which are the whole map with nothing
-- discovered on it, and one piece per area you have walked into painted over
-- them. Draw only the tiles and the map is the one you had at level one for the
-- whole game, which is what it was before this.
check(Window.Uncovered() == 3,
	("the board painted %d pieces of uncovered ground where Westfall has two areas, one of them two tiles wide")
		:format(Window.Uncovered()))

-- A zone you have never walked stays dark. The client answers nothing for it
-- and nothing is exactly what should be drawn: the ask was what has been
-- discovered, not everything.
check(Window.Select(DUROTAR), "the column would not move to the other continent")
check(Window.Uncovered() == 0,
	("a zone you have never walked painted %d pieces over its tiles")
		:format(Window.Uncovered()))

Window.Select(WESTFALL)

----------------------------------------------------------------------
-- The footer
----------------------------------------------------------------------

local says, count = Window.Says()
check(says == "Westfall, for levels 10 to 20",
	("the footer says %q"):format(says))
-- Two markers and you, and the count is of markers. You are not one of
-- Questie's and a line that counted you would say three of a zone with two.
check(count == "2 markers",
	("the footer counts %q where the zone has two markers and you"):format(count))

check(Window.Select(STORMWIND), "the column would not move to Stormwind City")
says = Window.Says()
check(says == "Stormwind City, a city, so no level range",
	("a city's footer says %q"):format(says))

check(Window.Select(DUROTAR), "the column would not move to the other continent")
check(Window.Says() == "Durotar, for levels 1 to 10",
	("the second continent's footer says %q"):format(Window.Says()))

-- The zone the client names and this addon has no row for. It has no art
-- either, which is the other half of the same picture: the board collapses and
-- the second line says why rather than leaving a rectangle of nothing.
check(Window.Select(NOWHERE), "the column would not move to the zone with no art")
check(Window.Says() == "Somewhere Else, no level range known for this place",
	("an unknown zone's footer says %q"):format(Window.Says()))
local _, note = Window.Says()
check(note == "this client has no map picture for that zone",
	("a zone with no art says %q under it"):format(note))
check(Window.Drawn() == 0, "a zone with no picture still drew marks on it")

----------------------------------------------------------------------
-- The wheel
----------------------------------------------------------------------

Window.Select(WESTFALL)
check(Window.Zoom() == 1, "the map did not open at rest")
check(Window.Zoom(1) > 1, "one notch of the wheel did not zoom the map")

for _ = 1, 20 do
	Window.Zoom(1)
end
local deepest = Window.Zoom()
check(deepest == 6,
	("twenty notches took the zoom to %s and the far end is six"):format(tostring(deepest)))

-- Kept across a repaint of the same zone and thrown away on a move to another
-- one, which is the rule UI/Chart.lua states and the second caller is the first
-- thing that could break it.
Window.Paint()
check(Window.Zoom() == deepest, "repainting the same zone threw the zoom away")
Window.Select(ELWYNN)
check(Window.Zoom() == 1, "stepping to another zone kept the last one's zoom")

----------------------------------------------------------------------
-- The edges
----------------------------------------------------------------------

-- A click on the picture asks the client what is under it and moves the column
-- there. Four answers, and three of them are the map staying where it is: the
-- middle of a zone is that zone, a click that lands on something the column has
-- no row for is not a place this window can show, and a client with nothing to
-- say leaves the map alone. The one that moves has to move the column as well
-- as the picture, because a name down the left pointing at another zone is a
-- window disagreeing with itself.
--
-- Every click is taken once and kept. A click has a side effect, and a second
-- one taken to write the message would step back over the border the first one
-- crossed, which is a check that moves what it is measuring.

-- Scoped, because every name here is a click's answer kept for one comparison
-- and a chunk in Lua 5.1 has two hundred locals to spend on the whole file.
do
	Window.Select(WESTFALL)
	local stayed = Window.Tap(0.5, 0.5)
	check(stayed == nil,
		("a click in the middle of Westfall stepped to %s"):format(tostring(stayed)))
	check(Window.Showing() == WESTFALL,
		("a click in the middle of a zone left the map on %s")
			:format(tostring(Window.Showing())))

	local stepped = Window.Tap(0.02, 0.5)
	check(stepped == ELWYNN,
		("a click on Westfall's border answered %s and the zone next door is Elwynn Forest")
			:format(tostring(stepped)))
	-- Showing reads the column rather than the board, so this is the half a
	-- screenshot of the picture would not settle: the name down the left moved too.
	check(Window.Showing() == ELWYNN,
		("the border was clicked and the column is pointing at %s")
			:format(tostring(Window.Showing())))

	-- Somewhere the client can name and this column cannot show. The stub answers
	-- the cosmic map on Stormwind's border, which is a real map and is the floor
	-- above the one this window draws: continents and zones, and nothing over
	-- them.
	Window.Select(STORMWIND)
	local nowhere = Window.Tap(0.02, 0.5)
	check(nowhere == nil,
		("a click stepped onto %s, which the column has no row for"):format(tostring(nowhere)))
	check(Window.Showing() == STORMWIND,
		("a click onto the cosmic map left the map on %s"):format(tostring(Window.Showing())))
	check(COSMIC ~= nil, "the cosmic map has no id, so the claim above proves nothing")

	-- A zone the client has no picture for is still a place, and the click has to
	-- reach it: the footer is what says the picture is missing, not the column.
	Window.Select(DUROTAR)
	local blank = Window.Tap(0.02, 0.5)
	check(blank == NOWHERE,
		("a click on Durotar's border answered %s and the zone next door has no picture")
			:format(tostring(blank)))
	check(Window.Says() == "Somewhere Else, no level range known for this place",
		("stepping into the zone with no picture says %q"):format(Window.Says()))

	-- And a client that has never heard of the call leaves a working map behind
	-- rather than an error under every click.
	local answering = _G.C_Map.GetMapInfoAtPosition
	_G.C_Map.GetMapInfoAtPosition = nil
	Window.Select(WESTFALL)
	local unasked = Window.Tap(0.02, 0.5)
	_G.C_Map.GetMapInfoAtPosition = answering
	check(unasked == nil,
		("a client with no call to ask stepped to %s"):format(tostring(unasked)))
	check(Window.Showing() == WESTFALL,
		("a client with no call to ask left the map on %s"):format(tostring(Window.Showing())))
end

----------------------------------------------------------------------
-- The continent
----------------------------------------------------------------------

-- Right steps out, left steps in, and the continent in between is a picture
-- like any other. The gesture is the client's own and it is the half of
-- navigating a map this window did not have: the column reaches any zone in one
-- click and could not reach Kalimdor at all.
do
	Window.Select(WESTFALL)
	local out = Window.TapOut()
	check(out == KINGDOMS,
		("the right button on Westfall stepped to %s"):format(tostring(out)))
	-- Showing reads the column, so this is the half a screenshot would not
	-- settle: the name down the left moved with the picture.
	check(Window.Showing() == KINGDOMS,
		("the right button moved the picture and the column says %s")
			:format(tostring(Window.Showing())))

	local says, count = Window.Says()
	check(says == "Eastern Kingdoms, the whole continent",
		("a continent's footer says %q"):format(says))
	-- Not the marker count, which is nought on every continent there is:
	-- Questie draws a zone at a time and a line reading "no markers" over a
	-- picture of Eastern Kingdoms is a bug report about Questie.
	check(count == "a whole continent, and Questie's markers are drawn a zone at a time",
		("a continent counts %q"):format(count))

	-- You are on it. The client places a unit against whatever map it is handed,
	-- so the continent answers for anybody standing anywhere on it, and this is
	-- the reading that catches a window asking about the zone you are in
	-- instead: the arrow would be on Westfall and nowhere else.
	check(Window.Drawn() == 1,
		("the continent is showing %d marks and you are standing on it")
			:format(Window.Drawn()))

	-- And the way back in. A click on a continent is a click on a zone.
	local into = Window.Tap(0.02, 0.5)
	check(into == WESTFALL,
		("a click on the continent stepped to %s"):format(tostring(into)))

	-- The right button on a continent does nothing, because there is no row
	-- above one. A gesture that fell off the top of the column would be a
	-- picture the column could not name.
	Window.Select(KINGDOMS)
	check(Window.TapOut() == nil,
		"the right button stepped out of a continent, and the column has no row above one")
end

Window.Select(ELWYNN)

----------------------------------------------------------------------
-- More markers than one zone gets
----------------------------------------------------------------------

worldmap.Flood(Pins.Crowd() + 40, ELWYNN)
local flooded = Pins.Of(ELWYNN)
check(#flooded == Pins.Crowd(),
	("a flooded zone took %d markers and the cap is %d")
		:format(#flooded, Pins.Crowd()))

Window.Paint()
local _, capped = Window.Says()
check(capped == "250 markers, which is as many as one zone gets",
	("a flooded zone's footer says %q"):format(capped))

local _, wide, tall = Window.Drawn()
check(wide == 1002 and tall > 0,
	("the board came out %d by %d and the picture is 1002 across"):format(wide, tall))

-- The turn-in survives the crowd, and it is drawn over the crowd.
--
-- A question mark dropped into a zone that is already past the cap. Cutting the
-- list as the registers are walked keeps whichever markers the hash handed over
-- first, which loses this one about as often as it keeps it; cutting it by what
-- the marker is keeps it every time. Last in the list as well as in it, because
-- the board draws in order and the turn-in shares its coordinate with objective
-- dots more often than not.
worldmap.TurnIn(ELWYNN, "The Quartermaster")
flooded = Pins.Of(ELWYNN)
check(#flooded == Pins.Crowd(),
	("a flooded zone with a turn-in in it took %d markers and the cap is %d")
		:format(#flooded, Pins.Crowd()))
check(flooded[#flooded] and flooded[#flooded].name == "The Quartermaster",
	("the last mark on a flooded zone is %q and it should be the turn-in")
		:format(flooded[#flooded] and flooded[#flooded].name or "nothing"))

----------------------------------------------------------------------
-- A mark that was the arrow
----------------------------------------------------------------------

-- The pins are pooled and the arrow is the only mark on the board that is ever
-- turned, so the pin that was the arrow on one zone is one of Questie's icons
-- on the next. It came back still on its side, and what that looks like in a
-- game is an exclamation mark upside down over a zone you walked into facing
-- south.
--
-- It could not be caught here until the stub grew SetRotation. The angle the
-- arrow is drawn at was kept in the addon's own field, which is what
-- Window.Arrow reads, so the write to the texture was the one thing on this
-- window no run had ever touched.
do
	quests.standing.map = WESTFALL
	quests.standing.x, quests.standing.y = 48, 52
	worldmap.Face(math.pi)
	Window.Select(WESTFALL)
	check(Window.Turned() == 1,
		("%d marks are on their side on a zone you are standing in facing south, and only the arrow is ever turned")
			:format(Window.Turned()))

	-- Elwynn is holding more markers than Westfall has marks, so the pin the
	-- arrow was is one of Questie's icons now.
	Window.Select(ELWYNN)
	check(Window.Turned() == 0,
		("%d of Elwynn's markers came out of the pool still turned")
			:format(Window.Turned()))

	worldmap.Face(0)
	Window.Select(WESTFALL)
end

----------------------------------------------------------------------
-- Your group
----------------------------------------------------------------------

-- Two people, one of them here. Every member of the group is handed over and
-- the ones the client will not place are drawn nowhere, which is what lets the
-- board put a mark up on its own tick when somebody walks into the zone: a list
-- of only the people who were here when the map was painted makes leaving work
-- and arriving wait for a repaint.
do
	local Mates = ns.MapMates
	H.group.Set({
		{ token = "player", you = true, name = "Tusksfirst", class = "WARRIOR" },
		{ token = "party1", name = "Sneaky", class = "ROGUE" },
		{ token = "party2", name = "Lightwell", class = "PRIEST" },
	}, false)
	worldmap.Stand("party1", WESTFALL, 20, 30)
	worldmap.Stand("party2", ELWYNN, 40, 50)
	H.fire("GROUP_ROSTER_UPDATE")

	local mates, placed = Mates.On(WESTFALL)
	check(#mates == 2,
		("%d of the group came back where two of them are with you"):format(#mates))
	check(placed == 1,
		("%d of them were placed on Westfall and one is standing in it"):format(placed))
	check(mates[1] and mates[1].name == "Sneaky" and mates[1].x == 20,
		"the one standing in the zone is not on the picture where the client put them")
	check(mates[2] and mates[2].x == nil,
		"the one standing in another zone was given a place on this one")

	-- You are not one of them. You are already the client's own arrow, and a
	-- square under it would only say where the arrow is.
	for _, mate in ipairs(mates) do
		check(mate.name ~= "Tusksfirst", "you were drawn twice, as the arrow and as a square")
	end

	-- Their own colours, which is what makes a mark answer "the healer has not
	-- moved" rather than "somebody is over there".
	check(mates[1].tint and mates[2].tint and mates[1].tint ~= mates[2].tint,
		"a rogue and a priest are drawn in the same colour")

	Window.Paint()
	local _, count = Window.Says()
	check(count == "2 markers, and one of your group",
		("the footer counts %q where one of the group is on the zone"):format(count))
	check(Window.Drawn() == 4,
		("the board is showing %d marks: two markers, you, and one of the group")
			:format(Window.Drawn()))

	-- Somebody walks in, and the mark arrives on the tick rather than on a
	-- repaint. Nothing here paints the window: this is the board taking every
	-- point that names a unit again, which is the same tick that turns the
	-- arrow.
	worldmap.Stand("party2", WESTFALL, 60, 70)
	check(Window.Locate(), "the board would not take the people on it again")
	check(Window.Drawn() == 5,
		("%d marks after somebody walked into the zone with the map open")
			:format(Window.Drawn()))

	-- And out again, without a repaint either.
	worldmap.Stand("party1", ELWYNN, 20, 30)
	Window.Locate()
	check(Window.Drawn() == 4,
		("%d marks after somebody walked out of the zone with the map open")
			:format(Window.Drawn()))

	-- The continent answers for both of them, because it answers for anybody
	-- standing anywhere on it. This is the one reading that says the party is on
	-- the continent picture and not only on the zone one.
	check(select(2, Mates.On(KINGDOMS)) == 2,
		("%d of the group were placed on the continent and both are on it")
			:format(select(2, Mates.On(KINGDOMS))))

	check(Mates.Describe() == "2 with you, 1 of them on the zone you are in",
		("the reading says %q"):format(Mates.Describe()))

	worldmap.Stand("party1", nil)
	worldmap.Stand("party2", nil)
	H.group.Forget()
	H.fire("GROUP_ROSTER_UPDATE")
	check(Mates.Describe() == "you are on your own, so there is nobody else to draw",
		("out of a group the reading says %q"):format(Mates.Describe()))
	Window.Paint()
end

----------------------------------------------------------------------
-- Blizzard's map
----------------------------------------------------------------------

local Blizz = ns.MapBlizzard
check(Blizz.Caged(), "Blizzard's world map is not in the attic")
check(ns.Attic.Held(_G.WorldMapFrame), "the attic is not holding the client's map")
check(Blizz.Describe() == "in the attic, and M opens this one",
	("the switch says %q"):format(Blizz.Describe()))

-- The key. The client's own toggle must not run while this addon is holding it,
-- and it must run again the moment the switch hands it back, which is the only
-- way to prove the original was kept rather than rebuilt.
Window.Hide()
local before = worldmap.Opened()
_G.ToggleWorldMap()
check(Window.Shown(), "the M key did not open this addon's map")
check(worldmap.Opened() == before, "the M key reached the client's own map as well")
_G.ToggleWorldMap()
check(not Window.Shown(), "the M key did not close this addon's map")

-- The same key inside a dungeon opens the other window. Neither of these
-- clients has a world map of an instance at all, so M underground used to open
-- a map that could only draw the continent overhead.
do
	local guide = ns.DungeonWindow
	local standing = quests.standing.map
	Window.Hide()
	guide.Hide()
	guide.Back()
	quests.standing.map = 291
	_G.ToggleWorldMap()
	check(not Window.Shown(), "M in a dungeon opened the world map")
	check(guide.Shown() and guide.Page() == "dungeon",
		("M in a dungeon left the guide %s"):format(guide.Describe()))
	_G.ToggleWorldMap()
	check(not guide.Shown(), "M did not close the guide again")
	guide.Back()
	quests.standing.map = standing
end

ns.db.worldMapHideBlizz = false
Blizz.Apply()
check(not Blizz.Caged(), "the switch would not let Blizzard's map back out")
check(not ns.Attic.Held(_G.WorldMapFrame), "the client's map is still in the attic")
_G.ToggleWorldMap()
check(worldmap.Opened() == before + 1,
	"the switch did not hand the M key back to the client")

ns.db.worldMapHideBlizz = true
Blizz.Apply()

----------------------------------------------------------------------
-- Where a finished quest's question mark went
----------------------------------------------------------------------

-- The picture cannot answer this and neither can Pins.Of, which hands back the
-- markers that survived and says nothing about the ones that did not. Four
-- quests, and each is one of the four things a missing question mark turns out
-- to be.
worldmap.TurnIn(WESTFALL, "Gryan Stoutmantle", 6002)
check(Pins.Chase(6002, WESTFALL):find("^its turn%-in is on Westfall"),
	("a turn-in on the zone you are on reads %q"):format(Pins.Chase(6002, WESTFALL)))
check(Pins.Chase(201, WESTFALL) == "nothing on Westfall; Questie has 1 on Elwynn Forest",
	("a quest whose markers are in another zone reads %q"):format(Pins.Chase(201, WESTFALL)))
check(Pins.Chase(102, WESTFALL) ==
	"1 marker(s) on Westfall (1 monster) and none of them a turn-in; Questie has hidden 1 more",
	("a quest with a hidden marker reads %q"):format(Pins.Chase(102, WESTFALL)))
check(Pins.Chase(9999, WESTFALL) == "Questie holds no marker for it",
	("a quest Questie never drew reads %q"):format(Pins.Chase(9999, WESTFALL)))

print(("map    %d zones over %d continents, %d with a level range")
	:format(zones, continents, (select(2, Zones.Ranged()))))
print(("map    %s; %s"):format(Window.Describe(), Pins.Describe()))
print(("map    %d pieces of Westfall uncovered, you drawn as the client's own arrow")
	:format(Window.Uncovered()))
