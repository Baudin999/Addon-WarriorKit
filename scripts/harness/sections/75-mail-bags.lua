-- Right click in the bags, onto the letter
--
-- The client's own way of attaching something and the only one anybody uses.
-- Driven by clicking a square of this addon's bag window with the mail window
-- open, the way the player does, because the take is a registration and an
-- OnMouseUp on that square, and a test that called the addon's own handler
-- would be testing nothing.
--
-- Every check here is about where the stack ends up. A click the addon claimed
-- and then handed back is the failure worth catching: the client's answer to a
-- right click on a bag slot is to eat, equip or sell what is in it. And the
-- square's own registration is read, because that is the mechanism: the right
-- button off it while the letter is open, so the secure OnClick never runs, and
-- back on it when the letter closes, so a scroll reads again.

local H = ...
local ns, fire, check, CARRIED = H.ns, H.fire, H.check, H.CARRIED

local Draft, Grid, Window = ns.MailDraft, ns.BagsGrid, ns.BagsWindow

----------------------------------------------------------------------
-- The scene: a fourth bag of copper ore, and the bag window up
----------------------------------------------------------------------

CARRIED[3] = {}
for slot = 1, 20 do
	CARRIED[3][slot] = "Copper Ore"
end
Window.Show()
Window.Refresh()

local squares = Grid.Squares()
local function square(bag, slot)
	for index = 1, #squares do
		if squares[index].bag == bag and squares[index]:GetID() == slot then
			return squares[index]
		end
	end
	return nil
end

local ORE = 7

----------------------------------------------------------------------
-- With the letter open
----------------------------------------------------------------------

fire("MAIL_SHOW")
check(ns.MailBags.Taking(), "the bag click was not taken over with the window open")
check(Draft.Held() == 0, "the right click block began with something on the draft")

local ore = square(3, ORE)
check(ore ~= nil, "no square was drawn for the ore the click is aimed at")
check(ore and not ore:GetRegisteredClicks().RightButtonUp,
	"a square still answers the right button through its secure OnClick")

ore:Click("RightButton")
check(Draft.Held() == 1,
	("a right click in the bags put %d on the mail"):format(Draft.Held()))
check(CARRIED[3][ORE] == "Copper Ore",
	"the right click used the stack rather than putting it on the mail")

-- The slot that was clicked, not the first one holding that item. This is the
-- whole difference between the click and a drop: twenty identical stacks, and
-- the seventh one you point at is the seventh one that goes.
local put = Draft.At(1)
check(put and put.bag == 3 and put.slot == ORE,
	("the click attached bag %s slot %s rather than the one it landed on")
		:format(tostring(put and put.bag), tostring(put and put.slot)))

-- The same slot twice is one attachment and a refusal, and the refusal is the
-- half that matters: a claimed click handed back is a client that eats the ore.
ore:Click("RightButton")
check(Draft.Held() == 1, "the same stack went on the mail twice")
check(CARRIED[3][ORE] == "Copper Ore", "a refused right click let the client use the stack")

square(3, ORE + 1):Click("RightButton")
check(Draft.Held() == 2, "a second stack of the same item would not go on")

-- A modified click is the client's and goes to its own modified handler, which
-- splits or dresses up and never uses. Nothing goes on the mail.
local modified = H.modifiedBagClicks()
_G.WarriorKitShift(true)
square(3, 20):Click("RightButton")
_G.WarriorKitShift(false)
check(Draft.Held() == 2, "a shift click put something on the mail")
check(H.modifiedBagClicks() == modified + 1, "a shift click did not reach the client")
check(CARRIED[3][20] == "Copper Ore", "a shift click used the stack")

local open = ns.MailBags.Describe()
Draft.Empty()

----------------------------------------------------------------------
-- With the letter closed
----------------------------------------------------------------------

fire("MAIL_CLOSED")
check(not ns.MailBags.Taking(), "the bag click was left taken over with the window closed")
check(ore:GetRegisteredClicks().RightButtonUp,
	"the right button was not given back to the square's secure OnClick")

-- Asserted by clicking rather than by asking, because the flag and the
-- registration are two different things and it is the registration a click
-- reaches. The stub's client uses what is in the slot.
check(ore:Click("RightButton"), "a right click with the window closed did not land")
check(CARRIED[3][ORE] == false, "a right click with the window closed did not reach the client")
check(Draft.Held() == 0, "a right click with the window closed went on a letter")

print(("mailbags a right click goes %s while the letter is open and is %s after; %d squares dressed")
	:format(open, ns.MailBags.Describe(), #squares))

CARRIED[3] = nil
Window.Refresh()
Window.Hide()
