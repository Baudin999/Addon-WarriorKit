local ADDON, ns = ...

local Requires = {}
ns.Requires = Requires

--------------------------------------------------------------------------
-- What the fight has to have done first
--
-- The rung of Buttons/Slot.lua's ladder the client cannot answer at all.
--
-- IsUsableAction knows about your resources, your stance, your cooldowns and
-- what you are wearing, and it is right about every one of them. What it knows
-- nothing about is the target. Execute is the plainest case on a warrior: it
-- can only be cast on something under a fifth of its health, and the client
-- says yes to it from full health down, so the square shouted through every
-- fight and meant it for the last twenty seconds of one.
--
-- That is the same defect Buttons/Reaction.lua was written for and it is a
-- different mechanism. A reaction window lives on the server, arrives as a
-- combat log line and has to be clocked. A condition like Execute's is visible
-- in the client the whole time and only has to be read. Two files rather than
-- one because a clock and a reading are not the same code, and because folding
-- them would put a combat log handler in front of a question that is three unit
-- calls.
--
-- What they share is the shape, deliberately: a class file names the abilities
-- and the numbers, this file knows the kinds and none of the abilities, and
-- Slot.State asks one question per square. A class that names nothing gets a
-- file that registers nothing and answers nil to every square, so no bar
-- anywhere is gated on a condition that could not apply.
--
-- One kind of condition is implemented, which is one more than the client has:
--
--   below   the target has to be under this percentage of its health
--
-- and one that every entry carries whether it says so or not: an ability that
-- names a condition is an ability aimed at something, so with nothing to aim it
-- at the answer is "notarget" before any threshold is read. That is what makes
-- the list short. Rend and Hamstring need a target too and are not here,
-- because the client already knows they are aimed at an enemy and Slot.State
-- greys every such square with nothing selected before this file is asked.
-- This file reads the same "nothing to aim at" off ns.Slot.Aimless, so a
-- threshold is never read off a unit that is not there.
--
-- Adding a second kind is a field on the entry and a branch in Unmet. It is
-- deliberately not done on speculation: "the target has to be casting" looks
-- like the obvious next one and neither of these clients agrees with the other
-- about whether an interrupt may be pressed at a target that is not, so it is
-- a fact nobody here has measured and it is not going in until somebody has.
--
-- Everything below Arm runs on the bar's ticker against every square, so
-- nothing allocates. check.sh's HOT list covers Requires.State and Unmet.
--------------------------------------------------------------------------

-- Filled at PLAYER_LOGIN off the class, and read on the tick after that.
--
--   list     the class's own entries, in the order it wrote them
--   nameOf   entry to the client's name for the spell, or false for no answer
--   found    a spell's name to its entry, or false for a spell that names none
--
-- Rank 1 of each, matched by name, for the reason Buttons/Reaction.lua matches
-- by name: every rank of Execute is called Execute, so one id per ability
-- outlives a trainer visit and a rank list does not. Both sides of the
-- comparison are the client's own name for a spell, so a localised client is
-- matching a string against itself and no English ever appears in it.
local list, nameOf, found = {}, {}, {}

-- Which unit a condition is read off. The same one Slot.State asks about range,
-- and the honest limit of the whole idea: with nothing targeted there is no
-- health to be under a fifth of.
local UNIT = "target"

-- nil until PLAYER_LOGIN, then true or the reason nothing is being read.
--
-- Nil is not false. Before login nothing has looked, and a reader treating "not
-- yet" as "no" would be answering about a character whose class the client has
-- not settled. Requires.State returns nil for all three states, so no square is
-- ever greyed on an answer this file does not have.
local watching

--------------------------------------------------------------------------
-- Which entry a spell is
--------------------------------------------------------------------------

-- Resolved on first use rather than at load, so no other file has to load after
-- this one for it to work. Same shape as Reaction.Name and Charge.Name.
local function NameOf(entry)
	if nameOf[entry] == nil then
		nameOf[entry] = ns.SpellNameHeld(entry.spell) or false
	end
	return nameOf[entry] or nil
end

-- The entry a spell's own name belongs to, memoised.
--
-- The memo is what keeps this off the tick: a table lookup per square once a
-- bar has been walked once. Nothing is written down until the client has named
-- at least one entry, because a false stored before the spell data arrived
-- would be the answer for every square for the rest of the session.
local function EntryFor(name)
	local known = found[name]
	if known ~= nil then
		return known or nil
	end
	local mine, answered = false, false
	for index = 1, #list do
		local entry = list[index]
		local called = NameOf(entry)
		if called then
			answered = true
			if name == called then
				mine = entry
				break
			end
		end
	end
	if not answered then
		return nil
	end
	found[name] = mine
	return mine or nil
end

--------------------------------------------------------------------------
-- Reading one
--------------------------------------------------------------------------

-- Which of the entry's conditions the fight has not met, or nil for all of
-- them met. Split out from State so the walk down the entry is one function and
-- the lookup that finds it is another, which is what makes adding a second kind
-- one branch here and nothing anywhere else.
--
-- Order is the ladder's own rule again, one level down: nothing to aim it at
-- outranks a threshold, because a threshold read off no unit is not a fact.
local function Unmet(entry)
	if ns.Slot.Aimless() then
		return "notarget"
	end
	if entry.below then
		-- Multiplied out rather than divided, so the comparison is two integers
		-- and lands exactly on the line. ns.Unit.Health's third return is a
		-- floored whole percentage, and a target at 20.1% floors to 20, which
		-- would open Execute a tick before the server does.
		--
		-- A maximum of zero is a client that has not said what the unit's health
		-- is, and not saying is not a refusal: a square greyed on a reading
		-- nobody gave is a square that lies for as long as the client stays
		-- quiet.
		local current, max = ns.Unit.Health(UNIT)
		if max > 0 and current * 100 > max * entry.below then
			return "condition"
		end
	end
	return nil
end

-- What is standing between a press and the spell landing, as one of
-- UI/Ability.lua's statuses, or nil for a spell this file has nothing to say
-- about. That last case is most of the bar and is answered in one table lookup.
function Requires.State(spell)
	if watching ~= true or not spell then
		return nil
	end
	local entry = EntryFor(spell)
	if not entry then
		return nil
	end
	return Unmet(entry)
end

function Requires.Watching()
	return watching == true
end

--------------------------------------------------------------------------
-- Telling the bar
--
-- The bars draw a square when something says it moved, and this file is one of
-- the two things that has to say so. What a condition is read off is the
-- target's health, the client does send an event for that, and this is that
-- event turned into one call.
--
-- Every entry is asked before the bar is told, because a mob going from 90% to
-- 89% moves nothing on any square. Execute's answer changes once in a fight, at
-- a fifth, and that is the only health tick worth a repaint. The rest cost two
-- unit calls and stop here.
--------------------------------------------------------------------------

-- Each entry's last answer, so an event that changed nothing costs nothing.
local was = {}

local function Moved()
	local moved = false
	for index = 1, #list do
		local entry = list[index]
		local now = Unmet(entry) or false
		if now ~= was[entry] then
			was[entry] = now
			moved = true
		end
	end
	return moved
end

--------------------------------------------------------------------------

function Requires.Describe()
	if watching == nil then
		return "not decided yet"
	end
	if watching ~= true then
		return watching
	end
	local said = ""
	for index = 1, #list do
		local entry = list[index]
		local unmet = Unmet(entry)
		said = said .. (said == "" and "" or ", ")
			.. (NameOf(entry) or ("spell " .. tostring(entry.spell)))
			.. " " .. (unmet or "ready")
	end
	return said
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Decided once, at login, and never at file scope. The README's trap says why:
-- class data is not reliable while the files load, so a file-scope answer locks
-- a warrior out for the session.
local function Arm()
	if watching ~= nil then
		return
	end
	local mine = ns.Class.Of("requires")
	if not mine or #mine == 0 then
		watching = ("no ability a %s owns waits on the fight rather than on you")
			:format(ns.Class.Label())
		return
	end
	-- Asked of Buttons/Slot.lua, which is the one place that knows whether a
	-- square can be told from another on this client. Without it every entry
	-- below would be looked for against a name nothing ever produces.
	local canName, why = ns.Slot.CanName()
	if not canName then
		watching = why
		return
	end

	-- Built once, here, and read on the tick after that. Everything above has
	-- already refused, so nothing half-filled is left behind.
	for index = 1, #mine do
		list[index] = mine[index]
	end
	watching = true

	-- Registered here rather than at file scope for the reason everything else
	-- in this function is: a class that names no condition watches nothing.
	-- Filtered to the one unit where the client can filter, which is what
	-- ns.RegisterUnitEvent is for.
	ns.RegisterUnitEvent(events, "UNIT_HEALTH", UNIT)
end

local function OnEvent(_, event, unit)
	if event == "UNIT_HEALTH" then
		-- The unit is read off the payload whether or not the registration was
		-- filtered, because a client with no RegisterUnitEvent hands over every
		-- unit in the raid.
		if unit == UNIT and Moved() and ns.Bars then
			ns.Bars.Soil()
		end
		return
	end
	Arm()
end

events:SetScript("OnEvent", OnEvent)
