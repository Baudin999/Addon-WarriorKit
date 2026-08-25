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

function ns.EdgeSize(edges, size)
	edges[1]:SetHeight(size)
	edges[2]:SetHeight(size)
	edges[3]:SetWidth(size)
	edges[4]:SetWidth(size)
end

-- Returns the four edges so a caller that recolours on state, the way a bar
-- takes the threat colour, or resizes them to a real pixel, does not have to
-- rebuild them.
function ns.Outline(frame, r, g, b, a)
	local edges = {}
	for i = 1, 4 do
		edges[i] = ns.Fill(frame, "BORDER", r, g, b, a)
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
		edges[i]:SetColorTexture(r, g, b, a)
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

local ICON_CROP = 5 / 64

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
