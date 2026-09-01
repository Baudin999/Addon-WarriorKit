-- The merchant window
--
-- Three claims, and the rest of the file is in service of them.
--
-- The rack is sorted by the same rules the bag window sorts your bags by, which
-- is the whole reason Core/Piles.lua left Bags/Bags.lua. So what is asserted is
-- that a vendor's stock lands in the same piles in the same order, with the
-- same tie broken the same way.
--
-- A row says what the scan put on it and a press on it buys that entry. Every
-- other window in this addon can be wrong about a picture; this one spends
-- money, so the thing checked is that the entry under the words is the entry
-- the purchase was aimed at.
--
-- And the client's own merchant window is moved rather than hidden. That is the
-- one decision in this part that cannot be recovered from: hiding that frame
-- ends the conversation with the vendor, and everything the addon then draws is
-- an empty rack. What proves it is the guard Comfort/Vendor.lua puts in front
-- of every sale, which reads IsShown on that frame and has to go on answering
-- true with the frame parked off the side of the screen.

local H = ...
local ns, check = H.ns, H.check
local ITEMS, state, merchant = H.ITEMS, H.state, H.merchant
local CARRIED = H.CARRIED

local UI = ns.UI
local C = UI.Color
local Stock, Rows = ns.Stock, ns.MerchantRows
local Window, Blizz = ns.MerchantWindow, ns.MerchantBlizzard

----------------------------------------------------------------------
-- The scene
--
-- A purse that affords four of the five things on the rack. The flask is
-- ninety gold against fifty in the purse, which is the only way to have a row
-- that is drawn, priced, in stock and still not yours.
----------------------------------------------------------------------

local PURSE = 50000
local held = state.purse
state.purse = PURSE

check(not Window.Shown(), "the merchant window is up before a vendor was spoken to")

merchant.open("Innkeeper Allison")

check(Window.Shown(), "a merchant opened and the window did not")
check(Window.Open(), "the window is up and does not think a session is open")

local read = Stock.Read()

local function pile(key)
	for index = 1, read.shown do
		if read.groups[index].key == key then
			return read.groups[index]
		end
	end
	return nil
end

----------------------------------------------------------------------
-- The piles
--
-- Five things over four piles, because the water and the flask are both
-- consumables and everything else on the rack is alone in its class. The two
-- consumables are what says the tie is broken the bag window's way: the flask
-- is blue and the water is white, and grade comes before name.
----------------------------------------------------------------------

check(read.count == 5,
	("the scan found %d things and the vendor has 5"):format(read.count))
check(read.shown == 4,
	("the scan drew %d piles and five things over four classes make 4"):format(read.shown))

local drink = pile("consumable")
check(drink ~= nil and #drink.entries == 2,
	"the water and the flask did not land in one pile of two")
check(drink and drink.entries[1].name == "Flask of Petrification",
	"the blue is not at the top of its pile, so the grade is not sorting first")
check(pile("armor") ~= nil and pile("projectile") ~= nil and pile("misc") ~= nil,
	"the helm, the arrows and the rod did not each get a pile of their own")
check(pile("empty") == nil,
	"a vendor's rack drew the bag window's empty pile, which it has no such thing as")

-- The same answer the bag window would give about the same link, asked of the
-- shared file rather than of either window. Both reading one table is the claim;
-- two tables that happen to agree today is what this is written against.
check(ns.Piles.Of(_G.GetMerchantItemLink(1)) == "consumable",
	"the vendor's water is filed under a different pile than the bag window would file it")

----------------------------------------------------------------------
-- The rows
--
-- Every branch a row can take is on this rack at once, which is why there are
-- five of them and not two: an ordinary price, a stack the vendor sells two
-- hundred at a time, a limited supply, something this class cannot use, and one
-- priced in tokens you have not got.
----------------------------------------------------------------------

local rows = Rows.Rows()

local function shown()
	local count = 0
	for index = 1, #rows do
		if rows[index]:IsShown() then
			count = count + 1
		end
	end
	return count
end

local function row(name)
	for index = 1, #rows do
		if rows[index]:IsShown() and rows[index].name == name then
			return rows[index], index
		end
	end
	return nil
end

local function inked(text, color)
	local r, g, b = text:GetTextColor()
	return r == color[1] and g == color[2] and b == color[3]
end

check(shown() == 5, ("%d rows are drawn and the rack has 5"):format(shown()))

local flask, flaskAt = row("Flask of Petrification")
local water = row("Refreshing Spring Water")
local arrow = row("Sharp Arrow")
local rod = row("Runed Copper Rod")
local helm = row("Gladiator's Plate Helm")

check(flaskAt == 1, ("the first row drawn is %s and the blue consumable heads the first pile")
	:format(flaskAt == 1 and "right" or "wrong"))

check(water and water.price:GetText() == ns.Coined(25),
	"the water's row does not carry the price the vendor is asking")
check(arrow and arrow.square.tally:GetText() == "200",
	"the arrows do not say on the square that one press buys two hundred")
check(water and water.square.tally:GetText() == "5",
	"a stack of five does not say so on the square")
check(rod and rod.square.tally:GetText() == "",
	"something sold one at a time drew a count on its square")

-- The one number a limited supply is for, and the one it must not draw. -1 is
-- the client saying it has an endless supply, and a row that read it as a count
-- would say the vendor has minus one flask.
check(flask and flask.note:GetText() == "2 left",
	"the flask does not say how many the vendor has left")
check(water and water.note:GetText() == "",
	"an endless supply drew a count of how many are left")

check(rod and inked(rod.label, C.quiet),
	"something this class cannot use is drawn in the same ink as something it can")
check(water and not inked(water.label, C.quiet),
	"something usable is drawn as though it were not")

----------------------------------------------------------------------
-- What you cannot buy
--
-- Two of the five, for two different reasons, and both are dimmed rather than
-- taken off the rack: what the vendor has is a fact and what you can pay for is
-- a fact about this minute. The token row is the one you cannot work out by
-- looking at your purse, so its number carries the colour instead.
----------------------------------------------------------------------

check(flask and flask:GetAlpha() < 1,
	"a flask at ninety gold against a fifty gold purse is drawn as though you could buy it")
check(water and water:GetAlpha() == 1,
	"something you can afford is dimmed")

check(helm and helm.chips[1]:IsShown() and helm.chips[1].count:GetText() == "40",
	"the token price is not drawn on the row that is paid in tokens")
check(helm and inked(helm.chips[1].count, C.loss),
	"a token price you cannot meet is drawn in the same ink as one you can")
check(helm and helm:GetAlpha() < 1,
	"a row you have not got the tokens for is drawn as though you could buy it")
check(water and not water.chips[1]:IsShown(),
	"a row paid for in money drew a token chip")

----------------------------------------------------------------------
-- A press
--
-- Through the client's own click rather than through the row's handler, and
-- that is the whole point of doing it this way. A frame that hands the right
-- and middle buttons to the camera has had which buttons it answers written,
-- and the left one has to be asked for again afterwards or the row draws
-- perfectly, hovers perfectly and does nothing at all when you press it. The
-- harness refuses a click a button is not registered for, so a row that lost
-- its registration fails here rather than in Ironforge.
--
-- What is checked is the entry, not the row: the purse moves by the price of
-- the thing whose name was on the line that was pressed.
----------------------------------------------------------------------

local passing = 0
for index = 1, #rows do
	local passed = rows[index]:GetPassThroughButtons()
	local clicks = rows[index]:GetRegisteredClicks()
	if passed and passed["RightButton"] and clicks and clicks["LeftButtonUp"] then
		passing = passing + 1
	end
end
check(passing == #rows,
	("%d of %d rows both hand the right button to the camera and still answer the left")
		:format(passing, #rows))

local before = state.purse
check(water:Click("LeftButton") == true,
	"a left click on a row was refused, so the row is a button that does nothing")

check(state.purse == before - 25,
	("a press on the water moved the purse by %d and the water costs 25")
		:format(before - state.purse))
check(merchant.bought[water.entry.index] == 1,
	"the press bought something other than the thing whose name was on the row")

-- The row under the pointer is the one that pays, whatever the layout did next.
-- The rack is re-read on the client's own update, so this also says the window
-- answered that update rather than drawing what it had.
check(Window.Shown() and shown() == 5,
	"buying something took a row off the rack")

----------------------------------------------------------------------
-- Spending tokens
--
-- The one purchase this window asks about first. Gold is not asked about,
-- because an item sold to the wrong vendor is in his buyback tab for an hour;
-- forty badges are gone from the game. So the press puts a question up and buys
-- nothing until it is answered, which is the shape UI/Ask.lua exists for.
----------------------------------------------------------------------

do
	local was = merchant.bought[helm.entry.index] or 0
	helm:Click("LeftButton")

	check(UI.Asking() ~= nil,
		"a press on a row priced in tokens bought them without asking")
	check((merchant.bought[helm.entry.index] or 0) == was,
		"the question went up and the tokens were spent anyway")

	UI.Answer(false)
	check(UI.Asking() == nil, "saying no left the question on the screen")
	check((merchant.bought[helm.entry.index] or 0) == was,
		"saying no to the question spent the tokens")

	helm:Click("LeftButton")
	UI.Answer(true)
	check((merchant.bought[helm.entry.index] or 0) == was + 1,
		"saying yes to the question did not buy the thing it was asking about")

	check(water:Click("LeftButton") and UI.Asking() == nil,
		"a row priced in money put a question up, which is a click asked about twice")
	UI.Answer(false)
end

----------------------------------------------------------------------
-- The vendor running out
--
-- The one refusal this window makes on its own. Everything else is left to the
-- server, because a window that greys a row out on its own arithmetic is a
-- window that can be wrong in the direction that costs you the sale.
----------------------------------------------------------------------

merchant.rack[3].available = 0
Window.Refresh()

local gone = row("Flask of Petrification")
check(gone ~= nil and not Stock.InStock(gone.entry),
	"the vendor has none left and the window still thinks he has")
check(select(1, Stock.Buy(gone.entry)) == false,
	"the window let a press through on something the vendor has none of")
check(gone and gone.note:GetText() == "0 left",
	"a rack that has run out does not say so")

merchant.rack[3].available = 2
Window.Refresh()

----------------------------------------------------------------------
-- The buyback rack
--
-- The half of the client's merchant window that went off the side of the screen
-- with the rest of it. Selling to the wrong vendor is recoverable for an hour
-- and that is the argument every sale in this addon leans on, so the window
-- that replaced the client's has to carry the tab that makes it true.
--
-- Three things are asserted. The order is the order you sold in, newest at the
-- top, because the row you came here for is the last one you sold. The slots
-- are a range and not a list, so a hole left by a row already taken back is
-- skipped rather than drawn blank. And a press on a buyback row buys that row
-- back rather than buying the rack row that was drawn on the same button a
-- moment earlier, which is the one way a shared pool of rows could go wrong.
----------------------------------------------------------------------

local tabs = Window.Frame().tabs
local foot = Window.Frame().tally

check(tabs ~= nil and #tabs.buttons == 2,
	"the merchant window has no tab strip, so buyback is nowhere a click can reach")

local purse = state.purse
check(merchant.sell("Runed Copper Rod", 1000) == 1,
	"selling something to the vendor did not put it on his buyback rack")
merchant.sell("Refreshing Spring Water", 5, 5)
check(state.purse == purse + 1005,
	"the two sales did not pay what they were sold for")

check(shown() == 5,
	"selling something changed what the rack tab is drawing")

check(tabs.buttons[2]:Click("LeftButton") == true,
	"the buyback tab refused a click")

check(shown() == 2,
	("the buyback tab drew %d rows and two things were sold"):format(shown()))
check(rows[1].name == "Refreshing Spring Water",
	"the buyback rack is not newest first, so the row you just sold is not the top one")
check(rows[2].name == "Runed Copper Rod",
	"the older of the two sales is not under the newer one")
check(not Rows.Headers()[1]:IsShown(),
	"the buyback rack drew a pile heading, which the tab above it already says")
check(rows[2].price:GetText() == ns.Coined(1000),
	"a buyback row does not carry the price it costs to take back")
check(rows[2].note:GetText() == "",
	"a buyback row drew a count of how many the vendor has left")
check(foot:GetText() == "2 to buy back",
	("the footer says %q with two things on the rack"):format(foot:GetText()))

-- The press, and the fact it proves is which of the two racks the row belonged
-- to. Taking the rod back costs the thousand he paid for it; the rack row drawn
-- on this same button a moment ago was the water at twenty five.
purse = state.purse
check(rows[2]:Click("LeftButton") == true, "a click on a buyback row was refused")
check(state.purse == purse - 1000,
	("taking the rod back moved the purse by %d and he paid 1000 for it")
		:format(purse - state.purse))

check(shown() == 1 and rows[1].name == "Refreshing Spring Water",
	"a slot taken back is still on the rack, or the hole it left was drawn as a row")
check(_G.GetNumBuybackItems() == 2,
	"the client stopped counting the empty slot, which is not what it does")

check(Window.Describe():find("buy back") ~= nil,
	"the window says nothing about buyback while that is what it is showing")

tabs.buttons[1]:Click("LeftButton")
check(shown() == 5 and foot:GetText() == "5 for sale",
	"going back to the rack tab did not put the vendor's stock back on the rows")

----------------------------------------------------------------------
-- Blizzard's window
--
-- Parked, and the two things that proves. It is off the side of the screen at
-- no opacity, so nothing of it is drawn and nothing of it can be clicked. And
-- it is still shown, which is the half that matters: the sale sweep asks that
-- frame whether a merchant is open before every pass, because the call that
-- sells a bag slot eats what is in it when one is not.
----------------------------------------------------------------------

Blizz.Apply()

check(Blizz.Parked(), "the client's merchant window was left on the screen")
check(_G.MerchantFrame:IsShown(),
	"parking the client's window stopped it being shown, which is the sale sweep's guard")
check(_G.MerchantFrame:GetAlpha() == 0,
	"the client's window is parked and still drawing")
check(_G.MerchantFrame:GetLeft() >= _G.UIParent:GetRight(),
	"the client's window is parked somewhere a cursor can still reach it")

----------------------------------------------------------------------
-- Walking away
--
-- The client's cross is off the screen with the rest of that window, so this
-- one has to end the session. Every way out goes through the frame's own
-- OnHide, which is where escape and the close box both land, so closing the
-- window is what is pressed rather than the handler.
----------------------------------------------------------------------

Window.Hide()

check(not merchant.shown(),
	"closing the window left the conversation with the vendor open")
check(not Window.Open(), "the session ended and the window still thinks it is up")

Blizz.Apply()
check(not Blizz.Parked(), "the vendor is gone and the client's window is still parked")
check(_G.MerchantFrame:GetAlpha() == 1,
	"the client's window was left at no opacity after the session ended")

----------------------------------------------------------------------
-- The switch
----------------------------------------------------------------------

SlashCmdList.WARRIORKIT("merchant off")
merchant.open()
check(not Window.Shown(), "the window came up with the feature switched off")
check(_G.GetMerchantNumItems() == 5,
	"the feature is off and the client no longer has a vendor either")
merchant.close()

SlashCmdList.WARRIORKIT("merchant on")
merchant.open()
check(Window.Shown(), "turning the window back on did not put it back on the vendor")
merchant.close()

state.purse = held
CARRIED[3] = nil

print(("vendor %d things over %d piles from %s; %s")
	:format(read.count, read.shown, Stock.Vendor() or "nobody", Rows.Describe()))
print(("vendor %s; the client's %s"):format(Window.Describe(), Blizz.Describe()))
