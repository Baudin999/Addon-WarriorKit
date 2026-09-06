-- Where a frame is
--
-- Anchors, the size a frame gets from them, the corner each one resolves to,
-- which frame is over which, and the drag the client runs on your behalf. One
-- file because they are one question asked five ways: a hit test needs a
-- rectangle, a rectangle needs a size, a size can come from a pair of opposing
-- anchors, an anchor is measured against another frame's corner, and which of
-- two frames at that point takes the press is strata and level.
--
-- Split out of 02-text.lua rather than left in it. That file is the Region stub
-- and is allow-listed for being one class, which held while the geometry in it
-- was four functions answering a constant. It is not four functions any more:
-- 22-mouse.lua asks where things really are, and everything that used to answer
-- "near enough" had to start answering.
--
-- **The origin is UIParent's top left corner**, with x to the right and y
-- downward and negative. That is not the client's origin, which is the bottom
-- left of the screen, and it does not matter: every reader here takes a
-- difference between two of these numbers and a difference is the same in both.
-- The one place the two meet is the cursor, and 22-mouse.lua says how.

local H = ...

local Region = H.Region

--------------------------------------------------------------------------
-- Which frame is over which
--------------------------------------------------------------------------

function Region:SetFrameLevel(l) self.frameLevel = l end
function Region:GetFrameLevel() return self.frameLevel end
function Region:SetToplevel(on) self.toplevel = on end
function Region:IsToplevel() return self.toplevel == true end

-- Lifting a frame over everything else in its strata.
--
-- This was a counter and nothing else, on the argument that the harness had no
-- sibling order to lift a frame above. It has one now: the hit test in
-- 22-mouse.lua asks which frame is on top at a point, and with Raise doing
-- nothing two windows open at once were stacked in the order they happened to
-- be built. A drag aimed at the quest log's title bar landed on the settings
-- panel, which is exactly what a player would get from a client that ignored
-- Raise, and is not what this one does.
--
-- The whole subtree moves by the same amount, because a window raised over
-- another has to bring its own chrome with it and every reading inside a window
-- is a difference between two of its own levels. The counter stays: three
-- sections ask whether a window was raised at all rather than where it ended up.
local function lift(frame, delta)
	frame.frameLevel = (frame.frameLevel or 0) + delta
	for index = 1, #frame.children do
		lift(frame.children[index], delta)
	end
end

local function ceiling(frame, strata, skip, top)
	if frame == skip then
		return top
	end
	if frame:GetFrameStrata() == strata and frame.frameLevel > top then
		top = frame.frameLevel
	end
	for index = 1, #frame.children do
		top = ceiling(frame.children[index], strata, skip, top)
	end
	return top
end

function Region:Raise()
	self.raised = (self.raised or 0) + 1
	local top = ceiling(_G.UIParent, self:GetFrameStrata(), self, 0)
	local delta = top + 1 - (self.frameLevel or 0)
	if delta > 0 then
		lift(self, delta)
	end
end
-- Recorded rather than constant, because a strata is what the bar 1 drop bug
-- turned out to be: MainActionBar sits mouse enabled in TOOLTIP, the top strata
-- there is, and no frame level a cloned bar can be given wins that argument.
-- A fixture that answered MEDIUM for everything could not model it.
--
-- Inherited where nobody set one, which is the client's answer and was not this
-- stub's: a child of a frame in TOOLTIP read back MEDIUM, so the hit test in
-- 22-mouse.lua would have put half of Blizzard's action bar under a window it
-- covers.
function Region:SetFrameStrata(value) self.strata = value end
function Region:GetFrameStrata()
	local step = self
	while step do
		if step.strata then
			return step.strata
		end
		step = step.parent
	end
	return "MEDIUM"
end
--------------------------------------------------------------------------
-- Anchors, and what they resolve to
--------------------------------------------------------------------------

-- Real anchors, because the skin reads Blizzard's back out of its own snapshot
-- and places the whole block on the first of them. Answering nothing dropped
-- the block to its fallback and left the one conversion in the file that
-- matters unexercised.
--
-- All three shapes the client takes. SetPoint("TOPLEFT", x, y) is the parent's
-- own corner at that offset, and stored as it arrived the offsets landed where
-- GetPoint hands back the relative frame and the relative point, so every inset
-- in the addon read as zero. SetPoint("CENTER") alone means the parent and the
-- same corner, and the stored nils left an anchor nothing can be placed against
-- and no drag can re-anchor. And an anchor is keyed by the corner it names: a
-- second SetPoint on that corner moves it, one on another corner is a second
-- anchor beside it. Appending both put a stale anchor in front of the live one,
-- replacing both made a frame that cannot be pinned by two corners at all,
-- which is the arrangement a secure header leaves behind.
function Region:SetPoint(point, relative, relativePoint, x, y)
	-- A name where a frame would do, which the client takes and this did not.
	-- Every anchor the addon writes into the account file carries "UIParent" as
	-- a string, and a saved anchor put back verbatim landed a frame relative to
	-- a string nothing could measure.
	if type(relative) == "string" then
		relative = _G[relative] or relative
	end
	if type(relative) == "number" then
		relative, relativePoint, x, y = self.parent, point, relative, relativePoint
	elseif type(relativePoint) == "number" then
		relativePoint, x, y = point, relativePoint, x
	end
	self.points = self.points or {}
	for index = 1, #self.points do
		if self.points[index][1] == point then
			self.points[index] = { point, relative or self.parent,
				relativePoint or point, x or 0, y or 0 }
			return
		end
	end
	self.points[#self.points + 1] = { point, relative or self.parent,
		relativePoint or point, x or 0, y or 0 }
end
function Region:ClearAllPoints() self.points, self.allPoints = nil, nil end
function Region:GetNumPoints() return self.points and #self.points or 0 end
function Region:GetPoint(index)
	local pt = self.points and self.points[index or 1]
	if not pt then
		return "CENTER", nil, "CENTER", 0, 0
	end
	return pt[1], pt[2], pt[3], pt[4], pt[5]
end
function Region:SetAllPoints(other)
	self.allPoints = other or self.parent
	self.points = { { "TOPLEFT", self.allPoints, "TOPLEFT", 0, 0 },
		{ "BOTTOMRIGHT", self.allPoints, "BOTTOMRIGHT", 0, 0 } }
end

-- Where a frame actually landed, resolved through the chain of anchors it was
-- given rather than answered as a constant.
--
-- The frame link needs it. Dropping the target in Edit Mode is read back as a
-- gap and a level by measuring four edges and taking two differences, and both
-- frames are on different scales, so a stub answering nil made the derivation
-- untestable and one answering a constant made it pass. UI/Tooltip.lua and
-- UI/Widgets.lua ask the same four when they pick a side to open on.
--
-- The walk follows the first anchor only, which is the one the addon places a
-- frame on. Both offsets are in the anchored frame's own units, the way the
-- client reads them, and the walk stops at UIParent or at a frame with no
-- anchor at all, either of which sits at the origin. Not modelled: a frame
-- sized by a pair of opposing anchors, and the client's own origin, which is
-- the bottom left of the screen where this is the top left of UIParent. Every
-- reader takes a difference between two of these, and a difference is the same
-- on both.
local function corner(point, width, height)
	local x = width / 2
	if point:find("LEFT") then
		x = 0
	elseif point:find("RIGHT") then
		x = width
	end
	local y = -height / 2
	if point:find("TOP") then
		y = 0
	elseif point:find("BOTTOM") then
		y = -height
	end
	return x, y
end

local function origin(self)
	if self == _G.UIParent or self:GetNumPoints() == 0 then
		return 0, 0
	end
	local point, relative, relativePoint, x, y = self:GetPoint(1)
	relative = relative or self.parent or _G.UIParent
	local scale, theirs = self:GetEffectiveScale(), relative:GetEffectiveScale()
	local rx, ry = origin(relative)
	local ax, ay = corner(relativePoint, relative:GetWidth(), relative:GetHeight())
	local mx, my = corner(point, self:GetWidth(), self:GetHeight())
	return rx + ax * theirs + (x - mx) * scale, ry + ay * theirs + (y - my) * scale
end

-- The size a frame was given, or the size its two anchors give it.
--
-- The client sizes a frame from a pair of opposing anchors and this stub did
-- not: a frame nobody called SetWidth on answered zero. That was harmless while
-- nothing measured such a frame and became a lie the moment the hit test in
-- 22-mouse.lua wanted a rectangle. A stepper's minus button is anchored TOPRIGHT
-- inside a row sized by its own two edges, the row answered a width of zero, and
-- the button resolved eighty units to the left of the row it is drawn in, which
-- put it under the rail and made it unpressable. Every assertion about that row
-- passed, because nothing but a pointer cares where a button really is.
--
-- Only where the size was never written. SetWidth and SetSize win outright, and
-- a frame with one anchor or none still answers zero, which is what the client
-- answers as well.
--
-- The guard is for a cycle rather than for depth. Two frames anchored to each
-- other have no size the client could work out either, and answering zero once
-- is better than running out of stack.
local measuring = {}

local function pinned(self, entry)
	local point, relative = entry[1], entry[2] or self.parent or _G.UIParent
	local relativePoint, x, y = entry[3], entry[4], entry[5]
	local rx, ry = origin(relative)
	local theirs = relative:GetEffectiveScale()
	local ax, ay = corner(relativePoint, relative:GetWidth(), relative:GetHeight())
	local own = self:GetEffectiveScale()
	return point, rx + ax * theirs + x * own, ry + ay * theirs + y * own
end

local function spanned(self, near, far, axis)
	if measuring[self] or not self.points or #self.points < 2 then
		return 0
	end
	measuring[self] = true
	local low, high
	for index = 1, #self.points do
		local point, x, y = pinned(self, self.points[index])
		local along = axis == "x" and x or y
		if point:find(near) then
			low = along
		elseif point:find(far) then
			high = along
		end
	end
	measuring[self] = nil
	if not low or not high then
		return 0
	end
	return math.abs(high - low) / self:GetEffectiveScale()
end

function Region:GetWidth()
	if self.width ~= 0 then
		return self.width
	end
	return spanned(self, "LEFT", "RIGHT", "x")
end

function Region:GetHeight()
	if self.height ~= 0 then
		return self.height
	end
	return spanned(self, "TOP", "BOTTOM", "y")
end

function Region:GetLeft()
	return (origin(self)) / self:GetEffectiveScale()
end
function Region:GetTop()
	local _, y = origin(self)
	return y / self:GetEffectiveScale()
end
function Region:GetRight() return self:GetLeft() + self:GetWidth() end
function Region:GetBottom() return self:GetTop() - self:GetHeight() end
function Region:GetCenter()
	return self:GetLeft() + self:GetWidth() / 2, self:GetTop() - self:GetHeight() / 2
end
--------------------------------------------------------------------------
-- The drag the client runs
--------------------------------------------------------------------------

-- Recorded, not swallowed: a frame that was never made movable answers every
-- drag by doing nothing, and looks exactly like one that was.
function Region:SetMovable(value) self.movable = value and true or false end

-- The client moving a frame for you, which is what an ordinary drag is.
--
-- Real rather than the PascalCase no-op, because the no-op is why every drag
-- test in this harness moved the frame itself with SetPoint afterwards: the
-- call did nothing, so the section had to, and what it was then asserting was
-- its own arithmetic. What is recorded here is where the frame was and where
-- the pointer was, and 22-mouse.lua re-anchors on the difference as the pointer
-- travels, which is the client's own arrangement.
--
-- A frame nobody made movable is refused, which is the state a locked frame is
-- in: UI/Placeable.lua takes the drag off with RegisterForDrag and leaves the
-- movable flag alone, so a frame that got this far and cannot move is a bug
-- rather than a lock.
local moving = {}

function Region:StartMoving()
	if not self.movable or self.moving then
		return
	end
	local point, relative, relativePoint, x, y = self:GetPoint(1)
	local cursorX, cursorY = _G.GetCursorPosition()
	local own = self:GetEffectiveScale()
	self.moving = { point = point, relative = relative or self.parent,
		relativePoint = relativePoint, x = x, y = y,
		x0 = cursorX / own, y0 = cursorY / own }
	moving[#moving + 1] = self
end

function Region:StopMovingOrSizing()
	if not self.moving then
		return
	end
	self.moving = nil
	for index = #moving, 1, -1 do
		if moving[index] == self then
			table.remove(moving, index)
		end
	end
end

function Region:IsMovingOrSizing() return self.moving ~= nil end
H.moving = moving
-- Recorded for the reason above it: a frame that registered no drag button
-- answers every drag by doing nothing and looks exactly like one that did.
-- RegisterForDrag with no arguments is how the addon takes a drag away again,
-- so the empty call has to be recorded as a value rather than ignored.
function Region:RegisterForDrag(button) self.dragButton = button end
function Region:IsDraggable() return self.dragButton ~= nil end