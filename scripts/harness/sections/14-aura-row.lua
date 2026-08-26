-- The aura row
--
-- The client hangs the target's buffs and debuffs off the frame's bottom left
-- corner, lifted by the height of the art that used to hang under the bars.
-- Fitting the frame to the block took that art away and the same lift then put
-- the row inside the gauge, which is where a screenshot found it.
--
-- The row is not moved by the addon and this asserts that it is not. Every
-- icon in it is a child of a secure unit button, so it can only be anchored
-- out of combat, and the client re-anchors the head of each row on every aura
-- the target gains or loses: a row placed by the addon would be back inside
-- the gauge on the first refresh of the first fight. What the addon moves is
-- the edge the client measures from, which it may do whenever it is allowed
-- to and which then holds for the rest of the session.
--
-- So the three numbers here are the whole contract. The heads keep the anchor
-- the client wrote, the frame is the block plus that lift, and the mouse
-- region is pulled back off the strip so the block is still all you can click.

local H = ...
local fire, check, playerFrame = H.fire, H.check, H.playerFrame
local targetFrame, AURA_LIFT, auraHeads = H.targetFrame, H.AURA_LIFT, H.auraHeads
local anchorAuras = H.anchorAuras

local targetBox = _G.WarriorKitSkinTarget

local function screenHeight(frame)
	return frame:GetHeight() * frame:GetEffectiveScale()
end

-- Before any aura exists there is nothing to measure and the frame is the
-- block exactly, which is what the fit assertions above have already checked.
check(math.abs(screenHeight(targetFrame) - screenHeight(targetBox)) < 1e-6,
	"the target frame carries a tail before the client has placed a single aura")

anchorAuras()
fire("UNIT_AURA", "target")

local lift = AURA_LIFT * targetFrame:GetEffectiveScale()
check(math.abs(screenHeight(targetFrame) - (screenHeight(targetBox) + lift)) < 1e-6,
	("the target frame is %.2f of screen and the block plus the client's %d unit"
		.. " lift is %.2f, so the aura row does not land under the block")
		:format(screenHeight(targetFrame), AURA_LIFT, screenHeight(targetBox) + lift))

for _, head in ipairs(auraHeads) do
	local point = head.points and head.points[1]
	check(point ~= nil and point[2] == targetFrame and point[5] == AURA_LIFT,
		head.name .. " was re-anchored by the addon, which is a write the client"
		.. " undoes on the next aura and combat refuses outright")
end

local _, _, _, bottom = targetFrame:GetHitRectInsets()
check(math.abs((bottom or 0) - AURA_LIFT) < 1e-6,
	("the target frame takes clicks %s units below the block, where the aura row"
		.. " hangs and there is nothing to click"):format(tostring(bottom)))

local _, _, _, playerBottom = playerFrame:GetHitRectInsets()
check((playerBottom or 0) == 0,
	"the player frame had its mouse region inset, and it has no aura row to make"
	.. " room for")

print(("auras  the client lifts the row %d units, the target frame is the block"
	.. " plus that and takes no clicks in it"):format(AURA_LIFT))
