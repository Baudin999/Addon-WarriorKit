-- The minimap
--
-- Two files and one question each. Shape.lua takes furniture off a frame the
-- addon does not own and has to put every piece of it back; Corral.lua borrows
-- other addons' buttons and has to hand them back the same way. So most of
-- what is asserted below is the reverse, because the forward direction is the
-- easy half of both.

local H = ...
local child, ns, fire = H.child, H.ns, H.fire
local check = H.check

local map = _G.Minimap
local mail = _G.MiniMapMailFrame

-- What the client built. Written down rather than read off the frame,
-- because by the time this block runs PLAYER_LOGIN has already applied the
-- square and what is on the frame is the addon's own arithmetic. These are
-- the numbers the fixture above anchors the map and the mail icon at, and
-- the square is only reversible if they are the ones that come back.
local BUILT_SIZE = 140
local MAIL_POINT, MAIL_X, MAIL_Y = "TOPRIGHT", -3, -30

-- The defaults, applied at login, so the square is already on.
check(ns.db.minimapSquare, "the square did not ship on")
check(map:GetWidth() == ns.db.minimapSize,
	("the map is %d wide and the setting says %d"):format(map:GetWidth(), ns.db.minimapSize))
check(map.mask == "Interface\\Buttons\\WHITE8X8",
	"the round mask is still on a map the addon calls square")
check(_G.MinimapBorder.wkStripped, "the ring is still drawn round a square map")
check(_G.MinimapZoomIn.wkStripped, "the zoom buttons are still on the arc")

-- The sun and the moon, which said whether it was day in a game whose sky
-- says the same thing. Furniture the addon takes off rather than furniture
-- it moves, so unlike the mail icon it is not on a corner and never was.
check(_G.GameTimeFrame.wkStripped, "the sun and moon are still on the map")

-- Blizzard's clock, and the piece that made any of this worth doing: it
-- draws its numbers on a strip of the old stone minimap tile, so on a
-- stripped square it was the last of the round map left on the screen.
--
-- It belongs to Blizzard_TimeManager, which is loaded on demand, so at
-- login it does not exist and there is nothing for the strip to take. The
-- Apply that catches it is the one ADDON_LOADED runs, and that is the whole
-- reason Shape.lua registers the event at all.
check(_G.TimeManagerClockButton == nil,
	"the fixture put Blizzard's clock up before the addon that owns it loaded")
child("button", map, "TimeManagerClockButton")
fire("ADDON_LOADED", "Blizzard_TimeManager")
check(_G.TimeManagerClockButton.wkStripped,
	"Blizzard's clock loaded after login and the square never took it off")

----------------------------------------------------------------------
-- The bezel and the clock
--
-- Their own block, so the names the bezel needs do not follow the clock
-- around. This was a hard requirement when the harness was one chunk against
-- Lua's ceiling of two hundred locals; it is only reading now.
----------------------------------------------------------------------

do
	-- The black the ring used to be. Four bands and a hairline on a frame
	-- of ours anchored outside the map's own bounds, which is what makes it
	-- safe: nothing it draws can land on the world however the client
	-- orders a child frame against its parent.
	local bezel = ns.MinimapShape.Bezel()
	check(bezel ~= nil, "a square map was left with no bezel round it")
	check(bezel:IsShown(), "the bezel is hidden on a map the addon calls square")
	check(bezel.pad > bezel.hairline,
		"the black round the map is no wider than the hairline round the black")

	local point, relative, _, x, y = bezel:GetPoint()
	check(point == "TOPLEFT" and relative == map and x < 0 and y > 0,
		("the bezel is anchored %s at %.2f %.2f, which is not outside the map")
			:format(tostring(point), x, y))

	-- The tab. It hangs off the middle of the bottom of the bezel and
	-- overlaps it by exactly the hairline, because the two edges landing in
	-- one row of pixels is what lets the seam be painted out and the
	-- outline read as one silhouette rather than as a box with a box stuck
	-- to it.
	local tab = _G.WarriorKitClock
	check(tab ~= nil, "the clock tab was never built")

	point, relative, _, x, y = tab:GetPoint()
	check(point == "TOP" and relative == bezel and x == 0,
		"the clock is not centred under the bottom of the bezel")
	check(math.abs(y - bezel.hairline) < 1e-9,
		("the clock overlaps the bezel by %.4f, the hairline is %.4f")
			:format(y, bezel.hairline))
	check(tab:GetWidth() > 0 and tab:GetHeight() > 0, "the clock tab has no size")

	-- Twenty four hours with no CVar to say otherwise, which is the reading
	-- a client that never offered the choice gets.
	check(ns.MinimapClock.Reading():match("^%d%d:%d%d$") ~= nil,
		("the clock reads %s, which is not a 24 hour time")
			:format(tostring(ns.MinimapClock.Reading())))

	-- The guard, and the only reason a clock is allowed on a ticker at all.
	-- The first write happened in Apply; a second look inside the same
	-- minute has nothing to say and must not touch the font string.
	check(ns.MinimapClock.Update() == false,
		"the clock wrote its font string again inside the same minute")

	-- The twelve hour toggle changes both what the reading says and how
	-- wide the widest one is, so it is a rebuild rather than a repaint, and
	-- it arrives on an event that carries every other CVar the client
	-- writes.
	local narrow = tab:GetWidth()
	_G.SetCVar("timeMgrUseMilitaryTime", 0)
	fire("CVAR_UPDATE", "timeMgrUseMilitaryTime")
	check(ns.MinimapClock.Reading():match("^%d?%d:%d%d [AP]M$") ~= nil,
		("the 12 hour clock reads %s"):format(tostring(ns.MinimapClock.Reading())))
	check(tab:GetWidth() > narrow,
		("the tab stayed %.1f wide for a reading three characters longer")
			:format(narrow))

	-- The realm's time, which the face has no room for and the tooltip
	-- carries under the reading that is on it.
	check(ns.MinimapClock.Realm() == "9:07 PM",
		("the realm clock said %s, the stub says 21:07")
			:format(tostring(ns.MinimapClock.Realm())))
	_G.SetCVar("timeMgrUseMilitaryTime", 1)
	fire("CVAR_UPDATE", "timeMgrUseMilitaryTime")
	check(ns.MinimapClock.Realm() == "21:07",
		("the realm clock said %s in 24 hour"):format(tostring(ns.MinimapClock.Realm())))

	-- The hover, and nothing is asserted about it beyond this: it must not
	-- raise. The tooltip is the client's frame and what it draws is the
	-- client's business.
	tab.scripts.OnEnter(tab)
	tab.scripts.OnLeave(tab)
end

-- Blizzard's own buttons were anchored to points on the arc, and a square
-- has no arc. Each is pulled to a corner of the frame itself.
local point, relative = mail:GetPoint()
check(point == "TOPRIGHT" and relative == map,
	"the mail icon was left hanging where the ring used to be")

-- The wheel does the zoom buttons' job now that they are gone. Both ends
-- clamp, because a client asked for a zoom it does not have raises.
local wheel = map:GetScript("OnMouseWheel")
check(wheel ~= nil, "the zoom buttons came off and nothing took their place")
if wheel then
	map.zoom = 2
	wheel(map, 1)
	check(map.zoom == 3, ("a wheel up moved the zoom to %d, not 3"):format(map.zoom))
	map.zoom = 4
	wheel(map, 1)
	check(map.zoom == 4, "a wheel up past the last zoom level was not clamped")
	map.zoom = 0
	wheel(map, -1)
	check(map.zoom == 0, "a wheel down past the first zoom level was not clamped")
end

-- The size is a number rather than a scale, so the frame takes it directly
-- and the cluster under it grows by the same amount.
local clusterBefore = _G.MinimapCluster:GetWidth()
ns.db.minimapSize = 220
ns.MinimapShape.Apply()
check(map:GetWidth() == 220, ("the map did not take 220, it is %d"):format(map:GetWidth()))
check(_G.MinimapCluster:GetWidth() > clusterBefore,
	"the map grew and the cluster the rest of the interface anchors under did not")

-- The reverse, and the half that matters. Everything goes back: the mask,
-- the ring, the width the client drew it at, and the anchor every moved
-- button arrived on.
ns.db.minimapSquare = false
ns.MinimapShape.Apply()
check(map:GetWidth() == BUILT_SIZE,
	("turning the square off left the map %d wide, the client drew it at %d")
		:format(map:GetWidth(), BUILT_SIZE))
check(map.mask == "Textures\\MinimapMask", "the round mask did not come back")
check(not _G.MinimapBorder.wkStripped, "the ring did not come back")
check(not _G.MinimapZoomIn.wkStripped, "the zoom buttons did not come back")
check(not _G.GameTimeFrame.wkStripped, "the sun and moon did not come back")
check(not _G.TimeManagerClockButton.wkStripped,
	"Blizzard's clock did not come back with the round map")
check(not ns.MinimapShape.Bezel():IsShown(),
	"the addon's own bezel is still drawn round a round map")
check(map:GetScript("OnMouseWheel") == nil,
	"the zoom buttons came back and the wheel is still driving them too")

local back, backRelative, backPoint, backX, backY = mail:GetPoint()
check(back == MAIL_POINT and backRelative == map and backPoint == MAIL_POINT
	and backX == MAIL_X and backY == MAIL_Y,
	("the mail icon went back to %s %s %d %d, not %s %s %d %d")
		:format(tostring(back), tostring(backPoint), backX, backY,
			MAIL_POINT, MAIL_POINT, MAIL_X, MAIL_Y))

ns.db.minimapSquare, ns.db.minimapSize = true, 180
ns.MinimapShape.Apply()

----------------------------------------------------------------------
-- The corral
----------------------------------------------------------------------

local corral = _G.WarriorKitCorral
check(corral ~= nil, "the corral button was never built")

-- Three addon buttons on the fixture and nothing else. Blizzard's four are
-- not addon buttons, the unnamed child cannot be released so is never
-- taken, and the seventy-two pins are pins.
check(ns.Corral.Count() == 3,
	("the corral is holding %d buttons, the three addon ones make 3")
		:format(ns.Corral.Count()))

-- The regression, and the one that cost a working Questie map. A pin pool
-- is left where it is, and a pool drawn at a button's size is left there
-- too, which is the half the size window cannot see.
--
-- Only the twelve count as skipped. The sixty are drawn at a pin's size and
-- never become candidates at all, the same way a texture never does, so
-- reporting them would turn a number that means "the corral decided not to"
-- into one that means "the minimap has things on it".
local pooled, refused = ns.Corral.Skipped()
check(pooled == 12,
	("%d frames were read as a pool, the button-sized pool is 12"):format(pooled))
check(refused == 0, ("%d buttons hit the ceiling and nothing should have"):format(refused))
check(_G.QuestieFrame1:GetParent() == map, "a quest pin was collected as a button")
check(_G.QuestieFrame1.wkPinned == nil,
	"a quest pin had its SetPoint taken, so its addon can no longer move it")
check(_G.GatherMatePin1:GetParent() == map,
	"a pin pool drawn at a button's size got past the family rule")
check(_G.SomeAddonMapNote:GetParent() == map, "a named Frame was collected as a button")
for _, name in ipairs({ "MiniMapMailFrame", "GameTimeFrame", "MiniMapTracking" }) do
	check(_G[name]:GetParent() == map,
		("the corral took %s, which is Blizzard's and not an addon's"):format(name))
end

local questie = _G.LibDBIcon10_Questie
check(questie:GetParent() ~= map, "an addon button was counted and not reparented")

-- The pin. A minimap button repositions itself whenever it feels like it,
-- so its own SetPoint is replaced with one that does nothing. Without it
-- the button sits in the tray for a second and jumps back to the arc.
questie:SetPoint("CENTER", map, "CENTER", 60, 20)
check(questie:GetParent() ~= map,
	"the button moved itself back out of the tray")

-- A second scan takes nothing twice.
check(ns.Corral.Scan() == 0, "a second scan collected the same buttons again")

-- And an addon that loads late is picked up on the event that says so,
-- which is the only reason there is no ticker in that file.
do
	local late = child("button", map, "LateLoadingAddonMinimapButton")
	late:SetSize(31, 31)
	late:SetPoint("CENTER", map, "CENTER", -60, 20)
	fire("ADDON_LOADED", "LateLoadingAddon")
	check(ns.Corral.Count() == 4, "an addon that loaded after login was never collected")
end

-- The release, which is the half that matters here too. Parent, anchor and
-- the button's own SetPoint all come back, and a button handed back has to
-- be able to move itself again.
ns.db.minimapCorral = false
ns.Corral.Apply()
check(ns.Corral.Count() == 0, "turning the corral off left it holding buttons")
check(questie:GetParent() == map, "a released button was not handed back to the minimap")
check(questie.wkPinned == nil, "a released button kept the no-op SetPoint")
questie:ClearAllPoints()
questie:SetPoint("CENTER", map, "CENTER", 11, 22)
local qx, qy = select(4, questie:GetPoint())
check(qx == 11 and qy == 22, "a released button still cannot move itself")

ns.db.minimapCorral = true
ns.Corral.Apply()

print(("minimap %s; corral %s, %d of %d children collected")
	:format(ns.MinimapShape.Describe(), ns.Corral.Describe(),
		ns.Corral.Count(), select("#", map:GetChildren())))
