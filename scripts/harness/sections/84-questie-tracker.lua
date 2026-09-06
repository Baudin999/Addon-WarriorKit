-- Questie's tracker, switched off by its own hand
--
-- One claim: the switch owns the state, the state lives in another addon's
-- saved variables, and the two ends agree after exactly one call.
--
-- **Nothing here is hidden and nothing is re-parented.** The fixture's Enable
-- and Disable are the only way Questie's setting moves, so an implementation
-- that reached for the tracker's frame instead would fail every count below
-- without a single assertion about a frame. That is deliberate: a hidden frame
-- comes back on the first quest Questie hears about, and the failure would be
-- a player's evening rather than a red line here.
--
-- **A call per login is the defect this is written against.** Both of Questie's
-- calls end in ReloadUI, so a file that threw the switch every time it was
-- asked would reload the interface, come back up, and reload again. Every block
-- asks twice and counts the reloads, and that is the assertion that could not
-- be made by reading the code.
--
-- **The asymmetry is the point.** Turning the tracker off is ours to do and
-- turning it back on is only ours if we were the one that turned it off. A
-- player who switched Questie's tracker off in Questie's own options and then
-- ticked and unticked our box must end with the tracker off, and the record
-- that makes that true is the only saved variable this addon keeps about a
-- neighbour.
--
-- **Absent is four states, not one.** No Questie global, the preinit
-- placeholder Modules/VersionCheck.lua leaves in Questie.db before AceDB
-- replaces it, a loader with a tracker module that has neither call on it, and
-- combat. All four are silent and none of them writes anything down.

local H = ...
local ns, check, fire, state = H.ns, H.check, H.fire, H.state
local questie = H.questieTracker

local Off = ns.QuestTrackerOff

-- Questie installed, its tracker on, the quest log on, our box unticked and
-- nothing claimed. Every block below starts here rather than from what the one
-- above it left.
local function settle()
	questie.Away(false)
	questie.Set(true)
	ns.db.quests = true
	ns.db.questsTrackerOff = false
	ns.db.questsTrackerTook = false
end

-- The three numbers a block is measured on: the calls made and the reloads they
-- caused.
local function counts()
	local enabled, disabled = questie.Counts()
	return enabled, disabled, state.reloads
end

settle()

----------------------------------------------------------------------
-- The box ticked, once
----------------------------------------------------------------------

do
	local wasOn, wasOff, wasReloads = counts()

	ns.db.questsTrackerOff = true
	check(Off.Apply(), "the box was ticked and nothing was called")

	local on, off, reloads = counts()
	check(off == wasOff + 1, ("Disable was called %d times, not once"):format(off - wasOff))
	check(on == wasOn, "switching the tracker off called Enable as well")
	check(questie.Enabled() == false, "Questie's own setting is still on")
	check(reloads == wasReloads + 1, "Questie's Disable did not reload the interface")
	check(Off.Took(), "the tracker was switched off and the record does not say so")
	check(Off.Describe() == "off, and this addon turned it off",
		("the reading says %q"):format(Off.Describe()))

	-- Twice more, which is the next two logins. The two ends agree now, so a
	-- file that asked Questie again would reload the interface again and the
	-- game would never finish coming up.
	check(Off.Apply() == false, "the second pass called Questie again")
	check(Off.Apply() == false, "the third pass called Questie again")

	local settledOn, settledOff, settledReloads = counts()
	check(settledOff == off and settledOn == on, "a login with the two ends agreeing moved Questie")
	check(settledReloads == reloads, "a settled switch reloaded the interface")
end

----------------------------------------------------------------------
-- The box unticked, and the setting goes back
----------------------------------------------------------------------

do
	local wasOn, wasOff, wasReloads = counts()

	ns.db.questsTrackerOff = false
	check(Off.Apply(), "the box was unticked and nothing was called")

	local on, off, reloads = counts()
	check(on == wasOn + 1, ("Enable was called %d times, not once"):format(on - wasOn))
	check(off == wasOff, "putting the tracker back called Disable as well")
	check(questie.Enabled() == true, "Questie's setting did not go back")
	check(reloads == wasReloads + 1, "Questie's Enable did not reload the interface")
	check(Off.Took() == false, "the tracker was handed back and the record still claims it")
	check(Off.Describe() == "on", ("the reading says %q"):format(Off.Describe()))

	check(Off.Apply() == false, "the login after the switch went off called Enable again")
	local settledOn = counts()
	check(settledOn == on, "Enable ran on a login with nothing left to do")
end

----------------------------------------------------------------------
-- In combat, neither call
--
-- Questie's own checkbox greys itself out on InCombatLockdown and the reason is
-- on the other side of the call: Enable rebuilds the tracker's frames. So the
-- work is booked rather than done, and PLAYER_REGEN_ENABLED is what runs it.
----------------------------------------------------------------------

do
	local lockdown = _G.InCombatLockdown
	local fighting = true
	_G.InCombatLockdown = function() return fighting end

	local wasOn, wasOff, wasReloads = counts()

	ns.db.questsTrackerOff = true
	check(Off.Apply() == false, "the box was ticked in combat and Questie was called")

	local on, off, reloads = counts()
	check(off == wasOff and on == wasOn, "a call was made with the player in combat")
	check(questie.Enabled(), "Questie's setting moved in combat")
	check(reloads == wasReloads, "the interface reloaded in combat")
	check(Off.Waiting(), "the work combat refused was not booked for the end of it")
	check(Off.Describe() == "waiting for combat to end",
		("the reading says %q"):format(Off.Describe()))

	fighting = false
	fire("PLAYER_REGEN_ENABLED")

	local afterOn, afterOff = counts()
	check(afterOff == wasOff + 1, "the deferred Disable did not run when the fight ended")
	check(afterOn == wasOn, "the end of the fight called Enable")
	check(questie.Enabled() == false, "combat ended and Questie's setting had not moved")
	check(Off.Waiting() == false, "the booking outlived the call it stood for")

	-- And the other direction, because both calls build frames and both are
	-- refused for it.
	fighting = true
	ns.db.questsTrackerOff = false
	check(Off.Apply() == false, "the box was unticked in combat and Questie was called")
	check(select(1, counts()) == wasOn, "Enable ran with the player in combat")
	check(Off.Waiting(), "the refused Enable was not booked")

	fighting = false
	fire("PLAYER_REGEN_ENABLED")
	check(select(1, counts()) == wasOn + 1, "the deferred Enable did not run when the fight ended")
	check(questie.Enabled(), "combat ended and Questie's tracker was not put back")

	_G.InCombatLockdown = lockdown
end

----------------------------------------------------------------------
-- A tracker the player turned off themselves
--
-- The one asymmetry, and the reason there is a record at all. This addon may
-- switch a tracker off and put it back; it may not put back one it never took.
----------------------------------------------------------------------

do
	settle()
	questie.Set(false)

	local wasOn, wasOff = counts()
	check(Off.Describe() == "off, and Questie turned it off",
		("the reading says %q"):format(Off.Describe()))

	ns.db.questsTrackerOff = true
	check(Off.Apply() == false, "the box was ticked on a tracker that was already off")
	check(Off.Took() == false, "the addon wrote down a tracker it never switched off")
	check(select(2, counts()) == wasOff, "Disable was called on a tracker that was already off")

	ns.db.questsTrackerOff = false
	check(Off.Apply() == false, "unticking the box called Enable")
	check(select(1, counts()) == wasOn,
		"unticking the box switched on a tracker the player had turned off")
	check(questie.Enabled() == false, "the player's own setting was overwritten")
end

----------------------------------------------------------------------
-- The setting put back in Questie's own options
--
-- The claim ends when the setting does, without a call. Anything else calls
-- Enable on a tracker that is already on, which reloads the interface for
-- nothing.
----------------------------------------------------------------------

do
	settle()
	ns.db.questsTrackerOff = true
	check(Off.Apply(), "the box was ticked and nothing was called")
	check(Off.Took(), "the switch is on and the record does not claim the tracker")

	questie.Set(true)
	local wasOn, _, wasReloads = counts()

	ns.db.questsTrackerOff = false
	check(Off.Apply() == false, "Enable was called on a tracker somebody had already put back")
	check(select(1, counts()) == wasOn, "Enable ran on a tracker that was already on")
	check(select(3, counts()) == wasReloads, "the interface reloaded for a call nobody needed")
	check(Off.Took() == false, "the claim outlived the setting it was about")
end

----------------------------------------------------------------------
-- Questie away, in four ways
----------------------------------------------------------------------

do
	settle()
	ns.db.questsTrackerOff = true

	local wasOn, wasOff, wasReloads = counts()

	questie.Away(true)
	check(Off.Apply() == false, "a client with no Questie on it made a call")
	check(Off.Describe() == "not here to switch off",
		("the reading says %q"):format(Off.Describe()))
	check(ns.db.questsTrackerTook == false, "an absent Questie was written down as switched off")

	-- Installed and not initialised. Modules/VersionCheck.lua writes a profile
	-- carrying one minimap flag and calls it a preinit placeholder in the
	-- comment beside it, so a caller that checked for the table rather than for
	-- the setting would read nil here and take it for the player's answer.
	questie.Away("preinit")
	check(Off.Apply() == false, "the preinit placeholder was read as the player's settings")
	check(Off.Describe() == "not here to switch off",
		("the preinit placeholder reads as %q"):format(Off.Describe()))

	-- And the loader half: a tracker module with neither call on it, which is
	-- what ns.Questie refuses by asking for the calls by name. ImportModule
	-- hands back a table for a name it has never heard of, so the module coming
	-- back proves nothing at all.
	questie.Away(false)
	local switching = _G.QuestieLoader:ImportModule("QuestieTracker")
	local enable, disable = switching.Enable, switching.Disable
	switching.Enable, switching.Disable = nil, nil
	check(Off.Apply() == false, "a tracker module with neither call on it was called")
	check(Off.Describe() == "not here to switch off",
		("a tracker with no calls reads as %q"):format(Off.Describe()))
	switching.Enable, switching.Disable = enable, disable

	local on, off, reloads = counts()
	check(on == wasOn and off == wasOff, "an absent Questie was called anyway")
	check(reloads == wasReloads, "an absent Questie reloaded the interface")
end

----------------------------------------------------------------------
-- The two surfaces
--
-- A setting that belongs to another addon has to be reachable and has to be
-- reported, which is the whole reason this feature has a switch rather than
-- riding the one that cages Blizzard's window.
----------------------------------------------------------------------

do
	settle()

	local chat = _G.DEFAULT_CHAT_FRAME.AddMessage
	local heard = {}
	_G.DEFAULT_CHAT_FRAME.AddMessage = function(_, text)
		heard[#heard + 1] = tostring(text)
	end

	local function said(what)
		for index = 1, #heard do
			if heard[index]:find(what, 1, true) then
				return true
			end
		end
		return false
	end

	_G.SlashCmdList.WARRIORKIT("quests tracker on")
	check(ns.db.questsTrackerOff, "the typed word did not throw the switch")
	check(questie.Enabled() == false, "the typed word did not reach Questie")
	check(said("Questie's tracker is off, and this addon turned it off"),
		"the typed word did not say which way the setting is or who put it there")

	heard = {}
	_G.SlashCmdList.WARRIORKIT("status")
	check(said("Questie's tracker is off, and this addon turned it off"),
		"/wk status does not report a setting this addon moved in another addon")

	heard = {}
	_G.SlashCmdList.WARRIORKIT("quests tracker off")
	check(ns.db.questsTrackerOff == false, "the typed word did not throw the switch back")
	check(questie.Enabled(), "the typed word did not put Questie's tracker back")

	_G.DEFAULT_CHAT_FRAME.AddMessage = chat
end

----------------------------------------------------------------------

-- Back the way it was found, which for this section means Questie's tracker on
-- and this addon claiming nothing.
settle()
check(Off.Apply() == false, "the section left the two ends disagreeing")

print("quests Questie's tracker is " .. Off.Describe())
