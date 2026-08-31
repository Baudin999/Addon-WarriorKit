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
-- **The width is the grid's and the height is fixed.** How many columns is a
-- setting, because how wide a bag window should be is a fact about your screen
-- and about how much of it you are willing to give a bag window. The height is
-- not, for the reason every window in this addon is a fixed rectangle: a pile
-- that does not fit scrolls.
--------------------------------------------------------------------------

local HEIGHT = 420

local window, view, free, purse

--------------------------------------------------------------------------

local function Width()
	return M.pad * 2 + ns.BagsGrid.Width(ns.db.bagColumns)
end

local function Fit()
	local width = Width()
	window:Resize(width, HEIGHT)
	view:Resize(width - M.pad * 2, window:Body() - M.pad * 2)
	return width
end

local function Build()
	window = UI.Window({
		name = "WarriorKitBags",
		title = "Bags",
		width = Width(),
		height = HEIGHT,
	})
	ns.Remember(window)

	view = UI.ScrollView(window.content, { overlay = true })
	view.frame:SetPoint("TOPLEFT", M.pad, -M.pad)
	ns.BagsGrid.Attach(view.canvas)

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
	view:Update(ns.BagsGrid.Paint(state, ns.db.bagColumns))
	free:SetText(("%d free of %d"):format(state.free, state.slots))
	purse:SetText(ns.Coined(GetMoney()))
	return true
end

-- The window at the width the column setting now asks for. Called from the
-- panel rather than watched for, because a setting this file may not name is a
-- setting this file may not watch either.
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
