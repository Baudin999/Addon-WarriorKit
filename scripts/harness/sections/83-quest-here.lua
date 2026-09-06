-- Where you are standing
--
-- One claim: ns.QuestHere answers the place around you as a map id, a name and
-- a dungeon flag, off numbers the whole way down, and it degrades one field at
-- a time rather than all at once.
--
-- **Every join is asserted on a number and none of them on a name.** The names
-- are checked once each, and only where they come straight back off the
-- client. The addon must never decide anything on one: Blizzard's own name for
-- a dungeon is a different name from the book's for eight of the forty and it
-- arrives in the player's language, so an assertion that a name drove a join
-- would certify a feature that works on one client in ten.
--
-- **Four clients, and the answer has to survive each.** One with Questie and
-- IsInInstance, which is 2.5.6 with the addon installed; one with Questie and
-- no IsInInstance; one with IsInInstance and no Questie; and one with neither.
-- Only the map id and the client's own name are there in all four, which is
-- why the contract puts the other three fields in "or nothing".
--
-- **The two disagreeing is the interesting case.** The client is asked first
-- and Questie's table is only the fallback, so a place Questie files as a
-- dungeon while the client says you are outdoors reads as outdoors. That
-- ordering is the whole reason the flag is IsInInstance rather than the book:
-- a caller going quiet indoors wants raids and battlegrounds too, and the book
-- has forty dungeons and none of either.
--
-- **The hold is read by changing a fixture and not saying so.** An answer that
-- moved with no walk behind it was never held; one that did not move after the
-- map id changed is a hold nothing empties. The one asymmetry is deliberate:
-- an answer with no area id on it is not held, because Questie's database
-- compiles minutes after login and standing still through that would otherwise
-- leave the area missing for the rest of the session.

local H = ...
local ns, check, advance = H.ns, H.check, H.advance
local quests, dungeons = H.quests, H.dungeons

local Here = ns.QuestHere

local standing = quests.standing
local WAS = standing.map

-- The five places this section stands you in. Every id is the live client's
-- own, and the area ids they join to are read off the installed Questie in
-- client/16-dungeons.lua rather than typed here.
local WESTFALL, NOWHERE = 1436, 9001
local DEADMINES, IRONCLAD, STOCKADE = 291, 292, 225

-- Stand somewhere, say whether the client thinks it is an instance, and drop
-- the held answer so the next reading is a fresh one. `kind` is a string for
-- inside an instance of that kind, nil for the open world, and false for a
-- client with no IsInInstance at all.
local function at(map, kind)
	standing.map = map
	dungeons.Inside(kind)
	Here.Forget()
	return Here.Now()
end

----------------------------------------------------------------------
-- The open world
----------------------------------------------------------------------

local here = at(WESTFALL)
check(here ~= nil, "standing in the open world answered nothing at all")
check(here and here.map == WESTFALL,
	("the map came back as %s"):format(here and tostring(here.map)))
check(here and here.name == "Westfall",
	("the client's own name came back as %s"):format(here and tostring(here.name)))
check(here and here.dungeon == false, "a zone in the open world read as a dungeon")
check(here and here.area == 40,
	("Questie's area came back as %s"):format(here and tostring(here.area)))
check(here and here.parent == nil,
	"a zone at the top of its own tree was given a parent")

check(Here.Describe() == "standing in Westfall, map 1436, area 40",
	("the reading says %q"):format(Here.Describe()))

----------------------------------------------------------------------
-- A map Questie has no row for
----------------------------------------------------------------------

-- The branch that takes a frame down without a pcall. The real
-- ZoneDB:GetAreaIdByUiMapId scans by name and then calls error() outright, and
-- the stub errors for the one id the map tree already has no picture for.
here = at(NOWHERE)
check(here and here.map == NOWHERE and here.name == "Somewhere Else",
	"a map Questie errors on lost the half of the answer that is the client's")
check(here and here.area == nil, "a map Questie errors on came back with an area id")
check(here and here.parent == nil, "a map Questie errors on came back with a parent")
check(Here.Describe()
	== "standing in Somewhere Else, map 9001, and Questie has no area id for it",
	("the reading says %q"):format(Here.Describe()))

----------------------------------------------------------------------
-- A dungeon
----------------------------------------------------------------------

here = at(DEADMINES, "party")
check(here and here.dungeon == true, "standing in a dungeon did not read as one")
check(here and here.map == DEADMINES and here.name == "The Deadmines",
	"the dungeon's own map id or name went missing")
check(here and here.area == 1581,
	("the dungeon's area came back as %s"):format(here and tostring(here.area)))
check(here and here.parent == nil,
	"the dungeon was given a parent, and Questie answers none for a dungeon's own area")
check(Here.Describe()
	== "standing in The Deadmines, map 291, area 1581, which is a dungeon",
	("the reading says %q"):format(Here.Describe()))

-- The second floor, which Questie files under an area of its own and hangs off
-- the first. It is the only one of the five with a parent, which is what makes
-- it worth standing on.
here = at(IRONCLAD, "party")
check(here and here.area == 10029 and here.parent == 1581,
	"the second floor did not come back under the area above it")
check(here and here.dungeon == true, "the second floor did not read as a dungeon")

----------------------------------------------------------------------
-- A client with no IsInInstance
----------------------------------------------------------------------

-- Questie's table is the fallback and it is read off the area id, not off a
-- name. Two dungeons and a zone, so the fallback has to say no as well as yes.
here = at(DEADMINES, false)
check(here and here.dungeon == true,
	"with no IsInInstance the dungeon flag did not come off Questie's table")
here = at(STOCKADE, false)
check(here and here.dungeon == true, "the second dungeon did not read as one")
here = at(WESTFALL, false)
check(here and here.dungeon == false, "a zone read as a dungeon off Questie's table")

-- And with neither the client nor a row, which is the map Questie errors on.
here = at(NOWHERE, false)
check(here and here.dungeon == false,
	"a map with no area id and no IsInInstance answered a dungeon flag")

----------------------------------------------------------------------
-- The client wins
----------------------------------------------------------------------

-- Standing on a dungeon's map with the client saying you are outdoors. The two
-- cannot both be right and the client is the one that is asked first, so this
-- reads as outdoors. It is the ordering rather than the scene that is being
-- asserted: IsInInstance covers raids and battlegrounds, and Questie's table
-- covers neither.
here = at(STOCKADE)
check(here and here.dungeon == false,
	"the client said you were outdoors and the flag came off Questie's table anyway")
check(here and here.area == 717,
	"the area id moved with the dungeon flag, and it is a different question")

----------------------------------------------------------------------
-- Questie absent
----------------------------------------------------------------------

local loader = _G.QuestieLoader

_G.QuestieLoader = nil
here = at(WESTFALL)
check(here and here.map == WESTFALL and here.name == "Westfall",
	"a client with no Questie lost the half of the answer that is the client's")
check(here and here.area == nil and here.parent == nil,
	"a client with no Questie answered an area id")
check(here and here.dungeon == false, "a zone with no Questie read as a dungeon")

here = at(DEADMINES, "party")
check(here and here.dungeon == true,
	"the dungeon flag went with Questie, and it is the client's own answer")

here = at(DEADMINES, false)
check(here and here.dungeon == false,
	"with no Questie and no IsInInstance the flag was not false")

-- A Questie that is loaded and has none of the three calls on it, which is what
-- ns.Questie refuses by asking for the calls by name rather than the module.
_G.QuestieLoader = { ImportModule = function() return {} end }
here = at(WESTFALL)
check(here and here.area == nil,
	"a Questie with none of the ZoneDB calls answered an area id")
check(here and here.map == WESTFALL, "and it lost the map id with them")

_G.QuestieLoader = loader

----------------------------------------------------------------------
-- Asked once
----------------------------------------------------------------------

here = at(WESTFALL)
check(rawequal(Here.Now(), here), "the same place was worked out twice")

advance(30)
check(rawequal(Here.Now(), here),
	"a complete answer was worked out again half a minute later in the same place")

standing.map = DEADMINES
check(not rawequal(Here.Now(), here) and Here.Now().map == DEADMINES,
	"walking into a new place did not move the answer")

-- The one thing that is not held. Questie learns the map without anything
-- saying so, which is what a database finishing its compile looks like from
-- here, and the next reading has to pick it up.
here = at(NOWHERE)
check(here and here.area == nil, "the fixture answered an area for the map it errors on")
dungeons.AREAS[NOWHERE] = 4242
check(rawequal(Here.Now(), here),
	"an incomplete answer was worked out again inside the few seconds it is held for")
advance(6)
check(Here.Now().area == 4242,
	"an answer with no area id was still held after Questie learned the map")
dungeons.AREAS[NOWHERE] = nil

----------------------------------------------------------------------
-- A client that will not say
----------------------------------------------------------------------

standing.map = nil
Here.Forget()
check(Here.Now() == nil, "a client that will not say which map you are on answered one")
check(Here.Describe() == "the client will not say which map you are standing on",
	("the reading says %q"):format(Here.Describe()))

standing.map = WAS
dungeons.Inside(nil)
Here.Forget()

print(("here %s"):format(Here.Describe()))
