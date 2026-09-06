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

-- Where the frame ended up, in whole units, handed to whoever named the
-- setting. Shared by the two drags below, because a secure drag lands in the
-- same place an ordinary one does.
local function Landed(place, frame)
	place.placed = true
	if not place.moved then
		return
	end
	local point, _, relativePoint, x, y = frame:GetPoint()
	place.moved({ point, "UIParent", relativePoint, UI.Whole(x), UI.Whole(y) })
end

-- The four attributes a secure drag writes, and the snippet that reads them.
--
-- The restricted environment does not carry StartMoving. It was written here as
-- though it did, and every drag on the character sheet ended in "attempt to call
-- a nil value" out of RestrictedExecution. What it does carry is SetPoint, and
-- that is enough: a frame the client refuses to let an addon move in combat is
-- one a snippet may still place, so a secure drag is a point written once a
-- frame rather than a move the client runs on our behalf.
--
-- A snippet cannot read a cursor, a scale or a Lua table, so the insecure half
-- does that arithmetic and hands the answer over as attributes. That is what
-- attributes are for: they are the way a value gets from insecure code into the
-- restricted environment, and the environment decides what may be done with it.
--
-- Four of them rather than one string, because this runs once a frame for as
-- long as the button is down and a string is a fresh object every time. Numbers
-- are not. The two corner names are written once at the grab, the two offsets
-- whenever they change, and the count last: it is what the snippet acts on, it
-- is different every time, and a snippet that hung off the offsets themselves
-- would sit still through a drag straight up the screen, where y moves and x
-- never does.
--
-- The count belongs to the frame and not to the grab that is pushing it. It
-- used to start again at zero every time you took hold of the window, so a
-- one-unit nudge wrote 1, and the next drag's first unit wrote 1 again, which
-- is not a change and ran no snippet: the window sat still until the cursor had
-- gone a second unit. Place below writes through the same count, and a saved
-- anchor put back at login has no grab behind it at all.
local MOVE = [[
	if name ~= "wk-move" then return end
	local point = self:GetAttribute("wk-point")
	if not point then return end
	self:ClearAllPoints()
	self:SetPoint(point, self:GetFrameRef("screen"), self:GetAttribute("wk-rel"),
		self:GetAttribute("wk-x"), self:GetAttribute("wk-y"))
]]

-- Where the frame would sit if it were where the cursor has dragged it to.
--
-- Whole units, because that is the number Landed writes into the setting, and a
-- drag that saved a different number than it drew is a window that jumps on the
-- next login. The cursor answers in physical pixels, the offsets are in the
-- frame's own units, and the scale between them is the division here.
--
-- Nothing is written unless the point has moved. A cursor spends most of a drag
-- inside the unit it was in a frame ago, and a point that has not changed is a
-- snippet run and a re-anchor for nothing.
local function Push(place, frame)
	local grab = place.grabbed
	local cursorX, cursorY = GetCursorPosition()
	local scale = frame:GetEffectiveScale()
	local x = UI.Whole(grab.x + cursorX / scale - grab.x0)
	local y = UI.Whole(grab.y + cursorY / scale - grab.y0)
	if x ~= grab.lastX or y ~= grab.lastY then
		grab.lastX, grab.lastY = x, y
		place.moves = place.moves + 1
		frame:SetAttribute("wk-x", x)
		frame:SetAttribute("wk-y", y)
		frame:SetAttribute("wk-move", place.moves)
	end
end

-- What the ticker calls. A named function at the top of the file rather than a
-- closure inside the drag, so that the whole of what a tick reaches is a name
-- check.sh can hold to the allocation rule, which is the rule this drag would
-- break first: it is the only ticker in the addon that runs while a window is
-- under the cursor rather than while a fight is on.
local function Follow(frame)
	Push(frame.placing, frame)
end

-- The drag itself: where the frame was and where the cursor was when it was
-- grabbed, and then that pair pushed at the snippet for as long as the button
-- is down. The Lua half may do all of this in a fight. Reading a cursor and
-- writing an attribute are not protected acts. Only the SetPoint at the far end
-- is, and that one happens inside the snippet.
--
-- The drag is taken by the grip where one is named and by the frame where none
-- is. A window is grabbed by its own chrome, so the frame is the grip. A bar
-- is squares from edge to edge, and a drag started on a square is a drag of
-- what the square holds, so the bar names a strip along its edge and the
-- strip is what the client delivers the drag to; the scripts still act on the
-- frame, which is the thing being moved.
local function Secure(place, frame, grip)
	frame.placing = place
	place.moves = 0
	frame:SetFrameRef("screen", UIParent)
	frame:SetAttribute("_onattributechanged", MOVE)

	grip:SetScript("OnDragStart", function()
		local point, _, relativePoint, x, y = frame:GetPoint()
		local cursorX, cursorY = GetCursorPosition()
		local scale = frame:GetEffectiveScale()
		place.grabbed = { x = x, y = y,
			x0 = cursorX / scale, y0 = cursorY / scale }
		frame:SetAttribute("wk-point", point)
		frame:SetAttribute("wk-rel", relativePoint)
		frame:SetScript("OnUpdate", Follow)
	end)

	grip:SetScript("OnDragStop", function()
		frame:SetScript("OnUpdate", nil)
		if not place.grabbed then
			return
		end
		-- Once more on the way out, because the last OnUpdate ran a frame before
		-- the button came up and the window would land a cursor's worth short of
		-- where it was dropped.
		Push(place, frame)
		place.grabbed = nil
		Landed(place, frame)
	end)
end

-- The half both drags share on the way out: the rim a frame with no chrome
-- wears while it is being placed, and the drag the client has to be told to
-- deliver at all.
local function Finish(place, frame, opts)
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
		place.grip:RegisterForDrag("LeftButton")
	end

	return place
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

	place.secure = opts.secure == true

	-- What the drag is delivered to. The frame itself, unless a secure caller
	-- names a strip of its own; Secure says why one would.
	place.grip = frame
	if opts.grip then
		assert(place.secure, "UI.Placeable: a grip is only for a frame dragged from a snippet")
		place.grip = opts.grip
	end

	frame:SetMovable(true)
	frame:SetClampedToScreen(true)

	-- A frame with a protected frame inside it may not be moved by an addon in
	-- combat, which is the same rule that keeps it from being shown: the client
	-- applies a protected frame's restrictions to its parent and to whatever it
	-- is anchored to. A snippet may move it, so a secure frame is placed from one
	-- above rather than dragged by the client. UI/Window.lua is the one caller
	-- and the character sheet is the one window: it has nineteen secure squares
	-- on its gear page, and a sheet you can open mid pull and not move is half a
	-- window.
	--
	-- The lock cannot reach one. A snippet has no way to read a Lua flag, so a
	-- lockable secure frame would be one the lock only half held. Nothing wants
	-- that combination, and saying so here is cheaper than finding out in a
	-- fight.
	if place.secure then
		assert(not place.lockable,
			"UI.Placeable: a secure frame is dragged from a snippet, which the lock cannot reach")
		Secure(place, frame, place.grip)
		return Finish(place, frame, opts)
	end

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
		Landed(place, self)
	end)

	return Finish(place, frame, opts)
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

-- Put the frame back where an anchor says it was.
--
-- The other half of moved. A frame that writes down where it was dropped and
-- has no way to be told again next login is a frame that saved nothing, and
-- until this existed the one window that remembered its corner did the SetPoint
-- longhand at the far end of its own Apply.
--
-- Which of the two drags this frame has decides how. A plain frame is anchored
-- outright. A secure one goes through the snippet, because a window with a
-- protected frame in it may not be re-anchored by an addon in a fight and the
-- character sheet is opened mid pull: the same four attributes the drag writes,
-- pushed once instead of once a frame.
--
-- The setting is not written back. This is the anchor coming out of it.
function Placeable:Place(anchor)
	local frame = self.frame
	self.placed = true
	if not self.secure then
		frame:ClearAllPoints()
		frame:SetPoint(anchor[1], UIParent, anchor[3], anchor[4], anchor[5])
		return
	end
	self.moves = self.moves + 1
	frame:SetAttribute("wk-point", anchor[1])
	frame:SetAttribute("wk-rel", anchor[3])
	frame:SetAttribute("wk-x", anchor[4])
	frame:SetAttribute("wk-y", anchor[5])
	frame:SetAttribute("wk-move", self.moves)
end

-- Whether the player has put this frame anywhere, by a drag or by an anchor out
-- of the account file.
--
-- One caller and it is UI/Window.lua. A window that sizes itself off the
-- monitor has to place itself off the monitor too, and it does that out of
-- every resize, because the resize is where a monitor swap and a zoom both
-- land. A frame the player has already moved must not be caught by that: a
-- sheet that walked back to the corner it ships in every time the zoom slider
-- moved would be a sheet with a drag that does not hold.
function Placeable:Placed()
	return self.placed == true
end

-- Who to tell, when the frame is told after it is built.
--
-- opts.moved is the usual way and it stays: eleven frames know which setting
-- they are for at the moment they are made. A window does not. It is built by
-- UI.Window out of a name, a size and a title, and the part above it is what
-- decides that this window is one of the ones that remembers its corner, which
-- it can only say once it has the window in its hand.
function Placeable:OnMoved(moved)
	self.moved = moved
end
