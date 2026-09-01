-- The bag window
--
-- Two claims, and the rest of the file is in service of them.
--
-- The piles are the client's own item classes and nothing here decides them, so
-- what is asserted is the two places the classes are overruled: a grey goes to
-- the bottom whatever class it is, and an item the client has graded nothing
-- stays where its class put it rather than being called junk on a guess.
--
-- And a square is a real bag slot. It is built on the client's own bag button
-- so the click is the client's code, which means the only thing that can be
-- wrong is which slot the square is pointing at, and that is a fact about the
-- parent it was given and the id it was set to. So the click is made the way
-- the client makes it, by calling the global every bag button in the game
-- routes through, and what is checked is that the right item was sold.

local H = ...
local ns, check = H.ns, H.check
local CARRIED, ITEMS, refill = H.CARRIED, H.ITEMS, H.refill
local refillQuests, state = H.refillQuests, H.state

local Bags, Grid, Window = ns.Bags, ns.BagsGrid, ns.BagsWindow

----------------------------------------------------------------------
-- The scene
--
-- Three of the five bags carry something and the fourth is put here: three
-- empty slots, which is the only way this suite has ever had a free slot at
-- all. Every other section is written against a character whose bags are full,
-- because a bag with a hole in it moves the numbers the vendor and the clutter
-- sections count.
----------------------------------------------------------------------

refill()
refillQuests()
CARRIED[3] = { false, false, false }

local carried = #CARRIED[0]
local slots = carried + #CARRIED[1] + #CARRIED[2] + #CARRIED[3]

local read = Bags.Read()

local function pile(key)
	for index = 1, read.shown do
		if read.groups[index].key == key then
			return read.groups[index]
		end
	end
	return nil
end

local function named(group, name)
	for index = 1, #group.entries do
		if group.entries[index].name == name then
			return group.entries[index], index
		end
	end
	return nil
end

----------------------------------------------------------------------
-- The piles
----------------------------------------------------------------------

check(read.slots == slots,
	("the scan counted %d slots and the bags hold %d"):format(read.slots, slots))
check(read.free == 3,
	("the scan found %d free slots and three of them are empty"):format(read.free))

local junk, trade = pile("junk"), pile("trade")
local quest, empty = pile("quest"), pile("empty")

check(junk ~= nil and #junk.entries == 3,
	"the three greys did not land in one pile of three")
check(junk and named(junk, "Chipped Boar Tusk") ~= nil,
	"a grey trade good was not filed as junk")
-- The whole of the junk rule. Emerald Pigment is the same item class as the
-- three greys above it and the client grades it green, so a pile built on class
-- alone puts all four together and a pile that reads quality first puts every
-- trade good in with the vendor trash.
check(trade ~= nil and #trade.entries == 1 and named(trade, "Emerald Pigment"),
	"a green trade good was not left in its own class")
check(quest ~= nil and #quest.entries == #CARRIED[2],
	"the quest items did not all land in the quest pile")
-- Three free slots, one square. The pile folds so the window draws the number
-- rather than three identical grey holes, and the count on that one entry is
-- the size of the pile rather than a stack size.
check(empty ~= nil and #empty.entries == 1,
	("the empty pile drew %d squares and it folds to one")
		:format(empty and #empty.entries or 0))
check(empty and empty.entries[1].count == 3,
	("the folded empty square counts %s free and three of them are")
		:format(tostring(empty and empty.entries[1].count)))
-- The square that survives is a real slot in the bag that is empty, which is
-- what lets a drag onto it land somewhere free rather than nowhere.
check(empty and empty.entries[1].bag == 3 and not empty.entries[1].link,
	"the folded empty square does not point at a free slot in the empty bag")

-- The piles come out in the shipped order, which is a subsequence of it rather
-- than the whole list: a pile with nothing in it is not drawn at all.
local ORDER = { "hearthstone", "consumable", "weapon", "armor", "container",
	"quiver", "projectile", "trade", "reagent", "recipe", "quest", "key",
	"misc", "other", "junk", "empty" }

local at, ordered = 0, true
for index = 1, read.shown do
	local found = nil
	for step = at + 1, #ORDER do
		if ORDER[step] == read.groups[index].key then
			found = step
		end
		if found then
			break
		end
	end
	if not found then
		ordered = false
	else
		at = found
	end
end
check(ordered, "the piles came out in an order the shipped list does not hold")

-- Grade first inside a pile, which is what puts the one thing worth seeing at
-- the front of it. Both weapons are in bag 0 and the orange one is second there,
-- so a pile that kept the order it found them in would fail this.
local weapon = pile("weapon")
if weapon and #weapon.entries > 1 then
	check(weapon.entries[1].name == "Arcanite Reaper",
		("the best weapon is not first in its pile; %s is"):format(tostring(weapon.entries[1].name)))
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

-- Where you left it, before the window is built, because the corner is read
-- once at build and never again.
--
-- Not in 51-placing with the other seven. This window is made the first time
-- you open it, so at that section there is no frame to drop, and the fault this
-- guards is not the drag: the corner was written down correctly and read back
-- correctly, and the window still opened half a bag lower every time, because
-- the first fit pinned the top of a two row placeholder and grew the piles
-- downward off it. So what is asserted is the anchor surviving the first draw,
-- which is the pass that used to eat it.
--
-- In a block of its own because this chunk is four names off the limit that
-- keeps a section readable, and none of these three is read below.
do
	local DROPPED = { "RIGHT", "UIParent", "RIGHT", -419, -26 }
	ns.db.windowSpots.WarriorKitBags = DROPPED

	check(Window.Show(), "the bag window refused to open")
	check(Window.Shown(), "the bag window was opened and is not up")

	local frame = _G.WarriorKitBags
	local opened = { frame:GetPoint() }
	check(opened[1] == DROPPED[1] and opened[3] == DROPPED[3]
			and opened[4] == DROPPED[4] and opened[5] == DROPPED[5],
		("the bag window was left at %s %s, %s and opened at %s %s, %s"):format(
			DROPPED[1], DROPPED[4], DROPPED[5],
			tostring(opened[1]), tostring(opened[4]), tostring(opened[5])))

	-- And the other half: dropped somewhere else, it writes the new corner down.
	frame.scripts.OnDragStart(frame)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 111, -222)
	frame.scripts.OnDragStop(frame)
	local dropped = ns.db.windowSpots.WarriorKitBags
	check(dropped and dropped[1] == "TOPLEFT" and dropped[4] == 111 and dropped[5] == -222,
		"the bag window was dragged and wrote down " .. (dropped
			and ("%s at %s, %s"):format(tostring(dropped[1]), tostring(dropped[4]),
				tostring(dropped[5])) or "nothing"))
	ns.db.windowSpots.WarriorKitBags = nil
end

local window = Window.Frame()
check(window ~= nil and window.frame:GetName() == "WarriorKitBags",
	"the bag window is not the named frame escape closes")

check(window and window.free:GetText() == ("%d free of %d"):format(3, slots),
	("the footer reads %q"):format(tostring(window and window.free:GetText())))
check(window and window.purse:GetText() == ns.Coined(_G.GetMoney()),
	"the footer is not drawing what you are carrying in coin")

-- The height is the piles', not a constant. Every row of every pile, plus the
-- heading over each one and the air between them, worked out from the same three
-- numbers the grid lays out with, and the window's body has to come to exactly
-- that. A window that went back to a fixed rectangle would fail here rather than
-- silently start scrolling a bag that fits.
local tall = 0
for index = 1, read.shown do
	local lines = math.ceil(#read.groups[index].entries / ns.db.bagColumns)
	tall = tall + ns.UI.SLOT_HEADER + lines * ns.UI.SLOT + (lines - 1) * ns.UI.SLOT_GAP
end
tall = tall + (read.shown - 1) * ns.UI.Metric.rowGap

check(window and window:Body() == tall + ns.UI.Metric.pad * 2,
	("the window's body is %d and the piles come to %d")
		:format(window and window:Body() or -1, tall + ns.UI.Metric.pad * 2))

local squares = Grid.Squares()
local headers = Grid.Headers()

check(#headers >= read.shown,
	("%d headers for %d piles"):format(#headers, read.shown))
check(headers[1] and headers[1]:GetText() == read.groups[1].name,
	"the first header does not name the first pile")

-- One square per slot you are using, plus the one the empty pile folds into,
-- and every one of them pointing at the slot the scan put on it. This is the
-- claim Mail/Bags.lua also depends on: a bag button says which slot it is by
-- its own id and which bag by its parent's.
local drawn, wrong = 0, 0
for index = 1, read.shown do
	local entries = read.groups[index].entries
	for held = 1, #entries do
		drawn = drawn + 1
		local square = squares[drawn]
		if not square or square:GetID() ~= entries[held].slot
			or square:GetParent():GetID() ~= entries[held].bag then
			wrong = wrong + 1
		end
	end
end
check(drawn == slots - read.free + 1,
	("%d squares drawn for %d used slots and one folded empty square")
		:format(drawn, slots - read.free))
check(wrong == 0, ("%d squares point at a slot that is not theirs"):format(wrong))

-- And nothing the template drew is still on it.
--
-- Every region of the square is walked rather than the two the widget answers by
-- getter, because the glow that reached the screen was neither of those. It is
-- an ordinary texture the template leaves showing, hidden again in the
-- template's own OnLeave, and the addon takes OnEnter and OnLeave for its
-- tooltip, so every square in the window wore it at once. A check that asked the
-- getters passed the whole time it was on screen.
--
-- The reading is the file a region points at rather than whether it is shown.
-- The widget shows and hides its own textures in C, where a Lua Hide is never
-- read, so a blanked texture draws nothing whatever the widget then does with it
-- and a hidden one does not.
--
-- The press is the one state the square keeps, in the addon's own black, because
-- a square that does not move under the mouse reads as a square that ate the
-- click.
-- Held in a block of its own, because the names in it are the section's and the
-- section is at its own ceiling for how many of those it may have at the top
-- level. Three readings that nothing below this point needs are three names
-- that do not have to be up there.
do
	local THEIRS = {
		["Interface\\Buttons\\ButtonHilight-Square"] = true,
		["Interface\\Buttons\\UI-Quickslot2"] = true,
	}

	local wearing, dead = 0, 0
	for index = 1, drawn do
		local square = squares[index]
		local pushed = square:GetPushedTexture()
		for _, region in ipairs({ square:GetRegions() }) do
			if region ~= pushed and THEIRS[region:GetTexture() or false] then
				wearing = wearing + 1
			end
		end
		for _, getter in ipairs({ "GetNormalTexture", "GetHighlightTexture" }) do
			local texture = square[getter](square)
			if texture and THEIRS[texture:GetTexture() or false] then
				wearing = wearing + 1
			end
		end
		-- The press is a colour rather than a file, so it is read as one: a colour
		-- texture answers no path at all.
		if not pushed or pushed:GetTexture() or not pushed.a then
			dead = dead + 1
		end
	end
	check(wearing == 0, ("%d of the client's own textures left on the squares"):format(wearing))
	check(dead == 0, ("%d squares draw nothing when they are pressed"):format(dead))
end

-- And nothing on a square hands the right button to the camera.
--
-- The right click on a bag slot is the whole of eat, equip, open, sell, attach
-- and put a stone on your axe, and a square that passes the right button
-- through answers none of them. It is invisible from every other check in this
-- file: the square is built, dressed, pointed at the right slot, and the click
-- below goes in through the global rather than the widget, so it lands whatever
-- the button does with the mouse. This is the only reading that catches it.
do
	local passing = 0
	for index = 1, drawn do
		local passed = squares[index]:GetPassThroughButtons()
		if passed and passed["RightButton"] then
			passing = passing + 1
		end
	end
	check(passing == 0,
		("%d squares pass the right button through, so a right click on them turns the camera")
			:format(passing))
end

----------------------------------------------------------------------
-- A click on one
--
-- Through the global rather than through the square's own handler, because the
-- global is what the client's own template calls and is the name Mail/Bags.lua
-- takes over. A test that called the button's script directly would prove the
-- script and not the seam.
--
-- At a merchant, because that is the one thing a right click on a bag slot does
-- that leaves a number behind. With the window down the same call eats or
-- equips whatever is in the slot, which is the failure this is written around.
----------------------------------------------------------------------

local tusk, where = named(junk, "Chipped Boar Tusk")
local square

if tusk then
	local seen = 0
	for index = 1, read.shown do
		local entries = read.groups[index].entries
		for held = 1, #entries do
			seen = seen + 1
			if entries[held] == tusk then
				square = squares[seen]
			end
		end
	end
end

if square then
	local before = state.purse
	_G.MerchantFrame:Show()
	_G.ContainerFrameItemButton_OnClick(square, "RightButton")
	_G.MerchantFrame:Hide()
	check(state.purse == before + ITEMS["Chipped Boar Tusk"].price,
		("a click on the square at %d sold %d copper of the wrong thing")
			:format(where or 0, state.purse - before))
	check(_G.GetContainerItemLink(tusk.bag, tusk.slot) == nil,
		"the slot the square pointed at still holds the item that was sold")
else
	check(false, "no square was drawn for the item the click was aimed at")
end

refill()
Window.Refresh()
check(select(1, Bags.Free()) == 3,
	"the refill did not put the bags back the way the window found them")

----------------------------------------------------------------------
-- The merchant row
--
-- The window grows a row while a vendor is open and loses it again when you
-- walk away, and what is on the row is what the two Chores parts would do if
-- you asked them: the greys this vendor will take, and the bill for your gear.
--
-- The squares change with it. A grey a vendor pays for wears a coin, the one
-- grey nobody buys does not, and what a merchant will not take at all goes dim
-- for as long as you are standing there.
----------------------------------------------------------------------

do
	local Merchant = ns.BagsMerchant
	local sell, repair = Merchant.Buttons()
	local plain = window:Body()

	check(Merchant.Height() == 0, "the merchant row is up with no merchant open")

	_G.MerchantFrame:Show()
	H.fire("MERCHANT_SHOW")

	check(Merchant.Open(), "a merchant opened and the bag window did not notice")
	check(Merchant.Height() > 0, "the merchant row is not up at a merchant")
	check(window:Body() == plain + Merchant.Height(),
		("the window is %d tall and the row wants %d over the %d it was")
			:format(window:Body(), Merchant.Height(), plain))

	-- Two of the three greys, because Broken Twig is priced at nothing and is
	-- the one thing in the junk pile a vendor will not take. That is the whole
	-- difference between the pile and the sale.
	check(sell:IsShown() and sell.text:GetText() == "sell 2 greys",
		("the sell button reads %q and two of the three greys are sellable")
			:format(tostring(sell:IsShown() and sell.text:GetText())))

	-- The coin is on what the sale will take and on nothing else.
	local coined, marked = 0, {}
	for index = 1, drawn do
		if squares[index].coin:IsShown() then
			coined = coined + 1
			marked[squares[index].name or "?"] = true
		end
	end
	check(coined == 2, ("%d squares wear the coin and two greys are sellable")
		:format(coined))
	check(marked["Chipped Boar Tusk"] and not marked["Broken Twig"],
		"the coin is on the grey nobody buys, or missing from one they do")

	-- And what the merchant will not buy is dim. Counted off the bags rather
	-- than off the window, because the claim is that the window agrees with the
	-- client: the quest items, and the one grey that is priced at nothing.
	local unsellable = 0
	for bag = 0, 4 do
		local held = CARRIED[bag]
		for slot = 1, (held and #held or 0) do
			local name = held[slot]
			if name and ITEMS[name].price == 0 then
				unsellable = unsellable + 1
			end
		end
	end

	local dimmed = 0
	for index = 1, drawn do
		if squares[index]:GetAlpha() < 1 then
			dimmed = dimmed + 1
		end
	end
	check(dimmed == unsellable,
		("%d squares went dim at the merchant and %d things in the bags cannot be sold")
			:format(dimmed, unsellable))

	-- And the pointer says which square you are on. The dimming is the grid at
	-- a glance and it is on everything the vendor refuses at once. The cursor is
	-- the answer for the one square under the mouse, which is the square you are
	-- about to click.
	local buyable, refused
	for index = 1, drawn do
		local square = squares[index]
		local item = square.name and ITEMS[square.name]
		if item and item.price > 0 then
			buyable = buyable or square
		elseif item then
			refused = refused or square
		end
	end
	check(buyable ~= nil and refused ~= nil,
		"the scene has to carry one thing this vendor buys and one it does not")

	local enter = buyable:GetScript("OnEnter")
	local leave = buyable:GetScript("OnLeave")

	check(state.cursor == false, "something wrote the cursor before a square was hovered")

	enter(buyable)
	check(state.cursor == "BUY_CURSOR",
		("the pointer over %s reads %q at a merchant"):format(buyable.name,
			tostring(state.cursor)))
	leave(buyable)
	check(state.cursor == false, "the pointer kept the coin after the mouse left")

	enter(refused)
	check(state.cursor == false,
		("the pointer over %s says sell and no merchant will take it"):format(refused.name))
	leave(refused)

	-- The repair half. The bill is written after the merchant opened, because
	-- the automatic repair pays it on the event and there would be nothing left
	-- for the button to quote.
	state.repairBill = 400
	Window.Refresh()
	check(repair:IsShown() and repair.text:GetText() == "repair " .. ns.Coined(400),
		("the repair button reads %q with a 400 copper bill standing")
			:format(tostring(repair:IsShown() and repair.text:GetText())))

	local purse = state.purse
	repair:Click("LeftButton")
	check(state.repairBill == 0, "the repair button did not pay the merchant")
	check(state.purse == purse - 400, "the repair was reported and nothing was paid")

	Window.Refresh()
	check(not repair:IsShown(), "nothing is damaged and the repair button is still up")

	-- Walking away. The row goes, the dimming goes with it, and the window is
	-- the height it was before the vendor.
	--
	-- The pointer is left on a square you could have sold, because that is the
	-- one way out of the coin cursor that is not an OnLeave: the mouse has not
	-- moved, the merchant closed under it, and the repaint is the only thing
	-- that finds out.
	enter(buyable)
	H.fire("MERCHANT_CLOSED")
	_G.MerchantFrame:Hide()
	check(state.cursor == false,
		"the merchant closed and the pointer still says sell")
	leave(buyable)
	check(not Merchant.Open(), "the merchant closed and the window still thinks one is open")
	check(Merchant.Height() == 0, "the merchant closed and the row is still up")
	check(window:Body() == plain,
		("the window stayed %d tall and it was %d before the merchant")
			:format(window:Body(), plain))

	local left = 0
	for index = 1, drawn do
		if squares[index]:GetAlpha() < 1 then
			left = left + 1
		end
	end
	check(left == 0, ("%d squares are still dim with no merchant open"):format(left))
end

----------------------------------------------------------------------
-- The nine calls
--
-- Every one of them reaches this window and none of them reaches the client's.
-- The three you press are the interesting half, and OpenAllBags is the one that
-- is not pressed at all: it is what a merchant and a bank call, and leaving it
-- in the client's hands is five of Blizzard's bags on the screen the first time
-- you sell something.
----------------------------------------------------------------------

local opened, closed = H.bagCalls()

_G.ToggleBackpack()
check(not Window.Shown(), "B did not close the window that was open")
_G.ToggleBackpack()
check(Window.Shown(), "B did not open it again")

_G.CloseAllBags()
check(not Window.Shown(), "walking away from a merchant did not shut the window")
_G.OpenAllBags()
check(Window.Shown(), "a merchant did not open the window")

_G.ToggleBag(1)
check(not Window.Shown(), "a bag button on the bar did not reach this window")
_G.OpenBag(1)
check(Window.Shown(), "a loot toast did not reach this window")
_G.CloseBackpack()
check(not Window.Shown(), "the backpack close did not reach this window")
_G.OpenBackpack()
check(Window.Shown(), "the backpack open did not reach this window")
_G.CloseBag(1)
check(not Window.Shown(), "the single bag close did not reach this window")
_G.ToggleAllBags()
check(Window.Shown(), "the all-bags binding did not reach this window")

local nowOpened, nowClosed = H.bagCalls()
check(nowOpened == opened and nowClosed == closed,
	("the client's own bags were asked to open %d times and shut %d during that")
		:format(nowOpened - opened, nowClosed - closed))

local found, of = ns.BagsBlizzard.Found()
check(found == of, ("%d of %d bag calls found on this client"):format(found, of))
check(ns.BagsBlizzard.Held(), "the addon is drawing the bags and not holding the keys")

----------------------------------------------------------------------
-- Off again
--
-- The nine go back, and they go back to the functions that were on them rather
-- than to something this addon built, which is the half a switch usually gets
-- wrong.
----------------------------------------------------------------------

SlashCmdList.WARRIORKIT("bags off")
check(not Window.Shown(), "turning the window off left it on the screen")
check(not ns.BagsBlizzard.Held(), "the window is off and the addon is still holding B")

_G.ToggleBackpack()
local backOpened = select(1, H.bagCalls())
check(backOpened == nowOpened + 1,
	"B does not reach the client's own bags again with the window switched off")
check(not Window.Shown(), "the window came back up with the feature switched off")

SlashCmdList.WARRIORKIT("bags on")
check(ns.BagsBlizzard.Held(), "turning the window back on did not take the keys again")

CARRIED[3] = nil
Window.Hide()

print(("bags   %d slots, %d piles, %d free; %s; the client's %s")
	:format(read.slots, read.shown, 3, Grid.Describe(), ns.BagsBlizzard.Describe()))
print(("bags   %s"):format(Bags.Describe()))
