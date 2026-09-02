-- The session pile
--
-- One claim, and everything here is in service of it: the pile holds what
-- arrived while the session was running and nothing else.
--
-- That is the only thing about this part that can be wrong. Where the pile is
-- drawn and what its squares look like are 55-bags.lua's, the heading is one
-- string pushed into Core/Piles.lua, and the press is a button. What no reading
-- of the code settles is the diff: an item you were already carrying must stay
-- in its class pile, an item that arrives must move, an item that arrives twice
-- must count twice, and an item that arrives after the stop must not count at
-- all. So the bags are changed under a running session and read back.
--
-- The two numbers on a session square are asserted together, because they are
-- the honest half of a thing this client cannot do. There is no per-item
-- identity in a container on 2.5, so a stack of twenty holding twelve you
-- looted and eight you carried in is one stack and stays one stack. The square
-- says twenty in the corner and twelve at the top, and the test is that those
-- two numbers are allowed to differ.

local H = ...
local ns, check = H.ns, H.check
local CARRIED, counted, fire = H.CARRIED, H.counted, H.fire
local refill = H.refill

local Bags, Session, Piles = ns.Bags, ns.BagsSession, ns.Piles

----------------------------------------------------------------------
-- The scene
--
-- The trash bag, refilled, and a zone to name the session after. GetZoneText
-- is not one of the client stubs, because until this file nothing in the addon
-- asked what zone you were in. It is put up here and taken down at the end, so
-- a section added after this one finds the client it expected.
----------------------------------------------------------------------

refill()
Session.Clear()

local zone = "Scholomance"
_G.GetZoneText = function() return zone end

local function pile(key)
	local read = Bags.Read()
	for index = 1, read.shown do
		if read.groups[index].key == key then
			return read.groups[index], index
		end
	end
	return nil
end

local function named(group, name)
	for index = 1, #group.entries do
		if group.entries[index].name == name then
			return group.entries[index]
		end
	end
	return nil
end

-- A slot in the trash bag, holding this many, with the bag update the client
-- would have sent. One helper because every step below is the same three lines
-- and the interesting part is which of the numbers moved.
local function put(slot, name, count)
	CARRIED[1][slot] = name or false
	counted(1, slot, count or 1)
	fire("BAG_UPDATE", 1)
end

----------------------------------------------------------------------
-- Before anything is recorded
----------------------------------------------------------------------

check(pile("session") == nil,
	"a character who has never pressed record has a session pile")
check(Session.Running() == false,
	"nothing was pressed and a session is running")

-- The pile a vendor's rack sorts into goes through the same file, and this is
-- the guard that keeps it out of there: Piles.Of decides on the item class and
-- has no way to answer this key, whatever is in the ledger.
check(Piles.Of(_G.WarriorKitItemLink("Chipped Boar Tusk")) ~= Piles.SESSION,
	"Piles.Of answered the session pile, which would put one in the merchant window")

----------------------------------------------------------------------
-- What arrives while it is running
----------------------------------------------------------------------

Session.Start()

check(Session.Running(), "record was pressed and nothing is recording")
check(Session.Name() == zone,
	("the session is called %s and the zone is %s")
		:format(tostring(Session.Name()), zone))

-- Twelve cloth into an empty slot, which is the whole of what a loot is here.
put(5, "Linen Cloth", 12)

local session = pile("session")
check(session ~= nil, "twelve cloth arrived during a session and no pile was drawn")

local cloth = session and named(session, "Linen Cloth")
check(cloth ~= nil, "the cloth that arrived is not in the session pile")
check(cloth and cloth.gained == 12,
	("the session recorded %s cloth and twelve arrived"):format(tostring(cloth and cloth.gained)))

-- The heading is the zone rather than the fallback, which is the one string
-- Core/Piles.lua cannot work out for itself.
check(session and session.name == zone,
	("the session pile is headed %q and the zone is %q")
		:format(tostring(session and session.name), zone))

-- First, above every class pile. It is the reason the window is open.
local _, at = pile("session")
check(at == 1, ("the session pile is drawn %s and it belongs at the top"):format(tostring(at)))

-- The four greys were in the bag before the session started, so they are still
-- graded on their quality and drawn under Junk. This is the half of the diff
-- that cannot be seen by looking at what moved.
local junk = pile("junk")
check(junk ~= nil and named(junk, "Chipped Boar Tusk") ~= nil,
	"a grey that was already in the bag was swept into the session pile")

----------------------------------------------------------------------
-- The same item arriving twice
--
-- Eight more into the same slot. The stack is twenty and the session recorded
-- twenty, because all of it arrived while it was running.
----------------------------------------------------------------------

put(5, "Linen Cloth", 20)

cloth = named(pile("session"), "Linen Cloth")
check(cloth and cloth.gained == 20,
	("the session recorded %s after twelve and then eight more"):format(tostring(cloth and cloth.gained)))
check(cloth and cloth.count == 20,
	("the square is holding %s"):format(tostring(cloth and cloth.count)))

----------------------------------------------------------------------
-- The two numbers, and why they differ
--
-- A second session, started with the twenty already in the bag, and eight more
-- arriving into it. The stack is twenty eight and the session recorded eight,
-- which is the case this client cannot draw any other way: the eight and the
-- twenty are one stack and no call will split them.
----------------------------------------------------------------------

Session.Start()
put(5, "Linen Cloth", 28)

cloth = named(pile("session"), "Linen Cloth")
check(cloth and cloth.gained == 8,
	("a fresh session recorded %s of a stack that grew by eight"):format(tostring(cloth and cloth.gained)))
check(cloth and cloth.count == 28,
	("the same square is holding %s"):format(tostring(cloth and cloth.count)))

----------------------------------------------------------------------
-- A scan that could not see the bags
--
-- The bug this section was written after, and the reason the baseline is
-- written over rather than replaced. Walking into Uldaman with a session
-- running, the bags read short for a frame. The baseline was emptied and
-- refilled from that reading, forty ids fell out of it, and the next scan
-- counted everything the character had walked in carrying as loot.
--
-- Modelled by taking the bag away and putting it back with nothing changed in
-- it, which is what a loading screen looks like from in here.
----------------------------------------------------------------------

local before = select(2, Session.Held())

local stashed = CARRIED[1]
CARRIED[1] = {}
fire("BAG_UPDATE", 1)
CARRIED[1] = stashed
fire("BAG_UPDATE", 1)

local _, restored = Session.Held()
check(restored == before,
	("a bag that read short for one scan added %d to the ledger")
		:format(restored - before))

----------------------------------------------------------------------
-- A stack on the cursor
--
-- The same failure wearing a different hat. Twelve out of a stack of twenty
-- leaves eight in the bag, which is a true reading of a real removal, so the
-- baseline follows it down and putting them back reads as twelve arriving. No
-- scan is taken at all while the cursor is holding something.
----------------------------------------------------------------------

local cursor = _G.GetCursorInfo
_G.GetCursorInfo = function() return "item", 2005, H.itemLink("Linen Cloth") end

put(5, "Linen Cloth", 16)
_G.GetCursorInfo = cursor
put(5, "Linen Cloth", 28)

local _, dragged = Session.Held()
check(dragged == before,
	("twelve lifted out of a stack and dropped back added %d to the ledger")
		:format(dragged - before))

----------------------------------------------------------------------
-- After the stop
----------------------------------------------------------------------

Session.Stop()
check(Session.Running() == false, "stop was pressed and it is still recording")

-- The pile survives the stop, which is the whole point of stop being its own
-- press: it is what you work through at a vendor on the way home.
check(pile("session") ~= nil, "stopping emptied the pile")

-- A green into the bag after the stop. Nothing about it may reach the ledger.
put(6, "Emerald Pigment", 1)

check(named(pile("session"), "Emerald Pigment") == nil,
	"something picked up after the stop landed in the session pile")

local kinds, total = Session.Held()
check(kinds == 1 and total == 8,
	("the ledger holds %d kind%s and %d in all, and eight cloth is all that arrived")
		:format(kinds, kinds == 1 and "" or "s", total))

----------------------------------------------------------------------
-- Clearing it
----------------------------------------------------------------------

Session.Clear()

check(pile("session") == nil, "the pile is still drawn after a clear")
check(Session.Name() == nil, "the session still has a name after a clear")

-- The press behind the forget button in the title bar, which is the only way
-- to the clear from the window itself. Driven rather than assumed, because the
-- button beside it says clear and opens the destroy window, and the two being
-- wired to each other's work is exactly the mistake the different word is
-- there to stop.
Session.Start()
put(7, "Emerald Pigment", 2)
check(select(1, Session.Held()) > 0, "nothing was recorded to forget")
Session.Forget()
check(select(1, Session.Held()) == 0, "forget left something in the ledger")
check(Session.Running() == false, "forget left the session recording")
put(7, nil, 1)
CARRIED[1][7] = nil

----------------------------------------------------------------------
-- A second dungeon
--
-- The heading is a string written onto Core/Piles.lua's own pile, and that file
-- caches a pile's word the first time it is asked for. So the run that proves
-- the cache is not a one-way door is the second one, under a different name.
--
-- The item is one that was already in the bag. Three more Tattered Cloth on top
-- of the one you were carrying is a gain of three, which is the reading the
-- whole diff turns on: the pile counts the rise and not the stack.
----------------------------------------------------------------------

zone = "Dire Maul"
Session.Start()
put(2, "Tattered Cloth", 4)

local second = pile("session")
check(second ~= nil and second.name == zone,
	("the second session is headed %s and the zone is %s")
		:format(tostring(second and second.name), zone))

local cloth2 = second and named(second, "Tattered Cloth")
check(cloth2 and cloth2.gained == 3,
	("three arrived on top of the one you were carrying and the pile says %s")
		:format(tostring(cloth2 and cloth2.gained)))

----------------------------------------------------------------------
-- A session that came back from a reload
--
-- The record is a per-character saved variable, so a /reload is meant to change
-- nothing about it. Two things would break that quietly and neither shows up in
-- any other check here.
--
-- The heading is the first. It is a string written onto Core/Piles.lua's pile
-- at the press, and Core/Piles.lua starts every session over, so a login that
-- did not push it back would draw last night's dungeon under the word Session.
--
-- The baseline is the second and it is the one that would go wrong silently. A
-- session counts the rise since the last scan, so if the counts it was holding
-- did not survive the reload, the first bag update afterwards would read your
-- whole bag as freshly gained and file everything you own under the dungeon.
--
-- Both are driven the way the client would: the saved table put back as it was
-- written, PLAYER_LOGIN fired over it, then a bag update with nothing new in it.
----------------------------------------------------------------------

-- The bags as they were when you reloaded, and a session recording over them.
-- Session.Start is what takes the baseline, and taking it that way rather than
-- writing one by hand is the point: the saved file holds a count for every item
-- you were carrying, and a hand-written one that missed a bag would prove the
-- opposite of what this is for.
put(5, "Linen Cloth", 12)

zone = "Stratholme"
Session.Start()
ns.dbc.bagSession.items = { [2005] = 12 }

-- Core/Piles.lua, as a fresh load leaves it: a pile with no heading on it.
Piles.Rename(Piles.SESSION, nil)
fire("PLAYER_LOGIN")

local back = pile("session")
check(back ~= nil and back.name == zone,
	("a session that survived a reload is headed %s and the zone was %s")
		:format(tostring(back and back.name), zone))
check(Session.Running(), "a session that was recording stopped across the reload")

-- A bag update with nothing new in it. This is the one that would go wrong
-- quietly: with no baseline in the saved file, it reads the whole bag as gained.
put(5, "Linen Cloth", 12)
local kinds2, total2 = Session.Held()
check(kinds2 == 1 and total2 == 12,
	("the first scan after the reload left the ledger holding %d kind(s), %d in all")
		:format(kinds2, total2))

-- And it is still recording, so eight more still land.
put(5, "Linen Cloth", 20)
local _, grown = Session.Held()
check(grown == 20,
	("eight more arrived after the reload and the ledger says %d"):format(grown))

----------------------------------------------------------------------
-- The scene, put back
----------------------------------------------------------------------

Session.Clear()
put(2, "Tattered Cloth", 1)
put(5, nil, 1)
put(6, nil, 1)
CARRIED[1][5], CARRIED[1][6] = nil, nil
refill()
_G.GetZoneText = nil
