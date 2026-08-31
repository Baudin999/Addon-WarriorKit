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
-- things you are not wearing, asked so a loadout can name one in a macro line.
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
-- Both calls are refused in a fight, by the client rather than by this file,
-- and the refusal is silent. So the fight is checked here and the reason is
-- said out loud: a slot that does nothing when you click it is the worst
-- version of this page.
--
-- **Nothing is cached.** What you are wearing changes on an event the client
-- fires, the window redraws on that event, and a cache between the two would be
-- one more thing that can be stale while the picture says otherwise. The one
-- thing kept is the empty-slot art, which is a texture path the client answers
-- the same way for the life of the session.
--------------------------------------------------------------------------

-- The nineteen, in the order the page draws them: down the left, down the
-- right, then the three weapons under the middle. That is the client's own
-- arrangement and it is kept because it is the one every player already knows
-- where to look in.
--
--   slot   the inventory number, which is what every call below takes
--   key    the client's own name for the slot, which is how the empty art is
--          asked for rather than written down as a texture path
--   label  what this addon calls it, lower case like every other label here
--   side   which of the three groups it is drawn in
--
-- Shirt and tabard are in the list and are left out of the two summaries at the
-- bottom of the page on purpose: neither has an item level, neither wears out,
-- and counting them would drag both numbers down for wearing a guild tabard.
local SLOTS = {
	{ slot = 1,  key = "HeadSlot",          label = "head",      side = "left" },
	{ slot = 2,  key = "NeckSlot",          label = "neck",      side = "left" },
	{ slot = 3,  key = "ShoulderSlot",      label = "shoulder",  side = "left" },
	{ slot = 15, key = "BackSlot",          label = "back",      side = "left" },
	{ slot = 5,  key = "ChestSlot",         label = "chest",     side = "left" },
	{ slot = 4,  key = "ShirtSlot",         label = "shirt",     side = "left", trim = true },
	{ slot = 19, key = "TabardSlot",        label = "tabard",    side = "left", trim = true },
	{ slot = 9,  key = "WristSlot",         label = "wrist",     side = "left" },

	{ slot = 10, key = "HandsSlot",         label = "hands",     side = "right" },
	{ slot = 6,  key = "WaistSlot",         label = "waist",     side = "right" },
	{ slot = 7,  key = "LegsSlot",          label = "legs",      side = "right" },
	{ slot = 8,  key = "FeetSlot",          label = "feet",      side = "right" },
	{ slot = 11, key = "Finger0Slot",       label = "ring",      side = "right" },
	{ slot = 12, key = "Finger1Slot",       label = "ring",      side = "right" },
	{ slot = 13, key = "Trinket0Slot",      label = "trinket",   side = "right" },
	{ slot = 14, key = "Trinket1Slot",      label = "trinket",   side = "right" },

	{ slot = 16, key = "MainHandSlot",      label = "main hand", side = "hands" },
	{ slot = 17, key = "SecondaryHandSlot", label = "off hand",  side = "hands" },
	{ slot = 18, key = "RangedSlot",        label = "ranged",    side = "hands" },
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
-- Putting something on and taking it off
--
-- Two calls, one line each, and the whole of this section is the sentence that
-- comes back when the client will not take them.
--------------------------------------------------------------------------

-- Whether a slot can be touched at all right now, and why not where it cannot.
-- Asked before either call below, so the page can grey a slot rather than
-- offering a click that quietly does nothing.
function Worn.Free()
	if InCombatLockdown and InCombatLockdown() then
		return false, "gear cannot be changed in a fight."
	end
	if type(_G.PickupInventoryItem) ~= "function" then
		return false, "this client has no call for moving an item into a slot."
	end
	return true
end

-- Whatever is on the cursor into this slot, and whatever was in the slot onto
-- the cursor. With an empty cursor it is the second half alone, which is how a
-- click takes something off.
function Worn.Swap(slot)
	local free, why = Worn.Free()
	if not free then
		return false, why
	end
	if not pcall(_G.PickupInventoryItem, slot) then
		return false, "the client refused the swap."
	end
	return true
end

-- Off, into your bags. The client's own call, which uses the item where the
-- item has a use, so a trinket right clicked here fires rather than coming off.
-- That is the client's behaviour on its own sheet and it is the behaviour
-- anybody clicking a trinket is expecting.
function Worn.Use(slot)
	local free, why = Worn.Free()
	if not free then
		return false, why
	end
	if type(_G.UseInventoryItem) ~= "function" then
		return false, "this client has no call for taking a worn item off."
	end
	if not pcall(_G.UseInventoryItem, slot) then
		return false, "the client refused it."
	end
	return true
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
