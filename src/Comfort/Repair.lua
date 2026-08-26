local ADDON, ns = ...

-- Repairing your gear.
--
-- The other half of what a merchant is for. Vendor.lua empties the bags of
-- what a vendor will buy; this pays the vendor for what he will mend, on the
-- same window, behind the same shift key.
--
-- It is one call and not a sweep. RepairAllItems does every slot at once and
-- the server either takes the money or does not, so unlike a sale there is
-- nothing to repeat and no ticker here at all. That is the whole reason this
-- is a separate file from the sale: they share a window and share nothing else.
--
-- Two purses, in a fixed order. Guild funds first when the guild has said you
-- may spend them and this repair fits inside what it has said, then your own.
-- The order is the one every repair addon uses and the one a guild bank with a
-- repair allowance exists for.

local Repair = {}
ns.Repair = Repair

-- Head through ranged. The call answers nil for a ring, a trinket, a tabard
-- and an empty slot, so the scan asks every one of them and counts what comes
-- back rather than carrying a list of which slots wear out.
local SLOTS = 18

-- What GetGuildBankWithdrawMoney answers for a rank with no limit on it. It is
-- a sentinel and not an amount, and comparing it as an amount is how an
-- unlimited allowance reads as the smallest one there is.
local UNLIMITED = -1

local frame
local lastCost, lastPayer = nil, nil

--------------------------------------------------------------------------
-- The client
--
-- The merchant half is named outright in .luacheckrc: TitanRepair and Leatrix
-- Plus both call all four unguarded, on both of these clients, inside the
-- feature this one is. The guild half is reached through _G instead. Classic
-- Era has no guild bank, TitanRepair calls CanGuildBankRepair there anyway,
-- and "another addon would also have broken" is not proof that a call exists.
-- A client without it loses guild funding and keeps the repair.
--------------------------------------------------------------------------

local function Call(name, ...)
	local fn = _G[name]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, value, second = pcall(fn, ...)
	if not ok then
		return nil
	end
	return value, second
end

-- Whether the merchant window is still up, asked for the reason Vendor.lua
-- asks it: everything below is only correct while the window the client is
-- quoting against is open.
local function Open()
	return MerchantFrame ~= nil and MerchantFrame:IsShown()
end

--------------------------------------------------------------------------
-- What it would cost
--------------------------------------------------------------------------

-- The quote, in copper, or nil where this merchant does not repair. Zero is a
-- real answer and means nothing is damaged, which is why it is not folded into
-- the nil.
function Repair.Cost()
	if not Open() or not CanMerchantRepair() then
		return nil
	end
	return GetRepairAllCost() or 0
end

-- How much of the guild bank this rank may spend today, or nil when there is
-- no guild funding to be had. An unlimited rank answers the bank's balance,
-- because the bank's balance is the real ceiling either way.
local function GuildAllowance()
	if not Call("CanGuildBankRepair") then
		return nil
	end
	local held = Call("GetGuildBankMoney")
	if type(held) ~= "number" then
		return nil
	end
	local limit = Call("GetGuildBankWithdrawMoney")
	if type(limit) ~= "number" then
		return nil
	end
	if limit == UNLIMITED or limit > held then
		return held
	end
	return limit
end

--------------------------------------------------------------------------
-- Durability
--
-- Read for the status line rather than for the repair. What decides whether to
-- repair is the merchant's quote, which is the client's own arithmetic over
-- every slot and is right about the ones this scan cannot see.
--------------------------------------------------------------------------

-- The worst piece as a percentage, and how many pieces answered at all. Both
-- nil on a client that will not quote durability.
function Repair.Durability()
	local worst, counted = nil, 0
	for slot = 1, SLOTS do
		local current, maximum = GetInventoryItemDurability(slot)
		if type(current) == "number" and type(maximum) == "number" and maximum > 0 then
			counted = counted + 1
			local percent = current / maximum * 100
			if worst == nil or percent < worst then
				worst = percent
			end
		end
	end
	if counted == 0 then
		return nil, 0
	end
	return worst, counted
end

--------------------------------------------------------------------------
-- Paying
--------------------------------------------------------------------------

-- Returns the cost and who paid, or nil and a line saying why not. The line is
-- printed only where a press asked for it, because a merchant you open with an
-- empty purse should not lecture you every time.
function Repair.Run()
	if not Open() then
		return nil, "no merchant window is open"
	end
	if not CanMerchantRepair() then
		return nil, "this merchant does not repair"
	end

	local cost = GetRepairAllCost() or 0
	if cost <= 0 then
		return 0, "nothing"
	end

	local allowance = GuildAllowance()
	if allowance and allowance >= cost then
		-- The argument is what tells the client to bill the guild. Nothing here
		-- can force a client to honour it, but nothing reaches this line on a
		-- client that would not: CanGuildBankRepair has already answered, and a
		-- client with no guild bank answers nil and never gets an allowance.
		Call("RepairAllItems", true)
		if (GetRepairAllCost() or 0) <= 0 then
			lastCost, lastPayer = cost, "guild"
			return cost, "guild"
		end
		-- The guild said it would pay and then did not, so the bill is still
		-- standing. Fall through to your own money rather than walking away
		-- with the gear still broken.
	end

	if GetMoney() < cost then
		return nil, ("repairing costs %s and you are carrying %s")
			:format(GetCoinText(cost), GetCoinText(GetMoney()))
	end

	RepairAllItems()
	lastCost, lastPayer = cost, "you"
	return cost, "you"
end

--------------------------------------------------------------------------

local function OnEvent(_, event)
	if event ~= "MERCHANT_SHOW" or not ns.db.autoRepair then
		return
	end
	-- Shift is the override, the same key that already holds the sale off.
	if IsShiftKeyDown() then
		return
	end

	local cost, payer = Repair.Run()
	-- Silent on every refusal. This runs at every merchant you open and a
	-- refusal is nearly always "nothing is damaged"; the reasons are worth
	-- reading when you asked, which is what /wk repair is for.
	if cost and cost > 0 then
		ns.Print(("repaired for %s, %s."):format(GetCoinText(cost),
			payer == "guild" and "on the guild" or "out of your own purse"))
	end
end

function Repair.Apply()
	if not frame then
		frame = CreateFrame("Frame")
		frame:SetScript("OnEvent", OnEvent)
	end
	if ns.db.autoRepair then
		frame:RegisterEvent("MERCHANT_SHOW")
	else
		frame:UnregisterEvent("MERCHANT_SHOW")
	end
end

function Repair.Describe()
	if not ns.db.autoRepair then
		return "off, you press the anvil yourself"
	end
	local worst = Repair.Durability()
	local wear = worst and (", worst piece at %d%%"):format(worst) or ""
	if lastCost and lastCost > 0 then
		return ("on, last repair %s on %s%s")
			:format(GetCoinText(lastCost), lastPayer, wear)
	end
	return "on, guild funds first where the guild allows it" .. wear
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	Repair.Apply()
end)
