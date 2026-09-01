-- The adventure guide
--
-- Twelve questions no amount of reading Dungeons/ will answer.
--
-- Does the book survive the bake. Dungeons/Baked.lua is generated out of
-- Questie's databases by a script that runs on a laptop and never in a game, so
-- the one thing nothing else checks is that what came out of it is a table this
-- addon can walk: forty dungeons, two hundred and thirty seven bosses, and a
-- drop list on nearly all of them.
--
-- Does every dungeon in the book have a picture, in the shape the board draws.
-- Dungeons/Sheets.lua is generated too, out of Blizzard's own map tables, and a
-- place the book names that the bake did not reach draws a window with every
-- column right and no map in the middle. The tiles are the other half: twelve
-- of them, one prefix and one to twelve, and a path that came out any other way
-- draws nothing at all and says nothing about it.
--
-- Does every dungeon in the book have a card, and does every card have a
-- painting on it. Dungeons/Art.lua is generated too, out of the 2.5 client's
-- own instance tables, and a place the bake did not reach is a card that is a
-- dark rectangle with a name on it, which looks like a bug rather than a gap.
--
-- Does the window open on the shelf, and does clicking a card become that
-- dungeon and only that dungeon. The left column used to hold every boss in the
-- game and now holds one dungeon's, so the count down that column is the whole
-- of what says which page is up and which dungeon is on it.
--
-- Do all three ways back work. Right click on the boss list, right click on the
-- map, and the button that says where it goes: three paths through two files,
-- and the two gestures are the ones nothing on the screen mentions.
--
-- Does a dungeon with floors get a strip and a dungeon without one not. Both
-- are ordinary and only one of them draws a control, and a strip of one button
-- under a map is furniture that says nothing.
--
-- Is a drop the client disagrees with refused. This is the one that matters
-- most and it is invisible on the screen: an item id that is wrong resolves to
-- a real item with a real icon and a real tooltip, and the only thing that can
-- catch it is the name the bake wrote down beside the id.
--
-- Is a drop the client has never cached still drawn. Most of the column is
-- items you have never seen, and a window that went blank until the client
-- caught up would be blank exactly when it is first opened.
--
-- Does looting a boss place it on the map. Nothing on either client says where
-- a boss stands, so a mark is a thing the addon learns, and the whole feature
-- is the difference between a picture with marks on it and a picture without.
--
-- Does looting a boss teach the book a drop it did not have. Questie's Outland
-- database carries almost no dungeon loot, so for fifteen dungeons this is the
-- only way the right hand column ever fills in.
--
-- Does opening it in a dungeon open it on that dungeon. The join runs from the
-- map id the client hands back, through the floors Dungeons/Sheets.lua baked,
-- to a row of the book, and not one step of it is a name: a match on a name
-- would work on an English client and quietly stop working on any other.
--
-- And does Shift-L open it. The key is an override on a plain button, which is
-- the one shape in this addon that is not proved by anything else: the other
-- three key holders are secure buttons carrying macros.
--
-- Scoped in do blocks, which is what the name budget in scripts/check.sh asks
-- of a section this long: Lua gives one chunk two hundred locals and a section
-- that declares fifty of them at the top is fifty of somebody else's budget.

local H = ...
local ns, check = H.ns, H.check
local quests, dungeons = H.quests, H.dungeons

local Window, Book, Places, Loot, Seen, Shelf =
	ns.DungeonWindow, ns.DungeonBook, ns.DungeonPlaces, ns.DungeonLoot,
	ns.DungeonSeen, ns.DungeonShelf

-- The ids the fixture is built on, named here rather than written into every
-- assertion because a number in a message is a number nobody can read.
local DEADMINES, COVE, STOCKADE = 291, 292, 225
local VANCLEEF, SMITE = 639, 646
local CRUEL_BARB, CAPE, THIEFS_BLADE = 5191, 5193, 5192

local places, bosses, drops = Book.Count()
local deadmines = Book.Dungeon("The Deadmines")
local boss = Book.Boss(VANCLEEF)

----------------------------------------------------------------------
-- The book
----------------------------------------------------------------------

do
	check(places > 30, ("the book holds %d dungeons"):format(places))
	check(bosses > 200, ("the book holds %d bosses"):format(bosses))
	check(drops > 700, ("the book holds %d drops"):format(drops))

	check(deadmines ~= nil, "the book has no Deadmines in it")
	check(deadmines and deadmines.low == 17 and deadmines.high == 26,
		"the Deadmines is not the levels the book says")

	local _, held, order = Book.Boss(VANCLEEF)
	check(boss ~= nil and boss.name == "Edwin VanCleef",
		"the creature id the combat log carries did not find the boss")
	check(held == deadmines and order == 7,
		("VanCleef came back as %s of %s")
			:format(tostring(order), held and held.name or "nowhere"))

	-- Every dungeon in the book is a name, a level range and at least one boss,
	-- and every boss is an id and a name. It is the whole of what a generated
	-- file can get wrong and the whole of what nothing else would notice.
	local ragged = 0
	for _, dungeon in ipairs(Book.All()) do
		if type(dungeon.name) ~= "string" or type(dungeon.low) ~= "number"
			or #dungeon.bosses == 0 then
			ragged = ragged + 1
		end
		for _, one in ipairs(dungeon.bosses) do
			if type(one.id) ~= "number" or type(one.name) ~= "string" then
				ragged = ragged + 1
			end
		end
	end
	check(ragged == 0,
		("%d rows of the baked book are not the shape it promises"):format(ragged))
end

----------------------------------------------------------------------
-- The client's dungeon maps
----------------------------------------------------------------------

do
	Places.Forget()

	-- A wing is the book's word and there is one picture behind the four of
	-- them, so the binding is on the part before the colon.
	check(Places.Place("Scarlet Monastery: Library") == "Scarlet Monastery",
		"a wing did not fall back to the place it is a wing of")
	check(#Places.Floors("Scarlet Monastery: Library") == 4,
		"the four wings of the monastery are not four floors of one picture")

	local floors = Places.Floors("The Deadmines")
	check(#floors == 2 and floors[1].map == DEADMINES and floors[2].map == COVE,
		("the Deadmines came back with %d floors"):format(#floors))
	check(floors[2].name == "Ironclad Cove",
		("the second floor of the Deadmines is called %q"):format(tostring(floors[2].name)))
	check(#Places.Floors("The Stockade") == 1,
		"a dungeon of one floor came back with more than the one floor it is")

	-- The tiles, which are the whole picture. A prefix and one to twelve, in
	-- reading order, which is the order UI/Chart.lua lays them out in.
	local sheet = floors[1].sheet
	check(#sheet.files == 12 and sheet.layer.layerWidth == 1002
		and sheet.layer.tileWidth == 256,
		("the first floor came back with %d tiles"):format(#sheet.files))
	check(sheet.files[1]:match("thedeadmines1_1$") ~= nil
		and sheet.files[12]:match("thedeadmines1_12$") ~= nil,
		("the tiles run %s to %s"):format(sheet.files[1], sheet.files[12]))

	-- Nothing baked that the book does not name. The whole book rather than the
	-- part this client can reach, because a picture of an Outland dungeon is
	-- correct on a vanilla client and simply never asked for. The other
	-- direction is the count below; this one is the entry left behind by a
	-- dungeon that was renamed or dropped, which nothing on the screen shows.
	local stray = 0
	for place in pairs(ns.DungeonSheets.PLACES) do
		local held = false
		for _, dungeon in ipairs(Book.DUNGEONS) do
			held = held or Places.Place(dungeon.name) == place
		end
		if not held then
			stray = stray + 1
		end
	end
	check(stray == 0, ("%d baked pictures are of places the book does not name"):format(stray))

	local drawn, wanted, held, known = Places.Count()
	check(drawn == wanted and wanted > 30,
		("%d of the book's %d dungeons have a picture"):format(drawn, wanted))
	check(held > drawn,
		("%d dungeons come to %d floors"):format(drawn, held))
	check(known == 3,
		("this client knows the map id of %d floors where the fixture has three"):format(known))
end

----------------------------------------------------------------------
-- The shelf
----------------------------------------------------------------------

do
	local held, drawn = Shelf.Count()
	check(drawn == places, ("the shelf drew %d cards for %d dungeons"):format(drawn, places))
	check(held == drawn,
		("%d of the shelf's %d cards have no picture on them"):format(drawn - held, drawn))
	check(Shelf.Describe():find("loading screen") ~= nil,
		("the reading for the shelf reads %q"):format(Shelf.Describe()))

	-- The four monastery wings are four cards and one painting, the same way
	-- they are four runs and one map. It is the one place a card and a picture
	-- are not one to one, and it is the case a bake keyed on the wrong half of
	-- the name would get wrong in both directions.
	local monastery = ns.DungeonArt.PLACES["Scarlet Monastery"]
	check(monastery ~= nil and monastery:find("Monastery") ~= nil,
		("the monastery's painting is %q"):format(tostring(monastery)))
	check(ns.DungeonArt.PLACES["Scarlet Monastery: Library"] == nil,
		"a wing was baked its own painting, which is the place baked four times")

	-- Nothing baked that the book does not name, which is the entry left behind
	-- by a dungeon that was renamed or dropped. The whole book rather than the
	-- part this client can reach, for the reason the map bake's own count is.
	local stray = 0
	for name in pairs(ns.DungeonArt.PLACES) do
		local wanted = false
		for _, dungeon in ipairs(Book.DUNGEONS) do
			wanted = wanted or Places.Place(dungeon.name) == name
		end
		if not wanted then
			stray = stray + 1
		end
	end
	check(stray == 0, ("%d baked paintings are of places the book does not name"):format(stray))
end

----------------------------------------------------------------------
-- The window, and moving between its two pages
----------------------------------------------------------------------

do
	check(Window.Built(), "the adventure guide was not built at login")
	Window.Show()
	check(Window.Shown(), "the adventure guide did not open")

	-- It opens on the shelf, which is the whole point of there being one: a
	-- window that opened on the last dungeon you read would be the old window
	-- with a page nobody sees.
	check(Window.Page() == "shelf",
		("the window opened on the %s page"):format(Window.Page()))
	check(#Window.Rows() == 0,
		("%d boss rows are drawn while the shelf is the page"):format(#Window.Rows()))
	check(Window.Showing() == nil, "a boss is selected while no dungeon is open")
	check(Window.Describe():find("shelf") ~= nil,
		("the reading for the window reads %q"):format(Window.Describe()))

	-- Every card carries the dungeon a press on it opens, which is the one
	-- claim about the shelf that cannot be made from outside it.
	local cards, carried = Shelf.Cards(), 0
	for _, card in ipairs(cards) do
		if card.dungeon and card.name:GetText() == card.dungeon.name then
			carried = carried + 1
		end
	end
	check(carried == places,
		("%d of %d cards show the dungeon they open"):format(carried, places))

	-- Pressing one becomes that dungeon and only that dungeon. Eight rows for
	-- the Deadmines' eight bosses, where the old column drew all two hundred
	-- and thirty seven at once.
	local card = nil
	for _, one in ipairs(cards) do
		if one.dungeon == deadmines then
			card = one
		end
	end
	check(card ~= nil, "the shelf has no Deadmines card on it")
	check(card:Click("LeftButton"), "the Deadmines card refused a press")
	check(Window.Page() == "dungeon",
		("clicking a card left the window on the %s page"):format(Window.Page()))

	local rows = Window.Rows()
	check(#rows == #deadmines.bosses,
		("the column drew %d rows for a dungeon of %d bosses")
			:format(#rows, #deadmines.bosses))

	local headers, marked = 0, 0
	for _, row in ipairs(rows) do
		if row.header then
			headers = headers + 1
		end
		if row.mark then
			marked = marked + 1
		end
	end
	check(headers == 0, ("%d headers on a page that is one dungeon"):format(headers))
	check(marked == 0,
		("%d bosses are ticked before anything has been looted"):format(marked))

	-- A card lands on the first boss rather than on nothing, because a page
	-- whose middle and right columns both say "nothing selected" looks like a
	-- page that failed to load.
	local shown, where, at = Window.Showing()
	check(at == 1 and where == "The Deadmines",
		("a card opened on %s of %s"):format(tostring(at), tostring(where)))

	check(Window.Select(VANCLEEF), "the window would not select a boss by its creature id")
	shown, where, at = Window.Showing()
	check(shown == VANCLEEF and where == "The Deadmines" and at == 7,
		("the window is showing %s of %s"):format(tostring(at), tostring(where)))

	-- The Deadmines has two floors, so the strip is drawn. The board is on the
	-- first of them until something says otherwise.
	local floor, count = Window.Floor()
	check(floor == 1 and count == 2, ("the map is on floor %d of %d"):format(floor, count))

	local note = (Window.Says())
	check(note:find("No bosses marked here yet") ~= nil,
		("the line under an unwalked map reads %q"):format(note))
	check((Window.Drawn()) == 0,
		("%d marks are on a map nothing has been looted in"):format((Window.Drawn())))
end

----------------------------------------------------------------------
-- The three ways back
----------------------------------------------------------------------

do
	-- The first descendant of a frame that answers a question, which is how the
	-- two gestures below reach the parts that carry them: a boss row and the
	-- box the map is drawn in are both pooled and neither has a name.
	local function Under(frame, wanted)
		if wanted(frame) then
			return frame
		end
		for _, child in ipairs(frame.children or {}) do
			local held = Under(child, wanted)
			if held then
				return held
			end
		end
		return nil
	end

	-- The right click on the column. A row is a button, a button eats a press it
	-- has not registered, and nothing behind it is ever told, so Click is asked
	-- rather than the script called: it refuses an edge the button never
	-- registered for, which is the whole failure this is here to catch.
	Window.Select(VANCLEEF)
	check(Window.Page() == "dungeon", "the window would not open a dungeon's page")
	local row = Under(_G.WarriorKitDungeonList, function(one)
		return one.kind == "button" and one.id ~= nil
	end)
	check(row ~= nil, "the boss column drew no rows to right click")
	check(row:Click("RightButton"),
		"a boss row refused a right click, which is a row that never registered for one")
	check(Window.Page() == "shelf",
		("a right click on a boss row left the window on the %s page"):format(Window.Page()))

	-- The right click on the map, which is the world map's own step-out gesture
	-- and the reason UI/Chart.lua takes a fourth argument at all.
	Window.Select(VANCLEEF)
	local port = Under(_G.WarriorKitDungeonChart, function(one)
		return one.scripts.OnMouseUp ~= nil
	end)
	check(port ~= nil, "the map has nothing on it that answers the mouse")
	port.scripts.OnMouseUp(port, "RightButton")
	check(Window.Page() == "shelf",
		("a right click on the map left the window on the %s page"):format(Window.Page()))

	-- And the button, which is the one of the three that says what it does.
	Window.Select(VANCLEEF)
	check(_G.WarriorKitDungeonBack ~= nil, "the page has no button back to the shelf")
	check(_G.WarriorKitDungeonBack:Click("LeftButton"), "the button refused a press")
	check(Window.Page() == "shelf",
		("the button left the window on the %s page"):format(Window.Page()))
	check((select(3, Window.Says())):find("Pick a dungeon") ~= nil,
		("the footer on the shelf reads %q"):format((select(3, Window.Says()))))
end

----------------------------------------------------------------------
-- What the client says about a drop
----------------------------------------------------------------------

do
	local payout = Loot.Rows(boss)
	local byName = {}
	for _, row in ipairs(payout) do
		byName[row.name] = row
	end

	check(byName["Cruel Barb"] ~= nil and byName["Cruel Barb"].quality == 3,
		"the drop the client agrees with did not come back graded")
	check(byName["Cape of the Brotherhood"] ~= nil,
		"the drop the client has never cached was dropped rather than drawn from the book")
	check(byName["Cape of the Brotherhood"].quality == nil,
		"a drop the client has not confirmed came back with a grade on it")

	local wanted = false
	for _, id in ipairs(dungeons.Asked()) do
		wanted = wanted or id == CAPE
	end
	check(wanted, "the window never asked the client to load the item it could not name")

	-- Grade first, which is what an adventure guide is read for.
	check(payout[1] ~= nil and payout[1].name == "Cruel Barb",
		("the column opened on %s rather than on the best thing on the table")
			:format(payout[1] and payout[1].name or "nothing"))

	-- The one that matters. The book says 5192 is Thief's Blade and this client
	-- says it is something else, which is exactly what a wrong id looks like.
	for _, row in ipairs(Loot.Rows(Book.Boss(SMITE))) do
		check(row.id ~= THIEFS_BLADE,
			"a drop the client disagreed with was drawn anyway, which is the window showing the wrong item")
	end
	check((Loot.Tally()) == 1,
		("%d drops were refused where the fixture disagrees about one"):format((Loot.Tally())))
	check(Loot.Describe():find("refused") ~= nil,
		("the reading for a refused drop reads %q"):format(Loot.Describe()))
end

----------------------------------------------------------------------
-- Looting a boss
----------------------------------------------------------------------

-- Standing in the Deadmines rather than in Westfall, because where you are
-- standing is the whole of what a mark is. Put back at the foot of the file.
local was = quests.standing.map
quests.standing.map = DEADMINES

do
	-- Back on the Deadmines page, because the block above left the window on the
	-- shelf and what this one reads is the boss column and the map.
	Window.Select(VANCLEEF)

	dungeons.Loot({
		guid = ("Creature-0-3007-0-11-%d-000136DF16"):format(VANCLEEF),
		slots = {
			{ CRUEL_BARB, "Cruel Barb" },
			{ 99001, "A Thing The Bake Never Heard Of" },
		},
	})
	H.fire("LOOT_OPENED")
	dungeons.Unloot()

	local map, x, y = Book.Where(VANCLEEF)
	check(map == DEADMINES, ("the boss was placed on map %s"):format(tostring(map)))
	check(x == quests.standing.x and y == quests.standing.y,
		("the boss was placed at %s, %s"):format(tostring(x), tostring(y)))

	local placed, learned = Seen.Count()
	check(placed == 1, ("%d bosses are placed after one loot window"):format(placed))
	check(learned == 1,
		("%d drops were learned where one of the two was already baked"):format(learned))
	check(#Book.Loot(boss) == 7,
		("the boss's table is %d rows after learning one"):format(#Book.Loot(boss)))

	-- The mark is on the picture now, and the row down the left carries its tick.
	Window.Paint()
	check((Window.Drawn()) == 1, "the boss that was looted is not on the map")
	local ticked = 0
	for _, row in ipairs(Window.Rows()) do
		if row.mark then
			ticked = ticked + 1
		end
	end
	check(ticked == 1, ("%d rows are ticked after one boss was looted"):format(ticked))
	check((Window.Says()):find("1 of 8 bosses marked") ~= nil,
		("the line under the map reads %q"):format((Window.Says())))

	-- A second loot window over the same corpse writes nothing new, which is
	-- what keeps a boss you farm every week from growing a row a run.
	dungeons.Loot({
		guid = ("Creature-0-3007-0-11-%d-000136DF16"):format(VANCLEEF),
		slots = { { CRUEL_BARB, "Cruel Barb" }, { 99001, "A Thing The Bake Never Heard Of" } },
	})
	H.fire("LOOT_OPENED")
	dungeons.Unloot()
	check(select(2, Seen.Count()) == 1, "looting the same boss twice wrote the drop down twice")
end

----------------------------------------------------------------------
-- What the shelf says once you have run something
----------------------------------------------------------------------

do
	-- The one thing on the front page that changes while you play. A shelf that
	-- looked the same after a run as before it would be a page you open once.
	Window.Back()
	Window.Paint()
	local said = nil
	for _, card in ipairs(Shelf.Cards()) do
		if card.dungeon == deadmines then
			said = card.caption:GetText()
		end
	end
	check(said ~= nil and said:find("1 of 8 looted") ~= nil,
		("the Deadmines card reads %q after one boss was looted"):format(tostring(said)))
	Window.Select(VANCLEEF)
end

----------------------------------------------------------------------
-- The wheel and the floors
----------------------------------------------------------------------

do
	check(Window.Zoom() == 1, "the map did not open at rest")
	Window.Zoom(1)
	check(Window.Zoom() > 1, "the wheel did not zoom the dungeon map")
	Window.Zoom(-1)

	local floor = Window.Floor(2)
	check(floor == 2, ("stepping to the second floor left the map on floor %d"):format(floor))
	check((Window.Drawn()) == 0, "the mark from the first floor is drawn on the second")
	Window.Floor(1)
end

----------------------------------------------------------------------
-- Where you are standing
----------------------------------------------------------------------

do
	-- The window opened while you are in a dungeon opens on that dungeon, on the
	-- floor you are on. It is answered off the map id the client hands back and
	-- never off a name, so this is the whole of what proves the join: 292 is the
	-- id the bake wrote for the Deadmines' second floor, and nothing in the book
	-- says "The Deadmines" anywhere along the path from that number to this page.
	Window.Hide()
	Window.Back()
	quests.standing.map = COVE
	Window.Show()
	check(Window.Page() == "dungeon",
		"the guide opened on the shelf while you were standing in a dungeon")
	check(select(2, Window.Showing()) == "The Deadmines",
		("the guide landed on %s"):format(tostring(select(2, Window.Showing()))))
	check((Window.Floor()) == 2,
		("the guide landed on floor %d of the two"):format((Window.Floor())))

	-- And outdoors it lands on nothing, which is the shelf it has always opened
	-- on. The map id there is a zone, and a zone is in no dungeon's floors.
	Window.Hide()
	Window.Back()
	quests.standing.map = was
	Window.Show()
	check(Window.Page() == "shelf",
		"the guide landed on a dungeon while you were standing outdoors")
	Window.Hide()
	quests.standing.map = DEADMINES
end

----------------------------------------------------------------------
-- The key
----------------------------------------------------------------------

do
	check(ns.db.dungeonKey == "SHIFT-L",
		("the dungeon log opens on %s rather than on Shift-L")
			:format(tostring(ns.db.dungeonKey)))

	-- Read back off the override layer rather than believed off the call, for
	-- the reason the three other key holders in the addon read theirs back: a
	-- client that takes SetOverrideBindingClick and does nothing with it leaves
	-- no other trace.
	local button = ns.DungeonKey.BUTTON_NAME
	local carries = ("CLICK %s:LeftButton"):format(button)
	check(GetBindingAction("SHIFT-L", true) == carries,
		("Shift-L carries %q"):format(GetBindingAction("SHIFT-L", true)))

	Window.Hide()
	_G[button].scripts.OnClick(_G[button], "LeftButton")
	check(Window.Shown(), "the key did not open the dungeon log")
	_G[button].scripts.OnClick(_G[button], "LeftButton")
	check(not Window.Shown(), "the key did not close the dungeon log again")

	-- Bound somewhere else, and the old key gives the override up. A part that
	-- cleared nothing would hold both.
	ns.DungeonKey.Bind("CTRL-K")
	check(GetBindingAction("SHIFT-L", true) == "",
		"rebinding left the old key holding the window open")
	check(GetBindingAction("CTRL-K", true) == carries, "rebinding did not take the new key")
	ns.DungeonKey.Bind("SHIFT-L")
end

----------------------------------------------------------------------

quests.standing.map = was
Seen.Forget()
check((Seen.Count()) == 0, "forgetting the ledger left something behind")

-- The size the picture actually came out, which is the one thing on this page
-- nothing else reports and the whole of what the window was widened for.
do
	Window.Select(VANCLEEF)
	local _, wide, tall = Window.Drawn()
	print(("dungeon the map is drawn %d by %d, out of art that is 1002 by 668")
		:format(wide, tall))
	Window.Hide()
end

print(("dungeon %d dungeons, %d bosses, %d drops; %s")
	:format(places, bosses, drops, Places.Describe()))
print(("dungeon %s; the shelf is the front page and right click is the way back")
	:format(Shelf.Describe()))
