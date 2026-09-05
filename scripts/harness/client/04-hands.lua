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
local counted = H.counted

local swing = {
	main = 3.4,   -- a slow two hander, which is the weapon Slam is pressed with
	off = nil,    -- nothing in the off hand until a test puts one there
	mainhand = nil, -- the link slot 16 answers with
	offhand = nil,  -- and slot 17
	talent = 0,   -- points in the talent whose name contains Slam's
	cast = nil,   -- a cast in flight, as start and stop in milliseconds
}
_G.WarriorKitSwing = swing

-- The two hands and the two trinkets. The hands are the swing timer's and the
-- trinkets are the cooldown row's, and they sit in one table because the client
-- answers all four out of one call.
local worn = { [13] = nil, [14] = nil }

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
	return worn[slot]
end

-- The name of an item's use effect, or nil for one you merely wear. This is
-- what tells the cooldown row a trinket it can put on the row from a trinket it
-- cannot, and it is a field on the item rather than a guess off the link, so a
-- passive trinket is a real fixture rather than an absent one.
_G.GetItemSpell = function(link)
	local name = type(link) == "string" and link:match("%\[(.-)%\]")
	local item = name and ITEMS[name]
	return item and item.use or nil
end

-- A worn item's own cooldown, which is a different call from a spell's and is
-- the one thing about a trinket square that cannot be read off a spell id.
-- Table driven off the same scene the spell cooldowns are driven from, so a
-- section puts a trinket on cooldown the way it puts Death Wish on one.
_G.GetInventoryItemCooldown = function(unit, slot)
	local entry = unit == "player" and H.own.worn[slot]
	if not entry then
		return 0, 0, 1
	end
	return entry[1], entry[2], 1
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
--
-- The fourth and fifth are the item's own level and the level it asks of you,
-- and they default to sixty because that is what every fixture written before
-- the clutter window measured a level said. An item that carries its own pair
-- is one written to be behind or in front of the player, and nothing else in
-- the suite moves when they are the same number.
local function itemInfo(link)
	local name = type(link) == "string" and link:match("%\[(.-)%\]")
	local item = name and ITEMS[name]
	if not item then
		return nil
	end
	return name, link, item.quality, item.rating or 60, item.needs or 60,
		nil, nil, item.stack or 1, item.equip, item.icon, item.price
end
-- The fourth and fifth returns are the two ns.ItemInfo reads, the equip
-- location and the icon. The sixth and seventh are the class and the subclass,
-- which is what tells a mining pick from a green somebody outgrew: both are a
-- level four white one hander and only the subclass separates them.
local function itemInfoInstant(link)
	local name = type(link) == "string" and link:match("%\[(.-)%\]")
	local item = name and ITEMS[name]
	if not item then
		return nil
	end
	return item.id, name, nil, item.equip, item.icon, item.classId, item.subClassId
end

-- Both homes for the same two lookups, because both are real. The 2.5.6 client
-- carries the loose globals and the newer one carries C_Item and has taken the
-- globals away, and Core resolves the pair once at load, so a stub that offered
-- only one of them would leave the other branch of every item lookup untested.
-- Named locals rather than one wrapping the other: 40-loot-feed.lua takes the
-- globals away to stand the addon on the newer client for a moment, and a
-- C_Item that reached them through _G would go down with them.
-- The two halves of a socket, which is the same split the client itself has.
--
-- GetItemGem walks what a link is carrying, and a hole is a nil in the middle of
-- that walk rather than the end of it: the fixture's `gems` list is indexed
-- straight, so an item written with a hole in its first socket answers nothing
-- at one and a gem at two, which is the shape ns.ItemSockets must not stop on.
--
-- GetItemStats is the other half and only ever counts. There is no call that
-- says which position is open, because a link with a hole in it has nothing in
-- that position to name, so the fixture carries a number rather than an order.
local function itemGem(link, index)
	local name = type(link) == "string" and link:match("%\[(.-)%\]")
	local item = name and ITEMS[name]
	local gem = item and item.gems and item.gems[index]
	if not gem then
		return nil
	end
	return gem, itemLink(gem)
end

local function itemStats(link)
	local name = type(link) == "string" and link:match("%\[(.-)%\]")
	local item = name and ITEMS[name]
	if not item or not item.open then
		return nil
	end
	return { EMPTY_SOCKET_RED = item.open }
end

_G.GetItemInfo, _G.GetItemInfoInstant = itemInfo, itemInfoInstant
_G.GetItemGem, _G.GetItemStats = itemGem, itemStats
_G.C_Item = {
	GetItemInfo = itemInfo, GetItemInfoInstant = itemInfoInstant,
	GetItemGem = itemGem, GetItemStats = itemStats,
}

-- The client's own word for a subclass, which is what a sub-pile is headed
-- with. Four are carried, the four the fixtures above use, and every other
-- pair answers nil, which is a client with no word for the number and is the
-- branch Core/Piles.lua heads with the pile's word and the number. On both
-- homes for the reason the two lookups above are: Baganator reads it off
-- C_Item on this client and the loose global is the older one's.
local SUBCLASSES = {
	[7] = { [5] = "Cloth", [7] = "Metal & Stone" },
	[15] = { [1] = "Reagent", [2] = "Pet" },
}
local function itemSubClassInfo(classId, subClassId)
	local row = SUBCLASSES[classId]
	return row and row[subClassId] or nil
end
_G.GetItemSubClassInfo = itemSubClassInfo
_G.C_Item.GetItemSubClassInfo = itemSubClassInfo
_G.GetContainerNumSlots = function(bag) return CARRIED[bag] and #CARRIED[bag] or 0 end
_G.GetContainerItemLink = function(bag, slot)
	local held = carrying(bag, slot)
	return held and itemLink(held) or nil
end
-- Texture, count, locked, quality, in the order the loose global answers them.
-- Nothing is ever locked here: a locked slot is a sale the server has not
-- finished, and modelling that would be modelling latency rather than the
-- addon.
--
-- The count is the one a section wrote and one otherwise, which is what the
-- client answers for a slot holding a single thing. Everything that reads it
-- read a literal one until stacks could be combined.
_G.GetContainerItemInfo = function(bag, slot)
	local held = carrying(bag, slot)
	if not held then
		return nil
	end
	return ITEMS[held].icon, counted(bag, slot), false, ITEMS[held].quality
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

-- The pointer. Two calls and one value, because that is all the client gives
-- you: there is no way to ask what the cursor is, so a section that wants to
-- know reads what was last written here.
_G.SetCursor = function(name) state.cursor = name or false end
_G.ResetCursor = function() state.cursor = false end

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

-- Counted, because the character sheet's gear page is the only caller and it
-- asks once per slot per paint. A count that has not moved is a page nobody has
-- painted, which is the whole of what login is supposed to cost now.
H.gear = { durability = 0 }

_G.GetInventoryItemDurability = function(slot)
	H.gear.durability = H.gear.durability + 1
	local pair = DURABILITY[slot]
	if not pair then
		return nil
	end
	return pair[1], pair[2]
end

-- What the loot filter is pointed at, in no bag and on nobody's rack: one item
-- per rule the filter has, so a claim about one rule is a claim about one slot.
--
-- The class and subclass numbers are the client's, read off Questie's TBC item
-- database rather than typed from memory: cloth is 7 and 5, leather 7 and 6,
-- metal and stone 7 and 7, meat 7 and 8, herb 7 and 9, enchanting 7 and 12, and
-- a gem is class 3 whatever its subclass. Elemental Water is 7 and 10, which no
-- rule in the addon names, so it is the one item here that can only be taken
-- because a profession asked for it.
--
-- Every name is the fixture's own. Silver Ore rather than the copper a level
-- twelve character digs, because 46-mail.lua carries a Copper Ore of its own
-- with no subclass on it, and a fixture that quietly replaces another file's is
-- a test that passes on whichever ran last.
ITEMS["Moth-eaten Wool"] = { id = 7001, classId = 7, subClassId = 5, quality = 0,
	price = 4, icon = "Interface\\Icons\\Wool" }
ITEMS["Silver Ore"] = { id = 7002, classId = 7, subClassId = 7, quality = 1,
	price = 30, icon = "Interface\\Icons\\Ore" }
ITEMS["Peacebloom"] = { id = 7003, classId = 7, subClassId = 9, quality = 1,
	price = 10, icon = "Interface\\Icons\\Herb" }
ITEMS["Light Leather"] = { id = 7004, classId = 7, subClassId = 6, quality = 1,
	price = 25, icon = "Interface\\Icons\\Leather" }
ITEMS["Strange Dust"] = { id = 7005, classId = 7, subClassId = 12, quality = 1,
	price = 100, icon = "Interface\\Icons\\Dust" }
ITEMS["Chunk of Boar Meat"] = { id = 7006, classId = 7, subClassId = 8, quality = 1,
	price = 5, icon = "Interface\\Icons\\Meat" }
ITEMS["Tigerseye"] = { id = 7007, classId = 3, subClassId = 7, quality = 1,
	price = 200, icon = "Interface\\Icons\\Gem" }
ITEMS["Elemental Water"] = { id = 7008, classId = 7, subClassId = 10, quality = 1,
	price = 400, icon = "Interface\\Icons\\Water" }
ITEMS["Bandit's Cudgel"] = { id = 7009, classId = 2, subClassId = 4, quality = 2,
	price = 1200, icon = "Interface\\Icons\\Mace" }
ITEMS["Splintered Femur"] = { id = 7010, classId = 15, subClassId = 0, quality = 0,
	price = 3, icon = "Interface\\Icons\\Bone" }
ITEMS["Mangled Sigil"] = { id = 7011, classId = 12, subClassId = 0, quality = 1,
	price = 0, icon = "Interface\\Icons\\Sigil" }

-- The quest the client names on a slot a quest in your log wants. One number
-- for every such slot, because nothing in the addon reads which quest it is:
-- what is read is that there is one.
local QUEST_ON_A_SLOT = 231

-- A corpse, with a quality on each slot so a master loot threshold has
-- something to sort by: two under a threshold of 2 and two at or above it.
--
-- A slot is a table rather than a bare quality, because the loot filter reads
-- what is in a slot and not only how good it is. `item` is a name out of ITEMS
-- and a slot carrying none is the coins, which is what every corpse in the game
-- has on it. `quest` is the flag the client sets on a slot a quest in your log
-- wants, which is a fact about the log rather than about the item and is why it
-- is written on the slot and not in ITEMS.
local CORPSE = {
	{ quality = 0 },
	{ quality = 1, item = "Linen Cloth" },
	{ quality = 3, item = "Bloodspiller" },
	{ quality = 2, item = "Emerald Pigment" },
}

-- What the loot window is showing. The four above, unless a section stands a
-- longer corpse up in their place: 69-loot-filter.lua does and puts them back,
-- because every other section in the suite counts those four.
local corpse = CORPSE
local looted = {}

_G.GetNumLootItems = function() return #corpse end

-- Nine values, in the order this client answers them: the icon, the name, how
-- many, the currency id, the quality, whether the slot is locked, whether a
-- quest in your log wants it, which quest, and whether that quest is active.
-- Nothing is ever locked, for the reason no bag slot is: a locked slot is a
-- server that has not answered yet, which is latency rather than the addon.
_G.GetLootSlotInfo = function(slot)
	local held = corpse[slot]
	if not held then
		return nil
	end
	local item = held.item and ITEMS[held.item]
	return item and item.icon or "Interface\\Icons\\Coin",
		held.item or "Coins", held.count or 1, nil, held.quality, false,
		held.quest == true, held.quest and QUEST_ON_A_SLOT or nil, held.quest == true
end

-- 1 for an item, 2 for money, 3 for a currency. Nothing here is a currency:
-- there is none on this client that drops off a corpse, and the branch that
-- reads one is reached from the money side of the same call.
_G.GetLootSlotType = function(slot)
	local held = corpse[slot]
	if not held then
		return nil
	end
	return held.item and 1 or 2
end

-- The link, which is the older client's way of telling money from an item and
-- is what ns.LootKind falls back to. 16-dungeons.lua puts its own in front of
-- this one for the length of a dungeon loot window and hands it back.
_G.GetLootSlotLink = function(slot)
	local held = corpse[slot]
	return held and held.item and itemLink(held.item) or nil
end

-- Where a slot lands when it is taken.
--
-- The client's own order: into a stack of the same item where one is already
-- open, otherwise into the first free slot there is. A bag with neither leaves
-- the item on the corpse and says nothing, which is what a full bag does in the
-- game and is the state the leftovers' five second rule exists for.
local function land(held)
	local item = ITEMS[held.item]
	local quantity = held.count or 1
	for bag = 0, 4 do
		local slots = CARRIED[bag]
		for slot = 1, slots and #slots or 0 do
			if slots[slot] == held.item and (item.stack or 1) > 1 then
				counted(bag, slot, counted(bag, slot) + quantity)
				return true
			end
		end
	end
	for bag = 0, 4 do
		local slots = CARRIED[bag]
		for slot = 1, slots and #slots or 0 do
			if slots[slot] == false then
				slots[slot] = held.item
				counted(bag, slot, quantity)
				return true
			end
		end
	end
	return false
end

-- Taking one slot off the corpse. The counter is what every loot assertion
-- written before the filter reads, and it is ticked whatever the slot held. An
-- item that reached a bag says so with the event the client says it with,
-- which is what the leftovers part is waiting for; H.fire is read at the call
-- because the runner builds it after this file loads. The four slots every
-- other section counts name no item, so nothing of theirs ever lands.
_G.LootSlot = function(slot)
	looted[slot] = true
	local held = corpse[slot]
	if held and held.item and land(held) then
		H.fire("BAG_UPDATE_DELAYED")
	end
end
_G.GetLootThreshold = constant(2)
_G.GetLootMethod = function() return state.lootMethod end
-- No C_PartyInfo here on purpose, so Comfort/Loot.lua resolves through the
-- loose global and the fallback half of that probe is the half being tested.
-- The two bindings that sit on shift by default answer from the shift key
-- 05-quests.lua holds, so a stack split on the merchant rack is reachable by
-- pressing shift the way the player does. Everything else, autoloot included,
-- is off, which is the loot section's premise.
_G.IsModifiedClick = function(binding)
	if binding == "SPLITSTACK" or binding == "CHATLINK" then
		return _G.IsShiftKeyDown and _G.IsShiftKeyDown() or false
	end
	-- No binding named is the client's "is any modifier down at all", which is
	-- the question a bag button's OnClick asks before choosing a handler.
	if binding == nil then
		return (_G.IsShiftKeyDown and _G.IsShiftKeyDown())
			or (_G.IsControlKeyDown and _G.IsControlKeyDown())
			or (_G.IsAltKeyDown and _G.IsAltKeyDown()) or false
	end
	return false
end

H.swing, H.enemyCasts, H.misused = swing, enemyCasts, misused
H.worn = worn
-- The corpse a section stands up in place of the four, and the way back. A
-- section that swaps one in puts the four back before the next one runs, the
-- way 16-dungeons.lua's own loot window does.
H.loot = {
	Set = function(slots) corpse = slots end,
	Reset = function() corpse = CORPSE end,
}
H.GUILD, H.CORPSE, H.looted = GUILD, CORPSE, looted
