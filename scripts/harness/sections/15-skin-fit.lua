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
--
-- The link is the second half and the same kind of claim. It writes an anchor
-- on a frame the addon does not own, so it is measured between the blocks
-- rather than inside one, and it has to come off again without a reload.

local H = ...
local ns, check, targetFrame = H.ns, H.check, H.targetFrame
local totFrame, BUILT = H.totFrame, H.BUILT
local blocks = H.carry.blocks
local fire, debuffs, skinTicker = H.fire, H.debuffs, H.carry.skinTicker

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

-- And the mouse region with it. The fit zeroes the insets so the whole block
-- takes clicks, and a frame handed back its size while still carrying somebody
-- else's idea of where its edge is cannot be used and cannot say why.
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

-- The chain, measured between the blocks rather than inside them
--
-- Edit Mode positions the player block and this addon positions everything
-- against it, so what has to hold is a distance between two frames that are
-- not on the same scale: the blocks are on the pixel grid and the two Blizzard
-- frames are on the UI scale. Every measurement below is taken in screen units
-- and divided by what one screen pixel costs there, because that is the only
-- space the two share and the one a setting is written in.
--
-- The stub leaves the two frames 46 pixels apart vertically on purpose, so
-- every assertion here has something to be wrong about before the link runs.
do
	local Region, fire = H.Region, H.fire
	local playerBox, targetBox = _G.WarriorKitSkinPlayer, _G.WarriorKitSkinTarget

	local function edge(frame, getter)
		return frame[getter](frame) * frame:GetEffectiveScale()
	end

	-- The middle of the screen, in the same units every edge below is read in.
	-- This is the line the pair is a mirror about, so it is the number every
	-- horizontal assertion here is written against.
	local function middle()
		return _G.UIParent:GetWidth() * _G.UIParent:GetEffectiveScale() / 2
	end

	-- One screen pixel in those same units, which is what turns a distance on
	-- the screen into a count a person can read.
	local function pixel()
		return ns.UI.Pixel(playerBox) * playerBox:GetEffectiveScale()
	end

	local function apart(a, aEdge, b, bEdge)
		return (edge(a, aEdge) - edge(b, bEdge)) / pixel()
	end

	-- Three UI scales. The offset written on the target frame is in that
	-- frame's units, so it has to change with the scale for the distance on the
	-- screen to stay the number the setting asks for. A link that skipped the
	-- conversion is exact at 0.65 and out by the ratio everywhere else.
	--
	-- Target of target is measured on the same sweep and for the same reason.
	-- Its three pixels are converted the same way, and a perch that only wrote
	-- its anchor when the state changed rather than on every pass leaves the
	-- old scale's offset under the block after the first of these.
	local shipped = _G.UIParent:GetScale()
	for _, scale in ipairs({ 0.65, 1, 0.5 }) do
		_G.UIParent:SetScale(scale)
		fire("UI_SCALE_CHANGED")
		-- The mirror, stated as the thing you can see: the two facing edges
		-- sit the same distance either side of the middle of the screen, so
		-- their midpoint is the middle of the screen. A pair anchored a fixed
		-- distance apart satisfies nothing here unless the player happens to
		-- be standing exactly where the arithmetic wants it, which is what
		-- was wrong with the first version of this feature.
		local axis = (edge(targetBox, "GetLeft") + edge(playerBox, "GetRight")) / 2
		check(math.abs(axis - middle()) / pixel() < 1e-6,
			("at ui scale %.2f the mirror line sits %.2f pixels off the middle of"
				.. " the screen"):format(scale, (axis - middle()) / pixel()))
		local drop = apart(playerBox, "GetTop", targetBox, "GetTop")
		check(math.abs(drop) < 1e-6,
			("at ui scale %.2f level 0 left the target block %.2f pixels off the"
				.. " player block's top edge"):format(scale, drop))
		local under = apart(targetBox, "GetBottom", totFrame, "GetTop")
		check(math.abs(under - 3) < 1e-6,
			("at ui scale %.2f target of target sits %.2f pixels under the target"
				.. " block and belongs 3 under it"):format(scale, under))
	end
	_G.UIParent:SetScale(shipped)
	fire("UI_SCALE_CHANGED")

	-- A level that is not zero, because zero is the one value a link that
	-- dropped the vertical offset altogether would also come out with.
	ns.db.skinLevel = 24
	ns.FrameSkin.Relayout()
	local dropped = apart(playerBox, "GetTop", targetBox, "GetTop")
	check(math.abs(dropped - 24) < 1e-6,
		("level 24 put the target block %.2f pixels below the player block"):format(dropped))
	ns.db.skinLevel = ns.DefaultFor("skinLevel")
	ns.FrameSkin.Relayout()

	-- A drag, read back off the screen.
	--
	-- Edit Mode drops a system on an absolute point of its own, so the frame is
	-- put on one here rather than on the anchor the link writes. That is the
	-- whole point of the test: the two numbers have to come back out of four
	-- measured edges, not out of inverting the offset this addon last wrote.
	-- The sideways part of the drag is deliberate: the drop has to be pulled
	-- off the mirror line for the re-anchor below to prove it goes back.
	local pullAside, wantLevel = 77, 33
	local px, scale = pixel(), targetFrame:GetEffectiveScale()
	targetFrame:ClearAllPoints()
	targetFrame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT",
		(edge(playerBox, "GetRight") + pullAside * px) / scale,
		(edge(playerBox, "GetTop") - wantLevel * px) / scale)
	ns.FrameSkin.Landed()
	check(ns.db.skinLevel == wantLevel,
		("the drag landed 33 down and was read back as %s")
			:format(tostring(ns.db.skinLevel)))
	local landed = targetFrame.points and targetFrame.points[1]
	check(landed ~= nil and landed[2] == playerBox,
		"the drop stored its numbers and never re-anchored the target on the player block")
	-- The horizontal half of a drop is not kept, and that is the design rather
	-- than a loss: the target's edge is the player's reflected, so the only
	-- place it can land is opposite wherever the player is. The drag above
	-- pulled it 77 pixels off that line and the re-anchor puts it back. What
	-- the drop is still allowed to set is the vertical, which the check above
	-- asserts.
	local axis = (edge(targetBox, "GetLeft") + edge(playerBox, "GetRight")) / 2
	check(math.abs(axis - middle()) / pixel() < 1e-6,
		("the re-anchor after the drop put the mirror line %.2f pixels off the"
			.. " middle of the screen"):format((axis - middle()) / pixel()))
	ns.db.skinLevel = ns.DefaultFor("skinLevel")
	ns.FrameSkin.Relayout()

	-- Off restores, and it restores the point the frame arrived with rather
	-- than the one the link wrote last.
	ns.db.skinLink = false
	ns.FrameSkin.Apply()
	local own, built = targetFrame.points and targetFrame.points[1], BUILT[targetFrame.name][3]
	check(own ~= nil and own[1] == built[1] and own[2] == built[2] and own[3] == built[3]
		and own[4] == built[4] and own[5] == built[5],
		"the link came off and did not hand the target frame back its own point")

	-- On again in lockdown. Anchoring a secure unit button is what combat
	-- forbids, so the switch has to write nothing at all and finish itself at
	-- PLAYER_REGEN_ENABLED, the same discipline the fit is under.
	local realLockdown, realProtected = _G.InCombatLockdown, Region.IsProtected
	local blocked, inCombat = {}, false
	_G.InCombatLockdown = function() return inCombat end
	function Region:IsProtected() return blocked[self] == true end

	blocked[targetFrame], inCombat = true, true
	ns.db.skinLink = true
	ns.FrameSkin.Apply()
	local held = targetFrame.points and targetFrame.points[1]
	check(held ~= nil and held[2] == _G.UIParent,
		"the link was written onto a protected frame in combat")

	inCombat = false
	fire("PLAYER_REGEN_ENABLED")
	_G.InCombatLockdown, Region.IsProtected = realLockdown, realProtected
	local caught = targetFrame.points and targetFrame.points[1]
	check(caught ~= nil and caught[2] == playerBox,
		"the link never caught up when combat dropped")

	-- And the third link after the first two have been off and on again, which
	-- is the pass that would leave target of target hanging off a corner the
	-- target block no longer has.
	local relinked = apart(targetBox, "GetBottom", totFrame, "GetTop")
	check(math.abs(relinked - 3) < 1e-6,
		("after a relink target of target sits %.2f pixels under the target block")
			:format(relinked))

	-- The distance across is not a setting and must not quietly become one
	-- again. A default named skinGap would land in ns.db here, and a link that
	-- read it would pass every check above while the mirror only held for
	-- whatever number it happened to hold.
	check(ns.db.skinGap == nil,
		"skinGap is back in the settings and the distance across is the mirror")

	print(("link   the mirror line is the middle of the screen at ui scale 0.65,"
		.. " 1 and 0.5, 3 px under the target block; a drag reads back %d down")
		:format(wantLevel))
end

----------------------------------------------------------------------
-- Told rather than polled
--
-- The sections above are what the three blocks draw. This is when they draw it:
-- the client says a unit's health, power, auras or connection moved, the block
-- is marked, and the pass a fifth of a second later draws what is marked. A
-- part that only ever ran on the tick would pass every check above and be
-- reading the client from the top five times a second to find out that nothing
-- had happened.
--
-- The target's debuff row is what all of it is read off, because the row is a
-- named global and a square is either up or it is not. What is being asserted
-- is the marking, not the drawing, which section 14 already settled.
--
-- The two clocks have to be put in a known phase before any of it means
-- anything. Both tickers hang off one frame and one long frame fires them both
-- and leaves both accumulators at zero, after which four short frames drive the
-- fast pass alone. Without that the reading could land on any of these lines
-- and the section would be measuring the phase it happened to start in.
----------------------------------------------------------------------

do
	local row = _G.WarriorKitTargetDebuffs
	local function settle()
		skinTicker.scripts.OnUpdate(skinTicker, 5)
	end
	local function pass()
		skinTicker.scripts.OnUpdate(skinTicker, 0.25)
	end
	local function lit()
		return row.children[1]:IsShown()
	end

	debuffs.target = nil
	settle()
	check(not lit(), "the target's debuff row is drawing something before this starts")

	-- One debuff and the event that says so, then one pass.
	debuffs.target = { { name = "Rend", icon = "Rend", spell = 11574,
		count = 1, duration = 21, expires = 121, source = "player" } }
	fire("UNIT_AURA", "target")
	pass()
	check(lit(), "a debuff and its event did not reach the row on the next pass")

	-- Taken away with nobody telling the addon, which is the half that says the
	-- pass is not reading the client any more.
	debuffs.target = nil
	pass()
	check(lit(), "the row redrew on a pass nothing had marked, so it is still polling")

	-- And an event about the wrong unit is not this block's news.
	fire("UNIT_AURA", "player")
	pass()
	check(lit(), "the target block redrew on an event that named another unit")

	-- The reading behind the events, which is what catches a client that fires
	-- none of them.
	settle()
	check(not lit(), "the once a second reading never caught up with the client")
end

----------------------------------------------------------------------
-- The bars, when Blizzard writes its own texture back
--
-- The tick used to read both bars back on every pass to find out whether the
-- client had put UI-StatusBar over the flat colour. It hooks
-- SetStatusBarTexture instead, which is the only call that can swap a status
-- bar's fill, so the readbacks are gone and the hook is what asks for the
-- flatten.
--
-- hooksecurefunc is installed for this block alone and taken away after, the
-- same as in 29-social.lua, 39-party-raid.lua and 43-blizzard-hide.lua and for
-- the same reason: left in the fixture it switches on hooks in other files that
-- have never been able to install here. The skin is turned off and on again
-- because the hook is asked for at style time.
----------------------------------------------------------------------

do
	_G.hooksecurefunc = function(target, name, post)
		local original = target[name]
		target[name] = function(...)
			original(...)
			post(...)
		end
	end
	ns.db.skin = false
	ns.FrameSkin.Apply()
	ns.db.skin = true
	ns.FrameSkin.Apply()
	_G.hooksecurefunc = nil

	local bar = _G.PlayerFrame.healthbar
	skinTicker.scripts.OnUpdate(skinTicker, 5)
	local flat = bar.fill.colorWrites
	skinTicker.scripts.OnUpdate(skinTicker, 5)
	check(bar.fill.colorWrites == flat,
		("the skin flattened the health bar %d more times with nothing having"
			.. " touched it"):format(bar.fill.colorWrites - flat))

	-- The client swapping the art under the bar, which is what the readback used
	-- to be looking for once a fifth of a second per bar.
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	skinTicker.scripts.OnUpdate(skinTicker, 0.25)
	check(bar.fill.colorWrites == flat + 1,
		"Blizzard put its own texture back on the health bar and the skin did not"
		.. " flatten it again on the next pass")
	check(bar.fill:GetTexture() == nil,
		"the health bar is drawing Blizzard's own art under the flat colour")

	print("told   a debuff event draws on the next pass, a pass with nothing"
		.. " marked draws nothing, and the bar is flattened when the client"
		.. " writes its own texture back")
end

-- Left for the sections below.
H.carry.back = back
