-- The button in the client's own menu
--
-- Core/Menu.lua puts one button in Blizzard's game menu, and every hard part of
-- that is arithmetic on a frame the addon does not own. None of it is visible
-- from the source, because the source names no Blizzard button: it reads the
-- anchor chain the menu is already laid out with and works out the foot of it.
-- So this is the only place that can say the answer it works out is the right
-- one.
--
-- Four things, and each is a way the button has actually gone wrong in an addon
-- that did this by hand.
--
-- It lands above the last button rather than on top of it, which means our
-- button takes the foot's anchor and the foot takes the same anchor off ours.
-- Two buttons sharing one anchor is the failure everybody ships first.
--
-- The menu grows by exactly what we added. A menu that did not grow has its
-- last button hanging through the bottom edge.
--
-- Attaching twice does nothing the second time. The real hook is the menu's
-- OnShow, so this runs every time somebody presses Escape, and a version that
-- grew the frame each time reaches the top of the screen inside a session.
--
-- Attaching again after the client has relaid its own column puts the button
-- back. That is the whole reason the work is on OnShow rather than done once at
-- login, and it is the case a login-only version passes here and fails in game.
--
-- The stub's column has a hidden button in the middle of it on purpose, which
-- is what Blizzard does. A walk that only looked at shown buttons would lose
-- track of the button above the hidden one, find two feet and refuse, so every
-- assertion below would fail rather than being quietly weaker.

local H = ...
local ns, check = H.ns, H.check

local menu, buttons = H.menu, H.menuButtons
local Menu = ns.GameMenu
local button = _G.WarriorKitGameMenuButton

local logout, continue = buttons[#buttons - 1], buttons[#buttons]
local STEP = H.MENU_BUTTON_H + H.MENU_GAP

check(button ~= nil, "no button was put in the game menu")
check(Menu ~= nil, "Core/Menu.lua left nothing on ns")

-- What the column measured before the addon reached it, worked back out of the
-- stub's own numbers rather than read off the frame, which the addon has
-- already grown by the time any section runs.
local BARE = #buttons * STEP + H.MENU_GAP

local function anchored(frame)
	local point, relative, relativePoint, x, y = frame:GetPoint(1)
	return ("%s|%s|%s|%s|%s"):format(tostring(point), tostring(relative and relative.name),
		tostring(relativePoint), tostring(x), tostring(y))
end

if button then
	check(button.parent == menu, "the button is not a child of the game menu")
	check(button:GetWidth() == continue:GetWidth()
		and button:GetHeight() == continue:GetHeight(),
		("the button is %g x %g and the menu's own are %g x %g")
			:format(button:GetWidth(), button:GetHeight(),
				continue:GetWidth(), continue:GetHeight()))

	local _, relative = button:GetPoint(1)
	check(relative == logout,
		("the button hangs off %s, not the button above the foot")
			:format(tostring(relative and relative.name)))

	local _, footRelative = continue:GetPoint(1)
	check(footRelative == button,
		("the foot hangs off %s, so the two are on top of each other")
			:format(tostring(footRelative and footRelative.name)))

	check(menu:GetHeight() == BARE + STEP,
		("the menu is %g tall and one button taller than %g is %g")
			:format(menu:GetHeight(), BARE, BARE + STEP))

	check(Menu.Describe():find("game menu") ~= nil,
		"the status line does not say the button is in: " .. Menu.Describe())
end

-- Twice more, which is two more presses of Escape.
if button then
	local before, ours, foot = menu:GetHeight(), anchored(button), anchored(continue)
	Menu.Attach()
	Menu.Attach()
	check(menu:GetHeight() == before,
		("attaching again took the menu from %g to %g"):format(before, menu:GetHeight()))
	check(anchored(button) == ours and anchored(continue) == foot,
		("attaching again moved something: button %s -> %s, foot %s -> %s")
			:format(ours, anchored(button), foot, anchored(continue)))
end

-- The client relaying its own column, which is what a version of this that ran
-- once at login would never see. Our button is dropped out of the chain, the
-- foot goes back under the button above it and the frame goes back to the
-- height it was built at.
if button then
	button:ClearAllPoints()
	continue:ClearAllPoints()
	continue:SetPoint("TOP", logout, "BOTTOM", 0, -H.MENU_GAP)
	menu:SetHeight(BARE)

	check(Menu.Attach(), "the button would not go back after the client relaid the menu")

	local _, relative = button:GetPoint(1)
	local _, footRelative = continue:GetPoint(1)
	check(relative == logout and footRelative == button,
		"the button did not go back between the last two")
	check(menu:GetHeight() == BARE + STEP,
		("the menu came back at %g rather than %g"):format(menu:GetHeight(), BARE + STEP))
end

-- The click. The menu comes off the screen and the panel goes up, in that
-- order, because a panel opened under a menu still covering it is the same
-- thing as a button that did nothing.
if button then
	ns.Options.Hide()
	menu:Show()
	button:GetScript("OnClick")()
	check(not menu:IsShown(), "clicking the button left the game menu up")
	check(ns.UI.Windows[1]:IsShown(), "clicking the button did not open the panel")
	ns.Options.Hide()
end

-- And the other menu.
--
-- Blizzard rewrote this frame on the modern clients and the rewrite lays every
-- button out against the frame itself, so there is no chain to read: every
-- button hangs off the menu and nothing hangs off any button, which makes every
-- one of them look like the end of a chain. The walk that reads anchors gives
-- up on that and the one that reads the screen takes over.
--
-- Modelled by re-anchoring the stub's column the way a layout frame would, and
-- unplacing our button, which is the state a client that relaid its menu leaves
-- behind. Blizzard's buttons must come out of this untouched: theirs are placed
-- by code we cannot see and re-placed whenever it likes, and one of ours that
-- re-anchored one of them would be undone on the next show and would take one
-- of Blizzard's with it.
if button then
	local placed = {}
	for index, entry in ipairs(buttons) do
		entry:ClearAllPoints()
		entry:SetPoint("TOP", menu, "TOP", 0, -(H.MENU_GAP + (index - 1) * STEP))
		placed[entry] = anchored(entry)
	end
	button:ClearAllPoints()
	menu:SetHeight(BARE)

	check(Menu.Attach(), "the button would not go into a menu laid out against its frame")

	local point, relative, _, _, y = button:GetPoint(1)
	check(relative == continue and point == "TOP",
		("the button hangs off %s rather than under the lowest button")
			:format(tostring(relative and relative.name)))
	check(y == -H.MENU_GAP,
		("the button sits %g under the foot and the column's own gap is %g")
			:format(-y, H.MENU_GAP))
	check(button:GetHeight() == continue:GetHeight(),
		"the button did not take the foot's height")
	check(menu:GetHeight() == BARE + STEP,
		("the menu is %g tall and one button taller than %g is %g")
			:format(menu:GetHeight(), BARE, BARE + STEP))

	local moved = 0
	for _, entry in ipairs(buttons) do
		if anchored(entry) ~= placed[entry] then
			moved = moved + 1
		end
	end
	check(moved == 0, ("%d of Blizzard's own buttons were moved"):format(moved))

	local height = menu:GetHeight()
	Menu.Attach()
	check(menu:GetHeight() == height and anchored(button) == anchored(button),
		"attaching again into a laid out menu moved something")
	check(Menu.Describe():find("under the last button") ~= nil,
		"the status line does not say the button went under: " .. Menu.Describe())
end

-- And the menu that keeps its buttons in a container.
--
-- This is what the live client answered on the first build: the button was
-- built, the frame was there and the walk found no button in it at all, which
-- is what a menu holding its column inside a frame of its own looks like from
-- outside. Modelled by moving Blizzard's buttons one level down, which is the
-- only thing that changes: they keep the anchors the block above gave them and
-- our button is unplaced again, the way a client that relaid its menu leaves it.
if button then
	local box = H.child("frame", menu, "GameMenuFrameHolder")
	box:SetSize(menu:GetWidth(), menu:GetHeight())
	box:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
	box:SetFrameLevel(4)

	local top = {}
	for _, entry in ipairs(menu.children) do
		if entry == button or entry == box then
			top[#top + 1] = entry
		else
			entry.parent = box
			box.children[#box.children + 1] = entry
		end
	end
	menu.children = top

	button:ClearAllPoints()
	menu:SetHeight(BARE)

	check(Menu.Attach(), "the button would not go into a menu holding a container")

	local _, relative = button:GetPoint(1)
	check(relative == continue,
		("the button hangs off %s rather than the lowest button in the container")
			:format(tostring(relative and relative.name)))
	check(button:GetFrameLevel() == continue:GetFrameLevel() + 1,
		("the button is at level %s and the foot is at %s, so it can be behind it")
			:format(tostring(button:GetFrameLevel()), tostring(continue:GetFrameLevel())))
	check(menu:GetHeight() == BARE + STEP,
		("the menu is %g tall and one button taller than %g is %g")
			:format(menu:GetHeight(), BARE, BARE + STEP))
end

-- The probe runs. It is the only thing in the addon that reports on somebody
-- else's frame, so it is the thing somebody will type when the button has not
-- turned up, and a probe that raises at that moment is worse than no probe.
check(pcall(SlashCmdList.WARRIORKIT, "menu"), "/wk menu raised")

print(("game menu one button, column %g to %g tall, %s")
	:format(BARE, menu:GetHeight(), Menu.Describe()))
