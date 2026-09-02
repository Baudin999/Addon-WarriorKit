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
-- **It is the bag window's shape, except for the one thing it must not copy.**
-- The two are open at the same time and they are the same act: what you have,
-- and what he has. The piles are the same piles under the same headings, the
-- square is the same square, the grid is the same number of columns wide, and
-- your purse is in the same corner of the footer. What is not the same is the
-- height.
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
-- The rectangle is a great deal more rack than it used to be, and that is the
-- grid rather than a bigger window. Sixty things were sixty lines and are now
-- eight, so the size below holds a quartermaster's whole stock where it used to
-- hold a fifth of it. The scroll view stays for the case that overflows anyway,
-- and it is the case nobody meets.
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
-- squares out of Grid.lua and the tab says which one is under it.
--
-- **The title is the vendor's name.** It is the one thing about a merchant
-- window worth a title bar: you talk to four of them in a row in a capital and
-- the rack alone does not always say which. A client that will not answer gets
-- the plain word.
--------------------------------------------------------------------------

-- How wide the window is: the bag window's column count, in the bag window's
-- squares.
--
-- Shared rather than a setting of its own, and it is the setting doing two jobs
-- rather than one setting missing. The two windows are open beside each other
-- for the whole of a vendor session and they are drawing the same squares; two
-- column counts would let a player set them to different widths, which is a
-- pair of windows that no longer read as one thing. Widening the bags widens
-- the rack, the next time it draws.
local function Width()
	return M.pad * 2 + UI.SlotSpan(ns.db.bagColumns)
end

-- How tall the rack is, and it does not move.
--
-- Ten lines of squares and four pile headings, which holds a quartermaster's
-- sixty items in one page at the default width and every ordinary vendor twice
-- over. Written as the pieces rather than as one number so that a square or a
-- heading changing size moves it, which is what stopped it being a number
-- somebody has to remember to revisit.
--
-- It is a size rather than a count of what this vendor has, so the window is
-- the same shape whatever you walk up to: a window that is a different height
-- at every vendor is a window whose close cross is somewhere new every time.
--
-- It is how tall the rack is and not how tall the window is. The tab strip is
-- added on top of it once the strip has said how tall it came out, so putting
-- the second rack in cost a row of tabs rather than a row of stock.
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

-- The window at the width the columns now ask for, and everything under the
-- title bar told about it.
--
-- Asked on every draw rather than once at build, because the width belongs to
-- the bag window's column setting and that can move while this window is shut.
-- Acted on only when the number changed: re-anchoring a view that has not moved
-- is the one thing this can do wrong, and a merchant update arrives in bursts.
--
-- Body rather than the height asked for, because UI.Window clamps a window to
-- what the screen holds and the view has to be told the height it actually got.
-- The strip comes off the top of it: a view told it has the whole body draws its
-- last line of squares under the footer, where a click reaches the window behind
-- this one.
local function Fit()
	local width = Width()
	if width == window.width then
		return width
	end
	local lines = tabs:Resize(width - M.pad * 2)
	window:Resize(width, HEIGHT + lines)
	-- The strip is one line of tabs at every width the columns can ask for, but
	-- it is the strip that decides that and not this file. A narrow window that
	-- wrapped it would draw the first line of squares over the second row of
	-- tabs, so the view is hung again whenever the answer moves.
	if lines ~= strip then
		strip = lines
		view.frame:ClearAllPoints()
		view.frame:SetPoint("TOPLEFT", M.pad, -strip - M.pad)
	end
	view:Resize(width - M.pad * 2, window:Body() - strip - M.pad * 2)
	return width
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
	-- to hang until the strip has one, so the first fit is made to happen rather
	-- than waited for: the window is built at the width Fit would ask for, so
	-- Fit's own guard would take it as nothing to do.
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
	Fit()
	local content = ns.MerchantGrid.Paint(state, ns.db.bagColumns, source)
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
