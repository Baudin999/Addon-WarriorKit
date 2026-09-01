local ADDON, ns = ...

local UI = ns.UI
local M = UI.Metric

local Merchant = {}
ns.BagsMerchant = Merchant

--------------------------------------------------------------------------
-- The row that is only there at a merchant
--
-- Two buttons across the top of the bag window while a merchant session is
-- open, and nothing at all the rest of the time. Selling your greys and paying
-- for your mending are the two things a vendor is for, and both of them were
-- already in this addon with no button anywhere near the window you are looking
-- at while you do them.
--
-- **Neither button does the work.** Comfort/Vendor.lua owns the sale and
-- Comfort/Repair.lua owns the repair, both of them with their own ticker, their
-- own refusals and their own harness section. This file is a press and a
-- number. A second sweep written here to save naming those two would be a
-- second set of rules about what a vendor takes, and the first time they
-- disagreed the window would be the one telling the truth.
--
-- **The row is drawn only when there is something on it.** A merchant who does
-- not mend and a bag with no greys in it get no row, which is the same rule the
-- piles below follow: a pile with nothing in it is not drawn. With the
-- automatic sale switched on the row is usually a flash of one button and then
-- nothing, because the sweep has already emptied the pile it was counting.
--
-- **The session is this file's own flag and not the repair's.** Both are set
-- off the same two events and there is no order between two frames on one
-- event, so a row that read the other file's flag would be a row that is right
-- or a frame late depending on which handler the client ran first. What is
-- taken from Comfort/Repair.lua is the quote, which asks the client rather than
-- a flag and is the same answer whoever asks it.
--------------------------------------------------------------------------

-- What the row costs the window when it is up: one control row and the air
-- under it before the first pile's heading.
local ROW = M.row

-- The air either side of a button's own words. The buttons carry numbers that
-- change width as you spend and sell, so each is sized to what it says rather
-- than given a width that has to be wide enough for the worst case and is too
-- wide for every other one.
local SIDE = M.gutter

local bar, sell, repair
local events
local session = false
local greys, worth, bill = 0, 0, nil

--------------------------------------------------------------------------

-- Whether a merchant is open and this window is the one drawing your bags.
--
-- The session rather than MerchantFrame being shown, for the reason
-- Comfort/Repair.lua spells out at its own flag: MERCHANT_SHOW is the server
-- opening a merchant, and the client's window may be a frame behind that or
-- may not be built yet at all.
function Merchant.Open()
	return (session and ns.db.bags) and true or false
end

-- What the sale would take and what it would pay, off the scan the window has
-- just done rather than off a walk of its own.
--
-- The rule is quality nought with a price on it, which is the rule
-- Comfort/Vendor.lua sells by. The pile has already answered the first half:
-- everything the client grades grey is in it, whatever class it is. The second
-- half is the grey a vendor will not take, a Broken Twig, which is filed as
-- junk like the rest and is the one thing in the pile the sweep leaves behind.
local function Trash(state)
	local count, paid = 0, 0
	for index = 1, state.shown do
		local group = state.groups[index]
		if group.key == ns.Bags.JUNK then
			for held = 1, #group.entries do
				local entry = group.entries[held]
				if ns.Bags.Sellable(entry) then
					count = count + 1
					paid = paid + entry.price * (entry.count or 1)
				end
			end
		end
	end
	return count, paid
end

--------------------------------------------------------------------------
-- The two presses
--------------------------------------------------------------------------

local function Sell()
	local going, why = ns.Vendor.Run()
	if not going then
		ns.Print(why .. ".")
	end
end

local function Repair()
	local cost, why = ns.Repair.Run()
	if not cost then
		ns.Print(why .. ".")
	elseif cost > 0 then
		ns.Print(("repaired for %s, %s."):format(GetCoinText(cost),
			why == "guild" and "on the guild" or "out of your own purse"))
	end
end

--------------------------------------------------------------------------
-- Building it
--------------------------------------------------------------------------

-- One button, saying what it says, at the width that says it. Hidden where
-- there is no text, because a button with nothing written on it is a button
-- with nothing to do.
local function Say(button, text)
	if not text then
		button:Hide()
		return false
	end
	button.text:SetText(text)
	button:SetWidth(UI.Round(button, (button.text:GetStringWidth() or 0) + SIDE * 2))
	button:Show()
	return true
end

-- The row, made on the first paint that wants it. `where` is the window's
-- content frame, which is what the grid's scroll view is anchored inside as
-- well, and the row is placed against the same two edges.
function Merchant.Attach(where)
	if bar then
		return bar
	end
	bar = CreateFrame("Frame", nil, where)
	bar:SetPoint("TOPLEFT", M.pad, -M.pad)
	bar:SetPoint("TOPRIGHT", -M.pad, -M.pad)
	bar:SetHeight(ROW)
	bar:Hide()

	sell = UI.Button(bar, { label = "", height = ROW, onClick = Sell })
	sell:SetPoint("LEFT")

	repair = UI.Button(bar, { label = "", height = ROW, onClick = Repair })
	repair:SetPoint("LEFT", sell, "RIGHT", M.rowGap, 0)
	return bar
end

-- How much of the window's height the row is taking right now. Nought when it
-- is not up, which is what makes a window with no merchant in front of it
-- exactly the window it was before this file existed.
function Merchant.Height()
	if not bar or not bar:IsShown() then
		return 0
	end
	return ROW + M.rowGap
end

-- The row, for the scan the window has just done. Called before the grid is
-- laid out, because how tall the window comes to depends on whether this is up.
function Merchant.Paint(state)
	if not bar then
		return false
	end

	greys, worth, bill = 0, 0, nil
	if not Merchant.Open() then
		bar:Hide()
		return false
	end

	greys, worth = Trash(state)
	-- The quote rather than the cost, because the cost is gated on the repair's
	-- own session flag and this file has already answered that question with
	-- its own.
	bill = ns.Repair.Quote()

	local selling = Say(sell, greys > 0
		and ("sell %d grey%s"):format(greys, greys == 1 and "" or "s") or nil)
	local mending = Say(repair, (bill and bill > 0)
		and ("repair %s"):format(ns.Coined(bill)) or nil)

	-- The second button takes the first one's place when the first is not
	-- there, so a merchant who only mends does not draw its button halfway
	-- across a row with a hole on the left of it.
	repair:ClearAllPoints()
	if selling then
		repair:SetPoint("LEFT", sell, "RIGHT", M.rowGap, 0)
	else
		repair:SetPoint("LEFT")
	end

	bar:SetShown(selling or mending)
	return selling or mending
end

--------------------------------------------------------------------------
-- What wakes it
--
-- The same two events Comfort/Vendor.lua and Comfort/Repair.lua hold, and for
-- the same reason: they are the two edges of a merchant session. The window is
-- repainted on both, because what a square looks like and whether this row is
-- on the screen both change at those two moments and nothing else in the addon
-- would ask.
--------------------------------------------------------------------------

local function OnEvent(_, event)
	session = event == "MERCHANT_SHOW"
	ns.BagsWindow.Refresh()
end

-- On while the bag window is a thing the addon draws and off when it is not.
-- A switched-off feature listening to the game is a switched-off feature.
function Merchant.Apply()
	if not events then
		events = CreateFrame("Frame")
		events:SetScript("OnEvent", OnEvent)
	end
	if ns.db.bags then
		events:RegisterEvent("MERCHANT_SHOW")
		events:RegisterEvent("MERCHANT_CLOSED")
		return true
	end
	events:UnregisterEvent("MERCHANT_SHOW")
	events:UnregisterEvent("MERCHANT_CLOSED")
	session = false
	return false
end

-- The row's two buttons, for the harness. It reads what they say and presses
-- them, which is the one claim about this file that cannot be made from the
-- outside: that the words on a button are the sale in front of you and that
-- pressing it is the sale Comfort/Vendor.lua and Comfort/Repair.lua run.
function Merchant.Buttons()
	return sell, repair
end

function Merchant.Describe()
	if not ns.db.bags then
		return "off with the window"
	end
	if not session then
		return "no merchant is open"
	end
	local sale = greys > 0
		and ("%d grey%s worth %s"):format(greys, greys == 1 and "" or "s", ns.Coin(worth))
		or "nothing to sell"
	if bill == nil then
		return sale .. ", and this merchant does not mend"
	end
	if bill <= 0 then
		return sale .. ", and nothing is damaged"
	end
	return ("%s, %s to mend"):format(sale, ns.Coin(bill))
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
	Merchant.Apply()
end)
