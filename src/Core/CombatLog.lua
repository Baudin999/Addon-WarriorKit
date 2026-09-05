local ADDON, ns = ...

local CombatLog = {}
ns.CombatLog = CombatLog

--------------------------------------------------------------------------
-- The combat log, read once
--
-- COMBAT_LOG_EVENT_UNFILTERED is the busiest event the client sends. In a five
-- man pull with fifteen plates up it is around sixty lines a second, and the
-- values on a line come from nowhere but CombatLogGetCurrentEventInfo, which
-- hands over twenty one of them.
--
-- Six parts of this addon read that log and every one of them used to make the
-- call itself: the meters, the breakdown record, the swing timer, the combat
-- feed, the reaction windows and the thank you whisper. Six unpacks a line is
-- about seven thousand value copies a second before a single filter has run,
-- and three of the six were doing it for a feature that was switched off.
--
-- So the call is made here, once, and the values go out to a plain array of
-- subscribers as the arguments they already are. Nothing is wrapped in a table:
-- a table per line is garbage the collector walks in the middle of a frame, and
-- all six parts already read the log positionally.
--
-- **The twenty second argument is your own GUID.** Five of the six reject a
-- line on it before anything else, and Feeds/Combat.lua was calling
-- UnitGUID("player") on every line that got past its shape filter to ask. It is
-- read at login and handed over with the rest, so no subscriber asks the client
-- who it is.
--
-- **A part with its switch off does not subscribe, and an empty array
-- unregisters the event.** An evening with the meters, the breakdown and the
-- swing bars off costs the client nothing at all rather than three unpacks a
-- line. Comfort/Thanks.lua has done this on its own since it shipped and its
-- comment says why; this is that shape with the other five moved onto it.
--
-- Not a bus. There is one event, one reader and one list, and a part still
-- names the source it wants by subscribing to this file rather than by asking
-- for a topic. A general stream over every client event would put one more
-- dispatch in front of every handler in the addon and would have saved nothing
-- here, because what costs is the read and not the routing.
--
-- No Perf slot either. Perf/Perf.lua times tickers, two debugprofilestop reads
-- bracketing a tick body forty times a second, and it says in its own header
-- that the bracketing has to be free to be honest. Sixty lines a second is the
-- one path in the addon where two clock reads and a table write per entry would
-- be a real fraction of what they were measuring.
--------------------------------------------------------------------------

-- Resolved once at load rather than probed per line. A client either carries
-- the call or it does not and that cannot change after login, so the guard in
-- the reader below is a truth test on an upvalue. Feeds/Combat.lua wrote this
-- out first and Meter/Meter.lua, Swing/Swing.lua and Buttons/Reaction.lua each
-- asked `type(...) == "function"` per event for the same fixed answer.
local readLog = _G.CombatLogGetCurrentEventInfo
if type(readLog) ~= "function" then
	readLog = nil
end

-- Who is reading, in the order they subscribed. A plain array because the
-- reader walks it on every line and a hash walk allocates an iterator.
local subscribers = {}

local playerGUID
local frame

-- How many lines have come through, ever. One increment on the busiest event in
-- the client, which is the cheapest thing this file could add and the only way
-- the frame trace can name the combat log as what filled a frame: Perf/Census.lua
-- counts every other event by registering for all of them, and this one event is
-- deliberately not on that list. The rule at the top of this file is that the
-- combat log is registered for once, here, and counting it twice would be the
-- same debt wearing a different name.
local lines = 0

-- Whether this client will say what happened at all. Both targets carry the
-- call, so this is expected to be true on both; a part asks it so it can say
-- in the panel that it cannot run, rather than drawing an empty table with no
-- explanation on it.
function CombatLog.Ready()
	return readLog ~= nil
end

-- Your own GUID, as the reader has it. For a part that wants it outside a log
-- line, which is Buttons/Reaction.lua deciding whether it can arm.
function CombatLog.PlayerGUID()
	return playerGUID
end

-- How many parts are reading. For the panel and for scripts/harness.lua, which
-- asserts that the client event goes away when this reaches nought.
function CombatLog.Count()
	return #subscribers
end

-- How many lines have arrived since login. Read once a frame by Perf/Trace.lua,
-- whose difference is how many landed in that frame.
--
-- It counts what this addon was handed, which is nothing at all on an evening
-- with every log reading part switched off: the event is unregistered then, by
-- design, and the frame trace says the client sent no lines because as far as
-- this addon is concerned it did not.
function CombatLog.Lines()
	return lines
end

--------------------------------------------------------------------------

-- One line, read once, handed to everybody.
local function OnLog()
	lines = lines + 1
	local count = #subscribers
	if count == 0 then
		return
	end

	-- Read again where the two events that own it came up with nothing. Both of
	-- them fire around a loading screen and nowhere else, so a client that had
	-- no GUID for you at either moment would leave every subscriber inert until
	-- the next zone with nothing on screen to say so. Breakdown/Breakdown.lua
	-- and Buttons/Reaction.lua each carried these three lines. In the steady
	-- state it is one comparison per line for all six.
	if not playerGUID then
		playerGUID = UnitGUID("player")
	end

	local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11,
		a12, a13, a14, a15, a16, a17, a18, a19, a20, a21 = readLog()

	for index = 1, count do
		-- Read out of the array rather than trusted from the count. A
		-- subscriber that leaves during a read shortens the list under this
		-- walk, and the line ends quietly instead of calling nil. Subscribe and
		-- Unsubscribe are called from a part's Apply and never from inside a
		-- line, which is what makes that a guard rather than a mechanism.
		local reader = subscribers[index]
		if reader then
			reader(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11,
				a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, playerGUID)
		end
	end
end

local function OnEvent(_, event)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		OnLog()
		return
	end
	playerGUID = UnitGUID("player")
end

frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", OnEvent)

--------------------------------------------------------------------------

-- Start reading. The function is called with the twenty one values the client
-- hands over, in the client's own order, and your GUID after them.
--
-- Idempotent, the way the client's own RegisterEvent is: a part that applies
-- its settings twice reads every line once. False on a client with no combat
-- log, so a caller can say so rather than wait for lines that will never come.
function CombatLog.Subscribe(reader)
	if not readLog or type(reader) ~= "function" then
		return false
	end

	for index = 1, #subscribers do
		if subscribers[index] == reader then
			return true
		end
	end

	subscribers[#subscribers + 1] = reader
	if #subscribers == 1 then
		frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
	return true
end

-- Stop reading, and take the addon off the event entirely once nobody is left.
-- That last half is the whole point of the file: a night with every log-reading
-- part switched off is a night the client never calls into this addon on its
-- busiest event.
function CombatLog.Unsubscribe(reader)
	for index = #subscribers, 1, -1 do
		if subscribers[index] == reader then
			table.remove(subscribers, index)
		end
	end

	if #subscribers == 0 then
		frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
end

--------------------------------------------------------------------------
-- Where the numbers are on a line
--
-- The twenty one values arrive in a fixed order and the meaning of the twelfth
-- onwards depends on the subevent. A swing puts its amount at twelve; a spell
-- puts its id, name and school there and its amount at fifteen. That is a fact
-- about the client's own log and it belongs beside the call that reads it.
--
-- Three parts worked it out for themselves and two of them still do:
-- Feeds/Combat.lua and Breakdown/Breakdown.lua each hold a copy of the table
-- below. Those two are one commit away from reading this one and are not part
-- of the change that put it here, because both of their readers carry a branch
-- count in scripts/shape.lua and moving them is a change worth making on its
-- own. CombatText/Numbers.lua is the third and it reads this rather than
-- becoming a third copy.
--
--   amount    the slot the number is in
--   spell     the slot the spell id is in, and nil for a swing, which has none
--   crit      the slot the critical flag is in
--   glancing  the slot the glancing flag is in
--   crushing  the slot the crushing flag is in
--   heal      whether the number is healing rather than damage
--   miss      the slot the miss type is in, for the shapes that carry one
--
-- Glancing and crushing are on the swing only, and that is the client rather
-- than an omission: both are melee mechanics and neither is sent for a spell.
-- On a spell they would sit at twenty two and twenty three anyway, past the end
-- of what this file hands over. Read back off Details' own parser on the live
-- 2.5.6 install, which unpacks the tail as critical, glancing, crushing.
CombatLog.SHAPES = {
	SWING_DAMAGE          = { amount = 12, crit = 18, glancing = 19, crushing = 20 },
	SPELL_DAMAGE          = { amount = 15, spell = 12, crit = 21 },
	SPELL_PERIODIC_DAMAGE = { amount = 15, spell = 12, crit = 21 },
	RANGE_DAMAGE          = { amount = 15, spell = 12, crit = 21 },
	DAMAGE_SHIELD         = { amount = 15, spell = 12, crit = 21 },
	SPELL_HEAL            = { amount = 15, spell = 12, crit = 18, heal = true },
	SPELL_PERIODIC_HEAL   = { amount = 15, spell = 12, crit = 18, heal = true },
	SWING_MISSED          = { miss = 12 },
	SPELL_MISSED          = { miss = 15, spell = 12 },
	RANGE_MISSED          = { miss = 15, spell = 12 },
}
