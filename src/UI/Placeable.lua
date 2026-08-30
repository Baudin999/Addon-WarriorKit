local ADDON, ns = ...

local UI = ns.UI

--------------------------------------------------------------------------
-- A frame you can unlock, drag, and find again next login
--
-- Twelve parts of this addon put a rectangle on the world that the player is
-- allowed to move, and until this file existed every one of them wrote the
-- same block to do it: SetMovable, SetClampedToScreen, a drag that refuses
-- while the frames are locked, a drag stop that reads the point back, rounds
-- the offsets and writes them into a setting, and a Lock that toggles
-- RegisterForDrag. Nine of them also drew a rim over the whole frame and a
-- name above it, because a frame with no chrome and nothing in it is a piece
-- of empty screen you would otherwise have to find from memory.
--
-- Nothing was wrong at any one site, which is exactly why it reached twelve.
-- It is the story the tooltip rule in scripts/check.sh was written for, a
-- second time, and the clone scan found two of the copies matching character
-- for character, comments and all: Cooldowns/Row.lua and Swing/Gauges.lua
-- carried the same note about a drag landing wherever the cursor was, with one
-- noun changed.
--
-- The split that let it happen was chrome. UI.Window owns the background, the
-- hairline, the title bar and the close box, and it owned a broken half of the
-- placing too: it made every window movable and then had nowhere to put the
-- result, so the one window that has to remember where it sits overwrote the
-- scripts UI.Window had just installed with a thirteenth copy of them. Chrome
-- is not the axis. Placing is one thing, chrome is another, six frames want
-- both, six want only the first, and UI.Window is a caller of this file rather
-- than a rival to it.
--
-- What this does not know is which setting it is writing. The caller passes a
-- function that takes the finished anchor, because this layer is not allowed
-- to know the name of a setting, which is the rule UI.Size and the tooltip's
-- dock are both already written to. Whether the frames are locked arrives the
-- same way, as the argument to Lock, so ns.db stays out of src/UI/ entirely.
--------------------------------------------------------------------------

local Placeable = {}
Placeable.__index = Placeable

-- The name above an unlocked frame, in units of the frame it hangs off.
local TITLE_GAP = 2

-- Frames that have no chrome of their own get a rim and a name while they are
-- being placed, and take the mouse only for as long as that lasts. Both halves
-- of that are opts.name.
--
-- Mouse only while unlocked, because a mouse enabled frame swallows every
-- button that lands on it, including the right button drag that turns the
-- camera, and these sit over the middle of the screen where that drag starts.
-- A frame with chrome is the opposite case: it has controls in it, it answers
-- the mouse all the time, and it is grabbable by the bar across its top, so it
-- passes no name and this leaves its mouse alone.
--
-- The label is at the outline floor rather than at the panel's body size. It
-- is drawn over the world while the frame is being placed, so it has to carry
-- a rim, and a rim costs a pixel of every stroke: at 12 it was closing up its
-- own counters to buy an edge it could not do without.
local function Marker(place, frame, name, edge)
	place.grab = UI.Box(frame, nil, edge or UI.Color.edge)
	-- Anchored rather than sized, so it follows the frame through every layout
	-- the feature does afterwards and nothing has to re-anchor it on an Apply.
	-- Three callers were doing exactly that, once per Apply, for no effect.
	place.grab:SetAllPoints(frame)
	place.grab:Hide()

	place.title = UI.Label(frame, UI.OutlineFloor(), UI.Color.heading,
		"LEFT", UI.OUTLINE)
	place.title:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0,
		TITLE_GAP * UI.Unit(frame))
	place.title:SetText(name)
	place.title:Hide()
end

-- Whether the addon's lock reaches this frame at all.
--
-- Eleven of the twelve say nothing and take the default, which is that /wk lock
-- and the panel's button decide whether they can be dragged. The five chrome
-- windows are the other case: a quest log or a mail window is a thing you open,
-- move and close again, and locking it would be locking a window rather than
-- placing a piece of the HUD. They are always movable and always were. Until
-- now that was a Lock(true) called once at build and never again, which is a
-- property of the frame written as a call nobody repeats, and the next person
-- to read it has to work out that nothing calls it a second time.
--
-- lockable = false says it instead. Lock is then a no-op the caller may still
-- call, and Unlocked answers true, because a frame the lock does not reach is
-- one you can always place.
function UI.Placeable(frame, opts)
	local place = setmetatable({}, Placeable)
	place.frame = frame
	place.moved = opts.moved
	place.combat = opts.combat
	place.lockable = opts.lockable ~= false
	place.unlocked = not place.lockable

	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetScript("OnDragStart", function(self)
		-- RegisterForDrag already refuses this while locked. The flag is read
		-- again because a frame that starts moving and is never told to stop
		-- follows the cursor for the rest of the session, and being sure costs
		-- one comparison on a drag.
		if not place.unlocked then
			return
		end
		-- Some frames are secure and cannot be moved in combat at all. Asked of
		-- the caller rather than assumed, because the ones that are not secure
		-- are placeable mid pull on purpose: unlocking during a fight to nudge
		-- the swing bars is a thing people do.
		if place.combat == false and InCombatLockdown() then
			return
		end
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if not place.moved then
			return
		end
		local point, _, relativePoint, x, y = self:GetPoint()
		place.moved({ point, "UIParent", relativePoint, UI.Whole(x), UI.Whole(y) })
	end)

	if opts.name then
		-- A name and a rim are what a frame with no chrome wears while it is
		-- being placed, so a frame the lock never reaches has no state to wear
		-- them in: it would carry a rim over the world for the whole session.
		-- The two options mean opposite things about the same frame and the
		-- combination is a mistake rather than a shape anybody wants, so it
		-- fails at login where the harness reaches it rather than looking odd
		-- in somebody's game.
		assert(place.lockable,
			"UI.Placeable: a frame that is never locked cannot carry a placing rim: " .. opts.name)
		Marker(place, frame, opts.name, opts.edge)
	end

	if not place.lockable then
		frame:RegisterForDrag("LeftButton")
	end

	return place
end

-- Locked is the normal state, and unlocked is the two minutes you spend putting
-- the frame somewhere.
--
-- A no-op rather than a refusal on a frame the lock does not reach, so a part
-- that holds a mix of both can call this on all of them without asking which
-- kind each one is.
function Placeable:Lock(unlocked)
	if not self.lockable then
		return
	end
	self.unlocked = unlocked and true or false
	if self.grab then
		self.frame:EnableMouse(self.unlocked)
		self.grab:SetShown(self.unlocked)
		self.title:SetShown(self.unlocked)
	end
	if self.unlocked then
		self.frame:RegisterForDrag("LeftButton")
	else
		self.frame:RegisterForDrag()
	end
end
