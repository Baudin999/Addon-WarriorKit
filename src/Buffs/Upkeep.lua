local ADDON, ns = ...

local Upkeep = {}
ns.Upkeep = Upkeep

--------------------------------------------------------------------------
-- What should be up and is not
--
-- Nothing in this addon read your own auras before this file. That is a real
-- hole rather than a missing convenience: a sharpening stone that wore off
-- forty minutes ago costs more damage over a raid than any single rotational
-- mistake, and Battle Shout falling off says nothing at all.
--
-- Two sources, because the client answers two different questions and only one
-- of them is an aura.
--
--   A weapon's temporary enchant is not a buff on you. It does not appear in an
--   aura scan at any index, and GetWeaponEnchantInfo is the only thing in the
--   client that knows about it.
--
--   Everything else is a buff on you and is found by walking your own auras.
--
-- Matching is on the name, never on the id, which is the rule the debuff row on
-- the enemy bars already follows. Battle Shout has eight ranks and the aura on
-- you carries the id of whichever rank was shouted, so an id comparison would
-- go dark the moment you trained the next one. The ids below exist only to ask
-- this client what it calls the spell in the language it is running in, which
-- is what makes the comparison locale independent.
--
-- The aura scan is event driven and never runs from the ticker. UNIT_AURA fires
-- for every aura you gain and every aura you lose, so a walk of forty slots ten
-- times a second would be four hundred lookups to learn what one event already
-- said. It is worse than that on a client carrying C_UnitAuras, where each slot
-- hands back a freshly built table: that is allocation on a ticker, which is
-- the thing scripts/harness.lua gates and check.sh bans.
--
-- The weapon enchants are the exception and are read on the tick, because a
-- stone that runs out fires nothing. Two values out of one call, no table and
-- no string, which is what makes that affordable.
--------------------------------------------------------------------------

local MAIN, OFF = ns.Gear.MAINHAND, ns.Gear.OFFHAND

-- Probed rather than trusted, and resolved to a local at load the way
-- Swing/Swing.lua resolves UnitAttackSpeed. Nothing installed on this machine
-- calls OffhandHasWeapon at all, and the only unguarded GetWeaponEnchantInfo
-- here is inside a Details library written for a much later client. A missing
-- one costs the weapon half of this feature; a missing one called anyway costs
-- an error ten times a second, which is the failure that gets a whole addon
-- offered up for disabling.
local GetWeaponEnchantInfo = _G.GetWeaponEnchantInfo
local OffhandHasWeapon = _G.OffhandHasWeapon
local UnitAura = _G.UnitAura

-- How many of your own aura slots the client will answer for. Forty is the
-- number every aura scan in the game uses and the number the enemy bars' own
-- debuff walk stops at.
local SLOTS = 40

-- How many spells of your own you may add on top of the four below. Six,
-- because the list this covers in practice is a flask and one or two elixirs,
-- and a nag row long enough to need scrolling is a nag row nobody reads.
local MAX_EXTRA = 6

--------------------------------------------------------------------------
-- The four that ship
--
-- Each is here because it is silent when it lapses and expensive while it is
-- lapsed. Nothing that announces itself belongs on this list.
--
-- Two of them are hands rather than auras, and they are the reason this file
-- exists at all. The other two are the cheapest buffs in the game to keep up
-- and the two most often forgotten after a wipe.
--------------------------------------------------------------------------

local FIXED = {
	-- The main hand, which is the sharpening stone, the oil or the shaman's
	-- imbue. Nagged only while there is a weapon in the slot, because an empty
	-- hand is a state you are in on purpose and briefly.
	{ key = "mainhand", hand = MAIN, label = "main hand" },

	-- The off hand, and the one entry in this file with a rule about what it
	-- must not do. A shield takes no stone, a held-in-off-hand item takes no
	-- stone, and an empty off hand is most warriors most of the time. All three
	-- answer false to OffhandHasWeapon, which is the client's own question of
	-- "is there a weapon in that hand", so the test is that call and not
	-- whether the slot has something in it.
	{ key = "offhand", hand = OFF, label = "off hand" },

	-- Battle Shout, rank 1. Warrior only, because it is the one entry on this
	-- list that is a class ability rather than something anybody standing in
	-- melee wants. Rank 1 covers all eight, because the match is by name.
	--
	-- 6673 is Battle Shout rank 1: Wowhead's TBC database gives 6673 as Battle
	-- Shout, 10 rage, +15 attack power for 2 minutes, which is rank 1's own
	-- number. Rank 3 of the same spell, 6192, is in this install's Details
	-- saved variables off a live 2.5.6 session, so the ranked chain is real on
	-- this client.
	{ key = "shout", spell = 6673, warrior = true, fixed = "battle shout" },

	-- Food. Every food buff in the game lands as one aura called Well Fed, and
	-- 19705 is the id this file asks the client to spell that phrase for. It is
	-- Nightfin Soup's buff on Wowhead's TBC database, named exactly "Well Fed",
	-- and which food granted it does not matter: the name is the thing being
	-- compared and every food shares it.
	{ key = "food", spell = 19705, fixed = "food" },
}

--------------------------------------------------------------------------
-- What is not on that list, and will not be
--
-- Flasks and elixirs, which are the obvious fifth entry and are deliberately a
-- setting instead.
--
-- These clients will not tell you that an aura came from an elixir. There is no
-- category on an aura, no flag, and no call that maps one back to the item that
-- applied it. The only way to ship a built-in flask check is a hand written
-- table of every flask and battle and guardian elixir id in the expansion,
-- which is about forty numbers that cannot be verified from outside the game,
-- go stale on the next content patch, and are wrong in a way nothing reports.
--
-- So the list is yours. `/wk buffs add <spell id>` puts an aura on the row and
-- the panel says where to find the id, exactly the way the debuff row on the
-- enemy bars takes one. Six slots, and the same rule as everywhere else in this
-- addon: use the id of the aura that lands on you, not of the item.
--------------------------------------------------------------------------

-- The live list, rebuilt at login and whenever the extra list moves. Never
-- rebuilt from a tick.
local order = {}

-- This client's name for an aura, to the entry that wants it. One lookup per
-- aura slot per scan instead of a walk of the list per slot.
local wanted = {}

-- The extra entries, pooled. A rebuild reuses these tables rather than making
-- new ones, because a rebuild runs on every add and every remove and the panel
-- can call it a dozen times while somebody is deciding.
local extras = {}
for index = 1, MAX_EXTRA do
	extras[index] = { key = "extra" .. index }
end

-- How many entries the row must be built to hold. A frame cannot be destroyed
-- on this client, only hidden, so Nag.lua builds this many squares once and
-- shows as many of them as the list is long.
function Upkeep.Ceiling()
	return #FIXED + MAX_EXTRA
end

function Upkeep.Count()
	return #order
end

function Upkeep.Entry(index)
	return order[index]
end

--------------------------------------------------------------------------
-- The weapon enchants
--
-- GetWeaponEnchantInfo has had three shapes. The oldest answers six values,
-- three per hand: whether there is an enchant, how many milliseconds are left,
-- and how many charges. 6.0 put the enchant's own id after the charges, which
-- makes it eight. Cataclysm added a ranged hand, which makes it twelve.
--
-- Nothing on this machine settles which of the three 2.5.6 and 1.15.9 answer
-- with. The one unguarded call in this install is inside a Details library
-- written against a much later client and reads the eight value shape, and the
-- language server stub beside it disagrees with itself twice.
--
-- So it is counted rather than assumed. select("#", f()) is the exact number of
-- values the client returned, whatever they are, and the only thing this file
-- needs from it is the stride between the two hands: three on the old shape and
-- four on either newer one.
--
-- Reading it positionally on a guess is the failure worth avoiding. At stride
-- three against a client that answers eight, the off hand's "has an enchant"
-- would be read out of the main hand's enchant id, which is a number, which is
-- truthy, which is a nag that never fires and never says why.
--
-- Counted on every read rather than once. A client does not change its mind
-- about an API mid-session, so a cache would be correct; what a cache also is
-- is a client answer this file has written down, and the whole point of the
-- count is not to have written a client answer down. It costs one extra call to
-- a function that reads two numbers off the player, four times a tenth of a
-- second, which is not a cost.
--------------------------------------------------------------------------

function Upkeep.EnchantShape()
	if type(GetWeaponEnchantInfo) ~= "function" then
		return nil
	end
	if select("#", GetWeaponEnchantInfo()) >= 8 then
		return 4
	end
	return 3
end

-- Both hands out of one call: whether each is enchanted and how many seconds
-- each has left. Nil when this client has no such call at all, which is "do not
-- know" and not "nothing is enchanted", so nothing is nagged about.
--
-- On the tick. No table, no string, no concatenation.
function Upkeep.Enchants()
	local step = Upkeep.EnchantShape()
	if not step then
		return nil
	end
	if step == 4 then
		local mine, mineLeft, _, _, other, otherLeft = GetWeaponEnchantInfo()
		return mine and true or false, (mineLeft or 0) / 1000,
			other and true or false, (otherLeft or 0) / 1000
	end
	local mine, mineLeft, _, other, otherLeft = GetWeaponEnchantInfo()
	return mine and true or false, (mineLeft or 0) / 1000,
		other and true or false, (otherLeft or 0) / 1000
end

-- Whether that hand is holding something a stone goes on and has nothing on it.
--
-- The off hand asks the client rather than the inventory slot, which is the
-- whole of the shield rule. A shield, a held-in-off-hand item and an empty hand
-- all answer false to OffhandHasWeapon and none of the three is ever nagged
-- about. Where the client has no such call the off hand is left alone entirely,
-- because guessing off the slot would nag every tank in the addon about the
-- shield they are meant to be holding.
function Upkeep.Bare(hand)
	local mine, _, other = Upkeep.Enchants()
	if mine == nil then
		return false
	end
	if hand == OFF then
		if type(OffhandHasWeapon) ~= "function" then
			return false
		end
		if not OffhandHasWeapon() then
			return false
		end
		return not other
	end
	if not GetInventoryItemLink("player", MAIN) then
		return false
	end
	return not mine
end

-- How long that hand's enchant has to run, in seconds, or nil when there is
-- nothing on it. For the status line and the panel, never for the row: the row
-- says missing or nothing at all.
function Upkeep.Left(hand)
	local mine, mineLeft, other, otherLeft = Upkeep.Enchants()
	if mine == nil then
		return nil
	end
	if hand == OFF then
		return other and otherLeft or nil
	end
	return mine and mineLeft or nil
end

--------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------

-- One aura slot's name. UnitAura is asked first and C_UnitAuras second, which
-- is the opposite way round from the spell shims in Core and is deliberate: the
-- old call hands back a string and the new one hands back a table it built to
-- put the string in. This scan wants the string. Where only the new call
-- exists the table is made and dropped, which is the cost of that client.
local function AuraName(index)
	if type(UnitAura) == "function" then
		return (UnitAura("player", index, "HELPFUL"))
	end
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		local aura = C_UnitAuras.GetBuffDataByIndex("player", index)
		return aura and aura.name
	end
	return nil
end

-- Which of the tracked auras are on you. Called from an event, never a tick.
function Upkeep.Scan()
	for index = 1, #order do
		order[index].present = false
	end

	local index = 1
	while index <= SLOTS do
		local name = AuraName(index)
		if not name then
			break
		end
		local entry = wanted[name]
		if entry then
			entry.present = true
		end
		index = index + 1
	end
end

-- The art each hand's square draws, which is the weapon you are holding. That
-- says what the nag is about better than a picture of a stone would: the square
-- is your own axe with a red edge round it, and the axe you swapped to is the
-- one that has nothing on it.
--
-- Re-read whenever the worn gear moves, and never on the tick.
function Upkeep.Refit()
	for index = 1, #order do
		local entry = order[index]
		if entry.hand then
			local _, icon = ns.ItemInfo(GetInventoryItemLink("player", entry.hand))
			entry.texture = icon or ns.Gear.Art(entry.hand)
		end
	end
end

-- Rebuild the live list from the four above and whatever you have added.
--
-- Battle Shout is the one entry gated on class, and it is gated here rather
-- than at the top of the file so that the rest of the part works for anyone.
-- ns.IsWarrior is asked at every rebuild rather than cached, for the reason
-- Core states: the class is not reliably known while files load, and a wrong no
-- cached at load would cost a warrior the entry for the whole session.
function Upkeep.Rebuild()
	for index = #order, 1, -1 do
		order[index] = nil
	end
	for name in pairs(wanted) do
		wanted[name] = nil
	end

	for index = 1, #FIXED do
		local entry = FIXED[index]
		if not entry.warrior or ns.IsWarrior() then
			order[#order + 1] = entry
		end
	end

	local list = ns.db.buffExtra
	for index = 1, math.min(#list, MAX_EXTRA) do
		local entry = extras[index]
		entry.spell = list[index]
		order[#order + 1] = entry
	end

	for index = 1, #order do
		local entry = order[index]
		entry.present = false
		if entry.spell then
			entry.name = ns.SpellName(entry.spell)
			entry.texture = ns.SpellTexture(entry.spell)
			-- A shipped entry says what it is in the caption's own words; one
			-- you added says whatever this client calls it, because "flask" is
			-- not a word the client would use and the spell's name is.
			entry.label = entry.fixed or entry.name or ("spell " .. entry.spell)
			if entry.name then
				wanted[entry.name] = entry
			end
		end
	end

	Upkeep.Refit()
	Upkeep.Scan()
end

-- Is the index'th entry missing right now. On the tick, so it reads a field for
-- an aura and makes one call for a hand.
--
-- An entry this client cannot name is never missing. That is the same answer
-- the debuff row gives an id it does not know: the slot keeps its place in case
-- you log in on the flavour that does know it, and nothing is drawn meanwhile.
function Upkeep.Missing(index)
	local entry = order[index]
	if not entry then
		return false
	end
	if entry.hand then
		return Upkeep.Bare(entry.hand)
	end
	if not entry.name then
		return false
	end
	return not entry.present
end

--------------------------------------------------------------------------
-- The list you keep
--------------------------------------------------------------------------

function Upkeep.Extra()
	return ns.db.buffExtra
end

function Upkeep.MaxExtra()
	return MAX_EXTRA
end

function Upkeep.Add(spell)
	local id = tonumber(spell)
	if not id or id <= 0 then
		return false, "that is not a spell id."
	end
	local list = ns.db.buffExtra
	for index = 1, #list do
		if list[index] == id then
			return false, (ns.SpellName(id) or ("spell " .. id)) .. " is already on the row."
		end
	end
	if #list >= MAX_EXTRA then
		return false, ("the row holds %d of your own and it is full."):format(MAX_EXTRA)
	end
	list[#list + 1] = id
	Upkeep.Rebuild()
	return true, ns.SpellName(id) or ("spell " .. id .. ", which this client cannot name")
end

function Upkeep.Remove(spell)
	local id = tonumber(spell)
	local list = ns.db.buffExtra
	for index = 1, #list do
		if list[index] == id then
			table.remove(list, index)
			Upkeep.Rebuild()
			return true
		end
	end
	return false
end

-- One line for the status and the panel. Names what is missing right now, which
-- is the only thing anybody types this to find out.
function Upkeep.Describe()
	if #order == 0 then
		return "nothing tracked"
	end
	local missing = 0
	for index = 1, #order do
		if Upkeep.Missing(index) then
			missing = missing + 1
		end
	end
	if missing == 0 then
		return ("%d tracked, all up"):format(#order)
	end
	return ("%d tracked, %d missing"):format(#order, missing)
end
