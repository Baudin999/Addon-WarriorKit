-- The world map
--
-- Six questions no amount of reading Map/ will answer.
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
check(table.concat(names, ", ") == "Elwynn Forest, Stormwind City, Westfall",
	("the first continent's zones came out as %q"):format(table.concat(names, ", ")))

-- The client hands them over by id descending, which is none of the three
-- orders a reader could mistake for alphabetical.
check(first[1] and first[1].map == ELWYNN,
	"the column is in the order the client handed the zones over")

local group, index = Zones.Find(WESTFALL)
check(group == 1 and index == 3,
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

ns.db.worldMapHideBlizz = false
Blizz.Apply()
check(not Blizz.Caged(), "the switch would not let Blizzard's map back out")
check(not ns.Attic.Held(_G.WorldMapFrame), "the client's map is still in the attic")
_G.ToggleWorldMap()
check(worldmap.Opened() == before + 1,
	"the switch did not hand the M key back to the client")

ns.db.worldMapHideBlizz = true
Blizz.Apply()

print(("map    %d zones over %d continents, %d with a level range")
	:format(zones, continents, (select(2, Zones.Ranged()))))
print(("map    %s; %s"):format(Window.Describe(), Pins.Describe()))
print(("map    %d pieces of Westfall uncovered, you drawn as the client's own arrow")
	:format(Window.Uncovered()))
