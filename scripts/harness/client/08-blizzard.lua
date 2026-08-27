-- Blizzard's own frames, stood up between the TOC and login
--
-- The three unit frames and the minimap, shaped the way 2.5.6 shapes them.
-- They belong to the client rather than to the addon, but they are built
-- after the TOC has loaded and before PLAYER_LOGIN fires, because that is the
-- window the skin and the minimap shape resolve in. The runner calls this
-- there and nowhere else.

local H = ...
local region, child = H.region, H.child

-- The three Blizzard unit frames, shaped the way 2.5.6 shapes them: a portrait
-- and two status bars hung off the frame under the four parent keys the skin
-- resolves through, the ring and the state icons on a texture frame one level
-- down, and target of target parented to the target frame, which is the nesting
-- the skin's skip set exists for. Standing them up before PLAYER_LOGIN because
-- that is when Skin.lua resolves and styles them.
local PORTRAIT_X, PORTRAIT_Y = 7, -11

local function unitFrame(name, w, h, parent, badges)
	local frame = child("frame", parent or _G.UIParent, name)
	frame:SetSize(w, h)
	frame:CreateTexture(name .. "Background")
	frame.portrait = frame:CreateTexture(name .. "Portrait")
	frame.portrait:SetTexture("Interface\\CharacterFrame\\TempPortrait")
	-- Anchored the way Blizzard anchors a portrait, in the frame's own units,
	-- which is the number the skin has to convert before it can hang the block
	-- on it. Deliberately not a whole pixel at this scale.
	frame.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", PORTRAIT_X, PORTRAIT_Y)
	frame.portrait:SetSize(60, 60)

	for _, key in ipairs({ "healthbar", "manabar" }) do
		local bar = child("statusbar", frame, name .. (key == "healthbar" and "HealthBar" or "ManaBar"))
		bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		bar:SetSize(119, 12)
		bar.TextString = bar:CreateFontString()
		frame[key] = bar
	end

	local art = child("frame", frame, name .. "TextureFrame")
	art:CreateTexture(name .. "Ring")
	art:CreateTexture(name .. "Flash")
	frame.name = art:CreateFontString()
	for _, badge in ipairs(badges or {}) do
		art:CreateTexture(badge)
	end
	return frame
end

-- Both frames carry a point of their own, the way the client hands them one
-- and the way Edit Mode writes one back. That is what the frame link has to
-- record before it moves the target and hand back when it is turned off, and a
-- frame standing here with no anchor at all would make the restore untestable:
-- there would be nothing to give back and no way to tell that from a restore
-- that did nothing.
local playerFrame = unitFrame("PlayerFrame", 232, 100, nil,
	{ "PlayerRestIcon", "PlayerAttackIcon", "PlayerPVPIcon" })
playerFrame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", -19, -4)
child("fontstring", playerFrame, "PlayerLevelText")
-- The combat feedback number, which is a font string and so is invisible to a
-- walk over textures. Blizzard draws it centred on a portrait twice the size
-- of the block, so left alone it lands across the level and the power gauge.
child("fontstring", playerFrame, "PlayerHitIndicator")
local targetFrame = unitFrame("TargetFrame", 232, 100, nil,
	{ "TargetFrameRaidTargetIcon", "TargetFramePVPIcon" })
-- Deliberately not the player's own Y. Two frames Edit Mode happened to leave
-- on one line would make "level 0 puts both block tops on one Y" true before
-- anything linked them, and an assertion that passes against the unlinked
-- layout is not an assertion.
targetFrame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 250, -50)
child("fontstring", targetFrame, "TargetLevelText")
child("fontstring", targetFrame, "TargetFrameHitIndicator")
local totFrame = unitFrame("TargetFrameToT", 120, 50, targetFrame, {})
-- Anchored the way the client anchors it: against a target frame 100 units
-- tall. That offset is the whole reason the skin has to place this frame
-- itself once the target frame is the height of the block instead.
totFrame:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -35, -70)

-- The head of each of the target's two aura rows. Nothing else about them is
-- stood up here, and where they are anchored has stopped mattering: the addon
-- hides this row and draws its own, so what the harness has to be able to see
-- is a button under each of those two names that starts out shown.
--
-- This used to carry a lift of 32 and a function that re-anchored both heads,
-- because the skin measured that number off the anchor and fitted the target
-- frame to the block plus it. The addon deletes that machinery in the same
-- change that deletes this. What replaced it is in 14-aura-row.lua, which
-- builds TargetFrameDebuff2 through 4 partway through its own run, the way the
-- client builds them: on demand, in order, and only once a target has carried
-- that many.
for _, name in ipairs({ "TargetFrameBuff1", "TargetFrameDebuff1" }) do
	child("button", targetFrame, name)
end

-- The head of each of your own two rows, and the client's own weapon enchant.
-- None of the three is a child of PlayerFrame on any client: the client hangs
-- your buffs off BuffFrame in the top corner of the screen and the enchants off
-- TemporaryEnchantFrame beside them, which is why the addon leaves both frames
-- alone and hides the buttons. What the harness needs from them is the same
-- thing it needs from the two above, a button under each name that starts out
-- shown, so the sweep has something to take off the screen.
--
-- TempEnchant1 is here because the addon draws the sharpening stone itself now,
-- at the head of your buff row. While it did not, the client's was the only
-- reading of the stone on the screen and was deliberately left up; the moment
-- the row drew one, leaving the client's up was a second copy of the same
-- number in the corner.
--
-- The two frames they hang off are stood up as well, and the parenting is the
-- client's: your buffs and your debuffs are both children of BuffFrame, and
-- the enchant is not, which is why `/wk auras off` has two frames to take down
-- and not one.
local buffFrame = child("frame", _G.UIParent, "BuffFrame")
local enchantFrame = child("frame", _G.UIParent, "TemporaryEnchantFrame")
for _, name in ipairs({ "BuffButton1", "DebuffButton1" }) do
	child("button", buffFrame, name)
end
child("button", enchantFrame, "TempEnchant1")

-- What each unit frame was built as, taken before PLAYER_LOGIN and so before
-- the skin has fitted any of them. The fit is only reversible if these are the
-- numbers that come back.
local BUILT = {}
for _, frame in ipairs({ playerFrame, targetFrame, totFrame }) do
	BUILT[frame.name] = { frame:GetWidth(), frame:GetHeight(),
		frame.points and frame.points[1] }
end

-- The minimap, shaped the way TBC shapes it: a frame inside a cluster, a ring
-- of art round it, four of Blizzard's own buttons anchored to points on that
-- ring, and three addon buttons of the kind that go on it uninvited.
--
-- Stood up before PLAYER_LOGIN because that is when Minimap/Shape.lua reads
-- the width the client drew it at, and the whole of turning the square off
-- again is handing that number back.
--
-- The zoom trio is here because taking the two zoom buttons off the ring means
-- the wheel has to do their work, and a stub without them would let a square
-- that cannot be zoomed pass.
do
	local map = region("frame", _G.UIParent, "Minimap")
	map:SetSize(140, 140)
	map.zoom, map.zoomLevels = 2, 5
	map.GetZoom = function(self) return self.zoom end
	map.GetZoomLevels = function(self) return self.zoomLevels end
	map.SetZoom = function(self, level) self.zoom = level end
	map.SetMaskTexture = function(self, path) self.mask = path end
	map.mask = "Textures\\MinimapMask"

	local cluster = region("frame", _G.UIParent, "MinimapCluster")
	cluster:SetSize(192, 192)

	for _, name in ipairs({ "MinimapBorder", "MinimapBorderTop", "MinimapNorthTag",
		"MinimapZoomIn", "MinimapZoomOut", "MiniMapWorldMapButton" }) do
		child("texture", map, name)
	end

	-- Blizzard's own, each anchored to a point on the arc the way the client
	-- anchors them. Those offsets are what the square has no room for and what
	-- has to come back when it goes off.
	for _, entry in ipairs({
		{ "MiniMapTracking", "TOPLEFT", 8, -3 },
		{ "MiniMapMailFrame", "TOPRIGHT", -3, -30 },
		{ "MiniMapBattlefieldFrame", "BOTTOMRIGHT", -8, 25 },
		{ "GameTimeFrame", "TOPRIGHT", 12, -8 },
	}) do
		local button = child("button", map, entry[1])
		button:SetPoint(entry[2], map, entry[2], entry[3], entry[4])
	end

	-- Three addon buttons, of the two shapes that actually turn up. LibDBIcon
	-- names one way and an addon rolling its own names the other, and both are
	-- children of the minimap with a point on the arc.
	for _, name in ipairs({ "LibDBIcon10_Questie", "LibDBIcon10_Details",
		"TitanMinimapButton" }) do
		local button = child("button", map, name)
		button:SetSize(31, 31)
		button:SetPoint("CENTER", map, "CENTER", 60, 20)
	end

	-- A child with no name at all, which is what a texture holder or an
	-- anonymous frame on the minimap looks like. It must never be collected:
	-- the corral is keyed by name and an unnamed one could not be released.
	child("frame", map)

	-- And the reason the corral has a shape test at all. The minimap is not
	-- only where addons hang their button, it is also where every addon that
	-- draws a pin hangs the pin, and Questie parents several hundred to it.
	-- The first client this met collected 555 of them and left Questie unable
	-- to move its own map.
	--
	-- Modelled the way a pool actually looks: one name with a counter on the
	-- end, and drawn at a pin's size rather than a button's. Sixty is enough to
	-- fail every count in the block below if the filter ever comes off.
	for index = 1, 60 do
		local pin = child("button", map, "QuestieFrame" .. index)
		pin:SetSize(16, 16)
		pin:SetPoint("CENTER", map, "CENTER", index, index)
	end

	-- A pin pool drawn at a button's size, which the size window cannot catch
	-- and only the family rule can. This is the assertion that says the family
	-- rule is doing work rather than riding along behind the size test.
	for index = 1, 12 do
		local pin = child("button", map, "GatherMatePin" .. index)
		pin:SetSize(31, 31)
		pin:SetPoint("CENTER", map, "CENTER", -index, index)
	end

	-- A frame rather than a button, at a button's size and with a name of its
	-- own. Pins are often frames and buttons almost never are.
	local pinFrame = child("frame", map, "SomeAddonMapNote")
	pinFrame:SetSize(31, 31)
	pinFrame:SetPoint("CENTER", map, "CENTER", 40, -40)
end

-- The client's own menu, shaped the way both clients shape it: a column of
-- buttons, each hung off the bottom of the one above it, and a frame tall
-- enough to hold exactly that column.
--
-- Stood up here rather than in 02-text.lua because it is Blizzard's frame and
-- because Core/Menu.lua reads it at PLAYER_LOGIN, which is the window this file
-- exists to fill.
--
-- One of the buttons is hidden, which is the case the chain walk in that file
-- has to survive: the button below a hidden one still hangs off it, so a walk
-- that only looks at shown buttons loses track of the button above and finds
-- two feet where there is one. Blizzard hides buttons in this menu for real.
local MENU_BUTTON_W, MENU_BUTTON_H, MENU_GAP = 144, 21, 1

do
	local menu = child("frame", _G.UIParent, "GameMenuFrame")
	local buttons = {}
	local names = { "GameMenuButtonOptions", "GameMenuButtonKeybindings",
		"GameMenuButtonMacros", "GameMenuButtonAddons", "GameMenuButtonLogout",
		"GameMenuButtonContinue" }

	local above
	for index, name in ipairs(names) do
		local entry = child("button", menu, name)
		entry:SetSize(MENU_BUTTON_W, MENU_BUTTON_H)
		entry:SetPoint("TOP", above or menu, above and "BOTTOM" or "TOP", 0, -MENU_GAP)
		above = entry
		if name == "GameMenuButtonMacros" then
			entry:Hide()
		end
		buttons[index] = entry
	end

	menu:SetSize(MENU_BUTTON_W + 32,
		#names * (MENU_BUTTON_H + MENU_GAP) + MENU_GAP)
	H.menu, H.menuButtons = menu, buttons
end

H.MENU_BUTTON_H, H.MENU_GAP = MENU_BUTTON_H, MENU_GAP

-- Taking a frame off the client's panel stack. Real rather than the no-op the
-- metatable would give it, because the game menu button closes the menu with
-- this and a stub that swallowed the call could not tell a button that closes
-- the menu from one that leaves it open over the panel it just opened.
function _G.HideUIPanel(frame)
	if frame then
		frame:Hide()
	end
end

H.playerFrame, H.targetFrame, H.totFrame = playerFrame, targetFrame, totFrame
H.BUILT = BUILT
