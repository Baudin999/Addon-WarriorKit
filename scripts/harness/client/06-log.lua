-- The combat log, the talent trees and the inspect handshake
--
-- Everything the meters are built on. All four are read through a local the
-- module took at load, so all four are declared here, before the addon runs,
-- and a test moves the data under them rather than replacing the function.
--
-- The log is modelled as the twenty-one values the client hands over, because
-- the addon reads seven of them out of fixed positions and the positions are
-- the whole contract: a stub that answered a named table would let a parser
-- that reads the wrong slot pass.
--
-- Twenty-one rather than sixteen because of the off hand flag. It is the last
-- value of SWING_DAMAGE and the second of SWING_MISSED, which is the same fact
-- in two places, and a stub that stopped at sixteen would let a swing timer
-- that never saw an off hand swing pass.

local H = ...
local state = H.state
local WARRIOR, constant = H.WARRIOR, H.constant

local logArgs = {}
_G.CombatLogGetCurrentEventInfo = function()
	return unpack(logArgs, 1, 21)
end

-- Three trees per character, points and an icon each. Two shapes, because
-- GetTalentTabInfo has two signatures across these clients: one leads with a
-- numeric tab id and one leads with the tree's name, and the addon tells them
-- apart on the type of the first value. Both are reachable from a test.
local talentTrees = {
	player = {
		{ name = "Arms", icon = "Interface\\Icons\\Ability_Warrior_SavageBlow", points = 31 },
		{ name = "Fury", icon = "Interface\\Icons\\Ability_Warrior_InnerRage", points = 20 },
		{ name = "Protection", icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance", points = 0 },
	},
	inspect = {
		{ name = "Beast Mastery", icon = "Interface\\Icons\\Ability_Hunter_BeastTaming", points = 11 },
		{ name = "Marksmanship", icon = "Interface\\Icons\\Ability_Marksmanship", points = 40 },
		{ name = "Survival", icon = "Interface\\Icons\\Ability_Hunter_SwiftStrike", points = 0 },
	},
}

_G.GetNumTalentTabs = function() return 3 end
_G.GetTalentTabInfo = function(index, inspect)
	local trees = inspect and talentTrees.inspect or talentTrees.player
	local tree = trees[index]
	if not tree then
		return nil
	end
	if state.talentShape == "old" then
		return tree.name, tree.icon, tree.points
	end
	return index, tree.name, "", tree.icon, tree.points, tree.name
end

_G.NotifyInspect = function(unit) state.inspecting = unit end
_G.ClearInspectPlayer = function() state.inspecting = nil end
_G.CheckInteractDistance = constant(true)
_G.UnitIsConnected = constant(true)

-- The sheet every class icon is cut out of. Only the three classes the meters'
-- section puts in a group, because a coordinate this file invented for a class
-- nothing draws would be a fixture proving nothing.
_G.CLASS_ICON_TCOORDS = {
	WARRIOR = { 0, 0.25, 0, 0.25 },
	HUNTER = { 0, 0.25, 0.25, 0.5 },
	PRIEST = { 0.5, 0.75, 0, 0.25 },
}

H.logArgs, H.talentTrees = logArgs, talentTrees
