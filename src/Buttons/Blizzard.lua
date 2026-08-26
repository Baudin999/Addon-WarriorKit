local ADDON, ns = ...

local Theirs = {}
ns.TheirBars = Theirs

--------------------------------------------------------------------------
-- Blizzard's own buttons
--
-- Hidden one button at a time, and deliberately NOT through ns.Strip.
--
-- ns.Strip swaps a region's Show for its Hide, which is exactly right for the
-- thing it was written for: a texture, which no protected code path ever calls
-- a method on. It is the wrong tool here and the difference is not cosmetic.
-- These are secure action buttons, and the client's own bar controller calls
-- Show on them from code that goes on to perform protected actions. An addon's
-- function executing inside that call stack taints it, and a tainted stack is
-- how you get "Interface action failed because of an AddOn" on a press,
-- halfway through a fight, with nothing on screen saying why.
--
-- Skin.lua looks like a precedent for stripping and is the opposite of one. It
-- strips regions of PlayerFrame and TargetFrame and says in its own header that
-- the frame itself is never hidden, because it is a secure unit button. The
-- rule this file follows is that same rule: strip what Blizzard draws, never
-- what Blizzard clicks.
--
-- So: statehidden and Hide, which is the channel Blizzard's own show and hide
-- logic reads, and no method on their frame is ever replaced. The cost is that
-- the client can still put a button back, on a page change or on entering the
-- world, so those events re-hide. That is a handful of Hide calls on events
-- that fire a few times a session, against a taint that is silent until it
-- costs you a taunt.
--
-- The holders are left alone. Bar 1's twelve are parented to
-- MainMenuBarArtFrame along with the micro menu and the bag bar, and hiding
-- that takes all three, which is the warning Artwork.lua already carries.
--
-- Only the buttons of bars this file actually cloned are touched. Hiding a bar
-- the player has switched off would mean the off switch showed it, and an off
-- switch that turns something on is worse than one that does nothing.
--------------------------------------------------------------------------

-- Every button of theirs this file has put out of sight, so the off switch
-- knows exactly what to put back and nothing else. Keyed by frame rather than
-- by name, because a name is resolved once and a frame is the thing.
local hidden = {}

-- One button out of sight. Returns false when combat refused it, which is the
-- same contract ns.Strip has and what lets the caller report a partial job.
local function Banish(frame)
	if ns.Blocked(frame) then
		return false
	end
	-- The documented way to tell the client's own bar code that this button is
	-- not to be shown. Written before the Hide, so a controller pass that lands
	-- between the two reads the flag rather than racing it.
	if frame.SetAttribute then
		frame:SetAttribute("statehidden", true)
	end
	frame:Hide()
	return true
end

local function Restore(frame)
	if ns.Blocked(frame) then
		return false
	end
	if frame.SetAttribute then
		frame:SetAttribute("statehidden", false)
	end
	frame:Show()
	return true
end

-- Hide every button named in the list. Takes global frame names rather than
-- walking the bars itself, so the file that decided which bars it was cloning
-- is the only file that knows, and this one only knows how to hide a button
-- without taking its taint with it.
function Theirs.Hide(names)
	local complete = true
	for index = 1, #names do
		local frame = _G[names[index]]
		if frame then
			if Banish(frame) then
				hidden[frame] = true
			else
				complete = false
			end
		end
	end
	return complete
end

-- Every button we have hidden, put back where the client can show it again.
-- Clearing a key during the walk is the one table mutation Lua allows mid
-- traversal, and a frame combat still refuses keeps the key it already has.
function Theirs.Show()
	local complete = true
	for frame in pairs(hidden) do
		if Restore(frame) then
			hidden[frame] = nil
		else
			complete = false
		end
	end
	return complete
end

-- The client put one of them back. Cheap enough to run over the whole set on
-- the few events that can do it, and guarded on IsShown so a pass that changed
-- nothing writes nothing.
function Theirs.Recheck()
	for frame in pairs(hidden) do
		if frame.IsShown and frame:IsShown() and not ns.Blocked(frame) then
			Banish(frame)
		end
	end
end

function Theirs.Count()
	local count = 0
	for _ in pairs(hidden) do
		count = count + 1
	end
	return count
end
