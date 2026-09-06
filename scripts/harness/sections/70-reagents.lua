-- The reagent list
--
-- A page of notes with one job: to still be right when a corpse is in front of
-- you and no profession window is open. Everything worth asserting here is
-- about what a second walk does to what the first one wrote, because that is
-- the only part a reading of the file cannot settle.
--
-- Three of the checks are negative and they carry the weight. A window that
-- belongs to somebody else must leave the list alone; a burst of updates must
-- not be four walks; and a walk of one profession must not touch another
-- profession's ids, because a warrior who opens enchanting after mining would
-- otherwise be told his ore is no longer his.

local H = ...
local ns, check, advance = H.ns, H.check, H.advance
local shop = H.professions
local Reagents = ns.Reagents

-- The ids 20-tradeskill.lua's two fixtures name, by the profession that names
-- them. Written out rather than read off the fixture, so a stub that stopped
-- answering fails here instead of agreeing with itself.
local FORGE = { 7001, 7002, 7003, 7004 }
local DUST = { 7005, 7006 }

-- Read off the saved table rather than through Reagents.Skill, so the shape the
-- list is written in is asserted here and not only the reading of it.
local function owner(itemId)
	local entry = ns.dbc.lootReagents[itemId]
	return entry and entry.owner
end

-- Whether a recipe wanting this id can still gain a point.
local function point(itemId)
	local _, gains = Reagents.Skill(itemId)
	return gains
end

-- Every id in the list is filed under that profession, and the first one that
-- is not is named. Nil rather than a message when they all are.
local function wrong(ids, profession)
	for _, itemId in ipairs(ids) do
		if owner(itemId) ~= profession then
			return ("%d is filed under %s and should be %s")
				:format(itemId, tostring(owner(itemId)), profession)
		end
	end
	return nil
end

----------------------------------------------------------------------
-- A list written in the old shape
----------------------------------------------------------------------

-- An entry was the profession's name and is now that name and a difficulty. A
-- list from before the change is dropped on sight rather than read across,
-- because reading it across means inventing a difficulty for every id on it.
-- What proves it went is that it answers for nothing: the next profession
-- window writes it back.
ns.dbc.lootReagents = { [7001] = "Blacksmithing" }
check(not Reagents.Has(7001), "a list in the old shape was read as this one")
check(Reagents.Count() == 0,
	("the old list left %d ids behind"):format(Reagents.Count()))

----------------------------------------------------------------------
-- Nothing opened yet
----------------------------------------------------------------------

check(Reagents.Count() == 0,
	("the list carries %d ids before any profession window was opened")
		:format(Reagents.Count()))
check(Reagents.Describe() == "none scanned yet, open each profession once",
	"an empty list reads: " .. Reagents.Describe())
check(not Reagents.Has(7001), "an empty list says it holds Copper Bar")
check(Reagents.Skill(7001) == nil,
	"an empty list named a profession for Copper Bar")

----------------------------------------------------------------------
-- One window
----------------------------------------------------------------------

shop.open("Blacksmithing")
check(wrong(FORGE, "Blacksmithing") == nil,
	"opening blacksmithing: " .. tostring(wrong(FORGE, "Blacksmithing")))
check(Reagents.Count() == 4,
	("blacksmithing put %d ids on the list and its fixture names 4")
		:format(Reagents.Count()))
check(Reagents.Has(7003), "the list does not hold Silver Bar after the walk")

-- Every recipe in the fixture is orange until a check below makes one grey, so
-- the reading names the profession and says the point is there.
local named, gains = Reagents.Skill(7003)
check(named == "Blacksmithing" and gains == true,
	("Silver Bar reads %s, point %s"):format(tostring(named), tostring(gains)))
check(Reagents.Skill(7099) == nil,
	"an id no recipe wants came back with a profession")

-- The two category rows are skipped rather than read as recipes. A header has
-- no reagents at all, so a walk that read one would have asked for reagent
-- links off it and quietly found none, which is why this is asserted on the
-- count above rather than left to look after itself.
check(Reagents.Describe() == "4 reagents from Blacksmithing",
	"one profession reads: " .. Reagents.Describe())

----------------------------------------------------------------------
-- A second window joins the first
----------------------------------------------------------------------

shop.openCraft("Enchanting")
check(wrong(DUST, "Enchanting") == nil,
	"opening enchanting: " .. tostring(wrong(DUST, "Enchanting")))
check(wrong(FORGE, "Blacksmithing") == nil,
	"enchanting took blacksmithing's ids: " .. tostring(wrong(FORGE, "Blacksmithing")))
check(Reagents.Count() == 6,
	("two professions put %d ids on the list and their fixtures name 6")
		:format(Reagents.Count()))

local names = Reagents.Professions()
check(#names == 2 and names[1] == "Blacksmithing" and names[2] == "Enchanting",
	("the professions read %s"):format(table.concat(names, ", ")))
check(Reagents.Describe() == "6 reagents from Blacksmithing and Enchanting",
	"two professions read: " .. Reagents.Describe())

----------------------------------------------------------------------
-- A recipe you no longer know
----------------------------------------------------------------------

-- The breastplate goes, and with it the only recipe that wants silver or
-- coarse stone. Copper and rough stone are still wanted by the two recipes
-- above it, so this separates "the walk replaced the profession's entries"
-- from "the walk emptied the profession".
local recipes = shop.TRADE.Blacksmithing
local breastplate = table.remove(recipes)

advance(2)
shop.update()
check(owner(7003) == nil and owner(7004) == nil,
	("the dropped recipe left %s and %s on the list")
		:format(tostring(owner(7003)), tostring(owner(7004))))
check(owner(7001) == "Blacksmithing" and owner(7002) == "Blacksmithing",
	"the rescan took ids two recipes still want")
check(wrong(DUST, "Enchanting") == nil,
	"a blacksmithing rescan took enchanting's ids: " .. tostring(wrong(DUST, "Enchanting")))
check(Reagents.Count() == 4,
	("the list carries %d ids after the rescan and should carry 4")
		:format(Reagents.Count()))

----------------------------------------------------------------------
-- The throttle
----------------------------------------------------------------------

-- The window fires an update on every change it makes to itself, and a
-- profession with four hundred recipes is four hundred reagent counts and a
-- link for each. The recipe goes back and the update comes past inside the
-- second, so a list that has already changed is a walk that ran when it should
-- not have.
recipes[#recipes + 1] = breastplate
shop.update()
check(owner(7003) == nil,
	"an update inside the throttle walked the window again")

advance(2)
shop.update()
check(owner(7003) == "Blacksmithing", "the reagent throttle never released")

----------------------------------------------------------------------
-- A category folded up
----------------------------------------------------------------------

-- The client answers a shorter list rather than a list with holes in it, so a
-- walk of a half folded window sees half the recipes and cannot tell that from
-- half the recipes being gone. This part does not unfold the window, so what
-- has to hold instead is that a walk which could not see everything adds and
-- never takes away: a category you folded is not a reagent you stopped using.
local armor = recipes[4]
armor.expanded = false

advance(2)
shop.update()
check(owner(7003) == "Blacksmithing" and owner(7004) == "Blacksmithing",
	("a folded category took %s and %s off the list")
		:format(tostring(owner(7003)), tostring(owner(7004))))
check(Reagents.Count() == 6,
	("a folded category left %d ids where 6 were"):format(Reagents.Count()))

armor.expanded = true
advance(2)
shop.update()
check(Reagents.Count() == 6,
	("unfolding the category left %d ids where 6 were"):format(Reagents.Count()))

----------------------------------------------------------------------
-- Somebody else's profession
----------------------------------------------------------------------

-- A trade skill window opened from a link in chat is their recipe list, and
-- the profession name on it is theirs as well, so entries taken off one could
-- not be told from your own afterwards. The whole list goes away under a linked
-- window and the addon must still be holding what it had.
shop.link(true)
local held = {}
for index = #recipes, 1, -1 do
	held[#held + 1] = table.remove(recipes, index)
end

advance(2)
shop.update()
check(Reagents.Count() == 6,
	("a linked window took the list down to %d"):format(Reagents.Count()))
check(wrong(FORGE, "Blacksmithing") == nil,
	"a linked window rewrote your own list: " .. tostring(wrong(FORGE, "Blacksmithing")))

for index = #held, 1, -1 do
	recipes[#recipes + 1] = held[index]
end
shop.link(false)

----------------------------------------------------------------------
-- A recipe with nothing left to teach
----------------------------------------------------------------------

-- The sharpening stone and the breastplate go grey. Rough stone is wanted by
-- the sharpening stone and by nothing else, so it stops being worth a point;
-- silver and coarse stone are the breastplate's alone and go with it. Copper
-- bar is the one that matters: the grey breastplate wants it and so does the
-- orange belt, and one orange recipe is a point still there however many grey
-- ones sit beside it.
recipes[2].kind = "trivial"
recipes[5].kind = "trivial"

advance(2)
shop.update()
check(point(7001) == true,
	"a grey recipe took Copper Bar's point off an orange one")
check(point(7002) == false and point(7003) == false and point(7004) == false,
	("the grey recipes read %s, %s and %s"):format(tostring(point(7002)),
		tostring(point(7003)), tostring(point(7004))))

-- Still on the list, still blacksmithing's, and still kept by the loot filter.
-- What the difficulty changes is the reason a feed can give for an item, not
-- whether the addon knows the item is a reagent.
check(Reagents.Has(7002) and owner(7002) == "Blacksmithing",
	"a grey recipe took its reagent off the list")
check(Reagents.Count() == 6,
	("the grey recipes left %d ids where 6 were"):format(Reagents.Count()))

-- A window nobody walked again still says what it said, which is the half of
-- this that is saved rather than worked out on the spot.
check(point(7005) == true and point(7006) == true,
	"the blacksmithing walk changed enchanting's answer")

recipes[2].kind = nil
recipes[5].kind = nil

print(("reagents %s, over two windows; a recipe dropped took its ids and left"
	.. " the rest, a window that was somebody else's took nothing, and a grey"
	.. " recipe kept its reagent and lost its point")
	:format(Reagents.Describe()))

----------------------------------------------------------------------
-- Emptying it
----------------------------------------------------------------------

check(Reagents.Clear() == 6,
	"clearing a list of six did not say six went")
check(Reagents.Count() == 0,
	("%d ids survived the clear"):format(Reagents.Count()))
check(Reagents.Describe() == "none scanned yet, open each profession once",
	"a cleared list reads: " .. Reagents.Describe())

shop.close()
shop.closeCraft()
