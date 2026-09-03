-- The wait before a square's box, and the hold at a merchant
--
-- Two claims about the bag window, both about what it does not do.
--
-- A square's box does not open on the way in. The pointer crosses a dozen
-- squares to reach the one you want, so the box waits for the hand to stop:
-- it is armed on entering, a move past the drift starts the wait again, and
-- it opens on the frame the wait runs out. Leaving before that opens nothing.
-- What is asserted is each of those frames, driven one at a time through the
-- tick's own function with the stub's pointer moved between them.
--
-- And the squares do not move while you sell. The first paint at a vendor is
-- held, a sale leaves an empty square where the item was, and every other
-- square stays on the point it was laid at. What breaks the hold is asserted
-- too, because a hold that never lets go is a window that cannot draw a
-- purchase: an item landing in a slot no held square points at lays the piles
-- out again, and walking away closes the gaps.

local H = ...
local ns, check = H.ns, H.check
local CARRIED, ITEMS, refill = H.CARRIED, H.ITEMS, H.refill
local refillQuests, state, cursor = H.refillQuests, H.state, H.cursor

local Bags, Grid, Window = ns.Bags, ns.BagsGrid, ns.BagsWindow
local Tip, Tooltip = ns.Tip, ns.UI.Tooltip

----------------------------------------------------------------------
-- The scene, which is 55-bags.lua's: three bags full and three slots free.
----------------------------------------------------------------------

refill()
refillQuests()
CARRIED[3] = { false, false, false }
local slots = #CARRIED[0] + #CARRIED[1] + #CARRIED[2] + #CARRIED[3]

Window.Show()
Window.Refresh()
local window, squares = Window.Frame(), Grid.Squares()

local function shown()
	local count = 0
	for index = 1, #squares do
		if squares[index]:IsShown() then
			count = count + 1
		end
	end
	return count
end

local function find(name)
	for index = 1, #squares do
		local square = squares[index]
		if square:IsShown() and square.name == name then
			return square, index
		end
	end
	return nil
end

-- Every shown square: the slot it points at and the point it was laid on.
local function snapshot()
	local seen = {}
	for index = 1, #squares do
		local square = squares[index]
		if square:IsShown() then
			local _, _, _, x, y = square:GetPoint(1)
			seen[index] = { bag = square.bag, slot = square.slot, x = x, y = y }
		end
	end
	return seen
end

-- How many squares of one snapshot are not where the other has them, or
-- point at a different slot, or are gone.
local function moved(before, after)
	local count = 0
	for index, was in pairs(before) do
		local now = after[index]
		if not now or now.bag ~= was.bag or now.slot ~= was.slot
			or now.x ~= was.x or now.y ~= was.y then
			count = count + 1
		end
	end
	return count
end

-- The client's own click on a square, at a merchant, which sells what is on
-- it; then the repaint the bag update would book.
local function sell(square)
	local purse = state.purse
	_G.ContainerFrameItemButton_OnClick(square, "RightButton")
	Window.Refresh()
	return state.purse - purse
end

----------------------------------------------------------------------
-- The wait
----------------------------------------------------------------------

H.tipSettle()
check(ns.db.bagHover == 50,
	("the wait ships at %s and it ships at 50ms"):format(tostring(ns.db.bagHover)))

local tusk = find("Chipped Boar Tusk")
local cloth = find("Tattered Cloth")
check(tusk ~= nil and cloth ~= nil, "the scene has to draw the two greys the checks hover")
local enter, leave = tusk:GetScript("OnEnter"), tusk:GetScript("OnLeave")

cursor.x, cursor.y = 300, 500
enter(tusk)
check(not Tooltip.IsShown(), "the box opened on the frame the pointer arrived, before it had stopped")
check(Tip.Waiting() > 0, "no wait was armed on the way in")

Tip.Settling(0.02)
check(not Tooltip.IsShown(), "twenty milliseconds in, the box is up before the wait ran out")

-- The hand is still moving. Ten units is well past the drift, so the count
-- starts again from nought and from where the pointer is now.
cursor.x = cursor.x + 10
Tip.Settling(0.02)
check(not Tooltip.IsShown() and math.abs(Tip.Waiting() - 0.05) < 1e-6,
	("the pointer moved and the wait reads %.3f rather than starting again at 0.050")
		:format(Tip.Waiting()))

Tip.Settling(0.03)
check(not Tooltip.IsShown(), "thirty milliseconds after a move, the box is up")
Tip.Settling(0.03)
check(Tooltip.IsShown() and Tooltip.Owner() == tusk,
	"the pointer held still for the wait and the box did not open on the square")
check(Tip.Waiting() == 0, "the box opened and the wait is still armed")

-- The template's own refresh: OnEnter again with the box already up on this
-- square. No wait, because the one thing this must never do is take down a
-- box you were reading.
enter(tusk)
check(Tooltip.IsShown() and Tooltip.Owner() == tusk and Tip.Waiting() == 0,
	"a box already up on the square was taken down to wait for the same box")
leave(tusk)
H.tipSettle()

-- Crossed on the way to somewhere else. The wait is cancelled by leaving, and
-- no number of frames after that opens anything.
enter(cloth)
leave(cloth)
check(Tip.Waiting() == 0, "leaving the square did not cancel the wait")
for _ = 1, 10 do
	Tip.Settling(0.02)
end
check(not Tooltip.IsShown(), "a square the pointer crossed opened a box after the pointer had left")
H.tipSettle()

-- Off is the plain open, on the way in.
ns.db.bagHover = 0
enter(cloth)
check(Tooltip.IsShown() and Tooltip.Owner() == cloth,
	"with the wait off the box did not open as the pointer arrived")
leave(cloth)
H.tipSettle()
ns.db.bagHover = 50

-- The slash word and the panel share one ruler: a stop is taken, and a number
-- between two stops is refused rather than rounded.
SlashCmdList.WARRIORKIT("bags hover 120")
check(ns.db.bagHover == 120,
	("bags hover 120 left the wait at %s"):format(tostring(ns.db.bagHover)))
SlashCmdList.WARRIORKIT("bags hover 55")
check(ns.db.bagHover == 120, "a number off the panel's step was taken")
SlashCmdList.WARRIORKIT("bags hover 50")
check(ns.db.bagHover == 50, "the wait did not go back to fifty")

----------------------------------------------------------------------
-- The hold
----------------------------------------------------------------------

check(Grid.Held() == nil, "the layout is held with no merchant open")

_G.MerchantFrame:Show()
H.fire("MERCHANT_SHOW")

local drawn = shown()
check(Grid.Held() == drawn,
	("%s squares are held at the merchant and %d are drawn"):format(tostring(Grid.Held()), drawn))

local before, body = snapshot(), window:Body()
local free = Bags.Free()

-- One sale. The square stays, empty, on the slot it pointed at, and nothing
-- else moves.
local tuskAt = select(2, find("Chipped Boar Tusk"))
local paid = sell(tusk)
check(paid == ITEMS["Chipped Boar Tusk"].price,
	("the click sold %d copper of something and the tusk is worth %d"):format(paid, ITEMS["Chipped Boar Tusk"].price))

local after = snapshot()
check(moved(before, after) == 0,
	("%d squares moved when one of them sold"):format(moved(before, after)))
check(shown() == drawn,
	("%d squares are drawn after the sale and %d were before it"):format(shown(), drawn))
check(tusk:IsShown() and tusk.link == nil
		and tusk.bag == before[tuskAt].bag and tusk.slot == before[tuskAt].slot,
	"the sold square is not an empty placeholder on the slot it pointed at")
check(tusk.tally:GetText() == "" and tusk.free:GetText() == "" and not tusk.art:IsShown(),
	"the placeholder is drawing a picture or a number")
check(not tusk.coin:IsShown() and tusk:GetAlpha() == 1,
	"the placeholder wears a coin or went dim")
check(window:Body() == body,
	("the window went from %d to %d tall at a merchant with nothing new in it"):format(body, window:Body()))

-- The free count moved, along the bottom and in the middle of the fold, which
-- is still the square it was and not the hole the sale opened.
check(window.free:GetText() == ("%d free of %d"):format(free + 1, slots),
	("the footer reads %q after a sale that freed a slot"):format(tostring(window.free:GetText())))
do
	local folds, reads = 0, nil
	for index = 1, #squares do
		local square = squares[index]
		if square:IsShown() and square.free:GetText() ~= "" then
			folds = folds + 1
			reads = square.free:GetText()
		end
	end
	check(folds == 1 and reads == tostring(free + 1),
		("%d squares carry a free count and it reads %s; one should, and it should read %d")
			:format(folds, tostring(reads), free + 1))
end

-- A second sale holds the same way.
local moreBefore = snapshot()
sell(cloth)
check(moved(moreBefore, snapshot()) == 0, "the second sale moved something")
check(shown() == drawn, "the second sale took a square away")

-- The pointer on a placeholder is told nothing, and waits for nothing.
enter(tusk)
check(not Tooltip.IsShown() and Tip.Waiting() == 0,
	"hovering the placeholder opened a box, or armed a wait for one")
leave(tusk)
H.tipSettle()

-- Something landing in a slot no held square points at. The fold is the first
-- free slot and that is bag 3 slot 1, so the second slot of that bag was never
-- drawn, and an item arriving there is a layout the hold cannot describe.
CARRIED[3][2] = "Linen Cloth"
Window.Refresh()
local linen = find("Linen Cloth")
check(linen ~= nil, "an item that landed outside the held squares was not drawn")
check(shown() == drawn - 1,
	("%d squares after the piles were laid out again, and two holes closing over one arrival is %d")
		:format(shown(), drawn - 1))
check(Grid.Held() == shown(),
	("the layout after the arrival is not held: %s held, %d drawn"):format(tostring(Grid.Held()), shown()))

-- Walking away lets go, and the gaps close.
CARRIED[3][2] = false
H.fire("MERCHANT_CLOSED")
_G.MerchantFrame:Hide()
check(Grid.Held() == nil, "the merchant closed and the layout is still held")
check(shown() == slots - (free + 2) + 1,
	("%d squares drawn away from the merchant, and %d used slots plus the fold is %d")
		:format(shown(), slots - (free + 2), slots - (free + 2) + 1))

print(("hold   the box waited 50ms for the pointer to stop; two sales moved 0 of %d squares, an arrival laid the piles out again, and walking away closed the gaps")
	:format(drawn))

refill()
CARRIED[3] = nil
Window.Refresh()
Window.Hide()
