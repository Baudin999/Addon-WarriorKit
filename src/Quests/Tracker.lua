local ADDON, ns = ...

local Tracker = {}
ns.QuestTracker = Tracker

--------------------------------------------------------------------------
-- Questie's tracker, pointed at this window
--
-- Clicking a quest in Questie's tracker opens the quest log at that quest. That
-- is the right behaviour and it is the whole problem: the log it opens is
-- Blizzard's, and Blizzard's is in the attic. So the one gesture a player makes
-- forty times an evening led to a window that is not on the screen any more.
--
-- Questie routes every one of those through a single function.
-- TrackerUtils:ShowQuestLog(quest) is called by the tracker's own click handler
-- in Modules/Tracker/LinePool/TrackerLine.lua and by the "Show in Quest Log"
-- line of its right-click menu in TrackerMenu.lua, so one replacement covers
-- both and there is no second path to keep in step.
--
-- **It is a function swap, and it is the addon's second.** Quests/Blizzard.lua
-- makes the same argument about ToggleQuestLog and it is worth reading there:
-- the original is kept, the switch puts it back, and the swap happens at login
-- rather than at load because the thing being replaced belongs to another addon
-- that may not have loaded yet.
--
-- **It follows the same switch the L key does.** Untick "put Blizzard's quest
-- log in the attic" and the tracker opens Blizzard's log again, because that is
-- the window the player has just said they want. A tracker that opened this
-- addon's window while the client's own log was on screen and holding the key
-- would be two logs and no rule about which one anything means.
--
-- **Everything here degrades to nothing.** Questie may not be installed, may be
-- a version whose tracker moved, or may have its tracker switched off. All
-- three are the same answer: no swap, and the player's clicks go wherever they
-- went before.
--------------------------------------------------------------------------

-- Whoever is holding the function now, remembered once, so a second addon that
-- wrapped it after this one is not swallowed by a later re-apply.
local original = nil
local taken = false

-- The table ShowQuestLog is a field on.
--
-- Questie hands out one table per module name and every Questie file takes its
-- reference from that, so writing the field on the module is what a click
-- reads. The name is TrackerUtils, its own module, and this file spent its
-- first version asking for QuestieTracker and reading a `utils` field off it.
-- There is no such field on any build that ships, so the swap never happened
-- and every click went to the log in the attic. Both spellings are still tried,
-- because a build that answers for neither name is the same answer as no
-- Questie at all, and ns.Questie in Core is what asks for the call by name.
local function Utils()
	local utils = ns.Questie("TrackerUtils", "ShowQuestLog")
	if utils then
		return utils
	end
	local tracker = ns.Questie("QuestieTracker")
	if tracker and type(tracker.utils) == "table"
		and type(tracker.utils.ShowQuestLog) == "function" then
		return tracker.utils
	end
	return nil
end

--------------------------------------------------------------------------

-- Open this window on one quest id, and answer whether it landed there.
--
-- The id is turned into this addon's own key rather than an index, for the
-- reason Quests/Log.lua gives at length: an index is a position that moves the
-- next time you hand anything in, and the window is being asked for a quest.
function Tracker.Open(questId)
	if not ns.db.quests then
		return false
	end
	-- Asked of the client before anything is put on the screen, because a
	-- tracker can be holding a quest you are not on and the fall-through has to
	-- be a clean no rather than this window opening on whatever it showed last.
	if not ns.QuestClient.IndexOf(questId) then
		return false
	end
	local key = ns.QuestLog.Key({ id = questId })
	ns.QuestWindow.Show()
	return ns.QuestWindow.Showing(key) == key
end

--------------------------------------------------------------------------

-- Whether the tracker's clicks should come here right now. The same switch that
-- takes the L key, because they are the same question asked by two gestures.
function Tracker.Wanted()
	return ns.QuestBlizzard.Wanted()
end

function Tracker.Apply()
	local utils = Utils()
	if not utils or type(utils.ShowQuestLog) ~= "function" then
		return false
	end
	if original == nil then
		original = utils.ShowQuestLog
	end

	local wanted = Tracker.Wanted()
	if wanted == taken then
		return false
	end
	taken = wanted

	if not wanted then
		utils.ShowQuestLog = original
		return true
	end

	-- The quest object is Questie's own and the id is the only field read off
	-- it. A click that arrives with something else on it falls through to
	-- whatever was there before rather than swallowing the gesture.
	utils.ShowQuestLog = function(self, quest)
		if type(quest) == "table" and type(quest.Id) == "number"
			and Tracker.Open(quest.Id) then
			return
		end
		return original(self, quest)
	end
	return true
end

function Tracker.Taken()
	return taken
end

function Tracker.Describe()
	if not Utils() then
		return "Questie's tracker is not here to click"
	end
	if not taken then
		return "clicking a quest in it opens Blizzard's log"
	end
	return "clicking a quest in it opens this window on that quest"
end
