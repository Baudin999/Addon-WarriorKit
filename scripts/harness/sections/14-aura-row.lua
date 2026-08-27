-- The target's aura rows
--
-- The client hangs the target's buffs and debuffs off the frame's bottom left
-- corner, lifted by the height of the art that used to sit under the bars.
-- Fitting the frame to the block took that art away and the same lift then put
-- the row inside the gauge. This file used to assert the answer to that, which
-- was to fit the frame to the block plus the measured lift so the client's own
-- arithmetic landed the icons under the block.
--
-- That is gone. The row is hidden and the addon draws its own, which is the
-- only shape available once you want to decide where an aura goes: every icon
-- in the client's row is a child of a secure unit button, an addon may anchor
-- one out of combat only, and the client re-anchors the head of the row on
-- every aura the target gains or loses.
--
-- So the questions changed. They are no longer "did the frame come out the
-- right height" but "is the client's row hidden, is ours where the block says,
-- and does it stay right when the target picks up a raid's worth of debuffs".
-- The one that carried over is the last: the frame is the block exactly now,
-- on all three, which is what section 15 goes on to take off and put back.
--
-- Measured off the frames rather than read out of Auras.lua's tables, the same
-- way 06-debuff-row measures the bar's icon row. Both rows are named globals
-- for exactly this reason.

local H = ...
local ns, check = H.ns, H.check
local targetFrame, debuffs, buffs = H.targetFrame, H.debuffs, H.buffs
local child, Region, own = H.child, H.Region, H.own
local skinTicker = H.carry.skinTicker

-- One pass of the skin's own ticker, which is what draws the rows. REFRESH is
-- a fifth of a second, so a quarter of one is exactly one pass.
local function tick()
	skinTicker.scripts.OnUpdate(skinTicker, 0.25)
end

local box = _G.WarriorKitSkinTarget
local px = ns.Pixel(box)
local rowD, rowB = _G.WarriorKitTargetDebuffs, _G.WarriorKitTargetBuffs

check(rowD ~= nil and rowB ~= nil,
	"the skin built no aura rows under the target block")

-- The frame is the block, on every one of the three. That was the whole point
-- of deleting the lift: a tail is a strip of frame under the block that takes
-- clicks and draws an Edit Mode selection round nothing you can see.
local function screenHeight(frame)
	return frame:GetHeight() * frame:GetEffectiveScale()
end
check(math.abs(screenHeight(targetFrame) - screenHeight(box)) < 1e-6,
	("the target frame is %.2f of screen and the block is %.2f, so something is"
		.. " still tailing it"):format(screenHeight(targetFrame), screenHeight(box)))

local _, _, _, bottom = targetFrame:GetHitRectInsets()
check((bottom or 0) == 0,
	("the target frame refuses clicks %s units above its own bottom edge, and"
		.. " there is no longer anything down there"):format(tostring(bottom)))

-- Where the chain hangs. Target of target is parked on exactly the corner the
-- rows hang from, so while it is shown the first row goes under it.
local function anchor(frame)
	local point, relative, relativePoint, x, y = frame:GetPoint()
	return point, relative, relativePoint, x or 0, y or 0
end

local point, relative, relativePoint = anchor(rowD)
check(point == "TOPRIGHT" and relativePoint == "BOTTOMRIGHT",
	("the debuff row is anchored %s to %s, and the target block is mirrored")
		:format(tostring(point), tostring(relativePoint)))
check(relative == _G.TargetFrameToT,
	"target of target is parked under the block and the debuff row is not"
	.. " hanging off it, so the two are drawn on top of each other")

local bpoint, brelative, brelativePoint = anchor(rowB)
check(bpoint == "TOPRIGHT" and brelative == rowD and brelativePoint == "BOTTOMRIGHT",
	"the buff row is not hanging off the bottom of the debuff row")

-- The squares, in the order the row built them.
local function squares(row)
	return row.children
end
local first, second = squares(rowD)[1], squares(rowD)[2]
check(first ~= nil and second ~= nil, "the debuff row built fewer than two squares")

local function leftOf(square)
	local _, _, _, x = anchor(square)
	return x
end
local side = first:GetWidth()
check(leftOf(first) > leftOf(second),
	("square 1 is at x=%.1f and square 2 at x=%.1f, so the row runs the wrong"
		.. " way for a mirrored block"):format(leftOf(first), leftOf(second)))
check(math.abs((leftOf(first) + side) - rowD:GetWidth()) < 1e-6,
	("square 1's right edge is at %.1f and the row is %.1f wide, so the row is"
		.. " not packed against the block's own edge")
		:format(leftOf(first) + side, rowD:GetWidth()))

-- Nothing on the target, so nothing drawn, and an empty row costs no height.
-- That is what puts the buff row against the block rather than one gap below
-- where the debuffs would have been.
check(not first:IsShown(), "a square is drawn with no debuff on the target")
check(math.abs(rowD:GetHeight() - px) < 1e-6,
	("an empty debuff row is %.2f tall and should be one pixel")
		:format(rowD:GetHeight()))

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

check(first.shownIcon == "rend",
	("square 1 drew %s. Yours go first, because the client's order is the order"
		.. " the auras landed in and a capped row loses your Rend under a raid's"
		.. " worth of other people's bleeds"):format(tostring(first.shownIcon)))
check(first.shownState == "mine", "your own Rend is not drawn as yours")
check(second.shownState == "theirs", "someone else's debuff is not drained")
check(squares(rowD)[3]:IsShown() and not squares(rowD)[4]:IsShown(),
	"three debuffs did not light exactly three squares")
check(squares(rowB)[1].shownIcon == "shout",
	"the buff row drew nothing for the buff on the target")

local oneLine = rowD:GetHeight()
check(oneLine > side and oneLine < side * 2,
	("three debuffs on one line made the row %.2f tall and a square is %.2f")
		:format(oneLine, side))

-- The client's own row, hidden, and hidden as it is built rather than once.
check(not _G.TargetFrameDebuff1:IsShown(),
	"the client's first debuff icon is still drawn under our own row")

-- Enough to wrap. The row grows downwards and its height says so, which is the
-- only thing the tick moves: every square was placed once at layout.
local many = {}
for index = 1, 12 do
	many[index] = { name = "Bleed" .. index, icon = "bleed",
		expires = now + index, source = index == 1 and "player" or "party1" }
end
debuffs.target = many
tick()
check(rowD:GetHeight() > oneLine,
	("twelve debuffs left the row at %.2f, the same height three took")
		:format(rowD:GetHeight()))
local top = select(5, anchor(squares(rowD)[1]))
local wrapped = 0
for _, square in ipairs(squares(rowD)) do
	if square:IsShown() and select(5, anchor(square)) ~= top then
		wrapped = wrapped + 1
	end
end
check(wrapped > 0, "twelve debuffs all stayed on one line of a 202 pixel block")

-- A tick that changes nothing writes nothing. The guard is ns.UI.Aura's and it
-- is the reason the same square can be handed the same texture five times a
-- second for the life of a setting.
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
check(writes == 0, ("twenty unchanged ticks wrote %d times to a square"):format(writes))

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
-- Your own two rows, under the player block
--
-- The same rows off the same settings, drawn by the same file, which is the
-- reason ROWS is keyed by frame rather than copied. Two things differ and both
-- come off the spec. The player block is not mirrored, so its rows run left to
-- right from the corner the portrait is on. And nothing is ever parked under
-- that block, so the debuff row hangs on the block itself rather than on a
-- perch the way the target's hangs under target of target.
--------------------------------------------------------------------------
do
	local playerBox = _G.WarriorKitSkinPlayer
	local yourD, yourB = _G.WarriorKitPlayerDebuffs, _G.WarriorKitPlayerBuffs
	check(yourD ~= nil and yourB ~= nil,
		"the skin built no aura rows under the player block")

	local ppoint, prelative, prelativePoint = anchor(yourD)
	check(ppoint == "TOPLEFT" and prelativePoint == "BOTTOMLEFT",
		("your debuff row is anchored %s to %s, and the player block is not"
			.. " mirrored"):format(tostring(ppoint), tostring(prelativePoint)))
	check(prelative == playerBox,
		"your debuff row is not hanging off the player block itself, and there"
		.. " is nothing parked under that block for it to hang off instead")
	local bp, br = anchor(yourB)
	check(bp == "TOPLEFT" and br == yourD,
		"your buff row is not hanging off the bottom of your debuff row")

	local yours = squares(yourD)
	check(leftOf(yours[1]) < leftOf(yours[2]),
		("square 1 is at x=%.1f and square 2 at x=%.1f, so your row runs the"
			.. " wrong way for a block that is not mirrored")
			:format(leftOf(yours[1]), leftOf(yours[2])))
	check(math.abs(leftOf(yours[1])) < 1e-6,
		("square 1 starts %.1f in from the block's own edge, and it should be"
			.. " against it"):format(leftOf(yours[1])))

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
	check(yours[1].shownIcon == "poison" and yours[2].shownIcon == "demo",
		"your debuff row drew nothing for the two debuffs on you")
	local mine = squares(yourB)
	check(mine[1].shownIcon == "shout" and mine[1].shownState == "mine",
		"your own Battle Shout is not drawn as yours on your own buff row")
	check(mine[2].shownState == "theirs",
		"a buff somebody else put on you is not drained")

	-- The client's own two, hidden by the same sweep and by name, because
	-- BuffButton1 is built on demand exactly the way TargetFrameDebuff1 is.
	check(not _G.BuffButton1:IsShown() and not _G.DebuffButton1:IsShown(),
		"the client is still drawing your own auras in the corner of the screen")

	debuffs.player, own.auras = nil, heldAuras
	tick()
	check(not yours[1]:IsShown() and not mine[1]:IsShown(),
		"a square is still lit with nothing on you")
end

-- Off, and the target then has no row at all. That is the honest answer rather
-- than an oversight: the frame is the block, so handing the client's row back
-- would hang it inside the gauge. Only the skin coming off gives it back, and
-- section 15 is where that happens.
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

print(("auras  debuffs %d wide and buffs %d under each of the two blocks,"
	.. " square %.0f px, the client's own rows hidden as they are built")
	:format(#squares(rowD), #squares(rowB), side))
