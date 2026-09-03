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
-- **The right button is taken off the square, not off the client.** A bag
-- button's OnClick is the template's own and it is secure, which is the only
-- reason a right click on a scroll reads it: `C_Container.UseContainerItem` is
-- protected and refuses insecure code. The handler resolves
-- `ContainerFrameItemButton_OnClick` by name on every click, so this file used
-- to take that name over while the window was open and hand it back when it
-- closed. That was the bug. A global written by an addon is tainted, and it
-- stays tainted when the value written back is the client's own function, so
-- one visit to a mailbox left every right click in the bags refused for the
-- rest of the session. Nothing here writes a global any more.
--
-- What a square answers to is a widget setting rather than a Lua value, and
-- writing it taints nothing. So while the window is open every square in this
-- addon's bag window is registered for the left button alone, which keeps the
-- secure OnClick off the right one, and an OnMouseUp of this file's takes the
-- right button instead. The window closes and both go back. The OnClick itself
-- is never set, read or replaced, and the client's own handler runs as secure
-- as it was built.
--
-- **Only this addon's squares.** The old takeover reached Blizzard's bags and
-- Baganator's through the shared name; a widget setting reaches the widgets it
-- is set on. This addon draws the bag window, so those are the squares under
-- the pointer. A square built while the window is open arrives through
-- Bags.Dress from Bags/Grid.lua, already holding the right state.
--
-- **A click this file claims is never passed on.** Not when the list is full,
-- not when the stack is already on the mail, not while a send is in flight. A
-- refusal says why and stops there. A bare right click on a square this file
-- does not want, an empty slot, does nothing: the client's own answer would go
-- through the protected call, and from here that call is refused. There is
-- nothing in an empty slot to use.
--
-- **Only a bare right click.** Shift is the client's stack split, ctrl is its
-- dress-up, and a modified right click is handed to the client's own modified
-- click handler by name. None of what that does is protected, so it can be
-- called from here. The left button is untouched, so picking a stack up and
-- dropping it on the block still works and is still the way to attach
-- something out of the bank.
--------------------------------------------------------------------------

-- The bags a mail can be filled out of: the backpack and the four on the belt.
-- The bank's are numbered past these and cannot be mailed from.
local FIRST_BAG, LAST_BAG = 0, 4

-- The client's own answer to a modified click on a bag button, by the name its
-- template resolves at click time.
local MODIFIED = "ContainerFrameItemButton_OnModifiedClick"

-- Whether the right button on the squares is this file's at the moment.
local taking = false

--------------------------------------------------------------------------

-- Which bag a button is in. Its own answer where it has one and its parent's
-- otherwise, which is where the classic bags keep it and where this addon's
-- squares keep it too. Both are tried rather than one or the other, because a
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

--------------------------------------------------------------------------

-- One click, taken. True where the click was answered here, false where the
-- slot is not one this window has anything to say about.
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
	-- attached.
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

-- The right button coming up on a square while the window is open. A modified
-- click is the client's, by name; a bare one is this file's.
local function Release(button, which)
	if which ~= "RightButton" then
		return
	end
	if Modified() then
		local theirs = _G[MODIFIED]
		if type(theirs) == "function" then
			theirs(button, which)
		end
		return
	end
	Take(button)
end

--------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------

function Bags.Wanted()
	return (ns.db.mail and ns.db.mailBags and ns.MailWindow.Shown()) and true or false
end

-- One square, brought to the current state. Called from Bags/Grid.lua when a
-- square is built and from here when the state changes, so a square arrives
-- and stays correct by the same call.
--
-- Both edges the template registers are put back by name, because that is
-- what ContainerFrameItemButton_OnLoad registers and a square handed back with
-- fewer would be a square the client could not use from.
function Bags.Dress(button)
	if type(button) ~= "table" or type(button.RegisterForClicks) ~= "function" then
		return false
	end
	if taking then
		button:RegisterForClicks("LeftButtonUp")
		button:SetScript("OnMouseUp", Release)
	else
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnMouseUp", nil)
	end
	return true
end

local function Sweep()
	local squares = ns.BagsGrid and ns.BagsGrid.Squares() or {}
	for index = 1, #squares do
		Bags.Dress(squares[index])
	end
end

function Bags.Apply()
	local wanted = Bags.Wanted()
	if wanted == taking then
		return false
	end
	taking = wanted
	Sweep()
	return true
end

function Bags.Taking()
	return taking
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
