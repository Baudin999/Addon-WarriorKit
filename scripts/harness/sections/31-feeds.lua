-- The feeds
--
-- Five questions no amount of reading Feeds/ will answer.
--
-- Does a loot sentence come apart the right way. The client hands over a
-- localised format string and the addon turns it into a pattern, and the one
-- way that goes wrong is invisible in the source: "You receive loot: %s."
-- matches the counted sentence as well, so a table that tries it first reads
-- every stack of eight as one item whose name ends in "x8". Both forms are in
-- the stub for exactly this.
--
-- Is the newest entry at the top, and does it stay there. A feed is a ring with
-- an offset into it and there are two ways to get that backwards, drawing the
-- list upside down and scrolling it the wrong way, and both look plausible in
-- the code.
--
-- Does an arrival move what you are reading. Scrolled back into history, a drop
-- has to push the list down under the offset rather than under your eyes. This
-- is the defect that would make the scrollback useless and it cannot be seen in
-- a screenshot, because a screenshot of a feed that jumped and one that did not
-- are the same picture taken at different moments.
--
-- Does the ring actually reuse its tables. The claim in UI/Feed.lua is that a
-- feed in its steady state allocates nothing at all, and the only way to state
-- that as a test rather than as a measurement is by identity: the four hundred
-- and first drop has to land in the table the first one used.
--
-- And does a row answer the mouse with the addon's own tooltip, anchored to the
-- row that was hovered rather than to whichever one was hovered last.

local H = ...
local guids, slots, logArgs = H.guids, H.slots, H.logArgs
local ns, fire, check = H.ns, H.fire, H.check

local Loot, Combat = ns.LootFeed, ns.CombatFeed
local lootStream, combatStream = Loot.Stream(), Combat.Stream()
local feed = lootStream:Feed()

check(_G.WarriorKitLootFeed ~= nil, "no loot feed was built at login")
check(_G.WarriorKitCombatFeed ~= nil, "no combat feed was built at login")
check(_G.WarriorKitLootFeed:GetWidth() == ns.db.lootFeedWidth,
	("the loot feed is %s wide and the setting says %s")
		:format(tostring(_G.WarriorKitLootFeed:GetWidth()), tostring(ns.db.lootFeedWidth)))

-- Every row the setting asks for is built and placed, and the ones past it
-- are not drawn. A pool sized to the setting rather than to its ceiling
-- would leak a column of frames every time the stepper moved, which is the
-- leak Meter/Window.lua's row pool exists to avoid and is invisible in game.
check(feed:Row(ns.db.lootFeedRows) ~= nil,
	"the feed has fewer rows than the setting asks for")
check(not feed:Row(ns.db.lootFeedRows + 1):IsShown(),
	"a row past the setting is drawn")

----------------------------------------------------------------------
-- Taking a sentence apart
----------------------------------------------------------------------

local function drop(format, ...)
	fire("CHAT_MSG_LOOT", (format):format(...))
end

local function newest()
	return feed:At(0) or {}
end

local live, total = Loot.Rules()
check(live == 10 and total == 12,
	("%d of %d loot sentences read off this client, expected 10 of 12")
		:format(live, total))

drop("You receive loot: %s.", _G.WarriorKitItemLink("Aegis"))
check(feed:Count() == 1, ("one drop and the feed holds %d"):format(feed:Count()))
check(newest().name == "Aegis",
	"a single drop did not come back as the item: " .. tostring(newest().name))
check(newest().count == 1, "a single drop did not read as one")
check(newest().amount == "x1", "a single drop drew no count")

-- The whole reason RULES is ordered. A table that tried the uncounted
-- sentence first reads this as one item called "Tattered Clothx8".
drop("You receive loot: %sx8.", _G.WarriorKitItemLink("Tattered Cloth"))
check(newest().count == 8, ("a stack of eight read as %s"):format(tostring(newest().count)))
check(newest().name == "Tattered Cloth",
	"the count was swallowed into the name: " .. tostring(newest().name))

-- A sentence that is not loot, and one that matches the shape while
-- carrying no item link in it. Neither may become a row.
local held, drawn = feed:Count(), feed:Shown()
fire("CHAT_MSG_LOOT", "You receive loot: a rumour.")
fire("CHAT_MSG_LOOT", "Ragnaros says something about firelands.")
check(feed:Count() == held, "a sentence with no item link in it became a row")

----------------------------------------------------------------------
-- Quality
--
-- The colour is compared by identity rather than by its numbers, because
-- that is what every guard in UI/Feed.lua compares and a palette rebuilt
-- per row would repaint a colour that had not changed on every arrival.
----------------------------------------------------------------------

drop("You receive loot: %s.", _G.WarriorKitItemLink("Bloodspiller"))
local rare = newest().color
drop("You receive loot: %s.", _G.WarriorKitItemLink("Aegis"))
check(newest().color == rare, "two rares came back with different colour tables")
drop("You receive loot: %s.", _G.WarriorKitItemLink("Chipped Boar Tusk"))
check(newest().color ~= rare, "a grey and a rare came back the same colour")

----------------------------------------------------------------------
-- Whose drop it was
----------------------------------------------------------------------

ns.db.lootFeedGroup = false
held = feed:Count()
drop("%s receives loot: %s.", "Bram", _G.WarriorKitItemLink("Aegis"))
check(feed:Count() == held, "the group's loot was captured with the setting off")

ns.db.lootFeedGroup = true
drop("%s receives loot: %sx3.", "Bram", _G.WarriorKitItemLink("Emerald Pigment"))
check(feed:Count() == held + 1, "the group's loot was refused with the setting on")
check(newest().who == "Bram",
	"a group drop did not record who got it: " .. tostring(newest().who))
check(newest().count == 3, "a counted group drop lost its stack size")
ns.db.lootFeedGroup = false

----------------------------------------------------------------------
-- Coin
----------------------------------------------------------------------

fire("CHAT_MSG_MONEY", "You loot 12 Silver, 39 Copper")
check(newest().money, "coin did not reach the feed")
check(newest().name == "12 Silver, 39 Copper",
	"the coin phrase did not survive the sentence around it: " .. tostring(newest().name))

-- Coin is recorded whatever its chip says, the same as everything else. What
-- the chip decides is whether it gets a row, and the purse along the bottom
-- has the number either way.
ns.db.lootFeedMoney = false
feed:Chipped()
held, drawn = feed:Count(), feed:Shown()
fire("CHAT_MSG_MONEY", "You loot 4 Copper")
check(feed:Count() == held + 1, "coin did not reach the ring with its chip off")
check(feed:Shown() == drawn, "coin got a row with its chip off")
ns.db.lootFeedMoney = true
feed:Chipped()
check(feed:Shown() == drawn + 2, "turning the coin chip back on did not bring both coin rows back")

----------------------------------------------------------------------
-- Which way it reads, and scrolling back
----------------------------------------------------------------------

feed:Clear()
check(feed:Count() == 0, "clearing the feed left entries in it")
check(feed:Live(), "a cleared feed did not go back to the top")

for index = 1, ns.db.lootFeedRows + 6 do
	drop("You receive item: %sx%d.", _G.WarriorKitItemLink("Aegis"), index)
end

-- The newest is the top row and the one before it is the second, which is
-- the whole of "it scrolls top to bottom" stated as two comparisons.
check(feed:Row(1).amount:GetText() == newest().amount,
	"the newest entry is not the top row")
check(feed:Row(2).amount:GetText() == feed:At(1).amount,
	"the second row is not the entry before the newest")
check(feed:Row(1).amount:GetText() ~= feed:Row(2).amount:GetText(),
	"two rows are drawing the same entry")

check(feed:Live(), "the feed was not at the top after an arrival")
check(feed:Scroll(3), "the feed refused to scroll back")
check(feed:Offset() == 3, ("scrolling back three left the offset at %d"):format(feed:Offset()))
check(feed:Row(1).amount:GetText() == feed:At(3).amount,
	"scrolling down three did not put the fourth newest at the top")

-- The one that cannot be seen in a screenshot. Scrolled back, an arrival
-- must push the list down under the offset rather than under your eyes.
local reading = feed:Row(1).amount:GetText()
drop("You receive loot: %s.", _G.WarriorKitItemLink("Arcanite Reaper"))
check(feed:Row(1).amount:GetText() == reading,
	"an arrival scrolled the feed under you while you were reading history")
check(feed:Offset() == 4, "the offset did not follow the list down")

feed:ToTop()
check(feed:Live() and feed:Row(1).name:GetText() == "Arcanite Reaper",
	"going back to the top did not land on the newest entry")

-- The bottom row fades only while there is something under it, because a
-- dimmed last row at the end of the history says there is more when there
-- is not.
check(feed:Row(ns.db.lootFeedRows):GetAlpha() < 1,
	"the bottom row does not fade while there is more below it")
feed:ScrollTo(9999)
check(feed:Row(ns.db.lootFeedRows):GetAlpha() == 1,
	"the bottom row fades at the end of the history, where there is nothing below it")
feed:ToTop()

----------------------------------------------------------------------
-- The ring
--
-- Stated by identity rather than measured. UI/Feed.lua claims a feed in its
-- steady state allocates nothing at all, and what that means precisely is
-- that the slot handed out a full lap later is the same table.
----------------------------------------------------------------------

local lap = feed.cap
local slot = feed:At(0)
for _ = 1, lap do
	drop("You receive loot: %s.", _G.WarriorKitItemLink("Aegis"))
end
check(feed:At(0) == slot,
	"a full lap of the ring did not come back to the same table, so every drop allocates")
check(feed:Count() == lap,
	("the ring holds %d once it has been filled past its cap of %d")
		:format(feed:Count(), lap))

----------------------------------------------------------------------
-- What a row says to the mouse
----------------------------------------------------------------------

do
	local row = feed:Row(1)
	local enter, leave = row:GetScript("OnEnter"), row:GetScript("OnLeave")
	check(enter and leave, "a feed row has no hover scripts, so it can never say what it is")

	ns.UI.Tooltip.Close(true)
	enter(row)
	check(ns.UI.Tooltip.IsShown(), "hovering a feed row said nothing")
	check(ns.UI.Tooltip.Owner() == row, "the tooltip is not anchored to the row you hovered")
	check(ns.UI.Tooltip.Text(1) == "Aegis",
		"the tooltip does not name the item: " .. tostring(ns.UI.Tooltip.Text(1)))

	-- This client hands over no text for an item, which is a real state and
	-- is the one the fallback exists for: the row's own name and the facts
	-- the feed knows, rather than an empty box.
	check(ns.UI.Tooltip.Lines() > 1, "the tooltip fell back to a name and nothing else")

	leave()
	check(not H.tipSettle(), "the tooltip stayed up after the mouse left")
end

-- With the mouse off the feed is a picture: no wheel, so the wheel reaches
-- the camera, and no row answers a hover.
ns.db.lootFeedMouse = false
lootStream:Apply()
check(feed.frame:GetScript("OnMouseWheel") == nil,
	"the feed still swallows the wheel with the mouse turned off")
check(not feed:Row(1):IsMouseEnabled(), "a row still takes the mouse with the setting off")
ns.db.lootFeedMouse = true
lootStream:Apply()
check(feed.frame:GetScript("OnMouseWheel") ~= nil,
	"the feed does not take the wheel with the mouse turned on")
check(feed:Row(1):IsMouseEnabled(), "a row does not take the mouse with the setting on")

-- Growing the feed and shrinking it again. Which rows answer the mouse is
-- decided by two things, the setting and the row count, and each one is
-- perfectly capable of leaving the other stale: the rows this stepper adds
-- have never been through the setting, and the ones it takes away are still
-- holding it. Neither is visible anywhere but at the bottom of a feed you
-- have just resized, which is to say not for weeks.
local rows = ns.db.lootFeedRows
ns.db.lootFeedRows = rows + 4
lootStream:Apply()
check(feed:Row(rows + 4):IsMouseEnabled(),
	"a row the feed just grew by does not take the mouse")
check(not feed:Row(rows + 5):IsMouseEnabled(),
	"a row past the setting takes the mouse")
ns.db.lootFeedRows = rows
lootStream:Apply()
check(not feed:Row(rows + 4):IsMouseEnabled(),
	"a row the feed just shrank past is still taking the mouse")

----------------------------------------------------------------------
-- The combat feed
--
-- The positions are the contract, the same as they are for the meters, so
-- the log is driven through the twenty-one values the client answers with
-- rather than through a shape this section invented.
----------------------------------------------------------------------

do
	local combat = combatStream:Feed()

	-- The feed ships off, because it is the one thing in the addon that runs
	-- on every combat log event in the zone. Everything below is about what a
	-- row says once you have turned it on, so it is turned on here and put
	-- back at the foot of the block.
	local shippedCollect, shippedShown = ns.db.combatFeed, ns.db.combatFeedShown
	ns.db.combatFeed, ns.db.combatFeedShown = true, true
	ns.Stream.Each("Apply")

	-- The sections above this one leave the player with no GUID, which is
	-- what the client looks like across a loading screen. That is a real
	-- state and it has its own assertion below; the rest of this block needs
	-- a player, so one is put back and the roster is rebuilt around it.
	guids.player = "Player-0-0000000f"
	ns.Unit.Roster.Build()
	local me = _G.UnitGUID("player")
	check(me ~= nil and ns.Unit.Roster.Owner(me) == me,
		"the roster does not own the player, so nothing in the log can be yours")

	local function log(subevent, source, sourceName, dest, destName, slots)
		for index = 1, 21 do
			logArgs[index] = nil
		end
		logArgs[1] = GetTime()
		logArgs[2] = subevent
		logArgs[4] = source
		logArgs[5] = sourceName
		logArgs[8] = dest
		logArgs[9] = destName
		for at, value in pairs(slots) do
			logArgs[at] = value
		end
		fire("COMBAT_LOG_EVENT_UNFILTERED")
	end

	combat:Clear()

	-- The other party fighting the pack next door. Neither end is yours, so
	-- it is the event this feed exists not to draw.
	log("SWING_DAMAGE", "Creature-77", "Snarler", "Player-9", "Stranger", { [12] = 400 })
	check(combat:Count() == 0, "an event with neither end yours got a row")

	-- A swing on you.
	--
	-- The two assertions below used to read the other way round: the name
	-- was "Ragged Wolf", because the rule was to fall back to the other
	-- party where there was no spell. That made an incoming swing and an
	-- outgoing spell the same shape on the screen, "Plains Creeper 26" and
	-- "Overpower 321", and neither of them said who was on the other end.
	-- So the name column is always what happened, which for a swing is the
	-- client's own word for one, and the middle column is always who, with
	-- the preposition that says which way it went.
	log("SWING_DAMAGE", "Creature-77", "Ragged Wolf", me, "Baudin", { [12] = 137 })
	check(combat:Count() == 1, "a swing on you did not get a row")
	check(combat:At(0).name == "Attack",
		"a swing is not named with the client's own word for one: "
			.. tostring(combat:At(0).name))
	check(combat:At(0).note == "from Ragged Wolf",
		"an incoming swing does not say who swung: " .. tostring(combat:At(0).note))
	check(combat:At(0).amount == "137", "an incoming swing lost its number")

	-- A spell you cast. It has a name and that is what you want to read.
	log("SPELL_DAMAGE", me, "Baudin", "Creature-77", "Ragged Wolf",
		{ [12] = 12294, [13] = "Mortal Strike", [15] = 871, [21] = true })
	check(combat:At(0).name == "Mortal Strike",
		"an outgoing spell is not named after the spell: " .. tostring(combat:At(0).name))
	check(combat:At(0).note == "on Ragged Wolf",
		"an outgoing spell does not say what it landed on: " .. tostring(combat:At(0).note))
	check(combat:At(0).crit, "a critical read as an ordinary hit")
	check(combat:At(0).tone ~= combat:At(1).tone,
		"a critical draws its number in the same colour as an ordinary hit")

	-- And the half of that a colourblind player has. Gold was the whole of
	-- how a critical announced itself, which is a hue and nothing else, on
	-- the one row in the feed that exists to be noticed.
	check(combat:At(0).amount == "871!",
		"a critical carries no mark on its number, so the crit is a colour and nothing else: "
			.. tostring(combat:At(0).amount))
	check(combat:At(1).amount == "137", "an ordinary hit picked up the critical's mark")

	-- Which way it went, as the colour that carries the whole row.
	check(combat:At(0).stripe ~= combat:At(1).stripe,
		"what you do and what hits you draw the same stripe")

	-- A miss is a row with no number on it.
	log("SWING_MISSED", "Creature-77", "Ragged Wolf", me, "Baudin", { [12] = "DODGE" })
	check(combat:At(0).amount == "dodge",
		"a dodge did not reach the feed as a word: " .. tostring(combat:At(0).amount))
	check(combat:At(0).value == nil, "a miss carried a number")

	ns.db.combatFeedMisses = false
	held = combat:Count()
	log("SWING_MISSED", "Creature-77", "Ragged Wolf", me, "Baudin", { [12] = "PARRY" })
	check(combat:Count() == held, "a miss got a row with misses turned off")
	ns.db.combatFeedMisses = true

	-- The floor, which is the one number that decides whether the feature
	-- is useful or is a column nobody can read.
	ns.db.combatFeedFloor = 200
	held = combat:Count()
	log("SPELL_PERIODIC_DAMAGE", me, "Baudin", "Creature-77", "Ragged Wolf",
		{ [12] = 12721, [13] = "Deep Wounds", [15] = 43 })
	check(combat:Count() == held, "a tick under the floor got a row")
	log("SPELL_PERIODIC_DAMAGE", me, "Baudin", "Creature-77", "Ragged Wolf",
		{ [12] = 12721, [13] = "Deep Wounds", [15] = 604 })
	check(combat:Count() == held + 1, "a tick over the floor was turned away")
	ns.db.combatFeedFloor = 0

	-- Each direction, turned off on its own. A tank wants what hits them and
	-- nothing else, which is the whole reason these are two settings.
	ns.db.combatFeedOut = false
	held = combat:Count()
	log("SPELL_DAMAGE", me, "Baudin", "Creature-77", "Ragged Wolf",
		{ [12] = 12294, [13] = "Mortal Strike", [15] = 700 })
	check(combat:Count() == held, "what you do got a row with that half turned off")
	log("SWING_DAMAGE", "Creature-77", "Ragged Wolf", me, "Baudin", { [12] = 210 })
	check(combat:Count() == held + 1, "what hits you was refused with only the other half off")
	ns.db.combatFeedOut = true

	-- No player GUID at all, which is what the client looks like across a
	-- loading screen and for the first frames after one. Nothing in the log
	-- is yours then, and the trap is that the obvious test for "is this
	-- mine" compares the log's owner against yours and finds nil equal to
	-- nil, which makes every creature in the zone yours. The symptom is a
	-- feed drawing the other party's pull, and it is a comparison that looks
	-- correct in the source.
	guids.player = nil
	held = combat:Count()
	log("SWING_DAMAGE", "Creature-77", "Ragged Wolf", "Creature-88", "Snarler", { [12] = 900 })
	check(combat:Count() == held,
		"with no player GUID the feed drew a fight between two creatures as yours")
	guids.player = "Player-0-0000000f"

	check(Combat.Ready(), "the combat feed says this client has no combat log")

	----------------------------------------------------------------
	-- Where one fight ends and the next begins
	--
	-- A feed with no markers in it is one unbroken column, and the only
	-- thing separating this pull from the last one is a gap in timestamps
	-- a row does not carry. Four claims here and the third is the one that
	-- needs a harness: the markers arrive in the order the two events do,
	-- the end of a fight says how long it was, a marker cannot be read as
	-- an event, and a row goes back to being a row afterwards.
	--
	-- The third is a claim about what was drawn rather than about what was
	-- stored. A marker that carried the right fields and drew an icon, a
	-- name and a number would be a hit for nothing in the middle of a
	-- fight, which is worse than no marker at all, and no assertion
	-- against the entry can see it.
	----------------------------------------------------------------

	combat:Clear()
	fire("PLAYER_REGEN_DISABLED")
	check(combat:Count() == 1, "entering combat drew no marker")
	check(combat:At(0).mark == "in",
		"the marker for entering combat is not marked as one: "
			.. tostring(combat:At(0).mark))

	log("SPELL_DAMAGE", me, "Baudin", "Creature-77", "Ragged Wolf",
		{ [12] = 12294, [13] = "Mortal Strike", [15] = 400 })
	fire("PLAYER_REGEN_ENABLED")

	check(combat:Count() == 3, ("a pull came out as %d rows rather than a marker, a hit and a marker")
		:format(combat:Count()))
	check(combat:At(0).mark == "out", "leaving combat drew no marker")
	check(combat:At(1).mark == nil, "the hit between the two markers is marked as one")
	check(combat:At(2).mark == "in",
		"the markers did not arrive in the order the fight did")
	check((combat:At(0).amount or ""):match("^%d+%.%d+s$") ~= nil,
		"the end of a fight does not say how long it lasted: "
			.. tostring(combat:At(0).amount))

	do
		local band, hit = combat:Row(1), combat:Row(2)
		check(band.caption:IsShown() and not band.name:IsShown(),
			"a marker draws the name column an entry uses, so the two read alike")
		check(not band.icon:IsShown(), "a marker draws an icon, so it reads as an event")
		check(band.stripe:GetWidth() == band.band,
			("a marker's stripe is %s wide and the band across the row is %s")
				:format(tostring(band.stripe:GetWidth()), tostring(band.band)))
		check(band.caption:GetText() == "out of combat",
			"the marker's word did not reach the row: " .. tostring(band.caption:GetText()))

		-- The swap has to go both ways. One that only turned rows into
		-- bands would leave a feed of bands behind the first pull.
		check(hit.name:IsShown() and hit.icon:IsShown() and hit.stripe:GetWidth() == hit.rib,
			"the row under a marker was left drawn as a marker")
		check(hit.note:GetText() == "on Ragged Wolf",
			"the middle column did not reach the row: " .. tostring(hit.note:GetText()))

		-- And what a marker says when you hover it, which has to be about
		-- the break rather than about a hit that never happened.
		band:GetScript("OnEnter")(band)
		check(ns.UI.Tooltip.Text(1) == "out of combat",
			"hovering a marker did not describe the marker: "
				.. tostring(ns.UI.Tooltip.Text(1)))
		band:GetScript("OnLeave")(band)
	end

	ns.db.combatFeed = false
	held = combat:Count()
	fire("PLAYER_REGEN_DISABLED")
	fire("PLAYER_REGEN_ENABLED")
	check(combat:Count() == held, "a marker reached the feed with the feed switched off")
	ns.db.combatFeed = true

	----------------------------------------------------------------
	-- Hidden and off are different states
	--
	-- They were one setting and it made the cheap request impossible: the
	-- only way to get the column off the screen was to stop recording, so
	-- what came back when you wanted it again was blank.
	--
	-- Three claims, and the middle one is the only one worth a harness. A
	-- hidden feed collecting is easy to assert against the entry count and
	-- easy to get wrong on the screen, because Feed:Paint is called on
	-- every arrival and does not know whether anybody can see it. So the
	-- assertion is against what was drawn: the row keeps the text it had
	-- while the ring behind it moves on, and showing the feed again brings
	-- the row up to date in one paint. An implementation that hid the frame
	-- and left the widget painting would pass every count below and fail
	-- none of them, which is why the reads are of a font string.
	----------------------------------------------------------------

	combat:Clear()
	log("SPELL_DAMAGE", me, "Baudin", "Creature-77", "Ragged Wolf",
		{ [12] = 12294, [13] = "Mortal Strike", [15] = 400 })
	check(combat:Row(1).name:GetText() == "Mortal Strike",
		"the row a shown feed drew is not the entry that arrived: "
			.. tostring(combat:Row(1).name:GetText()))

	ns.db.combatFeedShown = false
	combatStream:Show()
	check(not _G.WarriorKitCombatFeed:IsShown(), "hiding the combat feed left it on screen")

	held = combat:Count()
	log("SPELL_DAMAGE", me, "Baudin", "Creature-77", "Ragged Wolf",
		{ [12] = 1464, [13] = "Slam", [15] = 700 })
	check(combat:Count() == held + 1, "a hidden feed stopped collecting")
	check(combat:At(0).name == "Slam",
		"the entry a hidden feed collected is not the one that arrived: "
			.. tostring(combat:At(0).name))
	check(combat:Row(1).name:GetText() == "Mortal Strike",
		"a hidden feed repainted its rows, which is the whole cost it exists to save")

	ns.db.combatFeedShown = true
	combatStream:Show()
	check(_G.WarriorKitCombatFeed:IsShown(), "showing the combat feed left it hidden")
	check(combat:Row(1).name:GetText() == "Slam",
		"a feed brought back is showing what it drew before it went away: "
			.. tostring(combat:Row(1).name:GetText()))

	-- Off implies hidden. There is nothing to look at in a column nothing
	-- is being written to, and a frozen list left on screen reads as a bug
	-- rather than as a setting.
	ns.db.combatFeed = false
	combatStream:Show()
	check(not _G.WarriorKitCombatFeed:IsShown(),
		"a feed switched off is still on screen, showing a list that will never move")
	ns.db.combatFeed = true
	combatStream:Show()

	-- And the loot feed carries the same pair, because the two settings
	-- belong to Feeds/Stream.lua rather than to either capture file.
	ns.db.lootFeedShown = false
	lootStream:Show()
	check(not _G.WarriorKitLootFeed:IsShown(), "hiding the loot feed left it on screen")
	ns.db.lootFeedShown = true
	lootStream:Show()
	check(_G.WarriorKitLootFeed:IsShown(), "showing the loot feed left it hidden")

	----------------------------------------------------------------
	-- Every tooltip is one size, and it is the addon's
	--
	-- One frame serves every hover in the addon, so it has one zoom and
	-- forty possible owners. It took that zoom from the owner, which read
	-- well one box at a time and badly across a session: the missing buff
	-- row ships at 2x and the action bar under it at 1x, so the same
	-- sentence came out in two sizes depending on where the cursor was. The
	-- size of a HUD widget is how far away you read it from. The size of
	-- text is the slider.
	--
	-- Nothing outside the file can see which rule is in force but by
	-- opening the box on two owners at different zooms and reading the zoom
	-- back, which is why Tooltip.Zoom exists.
	----------------------------------------------------------------

	do
		local Tip = ns.UI.Tooltip
		local size = Tip.Scale()
		local function Wanted()
			return ns.UI.ScreenZoom() * Tip.Scale()
		end

		ns.db.combatFeedZoom = 2
		combatStream:Apply()
		-- The hover's own zoom, put well above both feeds, so the box's answer
		-- and either feed's are three different numbers. At 1x nothing here can
		-- fail.
		ns.Settings.SetTipZoom(3)

		local row = combat:Row(2)
		row:GetScript("OnEnter")(row)
		check(Tip.Zoom() == Wanted(),
			("a tooltip opened on a feed at 2x drew at %s and a hover box is at %s")
				:format(tostring(Tip.Zoom()), tostring(Wanted())))

		-- And the other feed, at a different zoom again. A box that had gone
		-- on following its owner would answer 2 here and a box following the
		-- last thing it saw would answer 2 as well, so the two hovers are
		-- what tells those apart from the one right answer.
		local loot = feed:Row(1)
		loot:GetScript("OnEnter")(loot)
		check(Tip.Zoom() == Wanted(),
			("a tooltip opened on a feed at %sx drew at %s and a hover box is at %s")
				:format(tostring(ns.db.lootFeedZoom), tostring(Tip.Zoom()),
					tostring(Wanted())))
		check(ns.db.lootFeedZoom ~= Wanted(),
			"both feeds are drawn at the hover box's own zoom, so this proves nothing")
		loot:GetScript("OnLeave")(loot)

		ns.Settings.SetTipZoom(size)
		ns.db.combatFeedZoom = 1
		combatStream:Apply()

		------------------------------------------------------------
		-- The data a caller hands over
		--
		-- Every shape in the schema is in one of the two feeds' fills
		-- already, so all of it is asserted through them rather than
		-- through a table this section invented. A schema the harness
		-- exercises and no caller uses is one that can rot without
		-- anything here noticing.
		------------------------------------------------------------

		combat:Clear()
		log("SPELL_DAMAGE", me, "Baudin", "Creature-77", "Ragged Wolf",
			{ [12] = 12294, [13] = "Mortal Strike", [15] = 871, [16] = 40, [21] = true })

		row = combat:Row(1)
		row:GetScript("OnEnter")(row)
		check(Tip.Text(1) == "Mortal Strike",
			"the title did not render: " .. tostring(Tip.Text(1)))
		check(Tip.Lines() == 7,
			("the fill describes seven lines and %d were drawn"):format(Tip.Lines()))

		local label, value = Tip.Text(5)
		check(label == "Damage" and value == "871",
			("a pair rendered as %s / %s"):format(tostring(label), tostring(value)))
		check(Tip.Text(6) == "A critical.",
			"a plain line did not render: " .. tostring(Tip.Text(6)))
		check(Tip.Text(7) ~= "" and Tip.Text(7) ~= nil,
			"the last line of the fill is blank, so a band left its air behind")
		check((Tip.Text(7) or ""):find("/wk", 1, true) == nil,
			"the blue switch line is still on the end of a feed row's box: "
				.. tostring(Tip.Text(7)))

		-- Two sizes, and both of them the addon's own.
		--
		-- The body was 11, which is UI.Metric.small, the size the panel keeps
		-- for a hint under a control. Every line of a tooltip is the thing you
		-- opened it to read, so a box whose prose was a size smaller than the
		-- panel it was hanging over had it exactly backwards, and the report
		-- was that the tooltip's font looked bad. It did.
		--
		-- The metric is the shipped answer rather than the only one: the body
		-- size is a setting now, and what is asserted here is the box the addon
		-- hands somebody who has not touched it. 48-tooltips.lua walks the
		-- slider itself.
		--
		-- Read off the font the client ended up with rather than off the two
		-- constants, because the point of the fix is that the file no longer
		-- writes its own numbers. Multiplied by nothing: a size inside an
		-- adopted frame is a count of design pixels and so is the metric.
		local M = ns.UI.Metric
		check(Tip.Size(1) == M.heading,
			("the tooltip title is %s pixels and the addon's heading is %d")
				:format(tostring(Tip.Size(1)), M.heading))
		for _, index in ipairs({ 5, 6, 7 }) do
			check(Tip.Size(index) == M.font,
				("tooltip line %d is %s pixels and the addon's body is %d")
					:format(index, tostring(Tip.Size(index)), M.font))
		end
		check(M.heading > M.font,
			("a title at %d and a body at %d is not a title")
				:format(M.heading, M.font))

		-- Nothing to say draws nothing, which is what a row whose entry has
		-- gone gets and what a nag square with nothing to nag about gets. A
		-- box the size of its own padding beside the thing it has nothing
		-- to say about is worse than no box.
		check(Tip.Show(row, nil) == false, "a tooltip handed nothing still opened")
		check(not Tip.IsShown(), "a tooltip handed nothing stayed on screen")
	end

	-- The combat feed back to shipping off, so the sections after this one see
	-- the client the addon actually hands a player.
	ns.db.combatFeed, ns.db.combatFeedShown = shippedCollect, shippedShown
	ns.Stream.Each("Apply")

	print(("feeds  loot %s, combat %s; %d of %d loot sentences; tooltip %s")
		:format(lootStream:Describe(), combatStream:Describe(), live, total,
			ns.UI.Scan.Describe()))
end

-- Put away, because the sections after this one hover things of their own
-- and a tooltip anchored to a loot row would still be up.
ns.UI.Tooltip.Close()
