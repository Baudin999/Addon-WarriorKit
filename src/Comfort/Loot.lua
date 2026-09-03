local ADDON, ns = ...

-- Fast loot.
--
-- The client's own auto loot is not slow because it is careful. It opens the
-- loot window, then takes one slot per frame with a pause between each, and the
-- window is drawn through all of it. That is where the half second of standing
-- over a corpse goes, and at four corpses a pull it is the single largest tax
-- on a fury pull.
--
-- LOOT_READY fires once the server has said what is on the corpse and before
-- the window is drawn. Taking every slot there empties the corpse without the
-- window appearing at all.
--
-- This part owns no frame and draws nothing, so nothing here is on a ticker.
--
-- What is worth taking is not decided here. Comfort/Wanted.lua answers that,
-- one slot at a time, and this file is the loop that asks it: emptying a
-- corpse and choosing what to empty out of it are two questions, and only the
-- first one has anything to do with the loot window being drawn.

local Loot = {}
ns.Loot = Loot

-- LOOT_READY can fire more than once for one corpse, and on a chest it fires
-- again as each slot clears. Two passes over the same slots is at best wasted
-- work and at worst a second LootSlot on a slot the first pass already took,
-- so a corpse is emptied once and the rest of the burst is ignored.
local THROTTLE = 0.3

local frame
local last = 0

-- The slots the filter could not answer yet, by number, on the corpse that is
-- open. A grey or white the client has not priced is an item the filter can
-- neither keep nor refuse, and asking for the price is what makes the client
-- go and fetch it. So the slot is left where it is, GET_ITEM_INFO_RECEIVED is
-- listened for while any slot is waiting, and the waiting slots are asked
-- again when it fires. The corpse closing forgets them: what is left on it is
-- a walk back at worst, and never a delete.
--
-- By slot rather than by walking the corpse again, because a slot the first
-- pass took is still a slot on this client's stub and on some builds of the
-- real one, and a second LootSlot on it is at best nothing.
local waiting = {}

-- Whether this click asked for auto loot. autoLootDefault is the setting and
-- AUTOLOOTTOGGLE is the modifier that inverts it for one click, so the two
-- disagreeing is the player asking for auto loot either way round. Emptying a
-- corpse behind their back is only the thing they asked for when it does.
local function AutoLooting()
	return GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE")
end

-- Whether this group is on master loot, on whichever API this client answers.
-- C_PartyInfo.GetLootMethod answers an enum where 2 is the master looter and
-- the old global answers the string "master".
--
-- Nil where neither answered, which is a different answer from "no" and the
-- caller has to tell them apart.
local function MasterLooting()
	local partyInfo = _G.C_PartyInfo
	if partyInfo and type(partyInfo.GetLootMethod) == "function" then
		return partyInfo.GetLootMethod() == 2
	end
	if type(_G.GetLootMethod) == "function" then
		return _G.GetLootMethod() == "master"
	end
	return nil
end

-- One slot, taken if the filter wants it and refused if it does not.
--
-- A refused slot is where the leftovers rule gets its turn. It is off unless
-- you turned it on, and what it means is that the slot is looted anyway and
-- what came out of it is destroyed, so a skinner behind you finds an empty
-- corpse rather than one nobody can touch. Comfort/Leftovers.lua owns that
-- setting and that decision; this line is the only place it is reached from.
local function Consider(slot)
	local want = ns.Wanted.Take(slot)
	if want == nil then
		waiting[slot] = true
		frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		frame:RegisterEvent("LOOT_CLOSED")
		return
	end
	waiting[slot] = nil
	if want then
		LootSlot(slot)
		return
	end
	if ns.dbc.lootDestroy then
		ns.Leftovers.Discard(slot)
	end
end

local function Forget()
	wipe(waiting)
	frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	frame:UnregisterEvent("LOOT_CLOSED")
end

-- The waiting slots asked again, once the client has answered something. Not
-- matched against the id the event carries, because a corpse rarely has two
-- slots waiting and a slot asked again before its answer simply waits on.
local function Retry()
	for slot in pairs(waiting) do
		Consider(slot)
	end
	if not next(waiting) then
		Forget()
	end
end

-- Empty the corpse.
--
-- Under master loot every slot at or above the threshold belongs to the master
-- looter to assign. LootSlot on one of those does nothing if you are not the
-- master looter and quietly assigns it to yourself if you are, which is a way
-- to ninja your own raid without ever meaning to. So under master loot only the
-- slots below the threshold are taken, and a slot whose quality the client will
-- not state is left where it is.
local function Take()
	local master = MasterLooting()

	-- Neither loot API answered. Solo there is nobody to take a slot from, so
	-- the corpse is emptied. In a group there might be, and the client's own
	-- auto loot handles it at its own pace, which is slower and correct.
	if master == nil then
		if GetNumGroupMembers() > 0 then
			return
		end
		master = false
	end

	local threshold = master and GetLootThreshold() or nil

	for slot = GetNumLootItems(), 1, -1 do
		if not master then
			Consider(slot)
		else
			local quality = select(5, GetLootSlotInfo(slot))
			if quality and threshold and quality < threshold then
				Consider(slot)
			end
		end
	end
end

local function OnLootReady()
	if not ns.db.fastLoot then
		return
	end

	local now = GetTime()
	if now - last < THROTTLE then
		return
	end
	last = now

	-- A new corpse, so whatever the last one left waiting is its own affair.
	Forget()
	if AutoLooting() then
		Take()
	end
end

local function OnEvent(_, event)
	if event == "LOOT_READY" then
		OnLootReady()
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		Retry()
	elseif event == "LOOT_CLOSED" then
		Forget()
	end
end

-- Registered and unregistered rather than left on with a branch inside, so the
-- setting off means the addon is not on the loot path at all.
function Loot.Apply()
	if not frame then
		frame = CreateFrame("Frame")
		frame:SetScript("OnEvent", OnEvent)
	end
	if ns.db.fastLoot then
		frame:RegisterEvent("LOOT_READY")
	else
		frame:UnregisterEvent("LOOT_READY")
		Forget()
	end
end

-- How many slots on the open corpse are waiting for a price. For the panel
-- and for the harness.
function Loot.Waiting()
	local count = 0
	for _ in pairs(waiting) do
		count = count + 1
	end
	return count
end

function Loot.Describe()
	if not ns.db.fastLoot then
		return "off, the client loots at its own pace"
	end
	local master = MasterLooting()
	if master == nil then
		return "on, and this client names no loot method, so grouped falls back to the client"
	end
	if master then
		return "on, master loot, so only what is under the threshold"
	end
	return "on"
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	Loot.Apply()
end)
