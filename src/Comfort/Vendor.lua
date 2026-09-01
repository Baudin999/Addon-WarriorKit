local ADDON, ns = ...

-- Selling your trash.
--
-- Grey items exist to be sold. Nothing else in the game consumes them, they
-- carry no set bonus and no quest, and the only thing a player ever does with
-- one is drag it onto a vendor. So the addon does it, on the one screen where
-- doing it is safe, and reports what it made.
--
-- The safety is the whole design. ns.UseContainerItem sells what is in a bag
-- slot when a merchant window is up and *uses* it when one is not: it eats the
-- food, equips the weapon, opens the box. So every path into it here is behind
-- a check that the merchant window is still open, and an item the client will
-- not grade is left alone rather than sold on a guess.

local Vendor = {}
ns.Vendor = Vendor

-- The five bags. The keyring is bag -2 and holds nothing sellable, so the scan
-- never reaches for it.
local BAGS = 4

-- The quality a vendor exists to take. Nothing above this is ever touched.
local TRASH = 0

-- A sale is not instant. UseContainerItem locks the slot, the server clears it,
-- and only then does the item leave the bag, so one pass cannot see the result
-- of its own work. The sweep repeats until a pass finds nothing left, which is
-- also what catches a sale the server dropped on the floor.
local INTERVAL = 0.2

-- The backstop. At a fifth of a second a pass, this is five seconds of trying,
-- which is longer than any real bagful takes and short enough that a vendor
-- who silently refuses everything does not leave a ticker running behind the
-- merchant window forever.
local MAX_PASSES = 25

local frame
local running = false
local elapsed, passes, sold, opening = 0, 0, 0, 0

-- Whether the merchant window is still up. Asked before anything is sold,
-- because with it closed the same call uses the item instead.
local function Selling()
	return MerchantFrame ~= nil and MerchantFrame:IsShown()
end

-- One pass over the bags. Returns how much sellable trash it saw and how many
-- slots held something this client has not cached yet.
--
-- Both numbers keep the sweep alive, for different reasons. Trash it saw may
-- still be locked from this pass's own sale and has to be looked at again;
-- something ungraded may grade next pass, and until it does it is not sold,
-- because a guessed quality is how a piece of gear ends up at a vendor.
local function Sweep()
	local found, unknown = 0, 0

	if not Selling() then
		return 0, 0
	end

	for bag = 0, BAGS do
		for slot = 1, ns.ContainerSlots(bag) do
			local link = ns.ContainerItemLink(bag, slot)
			if link then
				local quality, price = ns.ItemValue(link)
				if quality == nil then
					unknown = unknown + 1
				elseif quality == TRASH and price > 0 then
					found = found + 1
					local _, locked = ns.ContainerItem(bag, slot)
					if not locked and ns.UseContainerItem(bag, slot) then
						sold = sold + 1
					end
				end
			end
		end
	end

	return found, unknown
end

local function Tick(_, delta)
	elapsed = elapsed + delta
	if elapsed < INTERVAL then
		return
	end
	elapsed = 0
	passes = passes + 1

	local found, unknown = Sweep()
	if found + unknown == 0 or passes >= MAX_PASSES then
		Vendor.Stop()
	end
end

--------------------------------------------------------------------------
-- Starting and stopping
--------------------------------------------------------------------------

-- What the sale made, measured rather than predicted. Adding up sell prices
-- says what the bags were worth; the difference in your purse says what the
-- vendor actually paid, which is the number that is still right when a vendor
-- refuses an item halfway down the list.
local function Earned()
	return GetMoney() - opening
end

function Vendor.Stop()
	if not running then
		return
	end
	running = false
	frame:SetScript("OnUpdate", nil)
	frame:UnregisterEvent("UI_ERROR_MESSAGE")

	local made = Earned()
	if sold > 0 and made > 0 then
		ns.Print(("sold %d piece%s of trash for %s.")
			:format(sold, sold == 1 and "" or "s", GetCoinText(made)))
	end
end

local function Start()
	if running then
		return
	end
	running = true
	elapsed, passes, sold = 0, 0, 0
	opening = GetMoney()
	frame:RegisterEvent("UI_ERROR_MESSAGE")
	frame:SetScript("OnUpdate", Tick)
end

-- The same sale, because something asked for it.
--
-- The setting is not consulted at all. `sellTrash` decides whether a merchant
-- opening starts a sweep on its own, and a press is not a merchant opening: the
-- button in the bag window is there so that a player who keeps the automatic
-- sale off, or who held shift to skip it at this vendor, still has one click
-- that empties the greys.
--
-- False and a reason where there is nothing to sell into, because a press is
-- something a player is waiting for an answer to.
function Vendor.Run()
	-- Only where nothing has built it yet, which is a press that beat the login
	-- pass. Apply in full would stop a sweep already in flight and start it
	-- again, and a second press mid-sale is not a request to restart the count.
	if not frame then
		Vendor.Apply()
	end
	if not Selling() then
		return false, "no merchant window is open"
	end
	Start()
	return true
end

-- The two refusals worth listening for. A vendor who does not deal in what you
-- are selling, and a purse that cannot hold any more gold. Both mean every
-- remaining sale will fail the same way, so the sweep stops rather than
-- spending its twenty-five passes finding that out one item at a time.
local function Refused(...)
	local doesntBuy, tooMuchGold = _G.ERR_VENDOR_DOESNT_BUY, _G.ERR_TOO_MUCH_GOLD
	for index = 1, select("#", ...) do
		local value = select(index, ...)
		if value ~= nil and (value == doesntBuy or value == tooMuchGold) then
			return true
		end
	end
	return false
end

-- UI_ERROR_MESSAGE hands the message as the second value on a modern client and
-- as the first on an older one, so both are compared rather than picking one
-- and being wrong on the other client.
local function OnEvent(_, event, ...)
	if event == "MERCHANT_SHOW" then
		if not ns.db.sellTrash then
			return
		end
		-- Shift is the override, the same key that already means "let me do
		-- this myself" everywhere else at a vendor.
		if IsShiftKeyDown() then
			return
		end
		Start()
	elseif event == "MERCHANT_CLOSED" then
		Vendor.Stop()
	elseif event == "UI_ERROR_MESSAGE" and Refused(...) then
		Vendor.Stop()
	end
end

function Vendor.Apply()
	if not frame then
		frame = CreateFrame("Frame")
		frame:SetScript("OnEvent", OnEvent)
		-- MERCHANT_CLOSED stays registered whatever the setting says, because
		-- turning the setting off mid-sale still has to stop the sale.
		frame:RegisterEvent("MERCHANT_CLOSED")
	end
	if ns.db.sellTrash then
		frame:RegisterEvent("MERCHANT_SHOW")
	else
		frame:UnregisterEvent("MERCHANT_SHOW")
		Vendor.Stop()
	end
end

-- Whether a sale is in flight. The panel reads it so the status line says
-- something true while the ticker is running rather than only afterwards.
function Vendor.Running()
	return running
end

function Vendor.Describe()
	if not ns.db.sellTrash then
		return "off, your greys stay in your bags"
	end
	if running then
		return ("selling, %d gone so far"):format(sold)
	end
	if sold > 0 then
		return ("on, last vendor took %d piece%s"):format(sold, sold == 1 and "" or "s")
	end
	return "on, greys go at every merchant unless you hold shift"
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	Vendor.Apply()
end)
