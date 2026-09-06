-- The pin
--
-- Five questions about a list this addon keeps rather than about the log the
-- client hands over, which is why none of them belongs in the section above.
--
-- Does the gesture reach it. Shift left click on a row, driven through the
-- row's own button, because the modifier is read off the client inside
-- UI.List's handler: a window that hung the pin on Select would pin nothing at
-- all on the quest you are already reading, which is the row a player aims at.
--
-- And does a repaint not. Every paint hands the list the id it is already
-- showing, so a pin fired on that path would pin whatever you were reading
-- every time an event moved the log. It is asserted with shift held down,
-- because that is the state the failure needs.
--
-- Does the pin survive a turn-in. Handing one in takes every index under it up
-- by one, which is the reason the store is keyed on the quest, and a store
-- keyed on the index passes every other assertion in this file.
--
-- Is it uncapped. The client's own watch list holds five, and holding what you
-- put in it is the whole argument for this being ours.
--
-- And is the client's list left alone. AddQuestWatch is the call this addon
-- stopped making, so what is counted is every write over the whole run rather
-- than a state read at the end: a single write from anywhere fails this.

local H = ...
local ns, check, quests = H.ns, H.check, H.quests

local Log, Window = ns.QuestLog, ns.QuestWindow

----------------------------------------------------------------------
-- A log with room in it
----------------------------------------------------------------------

-- The section above leaves three quests standing and six is the number this
-- one is about, so five more rows go in under the header its abandon emptied.
-- None of them carries text and nothing here opens one: the middle column is
-- that section's question. Both the rows and the pins go back at the foot of
-- this file.
local ADDED = {}
for at = 1, 5 do
	ADDED[at] = { id = 300 + at, title = ("Nightbane Vile Fang %d"):format(at), level = 24 }
	quests.rows[#quests.rows + 1] = ADDED[at]
end

-- Whatever is pinned, off. The section above drives the footer button once per
-- quest to prove the row pool is reused, so the pin it leaves is a side effect
-- of counting frames rather than a state anybody chose to hand over.
for _, quest in ipairs(Log.Pins()) do
	Log.Pin(quest.key, false)
end

Window.Show()
Window.Paint()

check(select(1, Log.Tally()) == 8,
	("%d quests are in the log where this section wants eight"):format((Log.Tally())))
check(#ns.dbc.questPins == 0,
	("the section started with %d pins already on the character"):format(#ns.dbc.questPins))

-- This character's table and not the account's. A quest log belongs to one
-- character, so a pin the account shared would be a note about a quest most of
-- them cannot see.
check(ns.db.questPins == nil and type(ns.dbc.questPins) == "table",
	"the pins are saved on the account rather than on this character")

----------------------------------------------------------------------
-- The gesture
----------------------------------------------------------------------

do
	local quest = Log.Zones()[1].quests[1]

	check(Window.Click(quest.key), "a quest row took no left click")
	check(not Log.Pinned(quest.key),
		"an unmodified click pinned the quest it opened")

	_G.WarriorKitShift(true)
	check(Window.Click(quest.key), "a quest row took no shift left click")
	check(Log.Pinned(quest.key), "a shift left click did not pin the quest")

	-- The row already selected, which is the click the gesture exists for: you
	-- are reading the quest when you decide to keep it in front of you.
	check(Window.Click(quest.key), "the selected row took no second shift click")
	check(not Log.Pinned(quest.key),
		"a shift click on the quest already open did not take its pin off")

	check(Window.Click(quest.key), "the selected row took no third shift click")
	_G.WarriorKitShift(false)
	check(Log.Pinned(quest.key), "the third shift click did not put the pin back")

	check(Window.Click(quest.key), "the selected row took no unmodified click")
	check(Log.Pinned(quest.key),
		"an unmodified click on a pinned quest took the pin off")

	-- The footer button is the other half of the same gesture and not a second
	-- store, so what is asserted is that it moves the pin the row put on.
	check(Window.Pin(), "the footer button refused a quest that is open")
	check(not Log.Pinned(quest.key), "the footer button did not unpin the quest")
	Window.Pin()

	-- Shift held while the window repaints twice. Every paint hands the list
	-- the id it is showing, and the guard against that being read as a press is
	-- the button rather than the modifier.
	local held = #ns.dbc.questPins
	_G.WarriorKitShift(true)
	Window.Paint()
	Window.Paint()
	_G.WarriorKitShift(false)
	check(#ns.dbc.questPins == held,
		("two repaints with shift held moved the pins from %d to %d")
			:format(held, #ns.dbc.questPins))
	check(Log.Quest(quest.key).pinned,
		"the row lost the pin the character's own table still holds")
end

----------------------------------------------------------------------
-- A turn-in moves every index
----------------------------------------------------------------------

do
	local kept = Log.Zones()[3].quests[1]
	local going = Log.Zones()[1].quests[1]
	Log.Pin(kept.key, true)
	Log.Pin(going.key, true)

	local key, was = kept.key, kept.index
	local gone = table.remove(quests.rows, 2)
	Window.Paint()

	local again = Log.Quest(key)
	check(again ~= nil and again.index == was - 1,
		("the pinned quest sat at %d and the turn-in left it at %s")
			:format(was, tostring(again and again.index)))
	check(again.pinned and Log.Pinned(key),
		"a quest handed in one row above took the pin off its neighbour")

	-- The handed-in quest's own pin goes with it, which is the one thing that
	-- keeps the table from growing for the length of a character's life. It is
	-- done on a read that found a log: a client mid-loading-screen answers with
	-- no rows and a prune run on that answer would empty the table.
	check(not Log.Pinned(going.key),
		"the pin on a quest that left the log is still on the character")
	check(#Log.Pins() == 1 and Log.Pins()[1].key == key,
		("%d pinned quests are in the log where one is"):format(#Log.Pins()))

	table.insert(quests.rows, 2, gone)
	Window.Paint()
	check(Log.Pinned(key), "putting the quest back took the pin off its neighbour")
end

----------------------------------------------------------------------
-- Uncapped, and in the order you pinned them
----------------------------------------------------------------------

do
	for _, quest in ipairs(Log.Pins()) do
		Log.Pin(quest.key, false)
	end

	-- Six, which is one more than AddQuestWatch would have taken, pinned from
	-- the bottom of the log upwards so the order they come back in cannot be
	-- the order the log is in.
	local order = {}
	for at = #Log.Zones(), 1, -1 do
		local zone = Log.Zones()[at]
		for row = #zone.quests, 1, -1 do
			if #order < 6 then
				Log.Pin(zone.quests[row].key, true)
				order[#order + 1] = zone.quests[row].key
			end
		end
	end
	check(#order == 6, ("%d quests were pinned where six were asked for"):format(#order))

	Window.Paint()
	check(#Log.Pins() == 6,
		("%d of six pins came back from a read of the log"):format(#Log.Pins()))
	check(#ns.dbc.questPins == 6,
		("%d of six pins are on the character"):format(#ns.dbc.questPins))

	-- The order is the pinned group's whole shape, so it is asserted rather
	-- than assumed: a store that answered in log order would draw a group that
	-- rearranged itself every time you pinned a seventh.
	local held = Log.Pins()
	local wrong = 0
	for at = 1, #order do
		if not held[at] or held[at].key ~= order[at] then
			wrong = wrong + 1
		end
	end
	check(wrong == 0,
		("%d of six pins came back somewhere other than where they were put"):format(wrong))
end

----------------------------------------------------------------------
-- The client's five slots
----------------------------------------------------------------------

-- Over the whole run and not over this section. Nothing in the addon writes
-- that list any more, and the count is the only assertion that stays true when
-- somebody adds a caller somewhere else.
check(quests.WatchCalls() == 0,
	("the addon wrote the client's watch list %d times"):format(quests.WatchCalls()))

-- Both calls are still on Quests/Client.lua. They are what makes writing the
-- client's list again one line on the day Questie's tracked-only map filter
-- turns out to matter more than the cap does.
check(type(ns.QuestClient.Watch) == "function"
	and type(ns.QuestClient.Watched) == "function",
	"the client's watch calls came off the file, so the trade cannot be taken back")

----------------------------------------------------------------------

-- Everything back the way it was handed over: the five rows out of the log and
-- the pins off the character. The section under this one reads the same log.
for at = #quests.rows, 1, -1 do
	for _, row in ipairs(ADDED) do
		if quests.rows[at] == row then
			table.remove(quests.rows, at)
		end
	end
end
Window.Paint()
for _, quest in ipairs(Log.Pins()) do
	Log.Pin(quest.key, false)
end
Window.Paint()

print(("quests pin %d quests left in the log, %d pinned, %d writes to the client's watch list")
	:format((Log.Tally()), #Log.Pins(), quests.WatchCalls()))
