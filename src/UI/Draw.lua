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
