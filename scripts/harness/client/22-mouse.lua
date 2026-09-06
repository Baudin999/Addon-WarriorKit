-- The hand on the mouse
--
-- Every press in this harness used to be delivered by naming a script. A
-- section reached into a frame's own table, called OnClick or OnDragStart, and
-- read back what happened. That answers "does this handler do the right thing"
-- and nothing else, and the questions it cannot ask are the ones that shipped
-- bugs: is the frame on screen, does it take the mouse at all, is anything
-- lying over it, and would the client have handed it this button.
--
-- The character sheet's grip is the case worth writing down. It sat at a frame
-- level under the page it is a strip across the top of, so nothing the player
-- could aim at ever reached it and the window could not be dragged. The section
-- asserted the ordering it found, which was the broken one, and then called the
-- grip's OnDragStart by name. Both halves passed. A stub with no hit test
-- cannot tell "under the page" from "unreachable", because they are the same
-- picture to it.
--
-- So a press goes to a point on the screen and this file works out who gets it,
-- the way the client does: shown, taking the mouse, the point inside its own
-- rectangle, and the topmost of whatever is left. Topmost is strata first, then
-- frame level inside the strata, then the later frame of two at the same level,
-- which puts a child over the parent it was made from.
--
-- **The coordinate space is the one 02-text.lua measures in**, which is
-- UIParent's own corner at the origin with x to the right and y upward, in
-- physical units rather than interface ones, so a frame at a scale of its own
-- can be compared with a frame at another. H.mouse.Point turns a frame into a
-- point in it, and a section aiming at a widget should go through that rather
-- than write two numbers down.
--
-- **What is not modelled.** A frame with no parent chain up to UIParent is not
-- reachable here, which covers the handful of loose regions the stubs stand up
-- outside the tree. There is no drag threshold: a grab followed by a move is a
-- drag, where the client wants a few pixels of travel first. And one move of
-- the pointer runs one frame of the client for the frame under it and its
-- parents rather than for everything on screen, because a secure drag hangs its
-- follow on the frame it moves and running every ticker in the addon would be a
-- scene change rather than a mouse move.

local H = ...

local input, raw = H.input, H.raw

-- Which strata is over which. The client's own order, and the reason a cloned
-- action bar could not be raised over MainActionBar by any frame level: that
-- frame sits in TOOLTIP, which is the top of this list.
local ORDER = {
	WORLD = 1, BACKGROUND = 2, LOW = 3, MEDIUM = 4, HIGH = 5,
	DIALOG = 6, FULLSCREEN = 7, FULLSCREEN_DIALOG = 8, TOOLTIP = 9,
}

-- The drag in flight: what took it, which button, and whether the grab found a
-- frame registered for one.
local held = {}

local function scale()
	return _G.UIParent:GetEffectiveScale()
end

-- A frame's rectangle in physical units, hit rect insets taken off.
--
-- The insets are the client's way of making a button answer over less than it
-- draws, and they are the difference between a square you can press at its
-- corner and one you cannot, so they belong in the test rather than beside it.
local function rect(frame)
	local own = frame:GetEffectiveScale()
	local left, top = frame:GetLeft() * own, frame:GetTop() * own
	local l, r, t, b = frame:GetHitRectInsets()
	left, top = left + l * own, top - t * own
	return left, top,
		left + (frame:GetWidth() - l - r) * own,
		top - (frame:GetHeight() - t - b) * own
end

local function inside(frame, x, y)
	local left, top, right, bottom = rect(frame)
	return x >= left and x <= right and y <= top and y >= bottom
end

-- Which of two frames the client would hand the press to.
local function over(frame, best)
	if not best then
		return true
	end
	local mine = ORDER[frame:GetFrameStrata()] or ORDER.MEDIUM
	local theirs = ORDER[best:GetFrameStrata()] or ORDER.MEDIUM
	if mine ~= theirs then
		return mine > theirs
	end
	if frame:GetFrameLevel() ~= best:GetFrameLevel() then
		return frame:GetFrameLevel() > best:GetFrameLevel()
	end
	return frame.serial > best.serial
end

-- Whether this frame would take that button at all.
--
-- Three separate refusals and the client keeps them apart. A frame that does
-- not answer the mouse is not there as far as the pointer is concerned. A frame
-- with the mouse on and clicks off hovers and hands every button to the world,
-- which is how a tooltip goes on something without eating the camera drag. And
-- a frame may hand one named button through and keep the rest, which is what
-- the chat rail does with the right button.
local function takes(frame, button)
	if not frame:IsMouseEnabled() then
		return false
	end
	if button == nil then
		return true
	end
	if not frame:IsMouseClickEnabled() then
		return false
	end
	return not (frame.passed and frame.passed[button])
end

local function search(frame, x, y, button, best)
	if not frame.shown then
		return best
	end
	if frame.kind ~= "texture" and frame.kind ~= "fontstring"
		and takes(frame, button) and inside(frame, x, y) and over(frame, best) then
		best = frame
	end
	local children = frame.children
	for index = 1, #children do
		best = search(children[index], x, y, button, best)
	end
	return best
end

-- Who the client would give a press of that button at that point.
--
-- Called with no button it answers who the pointer is over, which is a
-- different question: a frame can take a hover and refuse every button.
local function at(x, y, button)
	return search(_G.UIParent, x, y, button, nil)
end

-- The same question asked of one window instead of the screen.
--
-- What takes a press is a fact about the whole screen, and for most of what the
-- harness aims at that is the point: a square covered by another addon's frame
-- is a square you cannot click. It is the wrong question for a check on one
-- window's own stacking order, where the answer wanted is "the grip, and not the
-- badges drawn over it", and a second window that happens to overlap the corner
-- being aimed at turns that check into a check on where the fixtures put their
-- windows.
local function within(root, x, y, button)
	return search(root, x, y, button, nil)
end

-- A point on the screen, in the units above. Called with a frame alone it is
-- the middle of it, which is where a player aims; the two offsets are in the
-- frame's own units and are how a section aims at a corner.
local function point(frame, x, y)
	local own = frame:GetEffectiveScale()
	local left = frame:GetLeft() * own
	local top = frame:GetTop() * own
	if x or y then
		return left + (x or 0) * own, top + (y or 0) * own
	end
	return left + frame:GetWidth() / 2 * own, top - frame:GetHeight() / 2 * own
end

-- Put the pointer somewhere.
--
-- The cursor stub in 11-tooltip.lua counts up from the bottom of the screen and
-- the geometry above counts down from UIParent's top, so the screen height is
-- the constant between them. Every reader takes a difference, so the constant
-- cancels; it is added anyway, because a pointer near the top of the screen
-- should read as a big number rather than a negative one.
local function place(x, y)
	local ui = scale()
	H.cursor.x = x / ui
	H.cursor.y = y / ui + _G.GetScreenHeight()
end

-- One handler, run as a delivery so the wrapper in 01-widgets.lua lets it
-- through. Answers whether there was one.
local function deliver(frame, name, ...)
	local handler = frame and raw(frame, name)
	if not handler then
		return false
	end
	input.depth = input.depth + 1
	local ok, err = pcall(handler, frame, ...)
	input.depth = input.depth - 1
	if not ok then
		error(err, 0)
	end
	return true
end

-- One frame of the client, for one frame and its parents.
--
-- That chain is where a drag hangs its follow: UI/Placeable.lua puts an OnUpdate
-- on the window and the drag is delivered to a grip inside it, and AdHoc's bars
-- put one on the bar and take the drag on a strip along its edge. Everything
-- else on screen is left alone on purpose. Running every ticker in the addon
-- because the pointer moved would be a scene change, and a section dragging a
-- window would quietly advance the tooltip, the meters and three animations.
--
-- Which chain is the one holding the drag where there is one, and the frame
-- under the pointer otherwise. The client does not stop running a frame's
-- OnUpdate because the pointer has left it, and taking the chain from under the
-- pointer meant a window dragged by a strip stopped following the moment the
-- cursor crossed off its own chrome, which is most of a drag.
local function ticked(frame, elapsed)
	local step = frame
	while step do
		local tick = step.scripts and step.scripts.OnUpdate
		if tick then
			tick(step, elapsed)
		end
		step = step.parent
	end
end

-- What StartMoving left behind, applied at the pointer's new position. The
-- client moves the frame itself for an ordinary drag, and this is that.
local function follow()
	local moving = H.moving
	for index = 1, #moving do
		local frame = moving[index]
		local grab = frame.moving
		local own = frame:GetEffectiveScale()
		local cursorX, cursorY = _G.GetCursorPosition()
		frame:ClearAllPoints()
		frame:SetPoint(grab.point, grab.relative, grab.relativePoint,
			grab.x + cursorX / own - grab.x0, grab.y + cursorY / own - grab.y0)
	end
end

local function move(x, y, elapsed)
	place(x, y)
	follow()
	ticked(held.frame or at(x, y), elapsed or 0.016)
end

-- Take hold of whatever is under the point.
--
-- OnMouseDown first, because the client fires that for every button on a frame
-- that answers the mouse whether or not it registered a drag. OnDragStart only
-- where RegisterForDrag named this button, which is the gate this whole file
-- was written for: a frame that never registered answers a drag by doing
-- nothing, and until now it looked exactly like one that did.
local function grab(x, y, button)
	button = button or "LeftButton"
	place(x, y)
	local frame = at(x, y, button)
	held = { frame = frame, button = button, dragging = false }
	if not frame then
		return nil, false
	end
	deliver(frame, "OnMouseDown", button)
	if frame.dragButton ~= button then
		return frame, false
	end
	held.dragging = true
	deliver(frame, "OnDragStart", button)
	return frame, true
end

-- Let go. OnDragStop only where a drag actually started, then OnMouseUp, then
-- OnReceiveDrag on whatever the pointer is over if something is still on the
-- cursor, which is how a spell lands on a square.
local function drop(x, y)
	local frame, button = held.frame, held.button
	if x then
		move(x, y)
	end
	if held.dragging then
		deliver(frame, "OnDragStop", button)
	end
	deliver(frame, "OnMouseUp", button)
	-- OnReceiveDrag, and only with something on the cursor. The client fires it
	-- when a drag ends over a frame while the pointer is carrying a spell, an
	-- item or a macro, and a stub that fired it on every release would let a
	-- square answer a drop that never had anything in it.
	local under = x and at(x, y, button) or frame
	if under and under ~= frame and _G.GetCursorInfo() ~= nil then
		deliver(under, "OnReceiveDrag")
	end
	held = {}
	return frame
end

local function drag(x, y, toX, toY, button)
	local frame, dragging = grab(x, y, button)
	move(toX, toY)
	drop(toX, toY)
	return frame, dragging
end

-- A press and a release at one point, which is the pair a player makes.
--
-- Region:Click is what does the work, because the edge, the registration and
-- the secure half of a press are 14-secure.lua's subject and this file's job is
-- only to say which frame the press reaches. Answers the frame and what the
-- click came back with, so a section can tell "nothing there" from "there and
-- it refused the button".
local function click(x, y, button)
	button = button or "LeftButton"
	place(x, y)
	local frame = at(x, y, button)
	if not frame then
		return nil, false
	end
	local took = frame:Click(button, true)
	return frame, frame:Click(button, false) or took
end

local function wheel(x, y, delta)
	place(x, y)
	local frame = at(x, y)
	if not frame then
		return nil, false
	end
	return frame, deliver(frame, "OnMouseWheel", delta)
end

-- Where the pointer is, in the units above. The inverse of Place.
local function where()
	local ui = scale()
	return H.cursor.x * ui, (H.cursor.y - _G.GetScreenHeight()) * ui
end

-- What the client says is under the pointer, answered by the same hit test that
-- decides where a press lands.
--
-- No stub carried these and three sections stood up one of their own, which is
-- the shape of fixture that agrees with whatever the test expects. This one can
-- disagree: a frame the pointer is not over does not come back, however sure the
-- caller is.
--
-- Both names, because the client has one of them and the addon does not know
-- which: GetMouseFoci answers a stack with the topmost first and GetMouseFocus
-- answers one frame. Buttons/Trace.lua reads whichever is there and says so.
_G.GetMouseFocus = function()
	return at(where())
end

_G.GetMouseFoci = function()
	local under = at(where())
	if not under then
		return {}
	end
	return { under }
end

-- Letting go of what the pointer is carrying, over a frame.
--
-- The other half of a drag, and the half that has no grab behind it: a spell
-- dragged off the book arrives on the cursor from the client rather than from a
-- frame in the addon, and what the addon sees is a release over one of its
-- squares. The frame is aimed at like a press, so a square with something over
-- it refuses the drop the way it would in the game.
local function give(frame, atX, atY)
	local x, y = point(frame, atX, atY)
	place(x, y)
	local under = at(x, y, "LeftButton")
	if under ~= frame then
		error(("a drop aimed at %s landed on %s"):format(
			frame:GetName() or frame:GetObjectType(),
			under and (under:GetName() or under:GetObjectType()) or "nothing"), 2)
	end
	if _G.GetCursorInfo() == nil then
		error("a drop was made with nothing on the cursor", 2)
	end
	deliver(under, "OnReceiveDrag")
	return under
end

-- Aim at a widget and press it. The middle of it, unless the caller names a
-- corner: a window is pressed on its title bar rather than on the page inside
-- it, the same way it is grabbed there.
--
-- The convenience every section wants, and it keeps the thing a section used to
-- skip: the press still goes to a point and the stub still works out who gets
-- it. Where that is not the widget aimed at, this stops the run and names what
-- was in the way, because a button under something else is a button the player
-- cannot press and every assertion after it would be about a press that never
-- happened.
local function on(frame, button, atX, atY)
	local x, y = point(frame, atX, atY)
	local took, answered = click(x, y, button)
	if took ~= frame then
		local function said(what)
			if not what then
				return "nothing"
			end
			return ("%s (%s, level %d, made %d)"):format(
				what:GetName() or what:GetObjectType(), what:GetFrameStrata(),
				what:GetFrameLevel(), what.serial)
		end
		error(("a press aimed at %s landed on %s"):format(said(frame), said(took)), 2)
	end
	return took, answered
end

-- Drag a frame until its own anchor reads the offsets given.
--
-- The gesture four sections make and each was writing out: take hold of the
-- strip the frame is grabbed by, work out how far the pointer has to travel for
-- the frame to land there, and let go. Offsets rather than a corner of the
-- screen, because the offsets are what a window writes into the account file
-- and what every one of those sections then reads back.
--
-- The frame is not the grip. A window is moved by a strip along its top and a
-- bar by a handle laid over it, and the travel is measured in the moved frame's
-- own units, which is what its offsets are in.
--
-- Answers what the grab found and whether it was a drag, so a caller can say
-- which of the two ways it failed: nothing there, or something there that is
-- not registered for the button.
local function dragTo(grip, frame, x, y, button, atX, atY)
	local own = frame:GetEffectiveScale()
	local _, _, _, wasX, wasY = frame:GetPoint()
	local grabX, grabY = point(grip, atX, atY)
	local took, dragging = grab(grabX, grabY, button)
	if took == grip and dragging then
		drop(grabX + (x - wasX) * own, grabY + (y - wasY) * own)
	else
		drop()
	end
	return took, dragging
end

-- Drag one widget onto another, middle to middle, which is what a spell on a
-- square or a card into a lane is.
local function onto(from, to, button)
	local x, y = point(from)
	local toX, toY = point(to)
	return drag(x, y, toX, toY, button)
end

H.mouse = { At = at, Within = within, Point = point, Move = move, Place = place, On = on, Onto = onto,
	Give = give, Where = where, DragTo = dragTo,
	Grab = grab, Drop = drop, Drag = drag, Click = click, Wheel = wheel,
	Deliver = deliver, Rect = rect, Inside = inside }
