-- Which bar is yours
--
-- Four states and not two. The third is the one that gets lost in a refactor:
-- with nothing targeted every bar is bright, because dimming the whole screen
-- to say "none of these" is noise and it is the moment you most want to read
-- threat off a mob that is not yours yet.

local H = ...
local guids, ns, fire = H.guids, H.ns, H.fire
local check = H.check
local barTicker = H.carry.barTicker

-- Everything above this point has been driving the panel and the skin, so
-- the bars are put back where this section needs them rather than assumed.
-- UnitIsUnit compares tokens in the stub, which is enough for every other
-- caller and not enough here: "nameplate1" and "target" are two tokens for
-- one mob and that is the whole question being asked.
local realIsUnit = _G.UnitIsUnit
_G.UnitIsUnit = function(x, y)
	if x == y then
		return true
	end
	return guids[x] ~= nil and guids[x] == guids[y]
end

ns.db.bars = true
ns.db.barsMode = "plates"
guids.target = nil
ns.EnemyBars.Rebuild()
for i = 1, 2 do
	fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i)
end
check(ns.EnemyBars.WidgetFor("nameplate1") ~= nil,
	"no bar attached, so the alpha states below would pass on nothing")

local function Alpha(unit)
	local bar = ns.EnemyBars.WidgetFor(unit)
	return bar and bar:GetAlpha() or -1
end
local function Tick()
	for _ = 1, 4 do
		barTicker.scripts.OnUpdate(barTicker, 0.05)
	end
end

Tick()
check(Alpha("nameplate1") == 1 and Alpha("nameplate2") == 1,
	"with nothing targeted both bars should be bright")

guids.target = guids.nameplate1
Tick()
check(Alpha("nameplate1") == 1, "the targeted bar should be at full alpha")
check(Alpha("nameplate1") > Alpha("nameplate2"),
	("the targeted bar is %.2f against %.2f on the other")
		:format(Alpha("nameplate1"), Alpha("nameplate2")))

guids.target = guids.nameplate2
Tick()
check(Alpha("nameplate2") > Alpha("nameplate1"),
	"switching target should move the bright bar with it")

guids.target = nil
Tick()
check(Alpha("nameplate1") == 1 and Alpha("nameplate2") == 1,
	"dropping target should bring every bar back to full")

guids.target = guids.nameplate1
Tick()
print(("alpha  yours %.2f, theirs %.2f, and every bar %.2f with nothing targeted")
	:format(Alpha("nameplate1"), Alpha("nameplate2"), 1))

--------------------------------------------------------------------------
-- Arriving and leaving
--
-- The ramp is a second thing riding on the same channel, so it is checked here
-- rather than somewhere of its own: what has to hold is that the two multiply.
-- A bar halfway in that is not your target is dim and half arrived at once, and
-- a refactor that let either one overwrite the other would still pass every
-- check above.
--------------------------------------------------------------------------

guids.target = nil
local frame = 1 / 60

-- Leaving first, because nameplate1 is up and taking it down is the state the
-- ramp exists for: the client hides a plate the moment its mob is gone, so a
-- bar still fading has to be off that plate and holding its own place on the
-- screen or the tail is invisible whatever its alpha says.
local leaving = ns.EnemyBars.WidgetFor("nameplate1")
fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
check(ns.EnemyBars.WidgetFor("nameplate1") == nil,
	"the bar is still attached to a plate that is gone")
check(leaving:IsShown() and leaving:GetAlpha() > 0, "the bar went out in one frame")
check(leaving:GetParent() == _G.UIParent,
	"a fading bar is still a child of the plate it is leaving")
for _ = 1, 4 do
	barTicker.scripts.OnUpdate(barTicker, frame)
end
check(leaving:GetAlpha() < 1 and leaving:GetAlpha() > 0,
	("four frames out, a bar leaving is at %.2f"):format(leaving:GetAlpha()))
Tick()
Tick()
check(not leaving:IsShown(), "a bar leaving never finished")

-- And arriving, which is the same plate coming back.
fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(Alpha("nameplate1") == 0, "a bar arrived at full alpha instead of from nothing")
for _ = 1, 4 do
	barTicker.scripts.OnUpdate(barTicker, frame)
end
local arriving = Alpha("nameplate1")
check(arriving > 0 and arriving < 1,
	("four frames in, a bar arriving is at %.2f and should be between the two"):format(arriving))
Tick()
check(Alpha("nameplate1") == 1, "a bar never finished arriving")

-- Off has to mean off rather than fast: a plate arriving is a bar at full
-- alpha on the frame it arrives, which is what the bars did before the ramp.
ns.db.barsFade = false
fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(Alpha("nameplate1") == 1, "with the ramp off a bar still arrived from nothing")
ns.db.barsFade = true

print(("ramp   four frames in is %.2f, out is off the plate and holding its place, off is full on the frame")
	:format(arriving))

--------------------------------------------------------------------------
-- The other faction
--
-- Attackable is the client's word and it is nearly the whole rule for which
-- plate gets a bar. The exception is a player of the other faction, who is
-- attackable and unflagged in their own zone on a PvP realm and gets a bar
-- only once the flag is up. Driven on nameplate2 rather than a plate of its
-- own, because the stub's plates persist and a third would be in every scene
-- after this one.
--------------------------------------------------------------------------

local realPlayers, unitFaction = H.realPlayers, H.unitFaction
local pvpUnits, ffaUnits = H.pvpUnits, H.ffaUnits

fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
realPlayers.nameplate2, unitFaction.nameplate2 = true, "Horde"
fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
check(ns.EnemyBars.WidgetFor("nameplate2") == nil,
	"an unflagged player of the other faction got a bar")

-- Flagging in front of you is the faction event on a plate that has no bar
-- for the tick to look at, so the event is the only way the bar arrives.
pvpUnits.nameplate2 = true
fire("UNIT_FACTION", "nameplate2")
check(ns.EnemyBars.WidgetFor("nameplate2") ~= nil,
	"a player of the other faction flagged and got no bar")

-- The flag dropping is the tick's business as much as the event's: a bar on
-- somebody who is no longer flagged goes on the next reading either way.
pvpUnits.nameplate2 = nil
Tick()
check(ns.EnemyBars.WidgetFor("nameplate2") == nil,
	"a player whose flag dropped kept the bar")

-- Gurubashi: no PvP flag, free-for-all instead, and still a bar.
ffaUnits.nameplate2 = true
fire("UNIT_FACTION", "nameplate2")
check(ns.EnemyBars.WidgetFor("nameplate2") ~= nil,
	"a free-for-all player of the other faction got no bar")
ffaUnits.nameplate2 = nil
Tick()

-- Your own faction is left to the client. A duel flags nobody and the bar on
-- your duel partner is the point of the duel.
unitFaction.nameplate2 = "Alliance"
fire("UNIT_FACTION", "nameplate2")
check(ns.EnemyBars.WidgetFor("nameplate2") ~= nil,
	"an attackable player of your own faction got no bar without a flag")

print("faction the other side gets a bar flagged or free-for-all, and none otherwise; your own side is the client's call")

-- Back to a mob, so every section after this one sees the plate it always has.
fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
realPlayers.nameplate2, unitFaction.nameplate2 = nil, nil
fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
check(ns.EnemyBars.WidgetFor("nameplate2") ~= nil, "nameplate2 did not come back as a mob")
Tick()
Tick()

_G.UnitIsUnit = realIsUnit
guids.target = nil
