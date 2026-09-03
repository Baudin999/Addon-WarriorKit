local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- The log
--
-- A column of lines that grows from the bottom, keeps the last few hundred of
-- them, wraps what is too long for the width, and scrolls.
--
-- It is not built out of UI/Stack.lua and UI/Scroll.lua, and that is the one
-- decision in this file worth arguing about. The stack asks every row how tall
-- it is and lays the column out again from the top, which is exactly right for
-- a settings page and exactly wrong here: a line arrives, the whole column
-- reflows, and in a raid that is three hundred measured font strings several
-- times a second. Worse, a font string on a hidden frame does not report its
-- wrapped height on this client, which is why the panel reflows a section only
-- after showing it, and a chat tab you are not looking at is hidden all
-- evening.
--
-- So the log is the client's own ScrollingMessageFrame, which is a frame type
-- rather than a template. UI/Scroll.lua already leans on two of those, the
-- Slider and the ScrollFrame, for the same reason and with the same guard: it
-- is probed with pcall, and a client that refuses it costs the log rather than
-- raising. That frame type has kept a wrapped, capped, scrollable message
-- buffer since the first client and it is what every chat window in the game
-- is made of, including Blizzard's.
--
-- Everything around it is ours. The font is the addon's shared Arial Narrow
-- object rather than the client's serif, the bar beside it is UI.ScrollBar, the
-- colours are the theme's, and the frame carries no template, no backdrop and
-- no art. What the client contributes is the buffer and the wrap.
--
-- **Nothing fades.** Blizzard's chat frames fade a line out after two minutes,
-- which is fine for a window that is a river you glance at and wrong for one
-- you are meant to be able to read. A line stays until it falls off the end of
-- the buffer.
--------------------------------------------------------------------------

-- How many lines are kept per log. Each tab holds its own buffer, so this is
-- paid once per tab rather than once for the window. 500 lines of short strings
-- is tens of kilobytes and it is the difference between scrolling back to what
-- somebody said before the pull and not.
local MAX_LINES = 500

-- What one notch of the wheel moves. Three is what the scroll view uses and
-- what every chat window in the game uses.
local WHEEL_LINES = 3

local Log = {}
Log.__index = Log

--------------------------------------------------------------------------
-- Standing one up
--
-- Every method that shapes the frame is probed by name rather than called, for
-- the reason the rest of the addon probes: nothing installed on 2.5.6 proves
-- any of them, and one missing method must cost its own feature rather than the
-- window. The two that would be visibly wrong if they were missing are recorded
-- and reported through Describe, because a log that draws upside down and says
-- nothing is worse than one that says why.
--------------------------------------------------------------------------

-- New lines at the bottom, the way every chat window in the game reads.
--
-- A ScrollingMessageFrame made by hand starts at TOP, which puts the newest
-- line above the oldest. The wiki carries a note from the patch that added the
-- method saying the all-caps token is refused and the lower case one works, and
-- another saying the opposite, so it is written and read back and the other
-- case is tried when the first does not take. That is the same shape as the
-- font readback in UI/Text.lua and it exists for the same reason: on this
-- client a refused write is silent.
local function InsertBottom(frame)
	if type(frame.SetInsertMode) ~= "function" then
		return false
	end
	for _, mode in ipairs({ "BOTTOM", "bottom" }) do
		if pcall(frame.SetInsertMode, frame, mode) then
			if type(frame.GetInsertMode) ~= "function" then
				return true
			end
			local got = frame:GetInsertMode()
			if type(got) == "string" and got:upper() == "BOTTOM" then
				return true
			end
		end
	end
	return false
end

-- opts.onLink   function(link, text, button) returning true when it has dealt
--               with the click itself, which is how a player name becomes a
--               whisper in our own field rather than in Blizzard's
-- opts.maxLines how many lines this log keeps, for a log that wants fewer
--
-- Returns the log, or nil and the reason, so a caller can say what happened
-- rather than draw an empty rectangle.
function UI.Log(parent, opts)
	opts = opts or {}
	-- A container, and the message frame inside it. Two frames rather than one
	-- because the bar has to sit beside the text and not over it: a
	-- ScrollingMessageFrame wraps to its own width, so the only way to keep the
	-- last few characters of a long line off the thumb is to make the message
	-- frame narrower than the space the log was given. The container is what the
	-- caller places and shows; everything else in here is private to this file.
	local container = CreateFrame("Frame", nil, parent)
	local made, frame = pcall(CreateFrame, "ScrollingMessageFrame", nil, container)
	if not made or not frame or type(frame.AddMessage) ~= "function" then
		container:Hide()
		return nil, "this client has no ScrollingMessageFrame"
	end
	frame:SetPoint("TOPLEFT")

	local log = setmetatable({ frame = container, view = frame, lines = 0 }, Log)

	if type(frame.SetMaxLines) == "function" then
		frame:SetMaxLines(opts.maxLines or MAX_LINES)
	end
	if type(frame.SetFading) == "function" then
		frame:SetFading(false)
	end
	if type(frame.SetJustifyH) == "function" then
		frame:SetJustifyH("LEFT")
	end
	-- A wrapped line indented under its own first line, so a long sentence
	-- cannot be mistaken for a second speaker.
	if type(frame.SetIndentedWordWrap) == "function" then
		frame:SetIndentedWordWrap(true)
	end
	if type(frame.SetSpacing) == "function" then
		frame:SetSpacing(1)
	end
	log.bottomInsert = InsertBottom(frame)

	log:SetFontSize(M.font)
	if type(frame.SetTextColor) == "function" then
		frame:SetTextColor(C.text[1], C.text[2], C.text[3])
	end

	--------------------------------------------------------------------------
	-- Links
	--
	-- An item link somebody linked in party chat has to be hoverable and
	-- clickable, or the window is a downgrade from the one it replaced. The
	-- frame reports the click and the addon decides: a player name is ours,
	-- because clicking one should fill in our own field rather than open
	-- Blizzard's, and everything else goes to the client's own handler, which
	-- is what knows how to open an item, a quest, an achievement or a talent.
	--------------------------------------------------------------------------
	if type(frame.SetHyperlinksEnabled) == "function" then
		frame:SetHyperlinksEnabled(true)
		frame:SetScript("OnHyperlinkClick", function(_, link, text, button)
			if opts.onLink and opts.onLink(link, text, button) then
				return
			end
			if type(_G.SetItemRef) == "function" then
				_G.SetItemRef(link, text, button)
			end
		end)
		-- The addon's own box rather than the client's, which is the whole of
		-- what a link in a chat line used to get wrong: a line drawn in Arial
		-- Narrow on a flat black panel raised a gold-bordered parchment when
		-- you hovered a word in it. UI/Scan.lua reads the item's real text off
		-- the client and UI/Tooltip.lua draws it here, so the two look like one
		-- interface. A malformed link is a link somebody typed, and it comes
		-- back with nothing rather than raising, which opens no box at all.
		frame:SetScript("OnHyperlinkEnter", function(this, link)
			ns.Tip.Open(this, { kind = "item", link = link })
		end)
		frame:SetScript("OnHyperlinkLeave", function()
			ns.Tip.Close()
		end)
	end

	--------------------------------------------------------------------------
	-- Moving in it
	--------------------------------------------------------------------------
	if type(frame.EnableMouseWheel) == "function" then
		frame:EnableMouseWheel(true)
		frame:SetScript("OnMouseWheel", function(_, delta)
			-- Shift is the whole way, which is what the client's own chat does
			-- and the one shortcut worth keeping from it.
			if IsShiftKeyDown and IsShiftKeyDown() then
				log:ToEnd(delta > 0)
				return
			end
			for _ = 1, WHEEL_LINES do
				if delta > 0 then
					frame:ScrollUp()
				else
					frame:ScrollDown()
				end
			end
			log:Sync()
		end)
	end

	log.bar = UI.ScrollBar(container, function(_, value)
		-- The bar writes back to itself whenever a line arrives, and that write
		-- fires this. The latch is the one in UI/Scroll.lua and it is here for
		-- the same reason: without it the write and the handler chase each other
		-- for a frame every time somebody speaks.
		if log.syncing then
			return
		end
		log:ScrollTo(value)
	end)
	if log.bar then
		log.bar:SetPoint("TOPRIGHT")
		log.bar:SetPoint("BOTTOMRIGHT")
		log.bar:Hide()
	end

	-- The client reports its own scrolling, including the scroll it does for us
	-- when a line arrives while we are at the bottom, so the bar follows a page
	-- up as well as a drag.
	--
	-- Asked for by name rather than probed through SetScript, which every frame
	-- has: a script type this client does not carry is refused by SetScript
	-- itself, and that raise took the whole window down and left Blizzard's chat
	-- on the screen. 2.5.6 has no OnMessageScrollChanged, so the bar follows the
	-- wheel and the arrivals, both of which Sync themselves, and nothing else.
	if type(frame.HasScript) == "function" and frame:HasScript("OnMessageScrollChanged") then
		frame:SetScript("OnMessageScrollChanged", function()
			log:Sync()
		end)
	end

	return log
end

--------------------------------------------------------------------------
-- Size and font
--------------------------------------------------------------------------

-- The bar column is reserved whether or not the bar is showing, the same as the
-- scroll view's, and for the same reason: handing the width back when the
-- content fits would rewrap every line, which can make it not fit, which brings
-- the bar back. A layout that can argue with itself is a layout that flickers.
function Log:Resize(width, height)
	self.width, self.height = width, height
	self.frame:SetSize(width, height)
	self.view:SetSize(math.max(width - M.bar - M.gutter, 1), height)
	self:Sync()
	return width, height
end

-- One shared font object per size, out of UI/Text.lua's cache, so a size change
-- is one write here rather than one per line held.
--
-- Shadowed, not flat. Flat is the role for text on a surface this addon painted
-- and knows the colour of, and the chat window is not one: its background alpha
-- is a setting and it ships at zero, so every line anybody speaks is drawn
-- straight onto the world. In the Barrens at midday that is dark orange chat
-- text on bright orange ground and the log is unreadable. The role for text
-- over ground the addon did not paint is a shadow, and it is the only one that
-- fits here: an outline is what UI/Text.lua asks for over the world, but it
-- costs a pixel on every stroke and this font ships at eleven, well under
-- UI.OutlineFloor, so a rim would close the counters of every glyph it saved.
--
-- The shadow rides on the font object rather than on the frame because a
-- ScrollingMessageFrame makes its own font strings and they take the frame's
-- font instance whole, the same route the justification above takes.
function Log:SetFontSize(size)
	if self.fontSize == size then
		return false
	end
	self.fontSize = size
	if type(self.view.SetFontObject) == "function" then
		self.view:SetFontObject(UI.Font(size, UI.SHADOW))
	end
	-- After the object, never before. A font object carries a justification and
	-- the frame takes the object's, so a SetJustifyH written above this line is
	-- overwritten by it. UI/Text.lua now makes every object left justified,
	-- which is the fix; this is the assertion that the window this file draws
	-- does not depend on remembering it.
	if type(self.view.SetJustifyH) == "function" then
		self.view:SetJustifyH("LEFT")
	end
	return true
end

-- How opaque the bar beside the log is drawn, as a fraction of its own colours.
--
-- The chat window is what asks. Its background takes an opacity setting and the
-- bar was drawn at full alpha over it, so a window at twenty percent had a
-- black stripe down the side of it that nothing faded.
function Log:SetOpacity(fraction)
	self.opacity = fraction
	return UI.FadeBar(self.bar, fraction)
end

--------------------------------------------------------------------------
-- Lines
--------------------------------------------------------------------------

-- A line, and the colour to draw it in. The colour is per line rather than per
-- log because a chat window's whole legibility is that a whisper is not a
-- channel is not a guild line, and the client keeps the colour with the message
-- so a resize does not lose it.
function Log:Add(text, r, g, b)
	self.lines = self.lines + 1
	self.view:AddMessage(text, r or C.text[1], g or C.text[2], b or C.text[3])
	if not self.bulk then
		self:Sync()
	end
	return self.lines
end

-- Many lines at once, and one Sync at the end of them.
--
-- The case is the replay at login. Chat/History.lua hands back up to four
-- hundred lines said before the reload, each of them routed into every room it
-- belonged to, and each arrival was putting a scrollbar back in step with a
-- buffer three hundred and ninety nine lines short of where it was going to
-- end up. The bar only has to be right once, when the replay stops.
--
-- A pair rather than a flag the caller writes, so the log is the thing that
-- knows a bulk ended and the Sync cannot be forgotten at one of the call sites.
function Log:Bulk(on)
	self.bulk = on and true or false
	if not on then
		self:Sync()
	end
	return true
end

function Log:Clear()
	if type(self.view.Clear) == "function" then
		self.view:Clear()
	end
	self.lines = 0
	self:Sync()
end

function Log:Count()
	if type(self.view.GetNumMessages) == "function" then
		return self.view:GetNumMessages() or 0
	end
	return self.lines
end

--------------------------------------------------------------------------
-- Where you are in it
--
-- The frame counts in messages from the newest, where zero is the bottom. The
-- bar counts in the other direction, because a thumb at the top means the top
-- of the conversation, so every read and every write between the two is a
-- subtraction from the range. Getting that the wrong way round gives a bar that
-- works and runs backwards, which is why it is one function each way.
--------------------------------------------------------------------------

function Log:Displayed()
	if type(self.view.GetNumLinesDisplayed) == "function" then
		local shown = self.view:GetNumLinesDisplayed()
		if type(shown) == "number" and shown > 0 then
			return shown
		end
	end
	-- What the height can hold, when the client will not say. One line is the
	-- font plus the spacing this file set.
	return math.max(1, math.floor((self.height or 0) / ((self.fontSize or M.font) + 1)))
end

function Log:Range()
	return math.max(0, self:Count() - self:Displayed())
end

function Log:Offset()
	if type(self.view.GetScrollOffset) == "function" then
		return self.view:GetScrollOffset() or 0
	end
	return 0
end

function Log:AtBottom()
	if type(self.view.AtBottom) == "function" then
		return self.view:AtBottom() and true or false
	end
	return self:Offset() <= 0
end

function Log:ScrollTo(value)
	if type(self.view.SetScrollOffset) ~= "function" then
		return false
	end
	local range = self:Range()
	local offset = math.max(0, math.min(range - (value or 0), range))
	self.view:SetScrollOffset(offset)
	self:Sync()
	return true
end

function Log:ToEnd(top)
	if top then
		if type(self.view.ScrollToTop) == "function" then
			self.view:ScrollToTop()
		end
	elseif type(self.view.ScrollToBottom) == "function" then
		self.view:ScrollToBottom()
	end
	self:Sync()
end

-- On screen or not, and the bar caught up when it comes back.
--
-- The window keeps one of these per room and shows the room you are reading, so
-- a line that belongs to your party, your guild and Conversation lands in three
-- logs of which at most one is on the screen. The other two were measuring
-- their own buffers and writing their own scrollbars for nobody, and in a raid
-- that is most of what a chat line costs.
--
-- IsVisible rather than IsShown, because the room you are reading inside a
-- window you have closed is exactly as invisible as the two you are not, and
-- that is the case a busy evening with the chat window shut spends its time in.
--
-- The skipped writes are owed rather than lost. A log that refused a Sync is
-- marked, and coming back on screen pays the one that matters.
function Log:Show(on)
	self.frame:SetShown(on and true or false)
	if on and self.stale then
		self:Sync()
	end
	return true
end

-- Puts the bar back in step with the frame. Called after anything that could
-- have moved either, which is a line arriving, a scroll, a resize and a tab
-- coming up.
--
-- Every write is compared first. The range is compared against what this file
-- last wrote, because nothing else writes it; the value is compared against the
-- widget, because a drag writes that one from the other end and a drag past the
-- end leaves the thumb somewhere this file never put it. A room sitting at the
-- bottom of its own history, which is every room you are not scrolled back in,
-- writes one number per line instead of four.
function Log:Sync()
	local bar = self.bar
	if not bar then
		return false
	end
	if not self.frame:IsVisible() then
		self.stale = true
		return false
	end
	self.stale = false

	local range = self:Range()
	if range <= 0 then
		if self.barShown ~= false then
			self.barShown = false
			bar:Hide()
		end
		return false
	end

	local size = math.max(M.thumb,
		UI.Round(self.frame, (self.height or 0) * self:Displayed() / math.max(self:Count(), 1)))
	if self.thumbAt ~= size then
		self.thumbAt = size
		bar.thumb:SetSize(M.bar, size)
	end

	local at = range - self:Offset()
	self.syncing = true
	if self.rangeAt ~= range then
		self.rangeAt = range
		bar:SetMinMaxValues(0, range)
	end
	if bar:GetValue() ~= at then
		bar:SetValue(at)
	end
	self.syncing = nil

	if self.barShown ~= true then
		self.barShown = true
		bar:Show()
	end
	return true
end

-- One line for a status command. What is worth saying is the two things that
-- would be visibly wrong and silent: a client that would not turn the insert
-- order round, and one that refused the bar.
function Log:Describe()
	if not self.bottomInsert then
		return "the client refused to put new lines at the bottom"
	end
	if not self.bar then
		return "no scrollbar on this client, the wheel scrolls"
	end
	return ("%d lines"):format(self:Count())
end
