local ADDON, ns = ...

local Worn = {}
ns.Worn = Worn

--------------------------------------------------------------------------
-- What you are wearing
--
-- Nineteen slots, what is in each of them, how worn it is, and the two calls
-- that put something in or take it off. Every question the gear page asks is
-- answered here, and nothing here draws anything.
--
-- **This is not Core/Gear.lua and the two do not overlap.** Gear answers "what
-- in your bags will the client let into a hand", which is a question about
-- things you are not wearing, asked so the charge macro can name one in a
-- macro line.
-- This answers "what is on you right now", which is a question about the
-- eighteen slots that have nothing to do with a macro. They meet at slots 16
-- and 17 and disagree about nothing: Gear names the two by number and this file
-- names all nineteen by number, out of the same client constants.
--
-- **Equipping goes through the cursor, the way the client's own sheet does.**
-- There is a call that equips an item by name and it is the wrong one here.
-- The right one is `PickupInventoryItem`, which swaps whatever is on the cursor
-- into the slot and picks up what was there, because that is the call
-- FrameXML's own paperdoll button makes and it is therefore the call the client
-- is written to accept from a hardware click. It costs nothing to be the same
-- as the thing being replaced.
--
-- It is refused in a fight, by the client rather than by this file, and the
-- refusal is silent. So the fight is checked here and the reason is said out
-- loud: a slot that does nothing when you click it is the worst version of this
-- page.
--
-- **Using what is in a slot is not a call at all, and that is the correction
-- this file exists in its current shape for.** `UseInventoryItem` is protected.
-- An addon that calls it from its own click gets the dialog saying WarriorKit
-- has been blocked from an action only available to the Blizzard UI, and so
-- does an addon that finishes a spell the client is holding until it is told
-- which item it is for, which is what a sharpening stone, a weapon oil, an
-- enchanting scroll and a poison all are. The client's own sheet may make that
-- call because it is the client's own sheet. This one may not, whatever it
-- calls, so it does not call: Character/Paperdoll.lua puts `/use <slot>` and a
-- `target-slot` on a secure button and the client runs both on the path a macro
-- runs on, which is the same `/use 16` every stone macro in the game already
-- carries. All this file owes that arrangement is the question below.
--
-- **Nothing is cached.** What you are wearing changes on an event the client
-- fires, the window redraws on that event, and a cache between the two would be
-- one more thing that can be stale while the picture says otherwise. The one
-- thing kept is the empty-slot art, which is a texture path the client answers
-- the same way for the life of the session.
--------------------------------------------------------------------------

-- The nineteen, in the order the page draws them: ten down the left and nine
-- down the right, with the figure standing in the gap between the two.
--
--   slot   the inventory number, which is what every call below takes
--   key    the client's own name for the slot, which is how the empty art is
--          asked for rather than written down as a texture path
--   label  what this addon calls it, lower case like every other label here
--   side   which of the two columns it is drawn in
--   hand   a slot a temporary enchant can be on, which is the three weapons and
--          nothing else. Marked here rather than counted at the call site,
--          because "which rows are weapons" is a fact about the slots and the
--          page already reads its rows out of this table
--
-- There were three groups and the third was the weapons, drawn as three bare
-- discs centred under the figure with no words on them at all. That was the one
-- place left on the page where you could not read what you were holding, and it
-- was a shape the sheets this page is drawn against do not have: they put the
-- weapons at the foot of the first column, in the same row shape as everything
-- else. So do these. Nothing was gained by the middle group except three
-- nameless circles and a durability chord that had to be drawn a special way
-- because there was no name to underline.
--
-- Shirt and tabard are last in their columns and are left out of the two
-- summaries the page draws on purpose: neither has an item level, neither wears
-- out, and counting them would drag both numbers down for wearing a guild
-- tabard. Last rather than sixth and seventh, which is where they were, because
-- a piece that counts for nothing belongs under the pieces that do.
local SLOTS = {
	{ slot = 1,  key = "HeadSlot",          label = "head",      side = "left" },
	{ slot = 2,  key = "NeckSlot",          label = "neck",      side = "left" },
	{ slot = 3,  key = "ShoulderSlot",      label = "shoulder",  side = "left" },
	{ slot = 15, key = "BackSlot",          label = "back",      side = "left" },
	{ slot = 5,  key = "ChestSlot",         label = "chest",     side = "left" },
	{ slot = 9,  key = "WristSlot",         label = "wrist",     side = "left" },
	{ slot = 16, key = "MainHandSlot",      label = "main hand", side = "left", hand = true },
	{ slot = 17, key = "SecondaryHandSlot", label = "off hand",  side = "left", hand = true },
	{ slot = 18, key = "RangedSlot",        label = "ranged",    side = "left", hand = true },
	{ slot = 4,  key = "ShirtSlot",         label = "shirt",     side = "left", trim = true },

	{ slot = 10, key = "HandsSlot",         label = "hands",     side = "right" },
	{ slot = 6,  key = "WaistSlot",         label = "waist",     side = "right" },
	{ slot = 7,  key = "LegsSlot",          label = "legs",      side = "right" },
	{ slot = 8,  key = "FeetSlot",          label = "feet",      side = "right" },
	{ slot = 11, key = "Finger0Slot",       label = "ring",      side = "right" },
	{ slot = 12, key = "Finger1Slot",       label = "ring",      side = "right" },
	{ slot = 13, key = "Trinket0Slot",      label = "trinket",   side = "right" },
	{ slot = 14, key = "Trinket1Slot",      label = "trinket",   side = "right" },
	{ slot = 19, key = "TabardSlot",        label = "tabard",    side = "right", trim = true },
}

-- The empty-slot pictures, asked for once each. A client that has no such call
-- draws an empty box, which is the honest degradation: the box is still where
-- the item goes.
local art = {}

local function Ask(name, ...)
	local call = _G[name]
	if type(call) ~= "function" then
		return nil
	end
	local ok, a, b, c = pcall(call, ...)
	if not ok then
		return nil
	end
	return a, b, c
end

function Worn.Slots()
	return SLOTS
end

function Worn.Art(entry)
	if art[entry.slot] == nil then
		local _, texture = Ask("GetInventorySlotInfo", entry.key)
		art[entry.slot] = texture or false
	end
	return art[entry.slot] or nil
end

--------------------------------------------------------------------------
-- What is in a slot
--------------------------------------------------------------------------

function Worn.Link(slot)
	return Ask("GetInventoryItemLink", "player", slot)
end

-- The picture, asked for separately rather than read off the link.
--
-- An empty slot has no link and the client still answers a texture for one that
-- is filled, so this is the call that decides whether anything is drawn at all.
-- It also answers for an item the client has not cached, which a link lookup
-- does not.
function Worn.Icon(slot)
	return Ask("GetInventoryItemTexture", "player", slot)
end

-- Current and maximum, or nothing at all for a slot that does not wear out.
-- Nil is not zero and the caller has to keep them apart: a ring answers nothing
-- and drawing it as a piece at zero percent is how a summary reads as broken
-- gear when it is a ring.
function Worn.Durability(slot)
	local current, maximum = Ask("GetInventoryItemDurability", slot)
	if type(current) ~= "number" or type(maximum) ~= "number" or maximum <= 0 then
		return nil
	end
	return current, maximum
end

--------------------------------------------------------------------------
-- What has been put on the piece since you got it
--
-- Two different questions with two different answers and one word between them.
-- The permanent enchant is part of the item: it is in the link, it survives a
-- logout, and the only thing missing from the link is what it is called. The
-- temporary one is a stone, an oil or a poison, it is on a hand rather than on
-- an item, it runs for an hour and it is the one a warrior is actually watching
-- go.
--------------------------------------------------------------------------

-- The client's own "Enchanted: %s" line, as a pattern with the blank half
-- captured.
--
-- Read off the client rather than typed, for the reason Feeds/Loot.lua reads
-- the loot sentences off the client: the string is localised, and a file that
-- typed the English would capture nothing on every other client and would not
-- say so. Escaped before the %s is opened up, because a locale is free to put a
-- bracket or a dash in its own wording and every one of those is a pattern
-- character here.
--
-- Built once at load. A client with no such string leaves it nil, and the
-- reader below answers nil the way it does for a client that will not fill a
-- tooltip at all: the row prints the level and nothing beside it.
local ENCHANTED = _G.ENCHANTED_TOOLTIP_LINE
local ENCHANT_LINE
if type(ENCHANTED) == "string" then
	local safe = (ENCHANTED:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
	ENCHANT_LINE = "^" .. (safe:gsub("%%%%s", "(.+)")) .. "$"
end

-- What is enchanted onto a piece, by name, or nil for a piece with nothing on
-- it.
--
-- Asked of the link and not of the slot, so the caller that already has the
-- link does not make the client find it twice.
--
-- **The id comes first and it is the whole of the saving.** An item link
-- carries the enchant as a number in its second field and carries no name at
-- all, so a name costs a tooltip scan; but the number is free, and a piece with
-- nothing on it says so in the link before anything is asked of a tooltip. On a
-- character wearing eleven enchanted pieces out of nineteen that is eight scans
-- that never happen, and on a fresh one it is all nineteen.
function Worn.Enchant(link)
	if type(link) ~= "string" or not ENCHANT_LINE then
		return nil
	end
	local id = link:match("item:%d+:(%d+)")
	if not id or id == "0" then
		return nil
	end
	return ns.UI.Scan.Match("item", ENCHANT_LINE, link)
end

-- How many seconds are left on the stone, the oil or the poison on this hand.
--
-- Nil for a hand with nothing on it, for the ranged slot and for a client with
-- no such call, and the caller draws all three the same way, which is nothing
-- at all. Zero would be wrong for every one of them: a hand at zero seconds is
-- a hand whose enchant has just lapsed, which is a thing worth saying, and a
-- hand nobody can ask about is not.
--
-- Buffs/Upkeep.lua is the reader and this is its second caller. That file
-- already counts how many values GetWeaponEnchantInfo answers with on this
-- client and picks the stride from the count, and its header says at length why
-- reading the call positionally on a guess is the failure worth avoiding. A
-- second reader here would be a second guess.
--
-- The ranged slot answers nothing and that is the client rather than a gap
-- here. The call has covered a ranged hand since Cataclysm and this is 2.5.6;
-- there is no stone, oil or poison in this expansion that goes on a bow.
function Worn.Oil(slot)
	if slot ~= 16 and slot ~= 17 then
		return nil
	end
	local mine, mineLeft, other, otherLeft = ns.Upkeep.Enchants()
	if mine == nil then
		return nil
	end
	if slot == 16 then
		return mine and mineLeft or nil
	end
	return other and otherLeft or nil
end

--------------------------------------------------------------------------
-- The two summaries under the paperdoll
--------------------------------------------------------------------------

-- How worn your gear is, as one fraction, plus the slot that is furthest gone.
--
-- Summed rather than averaged over the pieces, because a percentage per piece
-- averaged is a number that says a broken weapon and a fresh shirt are half of
-- each other. What the repair bill actually is proportional to is the points,
-- so the points are what is added up.
--
-- Nil where nothing in the list answered, which is a character wearing nothing
-- and a client with no such call, and both draw the same line.
function Worn.Wear()
	local current, maximum = 0, 0
	local worst, worstAt
	for index = 1, #SLOTS do
		local entry = SLOTS[index]
		local has, of = Worn.Durability(entry.slot)
		if has then
			current, maximum = current + has, maximum + of
			local fraction = has / of
			if not worst or fraction < worst then
				worst, worstAt = fraction, entry
			end
		end
	end
	if maximum == 0 then
		return nil
	end
	return current / maximum, worstAt, worst
end

-- The average item level of what you have on, and how many slots are empty.
--
-- Shirt and tabard are skipped, and so is an off hand you cannot fill because
-- your main hand is a two hander: counting an empty slot nobody may fill is
-- counting a decision the game made for you as a gap in your gear.
function Worn.Level()
	local total, pieces, empty = 0, 0, 0
	local twoHanded = false
	local main = Worn.Link(16)
	if main then
		local _, _, equip = ns.ItemInfo(main)
		twoHanded = equip == "INVTYPE_2HWEAPON"
	end

	for index = 1, #SLOTS do
		local entry = SLOTS[index]
		local skip = entry.trim or (entry.slot == 17 and twoHanded)
		if not skip then
			local link = Worn.Link(entry.slot)
			local level = link and ns.ItemLevel(link)
			if level and level > 0 then
				total, pieces = total + level, pieces + 1
			elseif not link then
				empty = empty + 1
			end
		end
	end

	if pieces == 0 then
		return nil, empty
	end
	return total / pieces, empty, pieces
end

--------------------------------------------------------------------------
-- Putting something on
--
-- One call and two questions. The call is the swap; the questions are whether
-- the client will take it and whether the click meant something else entirely.
--------------------------------------------------------------------------

-- The three the client will let you change in a fight. A weapon swap mid pull
-- is a thing the game allows and a thing warriors do, and it is the whole of
-- what combat allows: everything else is refused by the server with its own
-- message, which is the rule Blizzard's own sheet plays by.
local IN_COMBAT = {
	[16] = true, -- main hand
	[17] = true, -- off hand
	[18] = true, -- ranged
}

-- Whether a slot can be touched at all right now, and why not where it cannot.
-- Asked before the call below, so the page can say why rather than offering a
-- click that quietly does nothing.
--
-- The fight is asked about the slot rather than about the fight. This used to
-- refuse all nineteen in combat, which was one rule too broad: it also refused
-- the hands, and putting a weapon in your hand mid pull is the one gear change
-- the game is happy about.
function Worn.Free(slot)
	if InCombatLockdown and InCombatLockdown() and not IN_COMBAT[slot] then
		return false, "armour cannot be changed in a fight."
	end
	if type(_G.PickupInventoryItem) ~= "function" then
		return false, "this client has no call for moving an item into a slot."
	end
	return true
end

-- Whatever is on the cursor into this slot, and whatever was in the slot onto
-- the cursor. With an empty cursor it is the second half alone, which is how a
-- click takes something off.
--
-- Not while a spell is waiting for an item, which the page asks about first: in
-- that state the click is pointing the spell at this piece and the swap would
-- be both the wrong thing and a forbidden one.
function Worn.Swap(slot)
	local free, why = Worn.Free(slot)
	if not free then
		return false, why
	end
	if not pcall(_G.PickupInventoryItem, slot) then
		return false, "the client refused the swap."
	end
	return true
end

-- Whether the client is holding a spell that is waiting for an item.
--
-- True from the moment a stone, an oil, a scroll or a poison is used until it
-- lands or is cancelled. In that state a click on a slot means "that one", the
-- client's own secure template lands it on the slot, and the only thing the
-- page owes the arrangement is to not run the swap above over the top of it.
-- Asked before the click rather than after, because the landing is what clears
-- the state.
--
-- Both names, through the same pcall every other client call here goes through,
-- because the two clients this addon runs on need not agree that either exists.
-- A client that answers neither is a client where nothing can be waiting, which
-- is the state the page already draws.
function Worn.Targeting()
	if Ask("SpellCanTargetItem") then
		return true
	end
	return Ask("SpellCanTargetItemID") and true or false
end

--------------------------------------------------------------------------

function Worn.Describe()
	local level, empty = Worn.Level()
	local wear = Worn.Wear()
	if not level then
		return "nothing on"
	end
	local parts = ("item level %.1f"):format(level)
	if wear then
		parts = ("%s, %d%% durability"):format(parts, math.floor(wear * 100 + 0.5))
	end
	if empty > 0 then
		parts = ("%s, %d slot%s empty"):format(parts, empty, empty == 1 and "" or "s")
	end
	return parts
end
