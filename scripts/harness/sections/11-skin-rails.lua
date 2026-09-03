-- The two rails, measured against the block they divide
--
-- The inside of the block is laid out by ns.UI.Flow now, and this is the check
-- the enemy bars did not have when the same engine handed their gauge a height
-- of one pixel: a node with no size and no grow measures zero, is given a
-- pixel, and draws a bar nobody can read. Every anchor in that layout was
-- individually correct and nothing caught it until somebody measured it.
--
-- So both rails are measured, and against the block rather than against the
-- settings. Health, power and the three hairlines are the block's height. Each
-- rail is the block less the portrait's square and less the pixel the outline
-- draws into. Both start where the square stops, which the mirror puts on the
-- other side of the block.

local H = ...
local ns, check = H.ns, H.check
local blocks = H.carry.blocks

for _, block in ipairs(blocks) do
	local key, box = block[1], block[2]
	local healthRail, powerRail = box and box.children[1], box and box.children[2]
	if healthRail and powerRail then
		local px = ns.UI.Pixel(box)
		-- The block's height, which is also the side of the portrait's square.
		local side = box:GetHeight()
		local function near(a, b) return math.abs(a - b) < 1e-9 end

		-- Two bars and three hairlines fill the square exactly. A fractional
		-- share would leave a seam along one of them, which reads as a
		-- rendering fault rather than as a layout that does not add up.
		local stack = healthRail:GetHeight() + powerRail:GetHeight() + 3 * px
		check(near(stack, side),
			("%s: a %.0f px health rail and a %.0f px power rail with three hairlines"
				.. " come to %.0f, and the block is %.0f")
				:format(key, healthRail:GetHeight(), powerRail:GetHeight(), stack, side))

		local wide = box:GetWidth() - side - px
		local at = {
			{ "health", healthRail, px },
			{ "power", powerRail, 2 * px + healthRail:GetHeight() },
		}
		for _, row in ipairs(at) do
			local name, rail, y = row[1], row[2], row[3]
			check(near(rail:GetWidth(), wide),
				("%s: the %s rail is %.0f px wide inside a %.0f px block, expected %.0f")
					:format(key, name, rail:GetWidth(), box:GetWidth(), wide))
			-- Flow pins to the root's top left corner, so this is the offset
			-- into the block: one pixel down for the health rail, past it and
			-- the hairline under it for the power rail.
			local left = key == "target" and px or side
			local point = rail.points and rail.points[1]
			check(point and point[1] == "TOPLEFT" and point[2] == box
				and point[3] == "TOPLEFT" and near(point[4], left) and near(point[5], -y),
				("%s: the %s rail is pinned at %s, %s and belongs at %.0f, %.0f")
					:format(key, name, tostring(point and point[4]),
						tostring(point and point[5]), left, -y))
		end
	end
end

check(ns.UI.Ticking("skin") ~= nil, "the skin registered no ticker")
local skinPass, skinRead = H.tick("skin"), H.tick("skinread")
-- Both halves at once, the fast pass and the reading behind it, which is what
-- driving the skin's own frame did before every permanent tick moved to one
-- frame. A section that wants one half beats it through H.tick itself.
local skinTicker = {}
function skinTicker:Beat(delta)
	skinPass:Beat(delta)
	skinRead:Beat(delta)
end

local function skinChurn(n)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, n do
		skinTicker:Beat(0.05)
	end
	local after = collectgarbage("count")
	collectgarbage("restart")
	return after - before
end

-- Cold first, the same as the bars: the first pass fills the class colour
-- cache and interns one level tag per frame, and neither is a per tick cost.
skinChurn(200)
local writesBefore = _G.PlayerFrame.healthbar.fill.colorWrites
local blockChurn = skinChurn(200)
local flattenWrites = _G.PlayerFrame.healthbar.fill.colorWrites - writesBefore

-- Left for the sections below.
H.carry.blockChurn, H.carry.flattenWrites, H.carry.skinTicker = blockChurn, flattenWrites, skinTicker
