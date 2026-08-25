local ADDON, ns = ...

local Weapons = {}
ns.ChargeWeapons = Weapons

-- What the charge button is allowed to put in your hand, and where the number
-- 16 in the macro comes from.
--
-- The button carries an /equipslot line so a charge can bring the weapon you
-- want to open with. Typing that name was the only way to set it, which meant
-- a typo produced a macro line that silently did nothing, and nothing on
-- screen said so. So the panel picks from what you are actually carrying, and
-- this file is the part that knows what you are carrying.

Weapons.SLOT = 16 -- INVSLOT_MAINHAND, the slot the macro equips into

-- A one hander, a main hander and a two hander all go in slot 16. Off hands,
-- shields, held-in-off-hand items and anything ranged do not, and offering one
-- would build a macro line the client refuses.
local MAIN_HAND = {
	INVTYPE_WEAPON = true,
	INVTYPE_WEAPONMAINHAND = true,
	INVTYPE_2HWEAPON = true,
}

local LAST_BAG = 4 -- backpack is 0, and neither client has a reagent bag

-- Built on demand and thrown away whenever the bags or the worn gear move,
-- because the panel asks for this list on every refresh and a refresh is every
-- click anywhere in the window.
local cache

local function Add(list, seen, link, equipped)
	local name, icon, equip, color = ns.ItemInfo(link)
	if not name or not MAIN_HAND[equip or ""] then
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
		equipped = equipped and true or false,
	}
end

local function Scan()
	local list, seen = {}, {}

	Add(list, seen, GetInventoryItemLink("player", Weapons.SLOT), true)
	for bag = 0, LAST_BAG do
		for slot = 1, ns.ContainerSlots(bag) do
			Add(list, seen, ns.ContainerItemLink(bag, slot))
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

-- The picker rows: no swap, then everything that could go in slot 16, then the
-- name already saved when that name is not among them. The last of those is
-- how a weapon in the bank stays set rather than being dropped by a panel that
-- cannot see it, and it says on the row why it is greyed.
function Weapons.List(current)
	if not cache then
		cache = Scan()
	end

	local list = { { value = "", text = "|cff909090no weapon swap|r" } }
	local found = (current == nil or current == "")

	for _, item in ipairs(cache) do
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

-- Whether the saved name is something the client can equip right now. The
-- panel says so under the row, because an /equipslot line for an item you are
-- not carrying is the failure this whole file exists to make visible.
function Weapons.Carried(name)
	if not name or name == "" then
		return false
	end
	if not cache then
		cache = Scan()
	end
	for _, item in ipairs(cache) do
		if item.value:lower() == name:lower() then
			return true
		end
	end
	return false
end

function Weapons.Forget()
	cache = nil
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
	Weapons.Forget()
end)
