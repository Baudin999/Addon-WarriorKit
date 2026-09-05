local ADDON, ns = ...

local UI = ns.UI

local Calls = {}
ns.CombatTextCalls = Calls

--------------------------------------------------------------------------
-- The word above your head
--
-- Execute comes up and the word Execute rises off the third anchor, once, at
-- the moment it comes up. Overpower and Revenge do the same when the fight
-- opens their window. That is the whole feature, and the reason it is worth a
-- file is that "the moment it comes up" is not something either of the two
-- parts that know the answer ever says out loud.
--
-- **Neither source sends an event.** Buttons/Requires.lua reads a condition off
-- the target's health, which is a reading and not a message; the client fires
-- UNIT_HEALTH and the answer to "is Execute up" changes once in a fight,
-- somewhere in the middle of a stream of them. Buttons/Reaction.lua clocks a
-- window that opens on a combat log line and shuts on a clock running out, and
-- nothing at all is sent for the second half of that. So both are polled here
-- and the edge is found by comparison, which is what those two files already do
-- for the bars.
--
-- **It does not borrow their edge detectors.** Reaction.Moved and the one
-- inside Requires both answer "has anything changed since you last asked" and
-- both clear their own record when asked. Calling either would take the edge
-- away from the bar that repaints on it, and the bar would stop drawing the
-- square that just lit up. So this keeps its own record of what was true last
-- pass, which costs one boolean per ability.
--
-- **Only in a fight.** The tick is armed by entering combat and stopped by
-- leaving it. Out of combat there is nothing to announce, and a tick that reads
-- two booleans five times a second for the whole of an evening in a city is the
-- cost this part would otherwise put on everybody.
--
-- **Only what you have learned.** A class file names an ability whether or not
-- this character has trained it, so a level twenty warrior would be told about
-- Execute every time something dropped under a fifth. IsSpellKnown is asked per
-- entry, which is one call for a warrior and none for anybody else.
--------------------------------------------------------------------------

-- Five times a second. A window is five seconds long and a condition changes
-- once a fight, so this is far finer than either needs; what sets it is the
-- announcement itself, which is late enough to be useless if it arrives a third
-- of a second after the square lit up.
local EVERY = 0.2

-- One entry per ability that can be announced, built at login off the class.
--
--   kind   "window" for a reaction, "condition" for a requirement
--   spell  the id, for asking whether this character has it
--   key    the class's own key, for a reaction
--   name   the client's own name for the spell, which is the word drawn
local watch = {}

-- What each entry answered last pass. Indexed alongside watch rather than by
-- key, because two entries of different kinds could name the same word.
local was = {}

local events = CreateFrame("Frame")
local tick

--------------------------------------------------------------------------

-- Whether this ability is up right now.
--
-- Both readers answer nil or false about a character they have nothing to say
-- for, so a class that registered neither list runs this never: `watch` is
-- empty and the walk below does not start.
local function Ready(entry)
	if not IsSpellKnown(entry.spell) then
		return false
	end
	if entry.kind == "window" then
		return ns.Reaction.Watching() and ns.Reaction.Open(entry.key)
	end
	-- Nil is met, which is the only one of the three answers worth a word. The
	-- other two are "nothing to aim it at" and "not low enough yet", and both
	-- of those are the ordinary state of an ability nobody is waiting on.
	return ns.Requires.Watching() and ns.Requires.State(entry.name) == nil
end

-- Every watched ability compared against what it said last pass, and a word for
-- each one that has just come up.
--
-- Exported because ns.UI.Ticker takes a named function and scripts/hot.lua
-- walks out from the name it is given.
function Calls.Beat()
	if not ns.db.hits or not ns.db.hitsCalls then
		return
	end
	for index = 1, #watch do
		local entry = watch[index]
		local now = Ready(entry) and true or false
		if now ~= was[index] then
			was[index] = now
			if now then
				ns.CombatTextNumbers.Word(entry.name)
			end
		end
	end
end

--------------------------------------------------------------------------

-- The list, built once off whatever this character's class registered.
--
-- Rank one of each, by id, for the reason Buttons/Reaction.lua matches by name:
-- every rank of Execute is called Execute, so one id per ability outlives a
-- trainer visit and a rank list does not.
local function Arm()
	local reactive = ns.Class.Of("reactive")
	if reactive then
		for index = 1, #reactive do
			local entry = reactive[index]
			local name = entry.spell and ns.SpellName(entry.spell)
			if name then
				watch[#watch + 1] = {
					kind = "window", spell = entry.spell, key = entry.key, name = name,
				}
			end
		end
	end

	local requires = ns.Class.Of("requires")
	if requires then
		for index = 1, #requires do
			local entry = requires[index]
			local name = entry.spell and ns.SpellName(entry.spell)
			if name then
				watch[#watch + 1] = { kind = "condition", spell = entry.spell, name = name }
			end
		end
	end
end

-- In a fight the tick runs, out of one it does not, and switching the part off
-- stops it wherever it is.
function Calls.Apply()
	local want = ns.db.hits and ns.db.hitsCalls
		and #watch > 0 and InCombatLockdown()

	if not want then
		if tick and tick:Running() then
			tick:Stop()
		end
		return
	end

	if not tick then
		tick = UI.Ticker(UI.Forever, EVERY, "calls", Calls.Beat)
	elseif not tick:Running() then
		tick:Start()
	end
end

-- What can be announced on this character, for the settings page. A class that
-- registered neither list gets a sentence saying so rather than a page of
-- controls for a thing that will never fire.
function Calls.Count()
	return #watch
end

function Calls.Describe()
	if #watch == 0 then
		return "nothing on this class announces itself"
	end
	if not ns.db.hitsCalls then
		return "off"
	end
	return ("watching %d"):format(#watch)
end

--------------------------------------------------------------------------

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		Arm()
	end
	-- Leaving a fight clears what was true in it, so the first thing to come up
	-- in the next one is announced rather than compared against a window that
	-- was open when the last one ended.
	if event == "PLAYER_REGEN_ENABLED" then
		for index = 1, #was do
			was[index] = false
		end
	end
	Calls.Apply()
end)
