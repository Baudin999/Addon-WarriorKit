-- The two bars, measured against the block they divide
--
-- The inside of the block is laid out by ns.UI.Flow, and this is the check
-- the enemy bars did not have when the same engine handed their gauge a height
-- of one pixel: a node with no size and no grow measures zero, is given a
-- pixel, and draws a bar nobody can read. Every anchor in that layout was
-- individually correct and nothing caught it until somebody measured it.
--
-- So both bars are measured, and against the block rather than against the
-- settings. Health, power and the three hairlines are the block's height. Each
-- bar is the block less the portrait's square and less the pixel the outline
-- draws into. Both start where the square stops, which the mirror puts on the
-- other side of the block.

local H = ...
local ns, check = H.ns, H.check
local blocks = H.carry.blocks

for _, block in ipairs(blocks) do
	local key, button = block[1], block[3]
	local entry = ns.FrameSkin.Entry(key)
	local healthBar, powerBar = entry and entry.healthBar, entry and entry.powerBar
	if healthBar and powerBar then
		local px = ns.UI.Pixel(button)
		-- The block's height, which is also the side of the portrait's square.
		local side = button:GetHeight()
		local function near(a, b) return math.abs(a - b) < 1e-9 end

		-- Two bars and three hairlines fill the square exactly. A fractional
		-- share would leave a seam along one of them, which reads as a
		-- rendering fault rather than as a layout that does not add up.
		local stack = healthBar:GetHeight() + powerBar:GetHeight() + 3 * px
		check(near(stack, side),
			("%s: a %.0f px health bar and a %.0f px power bar with three hairlines"
				.. " come to %.0f, and the block is %.0f")
				:format(key, healthBar:GetHeight(), powerBar:GetHeight(), stack, side))

		local wide = button:GetWidth() - side - px
		local at = {
			{ "health", healthBar, px },
			{ "power", powerBar, 2 * px + healthBar:GetHeight() },
		}
		for _, row in ipairs(at) do
			local name, bar, y = row[1], row[2], row[3]
			check(near(bar:GetWidth(), wide),
				("%s: the %s bar is %.0f px wide inside a %.0f px block, expected %.0f")
					:format(key, name, bar:GetWidth(), button:GetWidth(), wide))
			-- Flow pins to the root's top left corner, so this is the offset
			-- into the block: one pixel down for the health bar, past it and
			-- the hairline under it for the power bar.
			local left = key == "target" and px or side
			local point = bar.points and bar.points[1]
			check(point and point[1] == "TOPLEFT" and point[2] == button
				and point[3] == "TOPLEFT" and near(point[4], left) and near(point[5], -y),
				("%s: the %s bar is pinned at %s, %s and belongs at %.0f, %.0f")
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
-- The bars are ours and nothing writes their colour back, so two hundred idle
-- ticks should paint the health bar's fill exactly never.
local fill = ns.FrameSkin.Entry("player").healthBar.fill
local writesBefore = fill.colorWrites
local blockChurn = skinChurn(200)
local idleWrites = fill.colorWrites - writesBefore

-- Left for the sections below.
H.carry.blockChurn, H.carry.idleWrites, H.carry.skinTicker = blockChurn, idleWrites, skinTicker
