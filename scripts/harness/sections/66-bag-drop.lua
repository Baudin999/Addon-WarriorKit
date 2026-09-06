-- Dropping on the window
--
-- One claim: an item let go of anywhere on the bag window that is not a square
-- goes into a bag. A square is the client's own button and the drop on one is
-- the client's code; this is the other ninety per cent of the window, the air
-- between squares and the headings and the title bar, which used to leave the
-- item on the cursor.
--
-- Three things are asserted, in the order they can be wrong. The item landed
-- and the cursor is empty. It landed in the first bag with room, which means
-- the walk went past three full bags rather than stopping at the backpack. And
-- a drop with nothing on the cursor is a click on the window and nothing else,
-- because the same handler answers a mouse up and every mouse up is not a drop.

local H = ...
local ns, check = H.ns, H.check
local CARRIED, refill, refillQuests = H.CARRIED, H.refill, H.refillQuests

local Window = ns.BagsWindow

----------------------------------------------------------------------
-- The scene: the four bags 55-bags.lua describes, three full and the
-- fourth with three empty slots, which is the only room there is.
----------------------------------------------------------------------

refill()
refillQuests()
CARRIED[3] = { false, false, false }
CARRIED[4] = nil

Window.Show()
Window.Refresh()

local frame = _G.WarriorKitBags
check(type(frame:GetScript("OnReceiveDrag")) == "function",
	"the bag window has no handler for a drag let go of over it")
check(type(frame:GetScript("OnMouseUp")) == "function",
	"the bag window has no handler for a click with an item in hand")

-- Both gestures land on the title bar rather than in the middle of the window,
-- because the middle of it is thirty-four bag squares and a press there is a
-- press on a square. Aiming eight units in from the corner is where the window
-- itself is the frame under the pointer, which is the whole of what makes these
-- two handlers reachable at all.
local function letGo()
	return H.mouse.Give(frame, 8, -8)
end

local function clickOn()
	local took = H.mouse.Click(H.mouse.Point(frame, 8, -8))
	check(took == frame, ("a click on the bag window's bar landed on %s")
		:format(took and (took:GetName() or took:GetObjectType()) or "nothing"))
	return took
end

-- Nothing in hand. The click that dismisses a dropdown must not become a move.
local before = {}
for bag = 0, 3 do
	before[bag] = {}
	for slot = 1, #CARRIED[bag] do
		before[bag][slot] = CARRIED[bag][slot]
	end
end
clickOn()
local moved = false
for bag = 0, 3 do
	for slot = 1, #CARRIED[bag] do
		if CARRIED[bag][slot] ~= before[bag][slot] then
			moved = true
		end
	end
end
check(not moved, "a click on the window with nothing in hand moved something")

-- A weapon out of the backpack, in hand, let go of over the window. Bags nought
-- to two are full, so the first room is the first slot of the third.
local carried = CARRIED[0][1]
_G.PickupContainerItem(0, 1)
check(_G.GetCursorInfo() == "item", "the pickup left nothing on the cursor")
letGo()
check(_G.GetCursorInfo() == nil, "the drop left the item on the cursor")
check(CARRIED[3][1] == carried,
	("the item landed in the wrong place: the third bag holds %s")
		:format(tostring(CARRIED[3][1])))
check(CARRIED[0][1] == false, "the item is still in the slot it was picked up from")

-- And the other route, a click-carried item, through the mouse up. The first
-- room now is the slot the last drop emptied, at the front of the backpack,
-- which is where the client's own backpack button would put it too.
carried = CARRIED[0][2]
_G.PickupContainerItem(0, 2)
clickOn()
check(_G.GetCursorInfo() == nil, "a click with an item in hand left it on the cursor")
check(CARRIED[0][1] == carried and CARRIED[0][2] == false,
	"the second drop did not take the first free slot, at the front of the backpack")

-- With no room anywhere the item stays in hand, which is what the client does
-- and the only honest answer: nothing here may destroy or swap to make space.
CARRIED[0][2] = "Chipped Boar Tusk"
CARRIED[3][2], CARRIED[3][3] = "Chipped Boar Tusk", "Chipped Boar Tusk"
carried = CARRIED[0][3]
_G.PickupContainerItem(0, 3)
letGo()
check(_G.GetCursorInfo() == "item", "a drop with no room anywhere took the item somewhere")
check(CARRIED[0][3] == carried, "a drop with no room anywhere emptied the source slot")
_G.ClearCursor()

print("drop   two items let go of over the window, both in a bag; a third with no room anywhere still in hand")

Window.Hide()
CARRIED[3] = nil
