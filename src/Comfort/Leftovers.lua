local ADDON, ns = ...

-- Destroying what the loot filter refused.
--
-- The filter leaves what you did not ask for on the corpse, which is the point
-- of it and is the wrong answer for one person: a corpse only opens for a
-- skinner once every slot is gone. So this is the switch for the person who
-- skins. With it on, a slot the filter refused is looted anyway and the item is
-- destroyed the moment it lands in a bag.
--
-- It ships off, and Feature.lua says why beside the default. This is the second
-- thing in the addon that destroys what you own and the first that does it
-- without a window in front of you, so the guards matter more here than in the
-- clutter window, where at least somebody is looking.
--
-- **Never a blue.** Quality three and up is left on the corpse whatever the
-- switch says, and so is a slot whose quality this client will not state. An
-- addon deleting an epic behind somebody's back is not a thing a tick box can
-- ask for, because the one time it happens is the time nobody can undo it. A
-- quest item is left for the same reason read from the other end: the quest is
-- why you are standing over the corpse.
--
-- **The count, not the slot.** Loot lands in a stack you already had, so the
-- slot the item arrived in is not the item that arrived. Twelve cloth in a bag
-- and two off a corpse is one stack of fourteen, and destroying that slot
-- destroys the twelve you walked in with. What is remembered is how many
-- arrived, and what is destroyed is that many split off the stack.
--
-- **A pending item is forgotten after five seconds.** A LootSlot the server
-- refused, because the bags were full or because somebody rolled faster, is an
-- item that never arrives. An entry left waiting on it would destroy the next
-- one of those you picked up an hour later, which is the worst thing this file
-- could do and the only one that would look like a haunting rather than a bug.
-- Five seconds is long enough for a server to answer and short enough that
-- nothing else can be mistaken for the answer.
--
-- This part owns no frame anybody can see and draws nothing, so nothing here is
-- on a ticker.

local Leftovers = {}
ns.Leftovers = Leftovers

-- The bags, the same number Comfort/Vendor.lua and Comfort/Clutter.lua walk.
local BAGS = 4

-- Blue. Nothing at this quality or above is taken, whatever the switch says.
local KEEP = 3

-- How long an item has to arrive in, in seconds.
local STALE = 5

-- itemId -> { count, since }: what was taken off a corpse on the switch's word
-- and has not been destroyed yet.
local pending = {}

-- What this session destroyed, for the reading on the panel. A number somebody
-- can look at is the cheapest way to find out that a switch you turned on a
-- week ago has been busy, which is the thing to know about this one.
local gone = 0

local frame

-- Which of the two bag events this client answers, settled once and by asking
-- for it. See Apply.
local bagEvent

-- The frame this walk last ran in, which is the throttle. See Sweep.
local walked = -1

--------------------------------------------------------------------------
-- Taking the slot
--------------------------------------------------------------------------

-- One slot the filter refused, taken anyway so the corpse can be skinned.
--
-- Four refusals, and each one leaves the slot where it is. A slot with no link
-- is coin or a currency and there is nothing to destroy. A quality the client
-- will not state is a slot nothing here can grade, and a guess is how a blue
-- gets deleted. Blue and up is never destroyed. A quest item is the reason you
-- are here.
--
-- True where the slot was taken, so the caller can say what it did.
function Leftovers.Discard(slot)
	if not (ns.dbc and ns.dbc.lootDestroy) then
		return false
	end

	local link = ns.LootSlotLink(slot)
	if not link then
		return false
	end

	local _, _, quantity, _, quality, _, isQuestItem = GetLootSlotInfo(slot)
	if quality == nil or quality >= KEEP or isQuestItem then
		return false
	end

	local itemId = ns.ItemKind(link)
	if not itemId then
		return false
	end

	local entry = pending[itemId]
	if entry then
		entry.count = entry.count + (quantity or 1)
		entry.since = GetTime()
	else
		pending[itemId] = { count = quantity or 1, since = GetTime() }
	end

	LootSlot(slot)
	return true
end

--------------------------------------------------------------------------
-- Destroying what arrived
--
-- The four checks Comfort/Destroy.lua makes, in the same order and for the
-- same reasons, with one in front of them that window does not need. A stack
-- holding more than arrived is split first, so what reaches the cursor is what
-- the corpse gave you rather than what you were already carrying, and the
-- cursor is then asked what it is really holding before anything is deleted.
--------------------------------------------------------------------------

local function Drop()
	if type(_G.ClearCursor) == "function" then
		_G.ClearCursor()
	end
end

-- Destroy what is owed out of one slot, and nothing else. Answers how many
-- went, which is nought on every refusal.
local function Destroy(bag, slot, itemId, owed, held)
	local take = held < owed and held or owed

	Drop()

	local reached, took
	if held > take then
		reached, took = pcall(ns.SplitContainerItem, bag, slot, take)
	else
		reached, took = pcall(ns.PickupContainerItem, bag, slot)
	end
	if not reached or not took then
		Drop()
		return 0
	end

	local kind, cursorId = _G.GetCursorInfo()
	if kind ~= "item" or cursorId ~= itemId then
		Drop()
		return 0
	end

	local delete = _G.DeleteCursorItem
	if type(delete) ~= "function" or not pcall(delete) then
		Drop()
		return 0
	end

	gone = gone + take
	return take
end

-- One slot, against what is still owed on the item in it. A locked slot is a
-- move the server has not finished and is looked at again on the next pass.
local function Settle(bag, slot)
	local itemId = ns.ItemKind(ns.ContainerItemLink(bag, slot))
	local entry = itemId and pending[itemId]
	if not entry then
		return
	end

	local held, locked = ns.ContainerItem(bag, slot)
	if not held or locked then
		return
	end

	entry.count = entry.count - Destroy(bag, slot, itemId, entry.count, held)
	if entry.count <= 0 then
		pending[itemId] = nil
	end
end

local function Walk()
	for bag = 0, BAGS do
		for slot = 1, ns.ContainerSlots(bag) do
			Settle(bag, slot)
		end
	end
end

-- One pass over the bags, at most one a frame, with the stale entries dropped
-- in front of it.
--
-- GetTime is the frame's own clock and does not move inside a frame, so reading
-- it is the throttle. That is worth having on the client that answers
-- BAG_UPDATE rather than BAG_UPDATE_DELAYED: that event comes once per bag, so
-- a stack of cloth spilling across two of them is two events describing one set
-- of bags, and a pass reads every slot you own. On the client that answers the
-- delayed event it is one event and the throttle costs a comparison.
--
-- Two events landing in the same frame lose the second pass and lose nothing
-- with it: what the second would read is what the first read, and anything
-- still owed is owed on the next event and on LOOT_CLOSED behind it.
local function Sweep()
	local now = GetTime()
	if now == walked then
		return
	end
	walked = now

	for itemId, entry in pairs(pending) do
		if now - entry.since > STALE then
			pending[itemId] = nil
		end
	end

	if next(pending) then
		Walk()
	end
end

--------------------------------------------------------------------------
-- The switch
--------------------------------------------------------------------------

-- Registered and unregistered rather than left on with a branch inside, which
-- is Comfort/Loot.lua's shape and is what makes the setting off mean the addon
-- is not on the bag path at all.
function Leftovers.Apply()
	if not frame then
		frame = CreateFrame("Frame")
		frame:SetScript("OnEvent", Sweep)
	end

	if not ns.dbc.lootDestroy then
		if bagEvent then
			frame:UnregisterEvent(bagEvent)
		end
		frame:UnregisterEvent("LOOT_CLOSED")
		wipe(pending)
		return
	end

	-- Which bag event this client has, asked by asking for it. A client that
	-- has never heard of BAG_UPDATE_DELAYED refuses the registration outright
	-- rather than quietly never firing it, so the refusal is the answer and
	-- BAG_UPDATE with the throttle above it is the fallback. Asked once and
	-- remembered, because the answer is a fact about the build.
	if not bagEvent then
		bagEvent = pcall(frame.RegisterEvent, frame, "BAG_UPDATE_DELAYED")
			and "BAG_UPDATE_DELAYED" or "BAG_UPDATE"
	end
	frame:RegisterEvent(bagEvent)

	-- The corpse closing, because an item that arrived while the throttle had
	-- the frame is an item nothing else is going to come back for.
	frame:RegisterEvent("LOOT_CLOSED")
end

function Leftovers.Describe()
	if not ns.dbc.lootDestroy then
		return "off"
	end
	if gone == 0 then
		return "on, greys, whites and greens that the filter refused are looted and destroyed"
	end
	return ("on, greys, whites and greens that the filter refused are looted"
		.. " and destroyed, %d gone this session"):format(gone)
end

-- How many items are waiting to land. For the panel and for the tests, and it
-- is a count of items rather than of how many of each: what a reader wants to
-- know is whether anything is outstanding at all.
function Leftovers.Pending()
	local count = 0
	for _ in pairs(pending) do
		count = count + 1
	end
	return count
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	Leftovers.Apply()
end)
