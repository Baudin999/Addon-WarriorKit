local ADDON, ns = ...

local Session = {}
ns.BagsSession = Session

--------------------------------------------------------------------------
-- What you picked up between pressing record and pressing stop
--
-- One pile at the top of the bag window holding everything that reached your
-- bags while a session was running, so a dungeon run, a farming circuit or an
-- hour of boosting somebody comes out of the evening as a list you can work
-- through at a vendor instead of a bag you have to remember your way around.
--
-- **It is a button and not a place.** The first design started a run off
-- IsInInstance and stopped it at the door, and every edge of that was a guess
-- this addon cannot test: a wipe and a run back, a summon out for a repair, the
-- corpse walk through the portal. A press has no edges. It also stops being a
-- dungeon feature, which is the better half of the trade: press record before a
-- Thorium circuit in Un'Goro and the same pile answers the same question.
--
-- **It counts what entered your bags, not what a corpse held.** Every scan is
-- compared against the last one and an item whose total went up is an item you
-- gained. That is deliberately wider than loot: a green the person you were
-- boosting traded you, a quest reward, something you crafted on the spot and
-- anything you took out of a mailbox all count, because all of them are things
-- you came out of the hour holding and did not go in with. A vendor purchase
-- counts too, which is the one reading that is arguably wrong and is not worth
-- a rule: buying a stack of arrows mid-run and having it show up in the list of
-- what you collected is a smaller surprise than a green that silently did not.
--
-- **This client will not tell two stacks apart, and the pile does not pretend
-- otherwise.** There is no per-item identity in a container on 2.5: the only
-- thing a bag slot can be asked is which item it holds. So eight Runecloth you
-- carried in and twelve you looted are one stack of twenty that no call can
-- split, and the square is drawn once in the session pile with the total the
-- session actually recorded written under it. That number is the honest half.
-- Which physical stack it is cannot be answered by anything, here or elsewhere.
--
-- **Stop and clear are two presses.** Stop means stop adding, and the pile
-- stays exactly as it is while you ride to town and work through it. Clear
-- empties it, and starting a new session clears it for you, so the only time
-- anybody has to press clear is when they want the pile gone early.
--
-- The record is this character's, in ns.dbc. What one character carried out of
-- Scholomance is not a preference and it is not the other one's business.
--------------------------------------------------------------------------

-- The backpack and the four on the belt, which is Bags/Bags.lua's five and the
-- same reason: this counts what you are carrying, and the bank is not that.
local FIRST_BAG, LAST_BAG = 0, 4

-- What the pile is called when you did not say and the client would not either.
local UNNAMED = "Session"

-- One table, refilled on every scan.
--
-- A bag update arrives five times for one loot and each of them recounts the
-- five bags whether or not the window is open, which is the price of a record
-- that is right when you finally do open it. Wiped and refilled rather than
-- rebuilt, so a session running all evening allocates this once.
local counts = {}

--------------------------------------------------------------------------

-- The record, with the two maps under it made on first use.
--
-- Lazily rather than out of a defaults table, for the reason Core/Core.lua
-- gives at ns.DefaultCopy: a default is copied one level deep, so a nested
-- table registered there would be handed out shared and every character would
-- be writing into the same one.
local function Record()
	local held = ns.dbc and ns.dbc.bagSession
	if type(held) ~= "table" then
		return nil
	end
	if type(held.items) ~= "table" then
		held.items = {}
	end
	if type(held.held) ~= "table" then
		held.held = {}
	end
	return held
end

-- Every item in the five bags and how many of it there are, by item id.
--
-- ns.ItemKind rather than a link comparison, because an id is what two stacks
-- of one item have in common and a link is not: a link carries the suffix and
-- the enchant, so two of the same green would count as two different things.
local function Count()
	wipe(counts)
	for bag = FIRST_BAG, LAST_BAG do
		for slot = 1, ns.ContainerSlots(bag) do
			local link = ns.ContainerItemLink(bag, slot)
			local id = link and ns.ItemKind(link)
			if id then
				counts[id] = (counts[id] or 0) + (ns.ContainerItem(bag, slot) or 1)
			end
		end
	end
	return counts
end

-- The counts this scan found, over the top of the ones the last scan left.
--
-- Over the top rather than in place of, which is the whole correctness of this
-- file and is the second thing it did. Emptying the baseline and refilling it
-- from the scan is right on a bag the client will answer for and catastrophic
-- on one it will not: an item missing from a single scan comes back on the next
-- one looking like a hundred and sixty one arrows you have just picked up.
--
-- The loading screen into a dungeon is exactly that. Press record at the
-- meeting stone, walk in, and for a frame the bags read short; forty ids fall
-- out of the baseline, and the pile fills with everything you walked in
-- carrying. That is what this shipped doing, on the first real run.
--
-- So an id this scan did not see keeps whatever it had. An id it did see is
-- written down at what it reads now, in both directions, because a stack that
-- is genuinely smaller than it was has genuinely been sold or eaten.
local function Keep(held, now)
	for id, count in pairs(now) do
		held[id] = count
	end
end

--------------------------------------------------------------------------
-- The record
--------------------------------------------------------------------------

-- One scan, and everything that went up since the last one added to the pile.
--
-- Only a rise counts. Selling, eating, mailing and equipping all take the count
-- down and none of them is a thing you collected, and the baseline follows a
-- present item down so that re-looting something you sold in there is recorded
-- the second time as well as the first.
--
-- The count added is the whole of the rise rather than the stack's size, so
-- twelve cloth arriving in three separate stacks over an hour reads twelve.
--
-- The cost of the rule above Keep is one honest under-count: an item you sold
-- or drank every last one of and then looted again is not recorded the second
-- time, because nothing here distinguishes that from a stack the client could
-- not read. Missing a potion is a smaller wrong answer than filing the whole
-- bag under Uldaman.
--
-- **A stack on the cursor is the same failure wearing a different hat.** Pick
-- twelve out of a stack of twenty and the bags hold eight, which is a true
-- reading of a real removal, so the baseline follows it down and putting them
-- back reads as twelve arriving. Nothing here can tell that from a sale, so no
-- scan is taken at all while the cursor is holding something. Bags/Stack.lua
-- refuses to start for the same reason and says so at its own guard.
function Session.Take()
	local record = Record()
	if not record or not record.running then
		return false
	end
	if GetCursorInfo() then
		return false
	end
	local now = Count()
	local items, held = record.items, record.held
	for id, count in pairs(now) do
		local was = held[id] or 0
		if count > was then
			items[id] = (items[id] or 0) + (count - was)
		end
	end
	Keep(held, now)
	return true
end

--------------------------------------------------------------------------
-- Starting, stopping and forgetting
--------------------------------------------------------------------------

-- Where you are standing, which is what the pile is called unless you said
-- otherwise. GetZoneText is the zone in your own language and inside an
-- instance it is the instance, which is exactly the word you want on the
-- heading. Nothing at all on a client that answers an empty string, and the
-- fallback is a heading that says Session rather than one that says nothing.
local function Where()
	if type(_G.GetZoneText) ~= "function" then
		return nil
	end
	local ok, zone = pcall(_G.GetZoneText)
	if ok and type(zone) == "string" and zone ~= "" then
		return zone
	end
	return nil
end

-- The heading, pushed into Core/Piles.lua. Called wherever the name changes
-- rather than on every scan, because it is a string that changes twice a run.
local function Label(record)
	ns.Piles.Rename(ns.Piles.SESSION, record and record.name or nil)
end

function Session.Start(name)
	local record = Record()
	if not record then
		return false, "this character's saved variables are not loaded yet"
	end
	wipe(record.items)
	record.name = (type(name) == "string" and name ~= "") and name or Where() or UNNAMED
	record.running = true
	-- The baseline first and the flag second would be the same thing here, but
	-- the order matters if anything ever scans between them: a session that is
	-- running with no baseline behind it counts your whole bag as a gain.
	--
	-- Emptied and refilled, which is the one place that is safe to do it. This
	-- is a press somebody made while standing still with their bags in front of
	-- them, not a scan off an event that may have caught the client mid-stride,
	-- and it has to forget the last session's counts rather than sit on top of
	-- them. Every other write to the baseline goes through Keep.
	wipe(record.held)
	Keep(record.held, Count())
	Label(record)
	return true
end

function Session.Stop()
	local record = Record()
	if not record or not record.running then
		return false, "no session is running"
	end
	-- One last scan, so whatever arrived between the final bag update and the
	-- press is in the pile. The press is usually the thing you do straight
	-- after the last pull, and that pull is exactly what would be missing.
	Session.Take()
	record.running = false
	return true
end

-- The pile emptied and its heading put back. Stopping first, because a clear
-- while a session is running would otherwise leave it recording into a pile
-- with no name and no explanation of where the last hour went.
function Session.Clear()
	local record = Record()
	if not record then
		return false, "this character's saved variables are not loaded yet"
	end
	record.running = false
	record.name = nil
	wipe(record.items)
	wipe(record.held)
	Label(record)
	return true
end

--------------------------------------------------------------------------
-- What the rest of the part asks
--------------------------------------------------------------------------

-- Whether this item belongs in the session pile.
--
-- The two cheap refusals come first on purpose. This is asked once per occupied
-- bag slot on every scan, and a character who has never pressed record must not
-- pay a call to the client's item database a hundred and fifty times a loot to
-- be told so.
function Session.Holds(link)
	if type(link) ~= "string" then
		return false
	end
	local record = ns.dbc and ns.dbc.bagSession
	if type(record) ~= "table" or type(record.items) ~= "table" then
		return false
	end
	if next(record.items) == nil then
		return false
	end
	local id = ns.ItemKind(link)
	return id ~= nil and record.items[id] ~= nil
end

-- How many of this item the session recorded, which is the number the square
-- carries. Nothing at all for an item no session put there.
function Session.Gained(link)
	if not Session.Holds(link) then
		return nil
	end
	return ns.dbc.bagSession.items[ns.ItemKind(link)]
end

function Session.Running()
	local record = ns.dbc and ns.dbc.bagSession
	return type(record) == "table" and record.running == true
end

function Session.Name()
	local record = ns.dbc and ns.dbc.bagSession
	return (type(record) == "table" and record.name) or nil
end

-- How many different items the pile holds and how many of them altogether. Two
-- numbers because they answer two questions: how long the list is, and how much
-- came out of the hour.
function Session.Held()
	local record = ns.dbc and ns.dbc.bagSession
	if type(record) ~= "table" or type(record.items) ~= "table" then
		return 0, 0
	end
	local kinds, total = 0, 0
	for _, count in pairs(record.items) do
		kinds = kinds + 1
		total = total + count
	end
	return kinds, total
end

-- The label on the button and on the panel's press, which is the state it is in
-- rather than the thing it will do. A button saying stop while nothing is
-- recording is a button nobody presses twice.
function Session.Label()
	return Session.Running() and "stop" or "record"
end

-- The press, wherever it came from: the window's title bar, the settings page
-- or the slash word. One place, so the sentence a press prints is written once.
function Session.Press()
	if Session.Running() then
		local kinds, total = Session.Held()
		Session.Stop()
		ns.Print(("stopped recording %s. %d item%s, %d in all.")
			:format(Session.Name() or UNNAMED, kinds, kinds == 1 and "" or "s", total))
	else
		Session.Start()
		ns.Print(("recording what you pick up in %s."):format(Session.Name() or UNNAMED))
	end
	ns.BagsWindow.Refresh()
	return true
end

-- The press that empties the pile, wherever it came from. Its own wrapper for
-- the reason Press has one: a press is something somebody is waiting for an
-- answer to, and the sentence it prints is written once.
function Session.Forget()
	local kinds, total = Session.Held()
	local name = Session.Name() or UNNAMED
	Session.Clear()
	if kinds == 0 then
		ns.Print("there was nothing recorded to forget.")
	else
		ns.Print(("forgot %s: %d item%s, %d in all.")
			:format(name, kinds, kinds == 1 and "" or "s", total))
	end
	ns.BagsWindow.Refresh()
	return true
end

function Session.Describe()
	local kinds, total = Session.Held()
	if Session.Running() then
		return ("recording %s, %d item%s so far")
			:format(Session.Name() or UNNAMED, kinds, kinds == 1 and "" or "s")
	end
	if kinds == 0 then
		return "not recording, and nothing is held"
	end
	return ("not recording, holding %d item%s of %s, %d in all")
		:format(kinds, kinds == 1 and "" or "s", Session.Name() or UNNAMED, total)
end

--------------------------------------------------------------------------
-- What makes it count
--
-- BAG_UPDATE is the one event that fires for every way an item can reach you,
-- which is the whole reason the record is a bag diff rather than a reading of
-- the loot messages: a trade, a mailbox and a crafting window all move
-- something into a bag and only one of the three says anything in chat. It
-- fires while the window is shut, which is the case that matters, because
-- nobody has their bags open walking through a dungeon.
--
-- PLAYER_LOGIN is the heading. A session survives a logout, and the pile it
-- draws into is Core/Piles.lua's, which starts every session called Session
-- until somebody tells it what last night's was called.
--------------------------------------------------------------------------

local function Wake(_, event)
	if event == "PLAYER_LOGIN" then
		Label(Record())
		return
	end
	Session.Take()
end

local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", Wake)
