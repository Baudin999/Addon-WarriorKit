-- The aura rows on the skinned frames
--
-- The client hangs the target's buffs and debuffs off the frame's bottom left
-- corner, lifted by the height of the art that used to sit under the bars.
-- Fitting the frame to the block took that art away and the same lift then put
-- the row inside the gauge. This file used to assert the answer to that, which
-- was to fit the target frame to the block plus the measured lift so the
-- client's own arithmetic landed the icons under the block.
--
-- That is gone. The rows are hidden and the addon draws its own, which is the
-- only shape available once you want to decide where an aura goes: every icon
-- in the client's target row is a child of a secure unit button, an addon may
-- anchor one out of combat only, and the client re-anchors the head of the row
-- on every aura the target gains or loses.
--
-- So the questions changed. They are no longer "did the frame come out the
-- right height" but "are the client's rows hidden, are ours on the sides of
-- the block they belong on, do they run the way the block is mirrored, and
-- does none of it move when a target picks up a raid's worth of debuffs". The
-- one that carried over is that the frame is the block exactly now, on all
-- three, which is what section 15 goes on to take off and put back.
--
-- Measured off the frames rather than read out of Auras.lua's tables, the same
-- way 06-debuff-row measures the bar's icon row. All four rows are named
-- globals for exactly this reason.

local H = ...
local ns, check = H.ns, H.check
local targetFrame, debuffs, buffs = H.targetFrame, H.debuffs, H.buffs
local targetAnchor = _G.WarriorKitTargetFrame
local child, Region, own = H.child, H.Region, H.own
local skinTicker, fire = H.carry.skinTicker, H.fire

-- The client saying an aura list moved, and then the pass that draws it.
--
-- Both halves, because the rows are told rather than polled now: UNIT_AURA is
-- one of the four events that mark a block, and a pass with nothing marked
-- draws nothing at all. Firing it against both units rather than working out
-- which of the four rows a given check is about, since every one of them is a
-- row on one of these two frames. REFRESH is a fifth of a second, so a quarter
-- of one is exactly one pass and never two.
local function tick()
	fire("UNIT_AURA", "player")
	fire("UNIT_AURA", "target")
	skinTicker:Beat(0.25)
end

local box = _G.WarriorKitTargetButton
local px = ns.Pixel(box)
-- The one gap in UnitFrames/Auras.lua, in the units these frames are drawn in.
local gap = 3 * px
local rowD, rowB = _G.WarriorKitTargetDebuffs, _G.WarriorKitTargetBuffs

check(rowD ~= nil and rowB ~= nil,
	"the skin built no aura rows under the target block")

-- The anchor is the block, on every one of the three. A tail would be a strip
-- of anchor under the block that the drag rim draws round and nothing fills.
local function screenHeight(frame)
	return frame:GetHeight() * frame:GetEffectiveScale()
end
check(math.abs(screenHeight(targetAnchor) - screenHeight(box)) < 1e-6,
	("the target's anchor is %.2f of screen and the block is %.2f, so something is"
		.. " still tailing it"):format(screenHeight(targetAnchor), screenHeight(box)))

local function anchor(frame)
	local point, relative, relativePoint, x, y = frame:GetPoint()
	return point, relative, relativePoint, x or 0, y or 0
end

-- Where a row sits and which way it grows.
--
-- Debuffs under the block and buffs over it, both anchored to the block itself.
-- Nothing chains: a target picking up twelve bleeds cannot move the buffs, and
-- a row that grows grows away from the block in the direction it was already
-- growing.
do
	local point, relative, relativePoint = anchor(rowD)
	check(point == "TOPLEFT" and relative == box and relativePoint == "BOTTOMLEFT",
		("the target's debuff row is anchored %s to %s and belongs under the"
			.. " block on its gauge end")
			:format(tostring(point), tostring(relativePoint)))
	local bpoint, brelative, brelativePoint = anchor(rowB)
	check(bpoint == "BOTTOMLEFT" and brelative == box and brelativePoint == "TOPLEFT",
		("the target's buff row is anchored %s to %s and belongs over the block")
			:format(tostring(bpoint), tostring(brelativePoint)))

	-- Target of target is parked three pixels under the block on the corner the
	-- portrait is on, and the debuff row runs from the other corner, so the two
	-- cannot be chained: the row would land inset by the difference between the
	-- two widths. It clears that frame by dropping past it instead.
	local tot = _G.WarriorKitTargetOfTargetButton
	check(tot:IsShown(), "nothing is parked under the target block, so the drop"
		.. " the debuff row has to clear is not being tested at all")
	local tall = tot:GetHeight() * tot:GetEffectiveScale() / box:GetEffectiveScale()
	local dropped = -select(5, anchor(rowD))
	check(dropped > tall and dropped < tall + 2 * gap,
		("target of target is %.2f tall and the debuff row dropped %.2f, so the"
			.. " two are drawn on top of each other"):format(tall, dropped))
end

-- The squares, in the order the row built them.
local function squares(row)
	return row.children
end
local function leftOf(square)
	return select(4, anchor(square))
end
-- How far the square's own top edge is under the row's, which is what the row
-- above the block has to get right: line one has to sit against the block, not
-- against the far end of a frame sized for a full list.
local function underTop(square)
	return -select(5, anchor(square))
end

-- Nothing built for a unit carrying nothing.
--
-- The rows were built to the client's own ceilings the moment the skin went on:
-- sixteen debuff squares and thirty two buff squares under each of two blocks,
-- ninety six of them, before the player had a target. A row is now as long as
-- the longest list it has actually been shown, and it grows on the pass that
-- finds one longer.
check(#squares(rowD) == 0 and #squares(rowB) == 0,
	("the target's rows built %d squares with nothing on the target")
		:format(#squares(rowD) + #squares(rowB)))

-- Three debuffs, one of them yours and third in the client's order.
local now = _G.GetTime()
debuffs.target = {
	{ name = "Sunder Armor", icon = "sunder", count = 4, expires = now + 20, source = "party1" },
	{ name = "Demoralizing Shout", icon = "demo", expires = now + 25, source = "party2" },
	{ name = "Rend", icon = "rend", expires = now + 12, source = "player" },
}
buffs.target = {
	{ name = "Battle Shout", icon = "shout", expires = now + 100, source = "party1" },
}
tick()

local first, second = squares(rowD)[1], squares(rowD)[2]
check(first ~= nil and second ~= nil,
	"three debuffs on the target built fewer than two squares")
check(#squares(rowD) == 3,
	("three debuffs built %d squares"):format(#squares(rowD)))
check(#squares(rowB) == 1,
	("one buff built %d squares"):format(#squares(rowB)))
local side = first:GetWidth()

-- The target block is mirrored, so its gauge end is its left edge and both its
-- rows start there and run right, away from the corridor in the middle of the
-- screen.
check(leftOf(first) < leftOf(second),
	("square 1 is at x=%.1f and square 2 at x=%.1f, so the target's row runs"
		.. " back towards the corridor"):format(leftOf(first), leftOf(second)))
check(math.abs(leftOf(first)) < 1e-6,
	("square 1 starts %.1f in from the block's gauge end"):format(leftOf(first)))

-- One gap between the block and line one, on both sides of it. Under the
-- block that is the row's own top edge; over it, line one sits against the
-- bottom, which is the edge anchored to the block.
--
-- Measured off the square's height rather than its width, because the two
-- parted company when the time left moved over the art: a square is the icon
-- and the strip of air over it that the number stands in.
do
	check(math.abs(underTop(first) - gap) < 1e-6,
		("line one of the debuff row is %.2f under the row's own top edge and"
			.. " the gap is %.2f"):format(underTop(first), gap))
	local over = rowB:GetHeight() - underTop(squares(rowB)[1]) - first:GetHeight()
	check(math.abs(over - gap) < 1e-6,
		("line one of the buff row is %.2f over the block and the gap is %.2f")
			:format(over, gap))
end

check(first.shownIcon == "rend",
	("square 1 drew %s. Yours go first, because the client's order is the order"
		.. " the auras landed in and a capped row loses your Rend under a raid's"
		.. " worth of other people's bleeds"):format(tostring(first.shownIcon)))
check(first.shownState == "mine", "your own Rend is not drawn as yours")
check(second.shownState == "theirs", "someone else's debuff is not drained")
check(squares(rowD)[3]:IsShown(), "three debuffs did not light three squares")
check(squares(rowB)[1].shownIcon == "shout",
	"the buff row drew nothing for the buff on the target")

-- And nothing on the target again leaves the squares built and dark, because a
-- frame cannot be destroyed on this client and a row that unbuilt itself would
-- build the same three squares on the next mob.
do
	local held = debuffs.target
	debuffs.target = nil
	tick()
	check(#squares(rowD) == 3 and not first:IsShown(),
		"a square is drawn with no debuff on the target")
	debuffs.target = held
	tick()
end

-- The client's own row, hidden, and hidden as it is built rather than once.
check(not _G.TargetFrameDebuff1:IsShown(),
	"the client's first debuff icon is still drawn under our own row")

-- Enough to wrap, which is what a raid's worth of bleeds does. Every square was
-- placed once at layout and the tick shows a prefix of them, so filling the row
-- moves nothing: not the row, not line one, and not the buffs on the far side
-- of the block.
--
-- Twelve, on a row the client caps at sixteen. There used to be a count
-- setting here, shipped at eight, and eight squares fit on one line of the
-- block the addon ships: the row could wrap and never had to, and the ninth
-- buff on you was not on the screen at all. The row runs to the client's own
-- ceiling now and there is no number to raise.
do
	local held = { rowD:GetHeight(), underTop(first), leftOf(first),
		underTop(squares(rowB)[1]) }
	local many = {}
	for index = 1, 12 do
		many[index] = { name = "Bleed" .. index, icon = "bleed",
			expires = now + index, source = index == 1 and "player" or "party1" }
	end
	debuffs.target = many
	tick()
	check(underTop(first) == held[2] and leftOf(first) == held[3],
		"twelve debuffs moved the square you read first")
	check(rowD:GetHeight() > held[1],
		"twelve debuffs wrapped onto a second line and the row did not grow")
	check(underTop(squares(rowB)[1]) == held[4],
		"twelve debuffs on the target moved the buffs over the block")

	local top, wrapped = underTop(squares(rowD)[1]), 0
	for _, square in ipairs(squares(rowD)) do
		if square:IsShown() and underTop(square) ~= top then
			wrapped = wrapped + 1
		end
	end
	check(wrapped > 0, ("twelve debuffs all stayed on one line of a %.0f pixel block")
		:format(box:GetWidth() / px))
	-- Downwards, because the row is under the block. The row over it wraps the
	-- other way and section 02 is where that is asserted against ns.UI.Flow.
	for _, square in ipairs(squares(rowD)) do
		if square:IsShown() then
			check(underTop(square) >= top,
				"a wrapped debuff line went up over the block instead of down")
		end
	end

end

-- The row over the block wraps the other way. Line one stays against the
-- block and the tail hangs above it, so a target picking up a tenth buff
-- grows the row upward and moves nothing you were already reading. The
-- squares on the tail are packed to the gauge end like the full line under
-- them, which is the half a mirrored row gets wrong when the direction is
-- three fields that have to agree rather than one.
do
	local many = {}
	for index = 1, 10 do
		many[index] = { name = "Blessing" .. index, icon = "bless",
			expires = now + 100 + index, source = "party1" }
	end
	buffs.target = many
	tick()

	local up = squares(rowB)
	local top, perLine = underTop(up[1]), 0
	for index = 1, 10 do
		check(up[index]:IsShown(),
			("buff %d of ten on the target is not drawn"):format(index))
		if underTop(up[index]) == top then
			perLine = perLine + 1
		end
	end
	check(perLine < 10, ("ten buffs all stayed on one line of a %.0f pixel block")
		:format(box:GetWidth() / px))
	local tail = up[perLine + 1]
	check(underTop(tail) < top,
		"a wrapped buff line went down into the block instead of up over it")
	check(math.abs(leftOf(tail)) < 1e-6,
		("the wrapped buff line starts %.1f in from the block's gauge end")
			:format(leftOf(tail)))
	buffs.target = { many[1] }
	tick()
end

-- A tick that changes nothing writes nothing. The guard is ns.UI.Aura's and it
-- is the reason the same square can be handed the same texture five times a
-- second for the life of a setting.
do
	local writes = 0
	for _, square in ipairs(squares(rowD)) do
		for _, key in ipairs({ "icon", "timer", "count" }) do
			local art = square[key]
			for _, method in ipairs({ "SetTexture", "SetText", "SetDesaturated" }) do
				if type(art[method]) == "function" and not art["wk" .. method] then
					art["wk" .. method] = art[method]
					art[method] = function(self, ...)
						writes = writes + 1
						return art["wk" .. method](self, ...)
					end
				end
			end
		end
	end
	for _ = 1, 20 do
		tick()
	end
	check(writes == 0,
		("twenty unchanged ticks wrote %d times to a square"):format(writes))
end

-- The client builds its aura buttons on demand, so the sweep has to catch one
-- that did not exist when the skin went on. Built here the way the client
-- builds them: in order, and only once a target has carried that many.
do
	local built = {}
	for index = 2, 4 do
		built[index] = child("button", targetFrame, "TargetFrameDebuff" .. index)
	end

	local realLockdown, realProtected = _G.InCombatLockdown, Region.IsProtected
	local inCombat = true
	_G.InCombatLockdown = function() return inCombat end
	function Region:IsProtected()
		return built[2] == self or built[3] == self or built[4] == self
	end

	tick()
	check(built[2]:IsShown(),
		"combat let the addon hide a protected aura button, which the client refuses")

	inCombat = false
	tick()
	for index = 2, 4 do
		check(not built[index]:IsShown(),
			("combat dropped and TargetFrameDebuff%d was still on screen")
				:format(index))
	end

	_G.InCombatLockdown, Region.IsProtected = realLockdown, realProtected
end

--------------------------------------------------------------------------
-- Your own two rows, under and over the player block
--
-- The same rows off the same settings, drawn by the same file, which is the
-- reason ROWS is keyed by frame rather than copied. What differs comes off the
-- block's mirror alone. The player block is not mirrored, so its gauge end is
-- its right edge: both its rows start there and run left, which is the target's
-- pair reflected across the corridor between them.
--------------------------------------------------------------------------
do
	local playerBox = _G.WarriorKitPlayerButton
	local yourD, yourB = _G.WarriorKitPlayerDebuffs, _G.WarriorKitPlayerBuffs
	check(yourD ~= nil and yourB ~= nil,
		"the skin built no aura rows on the player block")

	local ppoint, prelative, prelativePoint = anchor(yourD)
	check(ppoint == "TOPRIGHT" and prelative == playerBox
		and prelativePoint == "BOTTOMRIGHT",
		("your debuff row is anchored %s to %s and belongs under the block on"
			.. " its gauge end"):format(tostring(ppoint), tostring(prelativePoint)))
	local ybp, ybr, ybrp = anchor(yourB)
	check(ybp == "BOTTOMRIGHT" and ybr == playerBox and ybrp == "TOPRIGHT",
		("your buff row is anchored %s to %s and belongs over the block")
			:format(tostring(ybp), tostring(ybrp)))

	-- Nothing on you, nothing built, the same as the target's pair.
	check(#squares(yourD) == 0 and #squares(yourB) == 0,
		("your rows built %d squares with nothing on you")
			:format(#squares(yourD) + #squares(yourB)))

	-- What is on you, put on the same two stub tables the buff nag walks, and
	-- taken off again at the end of this block so no later section sees a buff
	-- appear under it.
	local heldAuras = own.auras
	debuffs.player = {
		{ name = "Crippling Poison", icon = "poison", expires = now + 8 },
		{ name = "Demoralizing Shout", icon = "demo", expires = now + 25,
			source = "party1" },
	}
	own.auras = {
		{ name = "Battle Shout", icon = "shout", expires = now + 100 },
		{ name = "Power Word: Fortitude", icon = "fort", expires = now + 900,
			source = "party2" },
	}
	tick()

	local yours = squares(yourD)
	check(leftOf(yours[1]) > leftOf(yours[2]),
		("square 1 is at x=%.1f and square 2 at x=%.1f, so your row runs back"
			.. " towards the corridor"):format(leftOf(yours[1]), leftOf(yours[2])))
	check(math.abs((leftOf(yours[1]) + side) - yourD:GetWidth()) < 1e-6,
		("square 1's right edge is at %.1f and the row is %.1f wide, so it does"
			.. " not start on the block's gauge end")
			:format(leftOf(yours[1]) + side, yourD:GetWidth()))
	local yourOver = yourB:GetHeight() - underTop(squares(yourB)[1])
		- squares(yourB)[1]:GetHeight()
	check(math.abs(yourOver - gap) < 1e-6,
		("line one of your buff row is %.2f over the block and the gap is %.2f")
			:format(yourOver, gap))

	check(yours[1].shownIcon == "poison" and yours[2].shownIcon == "demo",
		"your debuff row drew nothing for the two debuffs on you")
	local mine = squares(yourB)
	check(mine[1].shownIcon == "shout" and mine[1].shownState == "mine",
		"your own Battle Shout is not drawn as yours on your own buff row")
	check(mine[2].shownState == "theirs",
		"a buff somebody else put on you is not drained")

	-- A raid's worth of buffs on you, which is the report that started this:
	-- the row stopped at the end of the line and the rest were nowhere. Every
	-- one is drawn, the tail wraps upward, and it runs from the gauge end the
	-- way the full line does, which on your block is the right edge.
	for index = 3, 10 do
		own.auras[index] = { name = "Blessing" .. index, icon = "bless",
			expires = now + 100 + index, source = "party1" }
	end
	tick()
	local top, perLine = underTop(mine[1]), 0
	for index = 1, 10 do
		check(mine[index]:IsShown(),
			("buff %d of ten on you is not drawn"):format(index))
		if underTop(mine[index]) == top then
			perLine = perLine + 1
		end
	end
	check(perLine < 10, "ten buffs on you all stayed on one line")
	local tail = mine[perLine + 1]
	check(underTop(tail) < top,
		"your wrapped buff line went down into the block instead of up over it")
	check(math.abs((leftOf(tail) + side) - yourB:GetWidth()) < 1e-6,
		("your wrapped buff line ends at %.1f and the row is %.1f wide, so the"
			.. " tail is packed to the wrong edge")
			:format(leftOf(tail) + side, yourB:GetWidth()))
	own.auras[3], own.auras[4], own.auras[5] = nil, nil, nil
	for index = 6, 10 do
		own.auras[index] = nil
	end
	tick()

	-- The client's own two, hidden by the same sweep and by name, because
	-- BuffButton1 is built on demand exactly the way TargetFrameDebuff1 is.
	check(not _G.BuffButton1:IsShown() and not _G.DebuffButton1:IsShown(),
		"the client is still drawing your own auras in the corner of the screen")

	-- And the client's own weapon enchant, which is a run of its own under a
	-- name of its own. It was spared while the addon drew no enchant at all;
	-- the row draws both hands now, so the client's copy is a second reading of
	-- the same stone in the top corner of the screen.
	check(not _G.TempEnchant1:IsShown(),
		"the client is still drawing the weapon enchant in the corner of the"
			.. " screen, under a square of ours saying the same number")

	-- The sharpening stone on your weapon, at the head of the buff row. It sits
	-- at no aura index at all, so the walk above cannot find it and hiding the
	-- client's row would otherwise take the last reading of it off the screen.
	own.main, own.mainLeft = true, 1800
	H.swing.mainhand = "|cffffffff|Hitem:12404|h[Dense Sharpening Stone]|h|r"
	tick()
	check(mine[1].auraGear == ns.Gear.MAINHAND,
		"the weapon enchant is not the first square on your buff row")
	check(mine[1].shownIcon == "hand" .. ns.Gear.MAINHAND,
		"the enchant square drew no art, and it borrows the weapon's")
	check(mine[2].shownIcon == "shout",
		"the enchant pushed your buffs off the row instead of leading it")
	own.main, own.mainLeft, H.swing.mainhand = false, 0, nil

	debuffs.player, own.auras = nil, heldAuras
	tick()
	check(not yours[1]:IsShown() and not mine[1]:IsShown(),
		"a square is still lit with nothing on you")
end

-- An aura the client answers with no art at all.
--
-- Allowed, and this row is the only reader in the addon that takes an icon off
-- the aura rather than off a spell it already holds, so it is the only one that
-- can be handed nothing. What it drew before was an empty square with a timer
-- on it, which is a number over the block with nothing behind it. The spell's
-- own texture is the same picture asked for from the other end.
do
	debuffs.target = {
		{ name = "Rend", spell = 772, expires = now + 12, source = "player" },
	}
	tick()
	check(squares(rowD)[1].shownIcon == _G.GetSpellTexture(772),
		("an aura with no icon drew %s, and the spell it came from has art")
			:format(tostring(squares(rowD)[1].shownIcon)))
end

-- The square at another size, because the size is a setting and everything
-- inside the square is anchored to the square's own edges.
--
-- This is the one failure the anchors above cannot see. The timer is a font
-- string and draws off its own anchor whatever the square does, so a square
-- that came out the wrong size still puts its number roughly where the number
-- belongs and shows nothing else at all: no art, no hairline. Reported from the
-- game as "I changed the size and the icon is gone", which is what that looks
-- like from the other end.
--
-- Measured off the widget at three sizes rather than trusting the one the
-- default happens to be, because the range runs from 12 to the block's own
-- height and the arithmetic in between is where a resize goes wrong.
do
	local held = ns.db.skinAuraSize
	for _, want in ipairs({ 12, ns.DefaultFor("skinAuraSize"), 28 }) do
		ns.db.skinAuraSize = want
		ns.FrameSkin.Relayout()
		tick()

		local square = squares(rowD)[1]
		local edge = ns.Pixel(square)
		check(math.abs(square:GetWidth() - want * px) < 1e-6,
			("skin aura %d drew a square %.2f wide and a pixel is %.2f")
				:format(want, square:GetWidth(), px))

		-- The setting is the art. What the widget adds to it is the strip the
		-- time left stands in, over the top edge, and that is the whole of the
		-- difference between the two heights.
		check(math.abs(square.box:GetHeight() - square:GetWidth()) < 1e-6,
			("skin aura %d drew art %.2f by %.2f, which is not a square")
				:format(want, square.box:GetWidth(), square.box:GetHeight()))
		local strip = square:GetHeight() - square.box:GetHeight()
		check(strip >= square.timer:FontSize(),
			("skin aura %d left %.2f over the square for a %.2f pixel number")
				:format(want, strip, square.timer:FontSize()))
		check(math.abs(strip / edge - math.floor(strip / edge + 0.5)) < 1e-6,
			("skin aura %d left %.2f over the square, which is not a whole"
				.. " number of %.2f pixel steps"):format(want, strip, edge))

		-- The number is over the art and not on it, which is the reading the
		-- client's own row gives and the one this row was changed to match.
		local point, to, toPoint, _, lift = square.timer:GetPoint(1)
		check(point == "BOTTOM" and to == square.box and toPoint == "TOP"
			and math.abs(lift - edge) < 1e-6,
			("skin aura %d anchored the time %s to the art's %s at %.2f")
				:format(want, tostring(point), tostring(toPoint), lift or 0))

		-- The mouse stays on the art. A tooltip that opens over the blank sky
		-- above an icon is a tooltip nobody asked for.
		local _, _, top = square:GetHitRectInsets()
		check(math.abs((top or 0) - strip) < 1e-6,
			("skin aura %d takes the mouse %.2f above the art and the strip is"
				.. " %.2f"):format(want, top or 0, strip))

		-- The art, inset by one pixel and given a size of its own. The size is
		-- the half that matters: a region hung off two of the square's corners
		-- has no rectangle until the client works one out, and one it declines
		-- to work out draws nothing and says nothing.
		local top, relative, relativePoint, x, y = square.icon:GetPoint(1)
		check(top == "TOPLEFT" and relative == square.box and relativePoint == "TOPLEFT"
			and math.abs(x - edge) < 1e-6 and math.abs(y + edge) < 1e-6,
			("skin aura %d anchored the art %s to %s at %.2f, %.2f and the inset"
				.. " is one pixel of %.2f")
				:format(want, tostring(top), tostring(relativePoint), x, y, edge))
		check(math.abs(square.icon:GetWidth() - (want * px - 2 * edge)) < 1e-6
			and math.abs(square.icon:GetHeight() - square.icon:GetWidth()) < 1e-6,
			("skin aura %d drew the art %.2f by %.2f inside a %.2f square")
				:format(want, square.icon:GetWidth(), square.icon:GetHeight(),
					square:GetWidth()))

		-- And the hairline round it, thick one way and as long as the square
		-- the other, for the same reason.
		check(math.abs(square.edges[1]:GetHeight() - edge) < 1e-6
			and math.abs(square.edges[1]:GetWidth() - want * px) < 1e-6,
			("skin aura %d drew the top hairline %.2f by %.2f on a %.2f square")
				:format(want, square.edges[1]:GetWidth(),
					square.edges[1]:GetHeight(), square:GetWidth()))
		check(math.abs(square.edges[3]:GetWidth() - edge) < 1e-6
			and math.abs(square.edges[3]:GetHeight() - want * px) < 1e-6,
			("skin aura %d drew the left hairline %.2f by %.2f on a %.2f square")
				:format(want, square.edges[3]:GetWidth(),
					square.edges[3]:GetHeight(), square:GetWidth()))

		-- And it still has its art after the resize, because the guard in
		-- ns.UI.Aura writes the texture once and a square that lost it on a
		-- relayout would never be handed it again. The art here is the one the
		-- block above fell back to, so the fallback is measured at every size
		-- as well.
		check(square.shownIcon == _G.GetSpellTexture(772),
			("skin aura %d left square one holding %s")
				:format(want, tostring(square.shownIcon)))
	end
	ns.db.skinAuraSize = held
	ns.FrameSkin.Relayout()
	tick()
end

-- Off, and neither frame then has a row at all. That is the honest answer
-- rather than an oversight: each frame is its block, so handing the client's
-- row back would hang it in the gauge. Only the skin coming off gives it back,
-- and section 15 is where that happens.
ns.db.skinAuras = false
ns.FrameSkin.Relayout()
check(not rowD:IsShown() and not rowB:IsShown(),
	"skin auras off left a row on screen")
check(not _G.TargetFrameDebuff1:IsShown(),
	"skin auras off gave the client's row back, and it lands inside the gauge")

ns.db.skinAuras = ns.DefaultFor("skinAuras")
ns.FrameSkin.Relayout()
debuffs.target, buffs.target = nil, nil
tick()

-- The switches that take the client's own copies off the screen.
--
-- Five of them, one per thing you can see twice, and each is a plain boolean
-- that does what its label says. They are asserted through ns.db and
-- ns.BlizzHide.Apply rather than through the panel, because the panel is one
-- of two callers and the slash word is the other.
--
-- Two handles do the hiding and both are checked here. A frame goes down for
-- your own rows, which is what survives a button this backport names something
-- the sweep never guessed. The target's rows have no frame between them and
-- TargetFrame, so those go one button at a time, and that half is asserted
-- further up where the sweep is.
--
-- The default install is the case worth asserting first, because it is the one
-- nobody switches.
for _, switch in ipairs(ns.BlizzHide.Switches()) do
	check(ns.db[switch.key],
		("%s does not ship hidden, so the addon draws it twice out of the box")
			:format(switch.label))
end
check(not _G.BuffFrame:IsShown(),
	"the addon draws your buffs and Blizzard's are up too")
check(not _G.TemporaryEnchantFrame:IsShown(),
	"the addon draws the weapon enchant and Blizzard's is up too")

-- Held, the way every other strip in the addon holds what it hides: the client
-- turns its own frames back on whenever it redraws, so hiding one once is not
-- hiding it.
_G.BuffFrame:Show()
check(not _G.BuffFrame:IsShown(),
	"the client showed its own buff frame again and the strip did not hold it")

-- One switch off puts one thing back and leaves the rest where they were,
-- which is the whole of what was asked for. Buffs are the awkward one on this
-- client and so the one worth measuring: BuffFrame holds your debuffs as well
-- here, so it may not go down for a player who asked to keep only the buffs,
-- and the sweep has to be what hides the debuffs on their own.
ns.db.hideBlizzBuffs = false
ns.BlizzHide.Apply()
tick()
check(_G.BuffFrame:IsShown(),
	"buffs were put back and the frame they hang off stayed hidden")
check(_G.TemporaryEnchantFrame:IsShown(),
	"buffs were put back and the weapon enchant beside them stayed hidden")
check(_G.BuffButton1:IsShown(),
	"buffs were put back and the sweep was still holding the first one down")
check(not _G.DebuffButton1:IsShown(),
	"putting the buffs back put the debuffs back with them")

ns.db.hideBlizzBuffs = ns.DefaultFor("hideBlizzBuffs")
ns.BlizzHide.Apply()
tick()
check(not _G.BuffFrame:IsShown() and not _G.BuffButton1:IsShown(),
	"the buffs switch went back on and Blizzard's buffs stayed on screen")

-- The target's cast bar is the one frame in the list that a lockdown can
-- refuse, because it is a child of a secure unit button. Refused, remembered,
-- and taken down when combat drops, like every other strip in the addon.
ns.db.hideBlizzTargetCast = false
ns.BlizzHide.Apply()
check(_G.TargetFrameSpellBar:IsShown(),
	"the cast bar was put back and stayed hidden")

do
	local bar = _G.TargetFrameSpellBar
	local realLockdown, realProtected = _G.InCombatLockdown, Region.IsProtected
	local inCombat = true
	_G.InCombatLockdown = function() return inCombat end
	function Region:IsProtected()
		return bar == self
	end

	ns.db.hideBlizzTargetCast = true
	ns.BlizzHide.Apply()
	check(bar:IsShown(),
		"combat let the addon hide a protected cast bar, which the client refuses")

	-- Remembered rather than dropped, and taken the moment combat ends. The
	-- retry is the file's own PLAYER_REGEN_ENABLED, so this fires the event
	-- rather than calling Apply again: an Apply that works here and an event
	-- that never reaches it is a switch that only answers out of combat.
	inCombat = false
	H.fire("PLAYER_REGEN_ENABLED")
	check(not bar:IsShown(),
		"combat dropped and Blizzard's cast bar was still on screen")

	_G.InCombatLockdown, Region.IsProtected = realLockdown, realProtected
end

print(("auras  debuffs grown to %d under each block and buffs to %d over it, square"
	.. " %.0f px under a %.0f px strip for the time, the client's own rows"
	.. " hidden as they are built")
	:format(#squares(rowD), #squares(rowB), side,
		squares(rowD)[1]:GetHeight() - squares(rowD)[1].box:GetHeight()))
