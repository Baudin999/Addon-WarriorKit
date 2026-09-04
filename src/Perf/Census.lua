local ADDON, ns = ...

local Census = {}
ns.Census = Census

--------------------------------------------------------------------------
-- Every event the client sends, counted
--
-- One frame registered for all of them, a counter per name, and two questions
-- answered off it: how many events landed in the frame that just went past, and
-- which name most of them carried. A frame that took 90 ms with four hundred
-- events in it has explained itself, and nothing else in the client will say so.
--
-- **This is the only part of the addon that registers for events it does not
-- read.** RegisterAllEvents means the client makes a Lua call here for every
-- event in the game, which in a raid is over a thousand a second. That is a
-- real cost and it is why this is switched on with the frame trace rather than
-- at login: the handler is four lines, it allocates nothing, and it brackets
-- itself under the "census" slot so the performance tab reports what counting
-- costs beside everything else it measures.
--
-- **The combat log is not counted here.** It is the loudest event in the game
-- and the one that most often fills a frame, so leaving it out would gut the
-- census, but Core/CombatLog.lua's whole argument is that this addon registers
-- for it exactly once and gives the event back when no part is reading. A
-- second registration would be that debt wearing a different name. So that file
-- counts its own lines, one increment on a path it already owns, and
-- Perf/Trace.lua folds the difference in per frame. This file skips the name
-- whether or not the client hands it over, which is what stops it being counted
-- twice on a client where RegisterAllEvents does deliver it.
--
-- **Nothing is zeroed per frame.** A walk over every name the session has seen,
-- sixty times a second, is the shape this file exists to catch. Each name
-- carries the frame it was last counted in instead, so a count from an older
-- frame reads as zero and is overwritten rather than cleared.
--------------------------------------------------------------------------

local counts = {}   -- event -> how many landed in the frame stamped beside it
local stamps = {}   -- event -> which frame that count belongs to
local lifetime = {} -- event -> how many since watching began
local names = {}    -- every name seen, in the order it first arrived

local frame              -- the listener, made on the first watch
local watching = false
local generation = 0     -- which frame the counters above belong to
local landed = 0         -- events in this frame
local topName, topCount = nil, 0

--------------------------------------------------------------------------

-- hot: runs on every event the client sends, off this file's OnEvent closure.
-- Four lines and no allocation past the first sighting of a name.
function Census.Count(event)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		return
	end
	local count = 1
	if stamps[event] == generation then
		count = counts[event] + 1
	elseif lifetime[event] == nil then
		names[#names + 1] = event
		lifetime[event] = 0
	end
	counts[event] = count
	stamps[event] = generation
	lifetime[event] = lifetime[event] + 1
	landed = landed + 1
	if count > topCount then
		topCount = count
		topName = event
	end
end

-- What landed since the last call: how many, the name most of them carried, and
-- how many of that one. Read once a frame by Perf/Trace.lua, which is what ends
-- one generation and starts the next.
function Census.Take()
	local count, name, most = landed, topName, topCount
	generation = generation + 1
	landed, topName, topCount = 0, nil, 0
	return count, name, most
end

-- How many of one event have landed since watching began. The window ranks
-- events over a second by taking this twice; the counter itself never resets,
-- so a reader that misses a second reads a wider window rather than nothing.
function Census.Lifetime(event)
	return lifetime[event] or 0
end

-- Every name seen since watching began, in the order it first arrived. Handed
-- back as the live table because the caller walks it and never holds it: a copy
-- per read would be a table per second for a list that only grows.
function Census.Names()
	return names
end

--------------------------------------------------------------------------

local function OnEvent(_, event)
	ns.Perf.Start("census")
	Census.Count(event)
	ns.Perf.Stop("census")
end

function Census.Watch(on)
	if watching == on then
		return watching
	end
	watching = on

	if not on then
		if frame then
			frame:UnregisterAllEvents()
		end
		landed, topName, topCount = 0, nil, 0
		return watching
	end

	if not frame then
		frame = CreateFrame("Frame")
		frame:SetScript("OnEvent", OnEvent)
	end
	frame:RegisterAllEvents()
	return watching
end

function Census.Watching()
	return watching
end

-- Whether anything has arrived since watching began.
--
-- Asked rather than probed, because a client that takes RegisterAllEvents and
-- delivers nothing looks exactly like a quiet evening from in here, and the two
-- are worth telling apart on a window whose whole subject is what happened.
-- Standing in a city for a second answers it.
function Census.Heard()
	return #names > 0
end

function Census.Forget()
	for index = 1, #names do
		local name = names[index]
		lifetime[name] = 0
		counts[name] = 0
		stamps[name] = -1
	end
	landed, topName, topCount = 0, nil, 0
end
