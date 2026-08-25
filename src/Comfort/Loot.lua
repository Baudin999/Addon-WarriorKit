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

local Loot = {}
ns.Loot = Loot

-- LOOT_READY can fire more than once for one corpse, and on a chest it fires
-- again as each slot clears. Two passes over the same slots is at best wasted
-- work and at worst a second LootSlot on a slot the first pass already took,
-- so a corpse is emptied once and the rest of the burst is ignored.
local THROTTLE = 0.3

local frame
local last = 0

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
			LootSlot(slot)
		else
			local quality = select(5, GetLootSlotInfo(slot))
			if quality and threshold and quality < threshold then
				LootSlot(slot)
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

	if AutoLooting() then
		Take()
	end
end

-- Registered and unregistered rather than left on with a branch inside, so the
-- setting off means the addon is not on the loot path at all.
function Loot.Apply()
	if not frame then
		frame = CreateFrame("Frame")
		frame:SetScript("OnEvent", OnLootReady)
	end
	if ns.db.fastLoot then
		frame:RegisterEvent("LOOT_READY")
	else
		frame:UnregisterEvent("LOOT_READY")
	end
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
