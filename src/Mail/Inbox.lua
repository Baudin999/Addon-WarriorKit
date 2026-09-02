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
-- **A full bag steps past a message rather than ending the sweep.** A take with
-- no free slot fails quietly and the message stays where it is, so the free
-- slots are counted first. Counted per message rather than once for the whole
-- sweep: an inbox after a night of auctions is mostly coin and a few stacks,
-- coin needs no room at all, and stopping dead on the first message carrying a
-- leftover stack leaves forty mails of gold sitting behind it. What was stepped
-- past is counted and said at the end.
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

-- Which message the last take was aimed at, how much was on it, and how many
-- times it has been asked again since, so a message that does not empty cannot
-- be asked forever and one that is merely slow is not given up on.
--
-- Neither of those is theoretical. A message carrying five items with two free
-- slots in your bags takes two and keeps three, and the free-slot count passed,
-- because there was room for something; asking again takes nothing and changes
-- nothing, and the sweep would sit on that message until the mailbox closed.
--
-- The other way round is the one that was wrong. MAIL_INBOX_UPDATE arrives when
-- the server has taken the coin off a message, which is before the attachment
-- has left it, so the first reading after a take on a message carrying one item
-- and no coin is the same reading as before the take. Giving up there marks an
-- ordinary auction mail as one that would not empty and steps past it, and an
-- inbox of forty of them ends with most of them still in it. So a message is
-- asked again a few times, and only a message that answers the same every time
-- is stepped past.
local PATIENCE = 4
local aimed, held, asked, stuck, full = 0, 0, 0, 0, 0

local function Halt(why)
	at = 0
	note = why or note
	return false
end

-- What is on one message: its coin and how many attachments. A COD message
-- answers nothing on purpose, so the sweep never aims at one.
local function Carrying(index)
	local ask = _G.GetInboxHeaderInfo
	if type(ask) ~= "function" then
		return 0, 0
	end
	local ok, _, _, _, _, money, cod, _, items = pcall(ask, index)
	if not ok or (cod or 0) > 0 then
		return 0, 0
	end
	return money or 0, items or 0
end

-- The next message at or below the cursor that has something on it and somewhere
-- for it to go, or nil when the sweep is finished. The header is read again on
-- every step rather than trusted from before the last take, because taking is
-- what renumbers the inbox.
--
-- The load a message is judged by is its coin and its item count added
-- together, which is not a quantity of anything and is not meant to be. It is
-- nought for a message with nothing to take and it has to go down after a take
-- that worked, and those are the only two things asked of it.
--
-- The bags are counted once here rather than once per message: the count is the
-- same for every message this pass, and a scan of five bags inside the loop is
-- that scan again for every message in a mailbox of fifty.
local function Next()
	local room = Inbox.FreeSlots()
	while at > 0 do
		local money, items = Carrying(at)
		local load = money + items
		-- A load of nought is an empty message or a COD, and neither is the
		-- sweep's business.
		if load > 0 then
			if items > 0 and room < 1 then
				full = full + 1
			elseif at ~= aimed or load < held then
				asked = 0
				return at, load
			elseif asked < PATIENCE then
				asked = asked + 1
				return at, load
			else
				stuck = stuck + 1
			end
		end
		at = at - 1
		asked = 0
	end
	return nil
end

local function Finished()
	local said = ("took %d %s"):format(taken, taken == 1 and "message" or "messages")
	if full > 0 then
		said = said .. (", %d needs a free bag slot"):format(full)
	end
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
	-- Aimed at before it is asked for, and counted only when the message is one
	-- the sweep has not already asked for. A retry and the second half of a
	-- part-taken message both come back at the index the last take was aimed at,
	-- and counting either of them would report more messages taken than the
	-- mailbox held.
	if index ~= aimed then
		taken = taken + 1
	end
	aimed, held = index, load
	if not Inbox.Take(index) then
		return Halt("this client will not take a message for you")
	end
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
	aimed, held, asked, stuck, full = 0, 0, 0, 0, 0
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
	local said = ("%d waiting, %d attachments, %s"):format(count, items, ns.Coin(money))
	-- Why the last sweep stopped, in front of what is still sitting there. A
	-- mailbox that is not empty after a sweep is the only case this sentence is
	-- read in anger, and it used to answer it by describing the mailbox and
	-- never saying why anything had been left in it.
	if note ~= "" then
		return note .. "; " .. said
	end
	return said
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
