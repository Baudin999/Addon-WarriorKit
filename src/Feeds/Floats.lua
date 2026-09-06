local ADDON, ns = ...

local UI = ns.UI
local Float = ns.Ck.Float

local Floats = {}
ns.Floats = Floats

--------------------------------------------------------------------------
-- Drops, floated
--
-- What you just picked up, sliding in from the edge of the screen, resting a
-- moment beside the middle of it and fading. Several at once come in one under
-- the other, a beat apart, and climb when the one above them goes.
--
-- This is the first caller of ns.Ck.Float and it is deliberately the smallest
-- one that proves the library: it builds a row, hands it to a lane and takes it
-- back afterwards, and it does not know that anything moved.
--
-- **Where the settings live.** Every number the message is made of is one, and
-- all of them are read here. The library takes each as a spec field and reads
-- ns.db for none of them, which is what keeps it liftable into an addon of its
-- own, so this file is the whole of the join between a slider on a page and a
-- message crossing a screen.
--
-- **Why it reads chat rather than the loot window,** and why the sentence is
-- taken apart by the client's own format strings rather than by text typed
-- here, is written out at the head of Feeds/Loot.lua. This is the second reader
-- of ns.LootLine and it asks the same question through the same door.
--
-- **Why it is not a branch inside that file.** The feed is a column in a
-- window you open. This is a thing that happens on your screen while you are
-- looking at a mob. They answer to different switches, and a drop that the
-- feed's quality chips have filtered out is still a drop you want to see float
-- past. One event, two readers, no shared state.
--
-- **Why the rows are pooled.** A pull drops six items in a second and the lane
-- hands each row back the moment it has faded, so the pool settles at whatever
-- the screen held at once and never allocates again. Nothing here is on a tick,
-- but the lane's reflow is, and a row it releases must not be a row somebody
-- then rebuilds.
--------------------------------------------------------------------------

-- The defaults, which are the spec this was built to: in from forty pixels
-- inside the right edge, invisible, to forty pixels short of the centre, solid,
-- in half a second; a second on screen; a hundred pixels down from the top.
--
-- Every one of them is a setting now, and the reason is that none of them is a
-- fact. Where the eye is on a screen, how long a caption has to be up to be
-- read, and how much of the middle a message may cross are answers about a
-- monitor and a person, not about loot, and the numbers below are one person's.
-- ns.Ck.Float took them as spec fields from the first day for exactly this: the
-- library reads no setting and this file reads them all.
--
-- One number is missing from the list and one is on it that looks like it
-- should not be. The height is worked out rather than stored: a row is as tall
-- as the tallest thing on it, because a height beside an icon size is two
-- settings that have to agree and the one somebody forgets to move writes over
-- the message underneath. The width is stored rather than measured, because the
-- lane rests a message by its far edge and a row that sized itself to the name
-- in it would be a column whose left edge moved with every drop.
--
-- The picture is fifty pixels by default, two and a half times what the loot
-- feed's column draws, and the name is twenty rather than the twelve every
-- panel in the addon uses. Neither is UI.Metric and neither should be: those
-- numbers are the size of a control in a window, and this is a caption on the
-- world read at arm's length in the second before it goes.
local DEFAULTS = {
	lootFloat = true,
	lootFloatSide = "RIGHT",
	lootFloatEdge = 40,
	lootFloatRest = 40,
	lootFloatTop = 100,
	lootFloatGap = 4,
	-- Percentages, because that is what the panel's opacity row speaks and a
	-- setting a player reads as 0 to 100 should be stored as what they read.
	lootFloatEnter = 0,
	lootFloatAlpha = 100,
	lootFloatSeconds = 0.5,
	lootFloatHold = 1,
	-- Two frames' worth of daylight at sixty. Enough that six drops read as six
	-- arrivals rather than one block appearing, and short enough that the last
	-- of them is still on screen while the first is.
	lootFloatStagger = 0.08,
	-- Five. A pull drops more than that and the column would be the screen; the
	-- oldest goes early to make room, which is the trade the client's own
	-- floating combat text makes and for the same reason.
	lootFloatMost = 5,
	lootFloatWidth = 380,
	lootFloatIcon = 50,
	-- How much of the picture is added back over itself. Additive drawing is
	-- what takes the black square off an item icon, and it lets the world
	-- through the dark parts of the object too, which reads as a picture with
	-- the colour drained out of it. A second additive pass puts the colour back
	-- without putting the square back, because nothing added to black is still
	-- black. A hundred is the picture twice over; nought is one pass and the
	-- washed-out look the blend leaves on its own.
	lootFloatLift = 60,
	lootFloatName = 20,
	lootFloatCount = 16,
}

local pool = {}
local lane

--------------------------------------------------------------------------

-- How tall a row is: whichever of the three things on it stands tallest.
--
-- Asked rather than stored, because a height beside an icon size is two
-- settings that have to agree, and the one somebody forgets to move is a
-- message written over the message under it. The lane is told this number for
-- every push and lays the column out by summing them, so a row that grows
-- pushes the ones below it down rather than through.
local function Height()
	local db = ns.db
	return math.max(db.lootFloatIcon, db.lootFloatName, db.lootFloatCount)
end

-- Every size on a row, put on it.
--
-- Run on every drop rather than at Build, because the frames are pooled: a row
-- built when the icon was fifty is handed back and comes out again after the
-- setting says thirty, and a pool that dressed its rows once would show both
-- sizes on screen at the same time. This is five calls on an event that fires
-- when something drops, not on a tick.
local function Dress(frame)
	local db = ns.db
	frame:SetSize(db.lootFloatWidth, Height())
	frame.icon:SetSize(db.lootFloatIcon, db.lootFloatIcon)
	-- The lane fades the row by setting the frame's alpha, and a texture's own
	-- alpha is multiplied by its frame's, so the second pass fades with the
	-- first rather than hanging on after it.
	frame.lift:SetAlpha(db.lootFloatLift / 100)
	frame.name:SetFontObject(UI.Font(db.lootFloatName, UI.SHADOW))
	frame.count:SetFontObject(UI.Font(db.lootFloatCount, UI.SHADOW))
end

local function Build()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:Hide()

	frame.icon = UI.Icon(frame)
	frame.icon:SetPoint("TOPLEFT")
	-- Added rather than blended, which is the only way a black background comes
	-- off an icon. An item icon is a painting on a dark square with no alpha
	-- channel in it at all, so there is nothing for the usual blend to make
	-- transparent and every drop crossed the world as a black tile. Additive
	-- blending multiplies nothing by the destination where the source is black,
	-- so the square goes and the object stays.
	frame.icon:SetBlendMode("ADD")

	-- The same picture again, added over the first, which is where the colour
	-- comes back. It is a texture of its own rather than a second SetTexture on
	-- the first, because a vertex colour cannot go above one and this is asking
	-- for more light than the file holds. Pinned to the icon so every size the
	-- settings hand it is followed, and additive as well, so the black it is
	-- carrying stays as transparent as the black underneath it.
	frame.lift = UI.Icon(frame, "OVERLAY")
	frame.lift:SetBlendMode("ADD")
	frame.lift:SetAllPoints(frame.icon)

	-- Shadowed, not flat and not outlined. Flat is for a string on a surface
	-- this addon painted and there is none here. Outlined is the role for text
	-- over the world and would be defensible at these sizes, where the rim no
	-- longer closes up Arial Narrow's own counters; a shadow is chosen anyway,
	-- because a rim reads as a health number over a mob and this is a caption
	-- that arrives and leaves.
	--
	-- The two sizes handed to UI.Label here are replaced by Dress before the
	-- frame is ever shown. They are read off the settings anyway rather than
	-- written as numbers, so that there is one answer to how big the name is
	-- and it is not in two places.
	frame.count = UI.Label(frame, ns.db.lootFloatCount, UI.Color.dim, "RIGHT", UI.SHADOW)
	frame.count:SetPoint("RIGHT")

	frame.name = UI.Label(frame, ns.db.lootFloatName, UI.Color.text, "LEFT", UI.SHADOW)
	frame.name:SetPoint("LEFT", frame.icon, "RIGHT", UI.Metric.gutter, 0)
	-- Up to the count rather than to the row's own edge. Both were pinned to
	-- the right edge and the count is drawn over the name, so a stack of eight
	-- linen put its own number through the last letters of the word.
	frame.name:SetPoint("RIGHT", frame.count, "LEFT", -UI.Metric.gutter, 0)
	return frame
end

-- Handed back by the lane when a message has finished. The frame is already
-- hidden; this is only the pool taking it.
local function Release(frame)
	pool[#pool + 1] = frame
end

--------------------------------------------------------------------------

function Floats.Defaults()
	local copy = {}
	for key, value in pairs(DEFAULTS) do
		copy[key] = value
	end
	return copy
end

-- The lane the settings currently describe.
--
-- Built here rather than held as a table this file edits in place, because the
-- lane copies the spec at the moment it is made and a table shared with it
-- would be a lane whose numbers half changed.
--
-- The two alphas are the only settings that are not the spec's own units: they
-- are stored as the percentages the panel row shows and the library wants a
-- fraction, so the division happens here, once, at the boundary.
local function Spec()
	local db = ns.db
	return {
		side = db.lootFloatSide,
		enterEdge = db.lootFloatEdge,
		restCentre = db.lootFloatRest,
		enterAlpha = db.lootFloatEnter / 100,
		restAlpha = db.lootFloatAlpha / 100,
		seconds = db.lootFloatSeconds,
		ttl = db.lootFloatHold,
		top = db.lootFloatTop,
		gap = db.lootFloatGap,
		stagger = db.lootFloatStagger,
		most = db.lootFloatMost,
		onGone = Release,
	}
end

-- A setting changed, so the next drop gets a lane that has heard about it.
--
-- Thrown away rather than written into. A lane resolves its spec once and then
-- owns rows, slots and a stagger clock that were worked out from those numbers,
-- so a field poked into a live one would leave a column laid out on the old gap
-- climbing to slots computed from the new one.
--
-- What is on screen when this runs is left alone and finishes on the old
-- numbers. Its rows come back to the pool the ordinary way, because the lane
-- hands them to Release, which is this file's and not that lane's. A message
-- yanked off the screen because a slider moved under it would be a worse answer
-- than one that plays out and is replaced by the next drop.
function Floats.Apply()
	lane = nil
end

-- One drop, on screen.
--
-- The quality colour is ns.UI.Quality, which is the same table the feed's rows
-- and the quest log's rewards read. Identity matters there and not here, but
-- two palettes for one fact is how one of them ends up wrong.
function Floats.Show(link, count)
	if not lane then
		lane = Float.Lane(Spec())
	end

	local frame = table.remove(pool) or Build()
	Dress(frame)
	local name, icon = ns.ItemInfo(link)
	local quality = ns.ItemValue(link)
	local color = UI.Quality[quality or 1] or UI.Quality[1]

	frame.icon:SetTexture(icon)
	frame.lift:SetTexture(icon)
	frame.name:SetText(name or link)
	frame.name:SetTextColor(color[1], color[2], color[3])
	-- Nothing at all for a single item. "x1" beside every drop is a column of
	-- ones you learn to stop reading, which is the state the number wanted to
	-- be noticed against.
	if count and count > 1 then
		frame.count:SetText("x" .. count)
	else
		frame.count:SetText("")
	end

	lane:Push(frame, Height())
	return frame
end

function Floats.OnLoot(text)
	if not ns.db.lootFloat or type(text) ~= "string" then
		return false
	end
	local who, link, count = ns.LootLine.Read(text)
	-- Yours only, and not a setting. The feed offers the group's drops because
	-- a column you scroll can hold them; six people's loot floating across the
	-- middle of the screen is the client's own loot spam with an animation on
	-- it.
	if who or not link then
		return false
	end
	Floats.Show(link, count)
	return true
end

-- How many are on screen, for the harness.
function Floats.Count()
	return lane and lane:Count() or 0
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_LOOT")
events:SetScript("OnEvent", function(_, _, text)
	Floats.OnLoot(text)
end)
