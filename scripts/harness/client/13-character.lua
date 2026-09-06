-- The character sheet, and the thirty calls behind it
--
-- Everything the addon's own character window reads: what is in the eighteen
-- slots that are not a hand, the stats and ratings the sheet adds up, the skill
-- lines, the faction lines, and the two calls that put a piece on or take it
-- off.
--
-- Modelled rather than stubbed flat, and one number in it decides most of the
-- section. Weapon skill starts ten points short of the cap for this
-- character's level, because a fixture at the cap would leave the whole
-- shortfall branch of the miss maths unreachable and would let a formula that
-- ignored weapon skill pass either way. The published miss figures are the
-- check: at the cap a character misses 5.5%, 6% and 9% at one, two and three
-- levels up, and the section asserts all three by closing the ten points and
-- opening them again.
--
-- The ratings are the second decision. This is the 2.5.6 client, so combat
-- ratings exist and both indices answer. Section 53 takes them away again to
-- stand the addon on the older client for a moment, which is the branch where
-- the page has to say it cannot subtract rather than subtracting zero.

local H = ...
local ITEMS, itemLink, worn = H.ITEMS, H.itemLink, H.worn

--------------------------------------------------------------------------
-- The figure on the page
--
-- SetUnit is the one call that loads a model, and it is counted rather than
-- left to the widget stub's PascalCase no-op. What it costs is the whole reason
-- the sheet does not load one until somebody opens it, and a load nobody asked
-- for leaves nothing else behind to assert on.
--
-- It lives here rather than beside the other Region methods because the sheet
-- is the only thing in the addon that draws a player model, and 02-text.lua is
-- at its own ceiling.
--
-- Counted twice: on the region, for the sheet's own section, and once for the
-- run, which is what says login loaded none.
--------------------------------------------------------------------------

H.models = { loaded = 0 }

function H.Region:SetUnit(unit)
	self.modelUnit = unit
	self.dressed = (self.dressed or 0) + 1
	H.models.loaded = H.models.loaded + 1
end

-- The three other calls that pose that model, kept for the same reason SetUnit
-- is counted and beside it for the same reason.
--
-- The widget stub answers any PascalCase name with a no-op returning nil, so the
-- addon's probe on each of these passes under the harness whatever the client
-- would have said, and a figure that was never walked nearer and never handed
-- his weapons measures identically to one that was. What the gear page asserts
-- is the number that actually reached the model, so this is where the number
-- has to stop.
--
-- The fourth is SetRotation and it is already in 02-text.lua, because the client
-- has one call for a model's facing and a texture's angle and the map found it
-- first. Read back with GetRotation, the same way the arrow's is.
function H.Region:SetCamDistanceScale(scale) self.camScale = scale end

function H.Region:SetPosition(x, y, z) self.posX, self.posY, self.posZ = x, y, z end
function H.Region:GetPosition() return self.posX, self.posY, self.posZ end

function H.Region:SetSheathed(on) self.sheathed = on and true or false end
function H.Region:GetSheathed() return self.sheathed == true end

-- The cap a weapon skill has at this character's level, which every number
-- below is written against rather than against a level written down here. The
-- player is level 62 in this client and a fixture holding 310 would go quietly
-- wrong the first time a section levels somebody up.
local function cap()
	return _G.UnitLevel("player") * 5
end

--------------------------------------------------------------------------
-- What you are wearing
--------------------------------------------------------------------------

-- Four pieces, chosen so the summary has something to say. Every item in this
-- stub prices at item level 60, so an average over four is 60 and a fifth piece
-- would say nothing new; what the four buy is a filled slot in each of the
-- three columns the page draws, plus one in a slot that wears out.
--
-- The helmet is the one with holes in it, and it has a gem in its second socket
-- and none in its first. That is deliberate: GetItemGem answers nothing at one
-- and something at two, so a reader that stopped at the first nil would report a
-- bare piece, and the fixture that would have caught that is this one.
ITEMS["Lionheart Helm"] = { id = 4001, classId = 4, equip = "INVTYPE_HEAD",
	icon = "Interface\\Icons\\Helm", quality = 4, price = 12000,
	gems = { nil, "Bold Living Ruby" }, open = 1 }
-- Subclass 0 is red, which is the colour of the hole it is in. It carried no
-- subclass at all until the socketing window needed one: the gear page reads
-- the gem's picture and its link and nothing else, and a gem with no colour is
-- a gem the client would never say matched its hole.
ITEMS["Bold Living Ruby"] = { id = 4005, classId = 3, subClassId = 0,
	icon = "Interface\\Icons\\Gem", quality = 3, price = 900 }
ITEMS["Onyxia Tooth Pendant"] = { id = 4002, classId = 4, equip = "INVTYPE_NECK",
	icon = "Interface\\Icons\\Neck", quality = 3, price = 8000 }
ITEMS["Breastplate of Might"] = { id = 4003, classId = 4, equip = "INVTYPE_CHEST",
	icon = "Interface\\Icons\\Chest", quality = 4, price = 14000 }
ITEMS["Band of the Eternal"] = { id = 4004, classId = 4, equip = "INVTYPE_FINGER",
	icon = "Interface\\Icons\\Ring", quality = 4, price = 15000 }

-- What the client writes on the line of an item's tooltip that names its
-- enchant.
--
-- The real enUS string, for the reason the loot sentences in 03-player are the
-- real ones: Character/Worn.lua turns this into a pattern rather than typing
-- one, so the thing under test is that the pattern it builds reads the line the
-- client wrote. A fixture that said something convenient here would agree with
-- a reader that had typed the English in.
_G.ENCHANTED_TOOLTIP_LINE = "Enchanted: %s"

-- Straight into the table 04-hands reads for every slot that is not a hand, so
-- there is one GetInventoryItemLink in this client rather than two wrapping
-- each other.
worn[1] = itemLink("Lionheart Helm")
worn[2] = itemLink("Onyxia Tooth Pendant")
worn[5] = itemLink("Breastplate of Might")
worn[11] = itemLink("Band of the Eternal")

-- The two calls the gear page clicks with, counted rather than performed.
-- Neither moves anything: what the page is answerable for is whether it refused
-- in a fight and whether it called at all, and a stub that shuffled items
-- between bag and slot would be modelling the server.
local moved = { picked = {}, used = {}, macros = {}, targeting = false }

-- The state the page has to answer differently, and the one that had no stub:
-- the client is holding a spell that is waiting to be told which item it is
-- for, which is what a sharpening stone, an oil, a scroll or a poison looks
-- like from Lua. Off unless a section turns it on.
_G.SpellCanTargetItem = function()
	return moved.targeting
end

_G.PickupInventoryItem = function(slot)
	moved.picked[#moved.picked + 1] = slot
end
_G.UseInventoryItem = function(slot)
	moved.used[#moved.used + 1] = slot
end

-- What a secure button sent, counted the same way. The line is the assertion:
-- an attribute that says "macro" and a macro body that says nothing useful look
-- identical from outside, and the client runs the body.
_G.RunMacroText = function(text)
	moved.macros[#moved.macros + 1] = text
end

--------------------------------------------------------------------------
-- The numbers
--------------------------------------------------------------------------

-- One table the section moves rather than a stub per call. Every field here is
-- read by exactly one row of the page, so a section that wants to drive a row
-- writes the field and refreshes.
local sheet = {
	-- How far under the cap the weapon skill is. A number of points rather than
	-- a skill, so it survives a section levelling the character.
	short = 10,
	strength = 320, agility = 140, stamina = 480, intellect = 40, spirit = 60,
	armor = 8400,
	attackPower = 1450,
	crit = 24.31,
	expertise = 14,
	defense = 350,
	dodge = 15.42, parry = 18.03, block = 24.70, blockValue = 210,
	hitRating = 76,
	hitMelee = 4.82, hitSpell = 3.11, resilience = 0,
	spellPower = 0, spellHealing = 0, spellCrit = 2.5,
	manaBase = 0, manaCasting = 0,
	resistances = { [2] = 45, [3] = 10, [4] = 0, [5] = 25, [6] = 0 },
}

-- The two rating indices this client carries, at the numbers FrameXML gives
-- them. They are globals rather than arguments because that is how the addon
-- has to find them: a rating index is a client constant, and an addon that
-- wrote 6 down would be writing down a number the older client does not have.
_G.CR_HIT_MELEE = 6
_G.CR_HIT_SPELL = 8
_G.CR_CRIT_TAKEN_MELEE = 15

_G.GetCombatRating = function(index)
	if index == _G.CR_HIT_MELEE then
		return sheet.hitRating
	end
	if index == _G.CR_CRIT_TAKEN_MELEE then
		return sheet.resilience
	end
	return 0
end

_G.GetCombatRatingBonus = function(index)
	if index == _G.CR_HIT_MELEE then
		return sheet.hitMelee
	end
	if index == _G.CR_HIT_SPELL then
		return sheet.hitSpell
	end
	return 0
end

-- Base, total, positive and negative, in that order, which is the order the
-- page reads them in and the order the client answers them in. The positive is
-- not zero on strength, so the sentence under a stat is reachable.
local STATS = { "strength", "agility", "stamina", "intellect", "spirit" }

_G.UnitStat = function(unit, index)
	if unit ~= "player" or not STATS[index] then
		return nil
	end
	local total = sheet[STATS[index]]
	local buff = index == 1 and 60 or 0
	return total - buff, total, buff, 0
end

_G.UnitArmor = function(unit)
	if unit ~= "player" then
		return nil
	end
	return sheet.armor - 400, sheet.armor, sheet.armor, 400, 0
end

_G.UnitAttackPower = function(unit)
	if unit ~= "player" then
		return nil
	end
	return sheet.attackPower - 200, 200, 0
end

-- Both hands, in the four returns the client gives: the base skill and the
-- modifier for each. Off hand answers the same, because a character dual
-- wielding has one weapon skill per hand and the page reads the main.
_G.UnitAttackBothHands = function(unit)
	if unit ~= "player" then
		return nil
	end
	local skill = cap() - sheet.short
	return skill, 0, skill, 0
end

_G.UnitDamage = function(unit)
	if unit ~= "player" then
		return nil
	end
	return 180, 260, 90, 130, 0, 1
end

_G.UnitRangedDamage = function(unit)
	if unit ~= "player" then
		return nil
	end
	return 2.9, 90, 140
end
_G.UnitRangedAttackPower = function(unit)
	return unit == "player" and 210 or nil, 0, 0
end

_G.GetCritChance = function() return sheet.crit end
_G.GetRangedCritChance = function() return 12.5 end
_G.GetExpertise = function() return sheet.expertise end

_G.UnitDefense = function(unit)
	if unit ~= "player" then
		return nil
	end
	return sheet.defense, 0
end
_G.GetDodgeChance = function() return sheet.dodge end
_G.GetParryChance = function() return sheet.parry end
_G.GetBlockChance = function() return sheet.block end
_G.GetShieldBlock = function() return sheet.blockValue end

_G.UnitResistance = function(unit, index)
	if unit ~= "player" then
		return nil
	end
	return sheet.resistances[index] or 0
end

-- The spell half, all of it zero on a warrior, which is the case the page has
-- to draw as nothing at all rather than as six rows of nought.
_G.GetSpellBonusDamage = function() return sheet.spellPower end
_G.GetSpellBonusHealing = function() return sheet.spellHealing end
_G.GetSpellCritChance = function() return sheet.spellCrit end
_G.GetManaRegen = function() return sheet.manaBase, sheet.manaCasting end

--------------------------------------------------------------------------
-- Skills
--------------------------------------------------------------------------

-- Two headers, and under them one weapon skill at the cap, one ten points
-- short, one profession and one secondary skill. The four are the four
-- branches the page's Kind test takes, so a test that told them apart by
-- matching an English header name would pass here and fail in German.
--
-- The client answers these in one flat list with the headers in it, which is
-- the shape the page has to fold, so that is the shape here.
local LINES = {
	{ name = "Weapon Skills", header = true },
	{ name = "Axes", weapon = true, short = 0 },
	{ name = "Swords", weapon = true, short = 10 },
	{ name = "Professions", header = true },
	{ name = "Blacksmithing", rank = 300, max = 375, abandonable = true },
	{ name = "First Aid", rank = 300, max = 300 },
}

local expandedSkills = 0

_G.GetNumSkillLines = function() return #LINES end
_G.ExpandSkillHeader = function()
	expandedSkills = expandedSkills + 1
end

_G.GetSkillLineInfo = function(index)
	local line = LINES[index]
	if not line then
		return nil
	end
	local max = line.weapon and cap() or (line.max or 0)
	local rank = line.weapon and (max - line.short) or (line.rank or 0)
	-- name, isHeader, isExpanded, rank, temporary, modifier, max, abandonable
	return line.name, line.header or false, true, rank, 0, 0,
		max, line.abandonable or false
end

--------------------------------------------------------------------------
-- Reputation
--------------------------------------------------------------------------

-- One collapsed header with two factions under it, because collapsed is the
-- state the walk has to get past and a fixture that started expanded would
-- never reach the call that expands.
local FACTIONS = {
	{ name = "Outland", header = true, collapsed = true },
	{ name = "Thrallmar", standing = 6, low = 6000, high = 12000, value = 8400 },
	{ name = "The Consortium", standing = 4, low = 0, high = 3000, value = 900 },
}

local expandedFactions = 0

_G.GetNumFactions = function() return #FACTIONS end
_G.ExpandFactionHeader = function(index)
	local row = FACTIONS[index]
	if row and row.collapsed then
		row.collapsed = false
		expandedFactions = expandedFactions + 1
	end
end

_G.GetFactionInfo = function(index)
	local row = FACTIONS[index]
	if not row then
		return nil
	end
	-- name, description, standing, barMin, barMax, barValue, atWar,
	-- canToggleAtWar, isHeader, isCollapsed, hasRep
	return row.name, "", row.standing or 0, row.low or 0, row.high or 0,
		row.value or 0, false, false, row.header or false,
		row.collapsed or false, false
end

-- Five more of the eight standing labels. Three are still missing and exalted
-- is deliberately one of them: 03-player leaves gaps so the addon's fallback
-- for a client that names none of them stays reachable, and section 50 asserts
-- exactly that on exalted. Adding it here would pass that section a label and
-- delete the test.
for id, label in pairs({ [1] = "Hated", [2] = "Hostile", [3] = "Unfriendly",
	[4] = "Neutral", [5] = "Friendly" }) do
	_G["FACTION_STANDING_LABEL" .. id] = label
end

--------------------------------------------------------------------------

H.sheet, H.moved = sheet, moved
H.skillLines, H.factions = LINES, FACTIONS
H.expandedSkills = function() return expandedSkills end
H.expandedFactions = function() return expandedFactions end
