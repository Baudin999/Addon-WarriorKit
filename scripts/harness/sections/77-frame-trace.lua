-- Why a frame took that long
--
-- The recorder and the four answers it can give. Nothing here reads the source
-- and takes its word for it: each of the four is arranged in the stub and the
-- sentence the dip log wrote is compared against.
--
--   an event storm    two hundred and fifty events fired between two frames
--   Lua               the profiler on and the counter moved 90 ms
--   the client        the profiler on, the counter still, the collector stopped
--   unknown           the profiler off, which is how the addon ships
--
-- And the three things that are not answers. An ordinary frame is not written
-- into the log. A frame on the far side of a loading screen is not either,
-- because the client draws one enormous one on the way back into the world and
-- it is not a stall. And the recorder allocates nothing: it runs on every frame
-- the client draws, so a table per frame would be the fault the whole part
-- exists to find.
--
-- The census is driven at its own door rather than through fire(). This stub
-- has no RegisterAllEvents, so an event fired here reaches the frames that
-- named it and nothing else, and Perf/Census.lua names none of them: that is
-- the whole of what it is. What is worth asserting is what it does with a name
-- it is handed, which is what ns.Census.Count is, and the client's own delivery
-- is the half no stub can answer for anyway.

local H = ...
local ns, check, fire = H.ns, H.check, H.fire

local Trace, Cause, Census = ns.Trace, ns.Cause, ns.Census

----------------------------------------------------------------------
-- Armed at login, because the setting says to watch all session
----------------------------------------------------------------------

check(Trace.Watching(), "the frame trace did not start at login")
check(Census.Watching(), "the census did not start with the trace")
check(ns.UI.Ticking("frame") ~= nil, "the recorder armed no ticker")

local frame = H.tick("frame")
Trace.Forget()

----------------------------------------------------------------------
-- Sixty ordinary frames
----------------------------------------------------------------------

for _ = 1, 60 do
	frame:Beat(0.016)
end

local last = Trace.Second()
check(last.frames == 60,
	("a second of 16 ms frames counted %d of them"):format(last.frames))
check(last.worst > 15 and last.worst < 17,
	("the worst of sixty 16 ms frames read as %.1f ms"):format(last.worst))
check(Trace.Dips() == 0, "an ordinary frame was written into the dip log")
check(Trace.Column(1) ~= nil, "the strip has no column for the first frame")
check(Trace.Head() == 60, ("the ring head is at %d after sixty frames"):format(Trace.Head()))

----------------------------------------------------------------------
-- Off the shelf, which is the profiler off
----------------------------------------------------------------------

frame:Beat(0.120)
check(Trace.Dips() == 1, ("one long frame wrote %d dips"):format(Trace.Dips()))

local _, took, why = Trace.Dip(1)
check(took > 119 and took < 121, ("a 120 ms frame was logged as %.0f ms"):format(took))
check(why:match("^unknown"),
	("with no profiler the dip reads %q, and nothing can honestly say more"):format(why))

----------------------------------------------------------------------
-- An event storm
--
-- Counted under a name nothing in the addon listens for, so what is being
-- measured is the census and not two hundred and fifty unit frame passes.
----------------------------------------------------------------------

for _ = 1, 250 do
	Census.Count("WARRIORKIT_HARNESS_EVENT")
end
frame:Beat(0.150)
_, _, why = Trace.Dip(1)
check(why:match("^250 events"),
	("a frame with 250 events in it reads %q"):format(why))
check(Trace.Dips() == 2, "the storm did not land on top of the log")

-- Newest first, and the older one is still underneath it.
local older
_, older = Trace.Dip(2)
check(older > 119 and older < 121,
	("the second row of the log holds %.0f ms and should hold the 120"):format(older))

----------------------------------------------------------------------
-- The combat log, counted at the one door
--
-- Perf/Census.lua deliberately does not register for it. Core/CombatLog.lua
-- counts its own lines and the recorder folds the difference in, so a pull is
-- named as the combat log rather than going missing.
----------------------------------------------------------------------

local before = ns.CombatLog.Lines()
for _ = 1, 300 do
	fire("COMBAT_LOG_EVENT_UNFILTERED")
	-- Handed to the census as well, the way the client would on a build where
	-- RegisterAllEvents covers it. It has to come out of the count once and not
	-- twice, which is what the skip in Census.Count is for.
	Census.Count("COMBAT_LOG_EVENT_UNFILTERED")
end
check(ns.CombatLog.Lines() - before == 300,
	("300 combat log lines were counted as %d"):format(ns.CombatLog.Lines() - before))

frame:Beat(0.150)
_, _, why = Trace.Dip(1)
check(why:match("^300 events"),
	("300 lines counted twice would read as 600, and this reads %q"):format(why))
check(why:match("COMBAT_LOG_EVENT_UNFILTERED"),
	("a frame filled with combat log lines reads %q"):format(why))

----------------------------------------------------------------------
-- The profiler on, which is the only way an addon gets named
----------------------------------------------------------------------

local script = 0
local cpu = { 0, 0, 0 }
local names = { "Details", "Questie", "WarriorKit" }
_G.GetScriptCPUUsage = function() return script end
_G.UpdateAddOnCPUUsage = function() end
_G.GetAddOnCPUUsage = function(index) return cpu[index] or 0 end
_G.GetNumAddOns = function() return #names end
_G.GetAddOnInfo = function(index) return names[index] end
_G.SetCVar("scriptProfile", "1")

check(Cause.Profiling(), "the stub turned the profiler on and Cause cannot see it")
check(Cause.Mark(), "the baseline could not be taken with the profiler on")

-- One frame to prime the counter, then a frame with 90 ms of Lua in it and one
-- addon holding most of it.
frame:Beat(0.016)
script = script + 90
cpu[1] = cpu[1] + 71
cpu[2] = cpu[2] + 12
frame:Beat(0.120)

_, _, why = Trace.Dip(1)
check(why:match("^Lua, 90 ms"), ("90 ms of Lua in a 120 ms frame reads %q"):format(why))
check(why:match("Details 71 ms"), ("the addon that spent it is not named: %q"):format(why))

----------------------------------------------------------------------
-- The client itself, which is the answer nobody wants and often the true one
----------------------------------------------------------------------

collectgarbage("collect")
collectgarbage("stop")
frame:Beat(0.016)
frame:Beat(0.180)
collectgarbage("restart")

_, _, why = Trace.Dip(1)
check(why:match("^not Lua"),
	("a long frame with no Lua in it reads %q, and the client is what is left"):format(why))

----------------------------------------------------------------------
-- A loading screen is not a stall
----------------------------------------------------------------------

local kept = Trace.Dips()
fire("PLAYER_ENTERING_WORLD")
frame:Beat(1.400)
check(Trace.Dips() == kept,
	"the frame the client drew coming out of a loading screen was logged as a stall")

----------------------------------------------------------------------
-- What the recorder costs
--
-- It runs on every frame, so this is the measurement that matters more than
-- any number it reports. The gate is the one every ticker in this addon is
-- held to.
----------------------------------------------------------------------

local function churn(ticks)
	collectgarbage("collect")
	collectgarbage("stop")
	local held = collectgarbage("count")
	for _ = 1, ticks do
		frame:Beat(0.016)
	end
	local grew = collectgarbage("count") - held
	collectgarbage("restart")
	return grew
end

churn(200)
local churned = churn(200)
check(churned < 0.05, ("200 recorded frames allocated %.2f KB"):format(churned))

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

local Hud = ns.PerfHud
check(not Hud.IsShown(), "the performance window was open before anything asked for it")
Hud.Open()
check(Hud.IsShown(), "the window did not open")

-- On the window's own frame rather than on ns.UI.Forever, which is what makes
-- the repaint stop when the window is shut, so it is asked for by that frame.
local hud = ns.UI.Ticking("hud", Hud.Frame())
check(hud ~= nil, "the window armed no repaint")
hud:Beat(0.2)

local drawn = 0
for index = 1, Trace.Window() do
	if Trace.Column(index) then
		drawn = drawn + 1
	end
end
check(drawn > 200, ("the strip has %d columns of frames and the ring holds 240"):format(drawn))

Hud.Close()
check(not Hud.IsShown(), "the window did not close")
check(Trace.Watching(), "closing the window stopped a trace the setting asked to keep running")

-- And the way out nothing in this file calls. Escape hides the frame through
-- UISpecialFrames without going near Hud.Close, so the hook on OnHide is the
-- only thing that stops the repaint and puts the trace back where the setting
-- wants it. Driven by hiding the frame, which is all Escape does.
ns.db.perfWatch = false
Hud.Open()
check(Trace.Watching(), "the window did not start the trace it needs to draw anything")
Hud.Frame():Hide()
check(not Trace.Watching(),
	"a window closed with Escape left the trace running with the setting off")
ns.db.perfWatch = true

----------------------------------------------------------------------
-- The key
----------------------------------------------------------------------

check(ns.db.perfKey == "CTRL-R", ("the window opens on %s"):format(tostring(ns.db.perfKey)))
check(ns.PerfKey.Describe():match("^CTRL%-R"),
	("the key reads %q"):format(ns.PerfKey.Describe()))

----------------------------------------------------------------------
-- Put the client back the way it was found
----------------------------------------------------------------------

_G.GetScriptCPUUsage, _G.GetNumAddOns, _G.GetAddOnInfo = nil, nil, nil
_G.GetAddOnCPUUsage, _G.UpdateAddOnCPUUsage = nil, nil
_G.SetCVar("scriptProfile", "0")
Cause.Forget()
Trace.Forget()

print(("trace  %d frames a ring, %d dips kept, %.2f KB per 200 frames, four answers: %s")
	:format(Trace.Window(), kept, churned, "Lua, the collector, an event storm, the client"))
