-- Off, on, and where the three hang
--
-- The frames are ours, so turning the part off is three buttons down and
-- three unit watches released, and turning it back on is the same three up at
-- the size they had. Blizzard's own three are a different switch, in
-- Core/BlizzHide.lua, and that half is asserted here too because the two
-- switches together are what leave you with exactly one set of frames.
--
-- The chain is the second half and the same kind of claim. The target block
-- hangs off the player block while the link is on and on a point of its own
-- while it is off, and a drag on either writes the right number back: the
-- player's corner, the target's corner, or the level. Every one of those has
-- to hold at three UI scales and has to come off again without a reload.

local H = ...
local ns, check = H.ns, H.check
local blocks = H.carry.blocks
local fire, debuffs, skinTicker = H.fire, H.debuffs, H.carry.skinTicker

local playerAnchor, targetAnchor = _G.WarriorKitPlayerFrame, _G.WarriorKitTargetFrame
local totAnchor = _G.WarriorKitTargetOfTargetFrame
local playerButton, targetButton = _G.WarriorKitPlayerButton, _G.WarriorKitTargetButton
local totButton = _G.WarriorKitTargetOfTargetButton

-- Under the target's block by the edge the two share: the target is mirrored
-- and target of target is not, so aligning their outer edges is what puts one
-- portrait under the other.
local perch = totAnchor.points and totAnchor.points[1]
check(perch ~= nil and perch[2] == targetAnchor and perch[1] == "TOPRIGHT"
	and perch[3] == "BOTTOMRIGHT" and perch[5] < 0,
	"target of target is not parked under the target block by their shared edge")

local built = {}
for _, block in ipairs(blocks) do
	built[block[1]] = { block[3]:GetWidth(), block[3]:GetHeight() }
end

----------------------------------------------------------------------
-- Off and back on
----------------------------------------------------------------------

ns.db.skin = false
ns.FrameSkin.Apply()

for _, block in ipairs(blocks) do
	check(not block[3]:IsShown(),
		("%s: the frames came off and the button is still on the screen"):format(block[1]))
end
check(not _G.UnitWatchRegistered(targetButton) and not _G.UnitWatchRegistered(totButton),
	"the frames came off and the client is still watching two of the buttons")
check(not _G.PlayerFrame:IsVisible(),
	"our frames came off and Blizzard's came back, which is a different switch")

ns.db.skin = true
ns.FrameSkin.Apply()

for _, block in ipairs(blocks) do
	local key, button = block[1], block[3]
	check(button:IsShown(), ("%s: the frames went back on and the button stayed down"):format(key))
	check(button:GetWidth() == built[key][1] and button:GetHeight() == built[key][2],
		("%s: the second layout came out %.0f x %.0f, the first %.0f x %.0f")
			:format(key, button:GetWidth(), button:GetHeight(), built[key][1], built[key][2]))
end
check(_G.UnitWatchRegistered(targetButton) and _G.UnitWatchRegistered(totButton),
	"the frames went back on and the buttons are not back on the client's unit watch")

-- The four aura rows, which are the one thing on a block that a second part
-- takes off and puts back. Unstyle hides these frames and Auras.Place is the
-- only thing that shows one, and Place lays a row out only when one of the five
-- numbers it reads has moved. A skin toggled off and on moves none of them, so
-- the rows came back hidden and the character carried no debuffs anybody could
-- see for the rest of the session.
for _, name in ipairs({ "WarriorKitPlayerDebuffs", "WarriorKitPlayerBuffs",
	"WarriorKitTargetDebuffs", "WarriorKitTargetBuffs" }) do
	check(_G[name] ~= nil and _G[name]:IsShown(),
		("%s: the frames went back on and the aura row stayed down"):format(name))
end

-- Blizzard's three, through their own switch. Off, the player frame is
-- handed back to its parent and drawn; on, it is caged again.
ns.db.hideBlizzUnitFrames = false
ns.BlizzHide.Apply()
check(_G.PlayerFrame:IsVisible() and _G.TargetFrame:IsVisible(),
	"the switch came off and Blizzard's player and target frames stayed hidden")
check(not ns.Attic.Held(_G.PlayerFrame), "the attic is still holding a frame it handed back")
ns.db.hideBlizzUnitFrames = true
ns.BlizzHide.Apply()
check(not _G.PlayerFrame:IsVisible() and not _G.TargetFrame:IsVisible(),
	"the switch went back on and Blizzard's frames stayed on the screen")

----------------------------------------------------------------------
-- The chain, measured between the blocks rather than inside them
--
-- Every measurement below is taken in screen units and divided by what one
-- screen pixel costs there, because that is the space a setting is written
-- in. The shipped corners leave the two frames on one line, so the level is
-- driven to a number that is not zero before anything about it is believed.
----------------------------------------------------------------------

do
	local Region = H.Region

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
		return ns.UI.Pixel(playerButton) * playerButton:GetEffectiveScale()
	end

	local function apart(a, aEdge, b, bEdge)
		return (edge(a, aEdge) - edge(b, bEdge)) / pixel()
	end

	local function axis()
		return (edge(targetButton, "GetLeft") + edge(playerButton, "GetRight")) / 2
	end

	-- Three UI scales. The offset written on the target anchor is in the
	-- grid's units, which do not move with the UI scale, but the middle of the
	-- screen is measured in the client's and a link that mixed the two is
	-- exact at one scale and out by the ratio everywhere else.
	--
	-- Target of target is measured on the same sweep and for the same reason.
	local shipped = _G.UIParent:GetScale()
	for _, scale in ipairs({ 0.65, 1, 0.5 }) do
		_G.UIParent:SetScale(scale)
		fire("UI_SCALE_CHANGED")
		-- The mirror, stated as the thing you can see: the two facing edges
		-- sit the same distance either side of the middle of the screen, so
		-- their midpoint is the middle of the screen.
		check(math.abs(axis() - middle()) / pixel() < 1e-6,
			("at ui scale %.2f the mirror line sits %.2f pixels off the middle of"
				.. " the screen"):format(scale, (axis() - middle()) / pixel()))
		local drop = apart(playerButton, "GetTop", targetButton, "GetTop")
		check(math.abs(drop) < 1e-6,
			("at ui scale %.2f level 0 left the target block %.2f pixels off the"
				.. " player block's top edge"):format(scale, drop))
		local under = apart(targetButton, "GetBottom", totButton, "GetTop")
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
	local dropped = apart(playerButton, "GetTop", targetButton, "GetTop")
	check(math.abs(dropped - 24) < 1e-6,
		("level 24 put the target block %.2f pixels below the player block"):format(dropped))
	ns.db.skinLevel = ns.DefaultFor("skinLevel")
	ns.FrameSkin.Relayout()

	-- A drag, read back off the screen.
	--
	-- Fired at the anchor the way 51-placing.lua fires one: the drag scripts
	-- are the addon's and the move between them is the client's, so the two
	-- numbers have to come back out of measured edges rather than out of
	-- inverting the offset this addon last wrote. The frames are unlocked
	-- first, because a locked frame refuses the drag, and the button under the
	-- anchor gives the mouse up while they are, so the anchor can be grabbed.
	local wasLocked = ns.db.locked
	ns.db.locked = false
	ns.FrameSkin.Lock()
	check(playerAnchor:IsDraggable() and targetAnchor:IsDraggable(),
		"the frames are unlocked and one of the two anchors cannot be dragged")
	check(not playerButton:IsMouseEnabled(),
		"the frames are unlocked and the player button still takes the mouse over its anchor")

	-- A drag, delivered to a point on the screen and travelling the distance
	-- that lands the anchor's top left corner where the caller asked for it.
	--
	-- It used to call the two drag scripts by name and put the frame where it
	-- wanted with SetPoint in between, which asserts the addon's OnDragStop and
	-- nothing else: not that the anchor is where the pointer can reach it, not
	-- that it is registered for a drag, and not that the client would move it.
	-- The button that has to give the mouse up for this to work is checked
	-- directly above and had no bearing on the old drag at all.
	local function drop(anchor, x, y)
		local own = anchor:GetEffectiveScale()
		local grabX, grabY = H.mouse.Point(anchor)
		local took, dragging = H.mouse.Grab(grabX, grabY, "LeftButton")
		check(took == anchor,
			("a drag aimed at an anchor landed on %s"):format(
				took and (took:GetName() or took:GetObjectType()) or "nothing"))
		check(dragging, "the anchor under the pointer took no left drag")
		H.mouse.Drop(grabX + (x - anchor:GetLeft()) * own,
			grabY + (y - anchor:GetTop()) * own)
	end

	-- The sideways part of the drag is deliberate: the drop has to be pulled
	-- off the mirror line for the re-anchor below to prove it goes back.
	local pullAside, wantLevel = 77, 33
	local px, scale = pixel(), targetAnchor:GetEffectiveScale()
	drop(targetAnchor,
		(edge(playerButton, "GetRight") + pullAside * px) / scale,
		(edge(playerButton, "GetTop") - wantLevel * px) / scale)
	check(ns.db.skinLevel == wantLevel,
		("the drag landed 33 down and was read back as %s")
			:format(tostring(ns.db.skinLevel)))
	local landed = targetAnchor.points and targetAnchor.points[1]
	check(landed ~= nil and landed[2] == playerButton,
		"the drop stored its numbers and never re-anchored the target on the player block")
	-- The horizontal half of a drop is not kept, and that is the design rather
	-- than a loss: the target's edge is the player's reflected, so the only
	-- place it can land is opposite wherever the player is.
	check(math.abs(axis() - middle()) / pixel() < 1e-6,
		("the re-anchor after the drop put the mirror line %.2f pixels off the"
			.. " middle of the screen"):format((axis() - middle()) / pixel()))
	ns.db.skinLevel = ns.DefaultFor("skinLevel")
	ns.FrameSkin.Relayout()

	-- Off, the target sits on a corner of its own, and a drag writes that
	-- corner rather than the level.
	ns.db.skinLink = false
	ns.FrameSkin.Apply()
	local own = targetAnchor.points and targetAnchor.points[1]
	local corner = ns.DefaultFor("skinTargetPoint")
	check(own ~= nil and own[2] == _G.UIParent and own[1] == corner[1]
		and own[4] == corner[4] and own[5] == corner[5],
		"the link came off and the target did not go to its own corner")
	-- The corner written down is the frame's own, not one the test picked.
	-- StartMoving keeps the anchor a frame already has and moves its offsets, so
	-- a target sitting on the TOPRIGHT it ships on is still on TOPRIGHT when you
	-- let go. The old drag here set TOPLEFT by hand in the middle of the gesture
	-- and then asserted TOPLEFT came back, which is the test reading its own
	-- write.
	drop(targetAnchor, 500, -120)
	local stored = ns.db.skinTargetPoint
	local at, _, against, x, y = targetAnchor:GetPoint()
	check(stored[1] == at and stored[3] == against
			and stored[4] == ns.UI.Whole(x) and stored[5] == ns.UI.Whole(y),
		("an unlinked drag wrote %s at %s, %s and the frame sits on %s at %s, %s")
			:format(tostring(stored[1]), tostring(stored[4]), tostring(stored[5]),
				tostring(at), tostring(x), tostring(y)))
	check(math.abs(targetAnchor:GetLeft() - 500) < 1e-6
			and math.abs(targetAnchor:GetTop() + 120) < 1e-6,
		("the target was dropped at 500, -120 and landed at %.2f, %.2f")
			:format(targetAnchor:GetLeft(), targetAnchor:GetTop()))
	check(ns.db.skinLevel == ns.DefaultFor("skinLevel"),
		"an unlinked drag of the target moved the level")
	ns.db.skinTargetPoint = ns.DefaultCopy("skinTargetPoint")

	-- The player's corner is always its own, and while the link is on the
	-- target follows: the mirror line is the middle of the screen wherever
	-- the player was dropped.
	ns.db.skinLink = true
	ns.FrameSkin.Apply()
	drop(playerAnchor, 300, -200)
	-- Read back off the frame rather than typed, the way the target's drag is
	-- above. A drag keeps the corner the frame is already anchored by, and the
	-- corner it ships anchored by is Core\Shipped.lua's business: what this
	-- line is about is that the drop was written down.
	local mine = ns.db.skinPlayerPoint
	local mineAt, _, _, mineX, mineY = playerAnchor:GetPoint()
	check(mine[1] == mineAt
			and mine[4] == ns.UI.Whole(mineX) and mine[5] == ns.UI.Whole(mineY),
		("a drag of the player wrote %s at %s, %s and the frame sits on %s at %s, %s")
			:format(tostring(mine[1]), tostring(mine[4]), tostring(mine[5]),
				tostring(mineAt), tostring(mineX), tostring(mineY)))
	check(math.abs(playerAnchor:GetLeft() - 300) < 1e-6
			and math.abs(playerAnchor:GetTop() + 200) < 1e-6,
		("the player was dropped at 300, -200 and landed at %.2f, %.2f")
			:format(playerAnchor:GetLeft(), playerAnchor:GetTop()))
	check(math.abs(axis() - middle()) / pixel() < 1e-6,
		("the player moved and the mirror line sits %.2f pixels off the middle of"
			.. " the screen"):format((axis() - middle()) / pixel()))
	ns.db.skinPlayerPoint = ns.DefaultCopy("skinPlayerPoint")
	ns.FrameSkin.Relayout()

	ns.db.locked = wasLocked
	ns.FrameSkin.Lock()
	check(playerButton:IsMouseEnabled() == (wasLocked and true or false),
		"locking the frames again did not hand the mouse back to the player button")

	-- On again in lockdown. Anchoring the frame a secure button hangs in is
	-- what combat forbids, so the switch has to write nothing at all and
	-- finish itself at PLAYER_REGEN_ENABLED.
	ns.db.skinLink = false
	ns.FrameSkin.Apply()
	local realLockdown, realProtected = _G.InCombatLockdown, Region.IsProtected
	local blocked, inCombat = {}, false
	_G.InCombatLockdown = function() return inCombat end
	function Region:IsProtected() return blocked[self] == true end

	blocked[targetButton], inCombat = true, true
	ns.db.skinLink = true
	ns.FrameSkin.Apply()
	local held = targetAnchor.points and targetAnchor.points[1]
	check(held ~= nil and held[2] == _G.UIParent,
		"the link was written under a protected frame in combat")

	inCombat = false
	fire("PLAYER_REGEN_ENABLED")
	_G.InCombatLockdown, Region.IsProtected = realLockdown, realProtected
	local caught = targetAnchor.points and targetAnchor.points[1]
	check(caught ~= nil and caught[2] == playerButton,
		"the link never caught up when combat dropped")

	-- And the third link after the first two have been off and on again, which
	-- is the pass that would leave target of target hanging off a corner the
	-- target block no longer has.
	local relinked = apart(targetButton, "GetBottom", totButton, "GetTop")
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
		.. " 1 and 0.5, 3 px under the target block; a drag reads back %d down,"
		.. " an unlinked one writes a corner"):format(wantLevel))
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
-- fast pass alone.
----------------------------------------------------------------------

do
	local row = _G.WarriorKitTargetDebuffs
	local function settle()
		skinTicker:Beat(5)
	end
	local function pass()
		skinTicker:Beat(0.25)
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

	print("told   a debuff event draws on the next pass and a pass with nothing"
		.. " marked draws nothing")
end
