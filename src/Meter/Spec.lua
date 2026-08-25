local ADDON, ns = ...

local Spec = {}
ns.MeterSpec = Spec

--------------------------------------------------------------------------
-- What to draw beside a name
--
-- Neither of these clients has a spec. There is no GetSpecialization, no spec
-- id and nothing on a unit that says "Arms": a TBC character is three talent
-- trees with points in them, and which tree has the most is the whole of what
-- anyone means by a spec here. Details resolves its own player that way and
-- shows a class icon for everybody else, which is the honest floor.
--
-- This goes one step past that floor, because the tree icon is a better row
-- than the class icon and the client will hand it over if you ask properly.
--
--   yourself     GetTalentTabInfo reads your own trees at any time, for free.
--                Re-read whenever a point is spent.
--   anyone else  NotifyInspect, then GetTalentTabInfo with the inspect flag
--                once INSPECT_READY names them. Inside about 28 yards, out of
--                combat, one request at a time, and never twice for the same
--                person inside a minute.
--   neither      the class icon, which is always right and always available.
--
-- So the icon sharpens as the fight goes on and never blocks on anything. A
-- row is drawn from the moment its first swing lands, with whatever is known
-- then.
--
-- Two returns of GetTalentTabInfo, because the signature moved. The build that
-- leads with a numeric tab id answers id, name, description, icon, points,
-- file; the older one leads with the name and answers name, icon, points. The
-- first value is a number in one and a string in the other, which is the only
-- discriminator that does not depend on how far down the tail a nil appears.
--------------------------------------------------------------------------

-- Points in one tree before it is called a spec. Five, the figure Details
-- uses, which at level ten is a real choice and at level one is not.
local MIN_POINTS = 5

local TABS = 3

-- The sheet every class icon is cut from, and the crop of a spell icon, which
-- is the same five texel border UI.Icon takes off.
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local ICON_CROP = 5 / 64

-- One inspect in flight, one request every few seconds, and a minute before
-- the same person is asked again. The client throttles inspection itself and
-- answers nothing at all when pushed, so this is well under whatever it does.
local REQUEST_GAP = 3
local RETRY_GAP = 60

-- How long a request waits before it is written off. There is no event for an
-- inspect the client decided not to answer: the target walks out of range, or
-- zones, or the client drops it, and INSPECT_READY simply never comes. Without
-- an expiry one dropped request parks the queue on that GUID and no icon in the
-- group ever resolves again, which would look exactly like the feature not
-- working rather than like one lost packet.
local TIMEOUT = 5
local INSPECT_RANGE = 1 -- CheckInteractDistance's inspect index

-- guid -> talent icon path, or false for "asked, and this client would not say"
local icons = {}
-- guid -> when it was last asked, so a miss is retried rather than given up on
local asked = {}

local pending, pendingAt

local GetTalentTabInfo = _G.GetTalentTabInfo
local GetNumTalentTabs = _G.GetNumTalentTabs
local NotifyInspect = _G.NotifyInspect
local ClearInspectPlayer = _G.ClearInspectPlayer
local CheckInteractDistance = _G.CheckInteractDistance
local UnitIsConnected = _G.UnitIsConnected

--------------------------------------------------------------------------

-- Whether this client will answer the talent question at all. Details calls
-- both of these on both clients, so the probe is belt and braces rather than
-- doubt, and it costs one comparison at load.
function Spec.Ready()
	return type(GetTalentTabInfo) == "function"
end

function Spec.CanInspect()
	return type(NotifyInspect) == "function" and Spec.Ready()
end

-- Icon and points for one tree, across both signatures.
local function Tree(index, inspect)
	if not Spec.Ready() then
		return nil, 0
	end
	local first, second, third, fourth, fifth = GetTalentTabInfo(index, inspect)
	if type(first) == "number" then
		-- id, name, description, icon, points
		return fourth, tonumber(fifth) or 0
	end
	-- name, icon, points
	return second, tonumber(third) or 0
end

-- The icon of whichever tree has the most points in it, or nil where nobody has
-- committed to anything yet. Ties go to the first tree, which is arbitrary and
-- is also what every other addon does with them.
local function Resolve(inspect)
	local tabs = TABS
	if type(GetNumTalentTabs) == "function" then
		tabs = tonumber(GetNumTalentTabs()) or TABS
	end

	local bestIcon, bestPoints = nil, 0
	for index = 1, tabs do
		local icon, points = Tree(index, inspect)
		if icon and points > bestPoints then
			bestIcon, bestPoints = icon, points
		end
	end

	if bestPoints < MIN_POINTS then
		return nil
	end
	return bestIcon
end

--------------------------------------------------------------------------
-- Asking about someone else
--------------------------------------------------------------------------

-- Whether this unit can be inspected right now. Every one of these is a reason
-- the client would refuse or, worse, take the request and never answer, which
-- would park `pending` on someone unreachable.
local function Inspectable(unit)
	if not unit or not UnitExists(unit) or UnitIsUnit(unit, "player") then
		return false
	end
	if not UnitIsPlayer(unit) then
		return false
	end
	if type(UnitIsConnected) == "function" and not UnitIsConnected(unit) then
		return false
	end
	if type(CheckInteractDistance) == "function"
		and not CheckInteractDistance(unit, INSPECT_RANGE) then
		return false
	end
	return true
end

-- Ask about one GUID, if this is a reasonable moment to. Called from the
-- window's tick with whoever is on screen and unresolved, so the cost of
-- refusing has to be a handful of comparisons and no allocation.
--
-- Out of combat only. Inspection in a fight is the request most likely to be
-- dropped, and it is also the moment the answer matters least: the icon is
-- decoration on a row whose number is the point.
function Spec.Request(guid)
	if not guid or icons[guid] or not Spec.CanInspect() then
		return false
	end
	if InCombatLockdown() then
		return false
	end

	local now = GetTime()

	if pending and (now - pendingAt) > TIMEOUT then
		pending = nil
	end
	if pending then
		return false
	end

	if pendingAt and now - pendingAt < REQUEST_GAP then
		return false
	end
	local last = asked[guid]
	if last and now - last < RETRY_GAP then
		return false
	end

	local unit = ns.MeterRoster.UnitFor(guid)
	if not Inspectable(unit) then
		-- Recorded as asked anyway. Someone out of range on every tick for the
		-- next minute is someone this must stop reconsidering five times a
		-- second, and a minute later they may well be standing next to you.
		asked[guid] = now
		return false
	end

	asked[guid] = now
	pending, pendingAt = guid, now
	NotifyInspect(unit)
	return true
end

-- The client answered. It names the GUID it answered about, which may not be
-- the one asked for: anything else on the client can open the inspect window
-- and this event is not ours alone.
local function InspectReady(guid)
	if not guid or guid ~= pending then
		return
	end
	pending = nil

	local unit = ns.MeterRoster.UnitFor(guid)
	if unit and UnitExists(unit) then
		icons[guid] = Resolve(true) or false
	end

	if type(ClearInspectPlayer) == "function" then
		ClearInspectPlayer()
	end
end

--------------------------------------------------------------------------
-- Reading it back
--------------------------------------------------------------------------

-- The texture and its four crop coordinates, for one row. Always answers
-- something drawable: a talent icon where one is known, the class icon
-- otherwise, and the question mark the client uses for an unknown class where
-- even that is missing.
--
-- Five returns rather than a table, because this is called once per row per
-- tick and a table per row per tick is exactly the allocation the harness
-- measures.
function Spec.Icon(guid, class)
	local icon = guid and icons[guid]
	if icon then
		return icon, ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP
	end

	local coords = class and _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[class]
	if coords then
		return CLASS_SHEET, coords[1], coords[2], coords[3], coords[4]
	end

	return "Interface\\Icons\\INV_Misc_QuestionMark",
		ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP
end

-- Whether a real spec was resolved for this GUID, as opposed to the class
-- icon standing in. The panel says how many of the group got one, because a
-- feature whose quality depends on range and timing should be able to report
-- how it is doing rather than leave you guessing at the icons.
function Spec.Known(guid)
	return (guid and icons[guid]) and true or false
end

function Spec.Forget()
	wipe(icons)
	wipe(asked)
	pending, pendingAt = nil, nil
end

-- Your own, read straight out of your talent trees. Free, so it is done at
-- login and again on every point spent rather than waited for.
function Spec.Refresh()
	local guid = UnitGUID("player")
	if not guid or not Spec.Ready() then
		return
	end
	icons[guid] = Resolve(false) or false
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CHARACTER_POINTS_CHANGED")
events:RegisterEvent("INSPECT_READY")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "INSPECT_READY" then
		InspectReady(...)
		return
	end
	Spec.Refresh()
end)
