-- The skin on the three Blizzard unit frames
--
-- The same questions as the bars, against a part that cannot put its subject
-- on the grid. The portrait, the two bars and the state icons are regions of a
-- secure unit button, so what is asserted here is the boundary: whole pixels on
-- the frames the addon made, a sampling fix on the art it borrowed, sizes that
-- crossed the scale on the way out, and a tick that neither allocates nor
-- writes what is already there.
--
-- The block's own origin is deliberately not asserted. It hangs off Blizzard's
-- portrait anchor on a frame that is not on the grid, so where it lands is a
-- fraction the client owns, exactly as a bar on a nameplate is.

local H = ...
local PLAYER_CLASS, region, guids = H.PLAYER_CLASS, H.region, H.guids
local ns, check = H.ns, H.check
local anchor = H.carry.anchor

-- Units for the three frames, added now rather than at login so the enemy bar
-- figures above are measured against two mobs and not three.
guids.player, guids.target, guids.targettarget = "Player-1", "Creature-9", "Creature-8"
-- Apply rather than a tick, because that is what a target change does and it
-- is the path that has to leave a frame fully painted: a fifth of a second of
-- a white gauge reads as a bug.
ns.FrameSkin.Apply()

local blocks = {
	{ "player", _G.WarriorKitSkinPlayer, _G.PlayerFrame },
	{ "target", _G.WarriorKitSkinTarget, _G.TargetFrame },
	{ "tot", _G.WarriorKitSkinToT, _G.TargetFrameToT },
}

-- The palette, restated rather than reached for. Skin.lua keeps these local and
-- that is right; a gate that imported the number it is checking would pass on
-- the day somebody changed it by accident. UnitIsPlayer above is true for the
-- player alone, so the player wears their own class colour and the other two
-- fall to the hostile one on a reaction of 2.
--
-- What each of the three blocks should be painted, read from the palette
-- rather than written out again.
--
-- It used to be the stub's own class figures typed a second time, so that the
-- check was "the skin carried the client's colour through" rather than "two
-- tables agree". That stopped being the right question when Unit/Color.lua took
-- the class colours over: the bar is no longer the client's number, it is that
-- number under a luminance ceiling, and a hand-written copy here would be one
-- more place the arithmetic has to be redone by hand.
--
-- So this half is an identity check and the contrast section below is the half
-- that is independent. Together they say the skin painted what the palette
-- decided, and the palette decided something a name can be read on.
local TRACK, EDGE_DIM = ns.Unit.Color.track, 0.60
local HOSTILE = ns.Unit.Color.reaction.hostile
local TINT = {
	player = ns.Unit.Color.Class(PLAYER_CLASS),
	target = HOSTILE,
	tot = HOSTILE,
}
assert(TINT.player, PLAYER_CLASS .. " has no colour in the palette")

-- The two textures the skin draws inside each of Blizzard's bars, found the
-- way everything else here is found: by what they are, not by reaching into
-- the module's tables. The track fills its bar, so it is the one with
-- SetAllPoints on it; the slice is pinned to the fill texture instead, which
-- is what makes it start exactly where the bar stops.
local function barTexture(bar, filling)
	for _, region in ipairs(bar.regions) do
		if region.kind == "texture" and (region.allPoints ~= nil) == filling then
			return region
		end
	end
end

local function skinTrack(bar) return barTexture(bar, true) end
local function skinSlice(bar) return barTexture(bar, false) end

-- entry.top is the only frame the skin pins to the whole of the box, which is
-- how it is found without this file reaching into the module's own tables.
local function textFrame(box)
	for _, f in ipairs(box.parent.children) do
		if f.allPoints == box then
			return f
		end
	end
end

check(ns.FrameSkin.Hidden() > 0, "the skin walked all three frames and hid nothing")

for _, block in ipairs(blocks) do
	local key, box, frame = block[1], block[2], block[3]
	if not box then
		check(false, key .. ": no block was built over " .. tostring(frame and frame.name))
	else
		-- On the grid, which is the whole of what the addon can put there.
		check(box.ignoreScale == true, key .. ": the block is still on the unit frame's scale")
		local px = ns.UI.Pixel(box)
		check(math.abs(px - 1) < 1e-9,
			("%s: block is not on the grid, one pixel is %.4f units"):format(key, px))
		for _, axis in ipairs({ "GetWidth", "GetHeight" }) do
			local size = box[axis](box)
			check(size > 0 and math.abs(size - math.floor(size + 0.5)) < 1e-9,
				("%s: block %s is %.4f, not a whole pixel"):format(key, axis, size))
		end

		-- The fit, which is the whole of what makes Edit Mode's rectangle the
		-- one on the screen. The block sits on the frame's own corner, the
		-- portrait's square sits on the block, and the frame covers exactly
		-- the piece of screen the block does.
		--
		-- The last is the one with teeth, and it is asserted in screen space
		-- rather than in either frame's units because that is the only space
		-- the two share: the block is on the pixel grid and the unit frame is
		-- on the client's scale, so a fit that never converted would pass a
		-- comparison of the raw numbers and be out by the ratio between them.
		-- A fit dropped altogether leaves the frame at the 232 by 100 the stub
		-- built and fails by a mile.
		local corner = key == "target" and "TOPRIGHT" or "TOPLEFT"
		local anchor = box.points and box.points[1]
		check(anchor and anchor[2] == frame and anchor[1] == corner
			and anchor[3] == corner and anchor[4] == 0 and anchor[5] == 0,
			key .. ": the block is not pinned to the frame's own " .. corner)

		-- The square is the one frame the skin hangs on the block without
		-- naming it and without covering the block with it. The two rails are
		-- children of the box rather than of the frame, the text frame covers
		-- the whole of it, and the two aura rows are named globals so that a
		-- row that lands in the wrong place can be measured from a macro. That
		-- last one is why the name is in this walk: without it the debuff row
		-- is also a child of the frame pinned to the block, and the search
		-- came back with whichever of the two the client had built last.
		local slot
		for _, f in ipairs(frame.children) do
			if not f.name and not f.allPoints
				and f.points and f.points[1] and f.points[1][2] == box then
				slot = f
			end
		end
		check(slot ~= nil, key .. ": the portrait's square is not hung on the block")

		-- Read as an offset into the block rather than as an anchor on the
		-- mirrored corner, because ns.UI.Flow pins every frame in a tree to the
		-- root's top left corner at the offset that came out. Deliberately: a
		-- chain of anchors can only align the run it starts, which is what the
		-- hand-written version of this layout worked around by threading the
		-- mirror's sign through every offset it wrote.
		--
		-- The target's block runs backwards, so the square is the last cell of
		-- the row and sits a gauge's width in. On the other two it is the first.
		local square = slot and slot.points[1]
		local inset = key == "target" and (box:GetWidth() - slot:GetWidth()) or 0
		check(square and square[1] == "TOPLEFT" and square[2] == box
			and square[3] == "TOPLEFT" and square[4] == inset and square[5] == 0,
			("%s: the square is pinned to the block at %s, %s and belongs at %d, 0")
				:format(key, tostring(square and square[4]), tostring(square and square[5]),
					inset))
		check(slot and slot:GetWidth() == slot:GetHeight() and slot:GetHeight() == box:GetHeight(),
			key .. ": the portrait's square is not the block's height squared")

		for _, axis in ipairs({ { "width", "GetWidth" }, { "height", "GetHeight" } }) do
			local ours = box[axis[2]](box) * box:GetEffectiveScale()
			local theirs = frame[axis[2]](frame) * frame:GetEffectiveScale()
			check(math.abs(ours - theirs) < 1e-6,
				("%s: the block is %.2f of screen %s and the frame Edit Mode drags is %.2f")
					:format(key, ours, axis[1], theirs))
		end

		-- The two rails are the only frames the block parents, and Blizzard's
		-- bars are pinned to them corner to corner rather than sized.
		local healthRail, powerRail = box.children[1], box.children[2]
		check(healthRail and powerRail, key .. ": the gauge rails were never built")
		for name, rail in pairs({ health = healthRail, power = powerRail }) do
			local height = rail and rail:GetHeight() or 0
			check(height >= 1 and math.abs(height - math.floor(height + 0.5)) < 1e-9,
				("%s: the %s rail is %.4f pixels tall, not a whole one"):format(key, name, height))
		end
		check(frame.healthbar.allPoints == healthRail,
			key .. ": the health bar is not pinned to its rail")
		check(frame.manabar.allPoints == powerRail,
			key .. ": the power bar is not pinned to its rail")

		-- Stacking order, and the whole reason it is asserted this way.
		--
		-- The spent track used to be a texture on the rail, one frame under
		-- Blizzard's bar, and this file checked the two levels. Both clients
		-- took the writes and one of them did not keep them: the target frame
		-- came out with its rails level with its bars, the tie went to
		-- whichever was built later, which is ours, and the track drew over
		-- the fill at nine tenths alpha. A target at full health read at 28
		-- percent of its own colour. The player frame, one line of the same
		-- code away, was correct, and every level this file compared was the
		-- number the addon had asked for rather than the one on the screen.
		--
		-- So the order is no longer between two frames. The track and the heal
		-- slice are regions of Blizzard's own bar and sit under its fill by
		-- draw layer, which is settled inside one frame and cannot be a
		-- disagreement. What is asserted is that: same frame, and the layers
		-- in the order track, slice, fill.
		local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4 }
		local function depth(texture)
			if not texture or not LAYERS[texture.layer] then
				return nil
			end
			return LAYERS[texture.layer] * 16 + (texture.sublevel or 0)
		end
		for name, bar in pairs({ health = frame.healthbar, power = frame.manabar }) do
			local track = skinTrack(bar)
			check(track ~= nil and track.parent == bar,
				("%s: the spent part of the %s gauge is not a region of the bar it"
					.. " belongs to, so what draws on top is two frame levels arguing")
					:format(key, name))
			local under, over = depth(track), depth(bar.fill)
			check(under and over and under < over,
				("%s: the %s track is on %s and the fill on %s, so the track draws"
					.. " over the fill"):format(key, name, tostring(track and track.layer),
						tostring(bar.fill and bar.fill.layer)))
		end
		local slice = skinSlice(frame.healthbar)
		check(slice and slice.parent == frame.healthbar,
			key .. ": the heal slice is not a region of the health bar")
		check(depth(skinTrack(frame.healthbar)) < depth(slice)
			and depth(slice) < depth(frame.healthbar.fill),
			key .. ": the heal slice is not between the spent track and the fill")

		-- What the block is actually painted. The fill is the unit's colour at
		-- full brightness, the spent part of each gauge is that colour at a
		-- fifth, and the five hairlines are it at three fifths. All three are
		-- read back, because a gauge is only as good as the colour that reaches
		-- it and every one of these numbers used to be invisible here.
		local tint = TINT[key]
		local function near(a, b) return a and math.abs(a - b) < 1e-6 end
		local function paints(region, r, g, b, a)
			return region and near(region.r, r) and near(region.g, g)
				and near(region.b, b) and near(region.a, a)
		end
		check(paints(frame.healthbar, tint[1], tint[2], tint[3], 1)
			or (near(frame.healthbar.barR, tint[1]) and near(frame.healthbar.barG, tint[2])
				and near(frame.healthbar.barB, tint[3]) and near(frame.healthbar.barA, 1)),
			("%s: the health bar is painted %s,%s,%s and not the unit's %.2f,%.2f,%.2f")
				:format(key, tostring(frame.healthbar.barR), tostring(frame.healthbar.barG),
					tostring(frame.healthbar.barB), tint[1], tint[2], tint[3]))
		check(paints(skinTrack(frame.healthbar), tint[1] * TRACK, tint[2] * TRACK,
			tint[3] * TRACK, 0.9), key .. ": the spent part of the health gauge is not "
				.. "the unit's colour at ns.Unit.Color.track")
		local dimmed = 0
		for _, region in ipairs(box.regions) do
			if paints(region, tint[1] * EDGE_DIM, tint[2] * EDGE_DIM, tint[3] * EDGE_DIM, 1) then
				dimmed = dimmed + 1
			end
		end
		check(dimmed == 5, ("%s: %d of the block's five hairlines carry the unit's "
			.. "colour at three fifths, not all of them"):format(key, dimmed))

		-- Sampled art. The crop is on a texel boundary and the client's own
		-- snapping is off, the same two fixes a spell icon takes.
		local portrait = frame.portrait
		check(portrait.texcoord and math.abs(portrait.texcoord[1] * 64 - 10) < 1e-9,
			key .. ": the portrait crop is not on a texel boundary")
		check(portrait.snapped == false and portrait.bias == 0,
			key .. ": the portrait is still being snapped by the client")

		-- Sizes written onto a region of the unit frame cross the scale on the
		-- way out, and land on an even count so a badge centred on a corner
		-- does not put all four of its edges on a half pixel.
		local theirs = ns.UI.Pixel(frame)
		for _, badge in ipairs(frame.children[3].regions) do
			if badge.width > 0 then
				-- Rounded before the parity test, not after: the size was
				-- written as a count of pixels times the scale between us and
				-- reading it back divides that out again, which lands a hair
				-- off a whole number and never on one.
				local pixels = badge.width / theirs
				local whole = math.floor(pixels + 0.5)
				check(math.abs(pixels - whole) < 1e-6 and whole % 2 == 0,
					("%s: badge %s is %.4f pixels wide, not an even whole number")
						:format(key, tostring(badge.name), pixels))
			end
		end

		-- Shared font objects, not a font per string.
		local top = textFrame(box)
		check(top ~= nil, key .. ": no text frame over the block")
		for _, text in ipairs(top and top.regions or {}) do
			check(text.fontObject ~= nil and text.fontPath == nil,
				key .. ": a font string carries its own font instead of a shared object")
		end
	end
end

-- Left for the sections below.
H.carry.blocks, H.carry.skinSlice = blocks, skinSlice
