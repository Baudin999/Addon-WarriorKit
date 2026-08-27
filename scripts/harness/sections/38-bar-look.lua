-- What one bar looks like, and when it is up
--
-- Five settings per bar, and every one of them is invisible in review. A row
-- count that lays out wrong is arithmetic nobody re-does by hand. A colour is a
-- texture nothing reads back. And the two that decide when a bar is on the
-- screen are a macro string handed to the client to evaluate, which is the one
-- piece of this part that is not code this addon runs: a condition in the wrong
-- order is a bar that is up when it should be down, and the only place that can
-- be caught before the game is here.
--
-- A section of its own rather than two hundred more lines in 05-action-bars,
-- and along the seam that file already has. That one is the clone: the slots
-- each square presses, the keys, the paging and Blizzard's own buttons going
-- down behind it. Nothing in here knows what an action slot is.
--
-- Last in the run order, and self-contained because of it. Every section
-- between this one and 05 has been driving the panel, the skin and the meters,
-- and one of them unticks a bar, so the clone is stood up again here rather
-- than assumed. Everything below puts back what it moved: the last thing it
-- does is drop every record and assert bar 1 is the plan's own shape again.

local H = ...
local ns = H.ns
local check, fire = H.check, H.fire
local window = H.carry.window

local Look = ns.BarLook

ns.db.actionBars = true
ns.WhichBars.Follow()
check(ns.Bars.Apply(), "the clone reported combat deferring it with no combat running")

local bars = ns.Bars.All()
local one
for index = 1, #bars do
	if bars[index].def.key == "bar1" then
		one = bars[index]
	end
end
check(one ~= nil, "bar 1 is not standing, so nothing below is measuring anything")

if one then

local def = one.def

-- The pad, the square and the gap between two of them, which is the arithmetic
-- 05-action-bars measures the shipped bars with. Written again here because a
-- shape that is a setting has to be checked against the same three numbers at
-- every shape, and a bar that agreed with itself would prove nothing.
local PAD, GAP, SQUARE = 3, 2, 27

local function shape(columns, rows)
	return PAD * 2 + columns * SQUARE + (columns - 1) * GAP,
		PAD * 2 + rows * SQUARE + (rows - 1) * GAP
end

--------------------------------------------------------------------------
-- The shape
--------------------------------------------------------------------------

-- Nothing is saved until something is set, and what is drawn until then is the
-- plan in Which.lua. That is the whole of why a fresh clone of the repo looks
-- the same as the machine it was written on.
check(Look.Rows(def) == 1 and Look.Columns(def) == 12,
	("bar 1 came up as %d rows of %d and the plan says one row of twelve")
		:format(Look.Rows(def), Look.Columns(def)))
check(Look.Decided() == 0, "a bar nobody has touched is already carrying a record")

check(Look.SetRows(def, 3), "three rows was refused and it is one of the six")
check(ns.Bars.Restyle(), "the restyle reported combat deferring it with no combat running")
local width, height = shape(4, 3)
check(one.frame:GetWidth() == width and one.frame:GetHeight() == height,
	("three rows of four came out %s by %s, the arithmetic says %d by %d"):format(
		tostring(one.frame:GetWidth()), tostring(one.frame:GetHeight()), width, height))
check(one.buttons[12]:GetWidth() == SQUARE,
	"folding the bar changed the size of a square, which is the one number here that is not a setting")

-- A number that is not a shape is refused rather than rounded, because twelve
-- buttons in five rows is four rows and a stump and no message anywhere.
check(not Look.SetRows(def, 5), "five rows was accepted and twelve does not divide by it")

-- The panel's stepper counts in ones and only six of the twelve numbers it can
-- reach are a shape, so it walks between them on the direction of travel.
-- Snapping to the nearest instead is a control that does nothing on every
-- second press: +1 from four lands on five, and five is nearer four than six.
Look.StepRows(def, Look.Rows(def) + 1)
check(Look.Rows(def) == 4, ("a step up from three rows landed on %d"):format(Look.Rows(def)))
Look.StepRows(def, Look.Rows(def) + 1)
check(Look.Rows(def) == 6, ("a step up from four rows landed on %d"):format(Look.Rows(def)))
Look.StepRows(def, Look.Rows(def) - 1)
check(Look.Rows(def) == 4, ("a step down from six rows landed on %d"):format(Look.Rows(def)))

-- A setting put back to what the plan says is dropped rather than stored, so
-- "no record" and "the plan" stay one sentence. Stored, a bar you folded and
-- unfolded would carry a row count saying what the plan already says, and the
-- button that puts every bar back to plain would offer to undo nothing.
check(Look.SetRows(def, 1), "one row was refused and it is what bar 1 ships as")
check(Look.Decided() == 0, "a bar folded and unfolded again is still carrying a record")
check(Look.SetRows(def, 4), "four rows was refused and it is one of the six")

--------------------------------------------------------------------------
-- The paint
--
-- The colour is a name in a table in source rather than three numbers in saved
-- variables, so what has to be proved is that the name reaches the texture.
--------------------------------------------------------------------------

check(Look.SetColor(def, "blue"), "a colour in the palette was refused")
check(not Look.SetColor(def, "puce"), "a colour that is not in the palette was taken")
check(Look.SetAlpha(def, 40), "an opacity the slider can reach was refused")
check(ns.Bars.Restyle(), "the restyle reported combat deferring the paint")

local paint = Look.Tint(def)
check(one.frame.bg.r == paint[1] and one.frame.bg.g == paint[2]
	and one.frame.bg.b == paint[3],
	"the colour the palette names is not the colour the bar was painted")
check(math.abs((one.frame.bg.a or 1) - 0.4) < 1e-9,
	("the background came out at %s and the setting says 40%%"):format(tostring(one.frame.bg.a)))
check(one.frame.edges[1]:GetAlpha() == 1,
	"the hairline went with a background that is still there")

-- At nothing the hairline goes too, which is Feeds/Stream.lua's rule and is
-- right for the same reason: a rectangle of hairline round nothing is a window
-- frame with no window in it.
Look.SetAlpha(def, 0)
ns.Bars.Restyle()
check(one.frame.edges[1]:GetAlpha() == 0,
	"the background went to nothing and the hairline round it stayed")
Look.SetAlpha(def, 95)
ns.Bars.Restyle()

--------------------------------------------------------------------------
-- When it is up
--------------------------------------------------------------------------

check(_G.WarriorKitDriver(one.frame, "visibility") == nil,
	"a bar nobody has given hours is already having its visibility decided for it")

Look.SetCombat(def, true)
check(ns.Bars.Restyle(), "the restyle reported combat deferring the driver")
check(_G.WarriorKitDriver(one.frame, "visibility") == "[combat] hide; show",
	("the combat switch registered %q"):format(
		tostring(_G.WarriorKitDriver(one.frame, "visibility"))))

-- Registered again on every restyle, and the count is the point: two drivers on
-- one frame is two answers to the same question, the client keeps both, and
-- nothing on the screen says which one is talking.
ns.Bars.Restyle()
ns.Bars.Restyle()
check(_G.WarriorKitDrivers(one.frame, "visibility") == 1,
	("%d visibility drivers are on bar 1 after three restyles")
		:format(_G.WarriorKitDrivers(one.frame, "visibility")))

-- A key beats the combat switch rather than being read alongside it. A bar you
-- hold a key for is down unless you are holding the key, in a fight or out of
-- one, so there is nothing left for the other switch to decide.
check(Look.SetKey(def, "shift"), "shift was refused and it is one of the three")
check(not Look.SetKey(def, "tab"), "a key that is not a modifier was taken")
ns.Bars.Restyle()
check(_G.WarriorKitDriver(one.frame, "visibility") == "[mod:shift] show; hide",
	("a bar with both set registered %q"):format(
		tostring(_G.WarriorKitDriver(one.frame, "visibility"))))
check(Look.Hours(def) == "up only while shift is held",
	("the readout says %q"):format(Look.Hours(def)))

-- And handing the bar back takes the driver with it. Left on, the client would
-- go on deciding when to show a bar this addon had already given up, and would
-- show it the next time the macro changed its mind.
ns.WhichBars.Want("bar1", false)
check(ns.Bars.Apply(), "unticking the bar reported combat deferring it")
check(_G.WarriorKitDriver(one.frame, "visibility") == nil,
	"a bar that was handed back is still having its visibility decided for it")
ns.WhichBars.Want("bar1", true)
check(ns.Bars.Apply(), "ticking the bar back reported combat deferring it")
check(_G.WarriorKitDriver(one.frame, "visibility") == "[mod:shift] show; hide",
	"the bar came back and the client was not told when to show it again")

--------------------------------------------------------------------------
-- The words
--
-- Five settings and five slash words, and a word is the one part of a setting
-- nothing else here touches: the panel calls the setter directly. A word that
-- names the wrong bar, or parses its value the wrong way round, is a command
-- that reports success and changes something else.
--------------------------------------------------------------------------

check(pcall(SlashCmdList.WARRIORKIT, "actionbars rows bottomleft 2"),
	"actionbars rows raised")
check(Look.Rows(ns.BarLook.Find("bottomleft")) == 2,
	("the word left the bottom left bar on %d rows"):format(
		Look.Rows(ns.BarLook.Find("bottomleft"))))

-- Named by the tab's own label as well as by the plan's key, because
-- "bottom left" is what the panel calls it and a macro says the other one.
check(ns.BarLook.Find("bottom left") == ns.BarLook.Find("bottomleft"),
	"the label the tab strip carries does not name the same bar as the plan's key")
check(ns.BarLook.Find("nothing") == nil, "a bar nobody has is a bar the word found")

check(pcall(SlashCmdList.WARRIORKIT, "actionbars combat bottomleft on"),
	"actionbars combat raised")
check(Look.Combat(ns.BarLook.Find("bottomleft")),
	"combat on left the bar staying up in combat")
SlashCmdList.WARRIORKIT("actionbars combat bottomleft off")
check(not Look.Combat(ns.BarLook.Find("bottomleft")),
	"combat off left the bar going down in combat")

-- A value the setting cannot take changes nothing, which is the half a
-- dispatcher gets wrong: refusing loudly and writing anyway.
SlashCmdList.WARRIORKIT("actionbars rows bottomleft 5")
check(Look.Rows(ns.BarLook.Find("bottomleft")) == 2,
	"a row count that is not a shape was refused and written")

--------------------------------------------------------------------------
-- The bars' own lock
--
-- Shift and a drag, without unlocking every frame in the addon to do it. The
-- handles are what moves, so the handles are what is measured.
--------------------------------------------------------------------------

local function handles()
	local up = 0
	for index = 1, #bars do
		if bars[index].handle and bars[index].handle:IsShown() then
			up = up + 1
		end
	end
	return up
end

local wasLocked, wasBars = ns.db.locked, ns.db.barsLocked
ns.db.locked = true
ns.db.barsLocked = true
_G.WarriorKitShift(true)
fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
check(handles() == 0, ("shift put %d handles up on bars that are locked"):format(handles()))
check(not ns.BarPlace.Loose(), "the bars report themselves loose while they are locked")

ns.db.barsLocked = false
fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
check(handles() == #bars,
	("%d of %d bars grew a handle with shift held and the bars loose")
		:format(handles(), #bars))
check(ns.BarPlace.Loose(), "the bars are loose and shift is held and they still refuse to move")

_G.WarriorKitShift(false)
fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
check(handles() == 0, ("%d handles stayed up after shift came off"):format(handles()))

ns.db.locked, ns.db.barsLocked = wasLocked, wasBars
ns.Each("lock")

--------------------------------------------------------------------------
-- Which bar the page is showing, said on the screen
--
-- The strip names a bar and the rim points at it. Driven through the window's
-- own OnShow and OnHide rather than through Options.Show and Options.Hide,
-- because Escape closes the panel by calling Hide on the frame and that is the
-- route the mark has to survive.
--------------------------------------------------------------------------

local function rimmed()
	local up, on = 0, nil
	for index = 1, #bars do
		if bars[index].rim and bars[index].rim:IsShown() then
			up = up + 1
			on = bars[index].def.key
		end
	end
	return up, on
end

check(rimmed() == 0, "a bar is wearing the page's rim with the page shut")

ns.Options.Show()
window.frame:GetScript("OnShow")(window.frame)
ns.BarLook.Show(1)
ns.Bars.ApplyMark()
local up, on = rimmed()
check(up == 1 and on == "bar1",
	("the page is on bar 1 and %d bars are rimmed, the last of them %s")
		:format(up, tostring(on)))

-- The rim follows the strip, which is the whole point of it.
ns.BarLook.Show(2)
ns.Bars.ApplyMark()
up, on = rimmed()
check(up == 1 and on == "bottomleft",
	("the strip moved to the bottom left bar and the rim is on %s"):format(tostring(on)))

-- Anchored outside the bar on both corners. A rim on the bar's own edge covers
-- the hairline that is already there and reads as the colour setting having
-- moved, so the offsets are what is asserted rather than the colour.
local rim = bars[2].rim
local topLeft, _, _, left, top = rim:GetPoint(1)
local bottomRight, _, _, right, bottom = rim:GetPoint(2)
check(topLeft == "TOPLEFT" and left < 0 and top > 0,
	("the rim's top left corner is at %s, %s and is not outside the bar")
		:format(tostring(left), tostring(top)))
check(bottomRight == "BOTTOMRIGHT" and right > 0 and bottom < 0,
	("the rim's bottom right corner is at %s, %s and is not outside the bar")
		:format(tostring(right), tostring(bottom)))

-- And it goes with the window, by the route Escape takes.
window.frame:GetScript("OnHide")(window.frame)
check(rimmed() == 0, "the panel closed and a bar kept its rim")
ns.Options.Hide()

--------------------------------------------------------------------------
-- Back to the plan
--------------------------------------------------------------------------

check(Look.Decided() > 0, "five settings were written and no bar carries a record")
check(Look.Plain() > 0, "plain dropped nothing")
check(Look.Decided() == 0, "plain left a record behind")
check(ns.Bars.Restyle(), "the restyle reported combat deferring the way back")

width, height = shape(12, 1)
check(one.frame:GetWidth() == width and one.frame:GetHeight() == height,
	("plain left bar 1 at %s by %s and the plan says %d by %d"):format(
		tostring(one.frame:GetWidth()), tostring(one.frame:GetHeight()), width, height))
check(_G.WarriorKitDriver(one.frame, "visibility") == nil,
	"plain left the client still deciding when to show bar 1")
check(one.frame.edges[1]:GetAlpha() == 1, "plain left bar 1 without its hairline")

print(("look   %d shapes, bar 1 folded to 4 and back to 12, %d colours, "
	.. "shift lifts %d handles"):format(#Look.ROWS, #Look.PALETTE, #bars))

end
