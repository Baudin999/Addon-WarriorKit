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
-- **The server says what you got, and that is the whole of the record.** Every
-- item here came out of a CHAT_MSG_LOOT sentence, which is append only: a
-- message says twelve Runecloth reached you and twelve goes in the table.
--
-- It was a diff of your bags first, and that is worth writing down because it
-- is the mistake anybody would make again. Two photographs of your bags, one
-- subtracted from the other, is a reconstruction rather than a reading, and the
-- reconstruction is only as good as the worse photograph. Walking into Uldaman
-- the bags read short for a frame, forty ids fell out of the baseline, and the
-- pile filled with everything the character had walked in carrying. Two guards
-- went on it and it stayed a shape where a third hole was possible.
--
-- A message cannot do that. There is nothing to compare against and no state to
-- corrupt, so the worst a bad evening costs is one message missed rather than
-- thirty two invented. The count it carries is exact rather than inferred.
--
-- **What that gives up.** Loot, quest rewards and anything you craft all still
-- count, because the server sends a sentence for each and Core/Loot.lua reads
-- all three. Something traded to you, pulled out of a mailbox or bought from a
-- vendor does not, because no sentence is sent. That is the right way round for
-- what this is for: on a boost you are the one looting.
--
-- The other thing it gives up is the few seconds of a reload, where nothing is
-- listening. The diff had no blind window because it compared against stored
-- counts. You are not looting during your own reload, and a rare item missed is
-- the cheaper side of that trade by a wide margin.
--
-- **This client will not tell two stacks apart, and the pile does not pretend
-- otherwise.** There is no per-item identity in a container on 2.5: the only
-- thing a bag slot can be asked is which item it holds. So eight Runecloth you
-- carried in and twelve you looted are one stack of twenty that no call can
-- split, and the square is drawn once in the session pile with the twelve the
-- server said written in its top corner. That number is exact. Which physical
-- stack it belongs to cannot be answered by anything, here or elsewhere.
--
-- **Stop and clear are two presses.** Stop means stop adding, and the pile
-- stays exactly as it is while you ride to town and work through it. Clear
-- empties it, and starting a new session clears it for you, so the only time
-- anybody has to press clear is when they want the pile gone early.
--
-- The record is this character's, in ns.dbc. What one character carried out of
-- Scholomance is not a preference and it is not the other one's business.
--------------------------------------------------------------------------

-- What the pile is called when you did not say and the client would not either.
local UNNAMED = "Session"

--------------------------------------------------------------------------

-- The record, with the ledger under it made on first use.
--
-- Lazily rather than out of a defaults table, for the reason Core/Core.lua
-- gives at ns.DefaultCopy: a default is copied one level deep, so a nested
-- table registered there would be handed out shared and every character would
-- be writing into the same one.
--
-- `held` is dropped where an older record still carries it. It was the bag
-- counts the diff compared against, nothing reads it now, and a saved variable
-- is written back whole at every logout, so a key left behind sits in the file
-- forever looking like state. Core/Core.lua retires a whole setting the same
-- way and says why at its own list.
local function Record()
	local held = ns.dbc and ns.dbc.bagSession
	if type(held) ~= "table" then
		return nil
	end
	if type(held.items) ~= "table" then
		held.items = {}
	end
	held.held = nil
	return held
end

--------------------------------------------------------------------------
-- The record
--------------------------------------------------------------------------

-- One loot sentence, and what it says added to the pile.
--
-- Only your own. `who` is nil when the server was talking about you, and a
-- pile in your bags cannot hold the sword somebody else in the group won.
--
-- Added rather than written, because an item drops more than once in an hour:
-- twelve cloth arriving in three separate stacks reads twelve.
function Session.Heard(text)
	local record = Record()
	if not record or not record.running then
		return false
	end
	local who, link, count = ns.LootLine.Read(text)
	if who or not link then
		return false
	end
	local id = ns.ItemKind(link)
	if not id then
		return false
	end
	record.items[id] = (record.items[id] or 0) + count
	-- The window, because the square that just changed pile is the one you are
	-- looking at. It returns early on a window nobody has open, so a character
	-- who never opens their bags pays nothing for this line.
	ns.BagsWindow.Refresh()
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
	Label(record)
	return true
end

function Session.Stop()
	local record = Record()
	if not record or not record.running then
		return false, "no session is running"
	end
	-- Nothing to catch up on. A sentence is recorded the moment it arrives, so
	-- the pile is already whatever the last pull put in it. The diff this
	-- replaced took one final scan here, because a bag update it had not
	-- answered yet was a real thing to miss.
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
-- CHAT_MSG_LOOT is the server telling you what you got, and it is the only
-- source here. It arrives whether or not the bag window is open, which is the
-- case that matters, because nobody walks a dungeon with their bags up.
--
-- PLAYER_LOGIN is the heading. A session survives a logout, and the pile it
-- draws into is Core/Piles.lua's, which starts every session called Session
-- until somebody tells it what last night's was called.
--------------------------------------------------------------------------

local function Wake(_, event, text)
	if event == "PLAYER_LOGIN" then
		Label(Record())
		return
	end
	Session.Heard(text)
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_LOOT")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", Wake)
