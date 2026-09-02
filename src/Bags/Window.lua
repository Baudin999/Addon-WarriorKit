local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

local Window = {}
ns.BagsWindow = Window

--------------------------------------------------------------------------
-- The bag window
--
-- One window, one scroll view, and the two numbers along the bottom. Bags.lua
-- answers what is in there and Grid.lua draws it; this file owns when to ask
-- and how big the answer is allowed to be.
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

-- The stack button's width, fixed rather than sized to its word. The merchant
-- row's buttons carry numbers that change as you sell and are measured for that
-- reason; this one says the same thing forever and a fixed width keeps it
-- centred between two numbers that are both changing under it.
local STACK_WIDTH = 60

-- The record button in the title bar, wide enough for the longer of the two
-- words it says. Fixed rather than measured, because a button that shrinks when
-- you press it is a button that moves out from under the pointer.
local RECORD_WIDTH = 54

-- The clear button beside it, and it says one word forever.
local CLEAR_WIDTH = 44

-- The forget button, wide enough for its word. It sits left of clear and is
-- only up while a session is holding something.
local FORGET_WIDTH = 48

local window, view, free, purse, stack, record, clear, forget

-- The clutter window, opened from here.
--
-- This is the one name in this file that is not the bag window's own, and it is
-- deliberate rather than convenient. Comfort/Destroy.lua is the only file in
-- the addon that destroys anything and Comfort/Clutter.lua is the only one that
-- decides what may go; a clear button that did the work here would be a second
-- set of rules about what is finished with, and the first time the two
-- disagreed the bag window would be the one destroying an item the other would
-- have kept.
local function Clear()
	ns.Destroy.Show()
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

	-- Between the two numbers, because it is the one thing in this window that
	-- changes both of them: every pair of half stacks it puts together is a slot
	-- back on the left, and it is the only control the window has that is not
	-- about one square. It is up whatever you are standing in front of, unlike
	-- the merchant row, because loose stacks are not a vendor's business.
	stack = UI.Button(window.footer, { label = "stack", width = STACK_WIDTH,
		height = M.row, onClick = ns.BagsStack.Press })
	stack:SetPoint("CENTER")

	-- In the title bar rather than the footer, beside the close cross, which is
	-- where UI/Window.lua already puts the settings window's search field. It
	-- belongs there for the same reason that one does: it is a control over the
	-- whole window rather than over anything in it, and the footer's stack
	-- button is centred between the free count and your gold on purpose, so a
	-- second button there would take that arrangement apart.
	record = UI.Button(window.frame, { label = ns.BagsSession.Label(),
		width = RECORD_WIDTH, height = M.title - 8, size = M.small,
		onClick = ns.BagsSession.Press })
	record:SetPoint("TOPRIGHT", window.close, "TOPLEFT", -M.rowGap, 0)

	-- Beside record and for the same reason it is up there: it is a control
	-- over the whole window rather than over any one square. It is the button
	-- you press when the footer says nought free, which is why it is on the bag
	-- window at all rather than only on the settings page.
	clear = UI.Button(window.frame, { label = "clear", width = CLEAR_WIDTH,
		height = M.title - 8, size = M.small, onClick = Clear })
	clear:SetPoint("TOPRIGHT", record, "TOPLEFT", -M.rowGap, 0)

	-- Left of clear, and only up while there is a session to be rid of.
	--
	-- It says forget rather than clear because the button beside it already
	-- says clear and means something else: that one opens the destroy window to
	-- make room, and this one throws away a record of an hour. Two buttons a
	-- pixel apart wearing one word, meaning two different things, is worse than
	-- either word being slightly wrong on its own.
	--
	-- Hidden while there is nothing recorded, because stop and forget are two
	-- presses on purpose. Stop leaves the pile there to work through at a
	-- vendor; this is the press for the evening you want it gone early, and the
	-- next session clears it for you anyway. A character who has never recorded
	-- a run never sees it.
	forget = UI.Button(window.frame, { label = "forget", width = FORGET_WIDTH,
		height = M.title - 8, size = M.small, onClick = ns.BagsSession.Forget })
	forget:SetPoint("TOPRIGHT", clear, "TOPLEFT", -M.rowGap, 0)
	forget:Hide()

	Fit()

	-- The two numbers along the bottom and the button between them, recorded on
	-- the window the way the clutter window records its card. Nothing in the
	-- addon reads them; the harness reads the strings the footer actually drew
	-- and presses the button rather than going through a hook cut into this file
	-- for its benefit.
	window.free, window.purse, window.stack = free, purse, stack
	window.record, window.clear, window.forget = record, clear, forget

	return window
end

--------------------------------------------------------------------------

-- The whole of what a bag update does. False on a window nobody has opened,
-- which is what keeps this part free for a player who leaves it switched off.
function Window.Refresh()
	if not window or not window:IsShown() then
		return false
	end
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
	-- The word and the colour together, because they say one thing between them:
	-- green while it is recording, and the button's own control grey when it is
	-- not. `tone` as well as the tint, because UI.Button repaints its background
	-- from that field every time the mouse leaves it.
	record.text:SetText(ns.BagsSession.Label())
	record.tone = ns.BagsSession.Running() and C.tick or C.control
	UI.Tint(record.bg, record.tone)
	forget:SetShown(ns.BagsSession.Held() > 0)
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
--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("ITEM_LOCK_CHANGED")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function()
	Window.Refresh()
end)
