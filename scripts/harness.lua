-- The addon, loaded and driven under a stub of the client.
--
-- Nothing here is a client. It is enough of one to load every file in TOC
-- order, put nameplates up, run the enemy bars ticker and then ask four
-- questions no amount of reading the source will answer:
--
--   does the pixel grid resolve to one unit per pixel on a screen that is not
--   768 tall, which is every screen;
--   is a widget's geometry a whole number of pixels once the client's own
--   fractional measurements have been through it;
--   is a bar still the width the client's plate was after six mobs and a
--   setting change, or is it sizing itself off its own last answer;
--   and does a tick allocate.
--
-- The last is the one worth having automated. Allocation on a ticker is
-- invisible in review, invisible in game until a raid, and a one line change
-- reintroduces it. check.sh already bans the shapes that cause it inside the
-- functions HOT names; this measures the result and fails on a number.
--
-- What it does not prove: that the game agrees. Every API here answers what
-- these files say it answers. A stub that returns the wrong thing is a test
-- that passes and a client that does not.
--
--     lua5.1 scripts/harness.lua src
--     lua5.1 scripts/harness.lua src HUNTER
--     lua5.1 scripts/harness.lua src WARRIOR 12-debuff-square-size
--
-- The second argument is the class this run is. It defaults to WARRIOR, which
-- is every run this file has ever done. Two parts of the addon are warrior
-- only, and both decide it once at PLAYER_LOGIN: the charge button and the
-- world marker are not built at all on another class, and the action targeting
-- CVar is never written. A decision taken at login cannot be reached by
-- flipping the class afterwards, so the only way to test it is to come up as
-- something else, and check.sh does both runs.
--
-- The third argument stops the run after the section it names, by the file name
-- under harness/sections without its extension. Everything above that section
-- still runs, because a section reads what the ones above it left behind and a
-- run of one on its own is a crash rather than a smaller suite. It is for
-- working on a section; check.sh never passes it.
--
-- The layout:
--
--   harness/client/     a stub of the 2.5.6 client, one file per part
--   harness/sections/   the questions, one file per subject, in run order
--   harness/runner.lua  the order it all happens in
--
-- This was one file of eleven thousand lines until it nearly stopped loading.
-- Lua 5.1 gives one function two hundred locals, a chunk is a function, and
-- the count had reached a hundred and seventy one. The fix that lasts is one
-- chunk per subject, because each gets its own two hundred. Nothing that a
-- section leaves for a later section rides on scope any more: it goes through
-- H.carry, which is named at the point it is handed over and at the point it
-- is read.

local here = arg[0]:match("^(.*)[/\\]") or "."

-- Every file under harness/ is loaded through this rather than through require,
-- so that each one is a chunk of its own with its own local budget, and so that
-- the arguments it needs are arguments rather than globals.
local function load(path)
	return assert(loadfile(here .. "/harness/" .. path))
end

local failures = load("runner.lua")(arg[1] or "src", arg[2] or "WARRIOR",
	load, arg[3])

if failures > 0 then
	print(("harness: %d failed"):format(failures))
	os.exit(1)
end
print("harness: ok")
