local ADDON, ns = ...

local Inbox = {}
ns.MailInbox = Inbox

--------------------------------------------------------------------------
-- What is waiting
--
-- The other half of a mailbox. One row per message: who it is from, what it is
-- called, what is on it and how long you have got.
--
-- **The sender is coloured the same three ways the recipient field is.** That
-- is most of what this is for. An inbox of forty messages after a night of
-- auctions is a wall of identical white text, and the two lines in it you
-- actually want are the one from your wife and the one from your bank alt.
-- Mail/Who.lua already answers which is which for the send side, and the
-- question does not change direction.
--
-- **Taking is a sweep and the sweep counts down.** AutoLootMailItem takes the
-- money and every attachment off one message in one call, and a message with
-- nothing left on it and no text is then deleted by the server. That renumbers
-- the inbox. Walking upwards from one would then skip every other message,
-- which is the classic way to write this wrongly; walking down from the end
-- cannot, because deleting message seven moves nothing below seven.
--
-- **A full bag stops it rather than losing anything.** TakeInboxItem on no free
-- slot fails quietly and the message stays where it is, so the honest thing is
-- to count the free slots first and say why the sweep stopped.
--
-- Nothing here is on a ticker. An inbox changes when the server says so, which
-- is MAIL_INBOX_UPDATE, and it changes when you press something, which is a
-- gesture. Rows are built when somebody asks for them rather than held, because
-- the list is read on a draw and the draw is a moment.
--------------------------------------------------------------------------

-- Where the sweep is. Zero is not running, and it counts down.
local at, taken, note = 0, 0, ""

--------------------------------------------------------------------------
-- Reading it
--------------------------------------------------------------------------

function Inbox.Count()
	local ask = _G.GetInboxNumItems
	if type(ask) ~= "function" then
		return 0
	end
	local ok, count = pcall(ask)
	return (ok and tonumber(count)) or 0
end

-- One message's attachments, as icons and counts. Capped at the client's own
-- twelve, because that is as many as a mail can carry and a loop with no
-- ceiling on a client API is a loop that hangs on a client that answers oddly.
local function Attachments(index)
	local ask = _G.GetInboxItem
	local list = {}
	if type(ask) ~= "function" then
		return list
	end
	for slot = 1, ns.MailDraft.PerMail() do
		local ok, name, _, texture, count = pcall(ask, index, slot)
		if ok and name then
			list[#list + 1] = { name = name, icon = texture, count = count or 1, slot = slot }
		end
	end
	return list
end

-- Every message, newest first, which is the order the client already hands
-- them over in.
function Inbox.Rows()
	local rows = {}
	local ask = _G.GetInboxHeaderInfo
	if type(ask) ~= "function" then
		return rows
	end

	for index = 1, Inbox.Count() do
		local ok, package, stationery, sender, subject, money, cod, days,
			items, read = pcall(ask, index)
		if ok and (sender or subject) then
			rows[#rows + 1] = {
				index = index,
				sender = sender or "",
				subject = (subject and subject ~= "" and subject) or "(no subject)",
				money = money or 0,
				cod = cod or 0,
				days = days or 0,
				items = items or 0,
				read = read and true or false,
				icon = package or stationery,
				attachments = Attachments(index),
			}
		end
	end
	return rows
end

-- Whether there is anything on this message to take. A read letter with no coin
-- and no attachments is a thing to delete rather than a thing to sweep, and the
-- sweep steps straight past it.
function Inbox.Holds(row)
	return (row.money or 0) > 0 or (row.items or 0) > 0
end

-- What a COD message wants before it will hand anything over. Sweeping past one
-- is deliberate: a sweep that pays bills is a sweep nobody would run twice.
function Inbox.Payable(row)
	return (row.cod or 0) == 0
end

--------------------------------------------------------------------------
-- Room to put it
--------------------------------------------------------------------------

function Inbox.FreeSlots()
	local free = 0
	for bag = 0, 4 do
		for slot = 1, ns.ContainerSlots(bag) do
			if not ns.ContainerItemLink(bag, slot) then
				free = free + 1
			end
		end
	end
	return free
end

--------------------------------------------------------------------------
-- The three things you can do to one
--------------------------------------------------------------------------

local function Call(name, ...)
	local go = _G[name]
	if type(go) ~= "function" then
		return false
	end
	return pcall(go, ...)
end

function Inbox.Take(index)
	return Call("AutoLootMailItem", index)
end

function Inbox.Delete(index)
	return Call("DeleteInboxItem", index)
end

function Inbox.Return(index)
	return Call("ReturnInboxItem", index)
end

--------------------------------------------------------------------------
-- The sweep
--------------------------------------------------------------------------

-- Which message the last take was aimed at and how much was on it, so a
-- message that does not empty cannot be asked again forever.
--
-- That is not a theoretical loop. A message carrying five items with two free
-- slots in your bags takes two and keeps three, and the free-slot check above
-- passed, because there was room for something. Asking again takes nothing and
-- changes nothing, and the sweep would sit on that message until the mailbox
-- closed. So a message whose load did not go down is stepped past and counted.
local aimed, held, stuck = 0, 0, 0

local function Halt(why)
	at = 0
	note = why or note
	return false
end

-- How much is on one message, as a single number: nought for a message with
-- nothing to take, and a value that must go down after a take that worked.
-- Money and a count of items added together, which is not a quantity of
-- anything and is not meant to be.
local function Load(index)
	local ask = _G.GetInboxHeaderInfo
	if type(ask) ~= "function" then
		return 0
	end
	local ok, _, _, _, _, money, cod, _, items = pcall(ask, index)
	if not ok or (cod or 0) > 0 then
		return 0
	end
	return (money or 0) + (items or 0)
end

-- The next message at or below the cursor that has something on it, or nil when
-- the sweep is finished. The header is read again on every step rather than
-- trusted from before the last take, because taking is what renumbers the
-- inbox.
local function Next()
	while at > 0 do
		local load = Load(at)
		if load > 0 and at == aimed and load >= held then
			stuck = stuck + 1
		elseif load > 0 then
			return at, load
		end
		at = at - 1
	end
	return nil
end

local function Finished()
	local said = ("took %d %s"):format(taken, taken == 1 and "message" or "messages")
	if stuck > 0 then
		said = said .. (", %d would not empty"):format(stuck)
	end
	return Halt(said)
end

local function Step()
	local index, load = Next()
	if not index then
		return Finished()
	end
	if Inbox.FreeSlots() < 1 then
		return Halt(("your bags are full, %d taken"):format(taken))
	end
	if not Inbox.Take(index) then
		return Halt("this client will not take a message for you")
	end
	aimed, held = index, load
	taken = taken + 1
	return true
end

function Inbox.Sweep()
	if at > 0 then
		return false, "a sweep is already going"
	end
	local count = Inbox.Count()
	if count == 0 then
		return false, "there is nothing in your mailbox"
	end
	at, taken, note = count, 0, ""
	aimed, held, stuck = 0, 0, 0
	return Step()
end

function Inbox.Sweeping()
	return at > 0
end

function Inbox.Stop()
	if at == 0 then
		return false
	end
	Halt(("stopped after %d"):format(taken))
	return true
end

--------------------------------------------------------------------------
-- Saying what is there
--------------------------------------------------------------------------

function Inbox.Waiting()
	local money, items = 0, 0
	local rows = Inbox.Rows()
	for index = 1, #rows do
		money = money + rows[index].money
		items = items + rows[index].items
	end
	return money, items
end

function Inbox.Describe()
	if at > 0 then
		return ("sweeping, %d taken"):format(taken)
	end
	local count = Inbox.Count()
	if count == 0 then
		return note ~= "" and note or "nothing in your mailbox"
	end
	local money, items = Inbox.Waiting()
	return ("%d waiting, %d attachments, %s"):format(count, items, ns.Coin(money))
end

--------------------------------------------------------------------------

-- One step per update from the server. The sweep never advances itself, which
-- is the whole reason it is safe: one take is in flight at a time and the
-- inbox has been renumbered by the time the next one is chosen.
local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_INBOX_UPDATE")
events:RegisterEvent("MAIL_CLOSED")
events:SetScript("OnEvent", function(_, event)
	if event == "MAIL_CLOSED" then
		if at > 0 then
			Halt("the mailbox closed part way through")
		end
		return
	end
	if at > 0 then
		Step()
	end
end)
