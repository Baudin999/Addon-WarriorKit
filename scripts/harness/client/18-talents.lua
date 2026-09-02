-- The talent trees, one talent at a time, and the calls that spend a point
--
-- 06-log.lua answers the three trees as a whole, name and icon and points,
-- which is all the meters and the party frames ever asked. The talent window
-- asks the rest: where every talent sits, what rank it is at, what it needs
-- first, how many points are waiting, and the two calls that change any of
-- that. This file is the client's answer to all of it.
--
-- **Modelled on the anniversary client's shape.** C_SpecializationInfo takes a
-- query table and hands back a record, GetTalentPrereqs answers four values
-- per requirement, and the group is an argument on every call. The older
-- shape, a GetTalentInfo that answers a run of values, is installed by
-- section 67 over this one for a moment and taken off again, the way section
-- 58 stands the tab call on its older signature.
--
-- **Three trees drawn from the warrior's, and not the warrior's.** The names
-- are real so a picture of the window reads as one, but the layout is chosen
-- for what it exercises: a requirement straight down a column across an empty
-- tier, one along a row, one diagonal with a clear route and one whose short
-- route is blocked, a ninth tier so the window is sized for the taller
-- client, and a tree with no points in it so a locked tier is reachable. A
-- fixture that copied the real trees would test whichever of those the real
-- trees happen to have.
--
-- **04-hands.lua's GetTalentInfo stays.** The Slam window's estimate reads a
-- talent through it and the fixture there is shaped for that one question.
-- GetNumTalents is taken over, because the window walks every index and three
-- is not a tree, and the older reader in Swing/Slam.lua walks the same count
-- and finds its talent at the same index it always did.
--
-- What this cannot prove is that the game agrees. Every call answers what this
-- file says, and a wrong field is a test that passes and a window that draws
-- the wrong rim.

local H = ...
local region, talentTrees = H.region, H.talentTrees

local function talent(name, tier, column, max, rank, needTier, needColumn)
	return { name = name, icon = "Interface\\Icons\\" .. name:gsub("%s", ""),
		tier = tier, column = column, max = max, rank = rank,
		needTier = needTier, needColumn = needColumn }
end

local TREES = {
	{
		talent("Improved Heroic Strike", 1, 1, 3, 3),
		talent("Deflection", 1, 2, 5, 5),
		talent("Improved Rend", 1, 3, 3, 0),
		talent("Improved Charge", 2, 1, 2, 2),
		talent("Tactical Mastery", 2, 2, 5, 5),
		talent("Improved Thunder Clap", 2, 3, 3, 0),
		talent("Improved Overpower", 3, 1, 2, 2),
		talent("Anger Management", 3, 2, 1, 1),
		talent("Deep Wounds", 3, 3, 3, 3),
		talent("Two-Handed Weapon Specialization", 4, 2, 5, 5),
		-- Straight down, one tier.
		talent("Impale", 4, 3, 2, 2, 3, 3),
		talent("Poleaxe Specialization", 5, 1, 5, 0),
		talent("Sweeping Strikes", 5, 2, 1, 1),
		talent("Mace Specialization", 5, 3, 5, 0),
		talent("Sword Specialization", 5, 4, 5, 0),
		talent("Improved Hamstring", 6, 1, 3, 0),
		-- Straight down, across an empty tier.
		talent("Mortal Strike", 7, 2, 1, 0, 5, 2),
		-- Diagonal, and the short route is blocked by Mace Specialization, so
		-- the line goes down first and then over.
		talent("Improved Execute", 6, 3, 2, 0, 5, 2),
	},
	{
		talent("Booming Voice", 1, 1, 5, 5),
		talent("Cruelty", 1, 2, 5, 5),
		talent("Improved Demoralizing Shout", 2, 1, 5, 5),
		talent("Unbridled Wrath", 2, 2, 5, 5),
		-- Along the row, from a requirement that is full.
		talent("Improved Berserker Rage", 2, 3, 2, 0, 2, 2),
		talent("Improved Cleave", 3, 1, 3, 0),
		-- Along the row, from a requirement that is empty, on a tier that is
		-- open: the one square whose hover names what it needs rather than
		-- how many points open its tier.
		talent("Piercing Howl", 3, 2, 1, 0, 3, 1),
		talent("Blood Craze", 3, 3, 3, 0),
		talent("Improved Battle Shout", 3, 4, 5, 0),
		talent("Enrage", 4, 2, 5, 0),
		talent("Death Wish", 5, 2, 1, 0),
		-- Diagonal with a clear short route: over along tier four, then down.
		talent("Flurry", 6, 3, 5, 0, 4, 2),
		talent("Bloodthirst", 7, 2, 1, 0, 5, 2),
	},
	{
		talent("Shield Specialization", 1, 1, 5, 0),
		talent("Anticipation", 1, 2, 5, 0),
		talent("Improved Bloodrage", 2, 1, 2, 0),
		talent("Toughness", 2, 3, 5, 0),
		talent("Last Stand", 3, 1, 1, 0),
		talent("Improved Shield Block", 3, 2, 1, 0),
		talent("Defiance", 4, 2, 3, 0),
		talent("Improved Sunder Armor", 5, 1, 3, 0),
		talent("Shield Slam", 7, 2, 1, 0, 4, 2),
		-- The ninth tier, which the older client does not have.
		talent("Devastate", 9, 2, 1, 0, 7, 2),
	},
}

-- Ranks per group, keyed tab:index. The first group starts as the trees
-- above; the second is empty, which is what a freshly bought second spec is.
local ranks = { {}, {} }
for tab, list in ipairs(TREES) do
	for index, entry in ipairs(list) do
		ranks[1][tab .. ":" .. index] = entry.rank
		ranks[2][tab .. ":" .. index] = 0
	end
end

-- Client state a section is allowed to write: how many groups this
-- character has, which is live, how many points are waiting, and what the
-- two calls that change something were asked to do.
local model = {
	groups = 1,
	active = 1,
	unspent = 3,
	learned = {},
	activated = {},
	ranks = ranks,
	trees = TREES,
}
H.talentModel = model

local function Rank(group, tab, index)
	return model.ranks[group or model.active][tab .. ":" .. index] or 0
end

-- Points in one tree, for the group asked. The live group answers what
-- 06-log.lua's fixture says, because that is the number the runner drives a
-- spec run by; the other group is what its own ranks add up to.
local function Points(group, tab)
	group = group or model.active
	if group == model.active then
		local tree = talentTrees.player[tab]
		return tree and tree.points or 0
	end
	local total = 0
	for index = 1, #(TREES[tab] or {}) do
		total = total + Rank(group, tab, index)
	end
	return total
end

local function Met(group, tab, entry)
	if not entry.needTier then
		return true
	end
	for index, other in ipairs(TREES[tab]) do
		if other.tier == entry.needTier and other.column == entry.needColumn then
			return Rank(group, tab, index) >= other.max
		end
	end
	return false
end

_G.C_SpecializationInfo = {
	GetSpecializationInfo = function(tab, _, _, _, _, group)
		local tree = talentTrees.player[tab]
		if not tree then
			return nil
		end
		return tab, tree.name, "", tree.icon, "DAMAGER", 1, Points(group, tab), "Background", 0, true
	end,
	GetTalentInfo = function(query)
		local tab, index = query.specializationIndex, query.talentIndex
		local entry = TREES[tab] and TREES[tab][index]
		if not entry then
			return nil
		end
		local group = query.groupIndex or model.active
		return {
			talentID = tab * 100 + index,
			name = entry.name, icon = entry.icon,
			tier = entry.tier, column = entry.column,
			rank = Rank(group, tab, index), maxRank = entry.max,
			meetsPrereq = Met(group, tab, entry), previewRank = Rank(group, tab, index),
			meetsPreviewPrereq = Met(group, tab, entry),
			isExceptional = false, hasGoldBorder = false,
		}
	end,
	GetActiveSpecGroup = function()
		return model.active
	end,
	SetActiveSpecGroup = function(group)
		model.activated[#model.activated + 1] = group
		model.active = group
		H.fire("ACTIVE_TALENT_GROUP_CHANGED", group)
	end,
}

_G.GetNumTalentGroups = function()
	return model.groups
end

_G.GetNumTalents = function(tab)
	return #(TREES[tab] or {})
end

-- Four values per requirement, the newer client's shape.
_G.GetTalentPrereqs = function(tab, index, _, _, group)
	local entry = TREES[tab] and TREES[tab][index]
	if not entry or not entry.needTier then
		return nil
	end
	local met = Met(group or model.active, tab, entry)
	return entry.needTier, entry.needColumn, met, met
end

_G.GetUnspentTalentPoints = function(_, _, group)
	if group == nil or group == model.active then
		return model.unspent
	end
	return 0
end

_G.UnitCharacterPoints = function()
	return model.unspent
end

-- A point spent, the way the server spends one: refused where the client's
-- own frame would have refused, and both events on the way back.
_G.LearnTalent = function(tab, index, _, group)
	model.learned[#model.learned + 1] = { tab = tab, index = index, group = group }
	group = group or model.active
	local entry = TREES[tab] and TREES[tab][index]
	if not entry or group ~= model.active or model.unspent < 1 then
		return
	end
	local key = tab .. ":" .. index
	if model.ranks[group][key] >= entry.max or not Met(group, tab, entry) then
		return
	end
	model.ranks[group][key] = model.ranks[group][key] + 1
	model.unspent = model.unspent - 1
	talentTrees.player[tab].points = talentTrees.player[tab].points + 1
	H.fire("PLAYER_TALENT_UPDATE")
	H.fire("CHARACTER_POINTS_CHANGED")
end

-- The older client's GetTalentInfo, built from the same model, for the section
-- that stands the addon on that client for a moment. The run of values is the
-- deprecated wrapper's order: the requirement flag seventh and the preview
-- rank eighth.
function model.Legacy(tab, index, _, _, group)
	local entry = TREES[tab] and TREES[tab][index]
	if not entry then
		return nil
	end
	group = group or model.active
	local met = Met(group, tab, entry)
	return entry.name, entry.icon, entry.tier, entry.column, Rank(group, tab, index), entry.max,
		met, Rank(group, tab, index), met, false, false, tab * 100 + index
end

--------------------------------------------------------------------------
-- The client's own window
--
-- Named the way the newer client names it and standing from the start,
-- although in the game it is an addon of Blizzard's own that loads on the
-- first press. Standing early is what makes the cage testable: a frame that
-- never existed cannot be shown to be in the attic.
--
-- ToggleTalentFrame is the N key. A plain global, as on both clients, and the
-- stub's own version counts the press and shows the window, so a section can
-- tell the client's key from the addon's by which of the two moved.
--------------------------------------------------------------------------

local frame = region("frame", _G.UIParent, "PlayerTalentFrame")
frame:SetSize(384, 512)
frame:Hide()
_G.PlayerTalentFrame = frame

H.talentKey = { presses = 0 }
function _G.ToggleTalentFrame()
	H.talentKey.presses = H.talentKey.presses + 1
	frame:Show()
end
