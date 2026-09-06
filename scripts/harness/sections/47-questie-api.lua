-- Questie's declared-stable API
--
-- Three questions, and the first two are about a client this run is not on.
--
-- Does the door stay shut. `Questie.API` is a table on another addon's global,
-- reached without the loader every other question goes through, and the three
-- ways it is not there are three different clients: no Questie at all, Questie
-- v6 with no Public/ folder in it, and a Public/ that does not carry the call
-- being asked for. All three have to answer nil and say nothing, because a
-- quest log that errors on a machine without Questie is a quest log that is
-- broken for everyone who does not use it.
--
-- Does the wait work. Questie flips `isReady` at the end of its own third init
-- stage, which is minutes after login on a cold database, so the callback the
-- window registers at PLAYER_LOGIN sits in a queue until then. What is
-- measured is that it sat there and that the flip ran it: a window that wired
-- itself up to quest updates at login on the assumption Questie was ready would
-- pass every other assertion in this file and be listening to nothing in a real
-- game.
--
-- And does the update reach the paint. It is a second source next to the
-- client's four events, so it redraws an open window and leaves a closed one
-- alone, on the same rule the client's four are held to.

local H = ...
local ns, check = H.ns, H.check
local quests, questie = H.quests, H.questie

local Window = ns.QuestWindow

----------------------------------------------------------------------
-- The door
----------------------------------------------------------------------

local installed = _G.Questie
local REASONS = installed.API.Enums.QuestUpdateTriggerReason

-- No Questie. Not an install that answers nothing: no global at all, which is
-- what every client without the addon has.
_G.Questie = nil
check(ns.QuestieAPI("RegisterOnReady") == nil,
	"the API came back on a client with no Questie global at all")
check(Window.Attach() == false,
	"the window attached itself to an addon that is not installed")

-- Questie v6, which is a Questie running perfectly well with no Public/ in it.
-- The global is there and the field is not, and that is the whole difference
-- between the two versions from outside.
_G.Questie = { db = { profile = {} } }
check(ns.QuestieAPI("RegisterOnReady") == nil,
	"a Questie with no API table on it answered as one that has one")
check(Window.Attach() == false, "the window attached to a v6 Questie's API")

-- A Public/ that does not carry the call. The four stable things arrived over
-- four releases, so an install with the folder in it is not an install with
-- everything in the folder, and the name is what tells them apart.
_G.Questie = { API = { isReady = true } }
check(ns.QuestieAPI("RegisterOnReady") == nil,
	"an API table without the call on it came back anyway")
check(Window.Attach() == false,
	"the window called a register that is not there on this Questie")

_G.Questie = installed

local api = ns.QuestieAPI("RegisterOnReady")
check(api == installed.API,
	"asking for a call that is there did not hand back the API table")
-- The table rather than the function, and this is what that is for. isReady is
-- the fourth stable thing and it is a field, so a door that handed back only
-- the call it was asked for could not answer the question the README puts
-- first.
check(api.isReady == false,
	"Questie read as ready before its database had finished compiling")

----------------------------------------------------------------------
-- The wait
----------------------------------------------------------------------

-- What login left. The window attached at PLAYER_LOGIN, when the stub's
-- Questie was present and not ready, so there is one callback queued and
-- nothing yet listening for a quest update. The three refusals above added
-- neither.
local waiting, listening = questie.Listening()
check(waiting == 1, ("%d callbacks are waiting on Questie where login left one")
	:format(waiting))
check(listening == 0,
	"the window listened for quest updates before Questie said it was ready")

check(questie.Ready() == 1,
	"the database finishing did not run the callback waiting on it")
waiting, listening = questie.Listening()
check(waiting == 0, "the ready queue was run and not emptied")
check(listening == 1,
	"Questie became ready and nothing registered for its quest updates")

-- The other way in, which is the one a reload takes: a client where Questie
-- compiled its database before this addon asked. Questie runs the callback in
-- the call itself rather than queueing it, so the window is listening by the
-- time Attach returns.
check(Window.Attach() == true, "attaching to a ready Questie was refused")
waiting, listening = questie.Listening()
check(waiting == 0, "attaching to a ready Questie queued a wait anyway")
check(listening == 2, "attaching after ready did not register in the same call")

----------------------------------------------------------------------
-- The update
----------------------------------------------------------------------

local was = Window.Shown()

-- Every read of the log opens the client's headers first, so the client's
-- count of that is what says a paint happened. It is the cheapest probe that
-- cannot be satisfied by the window merely being asked.
Window.Show()
local reads = quests.Expanded()
check(questie.Update(102, 1, REASONS.QUEST_UPDATED) == 2,
	"the update did not reach every callback registered for it")
check(quests.Expanded() > reads,
	"a quest update from Questie did not redraw the open window")

-- And the rule the client's four events are held to, which this one does not
-- get to break: sixty rows and three borrows of the shared cursor are not read
-- for a window nobody is looking at.
Window.Hide()
reads = quests.Expanded()
questie.Update(102, nil, REASONS.QUEST_TURNED_IN)
check(quests.Expanded() == reads,
	"a quest update redrew a quest log that is not on the screen")

if was then
	Window.Show()
end

print(("quests questie ready, %d registered for its updates, and the three ways it is not there all answer nil")
	:format(select(2, questie.Listening())))
