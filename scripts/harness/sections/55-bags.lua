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
check(empty ~= nil and #empty.entries == 3,
	"the empty slots are not a pile of their own")

if empty then
	local wrong = 0
	for index = 1, #empty.entries do
		if empty.entries[index].bag ~= 3 then
			wrong = wrong + 1
		end
	end
	check(wrong == 0, ("%d empty squares point at a bag that is not the empty one"):format(wrong))
end

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

check(Window.Show(), "the bag window refused to open")
check(Window.Shown(), "the bag window was opened and is not up")

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
	tall = tall + Grid.HEADER + lines * Grid.SLOT + (lines - 1) * Grid.GAP
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

-- One square per slot in the bags, and every one of them pointing at the slot
-- the scan put on it. This is the claim Mail/Bags.lua also depends on: a bag
-- button says which slot it is by its own id and which bag by its parent's.
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
check(drawn == slots, ("%d squares drawn for %d slots"):format(drawn, slots))
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
