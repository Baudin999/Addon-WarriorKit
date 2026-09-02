-- The sub-piles and the quest lanes
--
-- Three claims. A pile the client files too much under is cut at the subclass,
-- one sub-pile per subclass under the client's own word for it, and the items
-- in one run by their level. The quest pile is drawn in two lanes on a fact
-- that is not the binding: what a quest in your log wants on the left, in the
-- order the log lists the quests, and what nothing in your log wants on the
-- right. And a session with no Questie in it gets the quest pile in one lane,
-- because "cannot say" is never a suggestion to throw something away.
--
-- Its own section rather than part of 62-bag-lanes.lua because the subject is
-- not the same. That file asks where a square landed when the pile splits on
-- the tooltip; this one asks what the rows are, which is the one thing about
-- the window that used to be exactly the pile list and is not any more.
--
-- **The fifth bag.** Every scene before this one is written against the four
-- bags 55-bags.lua describes, and the piles those hold are each one subclass
-- wide, which is the case where nothing here is reachable. So a fifth bag is
-- stood up with two kinds of cloth, an ore, two totems, a pet and one more
-- quest item, and taken down again at the end.

local H = ...
local ns, check = H.ns, H.check
local CARRIED, refill, refillQuests = H.CARRIED, H.refill, H.refillQuests

local Bags, Grid, Window = ns.Bags, ns.BagsGrid, ns.BagsWindow

----------------------------------------------------------------------
-- The scene
----------------------------------------------------------------------

refill()
refillQuests()
CARRIED[3] = { false, false, false }
-- Silk before wool and air before earth, on purpose: the bag order is the
-- wrong order for every claim below, so a pile that kept it fails.
CARRIED[4] = {
	"Silk Cloth", "Tin Ore", "Wool Cloth",
	"Air Totem", "Snake Basket", "Earth Totem",
	"Trapper's Rope",
}

Window.Show()
local read = Bags.Read()
Window.Refresh()

-- Every row with this key, in the order they came out.
local function rows(key)
	local found = {}
	for index = 1, read.shown do
		if read.groups[index].key == key then
			found[#found + 1] = read.groups[index]
		end
	end
	return found
end

local function names(row)
	local held = {}
	for index = 1, #row.entries do
		held[index] = row.entries[index].name or "?"
	end
	return table.concat(held, ", ")
end

----------------------------------------------------------------------
-- The cut
----------------------------------------------------------------------

local trade = rows("trade")
check(#trade == 4,
	("the trade goods came out as %d rows and three subclasses cut to a heading and three")
		:format(#trade))
check(trade[1] and not trade[1].under and #trade[1].entries == 0,
	"the first trade row is not the pile's own heading with nothing under it")
check(trade[1] and trade[1].name == "Trade Goods",
	("the trade heading reads %q"):format(tostring(trade[1] and trade[1].name)))
check(trade[2] and trade[2].under and trade[2].name == "Cloth",
	("the second trade row is %q and it is the cloth"):format(tostring(trade[2] and trade[2].name)))
check(trade[3] and trade[3].under and trade[3].name == "Metal & Stone",
	("the third trade row is %q and it is the ore"):format(tostring(trade[3] and trade[3].name)))

-- Wool is fifteen and silk is twenty five, and the bag holds them the other
-- way round.
check(trade[2] and names(trade[2]) == "Wool Cloth, Silk Cloth",
	("the cloth runs %s and it runs by level"):format(trade[2] and names(trade[2]) or "?"))
check(trade[3] and names(trade[3]) == "Tin Ore",
	("the ore runs %s"):format(trade[3] and names(trade[3]) or "?"))
-- Emerald Pigment is the trade good every earlier scene carries and it has no
-- subclass, which no item on the real client lacks. It is the sub-pile of
-- things the client did not file further: last, under the pile's own word.
check(trade[4] and trade[4].under and trade[4].name == "Trade Goods"
		and names(trade[4]) == "Emerald Pigment",
	("the fourth trade row is %q holding %s"):format(tostring(trade[4] and trade[4].name),
		trade[4] and names(trade[4]) or "?"))

local misc = rows("misc")
check(#misc == 3,
	("the miscellany came out as %d rows and two subclasses cut to three"):format(#misc))
check(misc[2] and misc[2].name == "Reagent" and names(misc[2]) == "Earth Totem, Air Totem",
	("the totems are under %q as %s, and they are Reagent, earth before air")
		:format(tostring(misc[2] and misc[2].name), misc[2] and names(misc[2]) or "?"))
check(misc[3] and misc[3].name == "Pet" and names(misc[3]) == "Snake Basket",
	("the pet is under %q as %s"):format(tostring(misc[3] and misc[3].name),
		misc[3] and names(misc[3]) or "?"))

-- The one trade good the earlier scenes carry is the only trade good they
-- carry, so their pile is one subclass wide and must come out as it always
-- did: one row, under its own heading, with the squares in it. That is the
-- shape 55-bags.lua measures the window's height against.
local junk = rows("junk")
check(#junk == 1 and not junk[1].under and #junk[1].entries == 3,
	"a pile that is not cut came out as more than one row")

----------------------------------------------------------------------
-- The quest lanes
----------------------------------------------------------------------

local quest = rows("quest")
check(#quest == 1 and quest[1].split == true,
	"the quest pile is not one row marked as drawn in two lanes")

local function entry(name)
	for index = 1, #quest[1].entries do
		if quest[1].entries[index].name == name then
			return quest[1].entries[index], index
		end
	end
	return nil
end

-- The diplomat's quest is the second row of the log and the brotherhood is
-- the fifth, under the Westfall header, so the ring sits before the rope
-- whatever bag either is in. The letter starts a quest you have not done:
-- kept, and after everything you are on. Everything else is tied to a quest
-- that is behind you or one you have not taken, and is the right lane.
local ring, rope, letter = entry("Diplomat's Ring"), entry("Trapper's Rope"), entry("Sealed Letter")
check(ring and ring.yours == true and ring.rank == 2,
	("the ring a quest in your log wants reads yours=%s rank=%s")
		:format(tostring(ring and ring.yours), tostring(ring and ring.rank)))
check(rope and rope.yours == true and rope.rank == 5,
	("the rope a lower quest wants reads yours=%s rank=%s")
		:format(tostring(rope and rope.yours), tostring(rope and rope.rank)))
check(letter and letter.yours == true and letter.rank == math.huge,
	("the letter that starts a quest you have not done reads yours=%s rank=%s")
		:format(tostring(letter and letter.yours), tostring(letter and letter.rank)))

local kept = "Diplomat's Ring, Trapper's Rope, Sealed Letter, "
check(names(quest[1]):sub(1, #kept) == kept,
	("the quest pile runs %s and the log's order comes first"):format(names(quest[1])))

for _, name in ipairs({ "Hogger's Claw", "Zul'Mamwe Fetish", "Rogue's Token", "Old Cipher" }) do
	local held = entry(name)
	check(held and held.yours == false and held.rank == nil,
		("%s is tied to nothing in your log and reads yours=%s rank=%s")
			:format(name, tostring(held and held.yours), tostring(held and held.rank)))
end

-- The trinket Questie has no row for. Not "no quest wants it": the database
-- cannot say, and cannot say is kept.
local trinket = entry("Unknown Trinket")
check(trinket and trinket.yours == true and trinket.rank == nil,
	("the item Questie has never heard of reads yours=%s and it has to be kept")
		:format(tostring(trinket and trinket.yours)))

-- Counted before the no-Questie pass below reads the same state table over.
local mine = 0
for index = 1, #quest[1].entries do
	if quest[1].entries[index].yours then
		mine = mine + 1
	end
end

----------------------------------------------------------------------
-- Where they landed
--
-- The pixel, the way 62-bag-lanes.lua reads it: the square for an entry is
-- found by counting to it the way the layout did.
----------------------------------------------------------------------

local squares = Grid.Squares()

local function offset(row, name)
	local drawn = 0
	for index = 1, read.shown do
		local entries = read.groups[index].entries
		for at = 1, #entries do
			drawn = drawn + 1
			if read.groups[index] == row and entries[at].name == name then
				local _, _, _, x, y = squares[drawn]:GetPoint(1)
				return x, y
			end
		end
	end
	return nil
end

local canvas = squares[1]:GetParent()
local gap = ns.UI.Round(canvas, ns.UI.SLOT_LANE)
local lane = ns.UI.Round(canvas,
	math.ceil(ns.db.bagColumns / 2) * (ns.UI.SLOT + ns.UI.SLOT_GAP) + gap)

check(offset(quest[1], "Diplomat's Ring") == 0,
	("the ring is %s units in and the left lane starts at nought")
		:format(tostring(offset(quest[1], "Diplomat's Ring"))))
check(offset(quest[1], "Hogger's Claw") == lane,
	("the claw is %s units in and the right lane starts at %.3f")
		:format(tostring(offset(quest[1], "Hogger's Claw")), lane))

----------------------------------------------------------------------
-- The captions
----------------------------------------------------------------------

local headers, subs = Grid.Headers(), Grid.Subs()

local function caption(pool, text)
	for index = 1, #pool do
		if pool[index]:IsShown() and pool[index]:GetText() == text then
			return pool[index]
		end
	end
	return nil
end

check(caption(headers, "Trade Goods") ~= nil, "no heading reads Trade Goods")
check(caption(subs, "Cloth") ~= nil and caption(subs, "Metal & Stone") ~= nil,
	"the two trade sub-captions were not both drawn")
check(caption(subs, "Reagent") ~= nil and caption(subs, "Pet") ~= nil,
	"the two miscellany sub-captions were not both drawn")
check(caption(headers, "Cloth") == nil,
	"a sub-caption was drawn in the heading pool")

-- The sub-caption sits on the same line as the heading, to its right, and
-- dropped so that its squares start where every other block's do: one
-- heading line under the top of the line. The cloth is beside the words
-- "Trade Goods" rather than under them, because a heading with nothing under
-- it on a line of its own was the column this window used to be.
do
	local heading, cloth = caption(headers, "Trade Goods"), caption(subs, "Cloth")
	local _, _, _, hx, hy = heading:GetPoint(1)
	local _, _, _, cx, cy = cloth:GetPoint(1)
	check(cx > hx, ("the cloth caption is at %.2f and the trade heading at %.2f, so it is not beside it")
		:format(cx, hx))
	check(math.abs((hy - cy) - (ns.UI.SLOT_HEADER - ns.UI.SLOT_SUBHEADER)) < 0.001,
		("the cloth caption is %.2f under the trade heading and the drop is %d")
			:format(hy - cy, ns.UI.SLOT_HEADER - ns.UI.SLOT_SUBHEADER))
	-- Snapped as a whole rather than as a distance, because the grid snaps
	-- every origin to the pixel it is nearest and the heading is not on one.
	local wx, wy = offset(trade[2], "Wool Cloth")
	local under = ns.UI.Round(canvas, -hy + ns.UI.SLOT_HEADER)
	check(-wy == under,
		("the first cloth square is %.2f down and the heading line ends at %.2f")
			:format(-wy, under))
	check(wx == cx, ("the first cloth square is %.2f in and its caption %.2f"):format(wx, cx))
end

----------------------------------------------------------------------
-- The height
--
-- 55-bags.lua's reading, with the sub-captions in it: the body is the lowest
-- edge of anything drawn plus the padding, within the unit the pixel snap
-- moves a square by.
----------------------------------------------------------------------

do
	local window = Window.Frame()
	local bottom = H.carry.bagBottom()
	check(window and math.abs(window:Body() - (bottom + ns.UI.Metric.pad * 2)) < 1,
		("the window's body is %d and what it draws comes to %.2f")
			:format(window and window:Body() or -1, bottom + ns.UI.Metric.pad * 2))
end

----------------------------------------------------------------------
-- No Questie
--
-- The quest pile in one lane: everything yours, nothing ranked, and the
-- window still up. The loader is taken away rather than the database, because
-- the loader is what ns.Questie probes, and put back the same way.
----------------------------------------------------------------------

do
	local loader = _G.QuestieLoader
	_G.QuestieLoader = nil
	local blind = Bags.Read()
	Window.Refresh()
	local pile
	for index = 1, blind.shown do
		if blind.groups[index].key == "quest" then
			pile = blind.groups[index]
		end
	end
	local kept, ranked = 0, 0
	for index = 1, pile and #pile.entries or 0 do
		if pile.entries[index].yours then
			kept = kept + 1
		end
		if pile.entries[index].rank ~= nil then
			ranked = ranked + 1
		end
	end
	check(pile and kept == #pile.entries and ranked == 0,
		("with no Questie %d of %d quest items are kept and %d are ranked; all and none")
			:format(kept, pile and #pile.entries or 0, ranked))
	local strayed = 0
	for index = 1, pile and #pile.entries or 0 do
		if offset(pile, pile.entries[index].name) >= lane then
			strayed = strayed + 1
		end
	end
	check(strayed == 0,
		("with no Questie %d quest items were still drawn in the right lane"):format(strayed))
	_G.QuestieLoader = loader
end

print(("piles  %d trade rows, %d misc rows, the quest pile in two lanes of %d and %d")
	:format(#trade, #misc, mine, #quest[1].entries - mine))

-- The fifth bag down and the window shut, the way 55-bags.lua found them.
CARRIED[4] = nil
Window.Hide()
