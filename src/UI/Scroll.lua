local ADDON, ns = ...

local UI = ns.UI

--------------------------------------------------------------------------
-- Scrolling
--
-- A viewport that clips, a canvas that moves inside it, and a bar on the right
-- that shows where you are and can be dragged.
--
-- Three client questions had to be answered before any of it, and all three are
-- probed rather than assumed, because nothing installed on 2.5.6 proves any of
-- them and a settings window that raises is worse than one that does not
-- scroll.
--
-- Clipping. SetClipsChildren is the direct way and is preferred where it
-- answers, because it is one method on an ordinary frame and the canvas is then
-- an ordinary child that moves by its anchor. Where it is missing the viewport
-- is built as a ScrollFrame instead, which is a frame type rather than a
-- template, has existed since the first client, and clips its scroll child by
-- construction. Where neither answers there is no clipping at all: the content
-- is placed and nothing is hidden, which looks wrong on a long page and is
-- still a window you can read.
--
-- The bar. It is a Slider, again a frame type and not a template, with a thumb
-- texture this file draws. That is deliberate: dragging a thumb means following
-- the cursor, following the cursor means an OnUpdate, and an OnUpdate on a
-- settings window is a ticker the addon then has to defend forever. The client
-- already tracks a slider's drag for us and reports it once per change, so the
-- whole cost is one OnValueChanged. Where the Slider type is refused the wheel
-- still scrolls and there is no bar.
--
-- The wheel. EnableMouseWheel on the viewport, probed by name. Children do not
-- swallow it unless they enable it themselves, and none of the widgets does.
--
-- The bar column is reserved whether or not the bar is showing. Handing the
-- width back when the content happens to fit would rewrap every note, which can
-- make the content taller, which brings the bar back, which takes the width
-- away again. A layout that can argue with itself is a layout that flickers.
--------------------------------------------------------------------------

local WHEEL_ROWS = 3

local View = {}
View.__index = View

-- Returns the frame that clips, the frame content is parented to, and a
-- function that moves the second inside the first. Which of the three paths
-- came up is worth knowing in a bug report, so it is recorded rather than
-- discarded.
local function Viewport(parent)
	local frame = CreateFrame("Frame", nil, parent)
	if type(frame.SetClipsChildren) == "function" then
		frame:SetClipsChildren(true)
		local canvas = CreateFrame("Frame", nil, frame)
		canvas:SetPoint("TOPLEFT")
		return frame, canvas, function(offset)
			canvas:ClearAllPoints()
			canvas:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, offset)
		end, "clips"
	end

	local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, parent)
	if ok and scroll and type(scroll.SetScrollChild) == "function" then
		local canvas = CreateFrame("Frame", nil, scroll)
		canvas:SetPoint("TOPLEFT")
		scroll:SetScrollChild(canvas)
		return scroll, canvas, function(offset)
			scroll:SetVerticalScroll(-offset)
		end, "scrollframe"
	end

	local canvas = CreateFrame("Frame", nil, frame)
	canvas:SetPoint("TOPLEFT")
	return frame, canvas, function() end, "none"
end

-- Everything past the frame itself is pcalled as one block rather than probed
-- method by method. A Slider takes a thumb the way no other frame type does,
-- and the one thing nothing here can check is whether 2.5.6 accepts a texture
-- object where a newer client accepts one. A refusal has to cost the bar and
-- nothing else, because the wheel still scrolls without it.
local function Dress(slider)
	local M, C = UI.Metric, UI.Color
	slider:SetOrientation("VERTICAL")
	slider:SetWidth(M.bar)
	slider:SetMinMaxValues(0, 0)
	slider:SetValue(0)
	if slider.SetValueStep then
		slider:SetValueStep(1)
	end
	-- Without this a drag reports continuous values and the step applies only to
	-- a click, which puts the canvas on a fractional pixel while the thumb is
	-- held. Newer clients have it, 2.5.6 may not, and the cost of missing it is
	-- a soft edge during the drag alone.
	if slider.SetObeyStepOnDrag then
		slider:SetObeyStepOnDrag(true)
	end

	slider.track = ns.Fill(slider, "BACKGROUND", C.sunken[1], C.sunken[2], C.sunken[3], C.sunken[4])
	slider.track:SetAllPoints()

	slider.thumb = ns.Fill(slider, "ARTWORK", C.edge[1], C.edge[2], C.edge[3], 1)
	slider.thumb:SetSize(M.bar, M.thumb)
	slider:SetThumbTexture(slider.thumb)
end

-- The bar on its own, with nothing to scroll behind it yet.
--
-- Public, because the scroll view is not the only thing in the addon that has
-- more content than room. The chat log is a ScrollingMessageFrame, which counts
-- in messages rather than in pixels and does its own clipping, so it cannot use
-- the view above and still wants exactly this bar: same width, same track, same
-- thumb, one place to change all three.
--
-- Nil rather than an error where the client refuses the Slider type, because
-- the wheel still scrolls without a bar and a window with no bar is a worse
-- window rather than a broken one.
function UI.ScrollBar(parent, onValue)
	local made, slider = pcall(CreateFrame, "Slider", nil, parent)
	if not made or not slider or type(slider.SetOrientation) ~= "function"
		or type(slider.SetThumbTexture) ~= "function" then
		return nil
	end
	if not pcall(Dress, slider) then
		slider:Hide()
		return nil
	end
	slider:SetScript("OnValueChanged", function(self, value)
		onValue(self, value)
	end)
	return slider
end

-- The bar, drawn at a fraction of its own alpha.
--
-- Its own function rather than two UI.Fade calls at each site, because the two
-- colours are this file's: the track is sunken and the thumb is an edge, and a
-- caller that wanted to fade them would have to know both and would go on
-- knowing them after the palette moved. See UI.Fade in UI/Theme.lua for why the
-- fraction is kept on the texture.
function UI.FadeBar(bar, fraction)
	if not bar or not bar.track or not bar.thumb then
		return false
	end
	local C = UI.Color
	UI.Tint(UI.Fade(bar.track, fraction), C.sunken)
	UI.Tint(UI.Fade(bar.thumb, fraction), C.edge)
	return true
end

local function Bar(view, parent)
	return UI.ScrollBar(parent, function(_, value)
		-- Refresh writes the value back when the extent changes, and that write
		-- fires this. Without the latch the write and the handler chase each
		-- other for one frame every time the content grows.
		if view.syncing then
			return
		end
		view:ScrollTo(value)
	end)
end

-- opts.overlay floats the bar over the right edge of the content instead of
-- reserving a column for it.
--
-- The column is right everywhere else and wrong in one place: the chat window's
-- rail is thirty pixels wide, the bar column is sixteen of them, and reserving
-- it leaves fourteen pixels for a sixteen pixel icon. A view narrower than the
-- bar it is making room for is a view with nothing in it. Overlaying costs the
-- right few pixels of a row on the rare column long enough to scroll, and the
-- alternative there is no bar at all and no sign that there is more.
function UI.ScrollView(parent, opts)
	local view = setmetatable({ offset = 0, extent = 0, scrollable = false }, View)
	view.overlay = opts and opts.overlay and true or false
	view.frame = CreateFrame("Frame", nil, parent)

	local port, canvas, move, mechanism = Viewport(view.frame)
	view.port, view.canvas, view.Move, view.mechanism = port, canvas, move, mechanism
	port:SetPoint("TOPLEFT")

	view.bar = Bar(view, view.frame)
	if view.bar then
		view.bar:SetPoint("TOPRIGHT")
		view.bar:SetPoint("BOTTOMRIGHT")
		view.bar:Hide()
	end

	if type(port.EnableMouseWheel) == "function" then
		port:EnableMouseWheel(true)
		port:SetScript("OnMouseWheel", function(_, delta)
			view:ScrollTo(view.offset - delta * WHEEL_ROWS * (UI.Metric.row + UI.Metric.rowGap))
		end)
	end

	return view
end

-- The size of the whole thing, bar included. The content width is what is left
-- after the bar column, and it is handed to the canvas so a stack laid out on
-- it knows how wide its rows are before it measures any of them.
function View:Resize(width, height)
	local M = UI.Metric
	self.width = self.overlay and width or (width - M.bar - M.gutter)
	self.height = height
	self.frame:SetSize(width, height)
	self.port:SetSize(self.width, height)
	self.canvas:SetWidth(self.width)
	return self.width
end

-- Called after anything changes how tall the content is. Everything about the
-- bar follows from two numbers, so there is one place that reads them.
function View:Update(extent)
	self.extent = extent or self.extent
	-- The ScrollFrame path needs its scroll child to have a real height or it
	-- has nothing to scroll, and the clipping path costs nothing for the write.
	self.canvas:SetHeight(math.max(self.extent, 1))
	local room = self.extent - self.height
	self.scrollable = room > 0

	if not self.scrollable then
		self.offset = 0
		self.Move(0)
		if self.bar then
			self.bar:Hide()
		end
		return false
	end

	if self.offset > room then
		self.offset = room
	end
	self.Move(self.offset)

	if self.bar then
		local M = UI.Metric
		local size = math.max(M.thumb, UI.Round(self.frame, self.height * self.height / self.extent))
		self.bar.thumb:SetSize(M.bar, size)
		self.syncing = true
		self.bar:SetMinMaxValues(0, room)
		self.bar:SetValue(self.offset)
		self.syncing = nil
		self.bar:Show()
	end
	return true
end

function View:ScrollTo(offset)
	local room = self.extent - self.height
	if room < 0 then
		room = 0
	end
	offset = UI.Round(self.frame, math.max(0, math.min(offset or 0, room)))
	if offset == self.offset then
		return false
	end
	self.offset = offset
	self.Move(offset)
	if self.bar and self.bar:IsShown() then
		self.syncing = true
		self.bar:SetValue(offset)
		self.syncing = nil
	end
	return true
end
