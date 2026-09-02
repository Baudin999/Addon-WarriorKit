-- The two lanes
--
-- One claim: the equipment piles are drawn in two, what has already bound to
-- you on the left and what has not on the right, and every other pile is one
-- lane of the full width with the same air spent at its right edge instead.
--
-- Its own section rather than part of 55-bags.lua because the subject is not
-- the same. That file asks whether a square is a real bag slot; this one asks
-- where the square landed, which is the one pile shape in the window whose
-- column is not the position in the pile.
--
-- **The binding is read off the client's tooltip and nothing else can answer
-- it.** A link carries no history: the sword you have been swinging for three
-- months and the same sword on a shelf are character for character the same
-- string. So the stub is seeded with the client's own two lines about one slot
-- and not about the one beside it, and what is checked is that the two squares
-- came out in different lanes. Without that seeding the whole split reads as
-- unbound and looks tested.
--
-- What this cannot prove is that the game writes ITEM_SOULBOUND where the stub
-- does. That is 11-tooltip.lua's caveat and it applies to every scan in the
-- addon.

local H = ...
local ns, check = H.ns, H.check
local CARRIED, refill, refillQuests = H.CARRIED, H.refill, H.refillQuests

local Bags, Grid, Window = ns.Bags, ns.BagsGrid, ns.BagsWindow

----------------------------------------------------------------------
-- The scene
--
-- 55-bags.lua's, put back: the sections between here and there sell, destroy
-- and loot out of these bags. Bag zero is the gear, and it holds two weapons
-- and a shield.
----------------------------------------------------------------------

refill()
refillQuests()
CARRIED[3] = { false, false, false }

-- Bag zero, slot three is Arcanite Reaper, and the client says it is already
-- yours. Bloodspiller is slot one, the same class in the same bag, and gets no
-- such line: still free to sell or give away.
H.tooltips.bag[H.tooltipKey(0, 3)] = {
	{ "Arcanite Reaper" }, { _G.ITEM_SOULBOUND },
}

-- Opened rather than refreshed. A refresh on a closed window lays nothing out,
-- and the squares would still be sitting where 55-bags.lua left them: the check
-- below would read last section's pile and pass or fail for the wrong reason.
Window.Show()
local read = Bags.Read()
Window.Refresh()

local function pile(key)
	for index = 1, read.shown do
		if read.groups[index].key == key then
			return read.groups[index]
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Which piles split
----------------------------------------------------------------------

check(pile("weapon") ~= nil and pile("weapon").split == true,
	"the weapon pile is not marked as one drawn in two lanes")
check(pile("armor") ~= nil and pile("armor").split == true,
	"the armor pile is not marked as one drawn in two lanes")
-- A pile of cloth and pigment has no binding to divide on, so a split there
-- would be a gap down the middle of it saying nothing.
check(pile("junk") ~= nil and pile("junk").split ~= true,
	"a pile that has nothing to do with binding was marked for a split")

----------------------------------------------------------------------
-- What the client said
----------------------------------------------------------------------

local weapon = pile("weapon")

local function held(name)
	if not weapon then
		return nil
	end
	for index = 1, #weapon.entries do
		if weapon.entries[index].name == name then
			return weapon.entries[index]
		end
	end
	return nil
end

check(held("Arcanite Reaper") ~= nil and held("Arcanite Reaper").bound == true,
	"the weapon the client called Soulbound was not read as bound")
check(held("Bloodspiller") ~= nil and held("Bloodspiller").bound == false,
	"the weapon with no binding line on it was read as bound anyway")

----------------------------------------------------------------------
-- Where they landed
--
-- The pixel rather than the order. The squares are a pool laid out pile by pile
-- in the order the scan hands them over, so the square for an entry is found by
-- counting to it the same way the layout did.
----------------------------------------------------------------------

local squares = Grid.Squares()

local function offset(name)
	local drawn = 0
	for index = 1, read.shown do
		local entries = read.groups[index].entries
		for at = 1, #entries do
			drawn = drawn + 1
			if read.groups[index] == weapon and entries[at].name == name then
				local _, _, _, x = squares[drawn]:GetPoint(1)
				return x
			end
		end
	end
	return nil
end

-- Half the columns of squares and gaps, and then half a square of air. That
-- last term is the whole of the split: without it the second lane is just the
-- sixth column and there is nothing to see.
local lane = math.ceil(ns.db.bagColumns / 2) * (ns.UI.SLOT + ns.UI.SLOT_GAP)
	+ ns.UI.SLOT_LANE

check(offset("Arcanite Reaper") == 0,
	("the bound weapon is %s pixels in and the left lane starts at nought")
		:format(tostring(offset("Arcanite Reaper"))))
check(offset("Bloodspiller") == lane,
	("the unbound weapon is %s pixels in and the right lane starts at %d")
		:format(tostring(offset("Bloodspiller")), lane))

----------------------------------------------------------------------
-- And the width that pays for it
--
-- Every pile spends the lane gap: a split pile in the middle, every other pile
-- as air at its right edge. That is what makes the two kinds of pile end in the
-- same place, and it is why the window is wider than its ten squares and nine
-- gaps come to.
----------------------------------------------------------------------

local window = Window.Frame()
local wide = ns.UI.Metric.pad * 2 + ns.UI.SlotSpan(ns.db.bagColumns)
	+ ns.UI.SLOT_LANE
check(window ~= nil and window.width == wide,
	("the window is %s wide and the squares, the gaps, a lane and the padding come to %d")
		:format(tostring(window and window.width), wide))

print(("lanes  %d weapons in two lanes, the bound one %s px in and the unbound one %s px in, in a window %d wide")
	:format(weapon and #weapon.entries or 0, tostring(offset("Arcanite Reaper")),
		tostring(offset("Bloodspiller")), wide))

-- Left shut, the way 55-bags.lua found it.
Window.Hide()
