-- The fit, off and back on
--
-- The skin resizes three frames it does not own and re-anchors one of them,
-- and that is the change in this part that has to be reversible without a
-- reload: everything else it does to a unit frame is a texture hidden or a
-- region moved, and the frame's own rectangle is what Edit Mode saves against.
--
-- Turned off, every frame is the size the stub built and target of target is
-- back on the anchor the stub wrote. Turned back on, all three fit again,
-- which is what catches a restore that handed back the fitted size as though
-- it were the original.

local H = ...
local ns, check, targetFrame = H.ns, H.check, H.targetFrame
local totFrame, BUILT = H.totFrame, H.BUILT
local blocks = H.carry.blocks

local function screenSize(frame)
	return frame:GetWidth() * frame:GetEffectiveScale(),
		frame:GetHeight() * frame:GetEffectiveScale()
end

-- Under the target's block and not under the target's frame. Those two have
-- the same bottom edge on every frame but this one, where the frame carries
-- the strip the client's aura row hangs in, and hanging target of target off
-- the frame would leave a row of icons' worth of gap above it.
local perch = totFrame.points and totFrame.points[1]
check(perch ~= nil and perch[2] == _G.WarriorKitSkinTarget and perch[1] == "TOPRIGHT"
	and perch[3] == "BOTTOMRIGHT" and perch[5] < 0,
	"target of target is not parked under the target block, so it is still"
	.. " anchored against a target frame that is no longer that size")

local fitted = {}
for _, block in ipairs(blocks) do
	fitted[block[1]] = { screenSize(block[3]) }
end

ns.db.skin = false
ns.FrameSkin.Apply()

for _, block in ipairs(blocks) do
	local key, frame = block[1], block[3]
	local built = BUILT[frame.name]
	check(frame:GetWidth() == built[1] and frame:GetHeight() == built[2],
		("%s: the skin came off and left the frame %.0fx%.0f, not the %.0fx%.0f it found")
			:format(key, frame:GetWidth(), frame:GetHeight(), built[1], built[2]))
end

-- And the mouse region with it. A frame handed back its size while still
-- refusing clicks along its bottom edge is a frame the user cannot use and
-- cannot see why.
local _, _, _, offInset = targetFrame:GetHitRectInsets()
check((offInset or 0) == 0,
	("the skin came off and left the target frame refusing clicks %s units above"
		.. " its own bottom edge"):format(tostring(offInset)))

local back = totFrame.points and totFrame.points[1]
local was = BUILT[totFrame.name][3]
check(back ~= nil and back[1] == was[1] and back[2] == was[2] and back[3] == was[3]
	and back[4] == was[4] and back[5] == was[5],
	"target of target did not get its own anchor back when the skin came off")

ns.db.skin = true
ns.FrameSkin.Apply()

-- The combat feedback number, which is the one Blizzard piece on these frames
-- that a walk over textures cannot reach. It is a font string, it is drawn at
-- Blizzard's size and centred on a portrait that no longer exists at that size,
-- and left alone it lands across the level and the power gauge. Asserted on
-- both frames, and asserted through Show, because Blizzard's own combat handler
-- calls Show on it at every hit and a plain Hide would last until the next one.
for _, name in ipairs({ "PlayerHitIndicator", "TargetFrameHitIndicator" }) do
	local text = _G[name]
	check(text ~= nil, ("the harness has no %s to hide"):format(name))
	text:Show()
	check(not text:IsShown(),
		("%s came back the moment the client showed it, so the damage number"
			.. " still lands across the level"):format(name))
end

for _, block in ipairs(blocks) do
	local key, frame = block[1], block[3]
	local wide, tall = screenSize(frame)
	check(math.abs(wide - fitted[key][1]) < 1e-6 and math.abs(tall - fitted[key][2]) < 1e-6,
		("%s: the second fit came out %.2f x %.2f of screen, the first %.2f x %.2f")
			:format(key, wide, tall, fitted[key][1], fitted[key][2]))
end

-- Left for the sections below.
H.carry.back = back
