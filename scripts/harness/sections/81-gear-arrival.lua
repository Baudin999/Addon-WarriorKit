-- The gear page arriving, and a row told that what is in it moved
--
-- Two motions on the character sheet, one per channel of Ck/Animations.lua.
-- The page coming up slides its two columns in from their own sides, and a
-- repaint that finds the link in a slot changed dips that row and brings it
-- back. Character/Paperdoll.lua carries the argument for both.
--
-- Last, and it has to be here rather than beside the sheet's other five
-- sections. Every one of those runs above 79-floating-messages, which asserts
-- that a dozen looted drops are still in the air and unticked; a section that
-- drove the animation tick from up there would expire them and read as that
-- section's own failure. This is the one place a section can beat that tick on
-- something other than the loot column: 79 has drained everything and 80 has
-- run its own library out, so what this finds on the tween list is nothing and
-- what it leaves is nothing.
--
-- Six things here fail silently and every one is a check below.
--
--   A row waiting its turn. The lead down a column is a delay on the tween,
--   and a tween inside its delay is not written to at all, so a row that was
--   not placed at the start of its own path stands where the layout put it
--   and jumps sideways on the first frame that touches it. Every row but the
--   top of each column, and it looks like a stutter rather than like a bug.
--
--   A column arriving from the wrong side. Both columns read perfectly while
--   they are still, and a right hand column that comes in over the figure is
--   a page nobody would call broken and nobody would call right.
--
--   The two channels crossing. A slide that also fades or a dip that also
--   moves is the field that survived from one arming into the next, which is
--   the bug the library's Arm exists to refuse and is invisible in a still
--   picture.
--
--   Where a row stops. The tween interpolates in whole units and the layout
--   places in the frame's own pixel, and a row left on the interpolation's
--   number is most of a physical pixel off the grid: a name that draws soft,
--   for the rest of the session, with nothing on screen saying why.
--
--   The first paint of a session. Redress compares nineteen links against
--   what it drew last time and the first time it drew nothing, so every slot
--   with a piece in it comes back changed and the sheet's first open would be
--   fifteen rows dipping at once.
--
--   A fight. Both motions are refused mid pull because the sheet is opened in
--   one to be read, and the refusal is the kind of thing that works until
--   somebody moves where it is asked.

local H = ...
local ns, check = H.ns, H.check

local Window, Animations = ns.CharWindow, ns.Ck.Animations

-- The three numbers Character/Paperdoll.lua lays the arrival out in. Written
-- here because the file does not hand them out, and a check that read them off
-- the pane would be agreeing with whatever it found.
local SLIDE, ARRIVE, STAGGER = 120, 0.6, 0.03
local FADE = 0.4

local FRAME = 1 / 60

-- One frame of the client for everything on the tween list, and the wall clock
-- moved with it, because a frame is both.
local function beat(seconds)
	while seconds > 0 do
		local step = (seconds < FRAME) and seconds or FRAME
		local tick = ns.UI.Ticking("anim")
		if tick then
			tick:Beat(step)
		end
		H.advance(step)
		seconds = seconds - step
	end
end

-- Where a row's anchor sits, which is the number the arrival writes.
local function offset(box)
	return select(4, box:GetPoint())
end

-- What the line at the foot reports.
local swept, dipped = 0, 0

check(Animations.Running() == 0,
	("%d tweens were still running when this section started, so the two sections above it left something in the air")
		:format(Animations.Running()))

----------------------------------------------------------------------
-- The page coming up
--
-- Shown, and then read before anything is ticked: every row has to be standing
-- at the start of its own path already, a hundred and twenty pixels outside
-- the column it belongs to, on its own side.
----------------------------------------------------------------------

Window.Show()
local pane = Window.Pane()

-- How many rows are being carried on one channel, which is not the same
-- question as how many tweens are running. UI/Window.lua arms the wash that
-- darkens the world behind a screen window on the same OnShow, and that one is
-- 52-screen-dark.lua's business rather than this section's.
local function carried(channel)
	local count = 0
	for _, box in ipairs(pane.squares) do
		if box[channel].playing then
			count = count + 1
		end
	end
	return count
end

do
	local placed, faded = 0, 0
	for _, box in ipairs(pane.left) do
		if math.abs(offset(box) - (box.restX - SLIDE)) < 0.01 then
			placed = placed + 1
		end
		if box:GetAlpha() ~= 1 then
			faded = faded + 1
		end
	end
	for _, box in ipairs(pane.right) do
		if math.abs(offset(box) - (box.restX + SLIDE)) < 0.01 then
			placed = placed + 1
		end
		if box:GetAlpha() ~= 1 then
			faded = faded + 1
		end
	end
	swept = placed

	check(placed == #pane.squares,
		("%d of %d rows were placed at the start of their own path, and a row that is not stands where the layout left it and jumps on the first tick")
			:format(placed, #pane.squares))
	check(faded == 0,
		("%d rows came up part faded, so the arrival is writing the alpha channel as well as the position one")
			:format(faded))
	check(carried("slide") == #pane.squares,
		("%d of %d rows are being carried in")
			:format(carried("slide"), #pane.squares))
end

----------------------------------------------------------------------
-- A sweep and not a block
--
-- The lead between one row and the next is what the stagger buys, so a frame
-- in the top row of a column has moved and the foot of it has not, and part
-- way through the run the top is nearer home than the foot throughout.
----------------------------------------------------------------------

do
	local first, last = pane.left[1], pane.left[#pane.left]
	check(#pane.left > 1 and (#pane.left - 1) * STAGGER > FRAME,
		"the column is too short or the stagger too small for a frame to tell the two ends apart")

	beat(FRAME)
	check(offset(first) > first.restX - SLIDE,
		"the top of the left column had not moved a frame into the arrival")
	check(math.abs(offset(last) - (last.restX - SLIDE)) < 0.01,
		("the foot of the left column had already travelled %d units a frame in, so nothing is leading anything")
			:format(offset(last) - (last.restX - SLIDE)))

	beat(0.25)
	check(first.restX - offset(first) < last.restX - offset(last),
		("part way in the top of the column has %d units left and the foot has %d, and the top is meant to be ahead")
			:format(first.restX - offset(first), last.restX - offset(last)))
end

----------------------------------------------------------------------
-- Where it stops
--
-- On the layout's own number, and not on the last number the interpolation
-- happened to write. Half a unit here is most of a physical pixel on this page
-- and a row of text drawn off the grid is a row of text drawn soft.
----------------------------------------------------------------------

do
	beat(ARRIVE + #pane.left * STAGGER)

	local home, moved = 0, 0
	for _, box in ipairs(pane.squares) do
		if offset(box) == box.restX then
			home = home + 1
		end
		if box:GetAlpha() == 1 then
			moved = moved + 1
		end
	end
	check(home == #pane.squares,
		("%d of %d rows came to rest on the number the layout gave them")
			:format(home, #pane.squares))
	check(moved == #pane.squares,
		("%d of %d rows arrived at full strength"):format(moved, #pane.squares))
	check(Animations.Running() == 0 and ns.UI.Ticking("anim") == nil,
		("%d tweens outlived the arrival"):format(Animations.Running()))
end

----------------------------------------------------------------------
-- A repaint that found a slot changed
--
-- The helmet comes off and goes back on. Each is one link moving, so each is
-- one row dipping and eighteen rows left alone, and the dip is the alpha
-- channel on its own: the row does not move a unit while it does it.
----------------------------------------------------------------------

do
	local head, other
	for _, box in ipairs(pane.squares) do
		if box.entry.slot == 1 then
			head = box
		elseif box.entry.slot == 5 then
			other = box
		end
	end
	check(head and other, "the head and the chest are not both rows on this page")

	local worn = H.worn[1]
	local where = offset(head)

	H.worn[1] = nil
	pane:Paint()
	check(carried("fade") == 1,
		("%d rows dipped and one link moved"):format(carried("fade")))
	check(head.name:GetText() ~= nil and head:GetAlpha() == 1,
		"the row was dipped before the repaint wrote it, so the dip is hiding the old text rather than announcing the new")

	beat(FADE / 2)
	dipped = head:GetAlpha()
	check(dipped < 0.05,
		("the row was at %.2f half way through its dip and the trough is nought")
			:format(dipped))
	check(other:GetAlpha() == 1,
		"a row whose link did not move dipped with the one that did")
	check(offset(head) == where,
		("the dip moved the row %d units, so the fade is writing the position channel as well")
			:format(offset(head) - where))

	beat(FADE / 2 + FRAME)
	check(head:GetAlpha() == 1,
		("the row came back to %.2f rather than to full strength"):format(head:GetAlpha()))
	check(Animations.Running() == 0, "the dip outlived its own run")

	-- And a repaint that found nothing arms nothing at all, which is the whole
	-- reason this is cheap: the sheet is repainted on six events and most of
	-- them are a bag moving.
	pane:Paint()
	check(Animations.Running() == 0,
		("%d rows dipped on a repaint that found nothing moved"):format(Animations.Running()))

	H.worn[1] = worn
	pane:Paint()
	beat(FADE + FRAME)
	check(head.name:GetText() == "Lionheart Helm" and head:GetAlpha() == 1,
		("the helmet was put back and the row reads %s at %.2f")
			:format(tostring(head.name:GetText()), head:GetAlpha()))
end

----------------------------------------------------------------------
-- A fight
--
-- Neither motion runs mid pull, and the sheet still comes up: in a fight it is
-- opened by the snippet on the key rather than by any Lua of ours, which is
-- the route taken here. Nothing about this is a protection rule. It is that
-- nineteen rows sliding in over six tenths of a second is nineteen rows you
-- cannot read while they do it.
----------------------------------------------------------------------

do
	local sheet = pane.frame:GetParent():GetParent()
	Window.Hide()

	local real = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end

	sheet:Show()
	check(Window.Shown(), "the sheet did not come up on the route a fight leaves open")
	check(carried("slide") == 0,
		("%d rows slid in during a fight"):format(carried("slide")))
	check(offset(pane.left[1]) == pane.left[1].restX,
		"the top of the left column was thrown off the page by an arrival that then refused to bring it back")

	H.worn[5] = nil
	pane:Paint()
	check(carried("fade") == 0,
		("%d rows dipped during a fight"):format(carried("fade")))

	_G.InCombatLockdown = real
	H.worn[5] = H.itemLink("Breastplate of Might")
	pane:Paint()
	beat(FADE + FRAME)
	Window.Hide()
end

check(Animations.Running() == 0 and ns.UI.Ticking("anim") == nil,
	("%d tweens and a tick were left running"):format(Animations.Running()))

print(("arrive %d rows placed off their own side, %d px over %.1fs with %.2fs"
	.. " of lead a row, landing on the layout's own number; a link that moved"
	.. " dips that row to %.2f and no other")
	:format(swept, SLIDE, ARRIVE, STAGGER, dipped))
