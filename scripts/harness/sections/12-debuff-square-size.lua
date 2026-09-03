-- How big a debuff square can be before the client blends two copies
--
-- The file used to say 16 and 32 were the sharp sizes. Nobody could have caught
-- that by reading, because the two things that make it false are in different
-- files: UI/Draw.lua crops five texels off each edge of the art, leaving 54 of
-- 64, and EnemyBars.lua insets the art one pixel inside the square's border, so
-- the drawn size is two less than the number in the panel. 54 halves to 27, so
-- the only setting in the range that puts one stored texel on one pixel is 29,
-- and the stepper stepped by two and could not reach it.
--
-- Checked against the arithmetic rather than against a list, so a change to the
-- crop moves the answer here as well as in the panel.

local H = ...
local CHURN, region, ns = H.CHURN, H.region, H.ns
local check = H.check
local blockChurn, idleWrites, listChurn = H.carry.blockChurn, H.carry.idleWrites, H.carry.listChurn
local plateChurn, widget = H.carry.plateChurn, H.carry.widget

do
	local low, high = ns.EnemyBars.IconRange()
	local texels = ns.UI.IconTexels()
	check(texels == 54, ("the crop leaves %s texels, not 54"):format(tostring(texels)))

	-- Once per zoom, because the drawn size is the setting times the zoom less
	-- the border, so which setting is exact moves when the zoom does. At 1x it is
	-- 29 drawing 27 off the half size copy. At 2x it is 28 drawing 54 off the
	-- full size copy, which is the sharpest a spell icon can be drawn.
	local sharpAt = {}
	for _, zoom in ipairs{1, 2, 3} do
		local exact = {}
		for size = low, high do
			local drawn, isExact = ns.EnemyBars.IconAdvice(size, zoom)
			check(drawn == size * zoom - 2,
				("at %dx a %d square draws %d pixels of art, not %d")
					:format(zoom, size, drawn, size * zoom - 2))

			-- The truth, worked out here from the texel count rather than taken
			-- from the function under test.
			--
			-- Non-negative steps only. A whole number of halvings down from 54
			-- texels is a stored copy landing one texel to a pixel. A whole
			-- number the other way is the client stretching 54 texels over 108
			-- pixels, which is clean magnification and is not the same claim, so
			-- it does not count as exact and the panel must not offer it as one.
			local steps = math.log(texels / drawn) / math.log(2)
			local shouldBeExact = steps > -1e-9
				and math.abs(steps - math.floor(steps + 0.5)) < 1e-9
			check(isExact == shouldBeExact,
				("at %dx, %d draws %d pixels from %d texels, %.3f copies down, and IconAdvice says %s")
					:format(zoom, size, drawn, texels, steps, isExact and "exact" or "blended"))

			if isExact then
				exact[#exact + 1] = size
			end
		end
		sharpAt[zoom] = exact
	end

	local function listed(zoom)
		return table.concat(sharpAt[zoom], ", ")
	end

	-- Two at 1x now that the ceiling reaches the second one: 29 draws 27 off the
	-- half size copy, 56 draws the full 54 and is the sharpest a spell icon gets.
	-- At 2x the zoom has already doubled the square, so 28 is the same 54 pixels
	-- and nothing else in the range lands.
	check(listed(1) == "29, 56", ("1x is sharp at %s, expected 29, 56"):format(listed(1)))
	check(listed(2) == "28", ("2x is sharp at %s, expected 28"):format(listed(2)))
	check(ns.EnemyBars.IconAdvice(56, 1) == 54,
		"56 at 1x does not draw the full 54 texel copy one for one")
	check(ns.EnemyBars.IconAdvice(28, 2) == 54,
		"28 at 2x does not draw the full 54 texel copy one for one")

	-- The advice points at the nearer of the two, not simply the largest.
	local _, _, near20 = ns.EnemyBars.IconAdvice(20, 1)
	local _, _, near50 = ns.EnemyBars.IconAdvice(50, 1)
	check(near20 == 29, ("at 20 the panel points at %s, not 29"):format(tostring(near20)))
	check(near50 == 56, ("at 50 the panel points at %s, not 56"):format(tostring(near50)))

	check(ns.EnemyBars.DescribeIcon(20, 1):find("29", 1, true) ~= nil,
		"the note at 20 does not name the size that is sharp: " .. ns.EnemyBars.DescribeIcon(20, 1))
	check(ns.EnemyBars.DescribeIcon(29, 1):find("one stored texel per pixel", 1, true) ~= nil,
		"the note at 29 does not say it is exact: " .. ns.EnemyBars.DescribeIcon(29, 1))

	local advertised = sharpAt[1][1]

	-- The sharp size is odd, and half of an odd icon is where the threat line
	-- used to land. Laid out at it here so the anchor check at the end of this
	-- file sees the odd case as well as the even one it gets from the default.
	local shipped = ns.db.barsIconSize
	ns.db.barsIconSize = advertised
	ns.EnemyBars.ApplyLayout()
	ns.EnemyBars.Rebuild()
	local _, _, _, _, threatY = widget.threatText:GetPoint()
	check(math.abs(threatY - math.floor(threatY + 0.5)) < 1e-6,
		("an odd icon put the threat line at %.3f pixels"):format(threatY))

	-- Every string the bar draws, against the three roles in UI/Text.lua.
	--
	-- One. Text over art the addon did not paint is flat and carries a shadow.
	-- An outline is a rim drawn round the glyph, so it costs the same number of
	-- pixels whatever the glyph is, and below about fourteen it has eaten the
	-- counters: the hole in a 6, the waist of an 8. The bars drew these outlined
	-- at seven to twelve pixels, which is where a stack count stops being a
	-- digit.
	--
	-- Two. Text over the world is outlined, at or above the floor. It has no
	-- known colour behind it, so a shadow has nothing to be darker than and flat
	-- is not softer, it is gone.
	--
	-- Three. Text over a fill the palette owns is flat and bare. Not because a
	-- rim looks wrong there but because Unit/Color.lua guarantees the contrast,
	-- and the section under this one is what holds it to that.
	local floor = ns.UI.OutlineFloor()

	-- Read back off the font object rather than off the constant, because the
	-- size a string ends up at is the smaller of the design size and a fraction
	-- of the icon, and it is the second one that produced the bad values.
	local function inspect(label, region)
		local _, drawnAt, flags = region:GetFont()
		local shadowX = select(1, region:GetShadowOffset())
		check(drawnAt ~= nil, ("the %s reports no font"):format(label))
		-- MONOCHROME was the default here for one commit and it was wrong: an
		-- unhinted face at this size rounds each stem independently and the
		-- report was that every string in the addon went fuzzy. Asserted rather
		-- than written down, because the next person to reach for it will reach
		-- for it in UI/Text.lua and not in the note explaining why not to.
		check(not (flags or ""):find("MONOCHROME", 1, true),
			("the %s has the rasteriser turned off, which broke Arial Narrow's"
				.. " stems the last time it was tried"):format(label))
		return drawnAt, flags or "", shadowX
	end

	local outlined, flat = 0, 0
	for size = low, high do
		ns.db.barsIconSize = size
		ns.EnemyBars.ApplyLayout()
		ns.EnemyBars.Rebuild()
		local holder = widget.icons[1]
		for _, part in ipairs{ { "timer", holder.timer }, { "count", holder.count } } do
			local drawnAt, flags, shadowX = inspect(
				("%s on a %d square"):format(part[1], size), part[2])
			if drawnAt then
				if flags:find("OUTLINE", 1, true) then
					outlined = outlined + 1
				else
					flat = flat + 1
					check(shadowX > 0,
						("at icon %d the %s is flat with no shadow, so it has nothing"
							.. " holding it off the art under it"):format(size, part[1]))
				end
			end
		end
	end
	-- Every one of them comes out flat, at every icon size, and that is now the
	-- rule rather than an accident of the caps: ns.UI.NumberFont has no outlined
	-- branch left to reach. Worth knowing rather than hiding: a 56 pixel square
	-- still carries a 12 pixel timer, which is legible but small for the room it
	-- has, because both numbers are capped by a design constant.
	check(outlined == 0,
		("%d numbers on a debuff square are outlined, and ns.UI.NumberFont should"
			.. " have no way left to produce one"):format(outlined))

	-- So the rule itself is checked where it lives, rather than through a call
	-- site that can only ever reach one size. Either side of the old switch
	-- point, because that is where a reintroduced branch would show.
	for _, size in ipairs{ floor - 1, floor, floor + 6 } do
		local font = ns.UI.NumberFont(size)
		local _, drawnAt, flags = font:GetFont()
		local shadowX = select(1, font:GetShadowOffset())
		check(drawnAt == size and not flags:find("OUTLINE", 1, true) and shadowX > 0,
			("NumberFont at %d came back %s with flags %q and a %s pixel shadow")
				:format(size, tostring(drawnAt), tostring(flags), tostring(shadowX)))
	end

	-- And the other side of the same rule, across every string the bar draws.
	--
	-- The two that sit in the gap above the gauge were 12 and outlined, which is
	-- the one combination that is wrong both ways at once: too small to carry a
	-- rim and unable to drop it. The three over the fill are listed separately,
	-- because an opaque backing is what lets them take a shadow instead.
	local OVER_THE_WORLD = {
		{ "threat line", function(w) return w.threatText end },
		{ "targeted by", function(w) return w.targetedBy end },
	}
	for _, entry in ipairs(OVER_THE_WORLD) do
		local drawnAt, flags = inspect(entry[1], entry[2](widget))
		check(flags:find("OUTLINE", 1, true),
			("the %s went flat, and it has no background to be flat over")
				:format(entry[1]))
		check(drawnAt and drawnAt >= floor,
			("the %s is %s pixels over the world, under the %d floor, and cannot drop its outline")
				:format(entry[1], tostring(drawnAt), floor))
	end

	local OVER_THE_FILL = {
		{ "level", function(w) return w.levelText end },
		{ "name", function(w) return w.name end },
		{ "health number", function(w) return w.healthText end },
	}
	for _, entry in ipairs(OVER_THE_FILL) do
		local region = entry[2](widget)
		local _, flags, shadowX = inspect(entry[1], region)
		check(flags == "" and shadowX == 0,
			("the %s carries %q and a %s pixel shadow over a fill whose contrast"
				.. " the palette already guarantees"):format(entry[1], flags, tostring(shadowX)))
	end

	print(("fonts  %d numbers on a square, all flat and shadowed; %d strings over the"
		.. " fill flat and bare; %d over the world outlined at %d px or more")
		:format(flat, #OVER_THE_FILL, #OVER_THE_WORLD, floor))

	print(("icons  %d texels sampled, range %d to %d; sharp at %s square at 1x, %s at 2x")
		:format(texels, low, high, listed(1), listed(2)))

	ns.db.barsIconSize = shipped
	ns.EnemyBars.ApplyLayout()
	ns.EnemyBars.Rebuild()
end

print(("grid   %s"):format(ns.UI.Describe()))
print(("bar    %.0f x %.0f px, box %.0f idle and %.0f casting, icon %.0f, hairline %.0f")
	:format(widget:GetWidth(), widget:GetHeight(), widget.boxIdle, widget.boxOpen,
		widget.icons[1]:GetWidth(), widget.box.edges[1].height))
print(("plates %s"):format(ns.Plates.Describe()))
local playerBox = _G.WarriorKitPlayerButton
local player = ns.FrameSkin.Entry("player")
print(("skin   %s; player block %.0f x %.0f px, gauge %.0f and %.0f, hairline %.0f")
	:format(ns.FrameSkin.Describe(), playerBox:GetWidth(), playerBox:GetHeight(),
		player.healthBar:GetHeight(), player.powerBar:GetHeight(),
		player.edges[1].height))
print(("churn  %.2f KB per 50 plate ticks, %.2f KB per 50 list ticks, two bars, gate is %.2f")
	:format(plateChurn, listChurn, CHURN.list))
print(("skin   %.2f KB per 50 ticks across three frames, gate is %.2f; %d colour writes on the fill in 200 idle ticks")
	:format(blockChurn, CHURN.skin, idleWrites))

check(listChurn <= CHURN.list,
	("the list collector allocates %.2f KB per 50 ticks, over the %.2f gate")
		:format(listChurn, CHURN.list))
check(plateChurn <= CHURN.list,
	("the plate path allocates %.2f KB per 50 ticks, over the %.2f gate")
		:format(plateChurn, CHURN.list))
check(blockChurn <= CHURN.skin,
	("the skin allocates %.2f KB per 50 ticks, over the %.2f gate")
		:format(blockChurn, CHURN.skin))
-- The bars are ours and nothing writes their colour back, so an idle tick
-- must not paint one: the unit's colour is compared by table identity before
-- the write, and a tick that wrote anyway is a tick that measures and relays
-- out a bar for nothing.
check(idleWrites == 0,
	("the skin painted the health bar's fill %d times in 200 idle ticks, and nothing had moved")
		:format(idleWrites))

-- Left for the sections below.
H.carry.playerBox = playerBox
