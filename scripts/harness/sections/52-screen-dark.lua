-- The dark behind a screen window
--
-- A screen window has no ground, so what it is written on is the game, and one
-- wash across its own half of the monitor is what makes it a page rather than
-- text scattered over scenery. UI/Window.lua draws it behind the screen flag,
-- off a getter the caller hands over, so this is the library's behaviour and not
-- the character sheet's: every screen window the addon grows later gets the same
-- wash and should be readable by the same checks.
--
-- The sheet is the one screen window there is today, which is why this runs
-- here and reads that frame. It was a block at the foot of 52-gear-page.lua for
-- exactly that reason and it does not belong there: everything else in that
-- file is the page, its rows, its columns, its figure and its readout, and this
-- is the window under all of them. The line ceiling is what noticed.
--
-- Four things about the wash fail silently and all four are here.
--
-- **It must not take the mouse.** This is the one thing on the sheet that could
-- cost the player the world behind it: a screen window turns the mouse off on
-- its own frame so a click reaches the mob, and a shadow over half the monitor
-- on a frame that answered the pointer would be half a monitor you can no
-- longer target, loot or turn the camera in. It draws and it hovers exactly the
-- same either way, so nothing about looking at it says which one shipped. The
-- floor is IsMouseEnabled on the frame; the check is a press at a point, and
-- the grid below sweeps the whole sheet so that the only thing hanging directly
-- off the frame the pointer ever reaches is the grip.
--
-- **It fades.** A rectangle of shadow that arrives between one frame and the
-- next on a key press reads as a bug, and a fade is the difference between
-- alpha 0 on the frame the sheet came up and alpha 0 forever, which is a wash
-- nobody can see at all. Both ends are read.
--
-- **It stops at the window's own edge.** The other half of the screen is what
-- the sheet was cut down to give back, and a wash pinned to anything but the
-- window's own two corners takes it away again without saying so.
--
-- **It runs the right way.** Solid at the outer edge and gone by the middle,
-- where the player's character is standing. Backwards is a dark rectangle over
-- the game and a clear one over the page, which is worse than no wash at all.
--
-- What this cannot prove: that half a monitor of shadow looks like anything. A
-- gradient is four colours on the corners of a quad and the stub answers what
-- they are without drawing one.

local H = ...
local ns, check = H.ns, H.check

local mouse, C = H.mouse, ns.UI.Color
local Window = ns.CharWindow

-- Opened here rather than inherited. The sections above this one leave the
-- sheet shut, and the fade is read off the frame's own OnShow, which fires on
-- the change and not on a Show over a window that is already up.
Window.Show()
local frame = _G.WarriorKitCharacter
check(frame ~= nil, "the character sheet was never built, so there is no screen window to read")

-- The window object rather than the frame, because the wash is the library's
-- and nothing in Character/ names it. Asked of UI.Windows the way
-- 51-placing.lua asks for a grip: a screen window that quietly stopped drawing
-- one would otherwise read as a sheet with nothing to check.
local held
for _, entry in ipairs(ns.UI.Windows) do
	if entry.frame == frame then
		held = entry
	end
end
check(held ~= nil and held.dark ~= nil, "the sheet draws no wash behind it")

local dark = held.dark

----------------------------------------------------------------------
-- What it is and where it stops
----------------------------------------------------------------------

do
	check(dark.layer == "BACKGROUND",
		("the wash is on %s, so it is drawn over the page it is meant to be behind")
			:format(tostring(dark.layer)))

	-- Pinned to the window's own corners and to nothing else.
	check(dark:GetNumPoints() == 2,
		("the wash is held by %d points and the two corners of the sheet are two")
			:format(dark:GetNumPoints()))
	local top, above, topPoint, topX, topY = dark:GetPoint(1)
	local foot, below, footPoint, footX, footY = dark:GetPoint(2)
	check(top == "TOPLEFT" and above == frame and topPoint == "TOPLEFT"
		and topX == 0 and topY == 0
		and foot == "BOTTOMRIGHT" and below == frame and footPoint == "BOTTOMRIGHT"
		and footX == 0 and footY == 0,
		"the wash is not pinned to the sheet's own two corners, so it runs into the half of the screen the player is playing in")

	-- Solid at the outer edge and gone by the middle. The client runs a
	-- horizontal gradient min at the left, so the sheet's is solid at max.
	local ramp = dark:GetGradient()
	check(ramp ~= nil and ramp.orientation == "HORIZONTAL",
		"the wash runs down the sheet rather than across it")
	check(ramp.min[4] == 0 and ramp.max[4] == C.shadow[4],
		("the wash runs from %s at the middle to %s at the outer edge, and it is meant to be the other way up")
			:format(tostring(ramp.min[4]), tostring(ramp.max[4])))
end

----------------------------------------------------------------------
-- Faded, not shown
--
-- The sheet is closed and opened again so the frame's own OnShow runs, which is
-- the one hook every route up goes through: the method, Escape's counterpart
-- and the secure snippet that is the only one of the three that opens the sheet
-- in a fight.
----------------------------------------------------------------------

do
	Window.Hide()
	Window.Show()
	check(dark:IsShown() and dark:GetAlpha() == 0,
		("the sheet came up with the wash already at %s, so half the screen goes black on the key press")
			:format(tostring(dark:GetAlpha())))

	local tick = ns.UI.Ticking("anim")
	check(tick ~= nil, "the wash was never handed to the animation tick, so it will never arrive")
	if tick then
		tick:Beat(0.3)
	end
	check(dark:GetAlpha() == 1,
		("a third of a second in, the wash is at %s and it should have landed")
			:format(tostring(dark:GetAlpha())))
end

----------------------------------------------------------------------
-- And it never answers the pointer
--
-- Every point on the sheet, on a grid: the frame itself must never be what a
-- press lands on, and the only child of it that may is the strip the sheet is
-- dragged by. Written as a sweep rather than as one aimed press because the
-- page under it is redrawn every few weeks and a single point that happened to
-- be free would quietly stop covering anything.
----------------------------------------------------------------------

local free = 0

do
	check(not frame:IsMouseEnabled(),
		"the sheet's own frame takes the mouse, so the half of the screen behind it cannot be clicked")
	local grip = held.grip
	for down = 0, 10 do
		for across = 0, 10 do
			local x, y = mouse.Point(frame,
				frame:GetWidth() * across / 10, -frame:GetHeight() * down / 10)
			local under = mouse.At(x, y, "LeftButton")
			if under == nil then
				free = free + 1
			end
			check(under ~= frame,
				("a press %d across and %d down the sheet landed on the sheet itself")
					:format(across, down))
			check(under == nil or under == grip or under:GetParent() ~= frame,
				("a press %d across and %d down the sheet landed on %s, which hangs off the sheet's own frame and is not the grip")
					:format(across, down, under and under:GetObjectType() or "nothing"))
		end
	end
	check(free > 0,
		"no point on the sheet hands the press back to the world, so nothing behind it can be clicked")
end

----------------------------------------------------------------------
-- The setting
--
-- Off has to reach a sheet that is already up, because a tick box that does
-- nothing until you shut the window and open it again is a tick box you press
-- twice. Put back at the foot of the block, so the reset section below finds
-- the setting the addon ships with.
----------------------------------------------------------------------

do
	ns.db.characterDim = false
	Window.Darken()
	check(not dark:IsShown() and dark:GetAlpha() == 0,
		"the setting was turned off with the sheet up and the wash stayed on the screen")
	Window.Hide()
	Window.Show()
	check(not dark:IsShown(),
		"the sheet was opened with the setting off and darkened the world anyway")
	ns.db.characterDim = ns.DefaultCopy("characterDim")
end

Window.Hide()

print(("dark   half the monitor washed behind the sheet, solid at the outer edge and gone by the middle, faded in over 0.2s; %d of 121 points on it hand the press back to the world")
	:format(free))
