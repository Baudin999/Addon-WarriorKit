local ADDON, ns = ...

local UI = {}
ns.UI = UI

--------------------------------------------------------------------------
-- The pixel grid
--
-- The client draws the whole interface in a virtual space 768 units tall,
-- whatever the monitor is. A frame of height H at effective scale S covers
--
--     H * S * physicalHeight / 768
--
-- physical pixels, so one pixel is 768 / (S * physicalHeight) units. On a
-- screen 768 pixels tall that collapses to 1 / S, which is what this addon
-- returned from ns.Pixel until now. On this machine, 1440 tall with the UI
-- scale at 0.65, the true figure is 0.82 units and the old one was 1.54: every
-- hairline in the addon was being asked for at 1.9 pixels, which the renderer
-- lays down as a two pixel smear along one edge of a box and a one pixel line
-- along the other. That is the whole reason nothing looked crisp.
--
-- Correcting the arithmetic is not enough on its own, because a correct
-- fractional number of units still lands wherever the frame's own origin
-- happens to sit. The fix is to stop working in fractions. SetIgnoreParentScale
-- detaches a frame from whatever scale its parent carries, and a scale of
-- 768 / physicalHeight then makes one unit exactly one physical pixel inside
-- that frame and everything under it. Sizes become whole numbers of pixels
-- written as whole numbers, there is no rounding anywhere, and no arithmetic
-- runs on a ticker to keep it true.
--
-- What this cannot fix: a bar attached to a nameplate takes its origin from
-- where the mob is standing, which is a moving sub-pixel position no addon can
-- read or round. Its geometry is exact and its edges are one pixel; where that
-- pixel lands is the client's business. Bars in the list anchor to UIParent and
-- are exact in both.
--------------------------------------------------------------------------

local BASE = 768

-- Every frame put on the grid, so a resolution change can re-scale all of them.
-- Weak keyed: a frame that goes away is not held here.
local grid = setmetatable({}, { __mode = "k" })
local listeners = {}

-- Adopted frames the client refused to re-scale, held until combat drops.
--
-- Every frame on the grid is one the addon created, but not every one is a
-- frame the addon may touch at any moment. The unit frame skin adopts blocks
-- parented to PlayerFrame and TargetFrame, which are secure unit buttons, and a
-- child of one can be protected with it. SetScale on a protected frame in
-- lockdown raises, and the two events below are a monitor swap and a windowed
-- resize, either of which can land in the middle of a pull.
--
-- Adopt itself is not guarded, and does not need to be. It runs when a frame is
-- created, and every caller that creates one under a secure button already
-- refuses in lockdown rather than building half a frame.
local deferred = setmetatable({}, { __mode = "k" })

local physical = BASE
local perfect = 1
local parentScale = 1
local supported -- probed on the first adoption

-- Windowed and fullscreen keep the answer in different CVars, and both spell it
-- "1920x1080".
local RESOLUTION_CVARS = { "gxWindowedResolution", "gxFullscreenResolution" }

local function ReadPhysicalHeight()
	if type(GetPhysicalScreenSize) == "function" then
		local ok, _, height = pcall(GetPhysicalScreenSize)
		if ok and type(height) == "number" and height > 0 then
			return height
		end
	end

	if type(GetCVar) == "function" then
		for _, cvar in ipairs(RESOLUTION_CVARS) do
			local ok, value = pcall(GetCVar, cvar)
			local height = ok and type(value) == "string" and tonumber(value:match("%d+%s*[xX]%s*(%d+)"))
			if height and height > 0 then
				return height
			end
		end
	end

	-- Neither answered, so assume the one screen height where the old
	-- arithmetic and the new agree and nothing moves.
	return BASE
end

local function Rescale(frame, zoom)
	if ns.Blocked(frame) then
		deferred[frame] = zoom
		return false
	end
	deferred[frame] = nil
	frame:SetScale(perfect * zoom)
	return true
end

-- The scale at which one unit is one physical pixel.
function UI.Scale()
	return perfect
end

function UI.ScreenHeight()
	return physical
end

-- Whether this client will let a frame off its parent's scale. Everything below
-- degrades to plain fractional units when it will not, which is the look the
-- addon had before, rather than to a wrong size.
function UI.Supported()
	return supported ~= false
end

-- One physical pixel in the units the frame is drawn in. Ask for this wherever
-- an edge is meant to be a hairline, and ask again after a reparent, because a
-- reparent can change the effective scale under it. On a frame that has been
-- adopted the answer is exactly 1 and the multiply is free.
function UI.Pixel(frame)
	local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
	if not scale or scale <= 0 then
		return 1
	end
	return BASE / (scale * physical)
end

-- How many units one pixel of the *design* occupies inside a frame.
--
-- This is not UI.Pixel, and the difference is not a nicety: confusing the two is
-- what made `bars zoom` do nothing for its entire life. UI.Pixel answers "how
-- many units is one physical pixel", which on the grid is 1/zoom. A design that
-- multiplies every one of its own numbers by that has divided itself by the
-- zoom, and the scale the zoom put on the frame multiplies it straight back. The
-- widget comes out the same physical size at zoom 1, 2 and 3, and the setting is
-- inert. That is exactly what the enemy bars did.
--
-- A design pixel is not a physical pixel. On the grid one design pixel is one
-- unit, and the zoom is what turns that unit into a 1x1, 2x2 or 3x3 block of
-- screen pixels, which is the entire point of having a zoom. Off the grid, on a
-- client with no SetIgnoreParentScale, there is no zoom and no block to make, so
-- the honest conversion is the fractional one and UI.Pixel is already it.
--
-- The rule for a caller: UI.Pixel for a hairline, an inset or anything else that
-- means one screen pixel and should stay one screen pixel when the design grows.
-- UI.Unit for every number that is a size in the design.
--
-- Answers for the frame that was adopted. Children inherit its scale, so a
-- layout asks the widget it is laying out rather than each region inside it.
function UI.Unit(frame)
	if grid[frame] then
		return 1
	end
	return UI.Pixel(frame)
end

-- A measurement snapped to a whole number of pixels. Anything that grows to fit
-- its own text goes through this: a font string is measured in fractions, and a
-- box sized to one lands its border half on a pixel and half off, which is the
-- one place the grid cannot help because the number arrived from outside it.
function UI.Round(frame, size)
	local px = UI.Pixel(frame)
	local pixels = math.floor(size / px + 0.5)
	if pixels < 1 and size > 0 then
		pixels = 1
	end
	return pixels * px
end

-- The nearest whole unit, negatives included, which inside an adopted frame is
-- the nearest physical pixel.
--
-- Not UI.Round, which is a different question with a similar name and is why
-- seven files wrote their own rather than reusing it. Round takes a size that
-- arrived from outside the grid and snaps it to a whole number of pixels,
-- refusing to return zero because a hairline asked for and not drawn is a
-- missing line. This takes a coordinate, where zero is the left edge and a
-- floor at one would be a bug.
--
-- Every anchor offset the addon saves goes through it. A drag lands wherever
-- the cursor was, and a frame whose own origin sits on a fraction rasterises
-- every edge, icon and glyph inside it across two rows of pixels.
function UI.Whole(value)
	return math.floor(value + 0.5)
end

-- A value measured in one frame's units, expressed in another's. Two frames on
-- different scales are the normal case now, not the exception: our widget sits
-- on the grid and the nameplate it is anchored to does not, so a width read off
-- the plate means nothing until it has been through here.
function UI.Convert(size, from, to)
	local fromScale = ns.Measure(from, "GetEffectiveScale")
	local toScale = to and to.GetEffectiveScale and to:GetEffectiveScale()
	if not size or not fromScale or not toScale or toScale <= 0 then
		return size
	end
	return size * fromScale / toScale
end

-- Put a frame on the grid. Zoom multiplies the whole thing, and one unit
-- becomes zoom physical pixels. It exists because the pixel sizes below are
-- absolute: a 21 pixel bar is 21 pixels on every monitor, which is the point,
-- and on a 4K panel that is small.
--
-- A whole zoom keeps the grid. At 2 one unit is a 2x2 block of pixels and every
-- edge still lands on a boundary. A fractional one does not, and the addon
-- allows it in exactly one place: UI.Size, the size slider in the settings
-- panel, where the player has asked for a window between the whole steps and
-- softer edges are the price they chose to pay. Nothing else passes a fraction
-- here, and the enemy bars refuse one outright.
function UI.Adopt(frame, zoom)
	if supported == nil then
		supported = type(frame.SetIgnoreParentScale) == "function"
	end
	if not supported then
		return false
	end
	grid[frame] = zoom or 1
	frame:SetIgnoreParentScale(true)
	frame:SetScale(perfect * (zoom or 1))
	return true
end

-- There was a UI.ZoomOf here, which walked up from a region to whichever
-- ancestor was adopted and answered what zoom it was drawn at. It had one
-- caller ever: the tooltip, matching itself to the widget under the cursor.
-- That rule is gone. A tooltip is drawn at the addon's own size now, so nothing
-- in the addon asks what somebody else's frame is scaled to, and a query with
-- no callers is a thing the next reader has to work out the purpose of.

function UI.Rezoom(frame, zoom)
	if not grid[frame] then
		return false
	end
	zoom = zoom or 1
	if grid[frame] == zoom then
		return false
	end
	grid[frame] = zoom
	return Rescale(frame, zoom)
end

-- Whatever combat refused. Clearing a key during the walk is the one table
-- mutation Lua allows mid traversal, and a frame still blocked keeps the key it
-- already has rather than gaining a new one, so neither branch breaks it.
function UI.Flush()
	if not next(deferred) then
		return false
	end
	for frame, zoom in pairs(deferred) do
		Rescale(frame, zoom)
	end
	UI.Notify()
	return true
end

-- Run when the grid moves under everything, so a module can lay itself out
-- again. Registered once at load, never removed.
function UI.OnRescale(callback)
	listeners[#listeners + 1] = callback
end

-- Tell every listener the ground moved. Three things move it and all three
-- mean the same thing to a window: lay yourself out again. The screen changes
-- size, combat lets go of a frame that refused to be rescaled, or the player
-- drags the UI size slider. Exported rather than left as a local loop because
-- the third of those is a setting and settings live outside this file.
function UI.Notify()
	for i = 1, #listeners do
		listeners[i]()
	end
end

-- Both halves matter. The screen height moves the grid itself, so every
-- adopted frame is re-scaled. The UI scale moves nothing on the grid, because
-- an adopted frame is off its parent's scale by construction, but it does move
-- every frame on a client that has no SetIgnoreParentScale, and it moves the
-- nameplates our bars are anchored to either way. So a change in either one
-- tells the listeners to lay out again.
function UI.Refresh()
	local height = ReadPhysicalHeight()
	local scale = UIParent:GetEffectiveScale()
	if height == physical and scale == parentScale then
		return false
	end

	if height ~= physical then
		physical = height
		perfect = BASE / height
		for frame, zoom in pairs(grid) do
			Rescale(frame, zoom)
		end
	end
	parentScale = scale

	UI.Notify()
	return true
end

function UI.Describe()
	if supported == false then
		return ("%d pixels tall, but this client has no SetIgnoreParentScale, so frames stay on the UI scale: edges are one pixel wide and land wherever the frame does")
			:format(physical)
	end
	return ("%d pixels tall, one unit is one pixel at scale %.4f"):format(physical, perfect)
end

physical = ReadPhysicalHeight()
perfect = BASE / physical
parentScale = UIParent:GetEffectiveScale()

-- The resolution is readable at load, but a windowed client that is resized and
-- a monitor that is swapped both move it afterwards, and neither fires anything
-- else the addon listens to.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("UI_SCALE_CHANGED")
watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		UI.Flush()
		return
	end
	UI.Refresh()
end)
