local ADDON, ns = ...

local Reaction = {}
ns.Reaction = Reaction

--------------------------------------------------------------------------
-- The abilities the fight hands you
--
-- A warrior's Overpower is pressable for a few seconds after the target dodges.
-- Revenge is the same mechanism seen from the other side: it opens when you
-- block, dodge or parry. Nothing else a warrior owns works this way, and on
-- these clients no other class owns anything that does.
--
-- One file for however many there are, because they are one idea. The trigger differs by which
-- end of the swing you are on and everything after that is identical: a clock
-- that starts on a combat log line, runs for a fixed few seconds, and stops
-- early when you spend it. Two copies of that clock is how the two drift, and
-- the drift would be silent, because each is right most of the time.
--
-- Why this exists at all. IsUsableAction answers yes for Overpower in Battle
-- Stance whether or not anything has dodged you. It is not lying about a
-- resource and it is not confused: the client simply has no idea, because the
-- window lives on the server and nothing is sent down for it. There is no aura
-- to scan, no cooldown to read, no event that fires when the window opens and
-- none when it shuts. So the bars drew Overpower as ready for the whole fight,
-- which is the one square on the bar whose whole point is that it is usually
-- not.
--
-- The combat log is the only source, exactly as it is for the swing timer, so
-- this file is shaped like Swing/Swing.lua and reads the same event the same
-- way: one handler, one subevent test, positional reads by index, and no state
-- the log did not put there.
--
-- A macro counts. This file used to see a plain spell and nothing else, so an
-- Overpower behind `#showtooltip` drew ready all fight and the gate had a hole
-- in it exactly where a loadout would put one. Buttons/Slot.lua resolves both
-- shapes to the client's own name for the spell and this file matches on that,
-- so neither the hole nor the distinction exists here any more.
--
-- Which abilities work this way, and what opens each, is a fact about your
-- class and lives in Class/<yours>.lua as `reactive`. This file knows two
-- triggers and nothing else: `dodged` is your own attack being dodged, and
-- `defended` is you blocking, dodging or parrying. A class that names neither
-- registers nothing, the clocks never move, and Reaction.Of answers nil for
-- every square, so no bar anywhere is gated on a window that could not open.
--
-- Decided once at PLAYER_LOGIN the way Charge/Feature.lua decides it, because
-- everything below is one table built off the class and then read on the tick.
--------------------------------------------------------------------------

local CombatLogGetCurrentEventInfo = _G.CombatLogGetCurrentEventInfo

-- The two triggers this file can watch. A class names one of these against
-- each of its reactive abilities and nothing else here is a class fact.
Reaction.DODGED = "dodged"     -- your own attack was dodged
Reaction.DEFENDED = "defended" -- you blocked, dodged or parried

-- Filled at PLAYER_LOGIN off the class, and read on the tick after that.
--
--   keys      the class's own keys, in the order it wrote them
--   spellOf   key to the rank 1 id the client is asked to name it by
--   openUntil key to when its window shuts, on the client's own clock
--   opens     trigger to the key it opens, or nil for a trigger this class
--             has nothing on
--
-- Rank 1 of each, because every other rank is matched by name against it. A
-- rank list would go stale at the next trainer visit and be wrong on a client
-- that shipped a rank nobody wrote down.
--
-- Matching on the name is locale-proof for the reason the debuff scan in
-- UnitFrames/EnemyBars.lua is: both sides of the comparison are the client's
-- own name for a spell, so a localised name is being matched against itself.
-- Nothing here ever compares against an English string.
--
-- Written in place forever. A reaction tracker that built a record per window
-- would be the shape check.sh's allocation gate exists to refuse.
local keys, spellOf, openUntil, opens = {}, {}, {}, {}

-- How long a window stays open, in seconds. The one number in this file that is
-- neither read off the client nor a class fact this file settles: the class
-- names it, because how long the server holds a reactive open is a property of
-- the ability. Class/Warrior.lua carries the reasoning for the five it gives.
local window = 0

-- The miss types that open Revenge. Blocking, dodging and parrying are the
-- three the tooltip names and no others count: a mob that simply misses you has
-- not been stopped by anything.
local DEFENDED = {
	BLOCK = true,
	DODGE = true,
	PARRY = true,
}

-- nil until PLAYER_LOGIN, then true or the reason nothing is being tracked.
-- Nil is deliberately not false: before login nothing has looked, and a reader
-- that treated "not yet" as "no" would be answering about a character whose
-- class the client has not settled. Reaction.Of returns nil for all three
-- states, so a square is never greyed on an answer this file does not have.
local watching

local playerGUID

--------------------------------------------------------------------------
-- Which spell a slot is holding
--------------------------------------------------------------------------

local names = {}  -- key to this client's name for it, or false for no answer
local keyOf = {}  -- a spell's name to its key, or false for a spell that is neither

-- Resolved on first use rather than at load, so no other file has to load after
-- this one for it to work. Same shape as Charge.Name.
function Reaction.Name(key)
	if names[key] == nil then
		names[key] = (spellOf[key] and ns.SpellName(spellOf[key])) or false
	end
	return names[key] or nil
end

-- Which reactive ability a spell is, taking the client's own name for it.
--
-- Called from Slot.State against every square on every bar ten times a second,
-- so the answer is memoised. That is one table lookup per square once the bar
-- has been walked a first time.
--
-- The name and not the id, because the name is what the match was always
-- against: every rank of Overpower is called Overpower, which is why one id per
-- ability is enough here and a rank list would go stale at the next trainer
-- visit. Taking it as a name is also what lets a macro through. Buttons/Slot.lua
-- resolves both a plain spell and a macro to the same string, so this file no
-- longer knows or cares which of the two a square holds.
--
-- Not cached until the client has named at least one of them. A false written
-- before the spell data arrived would lock every square out of every window for
-- the rest of the session.
function Reaction.OfSpell(name)
	if watching ~= true or not name then
		return nil
	end
	local known = keyOf[name]
	if known ~= nil then
		return known or nil
	end
	local found, answered = false, false
	for index = 1, #keys do
		local key = keys[index]
		local mine = Reaction.Name(key)
		if mine then
			answered = true
			if name == mine then
				found = key
				break
			end
		end
	end
	if not answered then
		return nil
	end
	keyOf[name] = found
	return found or nil
end

-- Which reactive ability a spell id is. The combat log's side of the same
-- question: every line names a spell by id and every square names one by
-- string, so the two meet here rather than in two copies of the match.
local function KeyForSpell(id)
	return Reaction.OfSpell(ns.SpellNameHeld(id))
end

-- Which reactive ability this action slot holds, or nil for the other
-- twenty-three squares on the bar.
--
-- A thin call now. Buttons/Slot.lua owns what is in a slot, including the macro
-- case this used to give up on, and Slot.State reaches OfSpell directly with a
-- name it has already resolved. What is left is the question asked of a slot,
-- which is what the status line and the harness ask.
--
-- Nothing is held against the slot itself. Buttons/Slot.lua's rule is that
-- nothing is cached that the client already holds, and what is in a slot is the
-- client's to hold: a cache here would need invalidating on every drag, every
-- stance page and every rank refresh, and would be wrong between the change and
-- the event.
function Reaction.Of(slot)
	if watching ~= true or not slot then
		return nil
	end
	return Reaction.OfSpell((ns.Slot.Spell(slot)))
end

--------------------------------------------------------------------------
-- Reading a window back
--------------------------------------------------------------------------

-- Whether that press would land right now, as far as the window is concerned.
-- Says nothing about stance, rage, range or the ability's own cooldown; four
-- other rungs of the ladder own those.
function Reaction.Open(key)
	return (openUntil[key] or 0) > GetTime()
end

-- Seconds left, floored at zero. Nothing draws this today. It is here because
-- the number is the whole state of the file and a status line that cannot show
-- it cannot be used to check the duration against the live client.
function Reaction.Remaining(key)
	local left = (openUntil[key] or 0) - GetTime()
	return left > 0 and left or 0
end

function Reaction.Watching()
	return watching == true
end

--------------------------------------------------------------------------
-- The log
--
-- The same event Meter/Meter.lua and Swing/Swing.lua read, read the same way.
-- Five subevents matter and the value this file wants sits in a different slot
-- in each of them, so every read is by index and none is guessed:
--
--   SWING_MISSED    12 is the miss type
--   SPELL_MISSED    12 is the spell, 15 is the miss type
--   SWING_DAMAGE    12 is the amount, 16 is how much of it was blocked
--   SPELL_DAMAGE    12 is the spell, 15 is the amount, 19 is the blocked part
--   SPELL_CAST_SUCCESS  12 is the spell
--
-- The damage pair is not an optimisation. A block that stops the whole hit
-- arrives as SWING_MISSED with "BLOCK", and a block that stops part of it
-- arrives as a landed hit carrying a blocked amount. A tank blocks partially
-- far more often than fully, so a parser that read only the miss events would
-- have Revenge dark through most of a fight it was open in.
--------------------------------------------------------------------------

local function OnLog()
	-- Read again where the two events that own it came up with nothing. That is
	-- not belt and braces: both of them fire around a loading screen and nowhere
	-- else, so a client that had no GUID for you at either moment would leave
	-- this file inert until the next zone, with nothing on screen to say so. In
	-- the steady state it is one comparison per log line.
	if not playerGUID then
		playerGUID = UnitGUID("player")
		if not playerGUID then
			return
		end
	end

	local _, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _,
		arg12, _, _, arg15, arg16, _, _, arg19 = CombatLogGetCurrentEventInfo()

	if sourceGUID == playerGUID then
		-- Spending it shuts it. The server takes the window away on the press
		-- and sends nothing to say so, so without this the square stays lit for
		-- the rest of the five seconds after the one press it had.
		if subevent == "SPELL_CAST_SUCCESS" then
			local key = KeyForSpell(arg12)
			if key then
				openUntil[key] = 0
			end
			return
		end

		-- Your attack was dodged, which is the whole of Overpower's condition.
		-- A dodged special counts as well as a dodged white hit, so both miss
		-- subevents are read.
		local missed
		if subevent == "SWING_MISSED" then
			missed = arg12
		elseif subevent == "SPELL_MISSED" then
			missed = arg15
		end
		if missed == "DODGE" and opens[Reaction.DODGED] then
			openUntil[opens[Reaction.DODGED]] = GetTime() + window
		end
		return
	end

	if destGUID ~= playerGUID then
		return
	end

	-- You stopped something, which is the whole of Revenge's condition.
	local missed
	if subevent == "SWING_MISSED" then
		missed = arg12
	elseif subevent == "SPELL_MISSED" then
		missed = arg15
	end
	if missed then
		if DEFENDED[missed] and opens[Reaction.DEFENDED] then
			openUntil[opens[Reaction.DEFENDED]] = GetTime() + window
		end
		return
	end

	local blocked
	if subevent == "SWING_DAMAGE" then
		blocked = arg16
	elseif subevent == "SPELL_DAMAGE" then
		blocked = arg19
	end
	if type(blocked) == "number" and blocked > 0 and opens[Reaction.DEFENDED] then
		openUntil[opens[Reaction.DEFENDED]] = GetTime() + window
	end
end

--------------------------------------------------------------------------

function Reaction.Describe()
	if watching == nil then
		return "not decided yet"
	end
	if watching ~= true then
		return watching
	end
	local open = ""
	for index = 1, #keys do
		local key = keys[index]
		local left = Reaction.Remaining(key)
		if left > 0 then
			open = open .. (open == "" and "" or ", ")
				.. (Reaction.Name(key) or key) .. (", %.1fs"):format(left)
		end
	end
	if open == "" then
		return ("%gs windows, all %d shut"):format(window, #keys)
	end
	return ("%gs windows, "):format(window) .. open
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Decided once, at login, and never at file scope. The README's trap says why:
-- class data is not reliable while the files load, so a file-scope answer locks
-- a warrior out for the session.
local function Arm()
	playerGUID = UnitGUID("player")
	if watching ~= nil then
		return
	end
	local list = ns.Class.Of("reactive")
	if not list or #list == 0 then
		watching = ("no ability a %s owns opens on a dodge or on a block")
			:format(ns.Class.Label())
		return
	end
	if type(CombatLogGetCurrentEventInfo) ~= "function" then
		watching = "this client has no combat log to read, so neither window can be seen"
		return
	end
	-- Asked of Buttons/Slot.lua rather than probed here. That file resolves
	-- what is in a slot for the whole addon now, including the macro case, so a
	-- second probe would be a second answer to a question that has one.
	local canName, why = ns.Slot.CanName()
	if not canName then
		watching = why
		return
	end

	-- Built once, here, and read on the tick after that. Everything above has
	-- already refused, so nothing half-filled is ever left behind.
	window = list.window or 0
	for index = 1, #list do
		local entry = list[index]
		keys[index] = entry.key
		spellOf[entry.key] = entry.spell
		openUntil[entry.key] = 0
		opens[entry.on] = entry.key
	end

	watching = true
	events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
end

events:SetScript("OnEvent", function(_, event)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		OnLog()
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- The fight is over, so nothing else is going to dodge you and nothing
		-- else is going to hit your shield. Shut both rather than let them run
		-- out, the same way Swing.lua stops a swing that is not coming.
		for index = 1, #keys do
			openUntil[keys[index]] = 0
		end
	else
		Arm()
	end
end)
