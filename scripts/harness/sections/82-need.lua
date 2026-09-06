-- Why an item matters to you
--
-- ns.Need is one answer that three parts are going to draw, and the reason it
-- is one function rather than three readings is the order. A wolf liver that is
-- also a blacksmithing reagent and is also something the loot filter would have
-- left is all three at once, and the whole value of the call is that every
-- caller ranks it the same way.
--
-- So the fixture is built round one item that qualifies twice, and everything
-- else here is a negative: an objective already finished, a reagent whose only
-- recipe has gone grey, an item with no reason at all, and that item again with
-- no loot slot to ask about. Those four are what stops the answer being "yes"
-- to everything, which is the failure a feed cannot recover from: a column
-- where every row is marked is a column with no marks on it.
--
-- The cache is read by changing a fixture and not saying so. An answer that
-- moved with no event behind it is a cache that was never built, and an answer
-- that did not move after the event is a cache nothing empties.

local H = ...
local ns, check, fire, advance = H.ns, H.check, H.fire, H.advance
local shop, loot, ITEMS, link = H.professions, H.loot, H.ITEMS, H.itemLink
local quests = H.quests

-- Four items this section owns, at ids nothing else in the suite uses. The
-- classes are the client's own: three trade goods, which is what a reagent is,
-- and one miscellaneous grey, which is what a corpse is mostly made of.
ITEMS["Wolf Liver"] = { id = 8301, classId = 7, subClassId = 8, quality = 1,
	price = 12, icon = "Interface\\Icons\\Liver" }
ITEMS["Sinew Thread"] = { id = 8302, classId = 7, subClassId = 6, quality = 1,
	price = 8, icon = "Interface\\Icons\\Thread" }
ITEMS["Boar Bristle"] = { id = 8303, classId = 7, subClassId = 5, quality = 1,
	price = 6, icon = "Interface\\Icons\\Bristle" }
ITEMS["Cracked Fang"] = { id = 8304, classId = 15, subClassId = 0, quality = 0,
	price = 2, icon = "Interface\\Icons\\Fang" }

-- Two objectives onto a quest already in the log. The liver is the one that
-- counts and the bristle is the one that has stopped: 6 of 6 is a line you have
-- finished, and an item you need no more of is not a reason to keep it.
local OBJECTIVES = quests.text[202].objectives
local COUNTING = { "Wolf Liver: 4/8", "item", false }
local FINISHED = { "Boar Bristle: 6/6", "item", true }
OBJECTIVES[#OBJECTIVES + 1] = COUNTING
OBJECTIVES[#OBJECTIVES + 1] = FINISHED

-- Two recipes onto the blacksmithing window. The girdle wants the liver and the
-- thread and can still teach you something; the brush wants the bristle and has
-- nothing left to teach, which is what takes the bristle's reason away without
-- taking it off the reagent list.
local RECIPES = shop.TRADE.Blacksmithing
local GIRDLE = { name = "Wolfhide Girdle", reagents = { "Wolf Liver", "Sinew Thread" } }
local BRUSH = { name = "Bristle Brush", reagents = { "Boar Bristle" }, kind = "trivial" }
RECIPES[#RECIPES + 1] = GIRDLE
RECIPES[#RECIPES + 1] = BRUSH

-- A corpse of three, the third of which nothing in the addon has a use for.
local SLOTS = {
	{ quality = 1, item = "Wolf Liver" },
	{ quality = 1, item = "Sinew Thread" },
	{ quality = 0, item = "Cracked Fang" },
}
local FANG = 3

-- One answer in the words a person would use, for a check that failed to say
-- with. Read through the same call rather than off the values already taken,
-- because a second ask is the cached path and a message that came off the cache
-- is a message about the answer the check saw.
local function read(name, slot)
	local reason, phrase = ns.Need(link(name), slot)
	if not reason then
		return "nothing"
	end
	return reason .. (phrase and (" " .. phrase) or "")
end

----------------------------------------------------------------------
-- The fixture stood up
----------------------------------------------------------------------

-- Every rule of the loot filter off but the switch. What is being asked of it
-- here is the last answer it has, which is "no", and a floor or a kind rule
-- left on from the section above would answer for the fang before the question
-- got that far.
ns.dbc.lootFilter = true
ns.dbc.lootFloor = 5
ns.dbc.lootWorth = 0
ns.dbc.lootCrafted = true
for _, key in ipairs({ "lootCloth", "lootLeather", "lootOre", "lootMeat",
	"lootHerbs", "lootEnchanting", "lootGems" }) do
	ns.dbc[key] = false
end

loot.Set(SLOTS)

-- The window walked, which is what puts the three reagents on the list, and the
-- log read, which is what fills the objective map. Past the reagent walk's one
-- second throttle first, because a section above this one opened a window.
advance(2)
shop.open("Blacksmithing")
fire("QUEST_LOG_UPDATE")

check(ns.Reagents.Skill(8301) == "Blacksmithing",
	"the girdle did not put the wolf liver on the reagent list")

----------------------------------------------------------------------
-- Nothing, which is most items
----------------------------------------------------------------------

-- The commonest answer and the one that has to be cheap. No quest counts a
-- cracked fang, no profession wants one, and with no slot named there is no
-- corpse to ask the filter about.
do
	local reason, phrase, tone = ns.Need(link("Cracked Fang"))
	check(reason == nil and phrase == nil and tone == nil,
		"a fang nobody wants reads " .. read("Cracked Fang"))
end

-- An item the client will not identify at all. A link with no id behind it is
-- not an item with no reason, it is a question that cannot be asked, and both
-- come back the same way on purpose: nothing drawn is the safe answer and a
-- guess on a broken link is not.
check(ns.Need(nil) == nil, "a nil link was given a reason")
check(ns.Need("not a link") == nil, "a string that is not a link was given a reason")

----------------------------------------------------------------------
-- A quest is counting it
----------------------------------------------------------------------

-- The phrase is the two numbers off the client's own sentence and nothing else,
-- because the column it goes in takes its width off the name beside it.
do
	local reason, phrase, tone = ns.Need(link("Wolf Liver"))
	check(reason == "quest", "the wolf liver reads " .. read("Wolf Liver"))
	check(phrase == "4/8", "the wolf liver's phrase is " .. tostring(phrase))
	check(tone == ns.UI.Color.quest,
		"the quest answer was not drawn in the palette's quest colour")
	-- The same fact spelled for a line rather than for a column. The slash is
	-- what makes a count fit 48 units and the one thing a sentence has no use
	-- for, and a tooltip building it out of the phrase would be the spelling
	-- kept in the one place that cannot cache it.
	check(select(4, ns.Need(link("Wolf Liver"))) == "4 of 8",
		"the wolf liver's sentence is "
			.. tostring(select(4, ns.Need(link("Wolf Liver")))))
end

-- The order, which is the whole reason this is one function. The liver is a
-- blacksmithing reagent as well and the girdle can still gain a point off it,
-- so both sources answer and the quest is the one that wins. A caller that
-- ranked them the other way round would tell you to keep eight of something for
-- a profession when your log is counting them.
do
	local profession, point = ns.Reagents.Skill(8301)
	check(profession == "Blacksmithing" and point == true,
		"the wolf liver stopped being a reagent worth a point")
	check(ns.Need(link("Wolf Liver")) == "quest",
		"a reagent beat a quest objective on the same item")
end

-- An objective you have finished is not a reason. 6 of 6 is a line that wants
-- no more of the thing, and the bristle's only other claim is a recipe with
-- nothing left to teach.
do
	local reason = ns.Need(link("Boar Bristle"))
	check(reason == nil, "a finished objective reads " .. read("Boar Bristle"))
end

----------------------------------------------------------------------
-- A profession still wants it
----------------------------------------------------------------------

-- The profession's name is the sentence and not the phrase, and the difference
-- is a measurement. "Blacksmithing" is 93 units in the shipped face at a row's
-- text size and "Leatherworking" is 104, against a loot row's column that is 48
-- units and is never handed more than 81. There is no width at which a row can
-- draw one, so a reagent answers a colour for the row and a word for the line,
-- which is the shape trash has had since this file was written.
do
	local reason, phrase, tone, said = ns.Need(link("Sinew Thread"))
	check(reason == "skill", "the sinew thread reads " .. read("Sinew Thread"))
	check(phrase == nil,
		"the skill answer carried the phrase " .. tostring(phrase))
	check(said == "Blacksmithing",
		"the sinew thread's sentence is " .. tostring(said))
	check(tone == ns.UI.Color.skill,
		"the skill answer was not drawn in the palette's skill colour")
end

-- A reagent with no point left in it is not a reason. The bristle is still on
-- the list, still blacksmithing's and still kept by the loot filter; what it
-- has stopped being is something worth telling you about, which is the whole
-- difference between Reagents.Has and Reagents.Skill.
do
	local profession, point = ns.Reagents.Skill(8303)
	check(profession == "Blacksmithing" and point == false,
		"the bristle brush did not go grey")
	check(ns.Reagents.Has(8303), "a grey recipe took its reagent off the list")
	check(ns.Need(link("Boar Bristle")) == nil,
		"a reagent with no point left reads " .. read("Boar Bristle"))
end

----------------------------------------------------------------------
-- The filter would have left it
----------------------------------------------------------------------

-- Last of the three and quiet, because it is the commonest answer of them and
-- the one nobody is looking for. It carries no phrase at all: a column of grey
-- rows each captioned in words is the feed back where it started.
do
	local reason, phrase, tone = ns.Need(link("Cracked Fang"), FANG)
	check(reason == "trash", "the fang on the corpse reads " .. read("Cracked Fang", FANG))
	check(phrase == nil, "the trash answer carried the phrase " .. tostring(phrase))
	check(select(4, ns.Need(link("Cracked Fang"), FANG)) == nil,
		"the trash answer carried a sentence")
	check(tone == ns.UI.Color.trash,
		"the trash answer was not drawn in the palette's trash colour")
end

-- The same item with no slot named, which is what a bag square can offer. There
-- is no corpse to ask about, so there is no answer, and this is the one source
-- of the three that a caller without a slot cannot have.
check(ns.Need(link("Cracked Fang")) == nil,
	"a fang with no loot slot behind it reads " .. read("Cracked Fang"))

-- The filter switched off answers "keep everything", so nothing is trash. That
-- is Wanted.Take's own answer rather than this file's, and it is here because
-- it is the state most of the addon's users are in.
ns.dbc.lootFilter = false
check(ns.Need(link("Cracked Fang"), FANG) == nil,
	"the filter switched off still called the fang trash")
ns.dbc.lootFilter = true

-- A slot the filter takes is not trash either, and this is the half that has to
-- go through Take rather than round it. The fang sells for two copper, a price
-- floor of one copper takes it, and the mark goes away with no other rule
-- touched.
ns.dbc.lootWorth = 1
check(ns.Need(link("Cracked Fang"), FANG) == nil,
	"the filter kept the fang and it was still marked: " .. read("Cracked Fang", FANG))
ns.dbc.lootWorth = 0

----------------------------------------------------------------------
-- The cache
----------------------------------------------------------------------

-- The quest log moved and nothing said so, which is the state a walk per drop
-- exists to avoid paying for. The answer must be the one it worked out before.
COUNTING[1] = "Wolf Liver: 7/8"
check(select(2, ns.Need(link("Wolf Liver"))) == "4/8",
	"the log was read again per item: the liver already reads "
		.. read("Wolf Liver"))

-- And the event empties it. QUEST_LOG_UPDATE is the client saying a count moved,
-- which is exactly the fact the phrase is made of.
fire("QUEST_LOG_UPDATE")
check(select(2, ns.Need(link("Wolf Liver"))) == "7/8",
	"the quest log's event left a stale phrase: " .. read("Wolf Liver"))

-- SKILL_LINES_CHANGED empties the whole of it and not only the skill half. A
-- point gained is what turns a recipe grey, and the cache holds one answer per
-- item rather than one per source, so there is nothing finer to throw away.
COUNTING[1] = "Wolf Liver: 8/8"
fire("SKILL_LINES_CHANGED")
check(ns.Need(link("Wolf Liver")) == "skill",
	"a point gained left the liver reading " .. read("Wolf Liver"))

-- The objective is finished now, so the liver falls through to the reagent
-- list, which is the source under it. Put the count back and it is a quest
-- again, which is the same fall the other way round.
COUNTING[1] = "Wolf Liver: 4/8"
fire("QUEST_LOG_UPDATE")
check(ns.Need(link("Wolf Liver")) == "quest",
	"the liver did not come back to its objective: " .. read("Wolf Liver"))

-- The trade window is the third event and it is the one that rewrites the list
-- under us. The girdle goes grey, the walk writes the thread down with nothing
-- left to teach, and the same update is what empties the cache holding the
-- answer from before it.
GIRDLE.kind = "trivial"
advance(2)
shop.update()
check(ns.Need(link("Sinew Thread")) == nil,
	"a recipe gone grey left the thread reading " .. read("Sinew Thread"))
check(ns.Need(link("Wolf Liver")) == "quest",
	"the liver lost its objective with its recipe: " .. read("Wolf Liver"))

print(("need   over a corpse of %d, the liver reads %s and the fang reads %s;"
	.. " a quest beats a reagent on the same item, a finished objective and a"
	.. " grey recipe are not reasons, and the log is walked once per change to"
	.. " it rather than once per drop")
	:format(#SLOTS, read("Wolf Liver"), read("Cracked Fang", FANG)))

----------------------------------------------------------------------
-- Handed back
----------------------------------------------------------------------

GIRDLE.kind = nil
RECIPES[#RECIPES] = nil
RECIPES[#RECIPES] = nil
OBJECTIVES[#OBJECTIVES] = nil
OBJECTIVES[#OBJECTIVES] = nil
ns.Reagents.Clear()
shop.close()
loot.Reset()
advance(2)
fire("QUEST_LOG_UPDATE")
