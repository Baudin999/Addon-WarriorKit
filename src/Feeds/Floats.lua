local ADDON, ns = ...

local UI = ns.UI
local Float = ns.Ck.Float

local Floats = {}
ns.Floats = Floats

--------------------------------------------------------------------------
-- Drops, floated
--
-- What you just picked up, sliding in from the right edge of the screen,
-- resting a moment beside the middle of it and fading. Several at once come in
-- one under the other, a beat apart, and climb when the one above them goes.
--
-- This is the first caller of ns.Ck.Float and it is deliberately the smallest
-- one that proves the library: it builds a row, hands it to a lane and takes it
-- back afterwards, and it does not know that anything moved.
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

-- One row, sized around the icon rather than around the text.
--
-- This is drawn over the world at arm's length from the thing that dropped it
-- and read in the second before it goes, which is a different job from a row in
-- a window you have opened and are looking at. So the picture is fifty pixels,
-- two and a half times what the loot feed's column draws, and the name is
-- twenty rather than the twelve every panel in the addon uses.
--
-- The width is what an item name fits in at that size with the icon beside it.
-- It is a fixed number and not a measurement, because the lane rests a message
-- by its far edge: a row that sized itself to the name in it would be a column
-- whose left edge moved with every drop.
local WIDTH, HEIGHT, ICON = 380, 50, 50

-- The name, and the count after it. Both well over anything else in the addon,
-- and neither is UI.Metric: those numbers are the size of a control in a window
-- and this is a caption on the world.
local NAME, COUNT = 20, 16

-- His numbers, and the reason each one is a number rather than a setting is
-- that nothing has asked for a second answer yet. They are the spec this was
-- built to: in from forty pixels inside the right edge, invisible, to forty
-- pixels short of the centre, solid, in half a second; a second on screen; a
-- hundred pixels down from the top.
local LANE = {
	side = "RIGHT",
	enterEdge = 40,
	restCentre = 40,
	enterAlpha = 0,
	restAlpha = 1,
	seconds = 0.5,
	ttl = 1,
	top = 100,
	gap = 4,
	-- Two frames' worth of daylight at sixty. Enough that six drops read as six
	-- arrivals rather than one block appearing, and short enough that the last
	-- of them is still on screen while the first is.
	stagger = 0.08,
	-- Five. A pull drops more than that and the column would be the screen; the
	-- oldest goes early to make room, which is the trade the client's own
	-- floating combat text makes and for the same reason.
	most = 5,
}

local pool = {}
local lane

--------------------------------------------------------------------------

local function Build()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:Hide()

	frame.icon = UI.Icon(frame)
	frame.icon:SetSize(ICON, ICON)
	frame.icon:SetPoint("TOPLEFT")

	-- Shadowed, not flat and not outlined. Flat is for a string on a surface
	-- this addon painted and there is none here. Outlined is the role for text
	-- over the world and would be defensible at these sizes, where the rim no
	-- longer closes up Arial Narrow's own counters; a shadow is chosen anyway,
	-- because a rim reads as a health number over a mob and this is a caption
	-- that arrives and leaves.
	frame.count = UI.Label(frame, COUNT, UI.Color.dim, "RIGHT", UI.SHADOW)
	frame.count:SetPoint("RIGHT")

	frame.name = UI.Label(frame, NAME, UI.Color.text, "LEFT", UI.SHADOW)
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
	return { lootFloat = true }
end

-- One drop, on screen.
--
-- The quality colour is ns.UI.Quality, which is the same table the feed's rows
-- and the quest log's rewards read. Identity matters there and not here, but
-- two palettes for one fact is how one of them ends up wrong.
function Floats.Show(link, count)
	if not lane then
		LANE.onGone = Release
		lane = Float.Lane(LANE)
	end

	local frame = table.remove(pool) or Build()
	local name, icon = ns.ItemInfo(link)
	local quality = ns.ItemValue(link)
	local color = UI.Quality[quality or 1] or UI.Quality[1]

	frame.icon:SetTexture(icon)
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

	lane:Push(frame, HEIGHT)
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
