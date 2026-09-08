local ADDON, ns = ...

local Artwork = {}
ns.Artwork = Artwork

-- Strips the 2007 furniture off the action bars: the two gryphons, the riveted
-- metal strip behind bar 1, the page arrows and the page number. None of it
-- carries information, and a row of icons only reads as a row of icons once it
-- is gone. On by default, because that is the look the loadout was designed
-- for, and reversible in one call because every other part of this addon is.
--
-- Five rules shape the file.
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
--   StatusTrackingBarManager are deliberately absent from all three lists.
--
--   A named region goes through the attic, a walked one does not. ns.Strip
--   puts a region's own Hide where its Show was and loses to SetShown, which is
--   resolved in C and reads no Lua field. Core/Attic.lua re-parents into a
--   frame that can never be shown, which no call on the frame itself undoes,
--   and Core/BlizzHide.lua's sweep then keeps it there for free. The attic
--   refuses a texture, so the endcaps fall back to ns.Strip inside the same
--   call and neither list has to know which of the two this client made them.
--
--   The textures inside the holders keep ns.Strip for a reason of their own. A
--   texture is a region of the frame it was created on and re-parenting one
--   takes it out of that frame's draw order rather than off the screen, which
--   is the rule Core/Attic.lua's own header states.
--
--   A name is not the only handle, and on this client it is not the one that
--   matters. The page arrows and the page number are three regions of a frame
--   reached by parentKey and nothing else, so ART_KEYS below is a third list
--   rather than five more spellings in the second. Its own comment says which
--   key, where the key is written down, and why this one is not cleared off its
--   owner the way Core/BlizzHide.lua clears the target's cast bar.

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
}

-- What this client hangs off a frame instead of off a global.
--
-- The page switcher is one frame with three regions in it. Blizzard_ActionBar
-- /Classic/MainActionBar.xml declares `ActionBarPageNumber` as a parentKey on
-- MainActionBar and puts Text, UpButton and DownButton inside it, and not one
-- of the four has a name a `_G` lookup can find. Both clients this addon ships
-- for declare it that way.
--
-- That is why the switch left the arrows on the screen in its default state and
-- nothing said so. This list used to name MainMenuBarPageNumber,
-- ActionBarUpButton, ActionBarDownButton and the two sliding stance textures,
-- which is what those four were called before the action bars were rewritten;
-- all five resolve to nil on both clients, so the walk skipped them, `found`
-- never counted them and the status line reported a clean strip of the two
-- endcaps. Five names that cannot match anything are deleted rather than left
-- as insurance, because insurance that has never once paid out is the thing
-- that made this take a screenshot to find.
--
-- One key, not several, which is the rule Core/BlizzHide.lua states for the
-- same mechanism: a key is read straight off a frame this addon does not own,
-- so a guess that lands on the wrong field hides something nobody asked to
-- hide. This one is written from the XML rather than guessed.
--
-- The key stays on the owner, which is where this differs from
-- Core/BlizzHide.lua's use of the same idea. That file clears the field so the
-- client stops reaching for a frame it can no longer see. Here the client must
-- keep reaching: MainActionBar's own mixin writes to self.ActionBarPageNumber
-- in four places with nothing guarding it, so clearing the field would trade a
-- visible arrow for a Lua error on every page change. The cage is enough. It
-- can be written to all it likes up there, and the font string goes with its
-- parent, which is why the page number needs no handle of its own.
local ART_KEYS = {
	{ owner = "MainActionBar", key = "ActionBarPageNumber" },
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

	-- Picked once rather than branched on per region, which keeps both walks at
	-- the depth the holders' walk above them already sits at.
	local move = hide and ns.Attic.Vanish or ns.Attic.Return
	for _, name in ipairs(ART_REGIONS) do
		local region = _G[name]
		if region then
			found = found + 1
			if not move(region) then
				complete = false
			end
		end
	end

	for _, slot in ipairs(ART_KEYS) do
		local owner = _G[slot.owner]
		local region = type(owner) == "table" and owner[slot.key] or nil
		if type(region) == "table" then
			found = found + 1
			if not move(region) then
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
