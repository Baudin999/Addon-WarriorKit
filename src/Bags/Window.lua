local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

local Window = {}
ns.BagsWindow = Window

--------------------------------------------------------------------------
-- The bag window
--
-- One window, one scroll view, five marks along the top and the two numbers
-- along the bottom. Bags.lua answers what is in there and Grid.lua draws it;
-- this file owns when to ask and how big the answer is allowed to be.
--
-- **The free count is in the footer and it is half the reason the window
-- exists.** Every bag interface in the game makes you count the empty squares
-- yourself, and the number you actually want before a dungeon is one number.
-- It sits beside your gold because those are the two facts about your bags that
-- are not about any one item in them.
--
-- **The window redraws on the event and not on a clock.** A bag update arrives
-- in bursts, five of them for one loot, and each one is answered in full: a scan
-- of a hundred and fifty slots and a hundred and fifty anchors. That is what the
-- client's own bags do on the same event and it is cheaper than it sounds,
-- because the pool is already built and the scan allocates nothing per slot. A
-- clock would buy a fraction of that back and cost the thing the window is for,
-- which is looking at it and seeing what you just picked up.
--
-- Nothing is drawn at all while the window is shut. Every refresh below returns
-- early on a hidden window, so a character who never opens their bags pays for
-- this part exactly once, at the login that registers the events.
--
-- **The width is the grid's and the height is the piles'.** How many columns is
-- a setting, because how wide a bag window should be is a fact about your screen
-- and about how much of it you are willing to give a bag window. The height is
-- not a setting and it is not a constant either: it is whatever the piles came
-- to this scan, so a full bag is one page and you look at it rather than
-- scrolling it. That is the whole of what a bag window is for. Every other
-- window in this addon is a fixed rectangle because what goes in it is a feed
-- with no end; a bag has a hundred and fifty slots and that is the top of it.
--
-- The scroll view stays, and it is the answer to the one case the height cannot
-- reach: Window:Resize clamps to what the screen holds, so a bag that comes to
-- more than that gets a clamped window and a bar, rather than a window with its
-- footer under the taskbar.
--------------------------------------------------------------------------

-- The shortest the body is allowed to get, so an empty bag is a window rather
-- than a strip of title bar with a number under it. A heading and two rows of
-- squares, in UI/Slot.lua's numbers rather than the grid's, because the grid
-- does not own them either.
local FLOOR = UI.SLOT_HEADER + UI.SLOT * 2 + UI.SLOT_GAP

-- The title bar's buttons are squares, one mark each, at the height the close
-- cross already is. Five of them wearing words were a title bar that was more
-- word than title, and a word that changes as you press it, record to stop, is
-- a button that changes width under the pointer. A mark is one size forever
-- and the sentence a hover says is where the word went.
local ICON = M.title - 8

-- The marks, by the letter UI/Text.lua's glyph face carries each one on.
local FILTER, STACK, CLEAR, FORGET = "f", "=", "t", "e"
local RECORD, RECORDING = "o", "q"

local window, view, free, purse, stack, record, clear, forget, filter

-- The clutter window and the pickup filter, reached from here.
--
-- These are the two names in this file that are not the bag window's own, and
-- both are deliberate rather than convenient. Comfort/Destroy.lua is the only
-- file in the addon that destroys anything from a window and
-- Comfort/Clutter.lua is the only one that decides what may go; a clear button
-- that did the work here would be a second set of rules about what is finished
-- with, and the first time the two disagreed the bag window would be the one
-- destroying an item the other would have kept. The filter is the same
-- argument the other way round: Comfort/Wanted.lua owns the switch, and the
-- button here presses it rather than writing the two settings it stands for.
local function Clear()
	ns.Destroy.Show()
end

local function Filter()
	ns.Wanted.Toggle()
	ns.BagsWindow.Refresh()
end

--------------------------------------------------------------------------
-- What each mark says when you rest on it
--
-- Functions rather than strings, because three of the five read state: the
-- filter says what it is taking, the record button says which way the next
-- press goes, and forget says how much it is about to throw away.
--------------------------------------------------------------------------

local function FilterTip()
	if ns.Wanted.Running() then
		return { "Stop the pickup filter, so everything on a corpse comes home again.",
			"Taking " .. ns.Wanted.Describe() .. "." }
	end
	return { "Start the pickup filter: " .. ns.Wanted.Describe() .. " come home,"
		.. " and the rest is destroyed so the corpse can be skinned.",
		"What it takes is on the Loot page." }
end

local function StackTip()
	return "Put your half stacks together and free the slots under them."
end

local function ClearTip()
	return "Review what your bags are finished with, one card at a time."
end

local function RecordTip()
	if ns.BagsSession.Running() then
		return ("Stop recording %s. The pile stays at the top to sell later.")
			:format(ns.BagsSession.Name() or "this session")
	end
	return "Record what you pick up from here on, in a pile of its own at the top."
end

local function ForgetTip()
	local kinds = ns.BagsSession.Held()
	return ("Forget the last session's pile, %d item%s.")
		:format(kinds, kinds == 1 and "" or "s")
end

--------------------------------------------------------------------------

local function Width()
	return M.pad * 2 + ns.BagsGrid.Width(ns.db.bagColumns)
end

-- What the chrome costs: the difference between the window and its body, which
-- the window knows and this file asks rather than repeats.
local function Chrome()
	return window.height - window:Body()
end

-- The top edge held still across a resize.
--
-- A window is anchored wherever it was last dropped and that is usually its
-- middle, so a window that grows a row when you loot one grows half a row upward
-- into whatever you were reading. Re-pinning to the top left first makes it grow
-- downward, which is the direction a list grows.
--
-- The corner in the account file is untouched. That setting is written by the
-- drag and by nothing else, so this changes where the frame hangs this session
-- and not where it opens tomorrow. The offsets are read and written in the
-- frame's own units, which after adoption are not UIParent's, so the reading
-- goes straight back in without a conversion.
local function PinTop()
	local frame = window.frame
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left or not top then
		return false
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	return true
end

-- How far down the piles start. Nought unless the merchant row is up, which is
-- only while a vendor is open and only when it has something on it.
local bar = 0

-- What the piles came to on the last scan, and whether there has been one.
--
-- The height is the piles' and the piles are not known until a scan, so the
-- window is built at the floor and reaches its real height on the first draw.
-- That growth is not a resize anybody watched: it is the window arriving at the
-- size it was always going to be, off the top edge of a two row placeholder.
-- Pinning that edge and then growing a bag's worth of piles downward off it is
-- what opened the window half a bag below wherever it had been dragged, every
-- time, on a corner that was written down correctly and read back correctly.
--
-- So the pin is for the second scan onward, and a fit with no scan behind it
-- keeps the height the last one came to rather than dropping to the floor.
local piles, scanned = 0, false

-- The window at the size this scan's piles came to. `content` is what the grid
-- said it drew, or nothing before anything has been drawn.
local function Fit(content)
	if content then
		piles = content
	end
	local width = Width()
	local room = ns.BagsMerchant.Height()
	local height = M.pad * 2 + room + math.max(piles, FLOOR) + Chrome()
	-- Only when the number is about to move, and only once a scan has said what
	-- the height is. A bag update arrives five times for one loot and four of
	-- them come to the same height, and re-anchoring a window that is not
	-- changing size is a thing that can only go wrong.
	if height ~= window.height and scanned then
		PinTop()
	end
	window:Resize(width, height)
	-- The view moves down and up again as the merchant row arrives and leaves,
	-- and only then. Re-anchoring a frame that has not moved is the same thing
	-- the height guard above refuses to do, five times a loot.
	if room ~= bar then
		bar = room
		view.frame:ClearAllPoints()
		view.frame:SetPoint("TOPLEFT", M.pad, -(M.pad + room))
	end
	-- Body again rather than the number just asked for, because Resize clamps
	-- and the view has to be told the height the window actually got.
	view:Resize(width - M.pad * 2, window:Body() - M.pad * 2 - room)
	if content then
		scanned = true
	end
	return width
end

-- An item let go of over the window and not over a square.
--
-- A square is the client's own bag button and a drop on one is the client's
-- code, which puts the item in that slot. Everything else in the window, the
-- air between squares, a heading, the title bar, is this frame, and a frame
-- with no answer for the drop leaves the item on the cursor, so the player
-- who pulled a helmet off the character sheet and let go of it over their
-- bags is still holding it. Dropped anywhere on the window it goes in the
-- first bag with room, which is what dropping it on the bag buttons along the
-- bar would have done, and is the only thing "into my bag" can mean.
--
-- Two scripts rather than one, for the reason UI/Widgets.lua gives its drop
-- square: an item picked up with a click arrives as a mouse up and one dragged
-- off a slot arrives as a received drag, and a window that listened for one
-- would take a helmet and refuse a sword. Nothing is drawn here: the client
-- fires the bag update the move causes and the window redraws on that, the
-- same as for anything else that lands in a bag.
local function Drop()
	ns.Stow()
end

-- The five marks along the top, in the title bar beside the close cross,
-- which is where UI/Window.lua already puts the settings window's search
-- field. They belong there for the reason that one does: each is a control
-- over the whole window rather than over anything in it. The footer is the
-- two numbers and nothing else, so the free count and your gold have the
-- whole width between them.
--
-- Right to left, so the one you press most is nearest the cross: record,
-- clear, stack, filter, and forget on the far left, up only while there is
-- a session to be rid of.
local function Marks()
	record = UI.Button(window.frame, { label = RECORD, glyph = true,
		width = ICON, height = ICON, tip = RecordTip,
		onClick = ns.BagsSession.Press })
	record:SetPoint("TOPRIGHT", window.close, "TOPLEFT", -M.rowGap, 0)

	-- The button you press when the footer says nought free, which is why it
	-- is on the bag window at all rather than only on the settings page.
	clear = UI.Button(window.frame, { label = CLEAR, glyph = true,
		width = ICON, height = ICON, tip = ClearTip, onClick = Clear })
	clear:SetPoint("TOPRIGHT", record, "TOPLEFT", -M.rowGap, 0)

	-- It used to sit in the footer between the two numbers, because it is the
	-- one thing in this window that changes both of them. It is up whatever
	-- you are standing in front of, unlike the merchant row, because loose
	-- stacks are not a vendor's business.
	stack = UI.Button(window.frame, { label = STACK, glyph = true,
		width = ICON, height = ICON, tip = StackTip,
		onClick = ns.BagsStack.Press })
	stack:SetPoint("TOPRIGHT", clear, "TOPLEFT", -M.rowGap, 0)

	-- The pickup filter, which is the mode you switch on for a run of an old
	-- dungeon. Green while it is on, the way record is green while it is
	-- recording, because a mode you forgot you left on is the one thing about
	-- it that has to be visible from across the room.
	filter = UI.Button(window.frame, { label = FILTER, glyph = true,
		width = ICON, height = ICON, tip = FilterTip, onClick = Filter })
	filter:SetPoint("TOPRIGHT", stack, "TOPLEFT", -M.rowGap, 0)

	-- Far left, and only up while there is a session to be rid of.
	--
	-- It is an eraser rather than the bin because the bin is already up there
	-- and means something else: that one opens the destroy window to make
	-- room, and this one throws away a record of an hour. Two marks a pixel
	-- apart looking alike, meaning two different things, is worse than either
	-- being slightly wrong on its own.
	--
	-- Hidden while there is nothing recorded, because stop and forget are two
	-- presses on purpose. Stop leaves the pile there to work through at a
	-- vendor; this is the press for the evening you want it gone early, and the
	-- next session clears it for you anyway. A character who has never recorded
	-- a run never sees it.
	forget = UI.Button(window.frame, { label = FORGET, glyph = true,
		width = ICON, height = ICON, tip = ForgetTip,
		onClick = ns.BagsSession.Forget })
	forget:SetPoint("TOPRIGHT", filter, "TOPLEFT", -M.rowGap, 0)
	forget:Hide()
end

local function Build()
	window = UI.Window({
		name = "WarriorKitBags",
		title = "Bags",
		width = Width(),
		height = FLOOR,
		zoom = function() return ns.Zoom("bagsZoom") end,
	})
	ns.Remember(window)
	-- Hooked rather than set, because the frame is placeable and its drag
	-- handlers are UI/Placeable.lua's.
	window.frame:HookScript("OnReceiveDrag", Drop)
	window.frame:HookScript("OnMouseUp", Drop)

	view = UI.ScrollView(window.content, { overlay = true })
	view.frame:SetPoint("TOPLEFT", M.pad, -M.pad)
	ns.BagsGrid.Attach(view.canvas)

	-- Over the piles rather than in the footer. The two numbers along the bottom
	-- are up whatever you are standing in front of and they must not move; a row
	-- that comes and goes with the merchant belongs at the edge that is already
	-- the top of a list that changes height every time you loot.
	ns.BagsMerchant.Attach(window.content)

	free = UI.Label(window.footer, M.font, C.text, "LEFT", UI.FLAT)
	free:SetPoint("LEFT")
	UI.Wrap(free, false)

	purse = UI.Label(window.footer, M.font, C.dim, "RIGHT", UI.FLAT)
	purse:SetPoint("RIGHT")
	UI.Wrap(purse, false)

	Marks()

	Fit()

	-- The two numbers along the bottom and the five marks along the top,
	-- recorded on the window the way the clutter window records its card.
	-- Nothing in the addon reads them; the harness reads the strings the footer
	-- actually drew and presses the buttons rather than going through a hook
	-- cut into this file for its benefit.
	window.free, window.purse, window.stack = free, purse, stack
	window.record, window.clear, window.forget = record, clear, forget
	window.filter = filter

	return window
end

--------------------------------------------------------------------------

-- The whole of what a bag update does. False on a window nobody has opened,
-- which is what keeps this part free for a player who leaves it switched off.
function Window.Refresh()
	if not window or not window:IsShown() then
		return false
	end
	-- Timed under its own slot on the performance tab, the way a tick is. It is
	-- not a tick, and that is why it needs one: at a vendor with the sale
	-- sweeping, the bag events book this close to ten times a second, and a
	-- pass that walks every slot, grades every item and lays out every square
	-- is the most expensive thing the addon does on an event. The bracket
	-- is here rather than in Booked so a press and a loot line are measured
	-- the same as a bag update.
	ns.Perf.Start("bags")
	local state = ns.Bags.Read()
	-- Before the grid and before the fit. What the row says comes out of this
	-- scan, and whether it is up decides both how far down the first pile starts
	-- and how tall the window comes to.
	ns.BagsMerchant.Paint(state)
	local content = ns.BagsGrid.Paint(state, ns.db.bagColumns)
	Fit(content)
	view:Update(content)
	free:SetText(("%d free of %d"):format(state.free, state.slots))
	purse:SetText(ns.Coined(GetMoney()))
	-- The mark and the colour together, because they say one thing between
	-- them: a stop square on green while it is recording, and a circle on the
	-- button's own control grey when it is not. `tone` as well as the tint,
	-- because UI.Button repaints its background from that field every time the
	-- mouse leaves it.
	local recording = ns.BagsSession.Running()
	record.text:SetText(recording and RECORDING or RECORD)
	record.tone = recording and C.tick or C.control
	UI.Tint(record.bg, record.tone)
	-- The filter keeps its mark and changes colour, for the same reason and in
	-- the same green. It is read here rather than watched, so a switch thrown
	-- from the page catches up on the next bag event or the next open.
	filter.tone = ns.Wanted.Running() and C.tick or C.control
	UI.Tint(filter.bg, filter.tone)
	forget:SetShown(ns.BagsSession.Held() > 0)
	ns.Perf.Stop("bags")
	return true
end

-- The window at the width the column setting now asks for. Called from the
-- panel rather than watched for, because a setting this file may not name is a
-- setting this file may not watch either.
--
-- Only the width is set here. Fewer columns is more rows, and how many rows the
-- new width comes to is a thing only the grid can say, so the height arrives out
-- of the refresh below like it does on every other pass.
function Window.Refit()
	if not window then
		return false
	end
	Fit()
	Window.Refresh()
	return true
end

function Window.Show()
	if not ns.db.bags then
		return false
	end
	if not window then
		Build()
	end
	window:Show()
	Window.Refresh()
	return true
end

function Window.Hide()
	if not window then
		return false
	end
	window:Hide()
	return true
end

function Window.Toggle()
	if Window.Shown() then
		return Window.Hide()
	end
	return Window.Show()
end

function Window.Shown()
	return (window and window:IsShown()) and true or false
end

function Window.Frame()
	return window
end

function Window.Describe()
	if not ns.db.bags then
		return "off"
	end
	if not window then
		return "not built yet"
	end
	local held, slots = ns.Bags.Free()
	return ("%s, %d free of %d")
		:format(window:IsShown() and "open" or "shut", held, slots)
end

--------------------------------------------------------------------------
-- What makes it redraw
--
-- BAG_UPDATE is a slot changing. ITEM_LOCK_CHANGED is a stack picked up or put
-- down, which is what makes a square go dark while the cursor holds it.
-- PLAYER_MONEY is the number on the right. GET_ITEM_INFO_RECEIVED is the one
-- that is not obvious: an item the client had not cached is graded nil, so it
-- sits in its class pile rather than in Junk until the answer arrives, and this
-- is the arrival.
--
-- One redraw a frame, whatever the client says in it. Every one of these fires
-- more than once for one thing happening: BAG_UPDATE comes once per bag, so
-- looting a stack that spills across two bags is two, and a vendor sale that
-- moves the money is a third with PLAYER_MONEY behind it. A refresh reads every
-- slot you own, regrades every item and lays the piles out again, so paying for
-- it four times in a frame is four full passes to draw one picture.
--
-- Booked rather than run, the way Core's binding pass is booked: the events set
-- a flag, an OnUpdate that only exists while one is booked runs the refresh on
-- the next frame, and it hands its own handler back. A frame in which nothing
-- moved costs nothing at all.
--------------------------------------------------------------------------

local events = CreateFrame("Frame")

-- cold: the redraw one frame after a bag moved, which is a change rather than a
-- tick: the frame is given an OnUpdate only while a refresh is booked and takes
-- it away again in the pass.
local function Booked(self)
	self:SetScript("OnUpdate", nil)
	Window.Refresh()
end

local function Book()
	events:SetScript("OnUpdate", Booked)
end

events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("ITEM_LOCK_CHANGED")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", Book)
