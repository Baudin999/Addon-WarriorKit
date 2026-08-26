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
-- The holders are not hidden. Bar 1's twelve are parented to
-- MainMenuBarArtFrame along with the micro menu and the bag bar, and hiding
-- that takes all three, which is the warning Artwork.lua already carries.
--
-- They are silenced instead, and that is the whole of the bar 1 drop bug.
--
-- A hidden button takes no mouse. The frame it was standing on is not hidden,
-- and on this client `MainActionBar` is mouse enabled in the TOOLTIP strata,
-- which is the top one there is: it sits invisible across the bottom of the
-- screen with its art stripped, above every strata a bar of ours could stand
-- in, and it takes every drop aimed at bar 1. `/wk actionbars trace` printed it
-- in one line after two fixes had guessed at frame levels, which is a number
-- that cannot win an argument with a strata.
--
-- So the mouse comes off it, not the frame off the screen. Nothing that frame
-- does with a click is anything the player wanted: it has no drag handler and
-- no click handler, it exists to stop a press reaching the world, and our own
-- bar standing over it does that job now. The micro menu and the bag bar are
-- children with a mouse of their own and are untouched, because EnableMouse is
-- per frame and never inherited.
--
-- Walked up from the buttons rather than named. The frame that took the drop is
-- an ancestor of the button it was standing on, whatever it happens to be
-- called on whichever client this is, and only an ancestor that actually takes
-- the mouse is touched: the four multi-bars are declared with no enableMouse at
-- all and stay exactly as they were found. UIParent ends the walk, because
-- silencing that is silencing the interface.
--
-- Only the buttons of bars this file actually cloned are touched. Hiding a bar
-- the player has switched off would mean the off switch showed it, and an off
-- switch that turns something on is worse than one that does nothing.
--------------------------------------------------------------------------

-- Every button of theirs this file has put out of sight, so the off switch
-- knows exactly what to put back and nothing else. Keyed by frame rather than
-- by name, because a name is resolved once and a frame is the thing.
local hidden = {}

-- Every frame this file took the mouse off, so the off switch hands back
-- exactly those and nothing else. A frame that was already deaf when we found
-- it never lands here and never gets a mouse it did not have.
local deafened = {}

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

-- The mouse off one frame, and back on. Same contract as Banish and Restore:
-- false means combat refused it and the caller can report a partial job.
local function Deafen(frame)
	if ns.Blocked(frame) then
		return false
	end
	frame:EnableMouse(false)
	return true
end

local function Hear(frame)
	if ns.Blocked(frame) then
		return false
	end
	frame:EnableMouse(true)
	return true
end

-- Every frame above one button, collected into `wanted`.
--
-- Stops at UIParent and at a frame with no parent, so the walk cannot reach the
-- interface itself.
--
-- Every ancestor is collected and not only the ones taking the mouse right now,
-- which is the difference between a switch and a loop. The pass below silences
-- the ones that are listening; a pass after that would find them deaf, leave
-- them out, and hand the mouse straight back to the frame it had just taken it
-- from. Whether a frame is worth silencing is decided once, at the moment it is
-- silenced, and remembered in `deafened`.
local function Above(frame, wanted)
	local step = frame and frame.GetParent and frame:GetParent()
	while step and step ~= UIParent do
		wanted[step] = true
		step = step.GetParent and step:GetParent() or nil
	end
end

-- Exactly these hidden and every other one handed back.
--
-- Takes global frame names rather than walking the bars itself, so the file
-- that decided which bars it was cloning is the only file that knows, and this
-- one only knows how to hide a button without taking its taint with it.
--
-- One call rather than a hide and a show, because the two halves have to agree
-- and there is a switch per bar that can move a button from one side to the
-- other. A bar unticked in the panel stops naming its twelve here, and the same
-- pass that stops hiding them is the pass that gives them back; nothing has to
-- remember which bar they came from.
function Theirs.Only(names)
	local wanted, above = {}, {}
	for index = 1, #names do
		local frame = _G[names[index]]
		if frame then
			wanted[frame] = true
			Above(frame, above)
		end
	end

	local complete = true
	for frame in pairs(hidden) do
		if not wanted[frame] then
			if Restore(frame) then
				hidden[frame] = nil
			else
				complete = false
			end
		end
	end
	for frame in pairs(wanted) do
		if not hidden[frame] then
			if Banish(frame) then
				hidden[frame] = true
			else
				complete = false
			end
		end
	end

	-- And the frames those buttons stand on, which is where the drops went.
	-- Handed back first for the same reason the buttons are: a bar unticked in
	-- the panel stops naming its twelve, so the same pass that stops silencing
	-- its holder is the pass that gives the mouse back.
	for frame in pairs(deafened) do
		if not above[frame] then
			if Hear(frame) then
				deafened[frame] = nil
			else
				complete = false
			end
		end
	end
	for frame in pairs(above) do
		if not deafened[frame] and type(frame.IsMouseEnabled) == "function"
			and frame:IsMouseEnabled() then
			if Deafen(frame) then
				deafened[frame] = true
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
	for frame in pairs(deafened) do
		if Hear(frame) then
			deafened[frame] = nil
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
	-- The same question for the holders. ACTIONBAR_SHOWGRID is one of the
	-- events this runs on and is exactly the moment the client tidies its own
	-- bars for a cursor with something on it, which is the moment a mouse
	-- handed back costs the drop that was already on its way.
	for frame in pairs(deafened) do
		if type(frame.IsMouseEnabled) == "function" and frame:IsMouseEnabled()
			and not ns.Blocked(frame) then
			Deafen(frame)
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

-- How many of Blizzard's own frames are standing there with their mouse off.
-- Counted separately from the buttons because they are a different claim on the
-- client's interface and because a status line that added them together would
-- report sixty-one buttons hidden.
function Theirs.Deafened()
	local count = 0
	for _ in pairs(deafened) do
		count = count + 1
	end
	return count
end
