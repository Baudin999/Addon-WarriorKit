local ADDON, ns = ...

local Auction = {}
ns.Auction = Auction

--------------------------------------------------------------------------
-- What the auction house thinks it is worth
--
-- One number for an item link, and the name of whoever answered.
--
-- **The client will not say.** There is no API in this game for the going rate
-- of an item. The auction house is a server query with a scan behind it, the
-- result lives in whichever addon did the scanning, and every one of those
-- addons keeps it somewhere different. So this file asks them, in order, and
-- takes the first answer.
--
-- **Which is a dependency this addon refuses to have.** Nothing here is
-- required, nothing here is suggested in a TOC, and a player with none of these
-- installed loses one line of one tooltip and is told nothing about it. That is
-- the whole contract: an addon that is present is read, an addon that is absent
-- is not mentioned, and no path in the loot feed cares which.
--
-- **The answer says who gave it.** A price with no source on it is a number the
-- player cannot check, cannot age and cannot argue with. "Auctionator 12g 40s"
-- can be looked up in Auctionator; "12g 40s" can only be believed. That is also
-- why the first provider wins rather than the highest or the average of them:
-- two scanners disagreeing is a real thing, and picking one to name is honest
-- where averaging two is a number nobody's addon holds.
--
-- Nothing here is on a ticker and nothing here is cached per item. A price is
-- read when a tooltip opens, which is a moment, and the moment is the only time
-- the answer matters.
--------------------------------------------------------------------------

-- The string an addon that wants one is handed as the caller's name. Auctionator
-- asks for it so it can attribute a query, and it wants the same string every
-- time rather than one built per call.
local CALLER = ADDON

--------------------------------------------------------------------------
-- The scanners, in the order they are asked
--
-- Newest interface first within an addon, because Auctionator carries both and
-- the old one is a compatibility shim over the new. Between addons the order is
-- how likely the addon is to be the one doing the scanning on a classic realm,
-- which is a judgement and is written down here rather than argued at each
-- call site.
--
-- Every entry is a name, a test that the addon is here and carries the shape
-- this file is about to use, and a read. The test is separate from the read so
-- a scanner that is installed but has never scanned reports as installed:
-- "Auctionator, and it has no price for this item" and "no auction addon at
-- all" are different states with different fixes, and a probe that merged them
-- would tell the player to install something they already have.
--------------------------------------------------------------------------

local SCANNERS = {
	{
		name = "Auctionator",
		here = function()
			local addon = _G.Auctionator
			return addon and addon.API and addon.API.v1
				and type(addon.API.v1.GetAuctionPriceByItemLink) == "function"
		end,
		read = function(link)
			return _G.Auctionator.API.v1.GetAuctionPriceByItemLink(CALLER, link)
		end,
	},
	{
		name = "Auctionator",
		here = function()
			return type(_G.Atr_GetAuctionBuyout) == "function"
		end,
		read = function(link)
			return _G.Atr_GetAuctionBuyout(link)
		end,
	},
	{
		name = "TradeSkillMaster",
		here = function()
			local api = _G.TSM_API
			return api and type(api.ToItemString) == "function"
				and type(api.GetCustomPriceValue) == "function"
		end,
		read = function(link)
			local item = _G.TSM_API.ToItemString(link)
			if not item then
				return nil
			end
			return _G.TSM_API.GetCustomPriceValue("dbmarket", item)
		end,
	},
	{
		name = "Auctioneer",
		here = function()
			local auc = _G.AucAdvanced
			return auc and auc.API and type(auc.API.GetMarketValue) == "function"
		end,
		read = function(link)
			return _G.AucAdvanced.API.GetMarketValue(link)
		end,
	},
	{
		name = "RECrystallize",
		here = function()
			return type(_G.RECrystallize_PriceCheck) == "function"
		end,
		read = function(link)
			return _G.RECrystallize_PriceCheck(link)
		end,
	},
}

local found

-- Which scanner is answering, or nil for a client with none of them.
--
-- Remembered once it has found one and probed again while it has not. An addon
-- cannot appear halfway through a session on this client, so the found case
-- never has to be rechecked; the empty case is five global lookups on a hover,
-- which is cheaper than being wrong about a player who enabled something and
-- reloaded into a tooltip that had already given up.
function Auction.Scanner()
	if found then
		return found
	end
	for index = 1, #SCANNERS do
		local scanner = SCANNERS[index]
		local ok, here = pcall(scanner.here)
		if ok and here then
			found = scanner
			return found
		end
	end
	return nil
end

-- What an item goes for, in copper, and who says so. Nil for a client with no
-- scanner and for an item the scanner has never seen.
--
-- pcalled, because the function on the other side belongs to somebody else and
-- an error inside it must not take a hover in this addon down with it. A
-- scanner that raises is treated as a scanner with no answer rather than
-- dropped, because the next hover is a different item and the addon on the
-- other side is not this file's to diagnose.
function Auction.Price(link)
	local scanner = Auction.Scanner()
	if not scanner or type(link) ~= "string" then
		return nil
	end

	local ok, copper = pcall(scanner.read, link)
	if not ok or type(copper) ~= "number" or copper <= 0 then
		return nil, scanner.name
	end
	return math.floor(copper), scanner.name
end

-- One line for the panel and for /wk status, which is the only place a player
-- ever finds out that this is reading anything at all.
function Auction.Describe()
	local scanner = Auction.Scanner()
	if not scanner then
		return "no auction addon is installed, so a row's tooltip says what a vendor pays and no more"
	end
	return ("reading %s for what an item goes for"):format(scanner.name)
end
