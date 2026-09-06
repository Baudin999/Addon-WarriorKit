local ADDON, ns = ...

local UI = ns.UI

--------------------------------------------------------------------------
-- Keeping an open box true
--
-- UI/Tip.lua builds a tooltip once, at the moment the pointer arrives, and
-- until this file existed that was the only time it was ever built. Everything
-- in the box was a photograph. The threat percentage on a mob you were holding
-- through a whole pull, the count on a quest drop you were part way through:
-- both were whatever they had been on the frame you arrived. Blizzard's own
-- tooltip re-runs its setter on an OnUpdate, which is why the client's box
-- ticks and ours sat still, and the complaint that produces is that the addon's
-- tooltips are slow. They were not slow. They were never redrawn at all.
--
-- **The memo is what is drawn, not what is read.** The obvious fix is to
-- rebuild on a tick, and it is wrong in both directions at once. It throws the
-- box away sixty times for every time anything in it moved, and the cache that
-- suggests itself instead is refused by UI/Scan.lua's own header for the
-- reason written there: a cache of the client's text buys a stale tooltip in
-- exchange for nothing anybody can measure. So neither side is cached. A stamp
-- is read instead. One number per thing in the box that can move, cheap enough
-- to read on every tick, and the box is rebuilt on the tick a stamp differs
-- from the one before it and on no other tick.
--
-- **Floored to the precision the box draws.** That is what makes it nearly
-- free rather than merely cheaper. The threat line writes `%d%%`, so its stamp
-- is the whole percent: a mob whose threat wanders between 61.2 and 61.8 is one
-- number and no redraw at all. A creature standing still at the same percentage
-- is read and dropped, which is the ordinary case, because what a player
-- actually does is hover something, read it and move on.
--
-- **Who declares a stamp is whoever draws the moving thing.** A source hooks a
-- line into the box and knows what makes that line move, so a stamp goes on the
-- source beside its fill. A caller whose own subject moves puts one on the
-- subject. This file knows neither and must not: a table here mapping a kind to
-- what makes it stale would be a second place to remember, sitting months away
-- from the line it is about, and it would be wrong the first time a source
-- changed what it draws.
--
-- **Nothing in the head band has a stamp today, on purpose.** The head is the
-- client's own scanned text, and whether a word inside it moves is a question
-- about the client rather than about this addon. A stamp that fired every
-- second and changed no character on screen would be exactly the waste this
-- file exists to avoid, so there is none until somebody has watched a head band
-- go stale and can say which call says so.
--------------------------------------------------------------------------

local Fresh = {}
UI.Fresh = Fresh

-- A tenth of a second, which is the step World/World.lua sweeps at and is the
-- same number for the same reason: it is the delay between a figure moving and
-- the box saying so, and anything shorter asks a question more often than a
-- person reading a tooltip can notice the answer.
local STEP = 0.1

-- What the box on screen was built from, one entry per stamp, written in place
-- every pass. A fixed table rather than a fresh one each tick because this runs
-- while you are reading a tooltip, which is precisely when a collector walking
-- the addon's garbage is felt rather than measured.
local held = {}

-- How many stamps the last pass found. Compared as well as the values, because
-- a source that had nothing to say about the last subject and has something to
-- say about this one is a box that has to be built again, and its stamp
-- appearing where there was none is the only sign of that here.
local count = 0

-- Which subject the tick is watching, held by identity so that a rebuild can
-- re-arm on the same subject without counting as a new one. See Fresh.Arm.
local watching

-- How many times the box has been built again under a pointer that never
-- moved, for scripts/harness. "fifty ticks over a mob standing still rebuilt
-- nothing" is the claim this whole file has to make good on, and there is no
-- answering it from the outside.
local rebuilds = 0

-- Whether the tick is running. Read before the frame is touched, so that the
-- one widget write in this file sits behind a comparison rather than on every
-- close the world hover's own sweep makes.
local armed = false

-- Hidden, so nothing runs on an ordinary frame. Shown for exactly as long as a
-- box with something moving in it is on screen.
local live = CreateFrame("Frame")
live:Hide()

-- Every stamp this subject has, read and written down, and how many there were.
--
-- One walk with a flag rather than a reader and a primer, because the two would
-- be the same loop twice and the failure mode of that is silent: the pass that
-- decides whether to rebuild and the pass that records what was rebuilt would
-- drift apart, and the symptom is a box that is right the first time and stale
-- afterwards.
--
-- `compare` is off at the arm and on for every tick after it. Off matters as
-- much as on: `held` still carries the last box's numbers at the moment a new
-- one opens, so a first tick that compared against them would find a difference
-- on nearly every hover and rebuild a box that had just been built. That is one
-- wasted build per hover, which is the exact cost this file was written to
-- remove, arriving through the front door.
--
-- The count is compared as well as the values. A source that had nothing to say
-- about the last subject and has something to say about this one is a box that
-- has to be built again, and a stamp appearing where there was none is the only
-- sign of that here.
local function Read(subject, compare)
	local moved, at = false, 0

	local own = subject.stamp
	if type(own) == "function" then
		at = at + 1
		local value = own(subject)
		if held[at] ~= value then
			moved, held[at] = compare, value
		end
	end

	local stamped = ns.Tip.Stamped()
	for index = 1, #stamped do
		local source = stamped[index]
		if source.kind == "*" or source.kind == subject.kind then
			at = at + 1
			local value = source.stamp(subject)
			if held[at] ~= value then
				moved, held[at] = moved or compare, value
			end
		end
	end

	if at ~= count then
		moved, count = moved or compare, at
	end
	return moved, at
end

-- cold: Redraw builds the box again, on the tick a stamp moved and not on the ticks it did not
local function Redraw()
	rebuilds = rebuilds + 1
	ns.Tip.Again()
end

-- Armed when a box opens and disarmed when it closes, both by UI/Tip.lua.
--
-- Re-arming on the subject already being watched is a no-op rather than a
-- reset, and that is load bearing: a rebuild goes back through Tip.Open with
-- the same subject table, and an Arm that started the count over would leave
-- the next pass finding a different number of stamps than the pass before it
-- and rebuilding again, every tick, forever.
function Fresh.Arm(subject)
	if type(subject) ~= "table" then
		return Fresh.Stop()
	end
	if armed and watching == subject then
		return true
	end
	Fresh.Stop()
	local _, found = Read(subject, false)
	if found < 1 then
		return false
	end
	armed, watching = true, subject
	live:Show()
	return true
end

function Fresh.Stop()
	if not armed then
		return false
	end
	armed, watching, count = false, nil, 0
	live:Hide()
	return true
end

-- One pass over everything in the open box that can move.
--
-- Compared entry by entry against the last pass rather than folded into one
-- number. Folding is a hash and a hash collides: two stamps that moved by the
-- same amount in opposite directions fold to the value they folded to before,
-- and the box sits there being wrong with nothing to show that it is. Entry by
-- entry costs one table read per stamp and cannot be wrong.
--
-- Nothing here allocates, which is what makes a tick under a pointer that is
-- not moving free rather than merely cheap. See scripts/check.sh, which scans
-- this path for a constructor and refuses one.
function Fresh.Sweep()
	if not armed then
		return false
	end
	local subject = watching
	if type(subject) ~= "table" then
		Fresh.Stop()
		return false
	end
	if not Read(subject, true) then
		return false
	end
	Redraw()
	return true
end

ns.UI.Ticker(live, STEP, "fresh", Fresh.Sweep)

-- How many rebuilds a box has taken since the count was last cleared, for
-- scripts/harness. Cleared by the reader rather than on an arm, because the
-- question a section asks is always "how many over the run I just drove".
function Fresh.Rebuilds()
	local total = rebuilds
	rebuilds = 0
	return total
end

-- Whether a tick is running, and what it is watching, for the options window
-- and for scripts/harness. Two returns rather than a sentence because the
-- panel words it and this file may not.
function Fresh.Watching()
	return armed == true, watching
end

-- What the player would see, rather than what this file meant to do.
function Fresh.Describe()
	local stamped = ns.Tip.Stamped()
	local total = #stamped
	if total < 1 then
		return "nothing in a hover moves while you read it"
	end
	if total == 1 then
		return ("one line in a hover keeps up while you read it, and it is %s")
			:format(stamped[1].name)
	end
	return ("%d lines in a hover keep up while you read it"):format(total)
end
