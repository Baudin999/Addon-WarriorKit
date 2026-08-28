-- The cooldown row
--
-- Five questions, and the first two are the ones that make this a class part
-- rather than a warrior part.
--
-- Is the row built out of the registry. The list this character draws is
-- whatever Class/<yours>.lua wrote down, so every count below is measured
-- against that file rather than written out here, and the section runs
-- unchanged on all five class shapes. A warrior draws four, a mage up to eight,
-- a hunter none at all, and none of those numbers appears in this file.
--
-- Do the three filters each drop a square on their own. A spell the client
-- cannot name, a spell this character has not learned, and a switch you turned
-- off are three different reasons for an empty place on the row and each one is
-- asserted separately, because a row that dropped everything would pass any one
-- of them.
--
-- Does a trinket get on the row for the right reason. The client is what
-- decides: an item with a use effect answers GetItemSpell and one you merely
-- wear answers nothing, so both are worn here and exactly one of them takes a
-- square. That call is reached through the loose global rather than through
-- C_Item, which is the fallback half of ns.ItemSpell's probe.
--
-- Is the row on screen when it should be. It is up for the whole fight, up
-- after one while something is still recovering, and gone otherwise, which is
-- three states rather than the two the buff nag has.
--
-- And does the tick stay free. Nothing here allocates, and what a countdown
-- costs is measured rather than argued about: the timer string is only built on
-- the ticks where the number behind it moved.

local H = ...
local PLAYER_CLASS, CHURN, frames = H.PLAYER_CLASS, H.CHURN, H.frames
local own, worn, inCombat = H.own, H.worn, H.inCombat
local itemLink, advance = H.itemLink, H.advance
local ns, fire, check = H.ns, H.fire, H.check

local Cooldowns, Row = ns.Cooldowns, ns.CooldownRow

local ticker
for _, f in ipairs(frames) do
	if f.scripts.OnUpdate and f.origin:match("Cooldowns/Row") then
		ticker = f
	end
end
check(ticker ~= nil, "the cooldown row registered no ticker")

local function tick()
	ticker.scripts.OnUpdate(ticker, 0.2)
end

-- What this class brought, which is what every count below is measured against.
local LISTED = ns.Class.Of("cooldowns") or {}

local function rebuild()
	fire("SPELLS_CHANGED")
	tick()
end

----------------------------------------------------------------------
-- The list is the class file's
----------------------------------------------------------------------

ns.db.locked = true
ns.db.cooldowns = true
ns.db.cooldownIdle = false
inCombat.player = false
worn[13], worn[14] = nil, nil
rebuild()

check(Cooldowns.Count() == #LISTED,
	("a %s was given %d squares and its class file lists %d")
		:format(PLAYER_CLASS, Cooldowns.Count(), #LISTED))

-- Every drawn entry carries a name this client answered for and an id it
-- resolved to, because a square with neither is a square with no picture and
-- nothing to ask the cooldown of.
for index = 1, Cooldowns.Count() do
	local entry = Cooldowns.Entry(index)
	check(entry.name ~= nil,
		("square %d is on the row with no name"):format(index))
	check(entry.id ~= nil or entry.slot ~= nil,
		("square %d resolved to no spell and is not a trinket"):format(index))
end

-- A class with nothing listed is a supported class and says why rather than
-- drawing an empty frame.
if #LISTED == 0 then
	check(Cooldowns.Refusal() ~= nil,
		("a %s draws no row and gives no reason"):format(PLAYER_CLASS))
	check(Cooldowns.Refusal():find(ns.Class.Label(), 1, true) ~= nil,
		("the refusal on a %s does not name the class: %s")
			:format(PLAYER_CLASS, Cooldowns.Refusal()))
end

----------------------------------------------------------------------
-- The three filters
----------------------------------------------------------------------

if #LISTED > 0 then
	local first = LISTED[1]

	-- An entry with two ids is one button under two names, which is what
	-- Bloodlust and Heroism are and what an Ice Block filed under two numbers
	-- is. Losing one of them has to leave the square alone, and that is
	-- asserted before the square is taken away, because a row that dropped an
	-- entry on the first missing id would pass the test below on its own.
	if #first.spells > 1 then
		own.unknown[first.spells[1]] = true
		rebuild()
		check(Cooldowns.Count() == #LISTED,
			("%s has %d ids and lost its square to one of them")
				:format(first.key, #first.spells))
	end

	-- Not learned. A talent nobody spent a point on, which is most of what
	-- separates one warrior from another at the same level.
	for index = 1, #first.spells do
		own.unknown[first.spells[index]] = true
	end
	rebuild()
	check(Cooldowns.Count() == #LISTED - 1,
		("an unlearned %s left %d squares of %d")
			:format(first.key, Cooldowns.Count(), #LISTED))
	for index = 1, #first.spells do
		own.unknown[first.spells[index]] = nil
	end
	rebuild()
	check(Cooldowns.Count() == #LISTED, "learning it back did not put the square back")

	-- Switched off, which is per character and is the only one of the three you
	-- can reach from the panel.
	Cooldowns.SetWatched(first.key, false)
	tick()
	check(Cooldowns.Count() == #LISTED - 1,
		("switching %s off left %d squares of %d")
			:format(first.key, Cooldowns.Count(), #LISTED))
	local silent, names = Cooldowns.Silent()
	check(silent == 1 and names ~= "",
		("a switched off entry is not reported anywhere: %d, %q"):format(silent, names))
	Cooldowns.SetWatched(first.key, true)
	tick()
	check(Cooldowns.Count() == #LISTED, "switching it back on did not put the square back")

	-- A word that belongs to another class is named as such rather than falling
	-- through to the bare on|off toggle, which would switch the whole row off
	-- and report that it had done something else.
	local other
	for token, def in pairs(ns.Class.All()) do
		if token ~= PLAYER_CLASS then
			for index = 1, #(def.cooldowns or {}) do
				other = other or def.cooldowns[index].key
			end
		end
	end
	if other and not Cooldowns.ByWord(other) then
		check(Cooldowns.Elsewhere(other) ~= nil,
			("%s belongs to no class this addon knows"):format(other))
	end
end

----------------------------------------------------------------------
-- What one square is doing
----------------------------------------------------------------------

if #LISTED > 0 then
	local entry = Cooldowns.Entry(1)

	local status = Cooldowns.State(1)
	check(status == "ready", ("a spell off cooldown reads as %s"):format(status))

	-- A global sweep is not a cooldown. Every square in the addon follows this
	-- rule and it is worth asserting on the one row where the whole point is the
	-- number: a row that counted the global would put 1.5 on every square every
	-- time you pressed anything.
	own.cooldowns[entry.id] = { _G.GetTime(), 1.5 }
	tick()
	status = Cooldowns.State(1)
	check(status == "ready", ("a global sweep read as %s"):format(status))

	own.cooldowns[entry.id] = { _G.GetTime(), 180 }
	tick()
	local start, duration
	status, start, duration = Cooldowns.State(1)
	check(status == "cooldown", ("a three minute wait reads as %s"):format(status))
	check(duration == 180, ("the swipe was handed %s seconds"):format(tostring(duration)))
	check(start == _G.GetTime(), "the swipe was handed the wrong start")

	-- Minutes, because a thirty minute cooldown on a 27 pixel square used to
	-- draw four digits of false precision. The whole ladder is walked here,
	-- because what a countdown has to get right is the seams: it rounds down, so
	-- 1m means a minute or more, and there is a label at every step from three
	-- minutes to the last tenth of a second.
	check(Row.Icon(1).timer:GetText() == "3m",
		("a three minute wait reads %q on the square"):format(Row.Icon(1).timer:GetText()))

	advance(61)
	tick()
	check(Row.Icon(1).timer:GetText() == "1m",
		("just under two minutes reads %q"):format(Row.Icon(1).timer:GetText()))

	advance(60)
	tick()
	check(Row.Icon(1).timer:GetText() == "59",
		("just under a minute reads %q"):format(Row.Icon(1).timer:GetText()))

	advance(55)
	tick()
	check(Row.Icon(1).timer:GetText() == "4.0",
		("four seconds left reads %q"):format(Row.Icon(1).timer:GetText()))

	own.cooldowns[entry.id] = nil
	tick()

	-- The window it opened, which the client will not answer for: a cooldown
	-- starts the moment you press the ability and says nothing about whether
	-- the fifteen seconds you pressed it for are still running. The aura is the
	-- only source, and it is read on an event rather than on the tick.
	own.auras[1] = { name = entry.name, icon = "Interface\\Icons\\A" }
	fire("UNIT_AURA", "player")
	tick()
	local _, _, _, active = Cooldowns.State(1)
	check(active == true, ("%s is running and the square does not say so"):format(entry.name))

	own.auras[1] = nil
	fire("UNIT_AURA", "player")
	tick()
	_, _, _, active = Cooldowns.State(1)
	check(active == false, "the window stayed open after the aura came off")
end

----------------------------------------------------------------------
-- The trinkets
--
-- Both slots are filled and exactly one of them takes a square, which is the
-- client answering rather than a list in the addon.
----------------------------------------------------------------------

local before = Cooldowns.Count()
worn[13] = itemLink("Bloodlust Brooch")
worn[14] = itemLink("Mark of Tyranny")
fire("PLAYER_EQUIPMENT_CHANGED")
tick()

check(Cooldowns.Count() == before + 1,
	("two trinkets, one of them passive, added %d squares")
		:format(Cooldowns.Count() - before))

local pressed = Cooldowns.Entry(Cooldowns.Count())
check(pressed.name == "Increased Strength",
	("the trinket square is named %q rather than after its use effect")
		:format(tostring(pressed.name)))
check(Cooldowns.Worn(13):find("Bloodlust Brooch", 1, true) ~= nil,
	("the panel reads trinket 1 as %q"):format(Cooldowns.Worn(13)))
check(Cooldowns.Worn(14):find("worn rather than pressed", 1, true) ~= nil,
	("the panel reads a passive trinket as %q"):format(Cooldowns.Worn(14)))

-- A worn item answers a different call from a spell, which is the one thing
-- about a trinket square that cannot be read off a spell id.
own.worn[13] = { _G.GetTime(), 120 }
tick()
local trinketStatus = Cooldowns.State(Cooldowns.Count())
check(trinketStatus == "cooldown",
	("a trinket on cooldown reads as %s"):format(trinketStatus))
own.worn[13] = nil
tick()

worn[14] = nil
fire("PLAYER_EQUIPMENT_CHANGED")
tick()
check(Cooldowns.Count() == before + 1,
	"taking a passive trinket off moved the row")

----------------------------------------------------------------------
-- When it is on the screen
----------------------------------------------------------------------

local DRAWS = Cooldowns.Count() > 0

inCombat.player = false
tick()
check((Row.Mode() == "quiet") or not DRAWS,
	("everything is ready out of combat and the row is %s"):format(tostring(Row.Mode())))

inCombat.player = true
tick()
check(Row.Mode() == (DRAWS and "fight" or "quiet"),
	("in combat the row is %s"):format(tostring(Row.Mode())))
check(Row.Shown() == Cooldowns.Count(),
	("%d squares drawn of %d on the list"):format(Row.Shown(), Cooldowns.Count()))

-- Out of a fight with something still recovering, which is the pull-or-wait
-- question and the only reason to look at the row between fights.
inCombat.player = false
own.worn[13] = { _G.GetTime(), 120 }
tick()
check(Row.Mode() == (DRAWS and "waiting" or "quiet"),
	("something is still recovering and the row is %s"):format(tostring(Row.Mode())))
own.worn[13] = nil
tick()

ns.db.cooldownIdle = true
Row.Apply()
tick()
check(Row.Mode() == (DRAWS and "waiting" or "quiet"),
	("idle on and the row is %s out of combat"):format(tostring(Row.Mode())))
ns.db.cooldownIdle = false
Row.Apply()

own.dead = true
inCombat.player = false
tick()
check(Row.Mode() == "quiet", "a corpse was drawn a cooldown row")
own.dead = false

ns.db.cooldowns = false
Row.Apply()
tick()
check(Row.Mode() == "quiet" and Row.Shown() == 0,
	"the row is switched off and still drawing")

-- A hidden row lays nothing out, which is a real bug rather than a hypothetical
-- one: the tick compares what it drew last against what it would draw now, and
-- comparing the list's length against the number of squares on the screen makes
-- those two disagree forever while the row is quiet. What that costs is a full
-- relayout of every square, ten times a second, for as long as you are out of a
-- fight. The row compares the list's rebuild count instead, which also catches
-- the rebuild that swaps one entry for another and leaves the length alone.
-- Counted rather than trusted, the way 04-ability-square.lua counts the writes
-- a redraw makes.
local laid = 0
if DRAWS then
	local square = Row.Icon(1)
	local wasPoint, wasHide = square.SetPoint, square.Hide
	square.SetPoint = function() laid = laid + 1 end
	-- Hide as well as SetPoint, and Hide is the one that catches it: a row that
	-- lays itself out while it is quiet takes the branch that hides every square
	-- rather than the one that places them, so a counter on SetPoint alone
	-- watches the half that is not running.
	square.Hide = function() laid = laid + 1 end
	for _ = 1, 20 do
		tick()
	end
	square.SetPoint, square.Hide = wasPoint, wasHide
end
check(laid == 0, ("a hidden row laid its squares out %d times over 20 ticks"):format(laid))

ns.db.cooldowns = true
Row.Apply()

----------------------------------------------------------------------
-- What a square says to the mouse
----------------------------------------------------------------------

inCombat.player = true
tick()

if DRAWS then
	local square = Row.Icon(1)
	local enter = square:GetScript("OnEnter")
	check(enter and square:GetScript("OnLeave"),
		"a cooldown square has no hover scripts, so it can never say what it means")
	ns.UI.Tooltip.Close()
	enter(square)
	check(ns.UI.Tooltip.IsShown(), "hovering a cooldown square opened nothing")
	local title = ns.UI.Tooltip.Text(1)
	check(tostring(title) == Cooldowns.Entry(1).name,
		("the tooltip is titled %q and the square is %q")
			:format(tostring(title), Cooldowns.Entry(1).name))
	ns.UI.Tooltip.Close()
end

----------------------------------------------------------------------
-- The grid, at every zoom
----------------------------------------------------------------------

local shipped = ns.db.cooldownZoom
local off = 0
for _, zoom in ipairs({ 1, 2, 3 }) do
	ns.db.cooldownZoom = zoom
	Row.Apply()
	tick()
	for slot = 1, Row.Shown() do
		local px = ns.UI.Pixel(Row.Icon(slot))
		for _, point in ipairs(Row.Icon(slot).points or {}) do
			local x, y = (point[4] or 0) / px, (point[5] or 0) / px
			if math.abs(x - math.floor(x + 0.5)) > 1e-6
				or math.abs(y - math.floor(y + 0.5)) > 1e-6 then
				off = off + 1
			end
		end
	end
end
check(off == 0, ("%d square anchors were off a whole pixel"):format(off))
ns.db.cooldownZoom = shipped
Row.Apply()
tick()

----------------------------------------------------------------------
-- What the tick costs
--
-- With the clock moving and something on cooldown, which is the row's only
-- moving state.
--
-- Five ticks are run before the count starts and they are the point of the
-- measurement rather than a way around it. The one allocation on this path is
-- the countdown's string, which UI/Ability.lua builds only on the ticks where
-- the number behind it moved; the tick that first drew this square is one of
-- those and every tick after it is the steady state. What the gate is for is
-- the steady state going non-zero, which is what a write nobody guarded looks
-- like.
----------------------------------------------------------------------

if DRAWS then
	own.worn[13] = { _G.GetTime(), 600 }
end
for _ = 1, 5 do
	advance(0.1)
	tick()
end
collectgarbage("collect")
collectgarbage("stop")
local start = collectgarbage("count")
for _ = 1, 50 do
	advance(0.1)
	tick()
end
local churned = collectgarbage("count") - start
collectgarbage("restart")
own.worn[13] = nil
check(churned < CHURN.cooldowns,
	("the cooldown row churned %.2f KB over 50 ticks, gate is %.2f")
		:format(churned, CHURN.cooldowns))

----------------------------------------------------------------------

-- The trinket comes off and the fight ends, because this is the last section
-- and what it leaves behind is what anybody reading a later scene would find.
-- The row itself is left drawn, which is what the print below describes.
inCombat.player = true
tick()

print(("cooldowns %d drawn for a %s, %d off the class file and %d trinket, %s; %s; %.2f KB per 50 ticks, gate is %.2f")
	:format(Row.Shown(), PLAYER_CLASS, #LISTED, Cooldowns.Count() - #LISTED,
		tostring(Row.Mode()), Cooldowns.Describe(), churned, CHURN.cooldowns))
