-- Everything about the player themselves that the buff nag reads
--
-- One table rather than one local each, for the reason `chat` in 01-widgets
-- is one table: eight names is eight things for 30-buff-nag.lua to ask for and
-- eight to keep in step, and the table is one.
--
--   race, raceName  what UnitRace answers, token second
--   main, mainLeft  the main hand's temporary enchant and its milliseconds
--   off, offLeft    the off hand's
--   wide            which shape GetWeaponEnchantInfo answers in
--   resting, dead   the two states that silence the missing buff row
--   auras           the buffs on you, in slot order
--   cooldowns       spell id to start and duration, for the racial

local H = ...
local state = H.state
local WARRIOR, chat, constant = H.WARRIOR, H.chat, H.constant
local unitName = H.unitName

local own = {
	race = "Orc", raceName = "Orc",
	main = false, mainLeft = 0, off = false, offLeft = 0, wide = false,
	resting = false, dead = false,
	auras = {},
	cooldowns = {},
	-- Spell ids this character has not learned, which is what a talent nobody
	-- spent a point on looks like to the addon. Empty in the shipped scene, so
	-- IsSpellKnown answers true for everything the way the constant it replaced
	-- did, and the cooldown row's section fills it to prove that an unlearned
	-- entry takes no square.
	unknown = {},
	-- What a worn item's own cooldown reads, keyed by inventory slot. The two
	-- trinket slots are the only ones anything asks about.
	worn = {},
}

-- The race, as the client answers it: a localised name first and a token
-- second. The name is deliberately not spelled the same as the token, so a file
-- that read the wrong return finds nothing in its table even on a client
-- running in English.
--
-- A variable rather than a constant, because the whole point of the racial half
-- is that an orc gets Blood Fury and a troll gets Berserking, and a stub that
-- answered one race would leave the other branch unreachable.
_G.UnitRace = function(unit)
	if unit ~= "player" then
		return nil, nil
	end
	return own.raceName, own.race
end

-- Your own temporary weapon enchants, and the one stub in this file whose shape
-- is itself the thing under test.
--
-- GetWeaponEnchantInfo has had three shapes: six values at three per hand,
-- eight once 6.0 put the enchant's own id after the charges, and twelve once
-- Cataclysm added a ranged hand. Nothing on this machine settles which of them
-- 2.5.6 and 1.15.9 answer with, so Buffs/Upkeep.lua counts the returns rather
-- than reading them positionally on a guess.
--
-- `wide` drives that count and both settings are exercised. On the eight value
-- shape the main hand's enchant id sits exactly where the six value shape puts
-- "the off hand has an enchant", and it is a number, and a number is truthy: a
-- parser that guessed three would say the off hand was enchanted forever and
-- never say why. That is what the buff section asserts.
_G.GetWeaponEnchantInfo = function()
	if own.wide then
		return own.main, own.mainLeft, own.main and 5 or 0, own.main and 2506 or 0,
			own.off, own.offLeft, own.off and 5 or 0, own.off and 2506 or 0
	end
	return own.main, own.mainLeft, own.main and 5 or 0,
		own.off, own.offLeft, own.off and 5 or 0
end

_G.IsResting = function() return own.resting end
_G.UnitIsDeadOrGhost = function() return own.dead end

-- Threat, with a hook for the same reason. Core/Core.lua resolves
-- UnitDetailedThreatSituation once at load and calls the local from then on, so
-- the meters' section installs a reader here rather than replacing the global,
-- which would do nothing at all.
_G.UnitDetailedThreatSituation = function(source, unit)
	if state.threatReader then
		return state.threatReader(source, unit)
	end
	return true, 3, 100, 0, 1200
end

_G.UnitIsDead, _G.UnitCanAttack = constant(false), constant(true)
_G.UnitName = function(unit) return unitName[unit] or "Target Dummy" end
_G.UnitHealth, _G.UnitHealthMax = constant(4200), constant(9000)
-- Heal prediction, which both clients register and both back with an event.
-- Written as a variable rather than a constant because the skin has to be
-- driven through three states to be worth testing: nothing on the way, a heal
-- that fits inside what is missing, and one that does not.
_G.UnitGetIncomingHeals = function() return state.incomingHeals end
_G.UnitReaction = constant(2)

-- Level by unit token, defaulting to 62 for everything nobody has said
-- otherwise about.
--
-- It was a flat constant until the breakdown's level bands needed a target that
-- is not the same level as the player. A stub answering 62 for everybody would
-- file every hit under one band and pass every assertion about banding while
-- proving nothing, which is the worst kind of fixture: the failure it hides is
-- that every crit and miss rate in the table is an average of unrelated fights.
--
-- On _G rather than on H, the way WarriorKitItemLink is: a section sets a
-- unit's level to drive a scene, and a global is one lookup for both sides
-- rather than a name to hand across.
_G.WarriorKitLevels = {}
_G.UnitLevel = function(unit)
	return _G.WarriorKitLevels[unit] or 62
end
-- True for exactly one unit, so the skin's player frame takes the class colour
-- through ClassTint and the other two fall to the reaction colour. Both halves
-- of Tint run, and the per class cache gets filled once and read after that.
local realPlayers = { player = true }
_G.UnitIsPlayer = function(unit) return realPlayers[unit] == true end
-- Who is swinging. Table driven because the meters open a segment on the first
-- damage anyone in the group does, and the whole point of that rule is the pull
-- somebody else made while you are still walking in.
local inCombat = {}
_G.UnitAffectingCombat = function(unit) return inCombat[unit] == true end
-- What each mob is bleeding from. Table driven and empty by default, because
-- the debuff row's whole contract is that a square lights up when an aura whose
-- name matches lands on the unit, and a stub that answered nil forever left
-- that half of ScanDebuffs unreachable.
--
-- The order of the returns is the client's, not a convenience: name is first,
-- the icon second, the stack count third, the expiry sixth and the caster
-- seventh, and the addon reads them positionally because that is the only way
-- this API can be read on 2.5.6.
--
-- The icon was nil here for as long as the only reader was the enemy bars'
-- tracked row, which draws the art it looked up from the spell ID and never
-- asks the aura for it. The row under the skinned target block draws whatever
-- is actually on the unit and has nowhere else to get the picture from, so a
-- stub answering nil would have let a row of blank squares pass.
local debuffs = {}
-- What is helping a unit that is not you. Its own table rather than a second
-- use of `own.auras`, because the two are asked by different parts for
-- different reasons: the buff nag walks your own list looking for what is
-- missing, and the row under the skinned target block walks the target's
-- looking for what is there. Empty in the shipped scene, like the debuffs
-- above it, so no section sees a buff appear under it.
local buffs = {}
_G.UnitAura = function(unit, index, filter)
	local aura
	if filter == "HELPFUL" then
		-- Your own buffs, which is the other half of the same call and the one
		-- the buff nag walks.
		local list = unit == "player" and own.auras or buffs[unit]
		aura = list and list[index]
		if not aura then
			return nil
		end
		return aura.name, aura.icon, aura.count, nil, aura.duration, aura.expires,
			aura.source or (unit == "player" and "player" or nil), nil, nil,
			aura.spell
	end
	if filter ~= "HARMFUL" then
		return nil
	end
	local list = debuffs[unit]
	aura = list and list[index]
	if not aura then
		return nil
	end
	return aura.name, aura.icon, aura.count, nil, aura.duration, aura.expires,
		aura.source, nil, nil, aura.spell
end
_G.UnitPowerType, _G.UnitPower, _G.UnitPowerMax = constant(1), constant(40), constant(100)
_G.UnitPlayerOrPetInParty, _G.UnitPlayerOrPetInRaid = constant(false), constant(false)
_G.UnitIsGroupLeader, _G.UnitIsGroupAssistant = constant(true), constant(false)
-- How many are in the group. A variable rather than a constant, because
-- People.AddParty walks party tokens up to this number and a constant zero
-- would make that button untestable. Every section that does not set it sees
-- the nothing it saw before, and 09-group.lua writes it when a section sets a
-- roster.
_G.GetNumGroupMembers, _G.IsInRaid = function() return chat.groupSize end, constant(false)
_G.GetRaidTargetIndex, _G.SetRaidTarget = constant(nil), function() end
_G.SetRaidTargetIconTexture = function() end
-- The wall clock, which the tests move rather than wait out. It starts where
-- the old constant sat, so everything written against a fixed 100 still sees
-- one, and the loot throttle can be stepped past a tenth of a second at a time.
local wall = 100
local function advance(seconds)
	wall = wall + seconds
end
_G.GetTime = function() return wall end
_G.GetQuestGreenRange, _G.InCombatLockdown = constant(8), constant(false)
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.tinsert, _G.date = table.insert, os.date
-- The realm's clock, which is not the machine's and is what Minimap/Clock.lua
-- puts in the tooltip under the reading on its face. A fixed pair rather than a
-- read of the real one, because a test that asserts on a formatted time has to
-- know what time it is.
_G.GetGameTime = function() return 21, 7 end
_G.GetBuildInfo = function() return "2.5.6", "69110", "2025-01-01", 20506 end
-- Death knight is here and is not in Unit/Color.lua's own table, on purpose:
-- it is the one class that has to arrive through this global, so it is what
-- proves the fallback shapes a colour rather than handing back the raw one.
-- Neither of these clients has the class; the path is what is being tested.
_G.RAID_CLASS_COLORS = {
	WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
	HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
	PRIEST = { r = 1.00, g = 1.00, b = 1.00 },
	DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
}
-- Every id names a spell except the block above 900000, which names none. The
-- debuff list has a path for an id this client does not know and a stub that
-- answered every number would leave that path unreachable.
--
-- The fourth return is the cast time in milliseconds, which is what
-- ns.SpellCastTime reads and what the Slam window is built on. Empty here and
-- filled by the swing section, so every other spell in this file stays the
-- instant it was.
_G.WarriorKitSpellCast = {}
-- The handful of ids whose real name is what the test is about, spelled the way
-- both clients spell them. Everything else keeps the synthetic name, because a
-- stub carrying the whole spell table would be a second copy of the client to
-- keep correct.
--
-- These two are here because the debuff row matches auras by name and these two
-- names differ by one letter. 12162 is the Deep Wounds talent, a hidden passive
-- on the warrior that no mob ever carries; 12721 is the bleed it applies, and
-- the client calls that one Deep Wound. Naming them "Spell12162" and
-- "Spell12721" would still tell them apart and would say nothing about why they
-- have to be told apart.
--
-- The other four are the two reactive abilities, each at rank 1 and at a later
-- rank. Buttons/Reaction.lua carries the two rank 1 ids and matches everything
-- else by asking this client what it calls them, so a bar holding a rank nobody
-- wrote down has to come back with the same string. A stub that named only rank
-- 1 would let a rank list pass.
local SPELL_NAMES = {
	-- Auto Attack, and two parts want it for the same reason. Feeds/Combat.lua
	-- puts this word in the name column of every swing, because a row whose name
	-- column sometimes holds a spell and sometimes holds a creature is a column
	-- you have to decode, and Breakdown/Breakdown.lua files every white swing
	-- under it. A stub answering "Spell6603" would let an assertion about either
	-- pass while saying nothing about the word a player actually reads.
	[6603] = "Attack",
	[12162] = "Deep Wounds",
	[12721] = "Deep Wound",
	[7384] = "Overpower",
	[11585] = "Overpower",
	[6572] = "Revenge",
	[25288] = "Revenge",
	-- The buff nag's five. Battle Shout and Well Fed are here because the aura
	-- walk compares this client's own string for an id against the string an
	-- aura carries, so both sides have to be the real words or the comparison
	-- proves nothing about the real words. The three racials are here because
	-- the row's caption says "press Blood Fury" and a caption reading "press
	-- Spell20572" would pass an assertion about a caption.
	[6673] = "Battle Shout",
	[19705] = "Well Fed",
	[20572] = "Blood Fury",
	[26297] = "Berserking",
	[20594] = "Stoneform",
}
_G.GetSpellInfo = function(id)
	if type(id) == "number" and id >= 900000 then
		return nil
	end
	return SPELL_NAMES[id] or ("Spell" .. id), nil,
		"Interface\\Icons\\A" .. id, _G.WarriorKitSpellCast[id]
end
_G.GetSpellTexture = function(id) return "Interface\\Icons\\A" .. id end
-- Table driven, and empty in the shipped scene so every spell reads as ready
-- the way a constant pair of zeroes already did. The racial half of the buff
-- nag is the only thing here that asks: pressing Blood Fury has to take the
-- square off the screen, and a stub that never put a cooldown on anything could
-- not tell a fixed nag from a working one.
_G.GetSpellCooldown = function(id)
	local entry = own.cooldowns[id]
	if not entry then
		return 0, 0, 1
	end
	return entry[1], entry[2], 1
end
_G.IsUsableSpell, _G.IsSpellInRange = constant(true), constant(1)
-- Table driven, and true unless a section says otherwise. What it is here for
-- is the cooldown row: every entry in a class file is walked with this call, a
-- talent nobody took has to leave no square behind, and a stub that answered
-- true for every id in the game could not tell that from a row that draws
-- whatever it is handed.
_G.IsSpellKnown = function(id)
	return not own.unknown[id]
end
_G.GetNumSpellTabs = constant(0)
-- Three items in the backpack and empty hands. Enough for the gear scan to
-- have something to offer, and chosen so all three rules it enforces are
-- reachable: a main hander, a shield, and a two hander that must keep the
-- off hand line out of a loadout's macro.
-- Every item carries its own id and the class the client files it under, both
-- of which the addon reads. The id matters more than it looks: the clutter
-- window asks the cursor which item it picked up and compares ids, so a stub
-- that gave every item the same one would make that check pass by accident.
-- Class 12 is a quest item and is the only class the clutter scan considers.
local ITEMS = {
	["Bloodspiller"]    = { id = 1001, classId = 2, equip = "INVTYPE_WEAPONMAINHAND", icon = "Interface\\Icons\\Sword", quality = 3, price = 4200 },
	["Aegis"]           = { id = 1002, classId = 4, equip = "INVTYPE_SHIELD", icon = "Interface\\Icons\\Shield", quality = 3, price = 3800 },
	["Arcanite Reaper"] = { id = 1003, classId = 2, equip = "INVTYPE_2HWEAPON", icon = "Interface\\Icons\\Axe", quality = 4, price = 9100 },
	-- What the second bag holds, which is what a vendor is for. Two greys a
	-- vendor pays for, one grey it will not, and a green. None of the four
	-- carries an equip location, so the gear scan still sees the three weapons
	-- in the first bag and nothing else.
	["Chipped Boar Tusk"] = { id = 2001, classId = 7, quality = 0, price = 47 },
	["Tattered Cloth"]    = { id = 2002, classId = 7, quality = 0, price = 12 },
	["Broken Twig"]       = { id = 2003, classId = 7, quality = 0, price = 0 },
	["Emerald Pigment"]   = { id = 2004, classId = 7, quality = 2, price = 1900 },
	-- A white item that is not a quest item, and the only one. It is in no bag:
	-- it exists so the loot feed's quest chip can be tested at all, because that
	-- chip is an override on the white quality and a quest item is white. With
	-- nothing white beside it, "the whites are off and the quest item is still
	-- drawn" is a claim about a column with one row in it.
	["Linen Cloth"]       = { id = 2005, classId = 7, quality = 1, price = 8 },
	-- The third bag, one item per branch the clutter verdict can take. Which of
	-- them is clutter and which is not is decided by the quest fixtures below,
	-- not here.
	["Hogger's Claw"]     = { id = 3001, classId = 12, quality = 1, price = 0 },
	["Diplomat's Ring"]   = { id = 3002, classId = 12, quality = 1, price = 0 },
	["Sealed Letter"]     = { id = 3003, classId = 12, quality = 1, price = 0 },
	["Zul'Mamwe Fetish"]  = { id = 3004, classId = 12, quality = 1, price = 0 },
	["Rogue's Token"]     = { id = 3005, classId = 12, quality = 1, price = 0 },
	["Old Cipher"]        = { id = 3006, classId = 12, quality = 1, price = 0 },
	["Unknown Trinket"]   = { id = 3007, classId = 12, quality = 1, price = 0 },
	-- Two trinkets, in no bag, worn by 42-cooldown-row.lua. `use` is what
	-- GetItemSpell answers and it is the whole difference between them: one is
	-- a thing you press and takes a square on the cooldown row, and one is a
	-- thing you wear and must not.
	["Bloodlust Brooch"]  = { id = 4001, classId = 4, quality = 4, price = 0,
		equip = "INVTYPE_TRINKET", icon = "Interface\\Icons\\Brooch",
		use = "Increased Strength" },
	["Mark of Tyranny"]   = { id = 4002, classId = 4, quality = 3, price = 0,
		equip = "INVTYPE_TRINKET", icon = "Interface\\Icons\\Mark" },
}

local BAG = { "Bloodspiller", "Aegis", "Arcanite Reaper" }
local JUNK = { "Chipped Boar Tusk", "Tattered Cloth", "Broken Twig", "Emerald Pigment" }
local QUESTBAG = {
	"Hogger's Claw", "Diplomat's Ring", "Sealed Letter", "Zul'Mamwe Fetish",
	"Rogue's Token", "Old Cipher", "Unknown Trinket",
}

-- Bag 0 is the gear the loadouts pick from, bag 1 is the trash, bag 2 is the
-- quest items. Kept apart so a sale never moves what the paperdoll tests are
-- counting and a destroy never moves what the vendor tests are counting.
local CARRIED = { [0] = BAG, [1] = JUNK, [2] = QUESTBAG }

local function reset(bag, ...)
	local held = { ... }
	for index = 1, #held do
		bag[index] = held[index]
	end
end

local function refill()
	reset(JUNK, "Chipped Boar Tusk", "Tattered Cloth", "Broken Twig", "Emerald Pigment")
end

local function refillQuests()
	reset(QUESTBAG, "Hogger's Claw", "Diplomat's Ring", "Sealed Letter",
		"Zul'Mamwe Fetish", "Rogue's Token", "Old Cipher", "Unknown Trinket")
end

-- A sold slot is left as false rather than removed, because the client does
-- not renumber a bag when something leaves it and neither may this.
local function carrying(bag, slot)
	local held = CARRIED[bag] and CARRIED[bag][slot]
	return held or nil
end

local function itemLink(name)
	return ("|cffff8000|Hitem:1::::::::60:::::|h[%s]|h|r"):format(name)
end
_G.WarriorKitItemLink = itemLink

-- The client's own loot sentences.
--
-- Feeds/Loot.lua never types one of these: it takes the format strings the
-- client used and turns them into patterns, so that a German client is read by
-- German rules. That is the thing being modelled here, which is why these are
-- the real enUS strings rather than something convenient. The counted and
-- uncounted forms of each are both present because the whole correctness of
-- that file's table is the order it tries them in: "You receive loot: %s."
-- matches the counted sentence too, and a stub carrying only one form could
-- not tell a correct order from a broken one.
--
-- LOOT_ITEM_CREATED and LOOT_ITEM_CREATED_MULTIPLE are deliberately absent. A
-- client that carries some of these and not others is a real state, the addon
-- has to degrade to capturing less rather than raising, and LootFeed.Rules is
-- the count that has to notice it and say so.
_G.LOOT_ITEM_SELF = "You receive loot: %s."
_G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
_G.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
_G.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
_G.LOOT_ITEM_CREATED_SELF = "You create: %s."
_G.LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
_G.LOOT_ITEM = "%s receives loot: %s."
_G.LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
_G.LOOT_ITEM_PUSHED = "%s receives item: %s."
_G.LOOT_ITEM_PUSHED_MULTIPLE = "%s receives item: %sx%d."
_G.YOU_LOOT_MONEY = "You loot %s"
_G.LOOT_MONEY_SPLIT = "You receive %s as your split."

-- The wall clock, which a loot row's tooltip turns GetTime into so it can say
-- what time something dropped. Beside `date` above it in every sense but the
-- line it is written on.
_G.time = os.time

H.own, H.realPlayers, H.inCombat = own, realPlayers, inCombat
H.debuffs, H.buffs, H.advance, H.ITEMS = debuffs, buffs, advance, ITEMS
H.JUNK, H.QUESTBAG, H.CARRIED = JUNK, QUESTBAG, CARRIED
H.refill, H.refillQuests, H.carrying = refill, refillQuests, carrying
H.itemLink = itemLink
