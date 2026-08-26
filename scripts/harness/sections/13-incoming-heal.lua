-- The incoming heal on the health gauge
--
-- Three states, because the arithmetic is only worth testing at its edges:
-- nothing on the way draws nothing, a heal that fits inside what is missing
-- draws its own share of the gauge, and a heal that does not fit draws what is
-- missing and not one pixel further.
--
-- The rail is measured off the block that landed rather than off the setting
-- that asked for it, which is the same rule the rest of this section works
-- under: a test written against skinWidth would be asserting the request and
-- not the answer.

local H = ...
local state = H.state
local ns, check = H.ns, H.check
local playerBox, skinSlice, skinTicker = H.carry.playerBox, H.carry.skinSlice, H.carry.skinTicker

local healSlice = skinSlice(_G.PlayerFrame.healthbar)
check(healSlice ~= nil, "the skin drew no incoming heal slice on the health bar")

local sliceAnchor = healSlice and healSlice.points and healSlice.points[1]
check(sliceAnchor ~= nil and sliceAnchor[2] == _G.PlayerFrame.healthbar.fill,
	"the heal slice is not pinned to the health bar's own fill texture, so it starts"
	.. " wherever the two scales happen to agree rather than where the bar stops")

-- A whole refresh interval per call, because the ticker only does the work
-- every fifth of a second and a heal set between two of those is a heal the
-- frame has not been told about yet.
local function healTick(amount)
	state.incomingHeals = amount
	skinTicker.scripts.OnUpdate(skinTicker, 0.25)
	if not healSlice.shown then
		return 0
	end
	-- Back into pixels, because the slice is a region of Blizzard's health bar
	-- and its width is written in that bar's units. That is the boundary this
	-- part is built on and the reason the number is asserted here at all: the
	-- span is worked out in whole pixels of the gauge and multiplied by one
	-- pixel in the bar's units on the way out, so dividing by the same figure
	-- is what the client will have drawn.
	return healSlice:GetWidth() / ns.UI.Pixel(_G.PlayerFrame.healthbar)
end

-- The gauge is the block less the portrait's square and the one pixel it is
-- inset by on its outer edge. Whole pixels, because the player block is on the
-- grid and that was asserted above.
local railPixels = playerBox:GetWidth() - playerBox:GetHeight() - 1
local MISSING = 9000 - 4200

check(healTick(0) == 0, "a unit with no heal on the way still draws a slice")

local fits = math.floor(1800 / 9000 * railPixels + 0.5)
local drawn = healTick(1800)
check(math.abs(drawn - fits) < 1e-9,
	("a 1800 heal on a 9000 unit drew %.2f px of a %d px gauge, expected %d")
		:format(drawn, railPixels, fits))
check(math.abs(drawn - math.floor(drawn + 0.5)) < 1e-9,
	"the heal slice is a fraction of a pixel wide")

local capped = math.floor(MISSING / 9000 * railPixels + 0.5)
local over = healTick(999999)
check(math.abs(over - capped) < 1e-9,
	("a heal far past what the unit is missing drew %.2f px, expected the %d px it is down")
		:format(over, capped))
check(capped < railPixels,
	"the clamp let an overheal cover the whole gauge, which says the unit is at full")

check(healTick(0) == 0, "the slice stayed up after the heal it predicted landed")

print(("heals  gauge %d px, 1800 of 9000 draws %d px, an overheal clamps to %d px")
	:format(railPixels, fits, capped))

-- Left for the sections below.
H.carry.capped, H.carry.drawn = capped, drawn
