-- The row of what you have out
--
-- Five questions, and the first two are what make this a class part rather than
-- a shaman part.
--
-- Is the row the class file's. Every count below is measured against whatever
-- Class/<yours>.lua wrote into `standing`, so the section runs unchanged on all
-- twelve shapes: a shaman draws four squares, everybody else draws none, and
-- neither number is written in this file.
--
-- Does a class with no plan build nothing at all. Not a hidden frame, not a
-- placeable rectangle, not a ticker: a part that is not for you costs nothing
-- and says why. That is the half a reading of the source cannot settle, because
-- the frame is made inside an event handler.
--
-- Does a slot filling light its own square and no other. The four slots are
-- read by the client's own numbering and drawn in the plan's order, and those
-- two orders are deliberately different, so a row that used one for the other
-- would light the wrong square and look entirely correct.
--
-- Are the empty slots still drawn. That is the whole design of the row against
-- the client's own: a hole keeps its place, so the shape of the row is what you
-- read rather than the names on it. A row that shrank to what is up would pass
-- every other assertion here.
--
-- And is it on the screen when it should be: up in a fight, up afterwards while
-- something is still standing, gone when everything has run out, and up anyway
-- when you asked for that. Plus the tick, which allocates nothing.

local H = ...
local PLAYER_CLASS, CHURN = H.PLAYER_CLASS, H.CHURN
local totems, own, inCombat = H.totems, H.own, H.inCombat
local advance = H.advance
local ns, fire, check = H.ns, H.fire, H.check

local Standing, Row = ns.Standing, ns.StandingRow

-- Anchors come back off the client as floats and a pixel is a whole number of
-- them, which is the same helper 67-talents.lua and 68-spellbook.lua carry.
local function whole(value)
	return math.abs(value - math.floor(value + 0.5)) < 1e-6
end

-- What this character brought, which is what every count below is measured
-- against. Read off the registry rather than off the part, so the part cannot
-- be measured against its own answer.
local PLAN = ns.Class.Of("standing")
local SLOTS = PLAN and PLAN.slots or {}

local function tick()
	local running = ns.UI.Ticking("standing")
	if running then
		running:Beat(0.2)
	end
end

----------------------------------------------------------------------
-- A class with no plan builds nothing
----------------------------------------------------------------------

if #SLOTS == 0 then
	check(Standing.Available() == false,
		("a %s has no plan and the part says it is available"):format(PLAYER_CLASS))
	check(_G.WarriorKitStanding == nil,
		("a %s built a row frame with nothing to put on it"):format(PLAYER_CLASS))
	check(ns.UI.Ticking("standing") == nil,
		("a %s armed the row's ticker with nothing to draw"):format(PLAYER_CLASS))
	check(Standing.Count() == 0,
		("a %s was given %d slots"):format(PLAYER_CLASS, Standing.Count()))

	-- Refused in words, and the words name the class. A switch that does
	-- nothing and says nothing reads as a broken addon.
	local refusal = Standing.Refusal()
	check(refusal ~= nil,
		("a %s draws no row and gives no reason"):format(PLAYER_CLASS))
	check(refusal == nil or refusal:find(ns.Class.Label(), 1, true) ~= nil,
		("the refusal on a %s does not name the class: %s")
			:format(PLAYER_CLASS, tostring(refusal)))

	-- And the switch is left out of On and off rather than drawn there
	-- pointing at a page that was never opened.
	for _, feature in ipairs(ns.features) do
		if feature.name == "standing" then
			check(ns.Options.SwitchAvailable(feature) == false,
				("the row's switch reads available on a %s"):format(PLAYER_CLASS))
		end
	end

	print(("standing no plan for a %s, nothing built, refused with: %s")
		:format(PLAYER_CLASS, tostring(Standing.Refusal())))
	return
end

----------------------------------------------------------------------
-- The list is the class file's
----------------------------------------------------------------------

ns.db.locked = true
ns.db.standing = true
ns.db.standingIdle = false
inCombat.player = false
own.dead = false

check(Standing.Count() == #SLOTS,
	("a %s was given %d squares and its class file lists %d")
		:format(PLAYER_CLASS, Standing.Count(), #SLOTS))

check(_G.WarriorKitStanding ~= nil,
	("a %s has a plan and no row frame was built"):format(PLAYER_CLASS))
check(ns.UI.Ticking("standing") ~= nil, "the row registered no ticker")

-- In the plan's order, which is not the client's numbering. The two are
-- different on purpose and this is the assertion that says so: a shaman's slots
-- are drawn earth, fire, water, air and the client counts them fire, earth,
-- water, air.
local shuffled = false
for index = 1, #SLOTS do
	local slot = Standing.Slot(index)
	check(slot == SLOTS[index],
		("square %d is not the %d%s slot the plan wrote down"):format(index, index, "th"))
	if slot.index ~= index then
		shuffled = true
	end
end
check(shuffled, "every slot is drawn at its own client index, so nothing here"
	.. " would catch a row that read the plan's order off the numbering")

-- Every slot has the four things a square is drawn out of. A slot with no
-- colour is a hole you cannot tell from the hole beside it, which is the one
-- thing this row has instead of captions.
for index = 1, #SLOTS do
	local slot = Standing.Slot(index)
	check(type(slot.label) == "string" and slot.label ~= "",
		("slot %d has no label"):format(index))
	check(type(slot.index) == "number",
		("slot %d names no client slot"):format(index))
	check(type(slot.color) == "table" and #slot.color >= 3,
		("slot %d has no colour, and colour is all an empty one says"):format(index))
end

-- And no two of them are the same colour, which is the property the reading
-- depends on rather than the presence of a table.
for a = 1, #SLOTS do
	for b = a + 1, #SLOTS do
		local one, two = SLOTS[a].color, SLOTS[b].color
		check(one[1] ~= two[1] or one[2] ~= two[2] or one[3] ~= two[3],
			("%s and %s are drawn in the same colour")
				:format(SLOTS[a].label, SLOTS[b].label))
	end
end

----------------------------------------------------------------------
-- One slot filling lights one square
----------------------------------------------------------------------

local NOW = _G.GetTime()
local FIRST = Standing.Slot(1)

totems[FIRST.index] = {
	name = "Stoneskin Totem", start = NOW, duration = 120,
	icon = "Interface\\Icons\\Spell_Nature_StoneSkinTotem",
}
fire("PLAYER_TOTEM_UPDATE")
tick()

local up, art, ends, span, name = Standing.State(1)
check(up == true, ("filling the %s slot left it reading empty"):format(FIRST.label))
check(name == "Stoneskin Totem",
	("the %s slot came back named %s"):format(FIRST.label, tostring(name)))
check(art ~= nil, "a filled slot came back with no art to draw")
check(ends == NOW + 120 and span == 120,
	("a filled slot runs out at %s over %s rather than at %d over 120")
		:format(tostring(ends), tostring(span), NOW + 120))

for index = 2, #SLOTS do
	check(Standing.State(index) == false,
		("filling the %s slot lit the %s one as well")
			:format(FIRST.label, Standing.Slot(index).label))
end
check(Standing.Up() == 1,
	("one totem is out and the row counts %d"):format(Standing.Up()))

----------------------------------------------------------------------
-- The holes keep their places
----------------------------------------------------------------------

check(Row.Shown() == #SLOTS,
	("one slot is filled and the row drew %d squares of %d")
		:format(Row.Shown(), #SLOTS))

-- Side by side, in order, on whole pixels, and none of them overlapping the
-- next. The one thing a fixed row promises is that the second square is always
-- in the second place.
local pitch
for index = 2, #SLOTS do
	local left = Row.Icon(index - 1)
	local here = Row.Icon(index)
	local gap = here:GetLeft() - (left:GetLeft() + left:GetWidth())
	check(gap > 0, ("square %d overlaps the one before it"):format(index))
	check(whole(gap),
		("square %d sits %s pixels from the one before it, which is not a whole"
			.. " number of them"):format(index, tostring(gap)))
	pitch = pitch or gap
	check(math.abs(gap - pitch) < 1e-6,
		("square %d sits %s from the one before it and square 2 sits %s")
			:format(index, tostring(gap), tostring(pitch)))
end

-- And the hairline round each one is that slot's own colour, which is the whole
-- of what an empty square says.
for index = 1, #SLOTS do
	local edges = Row.Icon(index).edges
	local color = Standing.Slot(index).color
	check(edges.r == color[1] and edges.g == color[2] and edges.b == color[3],
		("square %d is not drawn in its slot's colour"):format(index))
end

----------------------------------------------------------------------
-- When it is on the screen
----------------------------------------------------------------------

check(Row.Mode() == "standing",
	("out of combat with one totem out the row is %s"):format(tostring(Row.Mode())))

inCombat.player = true
tick()
check(Row.Mode() == "fight",
	("in a fight the row is %s"):format(tostring(Row.Mode())))
inCombat.player = false

-- Everything run out and no fight is the resting state, and the row is not
-- there for it. A row of four holes over your character between pulls is
-- furniture, which is the argument the buff nag's header makes about itself.
totems[FIRST.index] = nil
fire("PLAYER_TOTEM_UPDATE")
tick()
check(Row.Mode() == "quiet",
	("with nothing standing and no fight the row is %s"):format(tostring(Row.Mode())))
check(_G.WarriorKitStanding:IsShown() == false,
	"a quiet row is still on the screen")

ns.db.standingIdle = true
Row.Apply()
tick()
check(Row.Mode() == "standing",
	("idle is on and the row is %s"):format(tostring(Row.Mode())))
check(Row.Shown() == #SLOTS,
	("an idle row of nothing drew %d squares of %d"):format(Row.Shown(), #SLOTS))
ns.db.standingIdle = false
Row.Apply()

-- Off is off, and it stops the tick rather than drawing nothing ten times a
-- second for the rest of the session.
ns.db.standing = false
Row.Apply()
check(ns.UI.Ticking("standing") == nil,
	"the row is switched off and its tick is still running")
ns.db.standing = true
Row.Apply()

----------------------------------------------------------------------
-- What the tick costs
----------------------------------------------------------------------

-- Every slot filled and every one of them under a minute, so the number over
-- each square is counted in seconds and is rebuilt once a second per square for
-- the whole loop. That is the row's real steady state and it cannot be zero: a
-- gate quoted with the clock stopped would be measuring UI/Aura.lua's guard
-- rather than this tick, which is the argument the meters' gate is set by.
for index = 1, #SLOTS do
	local slot = Standing.Slot(index)
	totems[slot.index] = {
		name = slot.label, start = _G.GetTime(), duration = 45 + index,
		icon = "Interface\\Icons\\Spell_Nature_" .. slot.label,
	}
end
inCombat.player = true
fire("PLAYER_TOTEM_UPDATE")

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
check(churned < CHURN.standing,
	("the row churned %.2f KB over 50 ticks, gate is %.2f")
		:format(churned, CHURN.standing))

----------------------------------------------------------------------

-- Everything put back, because a later reader finds whatever this leaves.
for index = 1, #SLOTS do
	totems[Standing.Slot(index).index] = nil
end
inCombat.player = false
fire("PLAYER_TOTEM_UPDATE")
tick()

print(("standing %d slots for a %s, %s, %s; %.2f KB per 50 ticks, gate is %.2f")
	:format(#SLOTS, PLAYER_CLASS, Standing.Word(), Standing.Describe(),
		churned, CHURN.standing))
