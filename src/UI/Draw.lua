local ADDON, ns = ...

local UI = ns.UI

--------------------------------------------------------------------------
-- Drawing
--
-- A coloured rectangle, a one pixel outline, and a piece of the client's own
-- icon art with the sampling left alone. Between them they draw every surface
-- the addon owns. These names live on ns rather than on ns.UI because the panel
-- and both halves of the unit frames part already call them and the namespace
-- contract in the README names them there.
--
-- SetBackdrop is deliberately not used: it needs a template that may not be on
-- this client, and the whole of it is thirty lines here.
--------------------------------------------------------------------------

function ns.Fill(parent, layer, r, g, b, a)
	local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
	texture:SetColorTexture(r, g, b, a or 1)
	return texture
end

function ns.Pixel(frame)
	return UI.Pixel(frame)
end

-- How thick the four edges are, and how long, where the caller knows.
--
-- The length is optional and almost nobody passes it. An edge is pinned to two
-- of its frame's corners, so its length is the frame's and the client works it
-- out. That holds for anything laid out once and left alone, which is every
-- window and every bar in the addon.
--
-- It does not hold for a widget whose size is a setting. Pass the frame's own
-- width and height there and each edge gets a length of its own as well as the
-- two anchors, so an edge is a rectangle the client has been given rather than
-- one it has to derive from a frame that was resized under it.
function ns.EdgeSize(edges, size, width, height)
	edges[1]:SetHeight(size)
	edges[2]:SetHeight(size)
	edges[3]:SetWidth(size)
	edges[4]:SetWidth(size)
	if width and height then
		edges[1]:SetWidth(width)
		edges[2]:SetWidth(width)
		edges[3]:SetHeight(height)
		edges[4]:SetHeight(height)
	end
end

-- Returns the four edges so a caller that recolours on state, the way a bar
-- takes the threat colour, or resizes them to a real pixel, does not have to
-- rebuild them.
--
-- The layer is an argument because a frame can carry two of these at once: the
-- minimap bezel is a wide band on BACKGROUND with a hairline on BORDER over
-- it, and two sets on one layer have no order between them.
function ns.Outline(frame, r, g, b, a, layer)
	local edges = {}
	for i = 1, 4 do
		edges[i] = ns.Fill(frame, layer or "BORDER", r, g, b, a)
	end
	edges[1]:SetPoint("TOPLEFT")
	edges[1]:SetPoint("TOPRIGHT")
	edges[2]:SetPoint("BOTTOMLEFT")
	edges[2]:SetPoint("BOTTOMRIGHT")
	edges[3]:SetPoint("TOPLEFT")
	edges[3]:SetPoint("BOTTOMLEFT")
	edges[4]:SetPoint("TOPRIGHT")
	edges[4]:SetPoint("BOTTOMRIGHT")
	ns.EdgeSize(edges, 1)
	return edges
end

-- Four writes behind one comparison. Callers already guard on the colour table
-- they are about to pass, but they cannot all guard on the same thing: the
-- enemy bars compare table identity against a module constant, the skin builds
-- a colour from the class. The guard belongs here, where it covers both, and it
-- is what lets this be called from a ticker at all.
function ns.Recolor(edges, color)
	local r, g, b = color[1], color[2], color[3]
	local a = color[4] or 1
	if edges.r == r and edges.g == g and edges.b == b and edges.a == a then
		return false
	end
	edges.r, edges.g, edges.b, edges.a = r, g, b, a
	for i = 1, 4 do
		edges[i]:SetColorTexture(r, g, b, a) -- unguarded: the return above compares all four
	end
	return true
end

--------------------------------------------------------------------------
-- The wash
--
-- A rectangle that is solid at one edge and gone at the other. It is what a
-- window puts under its own text when there is no window: the character sheet
-- has no ground by design, so nineteen item names are read against whatever the
-- player happens to be standing on, and a white name on snow is a name you lean
-- in to read.
--
-- Not a texture file with the ramp painted into it, and the third reason is the
-- one that decided it. A file is a fixed number of texels and a row is as wide
-- as its own name, so nineteen rows would stretch one ramp by nineteen amounts
-- and the fade would begin in a different place on each. A file has to be
-- baked, shipped and kept in step with UI.Color, and the colour it would carry
-- is the palette's shadow, which is a decision that lives in Theme.lua and not
-- in art. And the client draws the ramp for nothing: a gradient is four colours
-- on the corners of a quad the hardware was going to interpolate anyway.
--
-- Not a stroke round the letters either. A rim thickens every glyph, costs a
-- second draw of the whole string, and says nothing about where the text ends,
-- which is the half a reader uses to find the row under it.
--
-- Which edge is solid is the caller's, because a row in a right hand column
-- runs the other way. A wash that always ran left to right would put its solid
-- end where that row has no text at all.
--------------------------------------------------------------------------

-- The axis each solid edge implies, and which of those edges is the gradient's
-- own min end. The client runs a horizontal gradient min at the left and a
-- vertical one min at the bottom.
local WASH_AXIS = {
	LEFT = "HORIZONTAL", RIGHT = "HORIZONTAL",
	BOTTOM = "VERTICAL", TOP = "VERTICAL",
}
local WASH_MIN = { LEFT = true, BOTTOM = true }

-- A texture the caller still has to place and size.
--
-- Unanchored and unsized on purpose. The sheet re-measures its washes after
-- every repaint, off strings that only just took their text, and a primitive
-- that guessed at either would be overwritten on the first paint and misleading
-- until then.
--
-- The far end is the same colour at zero alpha rather than black. A ramp to
-- black goes grey through the middle over anything that is not black, which is
-- exactly the case this exists for: what is behind it is the world.
--
-- White and solid first, because a gradient tints what is drawn rather than
-- replacing it, and a texture with no file and no colour has nothing to tint.
--
-- A client with no gradient gets a flat wash of the same colour at half
-- strength. That is worse and it is legible, which is the trade every probe in
-- this addon makes.
function UI.Wash(parent, color, edge, layer)
	local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
	edge = WASH_AXIS[edge] and edge or "LEFT"
	local solid = { color[1], color[2], color[3], color[4] or 1 }
	local gone = { color[1], color[2], color[3], 0 }
	local min, max = solid, gone
	if not WASH_MIN[edge] then
		min, max = gone, solid
	end
	texture:SetColorTexture(1, 1, 1, 1)
	if not ns.Gradient(texture, WASH_AXIS[edge], min, max) then
		texture:SetColorTexture(solid[1], solid[2], solid[3], solid[4] * 0.5)
	end
	return texture
end

--------------------------------------------------------------------------
-- Art the client drew
--
-- A solid colour is one texel stretched over a rectangle and there is nothing
-- to get wrong. A spell icon is a 64 texel square being resampled to whatever
-- size the layout asked for, and that is where the mush comes from.
--
-- Two things fix it. The crop has to land on texel boundaries: the border strip
-- baked into every icon is five texels wide, so the coordinate is 5/64 and not
-- 0.08, which cuts 5.12 texels and forces the sampler to interpolate across the
-- whole image to find the edge. And the client's own snapping has to come off:
-- SetSnapToPixelGrid pulls a texture's corners onto whole pixels, which is
-- right for a rectangle of flat colour and wrong for sampled art, because it
-- stretches the two axes by different amounts and the picture inside softens.
-- Both methods are probed, because nothing installed here proves either is on
-- 2.5.6, and an icon that is merely soft is better than a widget that raises.
--------------------------------------------------------------------------

-- What the client stores a spell icon at, and how much of it the crop leaves.
-- Both are needed by anything that wants to know how big an icon can be drawn
-- before the sampler has to blend, so they are named rather than inlined.
local ICON_SOURCE = 64
local ICON_CROP = 5 / 64

-- How many texels of the stored icon actually get sampled. 54, not 64, and that
-- number is the whole reason the sizes everybody assumes are sharp are not.
function UI.IconTexels()
	return ICON_SOURCE * (1 - ICON_CROP * 2)
end

-- The drawn sizes where one stored texel lands on exactly one pixel, largest
-- first.
--
-- The client keeps each texture at half the size of the one above it and picks
-- the pair nearest the size asked for, so a draw is exact only where the texels
-- the crop leaves halve down to it. Everyone reaches for 64, 32 and 16, and
-- those are the answer for an uncropped texture. Cropping to 54 makes the
-- answer 54 and 27, because 13.5 is not a number of pixels.
--
-- Anything not on this list is a blend of two stored copies, and the worst
-- place to stand is halfway between two of them, where both are weighted
-- equally and neither is the picture.
function UI.IconSizes()
	local sizes = {}
	local size = UI.IconTexels()
	while size >= 8 do
		if size == math.floor(size) then
			sizes[#sizes + 1] = size
		end
		size = size / 2
	end
	return sizes
end

function UI.Crisp(texture)
	if texture.SetSnapToPixelGrid then
		texture:SetSnapToPixelGrid(false)
	end
	if texture.SetTexelSnappingBias then
		texture:SetTexelSnappingBias(0)
	end
	return texture
end

function UI.Icon(parent, layer)
	local texture = parent:CreateTexture(nil, layer or "ARTWORK")
	texture:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	return UI.Crisp(texture)
end

--------------------------------------------------------------------------
-- The disc
--
-- A gear icon on the character sheet is round and its last few texels fade out
-- rather than stopping at a line. That is one file, src/Media/Round.tga, doing
-- two jobs, and scripts/bake-round.sh writes it and argues the ramp.
--
-- As a mask it clips the icon. As an ordinary texture, drawn a little wider
-- than the icon and vertex coloured, it is the quality colour the icon's fade
-- lands on, which is the only reason the fade reads as soft rather than as an
-- icon going missing at the edges.
--------------------------------------------------------------------------

local ROUND = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Round.tga"

-- Clip a texture into the disc.
--
-- Named Clip rather than Round because UI/Pixel.lua already owns UI.Round, which
-- is the pixel grid rounder thirty callers reach for. This file loads after that
-- one, so the second definition was not a clash anything reported: it replaced
-- the first and every layout in the addon started asking a number for its parent.
--
-- The mask is a texture of its own and has to live somewhere, so it is made on
-- the icon's parent and pinned to the icon rather than to the frame: it then
-- follows every resize and re-anchor the layout does, and no caller has to
-- remember it is there.
--
-- CLAMPTOBLACKADDITIVE on both axes rather than the default wrap. A mask is
-- sampled outside its own bounds wherever the texture under it reaches further,
-- and the default repeats the disc out there, which draws the corners of the
-- icon back in as four more circles.
--
-- Both calls are probed, the way UI.Crisp probes its two, and what comes back is
-- checked as well as the name. They are on 2.5.6 and on the vanilla client, and
-- a square icon is a worse page rather than a broken one. The return is worth a
-- line of its own because the harness is exactly the client that has the name
-- and not the thing: an unwritten method there answers a function that hands
-- back nil, which is how this shipped its first crash.
function UI.Clip(texture)
	local parent = texture:GetParent()
	if not parent.CreateMaskTexture or not texture.AddMaskTexture then
		return texture
	end
	local mask = parent:CreateMaskTexture()
	if not mask then
		return texture
	end
	mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
	texture.mask = mask
	return texture
end

-- The same disc as a texture. White in the file, so SetVertexColor is what
-- gives it a colour and every caller of this is about to call that.
function UI.Disc(parent, layer)
	local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
	texture:SetTexture(ROUND)
	return texture
end

--------------------------------------------------------------------------
-- The arc
--
-- A wedge of that same disc, whole when a wait begins and eaten away clockwise
-- from twelve as it runs down. Laid between a ring and the icon sitting inside
-- it, the only part of the wedge anybody sees is the band, and a band cut like
-- that is an arc.
--
-- The client will not draw one. A Cooldown frame draws its swipe over the
-- square it is on, there is no primitive for a sector, and the swipe texture
-- call that would round it off is Legion's: nothing installed here calls it
-- with a TBC interface, and a call the documentation has and the disk does not
-- is how this addon shipped a bug already. So the arc is built, and the build
-- is OPie's, out of UI/Mirage.lua, which does exactly this under
-- `## Interface: 20506`.
--
-- Two textures and two masks. Each texture is half the disc, pinned so its
-- straight edge is down the middle. Each mask is a white rectangle over the
-- right half, and a rectangle turned about the middle of its own left edge is a
-- half plane whose boundary sweeps: at no turn it keeps the right half, at half
-- a turn the left. So the right half of the disc is cut by a mask turning
-- through the first half of the wait, the left half by one turning through the
-- second, and between them they are one wedge with one moving edge.
--
-- The rectangle is half the frame wide and all of it tall, which is exactly the
-- half plane and not a pixel more: every point of a disc inscribed in that
-- frame lies within half a width along the mask's own axis and half a height
-- across it, whichever way it is turned. On a frame that is not square the disc
-- is an ellipse and the far corners of the sweep are approximate. Nothing here
-- draws one on anything but a square.
--
-- A client with no masks gets the whole ring dark while the wait runs and the
-- ring back when it ends. That says the thing worth saying and not how much
-- longer, which is the trade every probe in this file makes.
--------------------------------------------------------------------------

-- A solid white texture the client ships, and a mask cut from it keeps every
-- pixel inside its own rectangle and nothing outside. Minimap/Shape.lua hands
-- the same file to the map for the same reason.
local WEDGE = "Interface\\Buttons\\WHITE8X8"

-- What a mask turns about, in its own texture's coordinates: the middle of its
-- left edge, which the anchors below put on the middle of the disc.
local PIVOT = { x = 0, y = 0.5 }
local TURN = math.pi * 2

-- How far the boundary has to move before the two rotations are worth writing,
-- which is a pixel. A thirty-six pixel disc has a hundred and thirteen pixels
-- of edge round it, so a hundred and twenty eighth of a turn is where the
-- moving end of the arc lands on the next pixel and anything finer is a redraw
-- of the same picture.
local STEP = 1 / 128

-- One half's mask, or nil on a client that will not make one.
--
-- Probed the way UI.Clip probes its pair, and what comes back is checked as
-- well as the name: the harness is exactly the client that has the name and not
-- the thing, and an unwritten method there answers a function handing back nil.
local function Cut(frame, half)
	if not frame.CreateMaskTexture or not half.AddMaskTexture then
		return nil
	end
	local mask = frame:CreateMaskTexture()
	if not mask then
		return nil
	end
	mask:SetTexture(WEDGE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetPoint("TOPLEFT", frame, "TOP")
	mask:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
	half:AddMaskTexture(mask)
	return mask
end

-- The two halves, their two masks and the colour all of it is drawn in. Sized
-- and placed off the frame it is made on, so an arc follows every resize its
-- ring does and no caller has to place it.
--
-- Hidden at build. An arc is the exception on a page rather than the rule:
-- most of what a player is wearing has nothing to press.
function UI.Arc(frame, layer, color)
	local arc = { masks = {} }
	for index = 1, 2 do
		local right = index == 1
		local half = frame:CreateTexture(nil, layer or "BORDER")
		half:SetTexture(ROUND)
		half:SetTexCoord(right and 0.5 or 0, right and 1 or 0.5, 0, 1)
		half:SetPoint("TOPLEFT", frame, right and "TOP" or "TOPLEFT")
		half:SetPoint("BOTTOMRIGHT", frame, right and "BOTTOMRIGHT" or "BOTTOM")
		half:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
		half:Hide()
		arc[index] = half
		arc.masks[index] = Cut(frame, half)
	end

	-- Both or neither. One half cut and the other whole is a sweep that is right
	-- for half of every wait and a solid disc for the other half, which reads
	-- worse than the flat answer and takes longer to work out.
	if not (arc.masks[1] and arc.masks[2]) then
		arc.masks = nil
	end
	return arc
end

-- How much of the ring is still dark: one where a wait has just begun, nothing
-- where it has ended.
--
-- Quantised to the step above before anything is compared, so a pass that has
-- not moved the boundary a pixel reads as the same number and writes nothing.
-- Both ends survive the rounding exactly, which is what keeps the start and the
-- finish of a wait a write rather than something lost to it.
--
-- Answers whether it wrote. That is what the tick driving it wants to know and
-- what the harness reads: at four passes a second against a two minute trinket,
-- three passes in four have nothing to say.
function UI.Sweep(arc, fraction)
	local want = fraction < 0 and 0 or (fraction > 1 and 1 or fraction)
	want = math.floor(want / STEP + 0.5) * STEP
	if arc.at == want then
		return false
	end
	arc.at = want

	if arc.masks then
		-- One mask holds the moving edge and the other is parked at whichever end
		-- of its own half it has reached, which is what makes the pair one wedge:
		-- the first turns through the first half of the wait and the second waits
		-- at a half turn until the first has finished.
		local spent = 1 - want
		arc.masks[1]:SetRotation((1 - (spent < 0.5 and spent or 0.5)) * TURN, PIVOT)
		arc.masks[2]:SetRotation((1 - (spent > 0.5 and spent or 0.5)) * TURN, PIVOT)
	end

	local lit = want > 0
	if arc.lit ~= lit then
		arc.lit = lit
		arc[1]:SetShown(lit)
		arc[2]:SetShown(lit)
	end
	return true
end
