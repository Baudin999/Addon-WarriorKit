local ADDON, ns = ...

local UI = ns.UI

local Anchors = {}
ns.CombatTextAnchors = Anchors

--------------------------------------------------------------------------
-- The three places numbers come from
--
-- Everything this part draws flies away from one of three points on the screen,
-- and every one of them is a rectangle you can unlock and drag. What lands on
-- you comes off the left one, what you land on your target comes off the right
-- one, and a word about the fight comes off the one above your head.
--
-- **Why the spawn point is the whole anchor.** A number's flight has two ends
-- and only the first one is placed. Where it finishes is the start plus the
-- fall, and the fall is a number on the settings page, so moving the anchor
-- moves the whole arc rather than stretching it. The alternative is six grab
-- handles for three streams, which is a placing session rather than a setting,
-- and it cannot express the curve anyway: the far end of a bow is not a
-- straight offset from the near one.
--
-- **Why they are frames at all rather than four numbers.** A number is anchored
-- CENTER to CENTER on one of these, so the anchor is what the flight is
-- measured against and it survives a resolution change, a UI scale change and a
-- drag without any of the three being handled here. UI/Placeable.lua already
-- owns the drag, the rim, the name over it and writing the corner back into a
-- setting, and this file is twelve lines of caller on top of it.
--
-- The rectangles have nothing in them and take the mouse only while they are
-- unlocked, which is the case UI/Placeable.lua's `name` option exists for: they
-- sit over the middle of the screen where the right button drag that turns the
-- camera starts, and a frame that answered the mouse all the time would eat it.
--------------------------------------------------------------------------

-- Big enough to grab and read a name over, and no larger: this is a handle
-- rather than a container. Nothing is ever parented into one, so its size has
-- no effect at all once the frames are locked.
local WIDTH, HEIGHT = 90, 28

-- The three, in the order they are drawn on the settings page.
--
--   key    the setting its corner is written into
--   name   what is written over it while the frames are unlocked
--
-- A table walked by both Build and Apply rather than three of everything, which
-- is the shape this addon has had to be shown twice: UI/Placeable.lua exists
-- because twelve parts wrote the same drag out longhand.
local SPOTS = {
	{ id = "mine", key = "hitsMinePoint", name = "WarriorKit hits on you" },
	{ id = "theirs", key = "hitsTheirsPoint", name = "WarriorKit hits you land" },
	{ id = "calls", key = "hitsCallsPoint", name = "WarriorKit combat calls" },
}

local frames, places = {}, {}

--------------------------------------------------------------------------

-- cold: Build makes one anchor, on the first pass after the part is switched on
local function Build(spot)
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	-- Above the world and under every window the addon draws. A number is a
	-- caption on the fight and must not be over the bag you have opened.
	frame:SetFrameStrata("MEDIUM")
	frames[spot.id] = frame

	places[spot.id] = UI.Placeable(frame, {
		name = spot.name,
		moved = function(anchor)
			ns.db[spot.key] = anchor
		end,
	})
	return frame
end

-- The three frames, made the first time anything asks for one.
--
-- Built on demand rather than at login for the reason Swing/Gauges.lua is: a
-- part that ships switched off should not be three frames and three drag
-- handlers on a character that never turns it on.
--
-- cold: Anchors.Apply places three anchors, on a settings change and on the first number of a session
function Anchors.Apply()
	for index = 1, #SPOTS do
		local spot = SPOTS[index]
		local frame = frames[spot.id] or Build(spot)
		local anchor = ns.db[spot.key]
		frame:ClearAllPoints()
		frame:SetPoint(anchor[1], UIParent, anchor[3], anchor[4], anchor[5])
	end
end

-- Where a stream throws from, built if it has to be. Callers hold the frame for
-- the life of the session, so this is asked once each rather than per number.
function Anchors.Of(id)
	if not frames[id] then
		Anchors.Apply()
	end
	return frames[id]
end

function Anchors.Lock(unlocked)
	for index = 1, #SPOTS do
		local place = places[SPOTS[index].id]
		if place then
			place:Lock(unlocked)
		end
	end
end

function Anchors.Reset()
	for index = 1, #SPOTS do
		local spot = SPOTS[index]
		ns.db[spot.key] = ns.DefaultCopy(spot.key)
	end
	Anchors.Apply()
end

-- What the settings page says about where they are, and the only reason this
-- file answers a question at all: three rectangles you cannot see are three
-- things a status line has to be able to name.
function Anchors.Describe()
	local anchor = ns.db.hitsMinePoint
	return ("hits on you at %d, %d"):format(anchor[4], anchor[5])
end
