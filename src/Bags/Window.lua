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

local window, view, free, purse

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

local function Build()
	window = UI.Window({
		name = "WarriorKitBags",
		title = "Bags",
		width = Width(),
		height = FLOOR,
	})
	ns.Remember(window)

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

	Fit()

	-- The two numbers along the bottom, recorded on the window the way the
	-- clutter window records its card. Nothing in the addon reads them; the
	-- harness reads the strings the footer actually drew rather than going
	-- through a hook cut into this file for its benefit.
	window.free, window.purse = free, purse

	UI.OnRescale(function()
		if window then
			UI.Rezoom(window.frame, UI.WindowZoom())
			window.zoom = UI.WindowZoom()
		end
	end)
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
