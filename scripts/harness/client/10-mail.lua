-- The mailbox
--
-- Enough of one to stand the mail window up and drive a send through it. The
-- two halves are modelled rather than stubbed away, because both of them are
-- where the part can be wrong in a way no amount of reading it would show.
--
-- The outbox is a form with twelve slots that UseContainerItem fills, which is
-- how the client really attaches an item and is what Baganator does on this
-- client. A stub that took an attachment straight off a list would make the
-- split into several mails pass without the form ever having been full.
--
-- The send is asynchronous, and that is the point of it. SendMail here records
-- the mail and answers nothing; MAIL_SEND_SUCCESS arrives when a section says
-- so. A stub that fired it from inside SendMail would run the addon's own
-- handler with Post still on the stack, which is a shape the game never
-- produces and would hide the one thing the state machine is for.
--
-- The inbox renumbers when a message is taken, because that is the failure the
-- sweep is written against: taking message three moves four to three, and a
-- sweep walking upwards would skip every other one.

local H = ...
local region, ITEMS = H.region, H.ITEMS
local CARRIED, carrying, itemLink = H.CARRIED, H.carrying, H.itemLink

local POSTAGE = 30

_G.ATTACHMENTS_MAX_SEND = 12

--------------------------------------------------------------------------
-- The form
--------------------------------------------------------------------------

-- One entry per filled slot: the item's name, and the bag slot it came out of
-- so a take can be undone by a section that wants the bags back.
local form = { money = 0, showing = false }

local function FreeSlot()
	for index = 1, _G.ATTACHMENTS_MAX_SEND do
		if not form[index] then
			return index
		end
	end
	return nil
end

local function Wipe()
	for index = 1, _G.ATTACHMENTS_MAX_SEND do
		form[index] = nil
	end
	form.money = 0
end

_G.SetSendMailShowing = function(showing)
	form.showing = showing and true or false
end

_G.SetSendMailMoney = function(copper)
	form.money = copper or 0
end

_G.GetSendMailPrice = function()
	return POSTAGE
end

-- Name, id, texture, count, quality, in the order the client answers them. The
-- id is the second and is the one the addon tests, because a name is nil on an
-- item this client has not cached and an id never is.
_G.GetSendMailItem = function(index)
	local held = form[index]
	if not held then
		return nil
	end
	local item = ITEMS[held.name]
	return held.name, item.id, item.icon, held.count, item.quality
end

-- The call that decides everything. With the send pane flagged as showing it
-- attaches; without it, whatever 04-hands installed still sells or misuses.
local Use = _G.UseContainerItem
_G.UseContainerItem = function(bag, slot)
	if not form.showing then
		return Use(bag, slot)
	end
	local held = carrying(bag, slot)
	local index = held and FreeSlot()
	if not index then
		return
	end
	form[index] = { name = held, count = 1, bag = bag, slot = slot }
	CARRIED[bag][slot] = false
end

--------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------

-- Every mail this session has posted, in order, each carrying what was on the
-- form when it went. A section reads these back rather than watching the bags,
-- because "twenty items reached two mails, twelve and eight" is the claim and
-- the bags cannot say which mail anything landed in.
local sent = {}
local pending = false
local refuse = false

_G.SendMail = function(recipient, subject, body)
	local mail = { to = recipient, subject = subject, body = body,
		money = form.money, items = {} }
	for index = 1, _G.ATTACHMENTS_MAX_SEND do
		if form[index] then
			mail.items[#mail.items + 1] = form[index].name
		end
	end
	sent[#sent + 1] = mail
	pending = true
end

-- The server's answer, delivered by a section rather than by the call above.
-- Success empties the form the way the client does; a refusal leaves it exactly
-- as it was, which is the state the addon must not send on top of.
local function deliver()
	if not pending then
		return false
	end
	pending = false
	if refuse then
		H.fire("MAIL_FAILED")
		return true
	end
	Wipe()
	H.fire("MAIL_SEND_SUCCESS")
	return true
end

--------------------------------------------------------------------------
-- The inbox
--------------------------------------------------------------------------

-- Newest first, which is the order the client hands them over in. Each is a
-- sender, a subject, coin, a list of item names and how long is left.
local inbox = {}

_G.GetInboxNumItems = function()
	local items = 0
	for _, mail in ipairs(inbox) do
		items = items + #mail.items
	end
	return #inbox, items
end

_G.GetInboxHeaderInfo = function(index)
	local mail = inbox[index]
	if not mail then
		return nil
	end
	return "Interface\\Icons\\INV_Letter_15", nil, mail.sender, mail.subject,
		mail.money, mail.cod or 0, mail.days or 20, #mail.items, mail.read and 1 or nil
end

_G.GetInboxItem = function(index, slot)
	local mail = inbox[index]
	local name = mail and mail.items[slot]
	if not name then
		return nil
	end
	local item = ITEMS[name]
	return name, item.id, item.icon, 1, item.quality
end

_G.GetInboxItemLink = function(index, slot)
	local mail = inbox[index]
	local name = mail and mail.items[slot]
	return name and itemLink(name) or nil
end

_G.GetInboxText = function(index)
	local mail = inbox[index]
	return mail and mail.body or nil
end

-- Takes the coin and every attachment it has room for, and the message goes
-- when there is nothing left on it and nothing written in it. Both halves
-- matter: the addon's sweep counts down because taking renumbers, and it steps
-- past a message that would not empty because the bags filled.
local function Room()
	for bag = 0, 4 do
		for slot = 1, (CARRIED[bag] and #CARRIED[bag] or 0) do
			if not carrying(bag, slot) then
				return bag, slot
			end
		end
	end
	return nil
end

_G.AutoLootMailItem = function(index)
	local mail = inbox[index]
	if not mail then
		return
	end
	H.state.purse = H.state.purse + mail.money
	mail.money = 0
	while #mail.items > 0 do
		local bag, slot = Room()
		if not bag then
			break
		end
		CARRIED[bag][slot] = table.remove(mail.items, 1)
	end
	if mail.money == 0 and #mail.items == 0 and not mail.body then
		table.remove(inbox, index)
	end
	H.fire("MAIL_INBOX_UPDATE")
end

_G.DeleteInboxItem = function(index)
	if inbox[index] then
		table.remove(inbox, index)
		H.fire("MAIL_INBOX_UPDATE")
	end
end

_G.ReturnInboxItem = _G.DeleteInboxItem

_G.CloseMail = function()
	H.fire("MAIL_CLOSED")
end

--------------------------------------------------------------------------
-- The friends list, and the frame the client would have drawn
--------------------------------------------------------------------------

local friends = {}

_G.GetNumFriends = function()
	return #friends
end

_G.GetFriendInfo = function(index)
	return friends[index], 60, "Warrior", "Ironforge", true
end

_G.MailFrame = region("frame")
_G.MailFrame:Show()

H.mail = {
	form = form, sent = sent, inbox = inbox, friends = friends,
	deliver = deliver,
	refuse = function(value) refuse = value and true or false end,
	pending = function() return pending end,
	POSTAGE = POSTAGE,
}
