-- What a pass of the bars costs
--
-- Its own section rather than the tail of 05-action-bars.lua, which is at its
-- line budget, and a different question: that one asks whether the squares are
-- right, this one asks what asking cost. Three things no reading of
-- Buttons/Bars.lua settles.
--
--   That one ticker is armed and not one per loading screen. It used to be
--   armed inside the branch that runs on PLAYER_LOGIN and again on every
--   PLAYER_ENTERING_WORLD, so an instance door added a second walk of every
--   square and a hearth added a third, and nothing on screen said so. Driven by
--   entering the world again and measuring the pass.
--
--   That UI.Ticker refuses the second one at the call, so the next part that
--   arms a tick inside a handler fails where it is written rather than in the
--   frame budget.
--
--   That a pass draws the squares something happened to and no others. The old
--   pass asked the client twelve to sixteen questions about every square ten
--   times a second whether or not anything had moved.
--
-- Measured off the client rather than off the widgets. Every write a square
-- makes is already guarded on the value, so a square drawn again with nothing
-- different writes nothing, and counting writes cannot tell a pass that skipped
-- it from a pass that redrew it for nothing. Counting the calls it took to
-- decide can.

local H = ...
local ns, check, fire, region = H.ns, H.check, H.fire, H.region
local guids, slots = H.guids, H.slots

local ART = "Interface\\Icons\\Ability_Warrior_Charge"
local MOB = "Creature-0-0-0-0-1234-00000099"
local FRAME = 0.15 -- past the tenth of a second the action tick asks for

-- The bars' tick, asked for by the ns.Perf slot it is timed under. It used to
-- be found by the frame the bars register ACTIONBAR_PAGE_CHANGED on, which was
-- also the frame they hung the ticker off; every tick that never stops hangs
-- off ns.UI.Forever now and that frame carries no script at all.
check(ns.UI.Ticking("action") ~= nil,
	"the bars armed no ticker, so there is nothing to drive")
local action = H.tick("action")

-- Three counters over the client. GetActionCount is asked once per square on
-- every pass, so it counts passes; IsUsableAction is the rung nothing above it
-- answers for an ordinary square, so it counts squares drawn; IsActionInRange
-- is the one call the pass is allowed to make per attack.
local walked, drawn, ranged = 0, 0, 0
local realCount, realUsable, realRange =
	_G.GetActionCount, _G.IsUsableAction, _G.IsActionInRange
_G.GetActionCount = function(slot)
	walked = walked + 1
	return realCount(slot)
end
_G.IsUsableAction = function(slot)
	drawn = drawn + 1
	return realUsable(slot)
end
_G.IsActionInRange = function(slot, unit)
	ranged = ranged + 1
	return realRange(slot, unit)
end

local function pass()
	action:Beat(FRAME)
end

-- Two passes to spend whatever is standing, then the pass being measured. The
-- first spends the bits an apply raised, the second spends the range and stack
-- readings the first one took for the first time.
local function settle()
	pass()
	pass()
	walked, drawn, ranged = 0, 0, 0
end

--------------------------------------------------------------------------
-- One ticker
--------------------------------------------------------------------------

settle()
pass()
local once = walked
check(once == ns.Bars.Count(),
	("a pass walked %d squares and the bars carry %d"):format(once, ns.Bars.Count()))
check(once > 0, "a pass walked nothing, so every measurement below proves nothing")

fire("PLAYER_ENTERING_WORLD")
settle()
pass()
check(walked == once,
	("entering the world again armed a second action ticker: a pass now walks %d squares "
		.. "and it walked %d"):format(walked, once))

-- And the call refuses the second one, so the two halves of this cannot drift.
local again = { pcall(ns.UI.Ticker, ns.UI.Forever, 0.1, "action", ns.Bars.Tick) }
check(again[1] == false,
	"a second running ticker named action was accepted on the frame that already has one")
check(type(again[2]) == "string" and again[2]:find("action", 1, true),
	("the refusal does not name the ticker: %s"):format(tostring(again[2])))

-- A name is only taken on the frame it was taken on. Two parts wanting a tick
-- called the same thing off two frames is ordinary.
local spare = region("frame", _G.UIParent)
local other = ns.UI.Ticker(spare, 0.1, "action", ns.Bars.Tick)
check(other ~= nil, "a tick of the same name on another frame was refused")

-- And a stopped one is not in the way, because that is a part switching itself
-- back on rather than arming a second tick.
other:Stop()
local restarted = ns.UI.Ticker(spare, 0.1, "action", ns.Bars.Tick)
check(restarted ~= nil, "a stopped tick of the same name blocks the frame it stopped on")
restarted:Stop()

--------------------------------------------------------------------------
-- One OnUpdate for every tick that never stops
--------------------------------------------------------------------------

-- The client makes a Lua call per frame for every frame carrying an OnUpdate,
-- before anything in it compares an accumulator against an interval. Eighteen
-- parts of the addon armed a tick at login on a private frame of their own,
-- which was eighteen of those calls, about eleven hundred a second at 60 Hz, to
-- run twenty ticks. They hang off ns.UI.Forever now.
--
-- The eighteen are named rather than counted off the frames, because a part
-- that quietly stopped arming its tick would make a count go down and read here
-- as a pass. A frame from one of these files carrying the driver again is a
-- part that took a frame back for itself.
local PERMANENT = {
	["Bags/Stack.lua"] = true, ["Buffs/Nag.lua"] = true,
	["Buttons/Bars.lua"] = true, ["Buttons/Trace.lua"] = true,
	["Charge/Icon.lua"] = true, ["Charge/Marker.lua"] = true,
	["Comfort/Thanks.lua"] = true, ["Comfort/Vendor.lua"] = true,
	["Cooldowns/Row.lua"] = true, ["Core/BlizzHide.lua"] = true,
	["Meter/Window.lua"] = true, ["Minimap/Clock.lua"] = true,
	["Perf/Perf.lua"] = true, ["Swing/Gauges.lua"] = true,
	["UnitFrames/EnemyBars.lua"] = true, ["UnitFrames/Group.lua"] = true,
	["UnitFrames/PlayerCast.lua"] = true, ["UnitFrames/Skin.lua"] = true,
}
local Drive = ns.UI.Forever:GetScript("OnUpdate")
check(Drive ~= nil,
	"the frame the permanent tickers hang off carries no OnUpdate, so none of them runs")

local driving = 0
for _, f in ipairs(H.frames) do
	if f.scripts.OnUpdate == Drive and (f == ns.UI.Forever or PERMANENT[f.origin]) then
		driving = driving + 1
	end
end
check(driving == 1,
	("%d frames carry the ticker for ticks that never stop, and the client calls every one of them "
		.. "on every frame"):format(driving))

--------------------------------------------------------------------------
-- Only what moved
--------------------------------------------------------------------------

settle()
pass()
check(drawn == 0,
	("a pass with nothing having happened read the ladder on %d squares"):format(drawn))
check(ns.Reaction.Moved() == false,
	"the reaction windows report having moved with nothing having happened")

-- An event the client repaints its own bars on marks every square, and the
-- pass after it spends the marks rather than carrying them.
fire("ACTIONBAR_UPDATE_USABLE")
drawn = 0
pass()
local everything = drawn
check(everything > 1,
	("an event with no slot on it drew %d squares"):format(everything))
drawn = 0
pass()
check(drawn == 0, "the marks were not spent, so every pass draws the whole bar again")

-- The one event that names a slot draws that slot's square and no other.
fire("ACTIONBAR_SLOT_CHANGED", 73)
drawn = 0
pass()
check(drawn == 1,
	("one slot changed and %d squares were drawn"):format(drawn))

-- Zero is the client saying it changed something and not which.
fire("ACTIONBAR_SLOT_CHANGED", 0)
drawn = 0
pass()
check(drawn == everything,
	("a slot change the client did not name drew %d squares of %d"):format(drawn, everything))

--------------------------------------------------------------------------
-- What the client sends nothing for
--------------------------------------------------------------------------

-- The stack on an item. Nothing is sent when a count moves, so the pass reads
-- it and compares.
settle()
slots[73].count = 5
drawn = 0
pass()
check(drawn == 1,
	("a stack changed with nothing sent to say so and %d squares were drawn"):format(drawn))
slots[73].count = nil

-- Range, which is the one call Blizzard's own button keeps on its tick.
slots[73].harmful = true
slots[73].range = 1
guids.target = MOB
fire("PLAYER_TARGET_CHANGED")
settle()
pass()
check(drawn == 0, "a target standing still redraws the bar on every pass")
check(ranged == 1,
	("a pass asked about range %d times and one square holds an attack"):format(ranged))

slots[73].range = 0
drawn = 0
pass()
check(drawn == 1,
	("a square went out of range with nothing sent to say so and %d were drawn"):format(drawn))

guids.target = nil
slots[73] = { texture = ART }
fire("PLAYER_TARGET_CHANGED")
settle()
pass()
check(ranged == 0, "range is being asked about with nothing targeted")

_G.GetActionCount, _G.IsUsableAction, _G.IsActionInRange =
	realCount, realUsable, realRange

print(("tick   %d squares walked per pass, %d drawn on an event, 0 with nothing happening")
	:format(once, everything))
