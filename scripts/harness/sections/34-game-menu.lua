-- The button in the client's own menu
--
-- Core/Menu.lua hangs one button off the bottom of Blizzard's game menu and
-- grows the frame by what that costs. Everything hard about it is arithmetic on
-- a frame the addon does not own, and none of it is visible from the source,
-- because the source names no Blizzard button.
--
-- The first version of this file gated a walk that found the foot of the menu's
-- anchor chain and re-anchored it. That walk is gone, and the reason it is gone
-- is the reason these assertions are shaped the way they are: in game it drew a
-- button you saw on every other press of Escape. Blizzard's own column is
-- relaid whenever the client feels like it, and a placement that depends on
-- where that column ended up is a placement that changes under you.
--
-- So five things, and each is a way this has already gone wrong.
--
-- The button lands against the frame's own bottom edge, with air under it.
--
-- The menu grows by exactly the button and the air around it.
--
-- Attaching again does nothing. The real hook is the menu's OnShow, so this
-- runs on every press of Escape, and a version that grew the frame each time
-- reaches the top of the screen inside a session.
--
-- Blizzard's buttons are not touched. Not one of them moves, however the menu
-- is laid out, because ours no longer has an opinion about where they go.
--
-- It works on a menu with nothing in it. That is the case that decides whether
-- placement depends on the walk at all, and the old version could not do it.

local H = ...
local ns, check = H.ns, H.check

local menu, buttons = H.menu, H.menuButtons
local Menu = ns.GameMenu
local button = _G.WarriorKitGameMenuButton

local MARGIN = 8
local STEP = H.MENU_BUTTON_H + H.MENU_GAP
local BARE = #buttons * STEP + H.MENU_GAP

check(button ~= nil, "no button was put in the game menu")
check(Menu ~= nil, "Core/Menu.lua left nothing on ns")

local function anchored(frame)
	local point, relative, relativePoint, x, y = frame:GetPoint(1)
	return ("%s|%s|%s|%s|%s"):format(tostring(point), tostring(relative and relative.name),
		tostring(relativePoint), tostring(x), tostring(y))
end

local function grown()
	return BARE + button:GetHeight() + MARGIN * 2
end

if button then
	check(button.parent == menu, "the button is not a child of the game menu")

	local point, relative, relativePoint, _, y = button:GetPoint(1)
	check(point == "BOTTOM" and relative == menu and relativePoint == "BOTTOM",
		("the button is anchored %s to %s, not to the menu's own bottom edge")
			:format(tostring(point), tostring(relative and relative.name)))
	check(y == MARGIN,
		("the button sits %g off the bottom and the margin is %g"):format(y, MARGIN))

	check(button:GetWidth() == buttons[1]:GetWidth()
		and button:GetHeight() == buttons[1]:GetHeight(),
		("the button is %g x %g and the menu's own are %g x %g")
			:format(button:GetWidth(), button:GetHeight(),
				buttons[1]:GetWidth(), buttons[1]:GetHeight()))

	check(menu:GetHeight() == grown(),
		("the menu is %g tall and %g plus the button and its air is %g")
			:format(menu:GetHeight(), BARE, grown()))

	check(Menu.Describe():find("bottom of the game menu") ~= nil,
		"the status line does not say where the button went: " .. Menu.Describe())
end

-- Blizzard's own, before anything else happens to them.
local placed = {}
for _, entry in ipairs(buttons) do
	placed[entry] = anchored(entry)
end

local function unmoved(where)
	local moved = 0
	for _, entry in ipairs(buttons) do
		if anchored(entry) ~= placed[entry] then
			moved = moved + 1
		end
	end
	check(moved == 0, ("%d of Blizzard's own buttons moved %s"):format(moved, where))
end

unmoved("when the button was placed")

-- Twice more, which is two more presses of Escape. This is the assertion the
-- flip flop would have failed: it took two opens to see the button and two more
-- to lose it again, because the placement depended on where Blizzard's column
-- had ended up and our own button had joined the column it was reading.
if button then
	local before, ours = menu:GetHeight(), anchored(button)
	Menu.Attach()
	Menu.Attach()
	check(menu:GetHeight() == before,
		("attaching again took the menu from %g to %g"):format(before, menu:GetHeight()))
	check(anchored(button) == ours,
		("attaching again moved the button: %s -> %s"):format(ours, anchored(button)))
	unmoved("on the second and third attach")
end

-- The client putting its own height back, which is what a menu that lays itself
-- out on show does before our hook ever runs. The button has to come back to
-- the same place and the frame to the same height, from a height the addon did
-- not write.
if button then
	menu:SetHeight(BARE)
	check(Menu.Attach(), "the button would not go back after the client resized the menu")
	check(menu:GetHeight() == grown(),
		("the menu came back at %g rather than %g"):format(menu:GetHeight(), grown()))
	unmoved("after the client resized the menu")
end

-- A menu laid out against its own frame rather than as a chain, which is the
-- shape the rewritten client uses. Nothing about the placement may depend on it.
if button then
	for index, entry in ipairs(buttons) do
		entry:ClearAllPoints()
		entry:SetPoint("TOP", menu, "TOP", 0, -(H.MENU_GAP + (index - 1) * STEP))
		placed[entry] = anchored(entry)
	end
	button:ClearAllPoints()
	menu:SetHeight(BARE)

	check(Menu.Attach(), "the button would not go into a menu laid out against its frame")
	check(anchored(button) == ("BOTTOM|%s|BOTTOM|0|%g"):format(menu.name, MARGIN),
		"the button did not land on the menu's bottom edge: " .. anchored(button))
	check(menu:GetHeight() == grown(),
		("the menu is %g tall rather than %g"):format(menu:GetHeight(), grown()))
	unmoved("in a menu laid out against its frame")
end

-- A menu that keeps its column in a container of its own, which is what the
-- live client turned out to hold: the frame was there, our button was built and
-- a walk over the menu's own children found no button in it at all. Placement
-- must not care, and the size must still be copied off one of theirs.
if button then
	local box = H.child("frame", menu, "GameMenuFrameHolder")
	box:SetSize(menu:GetWidth(), menu:GetHeight())
	box:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)

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
	button:SetSize(0, 0)
	menu:SetHeight(BARE)

	check(Menu.Attach(), "the button would not go into a menu holding a container")
	check(button:GetWidth() == buttons[1]:GetWidth(),
		"the button did not take its size from a button inside the container")
	check(anchored(button) == ("BOTTOM|%s|BOTTOM|0|%g"):format(menu.name, MARGIN),
		"the button did not land on the menu's bottom edge: " .. anchored(button))
	unmoved("in a menu holding a container")
end

-- And a menu with nothing in it at all. There is no size to copy, so the
-- template's own stands, and the button still goes where it goes. This is the
-- assertion that says placement does not depend on the walk: the old version
-- refused here, and refusing here is what it was doing in game.
if button then
	local held = menu.children
	menu.children = { button }
	button:ClearAllPoints()
	menu:SetHeight(BARE)

	check(Menu.Attach(), "the button would not go into an empty menu")
	check(anchored(button) == ("BOTTOM|%s|BOTTOM|0|%g"):format(menu.name, MARGIN),
		"the button did not land on the menu's bottom edge: " .. anchored(button))
	check(menu:GetHeight() == grown(),
		("the menu is %g tall rather than %g"):format(menu:GetHeight(), grown()))
	check(Menu.Describe():find("template") ~= nil,
		"the status line does not say the size came from the template: " .. Menu.Describe())

	menu.children = held
end

-- The probe runs. It is the only thing in the addon that reports on somebody
-- else's frame, so it is what somebody types when the button has not turned up,
-- and a probe that raises at that moment is worse than no probe.
check(pcall(SlashCmdList.WARRIORKIT, "menu"), "/wk menu raised")

print(("game menu one button at the bottom, column %g to %g tall, %s")
	:format(BARE, menu:GetHeight(), Menu.Describe()))
