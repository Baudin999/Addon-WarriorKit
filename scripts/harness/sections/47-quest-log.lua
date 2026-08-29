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

-- The two colours the log is actually read for at a glance. A quest ready to
-- hand in is the tick green whatever its level, and one that failed is the loss
-- red, and neither of them is the XP ladder every other row is on.
local complete, failed
for _, row in ipairs(drawn) do
	if row.label == "[11] Wanted: Hogger" then complete = row end
	if row.label == "[18] Red Silk Bandanas" then failed = row end
end
check(complete and complete.color == ns.UI.Color.tick,
	"a quest ready to hand in is not drawn in the tick colour")
check(failed and failed.color == ns.UI.Color.loss,
	"a failed quest is not drawn in the loss colour")
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

print(("quests %s, %d quests in %d zones, %d ready; cursor stranded %d times; Blizzard's %s")
	:format(Window.Describe(), (Log.Tally()), Log.Count(), select(2, Log.Tally()),
		quests.Stranded(), ns.QuestBlizzard.Describe()))
