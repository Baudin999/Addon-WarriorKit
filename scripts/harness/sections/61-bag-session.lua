-- The session pile
--
-- One claim, and everything here is in service of it: the pile holds what the
-- server said you looted while the session was running, and nothing else.
--
-- That is the only thing about this part that can be wrong. Where the pile is
-- drawn and what its squares look like are 55-bags.lua's, the heading is one
-- string pushed into Core/Piles.lua, and the press is a button. What no reading
-- of the code settles is the record: an item you were already carrying must
-- stay in its class pile, an item you loot must move, an item looted twice must
-- count twice, somebody else's loot must not count at all, and nothing looted
-- after the stop may join it. So loot sentences are put through it and the
-- piles are read back.
--
-- The two numbers on a session square are asserted together, because they are
-- the honest half of a thing this client cannot do. There is no per-item
-- identity in a container on 2.5, so a stack of twenty holding twelve you
-- looted and eight you carried in is one stack and stays one stack. The square
-- says twenty in the corner and twelve at the top, and the test is that those
-- two numbers are allowed to differ.
--
-- The sentences are the client's own enUS strings out of 03-player.lua rather
-- than anything typed here, for the reason that file gives: the addon builds
-- its patterns off the format strings the client hands it, and a test that
-- typed the sentence would be testing a different thing than the one that runs.

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

-- The server saying you looted some of something, in the client's own words.
local function loot(name, count)
	if count then
		fire("CHAT_MSG_LOOT",
			(_G.LOOT_ITEM_SELF_MULTIPLE):format(H.itemLink(name), count))
	else
		fire("CHAT_MSG_LOOT", (_G.LOOT_ITEM_SELF):format(H.itemLink(name)))
	end
end

-- The same sentence about somebody else, which must never reach the pile.
local function theirs(who, name, count)
	fire("CHAT_MSG_LOOT",
		(_G.LOOT_ITEM_MULTIPLE):format(who, H.itemLink(name), count))
end

-- A slot in the trash bag, holding this many. The record is off the messages
-- now and never off the bags, so this exists only so the square the pile draws
-- has something real underneath it.
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
check(Piles.Of(H.itemLink("Chipped Boar Tusk")) ~= Piles.SESSION,
	"Piles.Of answered the session pile, which would put one in the merchant window")

-- A sentence arriving with nothing recording must not start anything.
loot("Linen Cloth", 5)
check(pile("session") == nil, "loot with no session running was recorded anyway")

----------------------------------------------------------------------
-- What the server says you looted
----------------------------------------------------------------------

Session.Start()

check(Session.Running(), "record was pressed and nothing is recording")
check(Session.Name() == zone,
	("the session is called %s and the zone is %s")
		:format(tostring(Session.Name()), zone))

-- Twelve cloth, and the stack in the bag it put there.
put(5, "Linen Cloth", 12)
loot("Linen Cloth", 12)

local session = pile("session")
check(session ~= nil, "twelve cloth were looted and no session pile was drawn")

local cloth = session and named(session, "Linen Cloth")
check(cloth ~= nil, "the cloth that was looted is not in the session pile")
check(cloth and cloth.gained == 12,
	("the session recorded %s cloth and twelve were looted"):format(tostring(cloth and cloth.gained)))

-- The heading is the zone rather than the fallback, which is the one string
-- Core/Piles.lua cannot work out for itself.
check(session and session.name == zone,
	("the session pile is headed %q and the zone is %q")
		:format(tostring(session and session.name), zone))

-- First, above every class pile. It is the reason the window is open.
local _, at = pile("session")
check(at == 1, ("the session pile is drawn %s and it belongs at the top"):format(tostring(at)))

-- The four greys were in the bag before the session started and nothing said a
-- word about them, so they are still graded on quality and drawn under Junk.
local junk = pile("junk")
check(junk ~= nil and named(junk, "Chipped Boar Tusk") ~= nil,
	"a grey that was already in the bag reached the session pile")

----------------------------------------------------------------------
-- The same item looted twice
----------------------------------------------------------------------

put(5, "Linen Cloth", 20)
loot("Linen Cloth", 8)

cloth = named(pile("session"), "Linen Cloth")
check(cloth and cloth.gained == 20,
	("the session recorded %s after twelve and then eight"):format(tostring(cloth and cloth.gained)))
check(cloth and cloth.count == 20,
	("the square is holding %s"):format(tostring(cloth and cloth.count)))

----------------------------------------------------------------------
-- Somebody else's loot
--
-- The same sentence with a name in front of it. The loot feed draws those,
-- because watching what the group is picking up is what a feed is for. A pile
-- in your own bags cannot hold the sword somebody else won.
----------------------------------------------------------------------

theirs("Grimble", "Linen Cloth", 5)

cloth = named(pile("session"), "Linen Cloth")
check(cloth and cloth.gained == 20,
	("a party member looted five and the pile went to %s"):format(tostring(cloth and cloth.gained)))

----------------------------------------------------------------------
-- The two numbers, and why they differ
--
-- A fresh session over a bag that already holds twenty, and eight looted into
-- it. The square says twenty at the bottom and eight at the top. There is no
-- per-item identity in a container on this client, so the eight and the twelve
-- under them are one stack and no call will ever split them; what the top
-- number is worth is that it is exact rather than inferred.
----------------------------------------------------------------------

Session.Start()
loot("Linen Cloth", 8)

cloth = named(pile("session"), "Linen Cloth")
check(cloth and cloth.gained == 8,
	("a fresh session recorded %s after eight were looted"):format(tostring(cloth and cloth.gained)))
check(cloth and cloth.count == 20,
	("the same square is holding %s"):format(tostring(cloth and cloth.count)))

----------------------------------------------------------------------
-- Nothing about your bags is a source
--
-- This is the whole of what changed when the record stopped being a diff, and
-- it is worth one section on its own. The pile filled with everything a
-- character had walked into Uldaman carrying, because the bags read short for
-- a frame on the loading screen and the reconstruction that followed invented
-- thirty two items.
--
-- Both shapes of that are driven here: a bag that vanishes and comes back, and
-- a stack that grows with nothing said about it. Neither may move the ledger by
-- one, and now neither can, because no reading of a bag reaches the record at
-- all.
----------------------------------------------------------------------

local _, before = Session.Held()

local stashed = CARRIED[1]
CARRIED[1] = {}
fire("BAG_UPDATE", 1)
CARRIED[1] = stashed
fire("BAG_UPDATE", 1)

local _, restored = Session.Held()
check(restored == before,
	("a bag that read short for one scan added %d to the ledger")
		:format(restored - before))

put(5, "Linen Cloth", 40)
local _, grown = Session.Held()
check(grown == before,
	("a stack that grew with nothing said about it added %d to the ledger")
		:format(grown - before))
put(5, "Linen Cloth", 20)

----------------------------------------------------------------------
-- After the stop
----------------------------------------------------------------------

Session.Stop()
check(Session.Running() == false, "stop was pressed and it is still recording")

-- The pile survives the stop, which is the whole point of stop being its own
-- press: it is what you work through at a vendor on the way home.
check(pile("session") ~= nil, "stopping emptied the pile")

put(6, "Emerald Pigment", 2)
loot("Emerald Pigment", 1)

check(named(pile("session"), "Emerald Pigment") == nil,
	"something looted after the stop landed in the session pile")

local kinds, total = Session.Held()
check(kinds == 1 and total == 8,
	("the ledger holds %d kind%s and %d in all, and eight cloth is all that was looted")
		:format(kinds, kinds == 1 and "" or "s", total))

----------------------------------------------------------------------
-- Forgetting it
----------------------------------------------------------------------

Session.Forget()

check(pile("session") == nil, "the pile is still drawn after a forget")
check(Session.Name() == nil, "the session still has a name after a forget")
check(select(1, Session.Held()) == 0, "forget left something in the ledger")
check(Session.Running() == false, "forget left the session recording")

----------------------------------------------------------------------
-- A session that came back from a reload
--
-- The record is a per-character saved variable, so a reload is meant to change
-- nothing about it, and the ledger is now the only thing that has to survive:
-- the diff this replaced also had to bring a baseline back intact, and that
-- baseline was the thing that got corrupted.
--
-- What is still worth driving is the heading. It is a string written onto
-- Core/Piles.lua's own pile at the press, and that file comes up every load
-- with the fallback word on it, so a login that did not push the name back
-- would draw last night's dungeon under the word Session.
----------------------------------------------------------------------

zone = "Stratholme"
ns.dbc.bagSession = { name = zone, running = true, items = { [2005] = 12 } }

-- Core/Piles.lua, as a fresh load leaves it: a pile with no heading on it.
Piles.Rename(Piles.SESSION, nil)
fire("PLAYER_LOGIN")

local back = pile("session")
check(back ~= nil and back.name == zone,
	("a session that survived a reload is headed %s and the zone was %s")
		:format(tostring(back and back.name), zone))
check(Session.Running(), "a session that was recording stopped across the reload")
check(select(2, Session.Held()) == 12,
	("the ledger came back holding %d"):format(select(2, Session.Held())))

-- And it is still recording, so the next sentence still lands.
loot("Linen Cloth", 8)
check(select(2, Session.Held()) == 20,
	("eight more were looted after the reload and the ledger says %d")
		:format(select(2, Session.Held())))

----------------------------------------------------------------------
-- A second dungeon
--
-- Core/Piles.lua caches a pile's word the first time it is asked for, so the
-- run that proves the cache is not a one-way door is the second one, under a
-- different name.
----------------------------------------------------------------------

Session.Clear()
zone = "Dire Maul"
Session.Start()
loot("Tattered Cloth", 3)

local second = pile("session")
check(second ~= nil and second.name == zone,
	("the second session is headed %s and the zone is %s")
		:format(tostring(second and second.name), zone))
check(second and named(second, "Tattered Cloth") ~= nil,
	"the second session did not pick up what was looted into it")

----------------------------------------------------------------------
-- The scene, put back
----------------------------------------------------------------------

Session.Clear()
put(5, nil, 1)
put(6, nil, 1)
CARRIED[1][5], CARRIED[1][6] = nil, nil
refill()
_G.GetZoneText = nil
