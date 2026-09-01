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

-- Whether a merchant is open, which is not the same question as whether
-- MerchantFrame is on screen.
--
-- This gate was `MerchantFrame:IsShown()` and that is the defect this file
-- shipped with. MERCHANT_SHOW is the server saying a merchant session is open;
-- it is not the client saying the window is drawn. ShowUIPanel defers when
-- another panel holds the slot, and a client that loads MerchantFrame on
-- demand has no frame to ask at all. Either way the repair asked a frame that
-- was not up yet, returned "no merchant window is open", and OnEvent below
-- swallows every refusal, so it failed in silence at every vendor.
--
-- The sale next door never saw it because the sale is a ticker. It asks the
-- same question again a fifth of a second later, by which time the window is
-- up, so one of the two parts on this event worked and the other did not.
--
-- The session is the answer, and its two edges are the two events. Both stay
-- registered whatever the setting says, because this flag is what /wk repair
-- and the panel button read and both of those work with the automatic repair
-- turned off.
local session = false

local function Open()
	return session
end

--------------------------------------------------------------------------
-- What it would cost
--------------------------------------------------------------------------

-- What the merchant in front of you would charge, asked of the client and not
-- of the session flag. Nil where this merchant does not mend. Zero is a real
-- answer and means nothing is damaged, which is why it is not folded into the
-- nil.
--
-- Public and ungated because the bag window's merchant row asks it. That row
-- keeps its own flag off the same two events, and there is no order between two
-- frames on one event, so a reading that went through the flag below would be
-- right or a frame late depending on which handler the client happened to run
-- first.
function Repair.Quote()
	if not CanMerchantRepair() then
		return nil
	end
	return GetRepairAllCost() or 0
end

-- The same quote for a caller with no merchant reading of its own, which is
-- every caller in this addon but that one.
function Repair.Cost()
	if not Open() then
		return nil
	end
	return Repair.Quote()
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
	if event == "MERCHANT_CLOSED" then
		session = false
		return
	end
	if event ~= "MERCHANT_SHOW" then
		return
	end

	-- Set before the setting is read, so a merchant opened with the automatic
	-- repair off still leaves /wk repair and the panel button able to answer.
	session = true

	if not ns.db.autoRepair then
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
		-- Registered once and never taken off. The setting decides whether the
		-- handler repairs, not whether the handler runs, because the session
		-- flag it keeps has to be right for the manual repair either way. It
		-- used to unregister here, and that is why turning the setting off left
		-- `/wk repair` at a merchant saying there was no merchant.
		frame:RegisterEvent("MERCHANT_SHOW")
		frame:RegisterEvent("MERCHANT_CLOSED")
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
