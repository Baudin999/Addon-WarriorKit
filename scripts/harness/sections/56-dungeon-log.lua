-- The dungeon log
--
-- Eight questions no amount of reading Dungeons/ will answer.
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

local Window, Book, Places, Loot, Seen =
	ns.DungeonWindow, ns.DungeonBook, ns.DungeonPlaces, ns.DungeonLoot, ns.DungeonSeen

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
-- The window
----------------------------------------------------------------------

do
	check(Window.Built(), "the dungeon log was not built at login")
	Window.Show()
	check(Window.Shown(), "the dungeon log did not open")

	local rows = Window.Rows()
	check(#rows == places + bosses,
		("the column drew %d rows for %d dungeons and %d bosses")
			:format(#rows, places, bosses))

	local headers, marked = 0, 0
	for _, row in ipairs(rows) do
		if row.header then
			headers = headers + 1
		end
		if row.mark then
			marked = marked + 1
		end
	end
	check(headers == places, ("%d headers for %d dungeons"):format(headers, places))
	check(marked == 0,
		("%d bosses are ticked before anything has been looted"):format(marked))

	check(Window.Select(VANCLEEF), "the window would not select a boss by its creature id")
	local shown, where, at = Window.Showing()
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

print(("dungeon %d dungeons, %d bosses, %d drops; %s")
	:format(places, bosses, drops, Places.Describe()))
