local ADDON, ns = ...

local Bags = {}
ns.MailBags = Bags

--------------------------------------------------------------------------
-- Right click in the bags, onto the letter
--
-- The client's own mail window has this and it is the only way anybody actually
-- attaches anything: you right click the stack and it goes. Dragging twelve
-- items onto a block one at a time is not a thing a person does twice.
--
-- **Why the handler is replaced and not hooked.** Everything else in this addon
-- that touches a Blizzard frame uses hooksecurefunc, which runs after the
-- client's own code and cannot stop it. That is exactly no use here: the thing
-- to stop is the client's own right click, and by the time a hook runs the
-- bread roll has been eaten. So the global is taken over, with whatever was
-- there kept and called for every click this file does not want, which is all
-- but one of them.
--
-- The one hooked function is the one the bags actually call. Both clients route
-- every bag button through `ContainerFrameItemButton_OnClick`, resolved by name
-- at click time rather than captured when the frame was built, which is what
-- lets one replacement cover every bag in the game: Blizzard's own, and
-- Baganator's, whose buttons inherit ContainerFrameItemButtonTemplate and
-- arrive at the same global. Auctionator hooks this same name on this same
-- client to put a bag item on the auction form, which is the same feature
-- pointed at a different window.
--
-- **It is installed while the window is open and taken off when it closes.**
-- One press of escape and the bags behave exactly as the client built them,
-- which is the same promise Mail/Blizzard.lua makes about the frame it parks.
-- The restore is guarded on the global still being ours: an addon that took the
-- name over while our window was up is an addon whose handler would otherwise
-- be thrown away by our restore.
--
-- **A click this file claims is never passed on.** Not when the list is full,
-- not when the stack is already on the mail, not while a send is in flight.
-- Every one of those falls through to the client otherwise, and the client's
-- answer to a right click on a bag slot is to eat, equip or open what is in it.
-- A refusal says why and stops there.
--
-- **Only a bare right click.** Shift is the client's stack split, ctrl is its
-- dress-up, and every modified click goes where it always went. The left button
-- is untouched, so picking a stack up and dropping it on the block still works
-- and is still the way to attach something out of the bank.
--------------------------------------------------------------------------

-- The bags a mail can be filled out of: the backpack and the four on the belt.
-- The bank's are numbered past these and cannot be mailed from, and a click on
-- one of those is the client's to answer.
local FIRST_BAG, LAST_BAG = 0, 4

local HANDLER = "ContainerFrameItemButton_OnClick"

-- Ours while it is the global, and whatever we found there when we put it in.
-- Both are nil while the window is closed.
local mine, theirs = nil, nil

--------------------------------------------------------------------------

-- Which bag a button is in. Its own answer where it has one and its parent's
-- otherwise, which is where the classic bags keep it and where Baganator's
-- buttons keep it too. Both are tried rather than one or the other, because a
-- button can carry the method and still answer nothing through it, and a nil
-- taken for an answer is a click that lands on no slot at all.
local function BagOf(button)
	if type(button.GetBagID) == "function" then
		local held = button:GetBagID()
		if type(held) == "number" then
			return held
		end
	end
	if type(button.GetParent) ~= "function" then
		return nil
	end
	local parent = button:GetParent()
	if type(parent) ~= "table" or type(parent.GetID) ~= "function" then
		return nil
	end
	local bag = parent:GetID()
	return type(bag) == "number" and bag or nil
end

-- The bag slot a button is, or nothing where the answer is not one this window
-- can mail out of. The slot is the button's own id on every client.
local function Where(button)
	if type(button) ~= "table" or type(button.GetID) ~= "function" then
		return nil
	end

	local bag = BagOf(button)
	local slot = button:GetID()
	if type(bag) ~= "number" or type(slot) ~= "number" then
		return nil
	end
	if bag < FIRST_BAG or bag > LAST_BAG or slot < 1 then
		return nil
	end
	return bag, slot
end

-- Whether any of the three modifiers is down, asked of the client rather than
-- of IsModifiedClick, because IsModifiedClick answers about one named binding
-- and the question here is whether the player asked for anything at all beyond
-- a plain click.
local function Down(ask)
	return type(ask) == "function" and ask() and true or false
end

local function Modified()
	return Down(_G.IsShiftKeyDown) or Down(_G.IsControlKeyDown) or Down(_G.IsAltKeyDown)
end

-- Whether this click is the window's rather than the client's. Everything here
-- is about the click; whether the slot holds anything is Draft's answer and is
-- asked after, because a refusal is still ours to report.
local function Wanted(which)
	return which == "RightButton"
		and ns.MailWindow.Shown()
		and not Modified()
end

--------------------------------------------------------------------------

-- One click, taken. True where the click was answered here and must go no
-- further, false where the client should have it.
local function Take(button)
	local bag, slot = Where(button)
	if not bag then
		return false
	end
	if not ns.ContainerItemLink(bag, slot) then
		return false
	end

	-- A send in flight is walking the list and filling the client's own form
	-- out of the bags. Something arriving on the list underneath that would be
	-- an attachment counted into no mail, so it is refused out loud rather than
	-- attached or handed back to the client.
	if ns.MailSend.Running() then
		ns.Print("a send is going, so nothing else can go on the mail yet.")
		return true
	end

	local at, why = ns.MailDraft.AttachSlot(bag, slot)
	if not at then
		if why then
			ns.Print(why .. ".")
		end
		return true
	end

	ns.MailWindow.Changed()
	return true
end

local function Click(button, which, ...)
	if Wanted(which) and Take(button) then
		return
	end
	if theirs then
		return theirs(button, which, ...)
	end
end

--------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------

function Bags.Wanted()
	return (ns.db.mail and ns.db.mailBags and ns.MailWindow.Shown()) and true or false
end

local function Install()
	local held = _G[HANDLER]
	if type(held) ~= "function" then
		return false
	end
	theirs, mine = held, Click
	_G[HANDLER] = Click
	return true
end

local function Remove()
	-- Only if the name is still holding ours. Anything else there is another
	-- addon's, put in while the window was open, and giving the client's own
	-- handler back over the top of it would be throwing that addon away.
	if _G[HANDLER] == mine then
		_G[HANDLER] = theirs
	end
	theirs, mine = nil, nil
	return true
end

function Bags.Apply()
	local wanted = Bags.Wanted()
	if wanted == (mine ~= nil) then
		return false
	end
	if wanted then
		return Install()
	end
	return Remove()
end

function Bags.Taking()
	return mine ~= nil
end

function Bags.Describe()
	if not ns.db.mailBags then
		return "the client's own"
	end
	if not Bags.Taking() then
		return "the client's own while this window is closed"
	end
	return "on the letter"
end
