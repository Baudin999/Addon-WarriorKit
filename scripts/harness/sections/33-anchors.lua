-- Every anchor on the grid, in whole pixels
--
-- The grid makes one unit one physical pixel inside an adopted frame. That buys
-- exact sizes, and it buys nothing at all about position: an anchor offset is a
-- number a person typed, and half of an odd number is half a pixel. A frame
-- whose own origin sits half a pixel off a boundary has every edge, every glyph
-- and every icon inside it rasterised across two rows of pixels. It is not
-- subtle and it is invisible in review, because the arithmetic that produces it
-- looks like centring, which is what it is.
--
-- Three of them were live when this check was written, all in the enemy bars,
-- and all three had the reason for rounding written in a comment a few lines
-- above the line that did not round.
--
--   PLATE_BAR_HEIGHT / 2 + 1   11.5 pixels, on the widget itself, in the style
--                              that ships as the default. Every bar the addon
--                              had ever drawn was half a pixel low.
--   STRIPE_WIDTH * px / 2      2.5 pixels, on the level tag's number.
--   lineHeight / 2             half a pixel on the threat line at any odd
--                              debuff icon size.
--
-- The first two are gone rather than rounded. The bar height is even now, so the
-- offset that centres it is whole by construction, and the level is a font
-- string inside the gauge with no stripe to centre it against. Rounding a
-- half-pixel away costs half a pixel of centring; not producing one costs
-- nothing. The check stays, because the next odd constant will not announce
-- itself either.
--
-- Scope is every frame the addon put on the grid and everything under it, asked
-- of ns.UI.OnGrid rather than sniffed off the client flag SetIgnoreParentScale
-- leaves behind. Those were the same set until the floating numbers, and the
-- difference is the exemption this rule now carries.
--
-- A frame that is not on the grid is not held to this: the charge button rides
-- UIParent's scale, and Blizzard's own frames are Blizzard's business. UIParent
-- itself is skipped, because the stub sets the flag on it to model the client.
--
-- And ns.UI.Adrift is off the parent's scale without being on the grid, which
-- is one thing in the addon: a floating combat number, whose scale ns.Ck.Stream
-- writes on every tick as it swells and shrinks. One unit inside it is a
-- different fraction of a pixel on every frame it is drawn, so "a whole number
-- of pixels" is not a rule it can be held to and would not mean anything if it
-- were. It is the anchored twin of the moving fill excused two paragraphs down:
-- a thing whose whole job is to be between pixels. What holds it instead is
-- section 80, which reads its position back multiplied by its own scale and
-- asserts where it is on the screen rather than what its anchor says.
--
-- This is the whole of the addon's first pixel rule and none of its second. It
-- walks anchor offsets, and an anchor offset is a static edge by construction:
-- a border, a band, a mark, a block of art. A moving fill is placed by
-- SetValue rather than by an anchor and never reaches this walk, which is
-- correct rather than a gap, because a moving fill is not allowed to be a whole
-- pixel. The second rule is gated in the swing section above, which asserts the
-- opposite thing about the same kind of edge: that the fill lands between
-- pixels on nearly every frame. Two rules, two gates, and neither excused.

local H = ...
local region, ns, check = H.region, H.ns, H.check

local offenders, checked, adopted = 0, 0, 0
local note = "at 1x"

local function onGrid(frame)
	local node = frame
	while node and node ~= _G.UIParent do
		if ns.UI.OnGrid(node) then
			return true
		end
		node = node.parent
	end
	return false
end

local function whole(value)
	return math.abs(value - math.floor(value + 0.5)) < 1e-6
end

local seen = {}
local walk
function walk(region)
	if seen[region] then
		return
	end
	seen[region] = true

	-- A frame's own offsets are in its own units. A texture or a font string
	-- carries no scale and is measured in the frame holding it.
	local host = region
	if region.kind == "texture" or region.kind == "fontstring" then
		host = region.parent
	end

	if host and region.points and onGrid(host) then
		adopted = adopted + 1
		local px = ns.UI.Pixel(host)
		for _, point in ipairs(region.points) do
			checked = checked + 1
			local x, y = (point[4] or 0) / px, (point[5] or 0) / px
			if not whole(x) or not whole(y) then
				offenders = offenders + 1
				check(false, ("%s: a %s anchored %s to %s sits at %.3f, %.3f pixels")
					:format(note, region.kind, tostring(point[1]), tostring(point[3]), x, y))
			end
		end
	end

	for _, kid in ipairs(region.regions) do
		walk(kid)
	end
	for _, kid in ipairs(region.children) do
		walk(kid)
	end
end

local function sweep(where)
	checked, adopted, offenders = 0, 0, 0
	seen = {}
	note = where
	walk(_G.UIParent)
	check(adopted > 0, where .. ": nothing on the grid carried an anchor")
	return checked, adopted, offenders
end

local one, regions, bad = sweep("at 1x")

-- And again at each whole zoom, because zoom scales every design number and
-- a size that was even at 1x is not obliged to stay whole once it has been
-- through a multiply. This is the sweep that would catch the bars going half
-- a pixel out at 2x, which nothing else here looks at.
local shipped = ns.db.barsZoom
for _, zoom in ipairs{2, 3} do
	ns.db.barsZoom = zoom
	ns.EnemyBars.ApplyLayout()
	ns.EnemyBars.Rebuild()
	local _, _, off = sweep(("at %dx"):format(zoom))
	bad = bad + off
end
ns.db.barsZoom = shipped
ns.EnemyBars.ApplyLayout()
ns.EnemyBars.Rebuild()
sweep("back at 1x")

print(("anchors %d offsets across %d regions on the grid, at 1x, 2x and 3x, %d off a whole pixel")
	:format(one, regions, bad))
