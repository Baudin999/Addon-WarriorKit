-- The merchant window
--
-- Three claims, and the rest of the file is in service of them.
--
-- The rack is sorted by the same rules the bag window sorts your bags by, which
-- is the whole reason Core/Piles.lua left Bags/Bags.lua. So what is asserted is
-- that a vendor's stock lands in the same piles in the same order, with the
-- same tie broken the same way.
--
-- A card shows what the scan put on it, names it, prices it, and a press on it
-- buys that entry in the vendor's own batch. Every other window in this addon
-- can be wrong about a picture; this one spends money, so what is checked is
-- that the entry the card described is the entry the purchase was aimed at, and
-- that a press buys the number the card said it would.
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
local Stock, Grid = ns.Stock, ns.MerchantGrid
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
-- Before the once-a-second pass has run. The park used to land on that pass
-- and the gap was a flash of the client's window under ours on every vendor.
check(Blizz.Parked() and _G.MerchantFrame:GetAlpha() == 0,
	"the vendor opened and the client's window was on the screen until the next pass")

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
-- The cards
--
-- A card is the bag window's square with the item's name and the vendor's price
-- beside it, which is the whole of what a rack has to say and the whole of what
-- a bare grid of pictures could not. Every branch a card can take is on this
-- rack at once, which is why there are five things on it and not two: an
-- ordinary price, a stack the vendor sells two hundred at a time, a limited
-- supply, something this class cannot use, and one priced in tokens you have
-- not got.
----------------------------------------------------------------------

local cards = Grid.Cards()

local function shown()
	local count = 0
	for index = 1, #cards do
		if cards[index]:IsShown() then
			count = count + 1
		end
	end
	return count
end

local function card(name)
	for index = 1, #cards do
		if cards[index]:IsShown() and cards[index].name == name then
			return cards[index], index
		end
	end
	return nil
end

check(shown() == 5, ("%d cards are drawn and the rack has 5"):format(shown()))

local flask, flaskAt = card("Flask of Petrification")
local water = card("Refreshing Spring Water")
local arrow = card("Sharp Arrow")
local rod = card("Runed Copper Rod")
local helm = card("Gladiator's Plate Helm")

check(flaskAt == 1, ("the first card drawn is %s and the blue consumable heads the first pile")
	:format(flaskAt == 1 and "right" or "wrong"))

check(arrow and arrow.square.tally:GetText() == "200",
	"the arrows do not say on the square that one press buys two hundred")
check(water and water.square.tally:GetText() == "5",
	"a stack of five does not say so on the square")
check(rod and rod.square.tally:GetText() == "",
	"something sold one at a time drew a count on its square")

----------------------------------------------------------------------
-- What the card says without being pointed at
--
-- The two strings a shop cannot do without. A rack of pictures alone was the
-- shape this window had for a day: it named nothing, priced nothing, and put
-- both a hover away on every entry. So the name is on the card in the item's
-- own grade, the price is on the card in coins, and what is left of a limited
-- supply is on the card beside the price.
----------------------------------------------------------------------

check(water and water.label:GetText() == "Refreshing Spring Water",
	"the card does not name what is on it")
check(water and water.price:GetText() == ns.Coined(25),
	"the card does not carry the price the vendor is asking")
check(flask and flask.note:GetText() == "2 left",
	"a limited supply does not say on the card how many are left")
check(water and water.note:GetText() == "",
	"an endless supply drew a count of how many are left")
check(helm and helm.price:GetText() == "" and helm.chips[1]:IsShown(),
	"a rack entry priced in tokens drew money, or drew no token at all")
check(helm and helm.chips[1].count:GetText() == "40",
	"the token chip does not say how many of it the helm costs")
check(water and not water.chips[1]:IsShown(),
	"something paid for in money drew a token chip")

-- The grade is on the name as well as on the rim, which is the one thing a row
-- of words can say that a row of pictures cannot.
local blue = UI.Quality[3]
check(flask and select(1, flask.label:GetTextColor()) == blue[1],
	"a blue item's name is not drawn in its own grade")
check(rod and select(1, rod.label:GetTextColor()) == C.quiet[1],
	"something this class cannot use is not drawn as though it could not")

----------------------------------------------------------------------
-- The box on a card
--
-- The whole of the offer, which is more than the card has room for: the price,
-- the tokens and how many of each you are holding, what one press buys, how
-- many the vendor has left, how many you may ask for at once, and the one line
-- about the item rather than about the sale. It is read back off the tooltip
-- the hover actually drew rather than off the table handed to it.
----------------------------------------------------------------------

-- The box a hover on this square drew, as a list of what each line said and
-- what colour the value on it was. The pointer is taken off again, because a
-- box left open is anchored to a square the next pass may put something else
-- on.
local function box(button)
	local enter, leave = button:GetScript("OnEnter"), button:GetScript("OnLeave")
	if not enter or not leave then
		return nil
	end
	enter(button)
	local lines = {}
	for index = 1, UI.Tooltip.Lines() do
		local left, right = UI.Tooltip.Text(index)
		lines[#lines + 1] = { left, right, tone = UI.Tooltip.Tone(index) }
	end
	leave(button)
	return lines
end

-- What the box said against a label, and nothing where it did not say it. Two
-- returns, because a line that is there and a line that is missing are opposite
-- facts and the colour is the second half of what the line says.
local function said(lines, label)
	for index = 1, #(lines or {}) do
		if lines[index][1] == label then
			return lines[index][2] or true, lines[index].tone
		end
	end
	return nil
end

local function inked(tone, color)
	return tone ~= nil and tone[1] == color[1] and tone[2] == color[2]
		and tone[3] == color[3]
end

check(box(water) ~= nil and box(water)[1][1] == "Refreshing Spring Water",
	"the box on a card does not name what is on it")
check(said(box(water), "Price") == ns.Coined(25),
	"the box on the water does not carry the price the vendor is asking")
check(said(box(arrow), "One press buys") == "200",
	"the box on the arrows does not say that one press buys two hundred")
check(said(box(rod), "One press buys") == nil,
	"something sold one at a time said what one press buys, which is one")

-- The one sentence in the addon that says what to press, and it is on the two
-- entries where more than one press-worth can be bought and nowhere else.
check(said(box(water), "Shift-click") == "up to 20",
	"the box on the water does not say how many of it one call can buy")
check(said(box(rod), "Shift-click") == nil,
	"something sold one at a time offered a number to pick")

-- The one number a limited supply is for, and the one it must not draw. -1 is
-- the client saying it has an endless supply, and a box that read it as a count
-- would say the vendor has minus one flask.
check(said(box(flask), "Left") == "2",
	"the box on the flask does not say how many the vendor has left")
check(said(box(water), "Left") == nil,
	"an endless supply drew a count of how many are left")

check(said(box(rod), "Your class cannot use this") ~= nil,
	"a rod no warrior can use says nothing about it")
check(said(box(water), "Your class cannot use this") == nil,
	"something usable is described as though it were not")

----------------------------------------------------------------------
-- What you cannot buy
--
-- Two of the five, for two different reasons, and both are dimmed rather than
-- taken off the rack: what the vendor has is a fact and what you can pay for is
-- a fact about this minute. The dim is what you read at a glance across the
-- whole grid; the box on the one square you are pointing at says which of the
-- two, and in the loss colour, which is the one thing about a token price you
-- cannot work out by looking at your purse.
----------------------------------------------------------------------

check(flask and flask:GetAlpha() < 1,
	"a flask at ninety gold against a fifty gold purse is drawn as though you could buy it")
check(water and water:GetAlpha() == 1,
	"something you can afford is dimmed")

check(said(box(flask), "Price") == ns.Coined(90000)
	and inked(select(2, said(box(flask), "Price")), C.loss),
	"a price the purse cannot meet is drawn in the same ink as one it can")
check(inked(select(2, said(box(water), "Price")), C.text),
	"a price you can afford is drawn as though you could not")

check(said(box(helm), "Mark of Honor Hold") == "0 of 40",
	("the box on the helm says %s of the tokens it costs")
		:format(tostring(said(box(helm), "Mark of Honor Hold"))))
check(inked(select(2, said(box(helm), "Mark of Honor Hold")), C.loss),
	"a token price you cannot meet is drawn in the same ink as one you can")
check(helm and helm:GetAlpha() < 1,
	"a square you have not got the tokens for is drawn as though you could buy it")
check(said(box(water), "Mark of Honor Hold") == nil,
	"the box on something paid for in money drew a token line")

check(not H.tipSettle(), "the box stayed up after the pointer left the card")

----------------------------------------------------------------------
-- A press
--
-- Through the client's own click rather than through the card's handler, and
-- that is the whole point of doing it this way. A frame that hands the right
-- and middle buttons to the camera has had which buttons it answers written,
-- and the left one has to be asked for again afterwards or the card draws
-- perfectly, hovers perfectly and does nothing at all when you press it. The
-- harness refuses a click a button is not registered for, so a card that lost
-- its registration fails here rather than in Ironforge.
--
-- What is checked is the entry, not the card: the purse moves by the price of
-- the thing the box on the pressed card described.
--
-- And it buys the batch. The client counts a purchase in items rather than in
-- the vendor's own stacks, so asking it for one at a vendor selling water five
-- at a time bought a single water and charged the price of five. The card says
-- 5 in its corner and this is the assertion that the press agrees with it.
----------------------------------------------------------------------

local passing = 0
for index = 1, #cards do
	local passed = cards[index]:GetPassThroughButtons()
	local clicks = cards[index]:GetRegisteredClicks()
	if passed and passed["RightButton"] and clicks and clicks["LeftButtonUp"] then
		passing = passing + 1
	end
end
check(passing == #cards,
	("%d of %d cards both hand the right button to the camera and still answer the left")
		:format(passing, #cards))

local before = state.purse
check(water:Click("LeftButton") == true,
	"a left click on a card was refused, so the card is a button that does nothing")

check(state.purse == before - 25,
	("a press on the water moved the purse by %d and the water costs 25")
		:format(before - state.purse))
check(merchant.bought[water.entry.index] == 5,
	("the press bought %d water and the vendor sells them five at a time")
		:format(merchant.bought[water.entry.index] or 0))

-- The card under the pointer is the one that pays, whatever the layout did
-- next. The rack is re-read on the client's own update, so this also says the
-- window answered that update rather than drawing what it had.
check(Window.Shown() and shown() == 5,
	"buying something took a card off the rack")

----------------------------------------------------------------------
-- Picking a number
--
-- The other half of the same bug. A press buys one batch, and until this there
-- was no way at all to buy four: the client's own stack split is on the frame
-- parked off the side of the screen, so a player who wanted twenty water had to
-- press four times and count.
--
-- The range is the item's stack over the vendor's batch, capped by what he has
-- left, which is the arithmetic the picker exists to do for you. Four for the
-- water, one for the rod, and two for the flask because he only has two.
----------------------------------------------------------------------

check(Stock.Batches(water.entry) == 4,
	("the water offers %d presses' worth and twenty over five is 4")
		:format(Stock.Batches(water.entry)))
check(Stock.Batches(rod.entry) == 1,
	"something that does not stack offers a number to pick")
check(Stock.Batches(flask.entry) == 2,
	("the flask offers %d and the vendor has 2, so the supply is not capping it")
		:format(Stock.Batches(flask.entry)))

check(UI.Amounting() == nil, "the picker is on the screen before anything asked for it")

_G.WarriorKitShift(true)
water:Click("LeftButton")
check(UI.Amounting() == 1, "a shift-click on a stack did not put the picker up on one")
check(UI.Choose(99) == 4,
	"the picker let you ask for more than one call can carry")
check(UI.Choose(0) == 1, "the picker let you ask for none")
check(UI.Choose(4) == 4, "the picker refused a number inside its own range")

before = state.purse
local was = merchant.bought[water.entry.index] or 0
check(UI.Take(true) == true, "the picker refused the button that buys")
check(UI.Amounting() == nil, "the picker stayed up after it was answered")
check(state.purse == before - 100,
	("four stacks of water moved the purse by %d and four at 25 is 100")
		:format(before - state.purse))
check((merchant.bought[water.entry.index] or 0) == was + 20,
	("the picker bought %d water and four stacks of five is 20")
		:format((merchant.bought[water.entry.index] or 0) - was))

-- Cancelling spends nothing, which is the one thing a window over a vendor's
-- rack has to get right.
water = card("Refreshing Spring Water")
water:Click("LeftButton")
before = state.purse
check(UI.Take(false) == true, "the picker refused the button that does not buy")
check(state.purse == before, "cancelling the picker spent money")

-- Nothing to pick is a press, not an empty window. A rod is one to a batch and
-- one to a stack, so shift on it is the same as no shift at all.
before = state.purse
rod = card("Runed Copper Rod")
rod:Click("LeftButton")
check(UI.Amounting() == nil,
	"a shift-click on something sold one at a time put a picker up with one choice on it")
check(state.purse == before - 4000, "the shift-click on the rod did not buy the rod")
_G.WarriorKitShift(false)

water = card("Refreshing Spring Water")

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
-- server, because a window that greys a card out on its own arithmetic is a
-- window that can be wrong in the direction that costs you the sale.
----------------------------------------------------------------------

merchant.rack[3].available = 0
Window.Refresh()

local gone = card("Flask of Petrification")
check(gone ~= nil and not Stock.InStock(gone.entry),
	"the vendor has none left and the window still thinks he has")
check(select(1, Stock.Buy(gone.entry)) == false,
	"the window let a press through on something the vendor has none of")
check(said(box(gone), "Left") == "0",
	"a rack that has run out does not say so")
check(gone:GetAlpha() < 1,
	"something the vendor has run out of is drawn as though you could buy it")

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
-- Three things are asserted. The order is the order you sold in, newest first,
-- because the thing you came here for is the last one you sold. The slots are a
-- range and not a list, so a hole left by something already taken back is
-- skipped rather than drawn blank. And a press on a buyback square buys that
-- entry back rather than buying the rack entry that was drawn on the same
-- button a moment earlier, which is the one way a shared pool could go wrong.
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
	("the buyback tab drew %d cards and two things were sold"):format(shown()))
check(cards[1].name == "Refreshing Spring Water",
	"the buyback rack is not newest first, so the thing you just sold is not the first one")
check(cards[2].name == "Runed Copper Rod",
	"the older of the two sales is not after the newer one")
check(not Grid.Headers()[1]:IsShown(),
	"the buyback rack drew a pile heading, which the tab above it already says")
check(said(box(cards[2]), "Price") == ns.Coined(1000),
	"the box on a buyback card does not carry the price it costs to take back")
check(said(box(cards[2]), "Left") == nil,
	"a buyback card drew a count of how many the vendor has left")
check(said(box(cards[2]), "Shift-click") == nil,
	"a buyback card offered a number to pick, and a slot holds what you sold and no more")
check(foot:GetText() == "2 to buy back",
	("the footer says %q with two things on the rack"):format(foot:GetText()))

-- The press, and the fact it proves is which of the two racks the square
-- belonged to. Taking the rod back costs the thousand he paid for it; the rack
-- entry drawn on this same button a moment ago was the water at twenty five.
purse = state.purse
check(cards[2]:Click("LeftButton") == true, "a click on a buyback card was refused")
check(state.purse == purse - 1000,
	("taking the rod back moved the purse by %d and he paid 1000 for it")
		:format(purse - state.purse))

check(shown() == 1 and cards[1].name == "Refreshing Spring Water",
	"a slot taken back is still on the rack, or the hole it left was drawn as a square")
check(_G.GetNumBuybackItems() == 2,
	"the client stopped counting the empty slot, which is not what it does")

check(Window.Describe():find("buy back") ~= nil,
	"the window says nothing about buyback while that is what it is showing")

tabs.buttons[1]:Click("LeftButton")
check(shown() == 5 and foot:GetText() == "5 for sale",
	"going back to the rack tab did not put the vendor's stock back on the cards")

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

-- With a picker up, because closing the window has to take it with it.
_G.WarriorKitShift(true)
card("Refreshing Spring Water"):Click("LeftButton")
_G.WarriorKitShift(false)
check(UI.Amounting() == 1, "the picker did not open for the walking-away check")

Window.Hide()

check(not merchant.shown(),
	"closing the window left the conversation with the vendor open")
check(UI.Amounting() == nil,
	"a number picker was left on the screen after the window under it went down")
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
	:format(read.count, read.shown, Stock.Vendor() or "nobody", Grid.Describe()))
print(("vendor %s; the client's %s"):format(Window.Describe(), Blizz.Describe()))
