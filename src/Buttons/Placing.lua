local ADDON, ns = ...

local Place = {}
ns.BarPlace = Place

-- Where each cloned bar sits, and how you move it.
--
-- Its own file because Buttons/Bars.lua is what a bar *is* and this is where it
-- *goes*, and because the two answer to different masters. The bar's shape is
-- decided by the plan in that file and is not negotiable at runtime. Its
-- position is the one thing you cannot sensibly type, so this is the only part
-- of the bars you drive with the mouse.
--
-- The drag handle here is the third in the addon, after Charge/Icon.lua and
-- Meter/Window.lua. If a fourth turns up it belongs in the UI layer as one
-- shared widget, the way UI/Gauge.lua and UI/Ability.lua were both extracted on
-- their second copy. Three is the point at which that becomes worth saying out
-- loud and not yet the point at which Meter's version, which enables the mouse
-- on the frame itself rather than laying a handle over it, is worth rewriting.

-- How deep a bar stands, which is the other half of where it is.
--
-- Blizzard's `MainActionBar` is declared `enableMouse="true"` on MEDIUM at frame
-- level 50, sized 454 by 35 and anchored to the bottom of UIParent.
-- Buttons/Blizzard.lua hides the twelve buttons standing on it and a hidden
-- frame takes no mouse, but the bar frame under them is not hidden and is not
-- ours to hide: that corner of the client carries the micro menu and the bag bar
-- too, which is the warning Artwork.lua already writes down. Strip its art,
-- which is the shipping setting, and what is left is an invisible frame across
-- the bottom of the screen that takes every click landing on it.
--
-- A frame built on UIParent starts at level 1. Fifty beats one, so every drop
-- and every click aimed at bar 1 went into a frame with no drag handler and
-- vanished, while the keys, which never ask the mouse anything, went on working.
-- Bar 1 only, mouse only, and nothing on screen to see, because the thing
-- swallowing the click had already had its art taken off.
--
-- The other four bars were never affected and Blizzard's own source says why:
-- MultiBarBottomLeft, MultiBarBottomRight, MultiBarLeft and MultiBarRight are
-- each declared on MEDIUM with no `enableMouse` at all, so none of them has ever
-- taken a click. MainActionBar is the one action bar frame in the client that
-- does, which is exactly why exactly one bar was broken.
--
-- 120 rather than 51, and the headroom is the point. The end caps and the page
-- number inside that bar are declared at level 100 and neither takes the mouse
-- today; a number that already clears the frames which could start taking it is
-- a number nobody has to come back to.
local LEVEL = 120

-- Stand one bar up where the mouse can reach it. Once, at build.
--
-- The header carries its own level rather than inheriting one. A child does
-- start a level above its parent and the squares rely on exactly that, but the
-- level the squares are hit-tested at is the whole of this bug, and a number
-- that load bearing is written down rather than left to a default no file
-- states. The strata is set first because SetFrameStrata re-seats a frame in the
-- new strata's own order, so a level written before it is a level thrown away.
function Place.Stand(entry)
	entry.frame:SetFrameStrata("MEDIUM")
	entry.frame:SetFrameLevel(LEVEL)
	if entry.header then
		entry.header:SetFrameLevel(LEVEL + 1)
	end
end

-- Where a bar sits: what you dragged it to, or what the plan says.
--
-- The plan is the record and the drag is the tool. A position saved in WTF does
-- not travel, and an addon whose whole point is that a fresh install looks right
-- cannot keep where its bars live somewhere a fresh install has never seen. So
-- dragging writes an override you can feel your way to, `actionbars where`
-- prints the two lines to paste into the plan above, and `actionbars reset`
-- drops the override once you have. Same shape as bake-ui.sh, without the round
-- trip through a shell.
function Place.Put(entry)
	local def = entry.def
	local saved = ns.db.barPoints[def.key]
	entry.frame:ClearAllPoints()
	if saved then
		entry.frame:SetPoint(saved[1], UIParent, saved[3], saved[4], saved[5])
	else
		entry.frame:SetPoint(def.point, UIParent, def.to, def.x, def.y)
	end
end

-- Nearest whole unit, negatives included. On the grid one unit is one physical
-- pixel, so this is the difference between a bar whose every edge lands on a
-- pixel boundary and one that is half a pixel out along both axes.
local function Whole(value)
	return math.floor(value + 0.5)
end

-- A plain frame laid over the bar, shown only while the frames are unlocked.
--
-- The two jobs cannot share one frame, which is the note Charge/Icon.lua
-- already carries and is more true here. Everything inside a bar is a secure
-- action button that has to keep answering clicks; enabling the mouse on the
-- bar underneath them would put a second claim on every press. A separate frame
-- over the top takes every click while you are placing, and the buttons keep
-- their action the whole time.
function Place.Handle(entry)
	local handle = CreateFrame("Frame", nil, UIParent)
	handle:SetAllPoints(entry.frame)
	handle:SetFrameStrata("HIGH")
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle:Hide()
	entry.handle = handle

	handle:SetScript("OnDragStart", function()
		if not ns.db.locked and not InCombatLockdown() then
			entry.frame:StartMoving()
		end
	end)
	handle:SetScript("OnDragStop", function()
		entry.frame:StopMovingOrSizing()
		local point, _, relativePoint, x, y = entry.frame:GetPoint()
		-- Rounded, because a drag lands wherever the cursor was and the bar is
		-- on the pixel grid, where a fractional offset is every icon and every
		-- glyph on it rasterised across two rows. The grid buys exact sizes and
		-- nothing at all about position; this is where position is decided, and
		-- The harness's anchor sweep fails on a bar left on a fraction.
		--
		-- Not UI.Round, which snaps to a multiple of one physical pixel and
		-- floors the result at one. That floor is right for a size, where zero
		-- means invisible, and wrong for a coordinate, where zero means the
		-- middle and negative means the other side.
		ns.db.barPoints[entry.def.key] = { point, "UIParent", relativePoint,
			Whole(x), Whole(y) }
		Place.Put(entry)
	end)

	handle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(entry.def.label)
		GameTooltip:AddLine("drag to move it", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("/wk actionbars where prints it for the plan", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	handle:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

-- Show or hide every handle. Registered as the buttons feature's `lock`, so
-- /wk unlock reaches the bars the same way it reaches the charge icon and the
-- meters.
function Place.Lock(order)
	for index = 1, #order do
		local handle = order[index].handle
		if handle then
			handle:SetShown(not ns.db.locked)
		end
	end
end

-- The plan lines for wherever the bars are standing now, ready to paste over
-- the geometry in Buttons/Bars.lua.
--
-- This is the whole reconciliation between dragging a thing and keeping the
-- answer in git. Feel your way to it with the mouse, then promote it, then drop
-- the override so a fresh clone of this repo puts the bar in the same place
-- with no saved variables involved at all.
function Place.Where(order)
	local lines = {}
	for index = 1, #order do
		local entry = order[index]
		local def = entry.def
		local saved = ns.db.barPoints[def.key]
		local point = saved and saved[1] or def.point
		local to = saved and saved[3] or def.to
		local x = saved and saved[4] or def.x
		local y = saved and saved[5] or def.y
		lines[#lines + 1] = ("  %s: point = %q, to = %q, x = %d, y = %d%s"):format(
			def.key, point, to, x, y, saved and "  (dragged)" or "")
	end
	return lines
end

-- Drop every dragged override, so the plan is what draws again.
function Place.Reset(order)
	local dropped = 0
	for key in pairs(ns.db.barPoints) do
		ns.db.barPoints[key] = nil
		dropped = dropped + 1
	end
	for index = 1, #order do
		Place.Put(order[index])
	end
	return dropped
end

function Place.Dragged()
	local count = 0
	for _ in pairs(ns.db.barPoints) do
		count = count + 1
	end
	return count
end
