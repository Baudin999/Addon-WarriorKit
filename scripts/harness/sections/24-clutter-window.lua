-- The clutter window
--
-- The only thing in the addon with nothing behind it. A grey sold to a vendor
-- is in the buyback tab; an item destroyed here is gone. So most of what is
-- asserted below is the window refusing: a slot that moved under the card, a
-- cursor holding the wrong thing, a client with no delete call, a second click
-- landing on the card that replaced the one you meant. Each of those is a way
-- to destroy the wrong item, and each one has to end with nothing destroyed.
--
-- Three rules fill the list and each one is asserted on both sides. A rule that
-- offers what it should is half the claim; the half that matters is the thing
-- beside it that it left alone, because every one of those is an item somebody
-- would have destroyed. So the green trade good sitting next to two greys, the
-- guild tabard sitting next to a vest of the same age, and the blue of the same
-- level as the green are all in the fixture on purpose.

local H = ...
local advance, QUESTBAG, refillQuests = H.advance, H.QUESTBAG, H.refillQuests
local destroyed, pickups, ns = H.destroyed, H.pickups, H.ns
local CARRIED, refill, counted = H.CARRIED, H.refill, H.counted
local check = H.check

local function byName(list)
	local out = {}
	for index = 1, #list do
		out[list[index].name] = list[index]
	end
	return out
end

local function verdicts(list)
	local out = {}
	for index = 1, #list do
		out[index] = list[index].verdict
	end
	return table.concat(out, " ")
end

----------------------------------------------------------------------
-- The three rules, on one bagful
--
-- A fourth bag stood up for the gear rule and taken down again at the end of
-- this block, because nothing after this section expects the player to be
-- carrying it.
----------------------------------------------------------------------

refill()
refillQuests()
CARRIED[3] = { "Ragged Leather Vest", "Guild Tabard", "Aged Chain Vest" }

local all = ns.Clutter.Scan()
local every = byName(all)

check(#all == 8, ("clear offered %d of the 8 things in the bags that are finished with")
	:format(#all))

-- Money. A vendor that will not take it at all, a stack under the floor, and a
-- green worth nineteen silver that is nobody's clutter.
check(every["Broken Twig"] and every["Broken Twig"].verdict == "worthless",
	"a grey no vendor will take was not offered as worthless")
check(every["Tattered Cloth"] and every["Tattered Cloth"].verdict == "cheap",
	"a grey worth twelve copper was not offered as cheap")
check(every["Chipped Boar Tusk"] and every["Chipped Boar Tusk"].verdict == "cheap",
	"a grey worth forty seven copper was not offered as cheap")
check(every["Emerald Pigment"] == nil, "a green worth nineteen silver was offered")

-- Level. A white vest thirteen levels behind you, and the two beside it that
-- the rule must not reach: a tabard has no level and never will, and a blue is
-- not measured whatever its level says.
check(every["Ragged Leather Vest"] and every["Ragged Leather Vest"].verdict == "outgrown",
	"a white vest rated fourteen was not offered to a level 62 character")
check(every["Guild Tabard"] == nil, "a tabard was offered for being low level")
check(every["Aged Chain Vest"] == nil, "a blue was offered for being low level")

-- Certain is the four the window has no second reading of, and the two
-- judgements are not among them.
check(ns.Clutter.Certain(every["Broken Twig"]), "a vendor's refusal was called a judgement")
check(ns.Clutter.Certain(every["Tattered Cloth"]), "a price under your own floor was called a judgement")
check(not ns.Clutter.Certain(every["Ragged Leather Vest"]), "a level gap was called certain")

-- The order the cards come in. Certain first so the window never opens on a
-- hard question, and least valuable first inside a kind so the first yes is the
-- cheapest one.
check(verdicts(all) == "worthless spent spent spent cheap cheap outgrown open",
	("the cards came in the order %q"):format(verdicts(all)))
local cloth, tusk
for index = 1, #all do
	if all[index].name == "Tattered Cloth" then cloth = index end
	if all[index].name == "Chipped Boar Tusk" then tusk = index end
end
check(cloth < tusk, "the more valuable grey was offered before the cheaper one")

----------------------------------------------------------------------
-- Both numbers are the player's own
----------------------------------------------------------------------

local worth = ns.db.clutterWorth
ns.db.clutterWorth = 0
local none = byName(ns.Clutter.Scan())
check(none["Broken Twig"] ~= nil, "a floor of nought stopped the vendor's own refusal")
check(none["Tattered Cloth"] == nil and none["Chipped Boar Tusk"] == nil,
	"a floor of nought still offered a grey a vendor would pay for")
ns.db.clutterWorth = worth

local gap = ns.db.clutterLevel
ns.db.clutterLevel = 60
check(byName(ns.Clutter.Scan())["Ragged Leather Vest"] == nil,
	"a gap of sixty levels still offered an item thirteen behind you")
ns.db.clutterLevel = gap

-- The whole stack, not one of them. A slot is what you are short of and a slot
-- holds the stack, so fifty cloth at twelve copper is six silver and is over
-- the floor that one of them is under.
counted(1, 2, 50)
check(byName(ns.Clutter.Scan())["Tattered Cloth"] == nil,
	"the money rule priced one of a stack rather than the slot")
counted(1, 2, 1)

CARRIED[3] = nil

----------------------------------------------------------------------
-- The verdict
--
-- The quest half on its own, with the greys taken out of the bags, because
-- everything below drives the two buttons and the queue has to be the four
-- quest items the fixtures were written for.
----------------------------------------------------------------------

local stowed = {}
for slot = 1, #CARRIED[1] do
	stowed[slot], CARRIED[1][slot] = CARRIED[1][slot], false
end

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

-- The greys go back in first, because the claim here is that the other two
-- rules go on answering when the database is gone.
for slot = 1, #stowed do
	CARRIED[1][slot] = stowed[slot]
end

local realLoader = _G.QuestieLoader
_G.QuestieLoader = nil
local without, why = ns.Clutter.Scan()
local left = byName(without)
check(why == "questie", "a missing Questie was not reported")
check(left["Hogger's Claw"] == nil and left["Rogue's Token"] == nil,
	"a quest item was judged with no database behind it")
check(left["Broken Twig"] ~= nil and left["Tattered Cloth"] ~= nil,
	"a missing Questie took the greys out of the list as well")
check(not ns.Clutter.Ready(), "a missing Questie still reported a working database")

-- The trap. ImportModule answers a fresh empty table for a module it does
-- not carry, so the module coming back is no proof of anything.
_G.QuestieLoader = { ImportModule = function() return {} end }
check(not ns.Clutter.Ready(), "an empty Questie module was taken for a working database")
_G.QuestieLoader = realLoader

ns.Destroy.Hide()
refill()
refillQuests()

print(("clutter %d of %d things in the bags finished with, %d of them quest items,"
	.. " %d destroyed and %d refusals held")
	:format(#all, #QUESTBAG + #CARRIED[1] + 3, #found, #destroyed, 3))
