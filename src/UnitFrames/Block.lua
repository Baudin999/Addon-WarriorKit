local ADDON, ns = ...

local Block = {}
ns.FrameBlock = Block

--------------------------------------------------------------------------
-- The block, and where it hangs
--
-- One square per unit frame: a portrait, a health gauge and a power gauge
-- inside one outline, with the frame underneath resized to it. Everything in
-- here is a rectangle. Nothing in here reads a unit, and the tick that paints
-- what it built is UnitFrames/Paint.lua.
--
-- The other two of the four rules in UnitFrames/Skin.lua's header are this
-- file's, and they are the two about geometry.
--
--   Fit the frame to the block, not the block to the frame. The block used
--   to hang off the portrait's own anchor inside a frame five times its size,
--   and everything that reads a unit frame's rectangle read that one: Edit
--   Mode selected it, snapped it against other frames and saved it, while
--   what you could see sat somewhere inside it, and the empty three quarters
--   went on eating clicks. So the block is anchored to the frame's own corner
--   now and the frame is sized to the block. What Edit Mode drags is what is
--   drawn, the hit region is the block, and target of target follows the
--   frame in rather than hanging where a 232 by 100 frame left it. The
--   frame's size is put back by `/wk skin off`, like every other change here.
--
--   Draw on the grid, measure off it. Everything this file creates goes on
--   the pixel grid in UI/Pixel.lua, so a size written here as 34 means 34
--   physical pixels and a hairline is one. Nothing the client owns can go
--   with it: the portrait and the two bars are regions of a secure unit
--   button and the addon must not scale, reparent or hide one of them. So
--   the boundary runs between what we made and what we borrowed, and every
--   number that crosses it is converted and snapped. What cannot cross is
--   position. The block sits on a corner of a frame that is not on the grid
--   and that Edit Mode positions in its own units, so where the whole block
--   lands is a fraction of a pixel no addon can read, exactly as a bar on a
--   nameplate is. The geometry is exact; the origin is Blizzard's.
--
-- Every function that writes on one of Blizzard's frames asks ns.Blocked
-- first, because these are secure unit buttons and combat forbids anchoring
-- or resizing one. A refusal is returned rather than raised, and the caller
-- carries it to the next PLAYER_REGEN_ENABLED.
--------------------------------------------------------------------------

-- How much of the gauge the health bar takes. The rest is power, less the
-- three hairlines: one along the top, one along the bottom, one between.
local HEALTH_SHARE = 0.70

-- The gap between the target block and target of target under it, in pixels.
-- Blizzard's own anchor for that frame was written against a 232 by 100
-- target frame and means nothing once the frame is the size of the block, so
-- this file places it and this is the whole of the placement.
--
-- A constant rather than the third pair of settings. The two blocks stand side
-- by side and the number between them is a corridor somebody wants to choose;
-- target of target is stacked under the target and reads as one unit with it,
-- and three pixels is the hairline that keeps two adjacent outlines from
-- reading as one thick edge. There is no second value anyone would type.
local TOT_GAP = 3

-- How far the target's top edge drops below the player's. The range one may
-- land in, shared with `/wk skin level` through Skin.LinkRange so the slash
-- command, the panel and a dropped drag all clamp to the same numbers.
--
-- There is no horizontal number beside it. The distance across is the mirror,
-- and the mirror is not a preference: the target's facing edge is the player's
-- reflected in the middle of the screen, so the corridor is twice the player's
-- distance from the centre and Edit Mode sets it by moving the player.
local LEVEL_LOW, LEVEL_HIGH = -100, 100

-- Below this many pixels tall a power bar cannot hold a readable number, so it
-- carries none. Target of target is the frame that hits it.
local VALUE_FLOOR = 9

-- The block's own geometry, in pixels, because everything this file draws is
-- on the grid. Three hairlines cross the square: one along the top of the
-- gauge, one along the bottom and one between the two bars.
local HAIRLINES = 3
local TEXT_PAD = 4

-- Font sizes are taken off the bar heights, because the same code draws a 34
-- pixel player frame and a 21 pixel target of target and one size cannot serve
-- both. These are the fraction of the bar a glyph gets and the range it is
-- allowed to land in.
local BIG_SHARE, BIG_MIN, BIG_MAX = 0.72, 8, 14
local SMALL_SHARE, SMALL_MIN, SMALL_MAX = 0.80, 7, 11

-- The look, and deliberately the enemy bars' look: the same flat fills, the
-- same hairline, no gloss, no gradient and no file path, so there is no art
-- asset that has to still exist on this client.
--
-- "Deliberately the enemy bars' look" used to be a comment and two copies of
-- the same nine literals. It is one table now. ns.Unit.Color is where every
-- colour the addon puts on a unit lives, and both files read it, so the two
-- cannot drift the way they were free to before.
local Color = ns.Unit.Color
local Gauge = ns.UI.Gauge

-- The state icons UnitFrames/Art.lua spared, which this file puts on the
-- corners of the portrait's square. Taken at load rather than per call: the
-- table is a constant over there and the two files have to agree about it.
local BADGES = ns.FrameArt.Badges()
local BARS = ns.FrameArt.Bars()

-- The stack panel the enemy bars are laid out with, which lays the block out.
local Flow = ns.UI.Flow

local BACKDROP = Color.backdrop
local NAME_TEXT = Color.text.name
local VALUE_TEXT = Color.text.value
local HEAL = Color.heal
local IDLE = Color.reaction.idle

-- What a spent track is until the first tick paints it its unit's colour.
-- ns.Fill defaulted to opaque black and ns.UI.Gauge.Underlay leaves a
-- texture uncoloured, so this is passed rather than dropped: the two paths
-- only differ on a styled frame whose unit does not exist, and a refactor
-- is the wrong place to decide that black was the wrong answer.
local BUILD_BLACK = { 0, 0, 0, 1 }

--------------------------------------------------------------------------
-- The boundary
--
-- On one side of it are the three frames this file creates per unit frame,
-- which are on the pixel grid and are counted in pixels. On the other are the
-- portrait, the two bars and the state icons, which are Blizzard's, are on
-- whatever scale the unit frame carries, and are counted in that frame's own
-- units. Two numbers cross the line, both of them outbound, because nothing
-- this file reads off the client decides a size any more.
--
-- ns.Pixel(frame) takes a length out: it is one physical pixel expressed in
-- that frame's units, so a size we want to be N pixels is written on one of
-- Blizzard's regions as N times that.
--
-- Fit() takes the whole block out. The block is the size the settings ask
-- for, in pixels, and the unit frame under it is given that same rectangle in
-- its own units, which is the one number in this file whose exactness is the
-- client's business rather than ours.
--------------------------------------------------------------------------

-- The frame's own geometry, taken before the first fit and put back by
-- Unstyle. Deliberately not the Snapshot table every region goes through:
-- that records anchors too, and the anchors on the player and target frames
-- belong to Edit Mode. Handing one of those back would drag a frame the user
-- moved while the skin was on to wherever it stood at login. The anchors are
-- kept all the same, because target of target is the one frame this file
-- re-anchors, and it is the only one ever given them back.
function Block.Remember(entry)
	if entry.frameShot then
		return
	end
	local frame, shot = entry.frame, {}
	pcall(function()
		shot.width, shot.height = frame:GetWidth(), frame:GetHeight()
		shot.points = {}
		for index = 1, frame:GetNumPoints() do
			shot.points[index] = { frame:GetPoint(index) }
		end
		-- The mouse region, which the fit zeroes so the whole block takes
		-- clicks. Recorded rather than assumed to be four zeroes: the client
		-- insets its own unit frames, and handing back zeroes would widen the
		-- target's hit region past anything it ever had.
		if frame.GetHitRectInsets then
			shot.insets = { frame:GetHitRectInsets() }
		end
	end)
	entry.frameShot = shot
end

-- The frame back on the anchors it carried before this file moved it.
--
-- Three callers now, which is why it is a function rather than the same six
-- lines three times: target of target coming off its perch, the target block
-- coming off the player block, and the whole skin coming off. A restore that
-- differed between those three would be a frame that lands somewhere new
-- depending on which switch you flipped.
--
-- A nil relativeTo means the parent, and SetPoint reads a nil there as
-- UIParent instead, which would fling the frame into the middle of the screen.
local function Replant(entry)
	local shot = entry.frameShot
	if not shot or not shot.points or #shot.points == 0 then
		return false
	end
	local frame = entry.frame
	frame:ClearAllPoints()
	for _, point in ipairs(shot.points) do
		frame:SetPoint(point[1], point[2] or frame:GetParent(),
			point[3], point[4], point[5])
	end
	return true
end

function Block.Restore(entry)
	local shot = entry.frameShot
	if not shot then
		return
	end
	local frame = entry.frame
	pcall(function()
		if shot.width and shot.width > 0 and shot.height and shot.height > 0 then
			frame:SetSize(shot.width, shot.height)
		end
		if entry.perched or entry.linked then
			Replant(entry)
		end
		if shot.insets and #shot.insets == 4 and frame.SetHitRectInsets then
			frame:SetHitRectInsets(shot.insets[1], shot.insets[2],
				shot.insets[3], shot.insets[4])
		end
	end)
	entry.frameShot = nil
	entry.perched, entry.linked = false, false
end

-- The unit frame, given the block's rectangle in the unit frame's own units.
--
-- Read back before it is written for the reason the tick reads a bar back:
-- this runs on every relayout and a SetSize is a resize of every anchor
-- underneath it, which on a unit frame is the cast bar.
--
-- It used to take a tail as well. The target frame was fitted to the block
-- plus the height the client lifts its own aura row by, so the client's
-- arithmetic dropped the icons under the block instead of inside the gauge.
-- UnitFrames/Auras.lua draws that row now and hides the client's, so all three
-- frames are the block exactly and there is one answer to where a row goes.
local function Fit(entry, width, height)
	local frame, box = entry.frame, entry.box
	local wide = ns.UI.Convert(width, box, frame)
	local tall = ns.UI.Convert(height, box, frame)
	if not wide or not tall or wide <= 0 or tall <= 0 then
		return
	end
	if frame:GetWidth() ~= wide or frame:GetHeight() ~= tall then
		frame:SetSize(wide, tall)
	end
	-- The mouse stops at the block, which is now the whole frame. Written
	-- rather than left alone: the client insets its own unit frames for art
	-- that is no longer there, and the recorded values go back on at
	-- Unstyle.
	if frame.SetHitRectInsets then
		frame:SetHitRectInsets(0, 0, 0, 0)
	end
end

-- Edit Mode draws its selection over the system it is dragging, and on this
-- client the box it drew was not the one on the screen. Pinned to the block
-- rather than to the frame. Those two are the same rectangle on all three now
-- that nothing is tailed, and pinning it is still worth doing: the selection is
-- what Edit Mode draws and it has to be what you can see, whatever a later
-- change does to the frame.
--
-- Every step is probed and nothing here exists on a client without Edit Mode,
-- where all three functions answer false and the skin is unchanged.
local function PinSelection(entry)
	local selection = entry.frame.Selection
	if type(selection) ~= "table" or type(selection.SetAllPoints) ~= "function" then
		return false
	end
	local ok = pcall(function()
		selection:ClearAllPoints()
		selection:SetAllPoints(entry.box or entry.frame)
	end)
	return ok
end

-- Edit Mode re-anchors its own selection whenever it puts one up, so pinning
-- it once at style time lasts until the next time the user opens Edit Mode.
-- The hook is the only piece of this file that cannot be taken off again,
-- which is why it does nothing at all while the skin is off.
local function HookSelection(entry)
	local frame = entry.frame
	if entry.hooked or type(frame.AnchorSelectionFrame) ~= "function"
		or type(hooksecurefunc) ~= "function" then
		return false
	end
	entry.hooked = pcall(hooksecurefunc, frame, "AnchorSelectionFrame", function()
		if entry.styled then
			PinSelection(entry)
		end
	end)
	return entry.hooked
end

-- A linked frame that swallows your drag is a bug report, so nothing here
-- refuses one. What this hooks is the drop, and Landed below turns where the
-- frame came to rest back into the two numbers.
--
-- Edit Mode drops a system by calling that frame's own OnDragStop, which is
-- how Blizzard's own system template carries it, so the method is post-hooked
-- where it exists and the script is hooked where it does not. Neither shape is
-- confirmed on this hybrid client and docs/README.md carries it in the
-- untested list with what would prove it.
--
-- Like the selection hook, this one cannot be taken off again, which is why it
-- does nothing at all unless the frame is linked at the moment of the drop.
local function HookDrag(entry, landed)
	local frame = entry.frame
	if entry.dragHooked or not entry.spec.beside then
		return false
	end
	local function drop()
		landed(entry)
	end
	if type(frame.OnDragStop) == "function" and type(hooksecurefunc) == "function" then
		entry.dragHooked = pcall(hooksecurefunc, frame, "OnDragStop", drop)
	elseif type(frame.HookScript) == "function" and frame:GetScript("OnDragStop") then
		entry.dragHooked = pcall(frame.HookScript, frame, "OnDragStop", drop)
	end
	return entry.dragHooked
end

--------------------------------------------------------------------------
-- The block we draw
--------------------------------------------------------------------------

-- The two textures this file draws inside Blizzard's own bars: the spent track
-- and the incoming heal slice. Both are regions of the client's bar rather than
-- of our rail beside it, and ns.UI.Gauge.Underlay carries the reason, which is
-- a bug this file shipped. The sublevels are ours to choose and are the two
-- lowest the client allows, which leaves the track under the slice and both
-- under the fill.
local TRACK_LAYER, SLICE_LAYER = -8, -7

-- One box, one divider, one text frame. It used to be two outlined boxes
-- pushed together, and two edges meeting down the middle is what made the
-- border read as furniture rather than as a frame. The portrait and the gauge
-- share one outline now with a single hairline between them, which is what the
-- enemy bars do with the mob tag for the same reason.
--
-- Three frame levels, and they are the whole z-order:
--
--   box  the unit frame's own level. Backdrop, edge and divider. It has to
--        stay at the parent's level because the portrait is a region of the
--        parent, and a box one level up would cover it.
--   bar  two levels up. Blizzard's health and power bars, carrying the two
--        spent tracks and the heal slice as regions of their own.
--   top  three levels up. Every piece of text, because font strings under a
--        status bar is exactly what the first version shipped.
function Block.Build(entry)
	local frame = entry.frame

	-- Ours, so all three go on the grid. SetIgnoreParentScale takes them off
	-- whatever scale the unit frame carries and a scale of 768 over the
	-- monitor's height makes one unit inside them one physical pixel, which is
	-- what lets every number in Place be a whole one. Blizzard's own regions
	-- cannot come with them: they are children of a secure unit button and
	-- rescaling one is both a protected action and a change to a frame the
	-- addon promised to hand back.
	--
	-- What the grid cannot fix here is where the block starts. It hangs off
	-- the portrait's anchor on a frame that is not on the grid, so the origin
	-- is a fraction of a pixel, the same way a bar on a nameplate takes its
	-- origin from wherever the mob is standing.
	--
	-- Adopt answers false on a client with no SetIgnoreParentScale, and
	-- nothing below cares: Place multiplies every constant by ns.Pixel, which
	-- is exactly 1 on the grid and the honest fraction off it.

	-- No textures of its own. It exists to hold the portrait's square, which
	-- is the one point on the block whose position the client decides.
	entry.slot = CreateFrame("Frame", nil, frame)
	entry.slot:EnableMouse(false)
	ns.UI.Adopt(entry.slot)

	entry.box = CreateFrame("Frame", entry.spec.global, frame)
	entry.box:EnableMouse(false)
	ns.UI.Adopt(entry.box)
	local backdrop = ns.Fill(entry.box, "BACKGROUND",
		BACKDROP[1], BACKDROP[2], BACKDROP[3], BACKDROP[4])
	backdrop:SetAllPoints()
	entry.box.edges = ns.Outline(entry.box, IDLE[1], IDLE[2], IDLE[3], 1)
	entry.divider = ns.Fill(entry.box, "BORDER", IDLE[1], IDLE[2], IDLE[3], 1)

	-- Two rails, one per bar, holding nothing but a rectangle of the right
	-- size. They are ours and they are on the grid, so their four corners are
	-- whole pixels; Blizzard's bars are then pinned to them corner to corner
	-- rather than given a size, and an anchor is resolved on the screen rather
	-- than in either frame's units. That is the whole trick: a bar whose
	-- geometry is exact without the bar ever leaving Blizzard's scale, and
	-- without a height that has to be converted and rounded to get there.
	entry.healthRail = CreateFrame("Frame", nil, entry.box)
	entry.healthRail:EnableMouse(false)
	entry.powerRail = CreateFrame("Frame", nil, entry.box)
	entry.powerRail:EnableMouse(false)

	-- The spent part of each bar, in the bar's own hue at a fifth of the
	-- brightness, so a unit at ten percent still reads as itself rather than
	-- as an empty box. Filling the bar, so it is placed once here rather than
	-- re-anchored on every relayout.
	entry.healthTrack = Gauge.Underlay(entry.healthbar, TRACK_LAYER, BUILD_BLACK)
	entry.powerTrack = Gauge.Underlay(entry.manabar, TRACK_LAYER, BUILD_BLACK)

	-- The incoming heal, between the track and the fill, on the sublevel
	-- between them. That ordering is the clamp doing itself a favour: a heal
	-- that overruns what is missing is covered by the fill rather than drawn
	-- past it, and the arithmetic below only has to be right, not defensive.
	--
	-- Anchored nowhere yet. Where it starts is where the fill stops, and that
	-- is a region the client owns and may hand back a different object for, so
	-- HealSlice pins it on the first tick and re-pins it if the object moves.
	entry.healSlice = Gauge.Underlay(entry.healthbar, SLICE_LAYER, HEAL)
	entry.healSlice:ClearAllPoints()
	entry.healSlice:Hide()

	entry.top = CreateFrame("Frame", nil, frame)
	entry.top:EnableMouse(false)
	ns.UI.Adopt(entry.top)

	-- One shared font object per size rather than a font on each string. Place
	-- picks the real size off the bar heights a moment later; these are only
	-- what the strings carry until it does.
	entry.nameText = ns.UI.Label(entry.top, BIG_MAX, NAME_TEXT, "LEFT", ns.UI.FLAT)
	entry.healthText = ns.UI.Label(entry.top, BIG_MAX, VALUE_TEXT, "RIGHT", ns.UI.FLAT)
	entry.levelText = ns.UI.Label(entry.top, SMALL_MAX, VALUE_TEXT, "LEFT", ns.UI.FLAT)
	entry.powerText = ns.UI.Label(entry.top, SMALL_MAX, VALUE_TEXT, "RIGHT", ns.UI.FLAT)

	-- The target's own aura rows, on the frames that have them. They are
	-- children of the unit frame like the three above, so they hide with it,
	-- and everything else about them is UnitFrames/Auras.lua's.
	ns.FrameAuras.Build(entry)
end

-- Sized off the two settings, placed on the frame's own corner, and the frame
-- resized to what came out.
--
-- The corner is the one the portrait is on, which is the left of the player
-- frame and the right of the target frame, so the block grows away from it in
-- opposite directions on the two. Nothing is measured off Blizzard's layout any
-- more. The block used to hang on the portrait's own anchor and be clamped to
-- the room the frame had left, which put the drawn rectangle somewhere inside a
-- much bigger invisible one; the frame is the drawn rectangle now, so there is
-- no room to be left and nothing to clamp against. What is inside the block
-- used to be SetPoint arithmetic with the mirror's sign threaded through every
-- offset in it, and is a tree handed to ns.UI.Flow now.
function Block.Place(entry)
	local spec, frame = entry.spec, entry.frame

	-- Every number below this line is a whole count of physical pixels, and px is
	-- what turns one into the units the block is drawn in. On the grid px is
	-- exactly 1 and every multiply is free. Off it, on a client with no
	-- SetIgnoreParentScale, it is the fraction that keeps the block the same
	-- physical size and its hairlines one pixel wide.
	local px = ns.Pixel(entry.box)
	-- And this is one pixel in Blizzard's units, for the handful of sizes and
	-- offsets that get written onto a region of theirs rather than one of ours.
	local theirs = ns.Pixel(frame)

	local side = math.max(math.floor(ns.db.skinHeight * spec.scale + 0.5), 16)
	local width = math.max(math.floor(ns.db.skinWidth * spec.scale + 0.5), 60)

	-- LEFT is the side the portrait is on, RIGHT the side the gauge runs to, and
	-- pull is the sign that turns an inset into an offset on whichever edge that
	-- leaves. What is left for them is what Flow cannot place: the block's corner
	-- on Blizzard's frame, four badges of theirs on the square, and four strings
	-- of ours as wide as whatever the unit happens to be called.
	local portraitEdge = spec.mirror and "RIGHT" or "LEFT"
	local gaugeEdge = spec.mirror and "LEFT" or "RIGHT"
	local pull = spec.mirror and 1 or -1

	-- The block first, on the frame's corner, then the frame given the block's
	-- rectangle. In that order: the fit converts the block's size out of the grid
	-- into the frame's units, and a block not yet sized hands it last tick's.
	entry.box:ClearAllPoints()
	entry.box:SetPoint("TOP" .. portraitEdge, frame, "TOP" .. portraitEdge, 0, 0)
	entry.box:SetSize((side + width) * px, side * px)
	entry.box:SetFrameLevel(frame:GetFrameLevel())
	ns.EdgeSize(entry.box.edges, px)

	Fit(entry, (side + width) * px, side * px)
	PinSelection(entry)

	-- The z-order Build's note sets out, rewritten on every relayout.
	entry.top:ClearAllPoints()
	entry.top:SetAllPoints(entry.box)
	entry.top:SetFrameLevel(frame:GetFrameLevel() + 3)
	entry.slot:SetFrameLevel(frame:GetFrameLevel())
	entry.healthRail:SetFrameLevel(entry.box:GetFrameLevel() + 1)
	entry.powerRail:SetFrameLevel(entry.box:GetFrameLevel() + 1)

	-- Whole pixels, because the two bars have to add up to the square exactly:
	-- health plus power plus the three hairlines is the side, and a fractional
	-- share leaves a seam along one of them that reads as a rendering fault.
	local inner = side - HAIRLINES
	local health = math.floor(inner * HEALTH_SHARE)
	local power = inner - health

	-- The whole inside of the block, in one row of three: the portrait's square,
	-- the gauge, and one pixel of nothing on the far edge for the box's own
	-- outline to draw into. The divider is the square's inner column rather than
	-- a cell of its own, so the square and the gauge read as one strip with a
	-- hairline down it rather than as two boxes that happen to touch.
	--
	-- `reverse` is the whole of the mirroring: it runs the row backwards, so the
	-- target's three cells land the other way round with no sign anywhere here.
	--
	-- Every node holding a frame stretches across the axis it is not sized on. A
	-- node with neither a size nor a stretch measures zero and is handed one
	-- pixel, which is what shipped on the enemy bars' gauge and stood until
	-- somebody measured it. Both rails are measured in the harness now.
	--
	-- A rail carries no texture, only the rectangle its bar is pinned to. It used
	-- to hold the spent track, which made the gauge depend on an order between
	-- two frames the client did not keep: see the note on Underlay.
	Flow.Arrange(entry.box, {
		direction = "row", reverse = spec.mirror, align = "stretch",
		width = (side + width) * px, height = side * px,
		{ frame = entry.slot, width = side * px, align = "stretch",
			direction = "row", reverse = spec.mirror, pad = { 0, px, 0, px },
			{ grow = 1 }, { frame = entry.divider, width = px } },
		{ direction = "column", grow = 1, gap = px, align = "stretch",
			pad = { 0, px, 0, px },
			{ frame = entry.healthRail, height = health * px },
			{ frame = entry.powerRail, height = power * px } },
		{ width = px },
	})

	if entry.portrait then
		-- Inset by one pixel written in Blizzard's units, because a SetPoint
		-- offset is measured in the units of the region being placed and the
		-- portrait is theirs. The corner it is inset from is ours and is on a
		-- pixel boundary, so the square the render lands in is exact.
		entry.portrait:ClearAllPoints()
		entry.portrait:SetPoint("TOPLEFT", entry.slot, "TOPLEFT", theirs, -theirs)
		entry.portrait:SetPoint("BOTTOMRIGHT", entry.slot, "BOTTOMRIGHT", -theirs, theirs)
		-- Above everything the box draws, because the box sits at the same
		-- frame level as the frame this portrait is a region of.
		entry.portrait:SetDrawLayer("OVERLAY")
	end

	-- What the tick needs to draw an incoming heal, worked out here because all
	-- three answers change with the layout and none of them changes between two
	-- ticks. The width a heal is a fraction of is read back off the rail Flow
	-- just sized rather than derived from the settings again, so one thing
	-- decides how wide the gauge is and not two.
	entry.railPixels = math.max(math.floor(entry.healthRail:GetWidth() / px + 0.5), 1)
	-- One pixel in the units the slice is drawn in, which are the bar's and no
	-- longer the block's: the slice is a region of Blizzard's health bar now,
	-- so a width written on it crosses the boundary like every other number
	-- that lands on something of theirs.
	entry.pixel = theirs
	-- Which end of the bar the fill stops at. This file mirrors the target
	-- frame and Blizzard does not mirror the bar inside it, so the two disagree
	-- on which side is which and the bar is the one that is right. Asked rather
	-- than assumed, because a slice drawn off the wrong end of the fill is not
	-- a pixel out, it is on the wrong side of the number it is describing.
	local healthbar = entry.healthbar
	entry.healReverse = (healthbar and healthbar.GetReverseFill
		and healthbar:GetReverseFill()) or false
	-- The tick guards every write on the width it last drew, and that width is
	-- now a different number of pixels. Forgetting it here is what makes a
	-- resolution change leave a slice at the old scale until the heal changes.
	entry.healSpan = nil
	entry.healAnchor = nil

	-- Blizzard's bars take the rails corner to corner. No size is written on
	-- either one, so nothing about them has to be converted or rounded: the
	-- client resolves an anchor on the screen, and the corners it is resolving
	-- to are ours and are whole pixels.
	for index, key in ipairs(BARS) do
		entry[key]:SetFrameLevel(entry.box:GetFrameLevel() + 2)
		entry[key]:ClearAllPoints()
		entry[key]:SetAllPoints(index == 1 and entry.healthRail or entry.powerRail)
	end

	-- Sized off the block, because the same code draws a 34 pixel player frame
	-- and a 21 pixel target of target. One shared object per size; UI/Text.lua
	-- says why. Not rounded: `big` is a whole count of pixels and `px` is what
	-- one costs in units, so `big * px` is already exact and the round that sat
	-- here undid it. Shadowed, not outlined: all four sit on an opaque bar.
	local big = math.min(math.max(math.floor(health * BIG_SHARE), BIG_MIN), BIG_MAX)
	local small = math.min(math.max(math.floor(power * SMALL_SHARE), SMALL_MIN), SMALL_MAX)
	local bigFont = ns.UI.Font(big * px, ns.UI.FLAT)
	local smallFont = ns.UI.Font(small * px, ns.UI.FLAT)

	entry.nameText:SetFontObject(bigFont)
	entry.healthText:SetFontObject(bigFont)
	entry.levelText:SetFontObject(smallFont)
	entry.powerText:SetFontObject(smallFont)

	-- Floored to a whole pixel rather than left on the bar's exact centre.
	-- Half of an odd bar is half a pixel, and a glyph asked for at half a pixel
	-- is rasterised across two, which is what makes small outlined text look
	-- like it has been breathed on.
	local pad = TEXT_PAD * px
	local healthMid = -(1 + math.floor(health / 2)) * px
	local powerMid = -(2 + health + math.floor(power / 2)) * px

	-- Anchored to the square's inner corner rather than to its side, because a
	-- side point sits at half height and the vertical offsets here are all
	-- measured down from the top of the block.
	entry.healthText:ClearAllPoints()
	entry.healthText:SetPoint(gaugeEdge, entry.box, "TOP" .. gaugeEdge, pull * pad, healthMid)

	entry.nameText:ClearAllPoints()
	entry.nameText:SetPoint(portraitEdge, entry.slot, "TOP" .. gaugeEdge, -pull * pad, healthMid)
	entry.nameText:SetPoint(gaugeEdge, entry.healthText, portraitEdge, pull * pad, 0)

	-- The level goes on the power bar's inner end, which is empty on every
	-- unit in the game, and the power number on its outer end.
	entry.levelText:ClearAllPoints()
	entry.levelText:SetPoint(portraitEdge, entry.slot, "TOP" .. gaugeEdge, -pull * pad, powerMid)

	entry.powerText:ClearAllPoints()
	entry.powerText:SetPoint(gaugeEdge, entry.box, "TOP" .. gaugeEdge, pull * pad, powerMid)
	entry.powerText:SetShown(power >= VALUE_FLOOR)

	-- On the outer corners of the square, the two the gauge is not against,
	-- each centred on its corner so it half overhangs the block. Lifted to
	-- OVERLAY for the portrait's reason: the box sits at the same frame level
	-- as the frame these are regions of.
	--
	-- An even number of pixels, because the badge is centred on a corner and
	-- half of an odd one puts all four of its edges on a half pixel. The size
	-- is written in Blizzard's units, since the region is theirs.
	for _, badge in ipairs(BADGES) do
		local region = entry.badges[badge.slot]
		if region then
			local size = math.floor(side * badge.scale / 2 + 0.5) * 2 * theirs
			region:ClearAllPoints()
			region:SetSize(size, size)
			region:SetPoint("CENTER", entry.slot, badge.corner .. portraitEdge, 0, 0)
			region:SetDrawLayer("OVERLAY")
		end
	end

	-- Last, because a row wraps against the block's width and the block has
	-- only just been given one.
	ns.FrameAuras.Place(entry, px, (side + width) * px, spec.mirror)
end

--------------------------------------------------------------------------
-- The chain
--
-- Edit Mode positions the player block and nothing else. The target block
-- hangs off the player block and target of target hangs off the target block,
-- so the three are one HUD and Edit Mode keeps the one job it is good at.
--
-- That is the only division available rather than a compromise. Edit Mode
-- stores an absolute point per system and writes it back, and has no notion of
-- one system anchored to another, so anything relational is this addon's by
-- definition and the only real question is how much absolute positioning is
-- left with it. One anchor is the right amount: dragging, snapping, switching
-- layouts and storing them per character all go on working and none of it is
-- written here.
--
-- One anchor per link, written out of combat behind the same lockdown guard as
-- the rest of Place, and the client maintains it from there. Nothing runs on a
-- tick, nothing resyncs after a drag and nothing polls GetPoint.
--------------------------------------------------------------------------

-- Which edge of each block faces the other.
--
-- Read off spec.mirror rather than written out. The mirror is what puts the
-- player's gauge end on its right edge and the target's on its left, so
-- linking the two gauge ends is what faces the gauges across the gap and turns
-- both portraits outward, and a frame that stops being mirrored takes its side
-- of the link with it rather than leaving a constant here to be found later.
--
-- It used to return a third value, the direction the second block reached in
-- to cover a gap somebody typed. Reflection has no direction to choose: the
-- reflected edge lands on whichever side of the centre the player is not.
local function Facing(host, entry)
	return entry.spec.mirror and "LEFT" or "RIGHT",
		host.spec.mirror and "LEFT" or "RIGHT"
end

-- One edge of a frame in screen units, which is the only space two frames on
-- different scales share. Nil where the client will not answer, which is a
-- frame whose position has not resolved yet, and the caller draws nothing out
-- of a nil rather than deriving a number from one.
local function ScreenEdge(frame, getter)
	local value = ns.Measure(frame, getter)
	local scale = ns.Measure(frame, "GetEffectiveScale")
	if not value or not scale then
		return nil
	end
	return value * scale
end

local function Snap(value, low, high)
	return math.max(low, math.min(high, math.floor(value + 0.5)))
end

-- The host's facing edge reflected in the middle of the screen, as an offset
-- from that edge in the units SetPoint takes.
--
-- Reflecting a point about the centre moves it 2 * (centre - point). Both
-- terms are read in screen units, because that is the only space two frames on
-- different scales share, and the result is divided back into the frame's own
-- units because that is what an anchor offset counts in.
--
-- Nil where the client has not resolved a position yet. There is nothing to
-- fall back to and that is deliberate: the caller leaves the target on the
-- point it already has and asks again on the next pass, which is the frame
-- staying where Edit Mode put it rather than jumping to an invented distance
-- and then jumping again once the host answers.
local function Mirrored(frame, block, theirs)
	local edge = ScreenEdge(block, theirs == "LEFT" and "GetLeft" or "GetRight")
	local width = ns.Measure(UIParent, "GetWidth")
	local screen = ns.Measure(UIParent, "GetEffectiveScale")
	local scale = ns.Measure(frame, "GetEffectiveScale")
	if not edge or not width or not screen or not scale or scale <= 0 then
		return nil
	end
	return 2 * (width * screen / 2 - edge) / scale
end

-- The target block on the player block's far side.
--
-- Across, it is the player's facing edge reflected in the middle of the
-- screen. Down, it is the level setting in screen pixels, snapped, the same
-- ruler `/wk skin height` and `/wk skin width` are on. Where the pair lands on
-- screen is still a fraction of a pixel nobody can read, because the player
-- frame's origin is Blizzard's and this file only decides where the target
-- goes given it. That is the boundary the header already draws round the
-- block, unchanged.
--
-- Both frames have to be skinned. Unskinned, TargetFrame is 232 by 100 and a
-- distance measured off its edge is a distance to the edge of a rectangle
-- three quarters of which is empty, so the link waits and Skin.DescribeLink
-- says why.
--
-- Written on every pass rather than only when the switch moves, because three
-- things change the numbers without changing the state: the player moving,
-- the level setting, and a resolution change that moves what one pixel costs
-- in this frame's units.
function Block.Link(entry, host)
	if not host then
		return true
	end
	local want = (ns.db.skinLink and entry.styled and host.styled) and true or false
	if not want and not entry.linked then
		return true
	end
	if ns.Blocked(entry.frame) then
		return false
	end
	local frame = entry.frame
	if want then
		Block.Remember(entry)
		local px = ns.Pixel(frame)
		local mine, theirs = Facing(host, entry)
		local block = host.box or host.frame
		-- On the host's block rather than the host's frame, for the reason the
		-- perch below is: those two are the same rectangle on the player and
		-- are not on the target, and the block is the one you can see.
		--
		-- The target's facing edge is the host's facing edge reflected in the
		-- middle of the screen, so the mirror line is the middle of the screen
		-- wherever Edit Mode left the player. Anchoring the two blocks a fixed
		-- distance apart put that line wherever the player happened to be,
		-- which is two frames facing each other rather than a mirror.
		--
		-- Reflecting a point about the centre puts it 2 * (centre - point)
		-- away from itself, and both terms are read in screen units because
		-- that is the only space two frames on different scales share.
		--
		-- Measured before the frame is unpinned, so a host that cannot answer
		-- yet leaves the target on the point it arrived with.
		local across = Mirrored(frame, block, theirs)
		if not across then
			return false
		end
		frame:ClearAllPoints()
		frame:SetPoint("TOP" .. mine, block, "TOP" .. theirs,
			across, -ns.db.skinLevel * px)
		entry.linked = true
	else
		Replant(entry)
		entry.linked = false
	end
	return true
end

-- Where the drag put it, read back as the level.
--
-- The level is how far the target's top edge sits below the player's, in
-- screen pixels, snapped and clamped to the range the slash command takes.
-- Then the anchor is written again, so the next relayout puts the frame where
-- the drag left it rather than where the setting used to say. The drag still
-- means something, and it teaches the number without a slash command.
--
-- Only the vertical half of the drop is kept, and that is the design rather
-- than a loss. The horizontal is the mirror, so the only place the target can
-- land is opposite wherever the player is; a drag that pulled it sideways is
-- answered by putting it straight back, which is what Link does below.
function Block.Landed(entry, host)
	if not host or not entry.linked or ns.Blocked(entry.frame) then
		return false
	end
	local frame, block = entry.frame, host.box or host.frame
	local ourTop, theirTop = ScreenEdge(frame, "GetTop"), ScreenEdge(block, "GetTop")
	-- One screen pixel in the units those two edges came back in, which is
	-- what turns a distance on the screen into the count a person types.
	local pixel = ns.Pixel(frame) * (ns.Measure(frame, "GetEffectiveScale") or 0)
	if not ourTop or not theirTop or pixel <= 0 then
		return false
	end
	ns.db.skinLevel = Snap((theirTop - ourTop) / pixel, LEVEL_LOW, LEVEL_HIGH)
	return Block.Link(entry, host)
end

-- Target of target, parked under the target block.
--
-- It has to be placed by this file once the target frame is fitted, and only
-- then. Blizzard anchored that frame against a target frame 100 units tall,
-- so the moment the target frame is the height of the block instead, its own
-- anchor points at a corner that has moved and it lands across whatever is
-- there. Anchored by the edge the two blocks share rather than by the
-- portrait's: the target is mirrored and target of target is not, so aligning
-- their outer edges is what puts one portrait under the other.
--
-- Both halves are conditional on the target being fitted, because a target
-- frame that is back at Blizzard's size wants Blizzard's anchor back with it.
--
-- Written on every pass rather than only when the switch moves, for Link's
-- third reason: TOT_GAP is three pixels and what three pixels cost in this
-- frame's units moves with the screen. Skipping a pass that changed nothing
-- else is what left this frame three pixels of the old grid under the block
-- after a monitor swap.
function Block.Perch(entry, host)
	if not host then
		return true
	end
	local want = entry.styled and host.styled and true or false
	if not want and not entry.perched then
		return true
	end
	if ns.Blocked(entry.frame) then
		return false
	end
	local frame = entry.frame
	if want then
		Block.Remember(entry)
		local edge = "TOP" .. (host.spec.mirror and "RIGHT" or "LEFT")
		local corner = "BOTTOM" .. (host.spec.mirror and "RIGHT" or "LEFT")
		frame:ClearAllPoints()
		-- Under the block rather than under the frame. Those two are the same
		-- bottom edge now that nothing tails the target, and the block is
		-- still the right thing to name: it is the rectangle this file draws
		-- and the one every other measurement here is taken in.
		frame:SetPoint(edge, host.box or host.frame, corner, 0, -TOT_GAP * ns.Pixel(frame))
		entry.perched = true
	else
		Replant(entry)
		entry.perched = false
	end
	-- What the host's aura rows now hang from. This frame is parked on exactly
	-- the corner they hang off, so without being told, the first row would be
	-- drawn on top of it. Told rather than worked out over there, because
	-- whether this frame is under that block is this function's answer and
	-- nobody else's.
	ns.FrameAuras.Under(host, entry.perched and frame or nil)
	return true
end

-- Whether that frame is on the screen at all.
--
-- Its size, its anchor, its artwork, its colours and its four numbers are all
-- this addon's. Whether it appears was the one thing left with the client, and
-- the client decides it inside a mixin method, behind a CVar and three tests on
-- the host unit, none of which this addon can see or reach. A frame the skin
-- has taken over that far cannot have its visibility owned somewhere else, so
-- this is the rule UnitFrames/Blizzard.lua states for the frames it takes down,
-- applied to the one frame here that goes up and down on its own: read what is
-- actually on the screen every pass and put back what moved.
--
-- The test is Blizzard's own with the CVar dropped, and its four terms are the
-- whole of when a target's target means anything: the host has a unit, that
-- unit has a target, the host is not you, and the host is alive. Not one of
-- them asks what the unit is, which is why it holds the same for a mob, an NPC
-- and a player of either faction.
--
-- Nothing here fights the client. Blizzard's own driver compares that frame's
-- shown flag against UnitExists on the same unit and only acts on a
-- disagreement, so a frame this put up is a frame it leaves alone.
--
-- Showing a secure unit button is a protected action, so a change combat
-- refuses is carried to PLAYER_REGEN_ENABLED like every other one in this file.
-- The client's own show and hide are secure and go on working through a fight,
-- which is what covers the frame that first needs to go up mid pull.
--
-- Nothing puts this back at Unstyle, and that is deliberate rather than a gap:
-- the client's driver reads the frame's own flag, so the first pass after the
-- skin comes off finds whatever state it was left in and corrects it.
function Block.Reveal(entry, host)
	if not host or not entry.styled or not host.styled then
		return true
	end
	local theirs = host.spec.unit
	local want = (UnitExists(theirs) and UnitExists(entry.spec.unit)
		and not UnitIsUnit("player", theirs)
		and (UnitHealth(theirs) or 0) > 0) and true or false
	local frame = entry.frame
	if (frame:IsShown() and true or false) == want then
		return true
	end
	if ns.Blocked(frame) then
		return false
	end
	frame:SetShown(want) -- unguarded: the return above compares shown against want
	return true
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

-- The three frames this file drew, up or down with the skin.
--
-- The two tracks are regions of Blizzard's bars rather than of the box, so
-- hiding the box no longer takes them with it and showing it does not bring
-- them back. The slice stays hidden until the tick has a heal to draw, which
-- Place has just told it to work out again.
function Block.Show(entry)
	entry.box:Show()
	entry.top:Show()
	entry.healthTrack:Show()
	entry.powerTrack:Show()
end

function Block.Hide(entry)
	if not entry.box then
		return
	end
	entry.box:Hide()
	entry.top:Hide()
	entry.healthTrack:Hide()
	entry.powerTrack:Hide()
	entry.healSlice:Hide()
end

-- Both hooks, in one call, because Style has no reason to know there are two.
-- Neither can be taken off again, which is why each does nothing at all unless
-- the skin is on at the moment it fires. `dropped` is what Edit Mode's drop
-- calls, and only the file that owns the entry list can answer what a drop
-- means, so it is handed in.
function Block.Hook(entry, dropped)
	HookSelection(entry)
	HookDrag(entry, dropped)
end

-- What a level is allowed to be, so the slash command, the panel's stepper and
-- the clamp a dropped drag goes through are all reading one range.
function Block.Range()
	return LEVEL_LOW, LEVEL_HIGH
end

-- The fit, which is the line to read when Edit Mode's box is not the block.
-- What the frame was before the skin touched it, and whether this client put
-- an Edit Mode selection on it for the skin to pin: a client with none is one
-- where the fit is the whole of the answer.
function Block.Probe(entry)
	local shot = entry.frameShot
	local was = shot and shot.width and shot.width > 0
		and ("was %dx%d, "):format(shot.width, shot.height) or ""
	-- The rows this addon draws under the block, where it draws any. What the
	-- client would have hung there is hidden, and how much of it has been
	-- caught so far is part of the same line.
	local row = ns.FrameAuras.Probe(entry)
	row = row and (", " .. row) or ""
	-- Whether the client is drawing that frame at all, which is the line to
	-- read when the block is measured, placed and painted and still nobody can
	-- see it. Only said for the frame whose visibility this file owns; the
	-- other two go down with the unit and there is nothing to report.
	local drawn = entry.spec.under and
		(entry.frame:IsShown() and ", on screen" or ", not drawn") or ""
	return ("%sedit mode selection %s%s%s%s%s"):format(was,
		type(entry.frame.Selection) == "table" and "pinned to the block"
			or "not on this client",
		entry.perched and (", parked under the " .. entry.spec.under) or "",
		entry.linked and (", hung off the " .. entry.spec.beside .. " block") or "",
		drawn, row)
end
