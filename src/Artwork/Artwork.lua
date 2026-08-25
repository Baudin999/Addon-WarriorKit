local ADDON, ns = ...

local Artwork = {}
ns.Artwork = Artwork

-- Strips the 2007 furniture off the action bars: the two gryphons, the riveted
-- metal strip behind bar 1, the page arrows and the page number. None of it
-- carries information, and a row of icons only reads as a row of icons once it
-- is gone. On by default, because that is the look the loadout was designed
-- for, and reversible in one call because every other part of this addon is.
--
-- Three rules shape the file.
--
--   Textures go, frames stay. Bar 1, the micro menu and the bag bar are all
--   anchored to MainMenuBarArtFrame in both saved Edit Mode layouts, so hiding
--   that frame would take them with it. Its textures are hidden one by one and
--   the frame stays where the anchors expect to find it.
--
--   Walk the regions, do not name them. This client is a hybrid: TBC art under
--   a backported Edit Mode, so a texture global the wiki names may not be the
--   one 2.5.6 has. GetRegions cannot go stale, and every name below is resolved
--   through _G so a missing one is a skipped entry rather than an error.
--
--   The experience bar is not artwork. MainMenuExpBar and
--   StatusTrackingBarManager are deliberately absent from both lists.

--------------------------------------------------------------------------
-- What gets stripped
--------------------------------------------------------------------------

-- Every texture these frames own. The frames themselves are left alone.
local ART_HOLDERS = {
	"MainMenuBar",
	"MainMenuBarArtFrame",
	"MainMenuBarArtFrameBackground",
}

-- Whole regions, which carry nothing but themselves. Endcaps appear here as
-- well as inside the holders above because clients disagree about whether they
-- are child textures or frames of their own; ns.Strip is idempotent, so being
-- caught twice costs nothing.
local ART_REGIONS = {
	"MainMenuBarLeftEndCap",
	"MainMenuBarRightEndCap",
	"MainMenuBarPageNumber",
	"ActionBarUpButton",
	"ActionBarDownButton",
	"SlidingActionBarTexture0",
	"SlidingActionBarTexture1",
}

--------------------------------------------------------------------------

local found, pending = 0, false

-- pcall guarded for the same reason ns.Measure is: a frame the addon does not
-- own may refuse a call that looks harmless, and a screenful of errors is worse
-- than a piece of art that stayed visible.
local function EachTexture(frame, apply)
	if not frame or type(frame.GetRegions) ~= "function" then
		return true
	end
	local ok, regions = pcall(function(target)
		return { target:GetRegions() }
	end, frame)
	if not ok or not regions then
		return true
	end

	local complete = true
	for _, region in ipairs(regions) do
		if type(region) == "table" and region.GetObjectType
			and region:GetObjectType() == "Texture" then
			found = found + 1
			if not apply(region) then
				complete = false
			end
		end
	end
	return complete
end

-- Returns false when combat blocked part of the work, so Apply can come back
-- for the rest at PLAYER_REGEN_ENABLED.
local function Sweep(hide)
	local function apply(region)
		if hide then
			return ns.Strip(region)
		end
		return ns.Unstrip(region)
	end

	found = 0
	local complete = true

	for _, name in ipairs(ART_HOLDERS) do
		if not EachTexture(_G[name], apply) then
			complete = false
		end
	end

	for _, name in ipairs(ART_REGIONS) do
		local region = _G[name]
		if region then
			found = found + 1
			if not apply(region) then
				complete = false
			end
		end
	end

	return complete
end

function Artwork.Apply()
	-- The house rule: every entry point tolerates being called before the saved
	-- variables exist, the same way each frame-owning part nil guards its frame.
	if not ns.db then
		return
	end
	pending = not Sweep(not ns.db.blizzArt)
end

-- How many regions the last sweep touched. Zero means every name in both lists
-- is absent, which is the answer worth seeing: it says this client calls the
-- art something else rather than that the art is already gone.
function Artwork.Found()
	return found
end

function Artwork.Deferred()
	return pending
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		Artwork.Apply()
	elseif pending then
		Artwork.Apply()
	end
end)
