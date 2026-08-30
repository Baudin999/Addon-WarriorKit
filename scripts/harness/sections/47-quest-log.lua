-- The quest log
--
-- Five questions no amount of reading Quests/ will answer.
--
-- Does the flat run of rows become zones. The client hands the log over as
-- headers and quests in one list, and a model that got the fold wrong would
-- draw a column that looks right until a zone with two quests in it puts the
-- second one under the wrong heading.
--
-- Does the cursor come back. Every text and reward call in this addon reads a
-- selection the whole client shares, so a borrow that forgot to restore leaves
-- another addon's quest log pointing at whatever this window last drew. It is
-- invisible from inside the window, which is exactly why it is measured here
-- and why the stub models the cursor rather than answering per index.
--
-- Does the left column colour by state. A quest ready to hand in and a quest
-- that will kill you are the two things a log is read for at a glance, and both
-- of them are one table lookup away from being drawn the same grey.
--
-- Do the frames get reused. This client cannot destroy a frame, so a column
-- rebuilt per click either pools its rows or leaks them, and leaking is
-- invisible until an evening of clicking quests has made a thousand frames.
--
-- And does abandoning ask the client rather than itself. The confirmation names
-- the quest the client says it has armed, off the cursor, so the one failure
-- worth catching is the window and the client disagreeing about which quest is
-- about to go.

local H = ...
local ns, check, quests = H.ns, H.check, H.quests
local group, fire = H.group, H.fire

local Log, Client, Window = ns.QuestLog, ns.QuestClient, ns.QuestWindow

----------------------------------------------------------------------
-- The fold
----------------------------------------------------------------------

Log.Read()

check(Log.Count() == 3,
	("the log folded into %d zones where the stub has three"):format(Log.Count()))

local total, done = Log.Tally()
check(total == 5, ("%d quests were counted where the stub has five"):format(total))
check(done == 1, ("%d quests read as ready to hand in, and one is"):format(done))

local zones = Log.Zones()
check(zones[1].name == "Elwynn Forest" and #zones[1].quests == 2,
	("the first zone came out as %s with %d quests")
		:format(tostring(zones[1].name), #zones[1].quests))
check(zones[2].quests[1].title == "The Defias Brotherhood",
	"the second zone's first quest is not the row that follows its header")
check(zones[1].quests[2].complete and not zones[1].quests[2].failed,
	"the quest the client marks 1 did not read as ready to hand in")
check(zones[2].quests[2].failed and not zones[2].quests[2].complete,
	"the quest the client marks -1 read as complete rather than failed")

-- Every header is opened before the rows are counted, because a collapsed one
-- hides its quests from the client's own count. The stub cannot collapse, so
-- what is checked is that the part asked at all: a part that does not ask reads
-- a short log on a real client and has no way to know it did.
check(quests.Expanded() > 0,
	"the log was read without ever asking the client to open its headers")

----------------------------------------------------------------------
-- The cursor
----------------------------------------------------------------------

-- Parked somewhere deliberate, then every reading the window takes, then the
-- same question again. The window is allowed to move the selection as often as
-- it likes and is not allowed to leave it moved.
local PARKED = 6
quests.Park(PARKED)

local key = Log.Zones()[1].quests[2].key
local detail = Log.Detail(key)

check(quests.Check(PARKED) == PARKED,
	("reading one quest left the shared cursor on %s rather than %d")
		:format(tostring(quests.Selection()), PARKED))
check(quests.Stranded() == 0,
	("%d readings left the cursor somewhere else"):format(quests.Stranded()))

check(detail ~= nil and detail.quest.title == "Wanted: Hogger",
	"the detail came back for a different quest than the one asked for")
check(#detail.objectives == 1 and detail.objectives[1].done,
	"the finished objective on a complete quest did not read as done")
check(detail.description ~= "" and detail.summary ~= "",
	"a quest with both paragraphs came back with one of them empty")

-- Three rewards on this one, in two lists, because a choice and an item are
-- different promises and a column that ran them together would be telling you
-- that you get all three.
check(#detail.rewards.choices == 2,
	("%d choices came back where the stub offers two"):format(#detail.rewards.choices))
check(#detail.rewards.items == 1,
	("%d guaranteed items came back where the stub gives one"):format(#detail.rewards.items))
check(detail.rewards.money == 4500,
	("the coin reward came back as %s"):format(tostring(detail.rewards.money)))
check(detail.rewards.choices[1].link ~= nil,
	"a reward came back with no item link, so its hover can say nothing")

-- The three the stub deliberately does not install, which is the state a real
-- client is in: honor and a title exist on one of the two builds and not the
-- other, and the experience number is not a client call at all until Questie
-- writes it. Nil rather than zero, because a quest that pays no honor and a
-- client that cannot say are not the same fact.
check(detail.rewards.honor == nil and detail.rewards.xp == nil,
	"a call this client does not have answered zero rather than nothing")

-- A timed quest, which is the one row of the tagline that comes off its own
-- call rather than off the log row.
local timed = Log.Detail(Log.Zones()[2].quests[1].key)
check(timed.seconds == 900,
	("the timer came back as %s seconds"):format(tostring(timed.seconds)))
check(timed.shareable,
	"a quest with a suggested group size did not read as shareable")
check(not detail.shareable,
	"a quest with no group size read as shareable")

-- A spell reward, which is the one payout that is neither an item nor a number.
-- It carries a name and a texture and no spell id at all, so the column draws
-- the picture and hangs no hover on it, and the texture is the half that goes
-- missing without anybody noticing: the line still reads correctly with the
-- icon thrown away.
local taught = Log.Detail(Log.Zones()[3].quests[1].key)
check(taught.rewards.spell ~= nil and taught.rewards.spell.name == "Blessing of the Night",
	"the spell reward did not come back off the cursor")
check(type(taught.rewards.spell.texture) == "string" and taught.rewards.spell.texture ~= "",
	"the spell reward came back with no texture, so its row can draw no icon")

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

Window.Show()
check(Window.Shown(), "the window did not come up")

-- The left column is every quest and every zone that holds one: five rows and
-- three headers, all eight of them drawn at once. The client draws six of these
-- through a slot, and that is the whole argument for the part.
local drawn = Window.Rows()
local headers, entries = 0, 0
for _, row in ipairs(drawn) do
	if row.header then
		headers = headers + 1
	else
		entries = entries + 1
	end
end
check(headers == 3 and entries == 5,
	("the column drew %d headers over %d quests"):format(headers, entries))
check(drawn[1].header == "Elwynn Forest" and drawn[2].label == "[20] The Missing Diplomat",
	"a quest is not drawn under the header that precedes it, or without its level")

-- The two colours the log is actually read for at a glance, and the mark that
-- carries the same fact in a character. A quest ready to hand in is the tick
-- green whatever its level, and one that failed is the loss red, and neither of
-- them is the XP ladder every other row is on.
--
-- The mark is checked as well as the colour, and it is the half that matters.
-- The tick green and the green the ladder gives a quest you have outlevelled
-- are two shades apart, and PaintListRow throws the row's own colour away for
-- the row you have selected, so a log that says "finished" in colour alone says
-- it least about the quest you are reading. The mark keeps its own colour
-- through the selection, which is why it carries one of its own.
local complete, failed
for _, row in ipairs(drawn) do
	if row.label == "[11] Wanted: Hogger" then complete = row end
	if row.label == "[18] Red Silk Bandanas" then failed = row end
end
check(complete and complete.color == ns.UI.Color.tick
	and complete.markColor == ns.UI.Color.tick,
	"a quest ready to hand in is not drawn in the tick colour")
check(failed and failed.color == ns.UI.Color.loss
	and failed.markColor == ns.UI.Color.loss,
	"a failed quest is not drawn in the loss colour")

-- The mark itself, and the one thing about it nothing else in the addon can
-- say: it is a letter the glyph face carries a mark on. The cmap of
-- Media/Glyphs.ttf is rewritten to a handful of letters and every other one
-- draws an empty rectangle, silently, so a tick cut onto a letter nobody baked
-- is a quest log with a blank column down its left edge and no error anywhere.
--
-- scripts/check.sh holds the alphabet to what the bake script produces. This is
-- the other half: that the marks the window actually draws are in it.
check(complete and complete.mark ~= "" and ns.UI.GLYPHS:find(complete.mark, 1, true),
	("a finished quest is marked %q, which the glyph face has no mark for")
		:format(complete and complete.mark or ""))
check(failed and ns.UI.GLYPHS:find(failed.mark, 1, true),
	("a failed quest is marked %q, which the glyph face has no mark for")
		:format(failed and failed.mark or ""))
check(complete and complete.mark ~= "+",
	"a quest ready to hand in is still marked with the plus that means add")
check(drawn[2].mark == "",
	("a quest in progress carries the mark %q"):format(drawn[2].mark or ""))
check(drawn[2].color ~= ns.UI.Color.tick and drawn[2].color ~= ns.UI.Color.loss,
	"a quest in progress took one of the two state colours")

-- The ladder itself, which every other row is coloured on. The player is 62
-- here, so a quest five levels above them and one fifty levels below them are
-- the two ends of it, and a WorthOf that answered one colour to everything
-- would leave the whole left column one shade of grey.
check(ns.Unit.Level.WorthOf(67) ~= ns.Unit.Level.WorthOf(62),
	"a quest five levels above you is the same colour as one at your level")
check(ns.Unit.Level.WorthOf(62) ~= ns.Unit.Level.WorthOf(11),
	"a quest at your level is the same colour as one fifty levels below it")

check(Window.Paint(), "the window refused to paint")

-- The margins, which is the half of this window a screenshot catches and no
-- assertion did. The three columns were laid edge to edge inside a content
-- frame that spans the window, under a footer UI/Window.lua insets by M.pad, so
-- the reward text ran into the right edge while the buttons under it sat
-- comfortably in from the same edge. Nothing was wrong at any one site.
--
-- What is checked is the arithmetic that cannot be wrong twice: four margins of
-- one width, three columns, and the whole of it adding up to the window.
--
-- Scoped in a do block, because everything in it is read once and this file is
-- against the harness name budget. An indented local is not a name at chunk
-- level, which is the shape scripts/check.sh asks every section for.
do
	local M = ns.UI.Metric
	local rail = _G.WarriorKitQuestList
	local text = _G.WarriorKitQuestText
	local reward = _G.WarriorKitQuestRewards
	check(rail and text and reward,
		"one of the three columns is not on the screen under its own name")

	local _, _, _, railIn, railTop = rail:GetPoint(1)
	local _, _, _, rewardIn, rewardTop = reward:GetPoint(1)
	check(railIn == M.pad and -railTop == M.pad,
		("the list sits %s in and %s down where the margin is %d")
			:format(railIn, -railTop, M.pad))
	check(-rewardIn == M.pad and -rewardTop == M.pad,
		("the reward column sits %s in and %s down where the margin is %d")
			:format(-rewardIn, -rewardTop, M.pad))

	local spanned = M.pad * 4 + rail:GetWidth() + text:GetWidth() + reward:GetWidth()
	local across = _G.WarriorKitQuests:GetWidth()
	check(spanned == across,
		("the columns and their four margins come to %d in a window %d wide")
			:format(spanned, across))
end

-- Clicking through every quest and back, which is what an evening of the window
-- being open is. The pool has to be the same frames afterwards.
local before = ns.UI.Windows and #ns.UI.Windows or 0
for _, zone in ipairs(Log.Zones()) do
	for _, quest in ipairs(zone.quests) do
		Window.Track()
		Log.Detail(quest.key)
	end
end
check(#ns.UI.Windows == before,
	("clicking through the log made %d more windows"):format(#ns.UI.Windows - before))
check(quests.Stranded() == 0,
	("%d readings left the shared cursor somewhere else"):format(quests.Stranded()))

----------------------------------------------------------------------
-- Who else in the group is on it
----------------------------------------------------------------------

-- Two sources answer this and neither can answer it alone, so the one thing
-- worth asserting is the merge.
--
-- The client says party1 and party3 are on quest 102. Questie has heard from
-- Sneaky, Ironhide and you. Sneaky is party1, so he is in both answers and is
-- one person; Ironhide is in Questie's alone; Lightwell is party3 and is in the
-- client's alone; and Tusksfirst is you, who are on every quest in your own log
-- and must never be counted as company.
--
-- Three, therefore, and any of four mistakes gives a different number.
--
-- Scoped in a do block for the reason the margin check above is: an indented
-- local is not a name at chunk level, which is the shape scripts/check.sh asks
-- every section for.
do
	group.Set({
		{ token = "player", you = true, guid = "Player-Tusksfirst",
			name = "Tusksfirst", class = "WARRIOR" },
		{ token = "party1", guid = "Player-Sneaky", name = "Sneaky", class = "ROGUE" },
		{ token = "party2", guid = "Player-Bramblefoot",
			name = "Bramblefoot", class = "DRUID" },
		{ token = "party3", guid = "Player-Lightwell",
			name = "Lightwell", class = "PRIEST" },
		{ token = "party4", guid = "Player-Ironhide",
			name = "Ironhide", class = "WARRIOR" },
	}, false)
	fire("GROUP_ROSTER_UPDATE")
	Window.Paint()

	local names = ns.QuestParty.On(102, Client.IndexOf(102))
	check(#names == 3,
		("%d in the group came back for a quest two answers name three people on")
			:format(#names))
	check(table.concat(names, ", ") == "Ironhide, Lightwell, Sneaky",
		("the group came back as %s, which is either the wrong people or an order that moves")
			:format(table.concat(names, ", ")))

	-- The row, which is where a player reads it. A number and not a count of
	-- rows: the quest nobody else is on draws nothing at all, because nobody
	-- having it and nothing being able to say are the same picture and only one
	-- of them would be a fact.
	local company, alone
	for _, row in ipairs(Window.Rows()) do
		if row.label == "[20] The Missing Diplomat" then company = row end
		if row.label == "[24] Wolves at the Gate" then alone = row end
	end
	check(company and company.note == "3",
		("the row reads %s where three of the group are on it")
			:format(tostring(company and company.note)))
	check(alone and alone.note == nil,
		("a quest nobody else is on carries the note %s")
			:format(tostring(alone and alone.note)))

	group.Forget()
	fire("GROUP_ROSTER_UPDATE")
	Window.Paint()
end

----------------------------------------------------------------------
-- Tracking, sharing and abandoning
----------------------------------------------------------------------

local watched = Log.Zones()[3].quests[1]
local was = watched.watched
Log.Watch(watched.key, not was)
Log.Read()
check(Log.Quest(watched.key).watched ~= was,
	"the track button did not move the client's own watch")

Log.Share(Log.Zones()[2].quests[1].key)
check(#quests.shared == 1,
	("%d quests were pushed to the party where one was asked for"):format(#quests.shared))

-- The name comes off the client's armed state rather than off the row this
-- addon thinks is selected, which is the only version of the confirmation worth
-- having. Arming and firing are one borrow, so nothing can move the cursor
-- between the two calls.
local doomed = Log.Zones()[2].quests[2]
check(Log.Abandoning(doomed.key) == doomed.title,
	("the client armed %s where the window meant %s")
		:format(tostring(Log.Abandoning(doomed.key)), doomed.title))
check(Log.Abandon(doomed.key), "the abandon did not go through")
Log.Read()
check(Log.Quest(doomed.key) == nil,
	"the abandoned quest is still in the log")
check(select(1, Log.Tally()) == 4,
	("%d quests are left after abandoning one of five"):format((Log.Tally())))

----------------------------------------------------------------------
-- The two marks on a row
----------------------------------------------------------------------

-- Four things about them that reading the window will not settle.
--
-- Is the share mark on the rows that can take it and off the ones that cannot.
-- The client refuses to hand over a quest nobody else could take, so a mark
-- drawn on every row is a control that fails silently on most of them, and the
-- failure is invisible until somebody presses one.
--
-- Does pressing it reach the client. The mark is wired through the widget to a
-- closure in the window, and a mark drawn and connected to nothing looks
-- exactly like a mark that works.
--
-- Does the cross ask before it acts, and does no mean no. That is the whole
-- reason the confirmation exists, and a window that opened and abandoned anyway
-- would pass every assertion about the window being on screen.
--
-- And does yes name the quest whose mark was pressed. The row's mark and the
-- footer's button are two ways in and only one of them is about the quest you
-- have open, so the one that is not is the one that can act on the wrong quest.
do
	Window.Show()
	local shareable = Log.Zones()[2].quests[1]
	local refused = Log.Zones()[1].quests[1]
	local pushed = #quests.shared

	check(not Window.Press(refused.key, 1),
		"a quest the client would not hand over carries a share mark anyway")
	check(Window.Press(shareable.key, 1),
		"a quest with a suggested group size carries no share mark")
	check(#quests.shared == pushed + 1,
		("pressing the share mark pushed %d quests where one was asked for")
			:format(#quests.shared - pushed))

	-- The cross, twice: once answered no and once answered yes.
	local going = Log.Zones()[3].quests[1]
	check(Window.Press(going.key, 2), "a quest row carries no abandon mark")
	check(ns.UI.Asking() ~= nil, "the cross abandoned the quest without asking")
	check(ns.UI.Asking():find(going.title, 1, true),
		("the question is %q, which does not name the quest the mark was on")
			:format(tostring(ns.UI.Asking())))

	ns.UI.Answer(false)
	Log.Read()
	check(ns.UI.Asking() == nil, "the question stayed up after it was answered")
	check(Log.Quest(going.key) ~= nil,
		"answering no to the confirmation abandoned the quest anyway")

	Window.Press(going.key, 2)
	ns.UI.Answer(true)
	Log.Read()
	check(Log.Quest(going.key) == nil,
		"answering yes to the confirmation left the quest in the log")
	check(quests.abandoned[#quests.abandoned] == going.title,
		("the client abandoned %s where the mark was on %s")
			:format(tostring(quests.abandoned[#quests.abandoned]), going.title))
	check(quests.Stranded() == 0,
		("%d readings left the shared cursor somewhere else"):format(quests.Stranded()))
end

----------------------------------------------------------------------
-- Questie's tracker
----------------------------------------------------------------------

-- Clicking a quest in Questie's tracker opens the quest log at that quest, and
-- the log it opened was Blizzard's, which is in the attic. Every route in
-- Questie goes through one function, so the two things to prove are that the
-- swap takes it and that the switch hands it back.
do
	local utils = _G.QuestieLoader:ImportModule("QuestieTracker").utils
	local diplomat = Log.Zones()[1].quests[1]
	local reached = quests.Tracked()

	Window.Showing(Log.Zones()[2].quests[1].key)
	utils:ShowQuestLog({ Id = 102 })
	check(Window.Shown(), "a click in the tracker did not open this window")
	check(Window.Showing() == diplomat.key,
		("the tracker opened this window on %s rather than on the quest clicked")
			:format(tostring(Window.Showing())))
	check(quests.Tracked() == reached,
		"the click reached Blizzard's quest log as well as this window")

	-- A quest you are not on. Questie tracks what it likes, and a click it
	-- cannot be answered for has to fall through rather than be swallowed.
	utils:ShowQuestLog({ Id = 999 })
	check(quests.Tracked() == reached + 1,
		"a click on a quest this window cannot show was swallowed")

	ns.db.questsHideBlizz = false
	ns.QuestBlizzard.Apply()
	ns.QuestTracker.Apply()
	utils:ShowQuestLog({ Id = 102 })
	check(quests.Tracked() == reached + 2,
		"unticking the switch did not hand Questie's own function back")

	ns.db.questsHideBlizz = true
	ns.QuestBlizzard.Apply()
	ns.QuestTracker.Apply()
	print("quests " .. ns.QuestTracker.Describe() .. "; " .. ns.QuestParty.Describe())
end

----------------------------------------------------------------------
-- Blizzard's own
----------------------------------------------------------------------

check(ns.QuestBlizzard.Caged(),
	"Blizzard's quest log was left on the screen with this one switched on")
check(_G.QuestLogFrame:GetParent() == _G.WarriorKitAttic,
	"Blizzard's quest log is not in the attic")

-- The key. Ours toggles and the client's is never reached, which is what stops
-- L opening a window that is not there.
local opened = quests.Opened()
_G.ToggleQuestLog()
check(quests.Opened() == opened,
	"the L key reached Blizzard's own toggle rather than this window")
check(not Window.Shown(), "the key did not toggle this window")

ns.db.questsHideBlizz = false
ns.QuestBlizzard.Apply()
check(not ns.QuestBlizzard.Caged(), "unticking the switch left the frame caged")
_G.ToggleQuestLog()
check(quests.Opened() == opened + 1,
	"the client's own toggle was not handed back")
ns.db.questsHideBlizz = true
ns.QuestBlizzard.Apply()

----------------------------------------------------------------------
-- The map behind the tab
----------------------------------------------------------------------

-- Five questions the drawing cannot answer and reading it will not either.
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
-- Scoped in a do block for the reason the margin check above is: an indented
-- local is not a name at chunk level, and this file is against the budget
-- scripts/check.sh holds every section to.
do
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

	for _ = 1, 20 do
		Window.Zoom(-1)
	end
	check(Window.Zoom() == 1,
		("twenty notches back took the zoom to %s"):format(tostring(Window.Zoom())))
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
end

print(("quests %s, %d quests in %d zones, %d ready; cursor stranded %d times; Blizzard's %s")
	:format(Window.Describe(), (Log.Tally()), Log.Count(), select(2, Log.Tally()),
		quests.Stranded(), ns.QuestBlizzard.Describe()))
