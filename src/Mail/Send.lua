local ADDON, ns = ...

local Send = {}
ns.MailSend = Send

--------------------------------------------------------------------------
-- Getting the letter out
--
-- Mail/Draft.lua says what is being sent and how many mails that divides into.
-- This is the conversation with the server: fill the client's own form, send
-- it, wait for the server to say it went, fill it again.
--
-- **Why it is a state machine and not a loop.** A mail is not sent when
-- SendMail returns. The attachments leave your bags, the server thinks about
-- it, and MAIL_SEND_SUCCESS arrives some time later with the form now empty. A
-- loop that filled the form three times in one frame would put thirty six items
-- into twelve slots and lose twenty four of them. So there is exactly one mail
-- in flight and the next one starts when the server has finished with the last.
--
-- **How an item gets onto the form.** UseContainerItem, with the send pane
-- flagged as showing. That is the same call that sells a grey at a merchant and
-- eats a bread roll anywhere else, and the flag is what decides which: this is
-- the shape Baganator/Transfers/AddToMail.lua uses on this exact client, and
-- SetSendMailShowing is what it sets first.
--
-- The pick-up-and-click route is the other way to do it, and it is worse here.
-- It puts an item on the cursor, which means a failure halfway leaves the
-- player holding a stack of ore in the middle of a window, and it needs the
-- attachment slot chosen by hand. UseContainerItem picks the first free slot
-- itself and never touches the cursor.
--
-- **Every slot is resolved again at send.** Draft holds a link and the bag slot
-- it was dropped from, and both are checked before anything moves: the slot has
-- to still hold that same link, and if it does not the bags are rescanned for
-- one that does. An item that has genuinely gone is counted and reported rather
-- than silently replaced by whatever is in that slot now, which is the failure
-- Comfort/Destroy.lua is built around and is worse here.
--
-- **There is no timeout and that is deliberate.** A stalled send waits, the
-- window says which mail of how many it is waiting on, and there is a stop
-- button under it. The alternative is an OnUpdate, and an OnUpdate is a ticker
-- this addon would then have to defend forever, for a case that is a server not
-- answering. MAIL_FAILED and the mailbox closing both end it on their own.
--------------------------------------------------------------------------

-- Nothing, one in flight, or finished. `done` counts mails the server has
-- confirmed, so "2 of 3" is a fact rather than a hope.
local running, at, done, total = false, 0, 0, 0
local missing, note = 0, ""

--------------------------------------------------------------------------
-- The client's own form
--------------------------------------------------------------------------

-- Whether the attachment slot at this index is holding something. The itemID is
-- the second return and is the one that is nil for an empty slot; the name is
-- not, on an item the client has not cached.
local function Occupied(index)
	local ask = _G.GetSendMailItem
	if type(ask) ~= "function" then
		return nil
	end
	local ok, _, itemId = pcall(ask, index)
	if not ok then
		return nil
	end
	return itemId ~= nil
end

-- The first free attachment slot, or nil when the form is full. Nil is also
-- what a client with no GetSendMailItem answers, and a send that cannot see the
-- form is a send that must not start.
local function FreeSlot()
	for index = 1, ns.MailDraft.PerMail() do
		local held = Occupied(index)
		if held == nil then
			return nil
		end
		if not held then
			return index
		end
	end
	return nil
end

-- How many of the twelve are already taken. Anything at all here before the
-- first mail goes is the player's own half-built form in Blizzard's window, and
-- sending it would be sending something they did not put on ours.
local function Loaded()
	local count = 0
	for index = 1, ns.MailDraft.PerMail() do
		if Occupied(index) then
			count = count + 1
		end
	end
	return count
end

-- The flag that decides what UseContainerItem does. Raised before every fill,
-- which is what Baganator does.
--
-- It used to be raised and left, and that was defensible until a right click in
-- the bags meant something. With the flag up, a bag click the addon did not
-- catch attaches to the client's own form, and that form is parked off the side
-- of the screen: the item leaves your bags and lands on an invisible letter
-- nobody is going to send. So a run that has finished puts it back down. The
-- claim is only about the runs this file drives, which is the only thing it
-- knows anything about.
local function Showing(state)
	local tell = _G.SetSendMailShowing
	if type(tell) ~= "function" then
		return false
	end
	return pcall(tell, state)
end

--------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------

-- Where this attachment is now, or nil. The slot it was dropped from first,
-- because that is nearly always still right and costs one lookup; a rescan
-- after, because a bag that moved is the ordinary case rather than the
-- exception.
local function Locate(entry)
	if ns.ContainerItemLink(entry.bag, entry.slot) == entry.link then
		return entry.bag, entry.slot
	end
	return ns.MailDraft.Slot(entry.link)
end

-- One attachment onto the form. False and a reason, so the caller can count
-- what did not make it rather than believing the mail is complete.
local function Put(entry)
	local bag, slot = Locate(entry)
	if not bag then
		return false
	end

	-- A locked slot is a move the server has not finished. Sending it would ask
	-- the client to do two things with one stack, so it is left where it is and
	-- counted, the same as one that has gone.
	local _, locked = ns.ContainerItem(bag, slot)
	if locked then
		return false
	end

	local index = FreeSlot()
	if not index then
		return false
	end
	if not ns.UseContainerItem(bag, slot) then
		return false
	end
	return Occupied(index) and true or false
end

local function Fill(which)
	local batch = ns.MailDraft.Batch(which)
	local placed, lost = 0, 0
	for index = 1, #batch do
		if Put(batch[index]) then
			placed = placed + 1
		else
			lost = lost + 1
		end
	end
	return placed, lost
end

--------------------------------------------------------------------------
-- One mail
--------------------------------------------------------------------------

local function Stop(why)
	running, at = false, 0
	note = why or note
	Showing(false)
	return false
end

local function Post(which)
	local Draft = ns.MailDraft
	local post = _G.SendMail
	if type(post) ~= "function" then
		return Stop("this client has no SendMail")
	end

	Showing(true)
	local placed, lost = Fill(which)
	missing = missing + lost

	local money = Draft.MoneyOn(which)
	if money > 0 and type(_G.SetSendMailMoney) == "function" then
		pcall(_G.SetSendMailMoney, money)
	end

	if placed == 0 and money == 0 and Draft.Body() == "" then
		return Stop("nothing of that mail is still in your bags")
	end

	at = which
	if not pcall(post, Draft.To(), Draft.SubjectFor(which), Draft.Body()) then
		return Stop("the client refused the send")
	end
	note = ("mail %d of %d is with the server"):format(which, total)
	return true
end

--------------------------------------------------------------------------
-- The run
--------------------------------------------------------------------------

function Send.Start()
	if running then
		return false, "a send is already going"
	end

	local why = ns.MailDraft.Problem()
	if why then
		return false, why
	end

	local already = Loaded()
	if already > 0 then
		return false, ("%d items are already on the client's own mail form"):format(already)
	end

	running, done, missing = true, 0, 0
	total = ns.MailDraft.Mails()
	note = ""
	if not Post(1) then
		return false, note
	end
	return true
end

function Send.Stop()
	if not running then
		return false
	end
	Stop("stopped after " .. done .. " of " .. total)
	return true
end

function Send.Running()
	return running
end

function Send.Progress()
	return done, total
end

function Send.Missing()
	return missing
end

function Send.Note()
	return note
end

-- What a mail window puts under its send button, and what `/wk status` says.
function Send.Describe()
	if running then
		return ("sending %d of %d"):format(at, total)
	end
	if note == "" then
		return "nothing sent yet"
	end
	if missing > 0 then
		return ("%s, %d left in your bags"):format(note, missing)
	end
	return note
end

--------------------------------------------------------------------------

-- The server's answer. Success advances; failure stops and keeps the reason,
-- because a mail that failed has left its attachments on the client's form and
-- carrying on would send them to whoever the next mail is for.
--
-- MAIL_CLOSED ends a run whatever it was doing. Walking away from the mailbox
-- is the player saying stop, and every call below it would be refused anyway.
local function OnEvent(_, event)
	if not running then
		return
	end
	if event == "MAIL_SEND_SUCCESS" then
		done = done + 1
		if done >= total then
			Stop(("sent %d %s"):format(total, total == 1 and "mail" or "mails"))
			ns.MailDraft.Clear()
		else
			Post(done + 1)
		end
	elseif event == "MAIL_FAILED" then
		Stop(("mail %d of %d was refused, the rest is still in your bags"):format(at, total))
	elseif event == "MAIL_CLOSED" then
		Stop("the mailbox closed part way through")
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_SEND_SUCCESS")
events:RegisterEvent("MAIL_FAILED")
events:RegisterEvent("MAIL_CLOSED")
events:SetScript("OnEvent", OnEvent)
