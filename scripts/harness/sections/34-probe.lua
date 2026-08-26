-- THROWAWAY. Drives ns.FrameAuras directly, before UnitFrames/Skin.lua calls
-- it, so the rows can be measured while item 8 holds the rebase. Delete once
-- 14-aura-row.lua asserts the same things through the real skin.

local H = ...
local ns, check = H.ns, H.check
local targetFrame, debuffs, buffs = H.targetFrame, H.debuffs, H.buffs

local box = _G.WarriorKitSkinTarget
local px = ns.Pixel(box)
local width = box:GetWidth()

local entry = {
	spec = { key = "target", unit = "target", mirror = true },
	frame = targetFrame, box = box, styled = true,
}

ns.db.skinAuras = true
ns.db.skinAuraSize = 20
ns.db.skinAuraDebuffs = 12
ns.db.skinAuraBuffs = 8

ns.FrameAuras.Build(entry)
check(entry.auras ~= nil and #entry.auras == 2,
	"Build made " .. tostring(entry.auras and #entry.auras) .. " rows, wanted 2")

ns.FrameAuras.Place(entry, px, width, true)

local rowD, rowB = entry.auras[1], entry.auras[2]
print(("probe  block %.0f wide, square %.0f, perLine debuffs %d buffs %d")
	:format(width, rowD.side, rowD.perLine, rowB.perLine))

-- The row hangs off the block's bottom right corner, because the target is
-- mirrored and the portrait is on the right.
local point, relative, relativePoint = rowD.frame:GetPoint()
check(point == "TOPRIGHT" and relative == box and relativePoint == "BOTTOMRIGHT",
	("the debuff row is anchored %s to %s of the block, not TOPRIGHT to BOTTOMRIGHT")
		:format(tostring(point), tostring(relativePoint)))

local bpoint, brelative, brelativePoint = rowB.frame:GetPoint()
check(bpoint == "TOPRIGHT" and brelative == rowD.frame and brelativePoint == "BOTTOMRIGHT",
	"the buff row is not hanging off the debuff row's bottom")

-- Square one is at the far right of the row, because the row is mirrored.
local function LeftOf(square)
	local _, _, _, x = square:GetPoint()
	return x or 0
end
local first, second = rowD.squares[1], rowD.squares[2]
check(first ~= nil and second ~= nil, "the debuff row built fewer than two squares")
if first and second then
	check(LeftOf(first) > LeftOf(second),
		("square 1 is at x=%.1f and square 2 at x=%.1f, so the row is not mirrored")
			:format(LeftOf(first), LeftOf(second)))
	check(math.abs((LeftOf(first) + rowD.side) - width) < 1e-6,
		("square 1's right edge is at %.1f and the block is %.1f wide")
			:format(LeftOf(first) + rowD.side, width))
end

-- Nothing on the target yet.
ns.FrameAuras.Update(entry)
check(not rowD.squares[1]:IsShown(), "a square is shown with no debuff on the target")
check(math.abs(rowD.frame:GetHeight() - px) < 1e-6,
	("an empty debuff row is %.2f tall, wanted one pixel"):format(rowD.frame:GetHeight()))

-- Three debuffs, one of them yours and not first in the client's order.
local now = _G.GetTime()
debuffs.target = {
	{ name = "Sunder Armor", icon = "sunder", count = 4, expires = now + 20, source = "party1" },
	{ name = "Demoralizing Shout", icon = "demo", count = 0, expires = now + 25, source = "party2" },
	{ name = "Rend", icon = "rend", count = 0, expires = now + 12, source = "player" },
}
buffs.target = {
	{ name = "Battle Shout", icon = "shout", count = 0, expires = now + 100, source = "party1" },
}
ns.FrameAuras.Update(entry)

check(rowD.squares[1].shownIcon == "rend",
	("square 1 drew %s, and yours is meant to be placed first")
		:format(tostring(rowD.squares[1].shownIcon)))
check(rowD.squares[1].shownState == "mine", "your own Rend is not drawn as yours")
check(rowD.squares[2].shownState == "theirs", "someone else's debuff is not drained")
check(rowD.squares[3]:IsShown() and not rowD.squares[4]:IsShown(),
	"three debuffs did not light exactly three squares")
check(rowB.squares[1].shownIcon == "shout", "the buff row did not draw the target's buff")

check(math.abs(rowD.frame:GetHeight() - (rowD.gap + rowD.side)) < 1e-6,
	("three debuffs made the row %.2f tall, one line is %.2f")
		:format(rowD.frame:GetHeight(), rowD.gap + rowD.side))

-- The client's row, hidden as it is built.
local head = _G.TargetFrameDebuff1
check(head ~= nil and not head:IsShown(),
	"the client's first debuff icon is still shown under our own row")

-- Enough to wrap.
local many = {}
for index = 1, 12 do
	many[index] = { name = "Bleed" .. index, icon = "bleed", count = 0,
		expires = now + index, source = index == 1 and "player" or "party1" }
end
debuffs.target = many
ns.FrameAuras.Update(entry)
local lines = math.ceil(12 / rowD.perLine)
check(math.abs(rowD.frame:GetHeight()
	- (rowD.gap + lines * rowD.side + (lines - 1) * rowD.gap)) < 1e-6,
	("twelve debuffs over %d lines came out %.2f tall"):format(lines, rowD.frame:GetHeight()))

-- A tick that changes nothing writes nothing.
local writes = 0
for slot = 1, 12 do
	local square = rowD.squares[slot]
	for _, key in ipairs({ "icon", "timer", "count" }) do
		local region = square[key]
		for _, method in ipairs({ "SetTexture", "SetText", "SetDesaturated" }) do
			if type(region[method]) == "function" and not region["wk" .. method] then
				region["wk" .. method] = region[method]
				region[method] = function(self, ...)
					writes = writes + 1
					return region["wk" .. method](self, ...)
				end
			end
		end
	end
end
for _ = 1, 20 do
	ns.FrameAuras.Update(entry)
end
check(writes == 0, ("twenty unchanged ticks wrote %d times to a square"):format(writes))

debuffs.target, buffs.target = nil, nil
ns.FrameAuras.Update(entry)
check(not rowD.squares[1]:IsShown(), "the debuffs fell off and a square stayed up")

-- A smaller square and a shorter row, which is a relayout and not a tick.
ns.db.skinAuraSize = 32
ns.db.skinAuraDebuffs = 4
ns.FrameAuras.Place(entry, px, width, true)
check(rowD.side == 32 * px and rowD.wanted == 4,
	("the relayout left the square at %.0f and the row at %d"):format(rowD.side, rowD.wanted))
-- Capped by the row's own length as well as by the block's width: with four
-- squares in the tree there is no fifth for Flow to break after.
local fits = math.min(math.floor((width + rowD.gap) / (rowD.side + rowD.gap)),
	rowD.wanted)
check(rowD.perLine == fits,
	("a %.0f wide block holding %d squares of %.0f fits %d, and Flow said %d")
		:format(width, rowD.wanted, rowD.side, fits, rowD.perLine))
check(not rowD.squares[5]:IsShown(),
	"the row got shorter and the squares past the end stayed up")

-- Off, which hides our rows and leaves the client's hidden, because the frame
-- is the block and the client's row would land inside the gauge.
ns.db.skinAuras = false
ns.FrameAuras.Place(entry, px, width, true)
check(not rowD.frame:IsShown() and not rowB.frame:IsShown(),
	"skin auras off left a row on screen")
check(not _G.TargetFrameDebuff1:IsShown(),
	"skin auras off gave the client's row back, and it lands inside the gauge")

-- The skin coming off does give it back, because the frame goes back to the
-- size the client built it at.
ns.FrameAuras.Unstyle(entry)
check(_G.TargetFrameDebuff1:IsShown(),
	"the skin came off and the client's own debuff icon stayed hidden")
check(rowD.swept == 0, "Unstyle left the sweep counter where it was")

ns.db.skinAuras = true
ns.db.skinAuraSize = 20
ns.db.skinAuraDebuffs = 12
ns.FrameAuras.Style(entry)
ns.FrameAuras.Place(entry, px, width, true)
check(not _G.TargetFrameDebuff1:IsShown(),
	"the skin went back on and the client's row came with it")

-- The client builds its aura buttons on demand, so the sweep has to catch one
-- that did not exist when the skin went on. Built here the way the client
-- builds them: in order, and only once a target has carried that many.
do
	local child, Region = H.child, H.Region
	local built = {}
	for index = 2, 4 do
		built[index] = child("button", targetFrame, "TargetFrameDebuff" .. index)
	end

	local realLockdown, realProtected = _G.InCombatLockdown, Region.IsProtected
	local inCombat = true
	_G.InCombatLockdown = function() return inCombat end
	function Region:IsProtected() return built[2] == self or built[3] == self
		or built[4] == self end

	ns.FrameAuras.Update(entry)
	check(built[2]:IsShown(),
		"combat let the addon hide a protected aura button, which the client refuses")

	inCombat = false
	ns.FrameAuras.Update(entry)
	for index = 2, 4 do
		check(not built[index]:IsShown(),
			("combat dropped and TargetFrameDebuff%d was still on screen"):format(index))
	end
	check(rowD.swept == 4, ("the sweep stopped at %d of 4"):format(rowD.swept))

	_G.InCombatLockdown, Region.IsProtected = realLockdown, realProtected
end

print(("probe  %d of the client's debuff icons hidden, row wraps at %d")
	:format(rowD.swept, rowD.perLine))
