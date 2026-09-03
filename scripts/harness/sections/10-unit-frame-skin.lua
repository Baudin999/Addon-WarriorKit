-- The three unit frames this addon draws
--
-- The same questions as the bars, against the player, the target and target
-- of target. All three are our own frames now, so what used to be asserted as
-- a boundary between our grid and Blizzard's scale is asserted as a rectangle:
-- a secure button on the grid, whole pixels everywhere, a portrait asked for,
-- two bars painted the unit's colour, and a tick that neither allocates nor
-- writes what is already there.
--
-- What the button carries is asserted before what it draws. A block that is
-- placed, measured and painted and cannot be clicked is Blizzard's frame with
-- the art taken off, and the two attributes and the click registration are the
-- whole of what makes it a unit frame rather than a picture of one.
--
-- What this cannot prove is that the game agrees. The secure button's click,
-- the menu behind the right button and the unit watch are all the client's,
-- and the fixture models each from the contract.

local H = ...
local PLAYER_CLASS, guids = H.PLAYER_CLASS, H.guids
local ns, check, fire = H.ns, H.check, H.fire
local own, inCombat, pvpUnits = H.own, H.inCombat, H.pvpUnits

-- Units for the three frames, added now rather than at login so the enemy bar
-- figures above are measured against two mobs and not three. The event is
-- what the client fires, and it is what puts the target's button up.
guids.player, guids.target, guids.targettarget = "Player-1", "Creature-9", "Creature-8"
fire("PLAYER_TARGET_CHANGED")
-- Apply rather than a tick, because that is what a settings change does and it
-- is the path that has to leave a frame fully painted: a fifth of a second of
-- a white gauge reads as a bug.
ns.FrameSkin.Apply()

local blocks = {
	{ "player", _G.WarriorKitPlayerFrame, _G.WarriorKitPlayerButton, "player" },
	{ "target", _G.WarriorKitTargetFrame, _G.WarriorKitTargetButton, "target" },
	{ "tot", _G.WarriorKitTargetOfTargetFrame, _G.WarriorKitTargetOfTargetButton, "targettarget" },
}

----------------------------------------------------------------------
-- What each button is
----------------------------------------------------------------------

for _, block in ipairs(blocks) do
	local key, anchor, button, unit = block[1], block[2], block[3], block[4]
	check(anchor ~= nil, key .. ": no anchor frame was built")
	check(button ~= nil, key .. ": no secure button was built")
	if anchor and button then
		check(button.parent == anchor, key .. ": the button is not a child of its anchor")
		check(button.template == "SecureUnitButtonTemplate",
			key .. ": the button was made from " .. tostring(button.template)
				.. " and a unit frame that cannot target is a picture")
		check(button:GetAttribute("unit") == unit,
			("%s: the button targets %s and belongs to %s")
				:format(key, tostring(button:GetAttribute("unit")), unit))
		check(button:GetAttribute("*type1") == "target",
			key .. ": the left button does not target")
		check(button:GetAttribute("*type2") == "togglemenu",
			key .. ": the right button does not open the menu")
		local clicks = button:GetRegisteredClicks()
		check(clicks ~= nil and clicks.AnyUp == true,
			key .. ": the button registered for no clicks, so nothing reaches the attributes")
		check(button.scripts.OnEnter ~= nil and button.scripts.OnLeave ~= nil,
			key .. ": hovering the button shows no tooltip")
	end
end

----------------------------------------------------------------------
-- Blizzard's three, off the screen
--
-- Caged rather than stripped, the way every frame this addon replaces is,
-- and target of target goes with its parent.
----------------------------------------------------------------------

check(ns.db.hideBlizzUnitFrames == true, "the switch that takes Blizzard's frames down ships off")
for _, name in ipairs({ "PlayerFrame", "TargetFrame", "TargetFrameToT" }) do
	check(_G[name]:IsVisible() == false,
		("Blizzard's %s is still on the screen under ours"):format(name))
end
check(ns.Attic.Held(_G.PlayerFrame) and ns.Attic.Held(_G.TargetFrame),
	"Blizzard's player and target frames are hidden but not caged, so a Show puts them back")

----------------------------------------------------------------------
-- Up and down with the unit
--
-- Your own button stays up. The other two are handed to the client's unit
-- watch, which is the one thing that can show a secure frame in a fight, and
-- the fixture models the watch: the frame follows UnitExists on the event
-- that says the target moved, before any addon code runs.
----------------------------------------------------------------------

local playerButton, targetButton = _G.WarriorKitPlayerButton, _G.WarriorKitTargetButton
local totButton = _G.WarriorKitTargetOfTargetButton

check(playerButton:IsShown(), "your own button is not on the screen")
check(_G.UnitWatchRegistered(targetButton) and _G.UnitWatchRegistered(totButton),
	"the target and target of target buttons are not on the client's unit watch, so"
	.. " a target picked up in a fight draws nothing")
check(targetButton:IsShown() and totButton:IsShown(),
	"the target has a target and one of the two buttons is not on the screen")

guids.targettarget = nil
fire("PLAYER_TARGET_CHANGED")
check(targetButton:IsShown() and not totButton:IsShown(),
	"the target has nothing targeted and target of target is still on the screen")
guids.target = nil
fire("PLAYER_TARGET_CHANGED")
check(not targetButton:IsShown(),
	"there is no target and the target button is still on the screen")
guids.target, guids.targettarget = "Creature-9", "Creature-8"
fire("PLAYER_TARGET_CHANGED")
check(targetButton:IsShown() and totButton:IsShown(),
	"a target picked up again did not put both buttons back")
ns.FrameSkin.Apply()

----------------------------------------------------------------------
-- The palette, restated rather than reached for
--
-- UnitIsPlayer is true for the player alone, so the player wears their own
-- class colour and the other two fall to the hostile one on a reaction of 2.
-- This half is an identity check against the palette; the contrast section
-- below is the half that is independent.
----------------------------------------------------------------------

local TRACK, EDGE_DIM = ns.Unit.Color.track, 0.60
local HOSTILE = ns.Unit.Color.reaction.hostile
local TINT = {
	player = ns.Unit.Color.Class(PLAYER_CLASS),
	target = HOSTILE,
	tot = HOSTILE,
}
assert(TINT.player, PLAYER_CLASS .. " has no colour in the palette")

-- The two textures under a bar's fill, found by what they are rather than by
-- reaching into the module's tables. The track fills its bar, so it is the one
-- with SetAllPoints on it; the slice is pinned to the fill texture instead,
-- which is what makes it start exactly where the bar stops.
local function barTexture(bar, filling)
	for _, region in ipairs(bar.regions) do
		if region.kind == "texture" and region ~= bar.fill
			and (region.allPoints ~= nil) == filling then
			return region
		end
	end
end

local function skinTrack(bar) return barTexture(bar, true) end
local function skinSlice(bar) return barTexture(bar, false) end

local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4 }
local function depth(texture)
	if not texture or not LAYERS[texture.layer] then
		return nil
	end
	return LAYERS[texture.layer] * 16 + (texture.sublevel or 0)
end

local function near(a, b) return a and math.abs(a - b) < 1e-6 end
local function paints(region, r, g, b, a)
	return region and near(region.r, r) and near(region.g, g)
		and near(region.b, b) and near(region.a, a)
end

for _, block in ipairs(blocks) do
	local key, anchor, button = block[1], block[2], block[3]
	local entry = ns.FrameSkin.Entry(key)
	if anchor and button and entry then
		-- On the grid, which is the whole of what makes every number below a
		-- whole pixel. The anchor is adopted and the button inherits it.
		check(anchor.ignoreScale == true, key .. ": the anchor is not on the grid")
		local px = ns.UI.Pixel(button)
		check(math.abs(px - 1) < 1e-9,
			("%s: the block is not on the grid, one pixel is %.4f units"):format(key, px))
		for _, axis in ipairs({ "GetWidth", "GetHeight" }) do
			local size = button[axis](button)
			check(size > 0 and math.abs(size - math.floor(size + 0.5)) < 1e-9,
				("%s: block %s is %.4f, not a whole pixel"):format(key, axis, size))
			check(anchor[axis](anchor) == size,
				("%s: the anchor is %.0f %s and the button %.0f, so what you drag is"
					.. " not what you see"):format(key, anchor[axis](anchor), axis, size))
		end
		local pin = button.points and button.points[1]
		check(pin and pin[1] == "TOPLEFT" and pin[2] == anchor and pin[3] == "TOPLEFT"
			and pin[4] == 0 and pin[5] == 0,
			key .. ": the button is not pinned to its anchor's own corner")

		-- The portrait's square. Read as an offset into the block rather than
		-- as an anchor on the mirrored corner, because ns.UI.Flow pins every
		-- frame in a tree to the root's top left corner at the offset that
		-- came out. The target's block runs backwards, so the square is the
		-- last cell of the row and sits a gauge's width in.
		local slot = entry.slot
		local square = slot and slot.points and slot.points[1]
		local inset = key == "target" and (button:GetWidth() - slot:GetWidth()) or 0
		check(square and square[1] == "TOPLEFT" and square[2] == button
			and square[3] == "TOPLEFT" and square[4] == inset and square[5] == 0,
			("%s: the square is pinned to the block at %s, %s and belongs at %d, 0")
				:format(key, tostring(square and square[4]), tostring(square and square[5]),
					inset))
		check(slot and slot:GetWidth() == slot:GetHeight() and slot:GetHeight() == button:GetHeight(),
			key .. ": the portrait's square is not the block's height squared")

		-- The two bars are laid out by Flow directly, whole pixels tall.
		local healthBar, powerBar = entry.healthBar, entry.powerBar
		check(healthBar and powerBar, key .. ": the gauges were never built")
		for name, bar in pairs({ health = healthBar, power = powerBar }) do
			local height = bar and bar:GetHeight() or 0
			check(height >= 1 and math.abs(height - math.floor(height + 0.5)) < 1e-9,
				("%s: the %s bar is %.4f pixels tall, not a whole one"):format(key, name, height))
			check(bar and bar.parent == button, key .. ": the " .. name .. " bar is not a child of the button")
		end

		-- The values, which Blizzard's bars used to carry for us. 4200 of 9000
		-- is what the fixture answers for every unit nobody has said otherwise
		-- about.
		local low, high = healthBar:GetMinMaxValues()
		check(low == 0 and high == 9000 and healthBar:GetValue() == 4200,
			("%s: the health bar reads %s to %s at %s and the unit is 4200 of 9000")
				:format(key, tostring(low), tostring(high), tostring(healthBar:GetValue())))

		-- Stacking order inside one bar. The track and the heal slice are
		-- regions of the bar and sit under its fill by draw layer, which is
		-- settled inside one frame and cannot be a disagreement between two.
		for name, bar in pairs({ health = healthBar, power = powerBar }) do
			local track = skinTrack(bar)
			check(track ~= nil and track.parent == bar,
				("%s: the spent part of the %s gauge is not a region of the bar"):format(key, name))
			local under, over = depth(track), depth(bar.fill)
			check(under and over and under < over,
				("%s: the %s track is on %s and the fill on %s, so the track draws"
					.. " over the fill"):format(key, name, tostring(track and track.layer),
						tostring(bar.fill and bar.fill.layer)))
		end
		local slice = skinSlice(healthBar)
		check(slice and slice.parent == healthBar,
			key .. ": the heal slice is not a region of the health bar")
		check(depth(skinTrack(healthBar)) < depth(slice)
			and depth(slice) < depth(healthBar.fill),
			key .. ": the heal slice is not between the spent track and the fill")

		-- What the block is actually painted. The fill is the unit's colour at
		-- full brightness, the spent part of each gauge is that colour at a
		-- fifth, and the five hairlines are it at three fifths. All three are
		-- read back, because a gauge is only as good as the colour that reaches
		-- it.
		local tint = TINT[key]
		check(near(healthBar.barR, tint[1]) and near(healthBar.barG, tint[2])
			and near(healthBar.barB, tint[3]) and near(healthBar.barA, 1),
			("%s: the health bar is painted %s,%s,%s and not the unit's %.2f,%.2f,%.2f")
				:format(key, tostring(healthBar.barR), tostring(healthBar.barG),
					tostring(healthBar.barB), tint[1], tint[2], tint[3]))
		check(paints(skinTrack(healthBar), tint[1] * TRACK, tint[2] * TRACK,
			tint[3] * TRACK, 0.9), key .. ": the spent part of the health gauge is not "
				.. "the unit's colour at ns.Unit.Color.track")
		local dimmed = 0
		for _, region in ipairs(button.regions) do
			if paints(region, tint[1] * EDGE_DIM, tint[2] * EDGE_DIM, tint[3] * EDGE_DIM, 1) then
				dimmed = dimmed + 1
			end
		end
		check(dimmed == 5, ("%s: %d of the block's five hairlines carry the unit's "
			.. "colour at three fifths, not all of them"):format(key, dimmed))

		-- The portrait: asked of the client for this unit, cropped on a texel
		-- boundary, and the client's own snapping off, the same two fixes a
		-- spell icon takes.
		local portrait = entry.portrait
		check(portrait.portraitUnit == block[4],
			("%s: the portrait was asked for %s and belongs to %s")
				:format(key, tostring(portrait.portraitUnit), block[4]))
		check(portrait.texcoord and math.abs(portrait.texcoord[1] * 64 - 10) < 1e-9,
			key .. ": the portrait crop is not on a texel boundary")
		check(portrait.snapped == false and portrait.bias == 0,
			key .. ": the portrait is still being snapped by the client")

		-- Badges land on an even count of pixels, so one centred on a corner
		-- does not put all four of its edges on a half pixel.
		for slot, badge in pairs(entry.badges) do
			local pixels = badge.width / px
			local whole = math.floor(pixels + 0.5)
			check(math.abs(pixels - whole) < 1e-6 and whole % 2 == 0,
				("%s: badge %s is %.4f pixels wide, not an even whole number")
					:format(key, slot, pixels))
		end

		-- Shared font objects, not a font per string.
		for _, text in ipairs(entry.top.regions) do
			if text.kind == "fontstring" then
				check(text.fontObject ~= nil and text.fontPath == nil,
					key .. ": a font string carries its own font instead of a shared object")
			end
		end
	end
end

----------------------------------------------------------------------
-- The badges, driven
--
-- Resting and fighting on your own square, one or the other; the flag on a
-- frame whose unit is flagged; the raid marker on the target's. Each is an
-- event the client fires and then the pass that draws it, and each is read
-- back off the texture rather than off the call.
----------------------------------------------------------------------

do
	local player, target = ns.FrameSkin.Entry("player"), ns.FrameSkin.Entry("target")
	local skinPass, skinRead = H.tick("skin"), H.tick("skinread")
	local function pass()
		skinPass:Beat(0.25)
	end

	local state = player.badges.state
	check(state ~= nil, "your own block carries no rest or combat badge")
	check(not state:IsShown(), "the state badge is up with nothing to say")

	own.resting = true
	fire("PLAYER_UPDATE_RESTING")
	pass()
	check(state:IsShown() and state.texcoord and state.texcoord[1] == 0,
		"resting did not put the rest icon on your square")

	-- A fight, through the reading behind the events rather than through
	-- PLAYER_REGEN_DISABLED, which every meter and clock in the addon also
	-- hears and would count as a fight for the rest of the run. The block is
	-- marked on that event in the game; here the once a second read is what
	-- finds the flag, and it is the same paint either way.
	own.resting = false
	inCombat.player = true
	skinRead:Beat(1)
	check(state:IsShown() and state.texcoord and state.texcoord[1] == 0.5,
		"a fight did not put the combat icon on your square")

	inCombat.player = false
	skinRead:Beat(1)
	check(not state:IsShown(), "the fight ended and the combat icon stayed up")

	local flag = player.badges.pvp
	check(flag ~= nil and not flag:IsShown(), "the pvp flag is up on an unflagged player")
	pvpUnits.player = true
	fire("UNIT_FACTION", "player")
	pass()
	check(flag:IsShown() and flag:GetTexture() == "Interface\\TargetingFrame\\UI-PVP-Alliance",
		("flagging yourself drew %s and belongs to the faction's flag"):format(tostring(flag:GetTexture())))
	pvpUnits.player = nil
	fire("UNIT_FACTION", "player")
	pass()
	check(not flag:IsShown(), "the flag dropped and the badge stayed up")

	local marker = target.badges.marker
	check(marker ~= nil and not marker:IsShown(), "the target carries a raid marker nobody set")
	check(player.badges.marker == nil, "your own block carries a raid marker badge, which Blizzard's does not")
	_G.SetRaidTarget("target", 8)
	fire("RAID_TARGET_UPDATE")
	pass()
	check(marker:IsShown() and marker.raidIcon == 8,
		("skull on the target drew icon %s"):format(tostring(marker.raidIcon)))
	_G.SetRaidTarget("target", 0)
	fire("RAID_TARGET_UPDATE")
	pass()
	check(not marker:IsShown(), "the marker came off and the badge stayed up")

	print("badges rest, combat, the flag and a raid marker each up on the event and down again")
end

-- Left for the sections below.
H.carry.blocks, H.carry.skinSlice = blocks, skinSlice
