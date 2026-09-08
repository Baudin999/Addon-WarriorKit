-- The map behind the quest log's tab
--
-- Its own section rather than the last third of 47-quest-log.lua, and the split
-- is by subject rather than by size. Everything above it is the log: a flat run
-- of rows folded into zones, a cursor the whole client shares, one quest's own
-- text and the numbers inside its objectives. This is a picture of a zone with
-- Questie's answer drawn on it, and the only thing the two have in common is
-- the window they are in.
--
-- Straight under that section and before 47-quest-pin.lua, because it reads the
-- log exactly as 47-quest-log.lua leaves it: the window on screen, the quest
-- Questie has spawns for still in it, and the cursor put back.

local H = ...
local ns, check, quests = H.ns, H.check, H.quests

local Log, Window = ns.QuestLog, ns.QuestWindow

----------------------------------------------------------------------

-- Six questions the drawing cannot answer and reading it will not either.
--
-- Does the join hold. A spawn is keyed on the area id the server uses, the
-- picture is keyed on the map id the client's atlas uses, and the only thing
-- between them is a table inside Questie. A part that read one id as the other
-- draws the right dots on the wrong zone, and every dot is still in the
-- rectangle, so nothing about the geometry would say so.
--
-- Does it thin the crowd out. Forty database rows inside one camp is one place
-- on a map at this size, and a part that drew all forty makes forty frames on a
-- client that cannot destroy one. The stub puts two spawns inside one step for
-- exactly this.
--
-- Does it leave things off. A spawn Questie marks -1 is inside an instance and
-- lands in the corner of the zone if it is drawn; a finished objective's camps
-- are the half of the answer that hides the other half; a zone with no map id
-- is not a zone anything can draw. All three are in the stub's data.
--
-- Does the picture get cropped. A zone is 1002 pixels of art in tiles of 256,
-- so the last column and the last row are part tiles padded out to full size,
-- and drawing them whole puts two black seams through every map in the game.
--
-- And does the wheel work. A zone at the width of one column is three hundred
-- pixels across a place that takes twenty minutes to walk, so the picture is
-- allowed to grow inside a box that does not, and every part of that is a
-- number: the far end, the box against the column, the dots against the
-- picture, and which of the two the zoom belongs to.
--
-- And do the marks come out as Questie's own art. The map beside this one
-- reads its icons off Questie's frames; this one is built out of the database
-- and has to resolve them from what the data names, which is a number on a
-- live spawn list and a kind on a database row. A mark that fell back to a
-- coloured square is a picture that draws in the right place and says nothing.
local diplomat = Log.Zones()[1].quests[1].key
local zones = ns.QuestWhere.Places(102)
local deepest = 1

check(#zones == 2,
	("the quest came back in %d zones where two of its three have a map")
		:format(#zones))
check(zones[1] and zones[1].map == 52,
	"the map did not open on the zone Questie says is nearest")

local elwynn = zones[2]
check(elwynn and elwynn.map == 37,
	"the quest's other zone did not come back under the client's map id")
check(elwynn and #elwynn.points == 4,
	("Elwynn came back with %s places where it has two camps, a person to speak to and a hand-in")
		:format(elwynn and #elwynn.points or "no"))

local corner, finished, back, speak = false, false, 0, false
for _, point in ipairs(elwynn and elwynn.points or {}) do
	if point.x < 0 or point.y < 0 then corner = true end
	if point.x == 90 and point.y == 90 then finished = true end
	if point.x == 22 and point.y == 70 then speak = true end
	if point.kind == ns.QuestWhere.BACK then back = back + 1 end
end
check(not corner, "a spawn Questie marks -1 was drawn in the corner of the zone")
check(not finished, "a finished objective's camps are still on the map")
check(back == 1, ("%d places are marked as the hand-in where one is"):format(back))

-- The objective the counts used to drop. Questie forces numRequired to 0
-- for every step the client counts nothing for, which is every "speak to",
-- "explore" and "use the thing" in the game, so 0 of 0 is equal and a filter
-- written as "needed is not collected" reads the whole kind as finished. A
-- quest whose only step is one of those lost its entire map.
check(speak,
	"an objective Questie files at 0 of 0 was read as finished and left off")

-- A quest Questie holds and has drawn nothing for, which is Questie's icons
-- switched off, or the log opened before it has finished drawing at login.
-- Every spawnList on it is empty and the coordinates are still in the row
-- the quest was compiled from, so the map has to ask the database instead.
-- One place per kind that fallback can take.
local dry = ns.QuestWhere.Places(201)
check(#dry == 1 and dry[1].map == 37,
	("a quest with no drawn icons came back in %d zones"):format(#dry))
check(dry[1] and #dry[1].points == 3,
	("the database answered %s places where the quest has a creature, an item and an event")
		:format(dry[1] and #dry[1].points or "no"))

local named = {}
for _, point in ipairs(dry[1] and dry[1].points or {}) do
	named[point.name or "?"] = true
end
check(named["Hogger"], "a creature objective did not come out of the database")
check(named["Riverpaw Gnoll"],
	"an item objective was not traced to what drops it")
check(named["Report to Dughan"],
	"an event objective's own coordinates were not read")

-- The marks themselves, which is the whole difference between a map you
-- can read at a glance and a map of coloured blobs. Every point the world
-- map draws carries Questie's own texture because it reads Questie's own
-- frames; this map is built out of the database and has to resolve the art
-- from the icon the data names, and there are three ways that goes wrong
-- and one way it goes right.
--
-- The live path first. A spawn list entry carries an ICON_TYPE number, and
-- the number has to be read through usedIcons rather than icons: the
-- fixture has the player's own texture on slay, so a reader that took the
-- stock path is drawing something the minimap is not.
local stock, slay = H.questieIcons, H.questieChosenSlay
local marks = {}
for _, point in ipairs(elwynn and elwynn.points or {}) do
	marks[point.icon or "?"] = (marks[point.icon or "?"] or 0) + 1
end
check(marks[slay] == 3,
	("%s places drew the icon the player put on slay, where three do")
		:format(tostring(marks[slay])))
check(marks[stock.incomplete] == 1,
	"the hand-in on an unfinished quest did not draw the grey question mark")
check(marks["?"] == nil,
	"a place on the map came back with no icon and would draw as a square")

-- The other half of the hand-in's mark. The map draws it whether or not the
-- quest is finished, which is where this addon and Questie part company, and
-- the colour is what keeps that honest: grey says the trip is wasted today and
-- gold says go. Both are drawn off the quest object's own IsComplete, so the
-- switch is on the fixture rather than on the client's log row.
H.questFinish(1)
local done = ns.QuestWhere.Places(102)[2]
local gold = 0
for _, point in ipairs(done and done.points or {}) do
	if point.icon == stock.complete then
		gold = gold + 1
	end
end
check(gold == 1,
	("%d hand-ins went gold on a finished quest, where one does"):format(gold))
H.questFinish(0)

-- And the database path, where the row names a kind rather than an icon
-- and one row carries a correction that outranks its kind. The event is
-- the corrected one: its kind would give it the event mark and Questie's
-- own row says the question mark, and the correction is the answer.
local dryMarks = {}
for _, point in ipairs(dry[1] and dry[1].points or {}) do
	dryMarks[point.name or "?"] = point.icon
end
check(dryMarks["Hogger"] == slay,
	"a creature row did not fall back to the slay mark for its kind")
check(dryMarks["Riverpaw Gnoll"] == stock.loot,
	"an item objective drew the mark for what carries it rather than for loot")
check(dryMarks["Report to Dughan"] == stock.complete,
	"a row's own icon lost to the default for its kind")

-- The window, driven through the tab rather than through its buttons, and
-- on the one quest of the five the stub files spawns under.
Window.Show()
Window.Showing(diplomat)
check(Window.Showing() == diplomat,
	"the window would not be moved onto the quest Questie has spawns for")
check(Window.Tab() == 1, "the middle column did not open on the quest")
Window.Tab(2)
check(Window.Tab() == 2, "the tab would not turn over to the map")

local text, map = _G.WarriorKitQuestText, _G.WarriorKitQuestMap
check(text and map and not text:IsShown() and map:IsShown(),
	"both sides of the tab are up at once, or neither is")

-- Westfall, which is where the stub says you are standing, so the quest's
-- one camp there and the dot for you are both on it.
local dots, where = Window.Places()
check(where == "Westfall",
	("the map is headed %s where Questie sends you to Westfall"):format(tostring(where)))
check(dots == 2,
	("%d dots on the zone you are in, where the quest has one camp and you are the other")
		:format(dots))

-- Elwynn, where you are not. Three places and no dot for you, which is the
-- half of the player marker that is easy to draw on every map at once.
Window.Zone(2)
dots, where = Window.Places()
check(where == "Elwynn Forest" and dots == 4,
	("stepping to the second zone drew %d dots headed %s")
		:format(dots, tostring(where)))

-- The art. Twelve tiles at 1002 by 668, so the map keeps the zone's shape
-- and the two part tiles are cropped rather than drawn whole.
--
-- Two frames down, not one. The board is a box that clips and the picture
-- is a frame inside it that the wheel is allowed to make bigger than the
-- box, so the tiles hang off the canvas and the canvas hangs off the port.
local board = _G.WarriorKitQuestChart
local port = board and board:GetChildren()
local canvas = port and port:GetChildren()
check(canvas ~= nil, "the map has no canvas to draw the zone on")
check(board:GetHeight() == ns.UI.Round(board, board:GetWidth() * 668 / 1002),
	("the map is %d by %d, which is not the shape the client's art is")
		:format(board:GetWidth(), board:GetHeight()))

local tiles, cropped = 0, 0
for _, region in ipairs({ canvas:GetRegions() }) do
	if region:GetTexture() and region:IsShown() then
		tiles = tiles + 1
		local right = region.texcoord and region.texcoord[2]
		if right and right < 1 then cropped = cropped + 1 end
	end
end
check(tiles == 12, ("the zone drew %d tiles where its art is twelve"):format(tiles))
check(cropped > 0,
	"every tile was drawn whole, so the padding on the last column is on the map")

-- Redrawn twenty times, which is an evening of clicking down the left
-- column. This client cannot destroy a frame, so the dots have to be the
-- same dots afterwards.
local pins = #ns.UI.Windows
for _ = 1, 20 do
	Window.Zone(1)
	Window.Zone(2)
end
check(select(1, Window.Places()) == 4,
	"redrawing the same zone twenty times changed what is on it")
check(#ns.UI.Windows == pins,
	"redrawing the map made windows")

-- The wheel.
--
-- A zone at the width of one column is three hundred pixels across a place
-- that takes twenty minutes to walk, and the answer is the picture growing
-- inside a box that does not. Four things about that cannot be seen in a
-- screenshot of the map at rest.
--
-- Does a notch move it at all, and does it stop. The far end is a constant
-- in Quests/Chart.lua and a zoom that ran past it would draw one of the
-- client's tiles at ten times its size.
--
-- Does the picture grow and the box hold. That is the whole shape of it: the
-- canvas takes the scale and the port takes what the column will spare.
--
-- Do the dots stay the size they were. A mark is a thing you look for on a
-- screen, so it wants the same pixels at every zoom, and a wash that scaled
-- with the map would cover the zone at the far end.
--
-- And does it come back. Zoom is kept across a repaint of the same zone and
-- dropped on a move to another one, which is two different quests' worth of
-- state living on one board.
check(Window.Zoom() == 1, "the map did not open at rest")

local dot = canvas:GetChildren()
local flat = { canvas:GetWidth(), port:GetHeight(), dot and dot:GetWidth() }
local level = Window.Zoom(1)
check(level > 1, ("a notch of the wheel left the zoom at %s"):format(tostring(level)))
check(canvas:GetWidth() > flat[1],
	("the picture is %d wide after a notch where it was %d")
		:format(canvas:GetWidth(), flat[1]))
check(port:GetWidth() <= board:GetWidth() and port:GetHeight() <= board:GetHeight(),
	("the box grew to %d by %d inside a column %d wide")
		:format(port:GetWidth(), port:GetHeight(), board:GetWidth()))
check(port:GetWidth() <= canvas:GetWidth() and port:GetHeight() <= canvas:GetHeight(),
	("the box is %d by %d looking at a picture %d by %d")
		:format(port:GetWidth(), port:GetHeight(),
			canvas:GetWidth(), canvas:GetHeight()))
check(dot and dot:GetWidth() == flat[3],
	"a dot changed size when the picture behind it did")

for _ = 1, 20 do
	Window.Zoom(1)
end
deepest = Window.Zoom()
check(deepest <= 6, ("twenty notches took the zoom to %s"):format(tostring(deepest)))
check(port:GetHeight() > flat[2],
	("the box is still %d tall at the far end where it started at %d")
		:format(port:GetHeight(), flat[2]))
check(select(1, Window.Places()) == 4,
	"zooming in changed how many places are on the map")

Window.PaintMap()
check(Window.Zoom() > 1, "repainting the same zone threw the zoom away")

-- The drag, which is the other half of the wheel.
--
-- At the far end the box is looking at a sixth of the zone, and for a long
-- time this map had no way across it: UI/Chart.lua hung its mouse only
-- where the caller had passed something to do with a click, and this one
-- passes nothing. The gesture is not visible in a picture of the map, so
-- both halves are asserted here: the picture moves while it is zoomed, and
-- a picture that fits its box refuses, which is what hands the drag up to
-- the window and moves the window instead.
check(Window.Drag(-40, 0), "a zoomed map would not drag")
check(Window.Drag(-9000, 0), "the map would not drag to its own edge")
check(Window.Drag(-9000, 0) == false, "the map dragged past its own edge")
Window.Drag(9000, 0)

for _ = 1, 20 do
	Window.Zoom(-1)
end
check(Window.Zoom() == 1,
	("twenty notches back took the zoom to %s"):format(tostring(Window.Zoom())))
check(Window.Drag(-40, 0) == false,
	"a map that fits its box moved instead of handing the drag to the window")
check(canvas:GetWidth() == flat[1] and port:GetHeight() == flat[2],
	("the map came back %d wide in a box %d tall, where it began %d by %d")
		:format(canvas:GetWidth(), port:GetHeight(), flat[1], flat[2]))

Window.Zoom(1)
Window.Zone(1)
check(Window.Zoom() == 1, "stepping to another zone kept the last one's zoom")
Window.Zone(2)

-- A zone Questie knows and this client has no picture for, which is the one
-- state a fixture cannot hold permanently. Nothing is drawn and the line
-- under the map says which of the four ways to have no map this is.
local art = quests.art[37]
quests.art[37] = nil
Window.PaintMap()
check(select(1, Window.Places()) == 0,
	"dots were drawn on a zone the client has no picture of")
-- The box goes too, not just the picture in it. It carries the sunken fill
-- and the hairline, so a box left at the last zone's size under a frame
-- collapsed to one pixel is an empty rectangle with the zone strip drawn
-- over it, and every assertion about the dots still passes.
check(not port:IsShown(),
	"the map's own box was left on screen over a frame with nothing in it")
quests.art[37] = art

Window.PaintMap()
check(port:IsShown(), "the box did not come back with the zone's art")

Window.Zone(1)
Window.Tab(1)
Log.Detail(diplomat)

print(("quests map %d of the quest's zones have a picture, %d dots on %s, %d tiles, the wheel goes to %gx")
	:format(#zones, select(1, Window.Places()), tostring(select(2, Window.Places())),
		tiles, deepest))
