-- A resolution change that lands in combat
--
-- The grid re-scales every frame on it, and the unit frames put anchors on it
-- that hold secure unit buttons. SetScale on a protected frame in lockdown
-- raises, and a monitor swapped or a window resized mid pull is how that
-- arrives. Refused frames wait for PLAYER_REGEN_ENABLED.

local H = ...
local state = H.state
local Region, ns = H.Region, H.ns
local fire, check = H.fire, H.check

local box = _G.WarriorKitPlayerFrame
check(box ~= nil, "the player frame's anchor is not a named frame, so this cannot be tested")
if box then
	local blocked, inCombat = {}, false
	local realLockdown, realProtected = _G.InCombatLockdown, Region.IsProtected
	_G.InCombatLockdown = function() return inCombat end
	function Region:IsProtected() return blocked[self] == true end

	local before = box:GetScale()
	blocked[box], inCombat = true, true
	state.SCREEN_H = 2160
	_G.GetPhysicalScreenSize = function() return 3840, state.SCREEN_H end
	fire("DISPLAY_SIZE_CHANGED")

	local wanted = 768 / state.SCREEN_H
	check(box:GetScale() == before,
		("a protected anchor was re-scaled in combat, %.4f"):format(box:GetScale()))
	check(math.abs(ns.UI.Scale() - wanted) < 1e-9,
		"the grid did not pick up the new screen height")
	check(math.abs(_G.WarriorKitEnemyBarsAnchor:GetScale() - wanted) < 1e-9,
		"an unprotected frame was deferred along with the protected one")

	inCombat = false
	fire("PLAYER_REGEN_ENABLED")
	check(math.abs(box:GetScale() - wanted) < 1e-9,
		("the anchor never caught up after combat, %.4f"):format(box:GetScale()))
	print(("lockdown a protected anchor held %.4f in combat and took %.4f after it")
		:format(before, box:GetScale()))

	_G.InCombatLockdown, Region.IsProtected = realLockdown, realProtected
	state.SCREEN_H = 1440
	_G.GetPhysicalScreenSize = function() return 3440, state.SCREEN_H end
	fire("DISPLAY_SIZE_CHANGED")
end
