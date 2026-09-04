local ADDON, ns = ...

local Cause = {}
ns.Cause = Cause

--------------------------------------------------------------------------
-- What made a frame take that long
--
-- The recorder next door knows a frame took 118 ms. This file is the half that
-- can say why, and the honest answer has four shapes and no more:
--
--   Lua, and whose      GetScriptCPUUsage is a running total of every
--                       millisecond the client has spent inside Lua. Read once
--                       a frame, its difference is that frame's Lua time
--                       exactly. Which addon spent it is a second question,
--                       answered a second at a time rather than a frame at a
--                       time, because naming it means walking every addon the
--                       client has loaded and that walk is not free.
--   the collector       Lua's own, which runs when it likes. A fall in
--                       collectgarbage("count") across one frame is a
--                       collection and nothing else is.
--   an event storm      four hundred combat log lines arriving between two
--                       frames is a stall whether or not any one handler is
--                       slow. Perf/Census.lua counts them.
--   the client itself   a frame with no Lua in it, no collection and no events
--                       went on drawing, streaming a texture off the disk, or
--                       compiling a shader. No addon can see any of that, and
--                       saying so is worth more than guessing.
--
-- **Three of the four need scriptProfile, which is a CVar and a reload.** With
-- it off, the client answers nothing about Lua time at all: this addon still
-- knows what its own tickers cost, because it times them itself, but the
-- ninety milliseconds some other addon spent are invisible and no amount of
-- code here changes that. The switch is offered on the page and turned nowhere
-- else. It slows the whole client for as long as it is on, which is the reason
-- it ships off and the reason nothing here turns it on quietly.
--------------------------------------------------------------------------

-- How many addons are ranked. Three is what a dip line has room for and what a
-- dip has ever needed: past the third the numbers are noise against the frame
-- that was lost.
local RANKED = 3

-- The client's addon list, spelled two ways across these builds. Both are
-- looked up and neither is assumed, the same way Chat/Voice.lua reads the
-- loader.
local function AddOnList()
	local addons = _G.C_AddOns
	local count = (addons and addons.GetNumAddOns) or _G.GetNumAddOns
	local info = (addons and addons.GetAddOnInfo) or _G.GetAddOnInfo
	if type(count) ~= "function" or type(info) ~= "function" then
		return nil, nil
	end
	return count, info
end

--------------------------------------------------------------------------
-- The client's own profiler
--------------------------------------------------------------------------

-- Whether the client is counting Lua time at all. Three things have to hold:
-- the CVar is on, the call exists, and it answers a number. A client that
-- refuses any of them makes every figure below nil, and every reader of this
-- file says so in words rather than drawing a zero.
function Cause.Profiling()
	if not (type(GetCVarBool) == "function" and GetCVarBool("scriptProfile")) then
		return false
	end
	return type(_G.GetScriptCPUUsage) == "function"
end

-- Total milliseconds the client has spent in Lua since it started counting.
local function ScriptTotal()
	local read = _G.GetScriptCPUUsage
	if type(read) ~= "function" then
		return nil
	end
	local ok, ms = pcall(read)
	return (ok and type(ms) == "number") and ms or nil
end

local lastScript = nil

-- Lua time since this was last called, in milliseconds, or nil where the client
-- will not say. Called once a frame by the recorder, so the answer is one
-- frame's worth of Lua, phase shifted by wherever the recorder runs in the
-- frame rather than clipped by it.
function Cause.LuaSince()
	local total = ScriptTotal()
	if not total then
		lastScript = nil
		return nil
	end
	local since = lastScript and (total - lastScript) or nil
	lastScript = total
	-- A counter that went backwards is the client having reset it, which
	-- ResetCPUUsage does and any addon may call. One frame reads as unknown
	-- rather than as a negative millisecond.
	if since and since < 0 then
		return nil
	end
	return since
end

function Cause.Forget()
	lastScript = nil
end

--------------------------------------------------------------------------
-- Who spent it
--
-- Per addon CPU is cumulative and the interesting figure is a difference, so a
-- baseline is taken once a second and every reading is against that. Both the
-- walk and the baseline cost a call per addon, which is why neither runs unless
-- something is watching.
--------------------------------------------------------------------------

local baseline = {}   -- addon index -> cumulative ms at the last mark
local marked = nil    -- when that was, on the client's clock
-- What the last ranking came to, kept so the window can read it without
-- walking every addon again at its own rate.
local lastFilled, lastTotal, lastSpan = 0, 0, 0
local ranked = {}     -- the top few, reused rather than rebuilt
for index = 1, RANKED do
	-- The addon's index rather than its name, because a name costs a call into
	-- the client and only three of forty are ever read back.
	ranked[index] = { at = nil, ms = 0 }
end

-- The cumulative figure for one addon, or nil where the client will not say.
local function AddOnCPU(index)
	local read = _G.GetAddOnCPUUsage
	if type(read) ~= "function" then
		return nil
	end
	local ok, ms = pcall(read, index)
	return (ok and type(ms) == "number") and ms or nil
end

local function Refresh()
	local update = _G.UpdateAddOnCPUUsage
	if type(update) ~= "function" then
		return false
	end
	return (pcall(update)) and true or false
end

-- Start a fresh second. Answers whether it could.
function Cause.Mark()
	local count = AddOnList()
	if not count or not Cause.Profiling() or not Refresh() then
		marked = nil
		return false
	end
	for index = 1, count() do
		baseline[index] = AddOnCPU(index) or 0
	end
	marked = GetTime and GetTime() or 0
	return true
end

-- One reading offered to the ranking, kept if it beats a row already there.
--
-- An insertion into a list of three rather than a sort over forty, because
-- table.sort takes a comparison and a comparison written here would be a
-- closure allocated at every dip.
local function Offer(index, ms)
	for slot = 1, RANKED do
		if ms > ranked[slot].ms then
			for back = RANKED, slot + 1, -1 do
				ranked[back].at, ranked[back].ms =
					ranked[back - 1].at, ranked[back - 1].ms
			end
			ranked[slot].at, ranked[slot].ms = index, ms
			return true
		end
	end
	return false
end

-- The top few addons by milliseconds spent since the last mark, biggest first.
-- Answers how many rows were filled, how much Lua was spent across all of them,
-- and how wide the window is in seconds.
function Cause.Rank()
	local count = AddOnList()
	for index = 1, RANKED do
		ranked[index].at, ranked[index].ms = nil, 0
	end
	if not count or not marked or not Refresh() then
		lastFilled, lastTotal, lastSpan = 0, 0, 0
		return 0, 0, 0
	end

	local total, filled = 0, 0
	for index = 1, count() do
		local spent = (AddOnCPU(index) or 0) - (baseline[index] or 0)
		if spent > 0 then
			total = total + spent
			if Offer(index, spent) then
				filled = math.min(RANKED, filled + 1)
			end
		end
	end
	lastFilled = filled
	lastTotal = total
	lastSpan = (GetTime and GetTime() or 0) - marked
	return lastFilled, lastTotal, lastSpan
end

-- The ranking as it last came out, without taking it again. The window reads
-- this ten times a second and the walk behind it runs once, on the second
-- boundary Perf/Trace.lua already keeps.
function Cause.Ranking()
	return lastFilled, lastTotal, lastSpan
end

-- One row of the ranking, as the addon's name and what it spent. The name is
-- read here rather than at the ranking, so three names are asked for instead of
-- forty.
function Cause.Ranked(index)
	local row = ranked[index]
	local _, info = AddOnList()
	if not row or not row.at or not info then
		return nil
	end
	local ok, name = pcall(info, row.at)
	if ok and type(name) == "string" then
		return name, row.ms
	end
	return "an addon", row.ms
end

--------------------------------------------------------------------------
-- The sentence
--------------------------------------------------------------------------

-- The two addons that spent the most in the second around a dip, as words, or
-- nil where nothing can be named. Built at a dip, which is rare by definition
-- and is the whole reason a dip is worth a string.
local function Blamed()
	local filled = Cause.Rank()
	if filled == 0 then
		return nil
	end
	local first, firstMs = Cause.Ranked(1)
	local second, secondMs = Cause.Ranked(2)
	if second and secondMs >= 1 then
		return ("%s %.0f ms, %s %.0f ms in that second")
			:format(first, firstMs, second, secondMs)
	end
	return ("%s %.0f ms in that second"):format(first, firstMs)
end

-- Why one frame took as long as it did, in a sentence.
--
-- The order the tests come in is the order the evidence is worth: a loading
-- screen explains a frame outright, a measured Lua figure beats a guess, and
-- the client's own work is what is left when nothing else claimed it. The last
-- line is not a failure to explain. It is the answer, and it is the one a
-- player needs to hear before spending an evening switching addons off.
function Cause.Explain(dip)
	if dip.loading then
		return "a loading screen, not a stall"
	end

	local lua = dip.lua
	if lua then
		if lua >= dip.ms * 0.5 then
			local who = Blamed()
			return ("Lua, %.0f ms of it%s"):format(lua, who and (": " .. who) or "")
		end
		if dip.freed and dip.freed > 64 then
			return ("the collector, %.0f KB handed back"):format(dip.freed)
		end
		if dip.events >= 200 then
			return ("%d events arrived, %d of them %s")
				:format(dip.events, dip.eventCount, dip.event or "unnamed")
		end
		return ("not Lua: %.0f ms of it was the client drawing, streaming or waiting")
			:format(dip.ms - lua)
	end

	if dip.ours >= dip.ms * 0.5 then
		return ("this addon, %.2f ms of it, worst tick %s")
			:format(dip.ours, dip.ourKey or "unnamed")
	end
	if dip.events >= 200 then
		return ("%d events arrived, %d of them %s")
			:format(dip.events, dip.eventCount, dip.event or "unnamed")
	end
	if dip.freed and dip.freed > 64 then
		return ("the collector, %.0f KB handed back"):format(dip.freed)
	end
	return "unknown: the client's own profiler is off, so nothing can say"
end

--------------------------------------------------------------------------

-- What the profiler is doing, as the line the page and the window both read.
function Cause.Describe()
	if type(GetCVarBool) ~= "function" then
		return "this client has no CVar to read"
	end
	if not GetCVarBool("scriptProfile") then
		return "off, so no Lua time can be attributed to any addon"
	end
	if type(_G.GetScriptCPUUsage) ~= "function" then
		return "on, but this client has no GetScriptCPUUsage"
	end
	return "on, and every millisecond of Lua is being counted"
end

-- Turn it on or off. It takes effect at the next load of the interface and not
-- before, which is the client's rule and not this file's, so the caller is
-- handed back whether a reload is what is left to do.
function Cause.Turn(on)
	if type(SetCVar) ~= "function" or type(GetCVarBool) ~= "function" then
		return false
	end
	if GetCVarBool("scriptProfile") == on then
		return true
	end
	SetCVar("scriptProfile", on and "1" or "0")
	return true
end
