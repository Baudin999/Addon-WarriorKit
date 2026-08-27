-- The hands, and how fast they swing
--
-- Everything the swing timer is built on, in one table the tests move rather
-- than four stubs they replace. All of it is read through a local the module
-- took at load, which is why it is declared here and never swapped out.
--
-- The two hands start empty, because most of this file is written against a
-- character carrying nothing: the gear scan counts what is in the bags and a
-- weapon appearing in a slot would move numbers three sections away. The swing
-- section equips one, drives the timer and takes it off again.

local H = ...
local state = H.state
local region, constant, ITEMS = H.region, H.constant, H.ITEMS
local CARRIED, carrying, itemLink = H.CARRIED, H.carrying, H.itemLink

local swing = {
	main = 3.4,   -- a slow two hander, which is the weapon Slam is pressed with
	off = nil,    -- nothing in the off hand until a test puts one there
	mainhand = nil, -- the link slot 16 answers with
	offhand = nil,  -- and slot 17
	talent = 0,   -- points in the talent whose name contains Slam's
	cast = nil,   -- a cast in flight, as start and stop in milliseconds
}
_G.WarriorKitSwing = swing

_G.GetInventoryItemLink = function(unit, slot)
	if unit ~= "player" then
		return nil
	end
	if slot == 16 then
		return swing.mainhand
	end
	if slot == 17 then
		return swing.offhand
	end
	return nil
end

-- The art on the hand, which is what the aura row draws for a temporary weapon
-- enchant: the enchant itself has no icon of its own and Blizzard's own enchant
-- button borrows the weapon's.
_G.GetInventoryItemTexture = function(unit, slot)
	if unit ~= "player" or not _G.GetInventoryItemLink(unit, slot) then
		return nil
	end
	return "hand" .. slot
end

-- Two returns, and the second is nil with an empty off hand or a shield in it,
-- which is the answer the client gives and the one the addon branches on.
_G.UnitAttackSpeed = function(unit)
	if unit ~= "player" then
		return nil, nil
	end
	return swing.main, swing.off
end
_G.OffhandHasWeapon = function()
	return swing.off ~= nil
end

-- The talent trees, read by index rather than by tab name. Meter/Spec.lua uses
-- GetTalentTabInfo and this is the other call on the same data, so the two do
-- not collide.
--
-- Tab 1 slot 2 is the talent the Slam window's estimate looks for, and its name
-- carries the spell's own name inside it, which is the rule the addon matches
-- on. Every other slot is a talent that does not, so a matcher that took the
-- first talent it found would fail here rather than pass by luck.
_G.GetNumTalents = function() return 3 end
_G.GetTalentInfo = function(tab, index)
	if tab == 1 and index == 2 then
		return "Improved Spell1464", "Interface\\Icons\\Slam", 4, 1, swing.talent, 5
	end
	return ("Talent%d%d"):format(tab, index), "Interface\\Icons\\T", 1, 1, 0, 5
end

-- A cast in flight, in the client's own milliseconds. Nil is nothing being
-- cast, which is every moment except the one a test opens.
--
-- Three tables and two calls. `swing.cast` is the player's, in milliseconds
-- already, because the Slam window measures itself off the one cast the player
-- makes. `enemyCasts` is keyed by unit and counted in seconds for the test's
-- convenience, because the enemy bars' cast row reads any unit the client will
-- answer for, which is the whole reason that row can exist at all.
--
-- The returns are positional and the two calls differ by one slot: a cast
-- carries a castID where a channel carries nothing, so notInterruptible is the
-- eighth return of one and the seventh of the other. A stub that put the flag
-- in the same place in both would let a shim that guessed wrong pass here and
-- draw every cast grey in the game.
--
-- Milliseconds on the way out, both of them. A stub that answered seconds would
-- let a shim that forgot to divide pass, and what that draws is a bar that is
-- full on its first frame with nothing about it looking wrong.
local enemyCasts = { cast = {}, channel = {} }

_G.UnitCastingInfo = function(unit)
	if unit == "player" then
		if not swing.cast then
			return nil
		end
		return swing.cast.name, swing.cast.name, nil, swing.cast.start, swing.cast.stop
	end
	local cast = enemyCasts.cast[unit]
	if not cast then
		return nil
	end
	return cast.name, cast.name, "Interface\\Icons\\Spell_Shadow_ShadowBolt",
		cast.start * 1000, cast.finish * 1000, false, "cast-9", cast.immune
end

_G.UnitChannelInfo = function(unit)
	local cast = enemyCasts.channel[unit]
	if not cast then
		return nil
	end
	return cast.name, cast.name, "Interface\\Icons\\Spell_Shadow_Drain",
		cast.start * 1000, cast.finish * 1000, false, cast.immune
end
-- Quality is the third value and the sell price the eleventh, which is the
-- order ns.ItemValue reads them in. Answering nil for a name this stub does not
-- carry is the client's "not cached yet", and the vendor sweep has to treat
-- that as a reason to leave the item alone.
local function itemInfo(link)
	local name = type(link) == "string" and link:match("%\[(.-)%\]")
	local item = name and ITEMS[name]
	if not item then
		return nil
	end
	return name, link, item.quality, 60, 60, nil, nil, 1, item.equip, item.icon, item.price
end
-- The fourth and fifth returns are the two ns.ItemInfo reads, the equip
-- location and the icon.
local function itemInfoInstant(link)
	local name = type(link) == "string" and link:match("%\[(.-)%\]")
	local item = name and ITEMS[name]
	if not item then
		return nil
	end
	return item.id, name, nil, item.equip, item.icon, item.classId
end

-- Both homes for the same two lookups, because both are real. The 2.5.6 client
-- carries the loose globals and the newer one carries C_Item and has taken the
-- globals away, and Core resolves the pair once at load, so a stub that offered
-- only one of them would leave the other branch of every item lookup untested.
-- Named locals rather than one wrapping the other: 40-loot-feed.lua takes the
-- globals away to stand the addon on the newer client for a moment, and a
-- C_Item that reached them through _G would go down with them.
_G.GetItemInfo, _G.GetItemInfoInstant = itemInfo, itemInfoInstant
_G.C_Item = { GetItemInfo = itemInfo, GetItemInfoInstant = itemInfoInstant }
_G.GetContainerNumSlots = function(bag) return CARRIED[bag] and #CARRIED[bag] or 0 end
_G.GetContainerItemLink = function(bag, slot)
	local held = carrying(bag, slot)
	return held and itemLink(held) or nil
end
-- Texture, count, locked, quality, in the order the loose global answers them.
-- Nothing is ever locked here: a locked slot is a sale the server has not
-- finished, and modelling that would be modelling latency rather than the
-- addon.
_G.GetContainerItemInfo = function(bag, slot)
	local held = carrying(bag, slot)
	if not held then
		return nil
	end
	return ITEMS[held].icon, 1, false, ITEMS[held].quality
end

-- The call the whole vendor part is built around, and the reason it checks the
-- merchant window before every sweep. With the window up the item is sold and
-- the money arrives. With it down the same call *uses* the item, which here
-- means it is gone and nothing was paid for it. A stub that sold either way
-- would pass the one bug in this part worth catching.
local misused = 0
_G.UseContainerItem = function(bag, slot)
	local held = carrying(bag, slot)
	if not held then
		return
	end
	CARRIED[bag][slot] = false
	if _G.MerchantFrame:IsShown() then
		state.purse = state.purse + ITEMS[held].price
	else
		misused = misused + 1
	end
end

_G.GetMoney = function() return state.purse end
_G.GetCoinText = function(amount) return ("%dc"):format(amount) end
_G.MerchantFrame = region("frame")
_G.MerchantFrame:Hide()

-- The repair side of the same window. Modelled as a bill that has to be paid
-- by somebody: the two repair calls move money out of a named purse and only
-- then clear the damage, so a repair the addon reports as done and never paid
-- for fails here rather than in Ironforge.
--
-- GUILD.allowed is what CanGuildBankRepair answers, GUILD.limit is the rank's
-- withdraw ceiling with -1 meaning none, and GUILD.held is what is actually in
-- the bank. All three are separate because the addon has to get the order of
-- them right and a single "can the guild pay" flag would let it get it wrong.
local GUILD = { allowed = false, limit = 0, held = 0, spent = 0 }

_G.CanMerchantRepair = function() return state.repairsMerchant end
_G.GetRepairAllCost = function() return state.repairBill end

_G.RepairAllItems = function(onGuild)
	if state.repairBill <= 0 then
		return
	end
	if onGuild then
		-- The client refuses rather than billing you personally, which is the
		-- behaviour the addon's fall-through exists for.
		if not GUILD.allowed then
			return
		end
		local ceiling = GUILD.limit == -1 and GUILD.held or GUILD.limit
		if ceiling < state.repairBill or GUILD.held < state.repairBill then
			return
		end
		GUILD.held = GUILD.held - state.repairBill
		GUILD.spent = GUILD.spent + state.repairBill
		state.paidBy = "guild"
	else
		if state.purse < state.repairBill then
			return
		end
		state.purse = state.purse - state.repairBill
		state.paidBy = "you"
	end
	state.repairBill = 0
end

_G.CanGuildBankRepair = function() return GUILD.allowed end

-- The error frame, and enough of the client's error constants for a key to
-- resolve to a name rather than to raw text.
--
-- Modelled as a list of what actually drew, because that is the only question
-- the filter answers: a muted message is one that never reaches AddMessage's
-- body, and a stub that recorded the call rather than the draw could not tell
-- a working filter from a broken one.
--
-- ERR_ABILITY_COOLDOWN is here unmuted throughout, as the control. A filter
-- that swallows everything passes every assertion about the messages it was
-- told to swallow.
_G.ERR_BADATTACKPOS = "You are too far away!"
_G.ERR_BADATTACKFACING = "You are facing the wrong way!"
_G.ERR_ABILITY_COOLDOWN = "Ability is not ready yet."
_G.SPELL_FAILED_UNIT_NOT_INFRONT = "Target needs to be in front of you."
-- A format string, which is the case that cannot key on a name because it
-- prints a different line every time.
_G.ERR_LEVEL_TOO_LOW = "You must be at least level %d."

-- The list of what drew hangs off the frame rather than sitting beside it,
-- because the main chunk is at Lua's 200 local ceiling and one more name here
-- costs a test somewhere else.
_G.UIErrorsFrame = region("frame")
_G.UIErrorsFrame.drawn = {}
_G.UIErrorsFrame.AddMessage = function(self, text)
	self.drawn[#self.drawn + 1] = text
end
_G.GetGuildBankMoney = function() return GUILD.held end
_G.GetGuildBankWithdrawMoney = function() return GUILD.limit end

-- Eighteen slots, of which the ones that wear are given a pair. A ring answers
-- nothing, which is what the scan has to skip rather than count as a piece at
-- zero percent.
local DURABILITY = {
	[1] = { 40, 100 },
	[5] = { 95, 100 },
	[16] = { 12, 100 },
}
_G.GetInventoryItemDurability = function(slot)
	local pair = DURABILITY[slot]
	if not pair then
		return nil
	end
	return pair[1], pair[2]
end

-- A corpse, with a quality on each slot so a master loot threshold has
-- something to sort by: two under a threshold of 2 and two at or above it.
local CORPSE = { 0, 1, 3, 2 }
local looted = {}

_G.GetNumLootItems = function() return #CORPSE end
_G.GetLootSlotInfo = function(slot)
	return "Interface\\Icons\\Coin", "Something", 1, nil, CORPSE[slot]
end
_G.LootSlot = function(slot) looted[slot] = true end
_G.GetLootThreshold = constant(2)
_G.GetLootMethod = function() return state.lootMethod end
-- No C_PartyInfo here on purpose, so Comfort/Loot.lua resolves through the
-- loose global and the fallback half of that probe is the half being tested.
_G.IsModifiedClick = constant(false)

H.swing, H.enemyCasts, H.misused = swing, enemyCasts, misused
H.GUILD, H.CORPSE, H.looted = GUILD, CORPSE, looted
