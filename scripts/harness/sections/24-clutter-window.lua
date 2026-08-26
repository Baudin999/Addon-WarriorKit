-- The clutter window
--
-- The only thing in the addon with nothing behind it. A grey sold to a vendor
-- is in the buyback tab; an item destroyed here is gone. So most of what is
-- asserted below is the window refusing: a slot that moved under the card, a
-- cursor holding the wrong thing, a client with no delete call, a second click
-- landing on the card that replaced the one you meant. Each of those is a way
-- to destroy the wrong item, and each one has to end with nothing destroyed.

local H = ...
local advance, QUESTBAG, refillQuests = H.advance, H.QUESTBAG, H.refillQuests
local destroyed, pickups, ns = H.destroyed, H.pickups, H.ns
local check = H.check

local function byName(list)
	local out = {}
	for index = 1, #list do
		out[list[index].name] = list[index]
	end
	return out
end

----------------------------------------------------------------------
-- The verdict
----------------------------------------------------------------------

refillQuests()
local found = ns.Clutter.Scan()
local seen = byName(found)

check(#found == 4,
	("the scan offered %d of 7 quest items; 4 of them are finished with"):format(#found))
check(seen["Diplomat's Ring"] == nil, "an item wanted by a quest in your log was offered")
check(seen["Sealed Letter"] == nil, "an item that starts a quest you have not done was offered")
check(seen["Unknown Trinket"] == nil, "an item the database has never heard of was offered")
check(seen["Hogger's Claw"] ~= nil and ns.Clutter.Certain(seen["Hogger's Claw"]),
	"an item whose only quest is behind you was not offered as certain")
check(seen["Zul'Mamwe Fetish"] ~= nil and ns.Clutter.Certain(seen["Zul'Mamwe Fetish"]),
	"an item whose two quests are both behind you was not offered as certain")
check(seen["Old Cipher"] ~= nil and ns.Clutter.Certain(seen["Old Cipher"]),
	"a starter for a quest you have already completed was not offered")
check(seen["Rogue's Token"] ~= nil and not ns.Clutter.Certain(seen["Rogue's Token"]),
	"an item for a quest still out there was not flagged as the uncertain one")

-- Certain first, so the window never opens on the hard question.
check(ns.Clutter.Certain(found[1]), "the queue did not put a certain item first")
check(not ns.Clutter.Certain(found[#found]), "the queue did not put the uncertain one last")

-- And the card names the quest, which is the whole reason the window exists
-- rather than a list of item names.
check(seen["Hogger's Claw"].reason:find("Wanted: Hogger", 1, true) ~= nil,
	"the card does not name the quest the item came from")
check(seen["Rogue's Token"].reason:find("A Rogue's Deal", 1, true) ~= nil,
	"the uncertain card does not name the quest that still wants the item")

----------------------------------------------------------------------
-- Cycling
----------------------------------------------------------------------

ns.Destroy.Show()

local clutter
for _, held in ipairs(ns.UI.Windows) do
	if held.frame and held.frame:GetName() == "WarriorKitClutter" then
		clutter = held
	end
end
check(clutter ~= nil, "the clutter window was never built")

local card = clutter.card
check(card.count:GetText() == "1 of 4",
	("the counter opened on %q rather than 1 of 4"):format(tostring(card.count:GetText())))

local before = #destroyed
card.skip.scripts.OnClick()
check(#destroyed == before, "skip destroyed something")
check(card.count:GetText() == "2 of 4",
	("skip left the counter on %q"):format(tostring(card.count:GetText())))

advance(1)
card.destroy.scripts.OnClick()
check(#destroyed == before + 1, "the destroy button destroyed nothing")
check(destroyed[#destroyed]:find("Old Cipher", 1, true) ~= nil,
	"destroy took an item other than the one on the card")

-- Two clicks in the same instant is one destroy. The window replaces the
-- card the moment the first lands, so without the debounce the second falls
-- on an item nobody looked at.
local held = #destroyed
card.destroy.scripts.OnClick()
check(#destroyed == held, "a second click in the same instant destroyed another item")

----------------------------------------------------------------------
-- Every way it has to refuse
----------------------------------------------------------------------

-- The slot moved under the card. Something looted, the vendor sweep sold,
-- a stack split and everything after it shifted by one.
refillQuests()
ns.Destroy.Show()
QUESTBAG[1] = "Unknown Trinket"
held = #destroyed
local touched = pickups
advance(1)
card.destroy.scripts.OnClick()
check(#destroyed == held, "the window destroyed whatever had replaced the item on the card")
check(QUESTBAG[1] == "Unknown Trinket", "the replacement item was destroyed")
-- And it never reached the cursor. The cursor check would have caught this
-- too, so counting pickups is the only way to say the slot re-read in front
-- of it is still there.
check(pickups == touched, "a stale card still put an item on the cursor")

-- The cursor came up holding something else, which is the client
-- contradicting the bag scan. It is a second opinion and it gets to win.
refillQuests()
ns.Destroy.Show()
local realPickup = _G.PickupContainerItem
_G.PickupContainerItem = function() realPickup(2, 7) end
held = #destroyed
advance(1)
card.destroy.scripts.OnClick()
check(#destroyed == held, "a cursor holding the wrong item was deleted anyway")
check(_G.GetCursorInfo() == nil, "the cursor was left holding an item")
_G.PickupContainerItem = realPickup

-- A client with no DeleteCursorItem. Nothing installed on either client
-- calls it, Questie only hooks it, so this is the client the probe exists
-- for and it has to refuse rather than raise.
refillQuests()
ns.Destroy.Show()
local realDelete = _G.DeleteCursorItem
_G.DeleteCursorItem = nil
held = #destroyed
advance(1)
card.destroy.scripts.OnClick()
check(#destroyed == held, "something was destroyed on a client with no delete call")
check(_G.GetCursorInfo() == nil, "the cursor was left holding an item")
_G.DeleteCursorItem = realDelete

----------------------------------------------------------------------
-- Without Questie
----------------------------------------------------------------------

local realLoader = _G.QuestieLoader
_G.QuestieLoader = nil
local none, why = ns.Clutter.Scan()
check(#none == 0 and why == "questie", "a missing Questie did not stop the scan")
check(not ns.Clutter.Ready(), "a missing Questie still reported a working database")

-- The trap. ImportModule answers a fresh empty table for a module it does
-- not carry, so the module coming back is no proof of anything.
_G.QuestieLoader = { ImportModule = function() return {} end }
check(not ns.Clutter.Ready(), "an empty Questie module was taken for a working database")
_G.QuestieLoader = realLoader

ns.Destroy.Hide()
refillQuests()

print(("clutter %d of %d quest items finished with, %d destroyed and %d refusals held")
	:format(#found, #QUESTBAG, #destroyed, 3))
