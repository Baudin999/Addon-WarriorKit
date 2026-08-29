local ADDON, ns = ...

local Draft = {}
ns.MailDraft = Draft

--------------------------------------------------------------------------
-- The letter you are writing
--
-- A recipient, a subject, a body, some coin and a list of things out of your
-- bags. Nothing here draws and nothing here talks to the server: this is what
-- the window edits and what Mail/Send.lua walks, and keeping the two apart is
-- what lets one mail of twelve items and three mails of twelve be the same
-- object with a different length.
--
-- **Twelve is the client's number, not ours.** A mail carries twelve
-- attachments and there is no argument to be had with that. What the client
-- then does is make twelve the number *you* have to think in: you fill a form,
-- send it, walk back to the bag, fill it again. So the list here has no such
-- limit and Draft.Mails divides. Thirty six is the cap, which is three mails
-- and about as much as anybody moves in one go; past that the postage is
-- noticeable and you would want to know rather than find out.
--
-- **An attachment is a link, not a bag slot.** The bags move while a window is
-- open: something loots, a stack splits, the vendor sweep sells and every slot
-- after it shifts by one. A list of slot numbers taken thirty seconds ago is a
-- list pointing at whatever is in those slots now, which is the failure the
-- clutter window is built around and is worse here, because the wrong item goes
-- to somebody else's mailbox rather than to nowhere. So a slot is resolved
-- twice: once when you drop, to say what you dropped, and again at send, by
-- Mail/Send.lua, against the link this recorded.
--
-- There are two ways on and they differ in what they know. A right click in the
-- bags landed on one square and names it, which is Draft.AttachSlot; a drop
-- carries an item and no slot at all, so Draft.Attach has to go looking for the
-- first stack of it that is not already spoken for. The click is the exact one
-- and the drop is the one that has to guess, which is why the third stack of
-- ore you point at is the third stack that goes.
--
-- **The subject writes itself.** Sending gold titles the mail "money" and
-- sending one thing titles it after that thing, because that is what you would
-- have typed and because an inbox of mails called nothing is an inbox you have
-- to open one at a time. A subject you type wins over both, always; a split
-- send numbers the parts so three mails that arrive together can be told apart.
--
-- **What "risky" means.** Value on the mail and a recipient who is not on your
-- favourites list. Not "a stranger": a guild bank alt you mail every week is a
-- stranger by relation and is exactly who you meant, and an alt the addon knows
-- about but you have never mailed is not. The list is the thing you curated, so
-- the list is what the warning is measured against. Mail/Window.lua is what
-- draws the warning and what makes you press twice.
--------------------------------------------------------------------------

-- What one mail holds. ATTACHMENTS_MAX_SEND is the client's own constant and is
-- read where it exists, because a client that changes it changes this and
-- nothing here should have to be edited for that to be true.
local PER_MAIL = 12

-- The most this will hold at once, and the reason is in the header.
Draft.MAX = 36

-- The client's own field limits. A subject longer than this is silently cut by
-- the server, which turns "Copper Ore and 4 more (2/3)" into something that
-- stops mid-word, so the split suffix is fitted rather than appended.
local SUBJECT_MAX = 64
local BODY_MAX = 500

-- Postage, per mail. Read off the client where it will say, because it is 30
-- copper on one of these clients and per-item on older ones, and a total that
-- is wrong is worse than no total at all.
local POSTAGE = 30

local to, subject, body, money = "", "", "", 0
local attached = {}

--------------------------------------------------------------------------

function Draft.PerMail()
	local held = _G.ATTACHMENTS_MAX_SEND
	if type(held) == "number" and held >= 1 then
		return held
	end
	return PER_MAIL
end

function Draft.Postage()
	local ask = _G.GetSendMailPrice
	if type(ask) == "function" then
		local ok, price = pcall(ask)
		if ok and type(price) == "number" and price > 0 then
			return price
		end
	end
	return POSTAGE
end

--------------------------------------------------------------------------
-- The fields
--------------------------------------------------------------------------

function Draft.To()
	return to
end

function Draft.SetTo(name)
	to = type(name) == "string" and name or ""
	return to
end

function Draft.Subject()
	return subject
end

function Draft.SetSubject(text)
	subject = type(text) == "string" and text:sub(1, SUBJECT_MAX) or ""
	return subject
end

function Draft.Body()
	return body
end

function Draft.SetBody(text)
	body = type(text) == "string" and text:sub(1, BODY_MAX) or ""
	return body
end

function Draft.BodyMax()
	return BODY_MAX
end

function Draft.Money()
	return money
end

function Draft.SetMoney(copper)
	money = math.max(0, math.floor(tonumber(copper) or 0))
	return money
end

--------------------------------------------------------------------------
-- The attachments
--------------------------------------------------------------------------

function Draft.List()
	return attached
end

-- How many are on the list, or how many of one thing are. The second answer is
-- what tells a refused drop apart from an item that is not in your bags.
function Draft.Held(link)
	if not link then
		return #attached
	end
	local count = 0
	for index = 1, #attached do
		if attached[index].link == link then
			count = count + 1
		end
	end
	return count
end

function Draft.At(index)
	return attached[index]
end

-- Whether this bag slot is already on the list. Two stacks of the same item are
-- two attachments and both are wanted; the same stack twice is one attachment
-- and a slot that would come up empty at send.
local function Taken(bag, slot)
	for index = 1, #attached do
		local entry = attached[index]
		if entry.bag == bag and entry.slot == slot then
			return true
		end
	end
	return false
end

-- The first bag slot holding this link that is not already on the list. This is
-- how a drop is turned into a stack: the cursor says what you are carrying and
-- never says which slot it came out of, so the answer is the first one that
-- matches and is free.
function Draft.Slot(link)
	for bag = 0, 4 do
		for slot = 1, ns.ContainerSlots(bag) do
			if ns.ContainerItemLink(bag, slot) == link and not Taken(bag, slot) then
				return bag, slot
			end
		end
	end
	return nil
end

-- One bag slot onto the list, named by where it is rather than by what it is
-- in. This is the right click's way in and it is the more exact of the two: a
-- click landed on one square and that square is the stack that should go, where
-- a cursor carrying an item can only say what it is holding.
function Draft.AttachSlot(bag, slot)
	if #attached >= Draft.MAX then
		return nil, ("%d is as much as one send carries"):format(Draft.MAX)
	end

	local link = ns.ContainerItemLink(bag, slot)
	if type(link) ~= "string" then
		return nil, "there is nothing in that slot"
	end
	if Taken(bag, slot) then
		return nil, "that stack is already on the mail"
	end

	local name, icon = ns.ItemInfo(link)
	local count = ns.ContainerItem(bag, slot)
	attached[#attached + 1] = {
		link = link, name = name or "?", icon = icon,
		count = count or 1, bag = bag, slot = slot,
	}
	return #attached
end

function Draft.Attach(link)
	if type(link) ~= "string" then
		return nil, "that is not something you can mail"
	end
	if #attached >= Draft.MAX then
		return nil, ("%d is as much as one send carries"):format(Draft.MAX)
	end

	local bag, slot = Draft.Slot(link)
	if not bag then
		-- Two different failures and they need two different sentences. The
		-- item is not in your bags at all, or every stack of it is already on
		-- the mail, and "that stack is already on the mail" said for the first
		-- one sends somebody looking at a list that does not hold it.
		if Draft.Held(link) > 0 then
			return nil, "every stack of that is already on the mail"
		end
		return nil, "that is not in your bags"
	end
	return Draft.AttachSlot(bag, slot)
end

function Draft.Detach(index)
	if not attached[index] then
		return false
	end
	table.remove(attached, index)
	return true
end

function Draft.Empty()
	wipe(attached)
	return true
end

-- Everything back to nothing, which is what a finished send and a closed
-- mailbox both leave behind. The recipient is kept on purpose: sending a second
-- mail to the same person is the ordinary next thing, and retyping the name is
-- the chore this window exists to remove.
function Draft.Clear()
	subject, body, money = "", "", 0
	return Draft.Empty()
end

--------------------------------------------------------------------------
-- How many mails that is
--------------------------------------------------------------------------

function Draft.Mails()
	local per = Draft.PerMail()
	if #attached <= per then
		return 1
	end
	return math.ceil(#attached / per)
end

-- The attachments of one of them, in order. Built rather than held, because the
-- list is edited by every drop and a cached split would be one refresh behind
-- whatever is on the screen.
function Draft.Batch(which)
	local per = Draft.PerMail()
	local batch = {}
	for offset = 1, per do
		local entry = attached[(which - 1) * per + offset]
		if not entry then
			break
		end
		batch[#batch + 1] = entry
	end
	return batch
end

-- The money rides on the first mail and only the first. Splitting coin across
-- three mails would mean three ways for half of it to be sitting in a mailbox
-- if the second one fails.
function Draft.MoneyOn(which)
	return which == 1 and money or 0
end

--------------------------------------------------------------------------
-- What it is called
--------------------------------------------------------------------------

-- The name this batch would be titled after, with nothing typed. One item is
-- its own name; several is the first and a count, because "Copper Ore and 4
-- more" is a line you can act on in an inbox and "5 items" is not.
local function Named(batch)
	if #batch == 0 then
		return nil
	end
	if #batch == 1 then
		return batch[1].name
	end
	return ("%s and %d more"):format(batch[1].name, #batch - 1)
end

-- " (2/3)", fitted rather than appended. The server cuts a subject at 64 and
-- says nothing, so the part that must survive is the part that says which part
-- this is.
local function Part(text, which, total)
	if total < 2 then
		return text:sub(1, SUBJECT_MAX)
	end
	local tail = (" (%d/%d)"):format(which, total)
	return text:sub(1, SUBJECT_MAX - #tail) .. tail
end

function Draft.SubjectFor(which)
	local total = Draft.Mails()
	if subject ~= "" then
		return Part(subject, which, total)
	end

	local named = Named(Draft.Batch(which))
	if named then
		return Part(named, which, total)
	end
	if Draft.MoneyOn(which) > 0 then
		return Part("money", which, total)
	end
	return ""
end

--------------------------------------------------------------------------
-- Whether it can go, and whether it should
--------------------------------------------------------------------------

-- Whether there is anything on this mail worth asking about. A letter with
-- nothing but words in it goes to whoever you like without a second press.
function Draft.Carries()
	return money > 0 or #attached > 0
end

function Draft.Risky()
	return Draft.Carries() and not ns.MailWho.Favourite(to)
end

function Draft.Cost()
	return Draft.Postage() * Draft.Mails()
end

-- Why the send button will not do anything, or nil when it will. One sentence,
-- because it is drawn under the button rather than printed.
function Draft.Problem()
	if not ns.MailWho.Key(to) then
		return "type a name to send to"
	end
	if not Draft.Carries() and body == "" then
		return "there is nothing on this mail"
	end
	if Draft.SubjectFor(1) == "" then
		return "a letter with nothing on it needs a subject"
	end

	local purse = GetMoney() or 0
	local owed = money + Draft.Cost()
	if purse < owed then
		return ("that is %s more than you are carrying"):format(ns.Coin(owed - purse))
	end
	return nil
end

-- One line for the status word and for the window's own footer.
function Draft.Describe()
	local mails = Draft.Mails()
	local parts = ("%d attached"):format(#attached)
	if money > 0 then
		parts = parts .. ", " .. ns.Coin(money)
	end
	if mails > 1 then
		parts = parts .. (", %d mails"):format(mails)
	end
	return parts
end
