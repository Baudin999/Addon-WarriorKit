local ADDON, ns = ...

local Block = {}
ns.FrameBlock = Block

--------------------------------------------------------------------------
-- The block, and where it hangs
--
-- One square per unit frame: a portrait, a health gauge and a power gauge
-- inside one outline, drawn on a secure unit button this addon made. Everything
-- in here is a rectangle. Nothing in here reads a unit, and the tick that
-- paints what it built is UnitFrames/Paint.lua.
--
-- Every frame here is ours. It used to be a block drawn over Blizzard's own
-- PlayerFrame, with the client's portrait and bars pinned to rails of ours and
-- every number that crossed between the two scales converted and snapped, and
-- the file's header spent a page on that boundary. The boundary is gone. The
-- button, the portrait, the two bars, the four strings and the badges are all
-- created below, all on the pixel grid in UI/Pixel.lua, so a size written here
-- as 34 means 34 physical pixels, a hairline is one, and where the whole block
-- lands is a whole pixel too, because the frame it hangs off is ours as well.
--
-- Two frames per unit, and the split is the one UnitFrames/Group.lua makes.
-- The anchor is a plain frame that UI.Placeable drags and the settings remember;
-- the button is the secure unit button inside it, which carries the click, the
-- menu and the unit watch. A secure button cannot be moved by an addon in
-- combat, and neither can its parent, so everything below that writes a point
-- or a size asks ns.Blocked on the button first and hands a refusal back to
-- UnitFrames/Skin.lua, which carries it to the next PLAYER_REGEN_ENABLED.
--------------------------------------------------------------------------

-- How much of the gauge the health bar takes. The rest is power, less the
-- three hairlines: one along the top, one along the bottom, one between.
local HEALTH_SHARE = 0.70

-- The gap between the target block and target of target under it, in pixels.
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
-- distance from the centre and dragging the player sets it.
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

-- The portrait render carries dead space around the head. Blizzard hides it
-- under the ring; with no ring it is cropped instead.
--
-- Written as a fraction of 64 rather than as a decimal, for the reason
-- UI/Draw.lua crops an icon at 5/64: a portrait is sampled art, and a crop
-- that lands between two texels makes the sampler interpolate across the whole
-- image to find the edge. 0.15 cut 9.6 texels. Ten is the nearest boundary.
local PORTRAIT_TRIM = 10 / 64

-- The look, and deliberately the enemy bars' look: the same flat fills, the
-- same hairline, no gloss, no gradient. ns.Unit.Color is where every colour the
-- addon puts on a unit lives, and both files read it, so the two cannot drift.
local Color = ns.Unit.Color
local Gauge = ns.UI.Gauge
local Flow = ns.UI.Flow

local BACKDROP = Color.backdrop
local NAME_TEXT = Color.text.name
local VALUE_TEXT = Color.text.value
local HEAL = Color.heal
local IDLE = Color.reaction.idle

-- The two textures under each bar's fill: the spent track and the incoming
-- heal slice. Both are regions of the bar, on the two lowest sublevels the
-- client allows, which leaves the track under the slice and both under the
-- fill. That ordering is the heal clamp doing itself a favour: a slice that
-- overran what is missing would be covered by the fill rather than drawn past
-- it, so the arithmetic in Paint only has to be right, not defensive.
local TRACK_LAYER, SLICE_LAYER = -8, -7

-- The state icons on the corners of the portrait's square, each centred on its
-- corner so it half overhangs the block. Which of the three a frame carries is
-- the spec's, in UnitFrames/Skin.lua; what each one is drawn from is here, and
-- what it says is UnitFrames/Paint.lua's.
--
-- The marker and the state share a corner on purpose, and no frame carries
-- both: Blizzard draws no raid marker on your own frame and no rest or combat
-- icon on anyone else's. The PvP flag is bigger, because that texture carries a
-- wide transparent margin and renders visibly smaller than the box it is given.
--
--   marker  the raid target icon, one of eight out of one sheet, which
--           SetRaidTargetIconTexture crops on the tick
--   state   resting or fighting, two cells of one sheet, which Paint crops
--   pvp     the faction's flag, a sheet of its own per faction, set on the tick
local BADGES = {
	marker = { corner = "TOP", scale = 0.55,
		art = "Interface\\TargetingFrame\\UI-RaidTargetingIcons" },
	state = { corner = "TOP", scale = 0.55,
		art = "Interface\\CharacterFrame\\UI-StateIcon" },
	pvp = { corner = "BOTTOM", scale = 0.72 },
}

--------------------------------------------------------------------------
-- The block we draw
--------------------------------------------------------------------------

-- One bar of ours, with its spent track on the sublevel the heal slice sits
-- over. Gauge.New leaves the track on the layer's default sublevel, which is
-- above the slice's, and a track drawn over the slice is a heal nobody can see.
--
-- The fill runs from the portrait outward on both blocks. The target block is
-- mirrored and a bar that filled left to right on it would drain toward the
-- portrait, which is the one direction that reads backwards. Probed, because
-- the older client this addon also loads on may not carry the call, and a bar
-- that fills the usual way is a look and not a fault.
local function Bar(entry)
	local bar = Gauge.New(entry.frame)
	bar:EnableMouse(false)
	if bar.track.SetDrawLayer then
		bar.track:SetDrawLayer("BACKGROUND", TRACK_LAYER)
	end
	if entry.spec.mirror and type(bar.SetReverseFill) == "function" then
		bar:SetReverseFill(true)
	end
	return bar
end

-- Three frame levels, and they are the whole z-order:
--
--   button  the secure unit button. Backdrop, edge, divider and the portrait's
--           square, which is a child at the same level.
--   bar     two levels up. The health and power bars, carrying the two spent
--           tracks and the heal slice as regions of their own.
--   top     three levels up. Every piece of text and every badge, because font
--           strings under a status bar is exactly what the first version
--           shipped.
function Block.Build(entry)
	local frame, spec = entry.frame, entry.spec

	-- What UnitFrames/Auras.lua hangs its rows off. The block and the button
	-- are one rectangle now, so the name the rows know it by points at the
	-- button.
	entry.box = frame

	local backdrop = ns.Fill(frame, "BACKGROUND",
		BACKDROP[1], BACKDROP[2], BACKDROP[3], BACKDROP[4])
	backdrop:SetAllPoints()
	entry.edges = ns.Outline(frame, IDLE[1], IDLE[2], IDLE[3], 1)
	entry.divider = ns.Fill(frame, "BORDER", IDLE[1], IDLE[2], IDLE[3], 1)

	-- The portrait's square, and the portrait inside it. Cropped once, here,
	-- rather than written back on every pass: the texture is ours and nothing
	-- else writes on it. SetPortraitTexture hands the render to the texture
	-- from the C side and leaves the crop alone.
	entry.slot = CreateFrame("Frame", nil, frame)
	entry.slot:EnableMouse(false)
	entry.portrait = ns.UI.Crisp(entry.slot:CreateTexture(nil, "ARTWORK"))
	entry.portrait:SetTexCoord(PORTRAIT_TRIM, 1 - PORTRAIT_TRIM,
		PORTRAIT_TRIM, 1 - PORTRAIT_TRIM)

	entry.healthBar = Bar(entry)
	entry.powerBar = Bar(entry)
	entry.healthTrack = entry.healthBar.track
	entry.powerTrack = entry.powerBar.track

	-- The incoming heal, between the track and the fill, pinned to the fill's
	-- inner edge. That edge is exactly where the bar stops whichever way the
	-- bar fills, so the slice starts where the fill ends and stands as tall as
	-- the bar without anybody working out how tall that is. Pinned once: the
	-- fill is ours and the client never swaps it.
	entry.healSlice = Gauge.Underlay(entry.healthBar, SLICE_LAYER, HEAL)
	entry.healSlice:ClearAllPoints()
	local fill = entry.healthBar:GetStatusBarTexture()
	local mine = spec.mirror and "RIGHT" or "LEFT"
	local theirs = spec.mirror and "LEFT" or "RIGHT"
	entry.healSlice:SetPoint("TOP" .. mine, fill, "TOP" .. theirs, 0, 0)
	entry.healSlice:SetPoint("BOTTOM" .. mine, fill, "BOTTOM" .. theirs, 0, 0)
	entry.healSlice:Hide()

	entry.top = CreateFrame("Frame", nil, frame)
	entry.top:EnableMouse(false)

	-- One shared font object per size rather than a font on each string. Place
	-- picks the real size off the bar heights a moment later; these are only
	-- what the strings carry until it does.
	entry.nameText = ns.UI.Label(entry.top, BIG_MAX, NAME_TEXT, "LEFT", ns.UI.FLAT)
	entry.healthText = ns.UI.Label(entry.top, BIG_MAX, VALUE_TEXT, "RIGHT", ns.UI.FLAT)
	entry.levelText = ns.UI.Label(entry.top, SMALL_MAX, VALUE_TEXT, "LEFT", ns.UI.FLAT)
	entry.powerText = ns.UI.Label(entry.top, SMALL_MAX, VALUE_TEXT, "RIGHT", ns.UI.FLAT)

	-- The badges this frame carries, hidden until the tick has something to
	-- say. On the text frame, so they sit over the portrait.
	entry.badges = {}
	for index = 1, #spec.badges do
		local slot = spec.badges[index]
		local texture = ns.UI.Crisp(entry.top:CreateTexture(nil, "OVERLAY"))
		if BADGES[slot].art then
			texture:SetTexture(BADGES[slot].art)
		end
		texture:Hide()
		entry.badges[slot] = texture
	end

	-- The aura rows, on the frames that have them. Children of the button like
	-- everything above, so they hide with it, and everything else about them is
	-- UnitFrames/Auras.lua's.
	ns.FrameAuras.Build(entry)
end

-- Sized off the two settings and laid out from the corner the portrait is on,
-- which is the left of the player frame and the right of the target frame, so
-- the block grows away from it in opposite directions on the two. The inside
-- is a tree handed to ns.UI.Flow; what is left for SetPoint is what Flow
-- cannot place, which is four strings as wide as whatever the unit happens to
-- be called and the badges on the square's corners.
--
-- False where combat refused, which is any pass at all in a lockdown: the
-- button is a secure unit button and sizing it is forbidden there.
function Block.Place(entry)
	local spec, frame, anchor = entry.spec, entry.frame, entry.anchor
	if ns.Blocked(frame) then
		return false
	end

	-- Every number below this line is a whole count of physical pixels, and px
	-- is what turns one into the units the block is drawn in. On the grid px is
	-- exactly 1 and every multiply is free. Off it, on a client with no
	-- SetIgnoreParentScale, it is the fraction that keeps the block the same
	-- physical size and its hairlines one pixel wide.
	local px = ns.Pixel(frame)

	local side = math.max(math.floor(ns.db.skinHeight * spec.scale + 0.5), 16)
	local width = math.max(math.floor(ns.db.skinWidth * spec.scale + 0.5), 60)
	local total = (side + width) * px

	-- LEFT is the side the portrait is on, RIGHT the side the gauge runs to, and
	-- pull is the sign that turns an inset into an offset on whichever edge that
	-- leaves.
	local portraitEdge = spec.mirror and "RIGHT" or "LEFT"
	local gaugeEdge = spec.mirror and "LEFT" or "RIGHT"
	local pull = spec.mirror and 1 or -1

	-- The anchor is the block's rectangle and the button covers it exactly.
	-- The anchor is what UI.Placeable drags and what the target's link anchors
	-- against, so it has to be the size you can see.
	anchor:SetSize(total, side * px)
	frame:SetSize(total, side * px)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
	ns.EdgeSize(entry.edges, px)

	-- The z-order Build's note sets out, rewritten on every relayout.
	local level = frame:GetFrameLevel()
	entry.slot:SetFrameLevel(level)
	entry.healthBar:SetFrameLevel(level + 2)
	entry.powerBar:SetFrameLevel(level + 2)
	entry.top:ClearAllPoints()
	entry.top:SetAllPoints(frame)
	entry.top:SetFrameLevel(level + 3)

	-- Whole pixels, because the two bars have to add up to the square exactly:
	-- health plus power plus the three hairlines is the side, and a fractional
	-- share leaves a seam along one of them that reads as a rendering fault.
	local inner = side - HAIRLINES
	local health = math.floor(inner * HEALTH_SHARE)
	local power = inner - health

	-- The whole inside of the block, in one row of three: the portrait's square,
	-- the gauge, and one pixel of nothing on the far edge for the outline to
	-- draw into. The divider is the square's inner column rather than a cell of
	-- its own, so the square and the gauge read as one strip with a hairline
	-- down it rather than as two boxes that happen to touch.
	--
	-- `reverse` is the whole of the mirroring: it runs the row backwards, so the
	-- target's three cells land the other way round with no sign anywhere here.
	Flow.Arrange(frame, {
		direction = "row", reverse = spec.mirror, align = "stretch",
		width = total, height = side * px,
		{ frame = entry.slot, width = side * px, align = "stretch",
			direction = "row", reverse = spec.mirror, pad = { 0, px, 0, px },
			{ grow = 1 }, { frame = entry.divider, width = px } },
		{ direction = "column", grow = 1, gap = px, align = "stretch",
			pad = { 0, px, 0, px },
			{ frame = entry.healthBar, height = health * px },
			{ frame = entry.powerBar, height = power * px } },
		{ width = px },
	})

	-- Inset by one pixel from the square, so the render lands inside the
	-- outline rather than under it.
	entry.portrait:ClearAllPoints()
	entry.portrait:SetPoint("TOPLEFT", entry.slot, "TOPLEFT", px, -px)
	entry.portrait:SetPoint("BOTTOMRIGHT", entry.slot, "BOTTOMRIGHT", -px, px)

	-- What the tick needs to draw an incoming heal, worked out here because
	-- both answers change with the layout and neither changes between two
	-- ticks. The width a heal is a fraction of is read back off the bar Flow
	-- just sized rather than derived from the settings again, so one thing
	-- decides how wide the gauge is and not two.
	entry.railPixels = math.max(math.floor(entry.healthBar:GetWidth() / px + 0.5), 1)
	-- The heal span is forgotten with it: the tick guards every write on the
	-- width it last drew, and that width is now a different number of pixels.
	entry.pixel, entry.healSpan = px, nil

	-- Sized off the block, because the same code draws a 34 pixel player frame
	-- and a 21 pixel target of target. One shared object per size; UI/Text.lua
	-- says why. Not rounded: `big` is a whole count of pixels and `px` is what
	-- one costs in units, so `big * px` is already exact. Shadowed, not
	-- outlined: all four sit on an opaque bar.
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
	-- is rasterised across two, which is what makes small text look like it
	-- has been breathed on.
	local pad = TEXT_PAD * px
	local healthMid = -(1 + math.floor(health / 2)) * px
	local powerMid = -(2 + health + math.floor(power / 2)) * px

	-- Anchored to the square's inner corner rather than to its side, because a
	-- side point sits at half height and the vertical offsets here are all
	-- measured down from the top of the block.
	entry.healthText:ClearAllPoints()
	entry.healthText:SetPoint(gaugeEdge, frame, "TOP" .. gaugeEdge, pull * pad, healthMid)

	entry.nameText:ClearAllPoints()
	entry.nameText:SetPoint(portraitEdge, entry.slot, "TOP" .. gaugeEdge, -pull * pad, healthMid)
	entry.nameText:SetPoint(gaugeEdge, entry.healthText, portraitEdge, pull * pad, 0)

	-- The level goes on the power bar's inner end, which is empty on every
	-- unit in the game, and the power number on its outer end.
	entry.levelText:ClearAllPoints()
	entry.levelText:SetPoint(portraitEdge, entry.slot, "TOP" .. gaugeEdge, -pull * pad, powerMid)

	entry.powerText:ClearAllPoints()
	entry.powerText:SetPoint(gaugeEdge, frame, "TOP" .. gaugeEdge, pull * pad, powerMid)
	entry.powerText:SetShown(power >= VALUE_FLOOR)

	-- On the outer corners of the square, the two the gauge is not against,
	-- each centred on its corner so it half overhangs the block.
	--
	-- An even number of pixels, because the badge is centred on a corner and
	-- half of an odd one puts all four of its edges on a half pixel.
	for index = 1, #spec.badges do
		local slot = spec.badges[index]
		local badge, texture = BADGES[slot], entry.badges[slot]
		local size = math.floor(side * badge.scale / 2 + 0.5) * 2 * px
		texture:ClearAllPoints()
		texture:SetSize(size, size)
		texture:SetPoint("CENTER", entry.slot, badge.corner .. portraitEdge, 0, 0)
	end

	-- Last, because a row wraps against the block's width and the block has
	-- only just been given one.
	ns.FrameAuras.Place(entry, px, total, spec.mirror)
	return true
end

--------------------------------------------------------------------------
-- The chain
--
-- The player block is placed by dragging it and nothing else is. The target
-- block hangs off the player block and target of target hangs off the target
-- block, so the three are one HUD and one drag moves all of it.
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
-- terms are read in screen units, and the result is divided back into the
-- frame's own units because that is what an anchor offset counts in. The two
-- blocks are on one scale now, but the arithmetic stays general: it is the
-- same three lines and it holds on a client where the grid is not supported.
--
-- Nil where the client has not resolved a position yet. There is nothing to
-- fall back to and that is deliberate: the caller leaves the target on the
-- point it already has and asks again on the next pass, which is the frame
-- staying where it was rather than jumping to an invented distance and then
-- jumping again once the host answers.
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
-- ruler `/wk skin height` and `/wk skin width` are on.
--
-- Written on every pass rather than only when the switch moves, because three
-- things change the numbers without changing the state: the player moving,
-- the level setting, and a resolution change that moves what one pixel costs.
-- UnitFrames/Skin.lua decides whether the link is wanted at all and calls this
-- only then; the unlinked target sits on a point of its own, which is
-- UI.Placeable's to write.
function Block.Link(entry, host)
	if ns.Blocked(entry.frame) then
		return false
	end
	local anchor = entry.anchor
	local mine, theirs = Facing(host, entry)
	-- Measured before the frame is unpinned, so a host that cannot answer yet
	-- leaves the target on the point it arrived with.
	local across = Mirrored(anchor, host.frame, theirs)
	if not across then
		return false
	end
	anchor:ClearAllPoints()
	anchor:SetPoint("TOP" .. mine, host.frame, "TOP" .. theirs,
		across, -ns.db.skinLevel * ns.Pixel(anchor))
	entry.linked = true
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
	if not host or ns.Blocked(entry.frame) then
		return false
	end
	local anchor, block = entry.anchor, host.frame
	local ourTop, theirTop = ScreenEdge(anchor, "GetTop"), ScreenEdge(block, "GetTop")
	-- One screen pixel in the units those two edges came back in, which is
	-- what turns a distance on the screen into the count a person types.
	local pixel = ns.Pixel(anchor) * (ns.Measure(anchor, "GetEffectiveScale") or 0)
	if not ourTop or not theirTop or pixel <= 0 then
		return false
	end
	ns.db.skinLevel = Snap((theirTop - ourTop) / pixel, LEVEL_LOW, LEVEL_HIGH)
	return Block.Link(entry, host)
end

-- Target of target, parked under the target block.
--
-- Anchored by the edge the two blocks share rather than by the portrait's: the
-- target is mirrored and target of target is not, so aligning their outer
-- edges is what puts one portrait under the other. Off the target's anchor
-- rather than its button, so the perch holds while the target has nothing to
-- draw and the button is down.
--
-- Written on every pass rather than only when the switch moves, for Link's
-- third reason: TOT_GAP is three pixels and what three pixels cost in this
-- frame's units moves with the screen.
function Block.Perch(entry, host)
	if ns.Blocked(entry.frame) then
		return false
	end
	local anchor = entry.anchor
	local side = host.spec.mirror and "RIGHT" or "LEFT"
	anchor:ClearAllPoints()
	anchor:SetPoint("TOP" .. side, host.anchor, "BOTTOM" .. side, 0, -TOT_GAP * ns.Pixel(anchor))
	entry.perched = true
	-- What the host's aura rows now hang from. This frame is parked on exactly
	-- the corner they hang off, so without being told, the first row would be
	-- drawn on top of it. The button rather than the anchor, because the button
	-- is what goes up and down with the unit and Hang asks it whether it is
	-- shown. Told rather than worked out over there, because whether this frame
	-- is under that block is this function's answer and nobody else's.
	ns.FrameAuras.Under(host, entry.styled and entry.frame or nil)
	return true
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

-- What a level is allowed to be, so the slash command, the panel's stepper and
-- the clamp a dropped drag goes through are all reading one range.
function Block.Range()
	return LEVEL_LOW, LEVEL_HIGH
end

-- Where the block is, for `/wk skin probe`. The anchor's point, which is either
-- the setting or the link, and whether the button is on the screen, which is
-- the line to read when the block is placed and painted and still nobody can
-- see it.
function Block.Probe(entry)
	local anchor = entry.anchor
	local point, relative, relativePoint, x, y = anchor:GetPoint()
	local against = relative and relative.GetName and relative:GetName() or "?"
	local row = ns.FrameAuras.Probe(entry)
	row = row and (", " .. row) or ""
	return ("%s %dx%d at %s of %s %s %d, %d, %s%s%s"):format(
		entry.spec.global,
		math.floor(ns.Measure(anchor, "GetWidth") or 0),
		math.floor(ns.Measure(anchor, "GetHeight") or 0),
		tostring(point), against, tostring(relativePoint),
		math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5),
		entry.linked and "hung off the player block" or
			(entry.perched and "parked under the target block" or "on its own point"),
		entry.frame:IsShown() and ", on screen" or ", not drawn",
		row)
end
