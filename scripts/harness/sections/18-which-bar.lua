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

_G.UnitIsUnit = realIsUnit
guids.target = nil
