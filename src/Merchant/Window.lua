local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

local Window = {}
ns.MerchantWindow = Window

--------------------------------------------------------------------------
-- The merchant window
--
-- One window, one scroll view, and the two numbers along the bottom. Stock.lua
-- answers what the vendor has and Grid.lua draws it; this file owns when to ask
-- and how big the answer is allowed to be.
--
-- **It is the bag window's shape in the two places that matter and its own
-- everywhere else.** The two are open at the same time and they are the same
-- act: what you have, and what he has. The piles are the same piles under the
-- same headings, the square is the same square, and your purse is in the same
-- corner of the footer. The width and the height are this window's own.
--
-- The bag window grows to fit what it is drawing, and it argues for that: a bag
-- has a hundred and fifty slots and that is the top of it, so you would rather
-- look at it than scroll it. A vendor's rack has no such top. A quartermaster
-- sells sixty things, and this window grew to fit all sixty, hit the clamp at
-- eighty six percent of the screen, and kept its old top edge, so most of the
-- list hung off the bottom of the screen and the rows down there were nowhere a
-- click could reach. That is the shape UI/Window.lua's header already rules on:
-- the window is a fixed rectangle and what does not fit scrolls.
--
-- Ten lines of two cards is twenty things at once, which is every ordinary
-- vendor in the game whole and a quartermaster in three flicks of a wheel. The
-- client's own frame shows ten and pages; this shows twice that and scrolls.
--
-- **Closing the window walks away from the vendor.** The client's own merchant
-- frame is parked off the side of the screen while this one is up, so its cross
-- is nowhere a cursor can reach and the session would otherwise stay open until
-- you ran out of range. Every way out of this window goes through the frame's
-- own OnHide, which is where escape and the close box both land, so there is
-- one place that ends the session rather than one per exit.
--
-- **Two racks, one window, one tab across the top.** What he sells and what you
-- have sold are the two halves of a merchant session, and the second one is the
-- game's only undo for a sale. The client keeps it behind the second tab of its
-- own frame, and that frame is parked off the side of the screen for the whole
-- session, so replacing the merchant window without replacing buyback left an
-- hour-long safety net nothing could reach. Both racks are drawn by one pool of
-- cards out of Grid.lua and the tab says which one is under it.
--
-- **The title is the vendor's name.** It is the one thing about a merchant
-- window worth a title bar: you talk to four of them in a row in a capital and
-- the rack alone does not always say which. A client that will not answer gets
-- the plain word.
--------------------------------------------------------------------------

-- How wide the window is: two cards, in Grid.lua's cards.
--
-- Two because that is the client's own merchant frame, and because a card is
-- wide enough to hold a name and a price without cutting either. It was the bag
-- window's column setting for a day, on the argument that two windows open
-- beside each other should be the same width. That argument was answering the
-- wrong question. The bag window's width is how many pictures fit on a line and
-- this one's is how long an item's name is, and tying the second to the first
-- gave the rack a width nothing about a rack had asked for.
--
-- A fixed count rather than a setting of its own. A card has one right width,
-- which is the width of the longest thing a vendor sells; the only choice left
-- is how many of them, and a third column is wider than the game's own window
-- for a list you are already scrolling.
local COLUMNS = 2

local function Width()
	return M.pad * 2 + ns.MerchantGrid.Span(COLUMNS)
end

-- How tall the rack is, and it does not move.
--
-- Ten lines of cards and four pile headings, which is twenty entries on the
-- screen at once and every ordinary vendor's whole stock. Written as the pieces
-- rather than as one number so that a card or a heading changing size moves it,
-- which is what stopped it being a number somebody has to remember to revisit.
--
-- It is a size rather than a count of what this vendor has, so the window is
-- the same shape whatever you walk up to: a window that is a different height
-- at every vendor is a window whose close cross is somewhere new every time.
--
-- It is how tall the rack is and not how tall the window is. The tab strip is
-- added on top of it once the strip has said how tall it came out, so putting
-- the second rack in cost a row of tabs rather than a row of stock.
--
-- A card is a square tall, so the lines below are Grid.lua's rows and
-- UI/Slot.lua's numbers still measure them.
local LINES, PILES = 10, 4
local HEIGHT = LINES * UI.SLOT + (LINES - 1) * UI.SLOT_GAP
	+ PILES * (UI.SLOT_HEADER + UI.SLOT_BREAK)

-- Which tab is which. The rack first, because that is what you walked up to
-- him for; buyback is where you go when something went wrong.
local RACK, BOUGHT = 1, 2

local window, view, tabs, tally, purse
local page = RACK
local session = false

-- How tall the tab strip came out, which is a number only the strip can answer
-- and everything under it has to be told.
local strip = 0

-- How wide the rack itself is: the window without its margins. The one number
-- Grid.lua is handed, because how many cards that holds is its business.
local function Rack()
	return window.width - M.pad * 2
end

local function Build()
	window = UI.Window({
		name = "WarriorKitMerchant",
		title = "Merchant",
		width = Width(),
		height = HEIGHT,
		zoom = function() return ns.Zoom("merchantZoom") end,
	})
	ns.Remember(window)

	tabs = UI.TabStrip(window.content, { onSelect = function(index)
		page = index
		Window.Refresh()
	end })
	tabs.frame:SetPoint("TOPLEFT", M.pad, 0)
	tabs.frame:SetPoint("TOPRIGHT", -M.pad, 0)
	tabs:Add("Rack")
	tabs:Add("Buyback")

	view = UI.ScrollView(window.content, { overlay = true })
	ns.MerchantGrid.Attach(view.canvas)

	-- The strip has no height until it has been resized and the view has nowhere
	-- to hang until the strip has one, so both are done here and in that order.
	-- The window is a fixed rectangle, so this is the only time either is asked.
	--
	-- Body rather than the height asked for, because UI.Window clamps a window
	-- to what the screen holds and the view has to be told the height it
	-- actually got. The strip comes off the top of it: a view told it has the
	-- whole body draws its last line of cards under the footer, where a click
	-- reaches the window behind this one.
	strip = tabs:Resize(window.width - M.pad * 2)
	window:Resize(window.width, HEIGHT + strip)
	view.frame:SetPoint("TOPLEFT", M.pad, -strip - M.pad)
	view:Resize(window.width - M.pad * 2, window:Body() - strip - M.pad * 2)

	tally = UI.Label(window.footer, M.font, C.text, "LEFT", UI.FLAT)
	tally:SetPoint("LEFT")
	UI.Wrap(tally, false)

	purse = UI.Label(window.footer, M.font, C.dim, "RIGHT", UI.FLAT)
	purse:SetPoint("RIGHT")
	UI.Wrap(purse, false)

	-- Hooked rather than set, because UI/Window.lua has its own handler here
	-- that closes an open dropdown, and replacing it would leave one hanging
	-- over the game every time this window went down.
	window.frame:HookScript("OnHide", function()
		-- The number picker goes with it. It is opened on a card on this rack
		-- and it spends at the vendor this window is a conversation with, so a
		-- picker left on the screen after the window went down is a buy button
		-- for a shop you have walked away from.
		UI.Take(false)
		Window.Leave()
	end)

	-- The two numbers along the bottom, recorded on the window the way the bag
	-- window records its own. Nothing in the addon reads them; the harness reads
	-- the strings the footer actually drew. The strip goes on beside them so the
	-- harness can press a tab rather than call the thing a press would call.
	window.tally, window.purse, window.tabs = tally, purse, tabs

	tabs:Select(RACK)

	return window
end

--------------------------------------------------------------------------

-- The whole of what a merchant update does. False on a window nobody has
-- opened, which is what keeps this part free for a player who leaves it
-- switched off.
function Window.Refresh()
	if not window or not window:IsShown() then
		return false
	end
	-- Both racks are read on every pass and only the one on top is drawn. The
	-- read is a walk of at most sixty entries with no allocation in it, and what
	-- it buys is that the tally under a tab is right the moment you press it
	-- rather than one refresh later.
	local rack = ns.Stock.Read()
	local sold = ns.Buyback.Read()

	local source = page == BOUGHT and ns.Buyback or ns.Stock
	local state = page == BOUGHT and sold or rack
	local content = ns.MerchantGrid.Paint(state, Rack(), source)
	view:Update(content)

	window:SetTitle(ns.Stock.Vendor() or "Merchant")
	if page == BOUGHT then
		tally:SetText(sold.count > 0
			and ("%d to buy back"):format(sold.count)
			or "nothing sold yet")
	else
		tally:SetText(("%d for sale"):format(rack.count))
	end
	purse:SetText(ns.Coined(GetMoney()))
	return true
end

function Window.Show()
	if not ns.db.merchant then
		return false
	end
	if not window then
		Build()
	end
	-- Every vendor starts on his rack. Buyback is where the last one went wrong,
	-- and a window that opens on the tab you left it on would show the next
	-- vendor's empty one instead of what he sells.
	if tabs then
		page = RACK
		tabs:Select(RACK)
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

-- The window went down by any route: the cross, escape, or the session ending
-- under it. The first two mean you are done with this vendor and the client has
-- to be told; the third is the client telling us, and calling back into it
-- there would be answering a message with itself.
function Window.Leave()
	if not session then
		return false
	end
	session = false
	return ns.CloseMerchant()
end

function Window.Shown()
	return (window and window:IsShown()) and true or false
end

function Window.Frame()
	return window
end

function Window.Open()
	return session and true or false
end

function Window.Describe()
	if not ns.db.merchant then
		return "off"
	end
	if not window then
		return "not built yet"
	end
	if not session then
		return "shut, no merchant is open"
	end
	if page == BOUGHT then
		return ("open on buyback, %s"):format(ns.Buyback.Describe())
	end
	return ("open, %s"):format(ns.Stock.Describe())
end

--------------------------------------------------------------------------
-- What wakes it
--
-- The two edges of a merchant session, and the three things that change what a
-- row says while one is open. MERCHANT_UPDATE is the vendor's own stock moving,
-- which is what a limited supply counting down looks like. PLAYER_MONEY and
-- BAG_UPDATE are the two halves of what you can afford: the purse for an
-- ordinary price and what you are carrying for a rack priced in tokens.
-- GET_ITEM_INFO_RECEIVED is the one that is not obvious, and it is the same one
-- the bag window listens for: an item the client had not cached is graded nil,
-- so it sits under the wrong heading until the answer arrives.
--
-- Those last three are also what a sale looks like from here. Selling something
-- moves the purse, empties a bag slot and puts a row on the buyback rack, and
-- the client says so twice; there is no event of its own for the second rack.
--------------------------------------------------------------------------

local function OnEvent(_, event)
	if event == "MERCHANT_SHOW" then
		session = true
		Window.Show()
		return
	end
	if event == "MERCHANT_CLOSED" then
		session = false
		Window.Hide()
		return
	end
	Window.Refresh()
end

local events

-- On while the merchant window is a thing the addon draws and off when it is
-- not. A switched-off feature listening to the game is a switched-off feature.
function Window.Apply()
	if not events then
		events = CreateFrame("Frame")
		events:SetScript("OnEvent", OnEvent)
		-- MERCHANT_CLOSED stays registered whatever the setting says, because
		-- turning the setting off with a vendor open still has to shut this.
		events:RegisterEvent("MERCHANT_CLOSED")
	end
	if ns.db.merchant then
		events:RegisterEvent("MERCHANT_SHOW")
		events:RegisterEvent("MERCHANT_UPDATE")
		events:RegisterEvent("PLAYER_MONEY")
		events:RegisterEvent("BAG_UPDATE")
		events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		return true
	end
	events:UnregisterEvent("MERCHANT_SHOW")
	events:UnregisterEvent("MERCHANT_UPDATE")
	events:UnregisterEvent("PLAYER_MONEY")
	events:UnregisterEvent("BAG_UPDATE")
	events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	Window.Hide()
	return false
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
	Window.Apply()
end)
