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
-- Hidden, the way the client's own template declares it. This is the one unit
-- frame that goes up and down on its own, and a fixture that handed it over
-- already shown would let a skin that never puts it up pass every assertion
-- about it: the block would be built, measured and painted on a frame nobody
-- can see, which is exactly the bug.
totFrame:Hide()
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

-- The client's own cast bar for your target, which this addon draws on the
-- enemy bar instead. A child of the target frame, so it is the one frame in
-- UnitFrames/Blizzard.lua's list that a lockdown can refuse.
--
-- Reachable under FrameXML's own parent key as well as under the global, because
-- that is the pair UnitFrames/Blizzard.lua resolves and a fixture carrying only
-- the global could not tell a client that renamed one from a client that renamed
-- both. It is the same frame under both names, which is also worth modelling:
-- the pass takes it down twice per call and that has to be free.
local spellBar = child("statusbar", targetFrame, "TargetFrameSpellBar")
targetFrame.spellbar = spellBar

-- What the cast bar mixin does when a cast starts, which is the call that put a
-- second cast bar on the screen with the switch on. SetShown, not Show: the
-- addon can replace Show and cannot replace this.
function _G.Target_Spellbar_OnEvent()
	spellBar:SetShown(true)
	spellBar:AdjustPosition()
end

-- And what that handler goes on to do, which is the reason a caged bar cannot
-- simply be left running. AdjustPosition reads auraRows off whatever the bar's
-- parent is, the attic is a plain frame with no such field, and the compare
-- raises. The client's version lays the bar out under the target's aura rows
-- and every branch of it is downstream of this one read, so one read is the
-- whole of what the fixture has to carry.
targetFrame.auraRows = 0

function spellBar:AdjustPosition()
	local parentFrame = self:GetParent()
	if parentFrame.auraRows > 1 then
		self.offset = parentFrame.auraRows * 22
	else
		self.offset = 0
	end
end

-- And the client's own cast bar for you, which this addon draws on a bar of
-- its own under the swing timer. A child of UIParent rather than of a unit
-- frame, so unlike the one above it nothing about it is protected and no
-- lockdown can refuse to take it down.
child("statusbar", _G.UIParent, "CastingBarFrame")

-- The client's own experience bar, with the reputation bar under it. Two of the
-- five names UnitFrames/Blizzard.lua looks for, which are the two 2.5.6 carries;
-- the other three are the max level bar, the newer builds' StatusTrackingBarManager
-- and the rested tick, and a fixture standing up all five would leave the
-- "this client does not carry that name" half of the walk unreached.
--
-- Children of UIParent, because nothing about either is protected: the pair is
-- FrameXML furniture and any lockdown can take them down.
child("statusbar", _G.UIParent, "MainMenuExpBar")
child("statusbar", _G.UIParent, "ReputationWatchBar")

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

-- Blizzard's own party and raid frames, which this addon draws itself out of a
-- secure group header and takes down by name.
--
-- The party is four separate frames on both clients, which is why one switch
-- names four of them. The raid is a container and the manager that lays it out,
-- and the manager is the reason a strip was never enough: it re-shows the
-- container on its own layout pass, through SetShown, which is resolved in C and
-- never reads the Lua Show that ns.Strip replaced.
--
-- So the fixture calls SetShown rather than writing the field, because that is
-- the one call the addon cannot intercept and the whole reason Core/Attic.lua
-- exists. A fixture that wrote `shown` directly would pass against a hide that
-- only replaces Show, which is the version this one is here to fail.
for index = 1, 4 do
	child("frame", _G.UIParent, "PartyMemberFrame" .. index)
end

-- The other two names the party answers to, and on a client with raid style
-- party frames on they are the ones actually drawing it: the four above are
-- hidden by the client itself and the switch looks like it worked.
--
-- Both are made here as frames of their own rather than as a parent and its
-- child, because the addon names both and cages both, and a fixture that nested
-- them would prove nothing except that hiding a parent hides a child.
child("frame", _G.UIParent, "PartyFrame")
child("frame", _G.UIParent, "CompactPartyFrame")
local raidContainer = child("frame", _G.UIParent, "CompactRaidFrameContainer")
child("frame", _G.UIParent, "CompactRaidFrameManager")

function _G.CompactRaidFrameManager_UpdateShown()
	raidContainer:SetShown(true)
end

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

--------------------------------------------------------------------------
-- The bags
--
-- One button per bag slot, made when a section first clicks it, and the global
-- every bag button in the game routes its clicks through. Both halves are the
-- point: the slot is the button's own id and the bag is its parent's, which is
-- where the classic bags keep them and the only thing a click has to go on.
--
-- The handler is modelled rather than stubbed away because it is the seam.
-- Mail/Bags.lua takes this name over while the mail window is open, so a
-- section clicks by calling the name, exactly as the client's own template
-- does, and what answers is whichever function is on it at that moment. A stub
-- that called the addon's handler directly would prove nothing about the
-- takeover, which is the half that can be wrong.
--
-- What the client does with a bare right click is use what is in the slot, and
-- the whole reason the mail window has to stop it is what using means: at a
-- merchant it sells, with the send pane flagged as showing it attaches to the
-- client's own form, and anywhere else it eats or equips the thing.
--------------------------------------------------------------------------

do
	local bags, slots = {}, {}

	function H.bagButton(bag, slot)
		local key = bag .. ":" .. slot
		if not slots[key] then
			if not bags[bag] then
				bags[bag] = region("frame", _G.UIParent, "ContainerFrame" .. (bag + 1))
				bags[bag]:SetID(bag)
			end
			local button = child("button", bags[bag])
			button:SetID(slot)
			slots[key] = button
		end
		return slots[key]
	end

	-- What the client's own bag button template arrives wearing.
	--
	-- Dressed here rather than left to the no-op, because taking this off again
	-- is the whole of what Bags/Grid.lua does to a square before it draws one of
	-- its own, and a bare frame cannot fail that. The blue is the one you see:
	-- ButtonHilight-Square is drawn over the whole slot on every mouse crossing,
	-- and it went unnoticed for as long as the fixture handed the addon a button
	-- with nothing on it.
	--
	-- The icon and the count are fields on the frame; the plate and the widget's
	-- own glow are not, and it only answers those by getter. Both halves are here
	-- because the file that strips them has to reach them two different ways.
	--
	-- The third half is the one that reached the screen. A template also leaves
	-- an ordinary texture on the button showing and hides it again in its own
	-- OnLeave, and the addon takes OnEnter and OnLeave for its tooltip, so
	-- nothing puts it away and every square in the window wears it. It is
	-- reachable neither by field nor by getter, only by walking the button's own
	-- regions, which is the walk a fixture with two named halves could not ask
	-- for.
	--
	-- This is the outermost wrapper of CreateFrame in the harness, because the
	-- runner loads this file after every file under client/ and before the addon
	-- has built anything. It delegates rather than replaces, so the secure half
	-- 09-group and the tooltip half 11-tooltip installed still answer.
	local ITEM_BUTTON = "ContainerFrameItemButtonTemplate"

	local made = _G.CreateFrame
	_G.CreateFrame = function(kind, name, parent, template)
		local frame = made(kind, name, parent, template)
		if template == ITEM_BUTTON then
			frame.icon = child("texture", frame, nil)
			frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			frame.Count = child("fontstring", frame, nil)
			frame:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
			frame:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
			local glow = child("texture", frame, nil)
			glow:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
			glow:Show()
			-- What ContainerFrameItemButton_OnLoad registers and what the
			-- template's OnClick does: both handlers are reached by name at
			-- click time, which is the seam Mail/Bags.lua once wrote through.
			-- A square that is not registered for the right button never
			-- reaches this, exactly as on the client, and that is the whole
			-- of how the mail window takes a right click without touching
			-- a handler.
			frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			frame:SetScript("OnClick", function(self, which)
				if _G.IsModifiedClick() then
					_G.ContainerFrameItemButton_OnModifiedClick(self, which)
				else
					_G.ContainerFrameItemButton_OnClick(self, which)
				end
			end)
		end
		return frame
	end

	function _G.ContainerFrameItemButton_OnClick(button, which)
		if which ~= "RightButton" then
			return
		end
		_G.UseContainerItem(button:GetParent():GetID(), button:GetID())
	end
	-- The handler as the client shipped it, so a section can say the global
	-- was never written. Written back or not, a global an addon assigns is a
	-- tainted global, and a tainted handler is a bag the client will not use
	-- a scroll from.
	H.bagClick = _G.ContainerFrameItemButton_OnClick

	-- A modified click is a stack split or a dress-up on the client, neither of
	-- which this fixture models. Counted, because the claim a section makes is
	-- that a shift click reached the client and not what the client then did.
	local modified = 0
	function _G.ContainerFrameItemButton_OnModifiedClick()
		modified = modified + 1
	end
	function H.modifiedBagClicks()
		return modified
	end
end

--------------------------------------------------------------------------
-- The nine calls a bag is opened and shut through
--
-- The client never shows a container frame except through one of these, which
-- is why Bags/Blizzard.lua takes all nine rather than the toggle alone. Three
-- of them are yours to press: B, a bag button on the bar, and the binding for
-- all of them. The other six are the client calling on your behalf, and
-- `OpenAllBags` is the one that matters, because it is what a merchant and a
-- bank do.
--
-- Modelled rather than stubbed away because it is the seam. What the addon
-- swaps in has to be reachable by name at call time, exactly as the client's
-- own keybinding reaches it, so a section presses B by calling `ToggleBackpack`
-- and what answers is whichever function is on the name at that moment. A stub
-- that called the addon's window directly would prove nothing about the
-- takeover, which is the half that can be wrong.
--
-- What the client's own version does is counted rather than drawn. A count
-- going up while the addon claims to be holding the name is the failure this
-- exists to catch: the client's bags opening beside the addon's window.
--------------------------------------------------------------------------

do
	local opened, closed = 0, 0

	local function theirs(which)
		return function()
			if which then
				opened = opened + 1
			else
				closed = closed + 1
			end
		end
	end

	for _, name in ipairs({ "ToggleBackpack", "ToggleAllBags", "ToggleBag",
		"OpenAllBags", "OpenBackpack", "OpenBag" }) do
		_G[name] = theirs(true)
	end
	for _, name in ipairs({ "CloseAllBags", "CloseBackpack", "CloseBag" }) do
		_G[name] = theirs(false)
	end

	-- How many times the client's own bags were asked to open and to shut since
	-- the last reading. Read by 55-bags.lua, which presses every one of the nine
	-- and expects both to stay where they were.
	function H.bagCalls()
		return opened, closed
	end
end

--------------------------------------------------------------------------
-- The client's character sheet
--
-- One window with five pages hung off it as children, which is the nesting the
-- cage depends on: Character/Blizzard.lua names all six, and the five going
-- down with the parent whether or not the client carries them under those
-- names is the claim the section makes.
--
-- ToggleCharacter is the C key. It is a plain global here because it is a plain
-- global on both of the clients this addon runs on, and the swap that takes it
-- is the second global function swap in the addon. The stub's own version
-- records the page it was asked for and shows the window, so a section can tell
-- the client's key from the addon's by which of the two moved.
--------------------------------------------------------------------------

do
	local sheet = region("frame", _G.UIParent, "CharacterFrame")
	sheet:SetSize(384, 512)
	for _, page in ipairs({ "PaperDollFrame", "SkillFrame", "ReputationFrame",
		"PetPaperDollFrame", "HonorFrame" }) do
		child("frame", sheet, page)
	end

	H.characterKey = { pages = {} }
	function _G.ToggleCharacter(page)
		H.characterKey.pages[#H.characterKey.pages + 1] = page
		sheet:Show()
	end
end
