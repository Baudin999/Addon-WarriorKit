-- A model of the text engine
--
-- Not the client's. It has one property the client's has and that is the only
-- one the layout depends on: a longer string in a narrower box is more lines,
-- and a row measured against it has to grow. Arial Narrow runs about 0.42 em
-- per glyph at panel sizes and a line box is the font size plus two, which is
-- close enough that a note wrapping to four lines here wraps to three or five
-- there and the row is tall enough either way.
--
-- Colour escapes are stripped before counting, because |cffd08040 is ten
-- characters of nothing and the notes are full of them.
--
-- What this cannot prove: that the game agrees on where a line breaks, that
-- GetStringHeight answers at all on a hidden font string, or that SetWordWrap
-- is on 2.5.6. All three are probed or floored in the code rather than trusted.

local H = ...
local state = H.state
local UI_SCALE, PLAYER_CLASS, frames = H.UI_SCALE, H.PLAYER_CLASS, H.frames
local events, chat, loading = H.events, H.chat, H.loading
local Region, region, child = H.Region, H.region, H.child

local ADVANCE, LEADING = 0.42, 2

local function plain(s)
	s = tostring(s or "")
	return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The client runs the field's OnTextChanged off SetText, and for a long while
-- this did not, so every decision the chat field takes while you type was a
-- decision the harness could not reach. The one that went unseen was the field
-- handing the enter key back the moment it emptied itself, which is the press
-- the line was supposed to run on.
function Region:SetText(s)
	local was = self.text
	self.text = s
	if was == s then
		return
	end
	-- false is the point: the client's second argument says whether a person
	-- typed this, and SetText is by definition the other kind. A stub that
	-- called every write user input would have agreed with a field that took
	-- its own tidying up for someone changing their mind.
	local changed = self.scripts and self.scripts.OnTextChanged
	if changed then
		changed(self, false)
	end
end
function Region:GetText() return self.text end
-- Recorded rather than dropped on the no-op floor, because one string in the
-- addon says two different things in two colours and the colour is the half a
-- reader takes first: an aura's time left is white while it is counted in
-- seconds and gold once it is counted in minutes.
function Region:SetTextColor(r, g, b, a)
	self.textR, self.textG, self.textB, self.textA = r, g, b, a
end
function Region:GetTextColor()
	return self.textR, self.textG, self.textB, self.textA
end
function Region:SetSpacing(v) self.spacing = v end
function Region:SetWordWrap(v) self.wordWrap = v and true or false end
function Region:SetJustifyH(v) self.justify = v end
function Region:FontSize()
	return self.fontSize or (self.fontObject and self.fontObject.fontSize) or 12
end
function Region:StringLines()
	local text = plain(self.text)
	if text == "" then
		return 0
	end
	if self.wordWrap == false or not self.width or self.width <= 0 then
		return 1
	end
	local wide = #text * ADVANCE * self:FontSize()
	return math.max(1, math.ceil(wide / self.width))
end
function Region:GetStringHeight()
	local lines = self:StringLines()
	if lines == 0 then
		return 0
	end
	return lines * (self:FontSize() + LEADING) + (lines - 1) * (self.spacing or 0)
end
-- 17.3 is what an unset string answers, deliberately fractional, because the
-- level tag on an enemy bar is sized off this and the whole point of that
-- assertion is that a fraction from outside the grid comes back whole.
function Region:GetStringWidth()
	local text = plain(self.text)
	if text == "" then
		return 17.3
	end
	return #text * ADVANCE * self:FontSize()
end
function Region:SetScale(s) self.scale = s end
function Region:GetScale() return self.scale end
function Region:SetIgnoreParentScale(v) self.ignoreScale = v end
function Region:GetEffectiveScale()
	if self.ignoreScale then
		return self.scale
	end
	return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1)
end
-- The mouse region, real rather than the metatable's no-op, because the skin
-- pulls it back off the strip of frame the client's aura row hangs in and a
-- stub that dropped the call would pass a target frame taking clicks in empty
-- space under the block.
-- Whether a region answers the mouse. Real rather than the metatable's no-op,
-- because "which rows of a feed can be hovered" is decided in two places, the
-- setting and the row count, and a stub that swallowed the call could not tell
-- a feed that had just been made taller and left its new rows inert from one
-- that had not. The symptom is the bottom of a feed you have just resized
-- quietly refusing to open a tooltip.
function Region:EnableMouse(on)
	self.mouseEnabled = on and true or false
end
function Region:IsMouseEnabled()
	return self.mouseEnabled and true or false
end
function Region:SetHitRectInsets(l, r, t, b)
	self.insets = { l, r, t, b } -- a stub, and this runs on a relayout rather than a tick
end
function Region:GetHitRectInsets()
	local insets = self.insets
	if not insets then
		return 0, 0, 0, 0
	end
	return insets[1], insets[2], insets[3], insets[4]
end
function Region:SetParent(p) self.parent = p end
function Region:GetParent() return self.parent end
function Region:SetFrameLevel(l) self.frameLevel = l end
function Region:GetFrameLevel() return self.frameLevel end
-- Recorded rather than constant, because a strata is what the bar 1 drop bug
-- turned out to be: MainActionBar sits mouse enabled in TOOLTIP, the top strata
-- there is, and no frame level a cloned bar can be given wins that argument.
-- A fixture that answered MEDIUM for everything could not model it.
function Region:SetFrameStrata(value) self.strata = value end
function Region:GetFrameStrata() return self.strata or "MEDIUM" end
function Region:SetTexCoord(a, b, c, d) self.texcoord = { a, b, c, d } end
-- Eight values, the way the client answers, and the first of them is the left
-- crop, which is what the skin's tick reads back before it writes.
function Region:GetTexCoord()
	local c = self.texcoord
	if not c then
		return nil
	end
	return c[1], c[3], c[1], c[4], c[2], c[3], c[2], c[4]
end
function Region:SetTexture(path) self.texture = path end
function Region:GetTexture() return self.texture end
function Region:SetColorTexture(r, g, b, a)
	-- A colour texture answers no file path, which is the readback Skin.lua's
	-- Flatten guards on. Counted rather than recorded, so the tick can be
	-- asserted to have stopped writing without the count itself allocating.
	self.texture = nil
	self.r, self.g, self.b, self.a = r, g, b, a
	self.colorWrites = self.colorWrites + 1
end
function Region:SetStatusBarTexture(t)
	if type(t) == "table" then
		self.fill = t
	else
		-- On ARTWORK, which is where every client builds a status bar's own
		-- fill and what the two textures the skin puts under it are measured
		-- against.
		self.fill = self.fill or region("texture", self)
		self.fill.layer, self.fill.sublevel = "ARTWORK", 0
		self.fill.texture = t
	end
end
function Region:GetStatusBarTexture() return self.fill end
-- Recorded rather than dropped. This was a no-op falling through to the
-- PascalCase catch-all, and GetStatusBarColor answered a constant white, which
-- between them meant nothing here could see a colour the skin painted. A bug
-- that drew every gauge at a third of its brightness passed this file.
function Region:SetStatusBarColor(r, g, b, a)
	self.barR, self.barG, self.barB, self.barA = r, g, b, a or 1
	self.barWrites = (self.barWrites or 0) + 1
end
function Region:GetStatusBarColor()
	if self.barR then
		return self.barR, self.barG, self.barB, self.barA
	end
	return 1, 1, 1, 1
end
function Region:SetSnapToPixelGrid(v) self.snapped = v end
function Region:SetTexelSnappingBias(v) self.bias = v end
function Region:SetFontObject(o) self.fontObject = o end
function Region:GetFontObject() return self.fontObject end
-- The padding inside an edit box, recorded rather than swallowed. The client
-- writes its own over the addon's every time the chat channel moves, so a no-op
-- here is an assertion that reads back nil and passes whichever version wrote
-- last.
function Region:SetTextInsets(left, right, top, bottom)
	self.insetLeft, self.insetRight = left or 0, right or 0
	self.insetTop, self.insetBottom = top or 0, bottom or 0
end
function Region:GetTextInsets()
	return self.insetLeft or 0, self.insetRight or 0, self.insetTop or 0, self.insetBottom or 0
end

-- A font string given a font object answers that object's font, which is what
-- the client does and is the only way to read back a size the addon never set
-- directly. Every string in this addon takes a shared font object rather than
-- its own copy, on purpose, so without this fall-through nothing here could
-- assert what size anything is drawn at.
function Region:GetFont()
	if self.fontPath then
		return self.fontPath, self.fontSize, self.fontFlags
	end
	local object = self.fontObject
	if object then
		return object.fontPath, object.fontSize, object.fontFlags
	end
	return nil
end
function Region:SetFont(path, size, flags)
	self.fontPath, self.fontSize, self.fontFlags = path, size, flags
	return true
end
function Region:SetShadowColor(r, g, b, a) self.shadowColor = { r, g, b, a } end
function Region:SetShadowOffset(x, y) self.shadowX, self.shadowY = x, y end
-- Same fall-through as GetFont, and for the same reason: the shadow is set on
-- the shared font object and never on the string, so a test that asked the
-- string directly would find nothing on every string in the addon.
function Region:GetShadowOffset()
	if self.shadowX then
		return self.shadowX, self.shadowY
	end
	local object = self.fontObject
	if object and object.shadowX then
		return object.shadowX, object.shadowY
	end
	return 0, 0
end
-- Real anchors, because the skin reads Blizzard's back out of its own snapshot
-- and places the whole block on the first of them. With GetNumPoints answering
-- nothing the snapshot recorded nothing, the block fell to its fallback anchor,
-- and the one conversion in the file that matters was never exercised.
--
-- Both shapes the client takes, because the addon writes both and this used to
-- record only one. SetPoint("TOPLEFT", x, y) means the parent's own corner at
-- that offset, and it is what every inset in the addon is written as; stored
-- as it arrived, the offsets landed in the fields GetPoint hands back as the
-- relative frame and the relative point, so an anchor read back out of here
-- was two numbers where a frame belonged and no offset at all. Anything
-- asserting on an inset was asserting on zero.
function Region:SetPoint(point, relative, relativePoint, x, y)
	if type(relative) == "number" then
		relative, relativePoint, x, y = self.parent, point, relative, relativePoint
	elseif type(relativePoint) == "number" then
		relativePoint, x, y = point, relativePoint, x
	end
	self.points = self.points or {}
	self.points[#self.points + 1] = { point, relative, relativePoint, x or 0, y or 0 }
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
-- frames are on different scales, so a stub that answered nil made the
-- derivation untestable and one that answered a constant made it pass. These
-- four are also what UI/Tooltip.lua and UI/Widgets.lua ask when they decide
-- which way to open over an owner.
--
-- What is modelled is one anchor per frame, which is what the addon writes.
-- Both offsets are in the anchored frame's own units, the way the client reads
-- them, and the walk stops at UIParent or at a frame carrying no anchor at
-- all, either of which sits at the origin. Two things are deliberately not
-- modelled: a frame sized by a pair of opposing anchors rather than by
-- SetSize, and the client's own origin, which is the bottom left of the screen
-- where this is the top left of UIParent. Every reader in the addon takes a
-- difference between two of these, and a difference is the same on both.
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
-- Stored rather than swallowed by the metatable, because a secure button's
-- macro is written as an attribute and reading it back is the only way to
-- assert what a key press would actually send.
-- Which click edges a button answers, recorded rather than swallowed.
--
-- This fell through to the PascalCase no-op above, and a no-op here is a whole
-- class of bug the harness cannot see: a secure button registered for an edge
-- this client does not fire draws perfectly and does nothing at all when you
-- click it. That is exactly what shipped on the action bars, which registered
-- AnyDown on a client whose own ActionButton_OnLoad registers AnyUp.
function Region:RegisterForClicks(...)
	self.clicks = {}
	for index = 1, select("#", ...) do
		self.clicks[select(index, ...)] = true
	end
end
function Region:GetRegisteredClicks() return self.clicks end

-- A press on a button, which is the only way to find out whether anything is on
-- the other end of one.
--
-- The edge is the point. A button registered for AnyDown does nothing at all on
-- an up press, and a test that ran the handler regardless would pass on exactly
-- the bug RegisterForClicks above is recorded to catch. The caller says which
-- edge because a key binding press and a mouse release are not the same event
-- and the client does not guess either.
--
-- OnClick then PostClick, in the client's order: a secure button does its work
-- between the two, which is why anything tidying up after a secure press is
-- written into PostClick rather than OnClick.
function Region:Click(button, down)
	button = button or "LeftButton"
	local edge = down and "Down" or "Up"
	local clicks = self.clicks
	if clicks and not (clicks["Any" .. edge] or clicks[button .. edge]) then
		return false
	end
	local scripts = self.scripts
	if scripts and scripts.OnClick then
		scripts.OnClick(self, button, down and true or false)
	end
	if scripts and scripts.PostClick then
		scripts.PostClick(self, button, down and true or false)
	end
	return true
end

-- Whether a frame takes the mouse. Recorded for the same reason: a frame laid
-- over an icon that answers the mouse is a button you cannot press, and it
-- looks identical to one you can.
function Region:EnableMouse(value) self.mouse = value and true or false end
-- Recorded, not swallowed: a frame that was never made movable answers every
-- drag by doing nothing, and looks exactly like one that was.
function Region:SetMovable(value) self.movable = value and true or false end
-- Recorded for the reason above it: a frame that registered no drag button
-- answers every drag by doing nothing and looks exactly like one that did.
-- RegisterForDrag with no arguments is how the addon takes a drag away again,
-- so the empty call has to be recorded as a value rather than ignored.
function Region:RegisterForDrag(button) self.dragButton = button end
function Region:IsDraggable() return self.dragButton ~= nil end
function Region:IsMouseEnabled() return self.mouse end

function Region:SetAttribute(key, value)
	self.attributes = self.attributes or {}
	self.attributes[key] = value
end
function Region:GetAttribute(key)
	return self.attributes and self.attributes[key]
end

-- Frame references, real rather than swallowed by the metatable above.
--
-- A SecureHandlerStateTemplate header reaches the buttons it re-points through
-- these and through nothing else, so a no-op here would let a snippet that
-- walked the wrong names pass every assertion below.
function Region:SetFrameRef(name, frame)
	self.refs = self.refs or {}
	self.refs[name] = frame
end
function Region:GetFrameRef(name)
	return self.refs and self.refs[name]
end
function Region:IsProtected() return false end
function Region:SetShown(v) self.shown = v and true or false end
-- Recorded rather than swallowed by the metatable above, because which bar is
-- yours is said in alpha, and a no-op here is an assertion that reads back nil
-- and passes on nothing.
function Region:SetAlpha(v) self.alpha = v end
function Region:GetAlpha() return self.alpha or 1 end
function Region:IsShown() return self.shown end

-- Shown, and every parent above it shown too.
--
-- Real rather than the metatable's no-op, because that is the whole of what
-- Core/Attic.lua does: it re-parents a frame of Blizzard's into a frame that is
-- hidden and can never be shown, and the guarantee it makes is that the frame is
-- not drawn whatever anybody calls on the frame itself. A fixture where
-- IsVisible answered nil could not tell that mechanism from one that does
-- nothing at all, and the two bugs the attic exists for both looked like a frame
-- whose own flag said shown.
--
-- The walk stops where the chain does, which is UIParent, whose parent is nil.
function Region:IsVisible()
	local step = self
	while step do
		if not step.shown then
			return false
		end
		step = step.parent
	end
	return true
end

-- A slider that behaves like one.
--
-- Real, rather than the metatable's no-op, because two things in the addon are
-- built on the client's Slider type and both of them are the client tracking a
-- drag on the addon's behalf: the scrollbar in UI/Scroll.lua and the UI size row
-- in UI/Widgets.lua. A no-op here would let a slider that never reports a value,
-- never snaps to its step and never clamps to its range pass every assertion in
-- this file, which is the whole widget.
--
-- The step is applied on the way in, which is what SetObeyStepOnDrag buys on the
-- real client: the setting can only ever hold a value the panel can also show.
-- OnValueChanged fires on every write, including the addon's own, because that
-- is what the client does and it is exactly what the latches in both callers
-- exist to survive.
function Region:SetMinMaxValues(low, high)
	self.valueMin, self.valueMax = low, high
end
function Region:GetMinMaxValues() return self.valueMin, self.valueMax end
function Region:SetValueStep(step) self.valueStep = step end
function Region:GetValueStep() return self.valueStep end

function Region:SetValue(value)
	value = tonumber(value) or 0
	local low, high = self.valueMin, self.valueMax
	if low and self.valueStep and self.valueStep > 0 then
		value = low + math.floor((value - low) / self.valueStep + 0.5) * self.valueStep
	end
	if low and value < low then
		value = low
	end
	if high and value > high then
		value = high
	end
	self.value = value
	local handler = self.scripts.OnValueChanged
	if handler then
		handler(self, value)
	end
end

function Region:GetValue() return self.value end
-- A message frame that keeps its messages.
--
-- Real, rather than the metatable's no-op, for the reason the slider above is:
-- the chat window is a ScrollingMessageFrame per tab and the whole question
-- asked of it is which tab a line landed on. A stub that swallowed AddMessage
-- would let a feed that routes every line to one log, or to none, pass every
-- assertion in this file.
--
-- The insert mode is data rather than a no-op for the same reason and one step
-- further: UI/Log.lua writes it and reads it back, because the two clients
-- disagree about which spelling of the token they accept, and a stub that
-- swallowed the write would make that readback untestable. This one accepts
-- whichever spelling `insertStrict` says, so both paths through it are
-- reachable.
function Region:AddMessage(text, r, g, b)
	self.messages = self.messages or {}
	self.messages[#self.messages + 1] = { text = text, r = r, g = g, b = b }
end
function Region:GetNumMessages() return self.messages and #self.messages or 0 end
function Region:Clear() self.messages = {} end
function Region:SetInsertMode(mode)
	if chat.insertStrict and mode ~= chat.insertStrict then
		error("this client will not take " .. tostring(mode))
	end
	self.insertMode = mode
end
function Region:GetInsertMode() return self.insertMode end
function Region:SetScrollOffset(offset) self.scrollOffset = offset end
function Region:GetScrollOffset() return self.scrollOffset or 0 end
function Region:AtBottom() return (self.scrollOffset or 0) <= 0 end

-- Real, rather than the metatable's no-op, because the panel hides every
-- section but one and a stub that answers shown to all of them would let a
-- layout that puts seven pages on top of each other pass.
--
-- Both run the frame's own OnShow and OnHide, and only on a change, which is
-- what the client does. Three places in the addon hang real work off those two
-- and none of them could run before: Core/Panel.lua wraps the options window's
-- pair to tell every part the window opened, Perf/Feature.lua starts and stops
-- the memory walk with the tab that owns it, and Mail/Window.lua closes the
-- mailbox from the frame's OnHide so that escape, the close box and the client
-- saying it shut all leave through one door. A stub that swallowed the scripts
-- made all three look tested.
function Region:Show()
	if self.shown then
		return
	end
	self.shown = true
	if self.scripts.OnShow then
		self.scripts.OnShow(self)
	end
end

function Region:Hide()
	if not self.shown then
		return
	end
	self.shown = false
	if self.scripts.OnHide then
		self.scripts.OnHide(self)
	end
end

-- The keyboard focus on an edit box, modelled rather than swallowed.
--
-- The chat window's line is drawn only while the cursor is in it, and the two
-- scripts that do that drawing hang off these two calls. A no-op here meant the
-- field could never be focused in a run, so every assertion about how it looks
-- while you are typing was an assertion about a state the harness could not
-- reach. One frame holds the focus at a time, the way the client's does.
local focused
function Region:SetFocus()
	if focused == self then
		return
	end
	if focused then
		focused:ClearFocus()
	end
	focused = self
	self.focused = true
	local gained = self.scripts and self.scripts.OnEditFocusGained
	if gained then
		gained(self)
	end
end

function Region:ClearFocus()
	if not self.focused then
		return
	end
	self.focused = false
	if focused == self then
		focused = nil
	end
	local lost = self.scripts and self.scripts.OnEditFocusLost
	if lost then
		lost(self)
	end
end

function Region:HasFocus() return self.focused and true or false end
-- Idempotent, the way the client's is. A frame that registers the same event
-- twice is registered once and is handed the event once, and a stub that
-- appended instead delivered every line twice to any part that reapplies its
-- registrations. That is not a small difference: the chat feed reapplies on
-- every setting change, so the doubling was proportional to how much the
-- player had touched the panel, and it looked like a routing bug in the addon.
function Region:RegisterEvent(e)
	events[e] = events[e] or {}
	for _, registered in ipairs(events[e]) do
		if registered == self then
			return
		end
	end
	events[e][#events[e] + 1] = self
end

-- The filtered form, which the skin uses for UNIT_AURA so a raid's worth of
-- other units never reaches its handler. Modelled as the plain registration it
-- is: the filter is the client's business and every fire() here names its unit
-- anyway, so what this proves is that the addon took the filtered path at all.
function Region:RegisterUnitEvent(e)
	self:RegisterEvent(e)
end

-- Real, rather than the metatable's no-op. Two parts turn an event off when
-- their setting goes off, and that the addon leaves the path entirely is the
-- assertion; a no-op here would pass a feature that only ever branches inside
-- a handler the client is still calling.
function Region:UnregisterEvent(e)
	local list = events[e]
	if not list then
		return
	end
	for index = #list, 1, -1 do
		if list[index] == self then
			table.remove(list, index)
		end
	end
end

_G.UIParent = region("frame")
_G.UIParent.scale = UI_SCALE
_G.UIParent.ignoreScale = true
_G.WorldFrame = region("frame")
_G.GameTooltip = region("frame")

function _G.CreateFrame(kind, name, parent)
	local f = child(kind, parent or _G.UIParent, name)
	f.origin = loading.file
	frames[#frames + 1] = f
	return f
end

function _G.CreateFont() return region("font") end

_G.GameFontNormal = region("font")
_G.GameFontNormal.fontPath = "Fonts\\FRIZQT__.TTF"
_G.GameFontNormalSmall, _G.GameFontHighlightSmall = _G.GameFontNormal, _G.GameFontNormal
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }

function _G.GetPhysicalScreenSize() return 3440, state.SCREEN_H end

-- A clock that advances a fixed amount per read, so a bracketed tick measures
-- the same figure every run and an assertion on it means something. The real
-- one is a wall clock and would make every number here a coin toss.
local TICK_MS = 0.05
local clock = 0
function _G.debugprofilestop()
	clock = clock + TICK_MS
	return clock
end
function _G.GetFramerate() return 97.5 end

-- Memory that only ever rises, which is what an addon between collections does.
local heap = 300
function _G.UpdateAddOnMemoryUsage() heap = heap + 2 end
function _G.GetAddOnMemoryUsage(name)
	return (name == "WarriorKit") and heap or 0
end

-- nameplateMaxDistance starts where the Anniversary client starts it, and that
-- figure is also the highest it will hold: a write past it is clamped and
-- answered with true, which is the whole reason an addon cannot tell whether a
-- range it asked for was given. Nothing else here clamps, because nothing else
-- this addon writes does.
local NAMEPLATE_MAX_DISTANCE_CEILING = 41
local cvars = { nameplateShowEnemies = "1", nameplateMotion = "0",
	nameplateOverlapV = "1.10", SoftTargetEnemy = "0",
	nameplateMaxDistance = "41" }
function _G.GetCVar(k) return cvars[k] end
function _G.SetCVar(k, v)
	if k == "nameplateMaxDistance" then
		local asked = tonumber(v)
		if asked and asked > NAMEPLATE_MAX_DISTANCE_CEILING then
			v = NAMEPLATE_MAX_DISTANCE_CEILING
		end
	end
	cvars[k] = tostring(v)
	return true
end
function _G.GetCVarBool(k) return cvars[k] == "1" end

local plates, plateSize = {}, {}
local PLATE_W, PLATE_H = 110, 45 -- what this stub client's own plate measures
_G.C_NamePlate = {
	GetNamePlates = function()
		local out = {}
		for i, p in ipairs(plates) do out[i] = p end
		return out
	end,
	GetNamePlateForUnit = function(unit)
		for _, p in ipairs(plates) do
			if p.namePlateUnitToken == unit then return p end
		end
	end,
	-- The client resizes every enemy plate it has when told, and that is not a
	-- detail: the bars read a plate's width to size themselves, so a stub that
	-- only records the call cannot see a bar sizing itself off its own last
	-- answer. Plates put up later start at the size in force, the same way.
	SetNamePlateEnemySize = function(w, h)
		plateSize[1], plateSize[2] = w, h
		for _, p in ipairs(plates) do
			p:SetSize(w, h)
		end
	end,
}

local guids = {}
local function constant(v) return function() return v end end
_G.UnitExists = function(u) return guids[u] ~= nil end
_G.UnitGUID = function(u) return guids[u] end
-- Table driven rather than a plain equality, for the same reason the threat
-- reader below is: several files resolve UnitIsUnit into a file-scope local as
-- they load, so a test that swapped the global afterwards would swap nothing.
-- The alias table is empty in the shipped scene, where two tokens are the same
-- unit or they are not.
local unitAlias = {}
_G.UnitIsUnit = function(a, b)
	if a == b then
		return true
	end
	local aliases = unitAlias[a]
	return aliases ~= nil and aliases[b] == true
end
-- Class and name are per unit where a test has said so and the shipped answer
-- everywhere else. Every module that reads them localises the global at load,
-- so a test cannot swap the function afterwards; it writes to these tables
-- instead, which is why they are here rather than in the section that uses them.
local unitClass, unitName = {}, {}
_G.UnitClass = function(unit)
	local class = unitClass[unit]
	if class then
		return class, class
	end
	return PLAYER_CLASS:sub(1, 1) .. PLAYER_CLASS:sub(2):lower(), PLAYER_CLASS
end

H.plain, H.cvars, H.plates = plain, cvars, plates
H.plateSize, H.PLATE_W, H.PLATE_H = plateSize, PLATE_W, PLATE_H
H.guids, H.constant, H.unitAlias = guids, constant, unitAlias
H.unitClass, H.unitName = unitClass, unitName
