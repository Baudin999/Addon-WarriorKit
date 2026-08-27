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
		"attaching again moved the button or the foot")
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

print(("game menu one button, column %g to %g tall, %s")
	:format(BARE, menu:GetHeight(), Menu.Describe()))
