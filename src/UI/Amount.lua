local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

--------------------------------------------------------------------------
-- How many
--
-- One number, picked before something happens to that many of a thing. Buying
-- five stacks of water off a vendor is the first of them; splitting a pile in
-- your bags is the same window with a different sentence under the number, and
-- so is every trade, mail and bank move after that. So it is one window rather
-- than one per site, for the reason UI/Ask.lua is one window: the question has
-- the same shape everywhere it is asked.
--
-- **It is not UI.Ask with a number bolted on.** A question is answered yes or
-- no and the window is a sentence. This is answered with a quantity, which
-- means the window has to say what each quantity comes to before you commit to
-- it: twenty water and two silver fifty is a different decision from four water
-- and fifty copper, and reading it off the number alone is arithmetic the
-- player should not be doing at a vendor. `note` is where the caller writes
-- that line, because what a count comes to is the caller's business and the
-- three ways to set the count are this file's.
--
-- **Three ways to set it, because three habits exist.** The two ends nudge by
-- one, the bar is dragged when the range is long enough that nudging is twenty
-- clicks, and the wheel works anywhere over the window because that is what a
-- wheel over a number does everywhere else. All three land in one place, which
-- is what keeps the readout, the bar and the sentence from disagreeing.
--
-- **The bar is optional and the window is not.** Slider is a frame type rather
-- than a template so it needs no Blizzard XML, but nothing installed on 2.5.6
-- proves it takes a thumb texture from a stranger, so it is probed exactly the
-- way UI/Scroll.lua probes it. Refused, the window loses the drag and keeps the
-- two ends, the wheel and the readout, which is a worse window rather than a
-- broken one.
--
-- **One window, reused.** Every popup in this addon is built once and
-- repainted, for the reason UI/Widgets.lua's dropdown gives: this client cannot
-- destroy a frame, so a window made per question is a window leaked per
-- question. Two of these cannot be on the screen at once, which is the
-- behaviour you want from a window that spends money.
--------------------------------------------------------------------------

local WIDTH = 236

-- The number this window is about, drawn bigger than anything else on it.
--
-- Its own size rather than M.heading, and the reason is what the window is for.
-- Everything else here is a label on the thing you are choosing; this is the
-- choice. It is read from across a stepper you are clicking rather than looked
-- at, and at body size it sat between two buttons and looked like a caption
-- rather than the answer.
local NUMBER = 18

-- The bar under the readout: the scrollbar's track, lying down, with a thumb
-- you can actually grab. Twelve wide rather than the scrollbar's twenty four
-- long, because a horizontal thumb that wide covers a fifth of the track on a
-- range of five.
local TRACK, THUMB = M.bar, 12

-- The window, and what it is asking about right now. `asked` is nil whenever
-- nothing is on the screen, which is what makes UI.Amounting answerable and
-- what stops a stale callback firing after the window was closed some other
-- way.
local window, asked = nil, nil

-- The range and the callback the open window is working under. Held here rather
-- than on the frame because nothing outside this file may set a count that is
-- not in the range it was opened with.
local low, high, count = 1, 1, 1
local note, onAccept

local function Close()
	asked = nil
	if window then
		window:Hide()
	end
end

--------------------------------------------------------------------------
-- The one place the number changes
--------------------------------------------------------------------------

-- The count, clamped, with everything that says it repainted.
--
-- The bar is written back as well as read, and the latch is why: a drag fires
-- OnValueChanged, which lands here, which writes the bar, which fires it again.
-- The same shape the scroll view's own bar has, for the same reason.
local function Set(value)
	value = math.floor(tonumber(value) or low)
	if value < low then
		value = low
	elseif value > high then
		value = high
	end
	count = value
	window.readout:SetText(tostring(count))

	local text, tone = nil, nil
	if note then
		text, tone = note(count)
	end
	window.note:SetText(text or "")
	tone = tone or C.dim
	window.note:SetTextColor(tone[1], tone[2], tone[3])

	if window.bar then
		window.syncing = true
		window.bar:SetValue(count)
		window.syncing = false
	end
	return count
end

local function Nudge(delta)
	if not asked then
		return nil
	end
	return Set(count + delta)
end

--------------------------------------------------------------------------
-- Building it
--------------------------------------------------------------------------

-- The thing being counted, along the top: the addon's own square with its
-- picture on it, and its name beside it in its own grade.
local function Subject()
	window.square = UI.Slot(window.content, UI.SLOT)
	window.square:SetPoint("TOPLEFT", M.pad, -M.pad)

	window.label = UI.Label(window.content, M.font, C.text, "LEFT", UI.FLAT)
	window.label:SetPoint("LEFT", window.square, "RIGHT", M.gutter, 0)
	window.label:SetWidth(WIDTH - M.pad * 2 - UI.SLOT - M.gutter)
	UI.Wrap(window.label, false)
end

-- The two ends and the number between them.
local function Stepper()
	local minus = UI.Button(window.content, { label = "-", glyph = true,
		width = M.row, onClick = function() Nudge(-1) end })
	minus:SetPoint("TOPLEFT", M.pad, -(M.pad + UI.SLOT + M.rowGap * 2))

	local plus = UI.Button(window.content, { label = "+", glyph = true,
		width = M.row, onClick = function() Nudge(1) end })
	plus:SetPoint("TOPRIGHT", -M.pad, -(M.pad + UI.SLOT + M.rowGap * 2))

	window.readout = UI.Label(window.content, NUMBER, C.heading, "CENTER", UI.FLAT)
	window.readout:SetPoint("LEFT", minus, "RIGHT", M.rowGap, 0)
	window.readout:SetPoint("RIGHT", plus, "LEFT", -M.rowGap, 0)
	UI.Wrap(window.readout, false)
	window.minus, window.plus = minus, plus
end

-- The bar, dressed the way UI/Scroll.lua dresses its own and lying down. Pulled
-- out so the whole of it can be pcalled: a client that refuses a thumb texture
-- has to cost the drag and nothing else.
local function Dress(bar)
	bar:SetOrientation("HORIZONTAL")
	bar:SetHeight(TRACK)
	bar:SetMinMaxValues(1, 1)
	bar:SetValue(1)
	if bar.SetValueStep then
		bar:SetValueStep(1)
	end
	-- Without this a drag reports fractions and the step applies to a click
	-- alone, which is a readout counting in halves while the thumb is held.
	if bar.SetObeyStepOnDrag then
		bar:SetObeyStepOnDrag(true)
	end
	bar.track = ns.Fill(bar, "BACKGROUND", C.sunken[1], C.sunken[2], C.sunken[3], 1)
	bar.track:SetAllPoints()
	bar.thumb = ns.Fill(bar, "ARTWORK", C.edge[1], C.edge[2], C.edge[3], 1)
	bar.thumb:SetSize(THUMB, TRACK)
	bar:SetThumbTexture(bar.thumb)
end

local function OnValue(_, value)
	if window and window.syncing then
		return
	end
	Set(value)
end

local function Bar()
	local made, bar = pcall(CreateFrame, "Slider", nil, window.content)
	if not made or not bar or type(bar.SetOrientation) ~= "function"
		or type(bar.SetThumbTexture) ~= "function" then
		return nil
	end
	if not pcall(Dress, bar) then
		bar:Hide()
		return nil
	end
	bar:SetPoint("TOPLEFT", M.pad, -(M.pad + UI.SLOT + M.row + M.rowGap * 4))
	bar:SetPoint("TOPRIGHT", -M.pad, -(M.pad + UI.SLOT + M.row + M.rowGap * 4))
	bar:SetScript("OnValueChanged", OnValue)
	return bar
end

-- The wheel, over the whole window rather than over the bar. A wheel that only
-- works on an eight pixel strip is a wheel nobody finds.
local function OnWheel(_, delta)
	Nudge(delta > 0 and 1 or -1)
end

local function Build()
	if window then
		return window
	end

	window = UI.Window({
		name = "WarriorKitAmount",
		title = "",
		width = WIDTH,
		height = M.title + M.footer + M.pad * 2 + UI.SLOT + M.row,
		-- Over every other window in the addon, for the reason UI/Ask.lua asks
		-- for the same strata: this opens on top of the window that raised it
		-- and every other window here is on DIALOG.
		strata = "FULLSCREEN_DIALOG",
	})

	Subject()
	Stepper()
	window.bar = Bar()

	window.note = UI.Label(window.content, M.small, C.dim, "LEFT", UI.FLAT)
	window.note:SetPoint("TOPLEFT", M.pad, -(M.pad + UI.SLOT + M.row + M.rowGap * 4
		+ (window.bar and TRACK + M.rowGap * 2 or 0)))
	window.note:SetWidth(WIDTH - M.pad * 2)
	UI.Wrap(window.note, false)

	window.accept = UI.Button(window.footer, {
		label = "buy",
		width = 92,
		tone = C.accent,
		onClick = function() UI.Take(true) end,
	})
	window.accept:SetPoint("RIGHT", 0, 0)

	window.refuse = UI.Button(window.footer, {
		label = "cancel",
		width = 76,
		onClick = function() UI.Take(false) end,
	})
	window.refuse:SetPoint("RIGHT", window.accept, "LEFT", -M.rowGap, 0)

	window.frame:EnableMouseWheel(true)
	window.frame:SetScript("OnMouseWheel", OnWheel)

	-- Escape, the close box and anything else that takes the window off the
	-- screen are all the same answer, and it is no. Hung on the frame rather
	-- than on the method for the reason UI/Window.lua hangs its own cleanup
	-- there: UISpecialFrames calls Hide and knows nothing about this file.
	window.frame:HookScript("OnHide", function()
		asked = nil
	end)
	return window
end

-- How tall the window came out, which is the chrome, the subject, the stepper,
-- the bar where there is one, and the line under it. Written as the pieces
-- rather than as a number, so a metric moving moves the window.
local function Height()
	return M.title + M.footer + M.pad * 2 + UI.SLOT + M.rowGap * 2 + M.row
		+ (window.bar and TRACK + M.rowGap * 2 or 0)
		+ M.rowGap * 2 + M.small
end

--------------------------------------------------------------------------

-- Put the number up.
--
--   title     what the window is called
--   name      the thing being counted, and its picture, grade and batch size
--   low, high the ends of the range, inclusive
--   value     where the number starts, clamped into the range
--   note      handed the count, answers the line under it and a colour for it
--   accept    the word on the button that does the thing
--   onAccept  handed the count when that button is pressed, and never otherwise
--
-- Answers the count the window opened on, so a caller can say what it asked.
function UI.Amount(opts)
	Build()
	asked = true

	low = math.max(1, math.floor(opts.low or 1))
	high = math.max(low, math.floor(opts.high or low))
	note, onAccept = opts.note, opts.onAccept

	window:SetTitle(opts.title or "")
	window.label:SetText(opts.name or "")
	local ink = UI.SlotInk(opts.quality)
	window.label:SetTextColor(ink[1], ink[2], ink[3])
	UI.SlotPaint(window.square, opts.icon, opts.each, opts.quality, false)

	window.accept.text:SetText(opts.accept or "yes")
	if window.bar then
		window.syncing = true
		window.bar:SetMinMaxValues(low, high)
		window.syncing = false
		-- A range of one is a bar with nowhere to go. It is drawn quiet rather
		-- than taken off the window, because a window that changes height with
		-- the vendor's stock is a window whose buttons move under the cursor.
		UI.FadeBar(window.bar, high > low and 1 or 0.35)
		window.bar:EnableMouse(high > low)
	end

	Set(opts.value or low)
	window:Resize(WIDTH, Height())
	window:Show()
	return count
end

-- The count on the screen now, or nil. Public because a part that put one up
-- has to be able to tell whether the player has dealt with it, and because it
-- is the only way a test can read the window without naming its frames.
function UI.Amounting()
	return asked and count or nil
end

-- Set it from outside, clamped to the range the window was opened with. The
-- wheel and the two ends go through Set directly; this is for a caller that
-- knows the number it wants, and for the harness.
function UI.Choose(value)
	if not asked then
		return nil
	end
	return Set(value)
end

-- Press one of the two buttons. Answers whether there was a count to answer
-- with, so a caller pressing this blind can tell the difference between a
-- window it closed and one that was not there.
function UI.Take(yes)
	if not asked then
		return false
	end
	local going, chosen = onAccept, count
	Close()
	if yes and going then
		going(chosen)
	end
	return true
end
