local ADDON, ns = ...

local Gear = {}
ns.Gear = Gear

--------------------------------------------------------------------------
-- What the client will let into a hand, and which number that hand is
--
-- An /equipslot line is the only way an addon can put a weapon in your hand
-- during a fight, and it takes an item name. Typing that name was the only way
-- to set it, which meant a typo produced a macro line that silently did
-- nothing and nothing on screen said so. So nothing in this addon takes a name
-- typed by hand: the panel offers what you are actually carrying, and this
-- file is the part that knows what you are carrying.
--
-- It was Charge/Weapons.lua and it knew about one slot, because one part
-- needed one weapon. Two parts need two hands now. It is a shared file rather
-- than a reach across a folder boundary, and it is in Core for the same reason
-- ns.ItemInfo is: it wraps a client API and owns no setting.
--------------------------------------------------------------------------

Gear.MAINHAND = 16 -- INVSLOT_MAINHAND, the number the macro equips into
Gear.OFFHAND = 17  -- INVSLOT_OFFHAND

-- A one hander, a main hander and a two hander go in the main hand. A shield,
-- a held-in-off-hand item, an off hander and, because warriors dual wield, a
-- plain one hander go in the off hand. Anything else builds an /equipslot line
-- the client refuses, so offering one is worse than not offering it.
--
-- A two hander is deliberately absent from the off hand list. Titan's Grip is
-- three expansions after the newest client this addon runs on.
local FITS = {
	[Gear.MAINHAND] = {
		INVTYPE_WEAPON = true,
		INVTYPE_WEAPONMAINHAND = true,
		INVTYPE_2HWEAPON = true,
	},
	[Gear.OFFHAND] = {
		INVTYPE_WEAPON = true,
		INVTYPE_WEAPONOFFHAND = true,
		INVTYPE_SHIELD = true,
		INVTYPE_HOLDABLE = true,
	},
}

-- The client's own name for each slot, which is how the empty-slot art is
-- asked for rather than written down as a texture path. Baganator calls
-- GetInventorySlotInfo unguarded on the TBC client and TitanAmmo calls it on
-- both, which is what proves it is here.
local SLOT_NAMES = {
	[Gear.MAINHAND] = "MAINHANDSLOT",
	[Gear.OFFHAND] = "SECONDARYHANDSLOT",
}

local LAST_BAG = 4 -- backpack is 0, and neither client has a reagent bag

-- Built on demand and thrown away whenever the bags or the worn gear move,
-- because the panel asks for this list on every refresh and a refresh is every
-- click anywhere in the window.
local cache = {}
local art = {}

function Gear.Fits(slot, equip)
	local fits = FITS[slot]
	return (fits and equip and fits[equip]) and true or false
end

local function Add(slot, list, seen, link, equipped)
	local name, icon, equip, color = ns.ItemInfo(link)
	if not name or not Gear.Fits(slot, equip) then
		return
	end

	local key = name:lower()
	if seen[key] then
		return
	end
	seen[key] = true

	local text = color and ("|c" .. color .. name .. "|r") or name
	if equipped then
		text = text .. " |cff808080(equipped)|r"
	end

	list[#list + 1] = {
		value = name,
		name = name,
		text = text,
		icon = icon,
		equip = equip,
		equipped = equipped and true or false,
	}
end

local function Scan(slot)
	local list, seen = {}, {}

	Add(slot, list, seen, GetInventoryItemLink("player", slot), true)
	-- The other hand too. A one hander worn in the main hand is a legal off
	-- hand and the pair is often the same two items swapping places, so a list
	-- that showed only the bags would leave the obvious answer off it.
	for other in pairs(FITS) do
		if other ~= slot then
			Add(slot, list, seen, GetInventoryItemLink("player", other), true)
		end
	end
	for bag = 0, LAST_BAG do
		for index = 1, ns.ContainerSlots(bag) do
			Add(slot, list, seen, ns.ContainerItemLink(bag, index))
		end
	end

	table.sort(list, function(a, b)
		if a.equipped ~= b.equipped then
			return a.equipped
		end
		return a.name < b.name
	end)

	return list
end

local function Carried(slot)
	if not cache[slot] then
		cache[slot] = Scan(slot)
	end
	return cache[slot]
end

-- The row for one item this character is carrying, or nil. Everything the
-- panel draws about a saved name goes through here: the icon beside it, the
-- colour of its name, and whether the swap will fire at all.
function Gear.Find(slot, name)
	if not name or name == "" then
		return nil
	end
	local wanted = name:lower()
	for _, item in ipairs(Carried(slot)) do
		if item.value:lower() == wanted then
			return item
		end
	end
	return nil
end

-- Whether the saved name is something the client can equip right now. An
-- /equipslot line for an item you are not carrying is the failure this whole
-- file exists to make visible.
function Gear.Held(slot, name)
	return Gear.Find(slot, name) ~= nil
end

-- What an item link would be if it went in that slot: the name to save, or nil
-- and the reason it will not go. The reason is written for a player reading it
-- under a slot they just dropped something onto.
function Gear.Accepts(slot, link)
	local name, icon, equip = ns.ItemInfo(link)
	if not name then
		return nil, "that is not an item."
	end
	if not Gear.Fits(slot, equip) then
		if slot == Gear.OFFHAND and equip == "INVTYPE_2HWEAPON" then
			return nil, ("%s is a two hander. It only goes in the main hand."):format(name)
		end
		return nil, ("%s does not go in that hand."):format(name)
	end
	return name, icon
end

-- The client's own empty-slot art, asked for by slot name rather than written
-- down as a texture path. Probed, because a client that does not answer should
-- leave an empty square rather than raise.
function Gear.Art(slot)
	if art[slot] == nil then
		local texture
		if type(GetInventorySlotInfo) == "function" and SLOT_NAMES[slot] then
			local ok, _, path = pcall(GetInventorySlotInfo, SLOT_NAMES[slot])
			texture = ok and path or nil
		end
		art[slot] = texture or false
	end
	return art[slot] or nil
end

-- The picker rows: an empty row, then everything that could go in that slot,
-- then the name already saved when that name is among neither. The last of
-- those is how a weapon in the bank stays set rather than being dropped by a
-- panel that cannot see it, and it says on the row why it is greyed.
function Gear.List(slot, current, emptyText)
	local list = { { value = "", text = emptyText or "|cff909090none|r" } }
	local found = (current == nil or current == "")

	for _, item in ipairs(Carried(slot)) do
		list[#list + 1] = item
		if not found and item.value:lower() == current:lower() then
			found = true
		end
	end

	if not found then
		list[#list + 1] = {
			value = current,
			text = current .. " |cff808080(not in your bags)|r",
		}
	end

	return list
end

function Gear.Forget()
	wipe(cache)
end

-- BAG_UPDATE and UNIT_INVENTORY_CHANGED rather than the later, quieter events
-- of the same shape: these two are vanilla-era and so exist on both clients,
-- and all they cost here is dropping a table.
local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("UNIT_INVENTORY_CHANGED")
events:SetScript("OnEvent", function(_, event, unit)
	if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then
		return
	end
	Gear.Forget()
end)
