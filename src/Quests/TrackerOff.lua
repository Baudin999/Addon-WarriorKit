local ADDON, ns = ...

local Off = {}
ns.QuestTrackerOff = Off

--------------------------------------------------------------------------
-- Questie's tracker, switched off by its own hand
--
-- **Its own call and nothing else.** `QuestieTracker:Disable()` is what
-- Questie's own "Enable Tracker" checkbox calls, and `Enable()` is what puts it
-- back; Modules/Options/TrackerTab/QuestieOptionsTracker.lua is four lines long
-- for exactly this. There is no Hide here, no SetParent, and nothing goes into
-- Core/Attic.lua.
--
-- The attic is for Blizzard's frames and the difference is who else is holding
-- them. Nothing re-parents a client frame behind us; Questie re-shows its
-- tracker on a dozen of its own events, so a frame hidden here comes back on
-- the first quest accepted and the answer to that is to hide it again, forever,
-- once per event. Turning the feature off at the source is one call and the
-- events stop happening.
--
-- **This addon writes another addon's saved setting, and that is new.**
-- Everything else it does to a neighbour is a function swap it can hand back
-- inside the session. `Questie.db.profile.trackerEnabled` outlives the session,
-- outlives this addon being uninstalled, and is a box the player may well have
-- ticked themselves. A feature that moved it quietly is a feature that reads as
-- Questie breaking, so it gets a switch with its own name on it and a clause in
-- `/wk status` saying which way the setting is and who put it there.
--
-- **Two ends and a record between them.** Quests/Blizzard.lua's rule is that
-- the switch owns the state and the file's job is that the two ends agree, and
-- there the two ends are our switch and our own cage. Here there is a third
-- party: Questie's setting has an owner who is not us. So `questsTrackerTook`
-- is the record of whether this addon is the one holding the tracker off, and
-- it is a saved variable rather than an upvalue because `Disable()` reloads the
-- interface and an upvalue would not survive the reload it caused.
--
-- The record is what stops the two failures that are not symmetrical. With the
-- switch on and the tracker already off because the player turned it off in
-- Questie, nothing is done and nothing is claimed, so unticking our box later
-- does not switch on a tracker the player never wanted. And with the switch on
-- and the record set, the two ends agree at every login after the first, so
-- `Disable()` runs once rather than once a session.
--
-- **Neither call is made in combat.** Questie's own checkbox greys itself out
-- on InCombatLockdown and the reason is on the other side of the call: Enable
-- rebuilds the tracker's frames. Work refused here is booked and run at
-- PLAYER_REGEN_ENABLED, which is the shape every deferred build in this addon
-- takes, and `/wk status` says so while it is waiting.
--
-- **Both calls reload the interface.** Questie's Disable ends in ReloadUI and
-- its Enable hands ReloadUI to ThreadLib as the callback; its own checkbox says
-- so in the description text. Nothing here can avoid that and nothing should
-- try, so the panel says it in front of the box.
--------------------------------------------------------------------------

-- Work combat refused, run again when it ends.
local pending = false

-- Questie's tracker module, or nil, asked for by the two calls this file makes.
--
-- QuestieTracker is a module on Questie's own loader rather than anything in
-- Public/, so it comes through ns.Questie and not ns.QuestieAPI. Both calls are
-- declared with a colon in Questie's source and are therefore called with one
-- here; ns.Questie checks that the field is a function, which is the same
-- question for either spelling.
local function Module()
	return ns.Questie("QuestieTracker", "Enable", "Disable")
end

-- Questie's settings table, or nil, and it answers three things at once: that
-- Questie is installed, that its database has initialised past the preinit
-- placeholder in Modules/VersionCheck.lua, and that this build still spells the
-- setting this way.
local function Profile()
	return ns.QuestieProfile("trackerEnabled")
end

--------------------------------------------------------------------------

-- Whether Questie's tracker should be off right now. The quest log's own switch
-- is half of it, because a part switched off does not reach into a neighbour.
function Off.Wanted()
	return (ns.db.quests and ns.db.questsTrackerOff) and true or false
end

-- Whether this addon is the one holding it off.
function Off.Took()
	return ns.db.questsTrackerTook and true or false
end

-- Make the two ends agree, and answer whether a call was made.
--
-- Four states and two of them do nothing, which is the point: the pair that
-- moves is the switch changing, and every login after that finds them agreeing
-- already.
function Off.Apply()
	local profile, tracker = Profile(), Module()
	if not profile or not tracker then
		pending = false
		return false
	end

	local wanted, took = Off.Wanted(), Off.Took()
	if wanted == took then
		return false
	end

	-- Wanted and not ours yet. A tracker that is already off is the player's
	-- own doing and is left alone unclaimed, so unticking the box later cannot
	-- switch it back on.
	if wanted then
		if not profile.trackerEnabled then
			return false
		end
		if InCombatLockdown() then
			pending = true
			return false
		end
		pending = false
		ns.db.questsTrackerTook = true
		tracker:Disable()
		return true
	end

	-- Ours and no longer wanted. Somebody putting the tracker back in Questie's
	-- own options while our box was ticked ends the claim without a call: the
	-- setting is already where unticking would have put it.
	if profile.trackerEnabled then
		pending = false
		ns.db.questsTrackerTook = false
		return false
	end
	if InCombatLockdown() then
		pending = true
		return false
	end
	pending = false
	ns.db.questsTrackerTook = false
	tracker:Enable()
	return true
end

-- Whether a call is booked for the end of combat.
function Off.Waiting()
	return pending
end

-- Short enough for a reading on the options page, which never wraps. The noun
-- is supplied by whoever prints it.
function Off.Describe()
	local profile = Profile()
	if not profile or not Module() then
		return "not here to switch off"
	end
	if pending then
		return "waiting for combat to end"
	end
	if Off.Took() then
		return "off, and this addon turned it off"
	end
	return profile.trackerEnabled and "on" or "off, and Questie turned it off"
end

--------------------------------------------------------------------------

local function OnEvent(_, event)
	if event == "PLAYER_LOGIN" or pending then
		Off.Apply()
	end
end

-- Login rather than load, for the reason Quests/Window.lua gives about the
-- function swap beside this one: the addon being reached into may not have
-- loaded yet, and Questie fills its settings table in at ADDON_LOADED.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", OnEvent)
