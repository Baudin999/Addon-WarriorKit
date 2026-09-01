local ADDON, ns = ...

local UI = ns.UI
local C, M = UI.Color, UI.Metric

local Window = {}
ns.MerchantWindow = Window

--------------------------------------------------------------------------
-- The merchant window
--
-- One window, one scroll view, and the two numbers along the bottom. Stock.lua
-- answers what the vendor has and Rows.lua draws it; this file owns when to ask
-- and how big the answer is allowed to be.
--
-- **It is the bag window's shape, except for the one thing it must not copy.**
-- The two are open at the same time and they are the same act: what you have,
-- and what he has. The piles are the same piles under the same headings, the
-- square is the same square, and your purse is in the same corner of the
-- footer. What is not the same is the height.
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
-- **Closing the window walks away from the vendor.** The client's own merchant
-- frame is parked off the side of the screen while this one is up, so its cross
-- is nowhere a cursor can reach and the session would otherwise stay open until
-- you ran out of range. Every way out of this window goes through the frame's
-- own OnHide, which is where escape and the close box both land, so there is
-- one place that ends the session rather than one per exit.
--
-- **The title is the vendor's name.** It is the one thing about a merchant
-- window worth a title bar: you talk to four of them in a row in a capital and
-- the rack alone does not always say which. A client that will not answer gets
-- the plain word.
--------------------------------------------------------------------------

-- How wide the window is. Enough for a square, a name most items fit inside,
-- and a price with gold in it. Fixed rather than a setting, because unlike the
-- bag window's columns there is nothing here a player would want to trade width
-- for: a row is a row.
local WIDTH = 400

-- How tall it is, and it does not move.
--
-- Thirteen rows of rack and the two headings over them, which is more than most
-- vendors have and a comfortable page of a quartermaster who has sixty. The
-- number is a size rather than a count so that the window is the same shape
-- whatever you walk up to: a window that is a different height at every vendor
-- is a window whose close cross is somewhere new every time.
local HEIGHT = 450

local window, view, tally, purse
local session = false

local function Build()
	window = UI.Window({
		name = "WarriorKitMerchant",
		title = "Merchant",
		width = WIDTH,
		height = HEIGHT,
	})
	ns.Remember(window)

	view = UI.ScrollView(window.content, { overlay = true })
	view.frame:SetPoint("TOPLEFT", M.pad, -M.pad)
	ns.MerchantRows.Attach(view.canvas)
	-- Once, at the size the window is and stays. Body rather than the height
	-- asked for, because UI.Window clamps a window to what the screen holds and
	-- the view has to be told the height it actually got.
	view:Resize(WIDTH - M.pad * 2, window:Body() - M.pad * 2)

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
	-- the strings the footer actually drew.
	window.tally, window.purse = tally, purse

	UI.OnRescale(function()
		if window then
			UI.Rezoom(window.frame, UI.WindowZoom())
			window.zoom = UI.WindowZoom()
		end
	end)
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
	local state = ns.Stock.Read()
	local content = ns.MerchantRows.Paint(state, WIDTH - M.pad * 2)
	view:Update(content)
	window:SetTitle(ns.Stock.Vendor() or "Merchant")
	tally:SetText(("%d for sale"):format(state.count))
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
