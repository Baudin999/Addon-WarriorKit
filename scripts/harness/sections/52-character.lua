-- The character window
--
-- Four tabs replacing a window of the client's, and most of this section is
-- about the one number on them the client has never drawn.
--
-- **The miss maths is asserted against published figures rather than against
-- itself.** A character at the weapon skill their level allows misses 5.5% one
-- level up, 6% two up and 9% three up. Those three are what every hit cap
-- anybody quotes is derived from, they are not derivable from each other, and
-- the four constants in Character/Stats.lua are the only shape that lands on
-- all three. So the section closes the ten point shortfall the client stub
-- ships with, reads the three numbers, and opens it again. A formula that
-- ignored weapon skill would pass one half of that and fail the other.
--
-- **Everything else is what a page cannot say about itself.** How many squares
-- were drawn and which of them lit a durability line, whether the row a
-- sentence wrapped inside came out taller than one line, whether the client's
-- own sheet is off the screen and its key redirected, and whether a click in a
-- fight refused instead of calling.
--
-- What this cannot prove: that the client agrees about any of the thirty calls
-- behind it. The stub answers what client/13-character.lua says it answers, and
-- the two clients this addon runs on disagree about three of them, which is why
-- the ratings are taken away here for a moment rather than assumed.

local H = ...
local ns, check, state, fire = H.ns, H.check, H.state, H.fire
local sheet, moved = H.sheet, H.moved

local Window, Stats, Worn = ns.CharWindow, ns.CharStats, ns.Worn
-- The three tabs this section drives by number. The reputation page is read
-- through its own module rather than through a tab, so it needs none, and the
-- stats are not a tab at all any more: they are a column on the gear page.
local GEAR, SKILLS, LOADOUTS = 1, 2, 4

-- The heading the three miss rows sit under. It carries the three levels so the
-- rows underneath do not have to, and it is named here because six checks below
-- read it.
local MISSING = "Missing a boss, three levels up"

local function whole(value)
	return math.abs(value - math.floor(value + 0.5)) < 1e-6
end

local function Find(groups, title, label)
	for _, group in ipairs(groups) do
		if group.title == title then
			for _, row in ipairs(group.rows) do
				if row.label == label then
					return row
				end
			end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- The first open pays for the sheet
--
-- 00-login has the other half: login reads no slot and loads no figure for a
-- window nobody has opened. This is what opening it costs, and it is asserted
-- before anything below drives the window.
----------------------------------------------------------------------

do
	local model = Window.Pane(GEAR).panel.model
	check((model.dressed or 0) == 0, "the figure was loaded before the sheet was opened")

	Window.Show()
	check((model.dressed or 0) > 0, "opening the sheet did not load the figure")
	check(H.gear.durability > 0, "opening the sheet did not read what you are wearing")
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

Window.Show()
local frame = _G.WarriorKitCharacter
check(frame ~= nil, "the character window was never built")
check(Window.Shown(), "the character window would not open")
check(math.abs(ns.UI.Pixel(frame) - 1) < 1e-9,
	("the character window is not on the grid: one pixel is %.4f units")
		:format(ns.UI.Pixel(frame)))
check(whole(frame:GetWidth()) and whole(frame:GetHeight()),
	("the character window is %.2f x %.2f, not a whole number of pixels")
		:format(frame:GetWidth(), frame:GetHeight()))
check(frame:GetHeight() * ns.Zoom("characterZoom") <= state.SCREEN_H,
	"the character window is taller than the screen")

-- Half the monitor, on the right, at four by three.
--
-- It was the whole monitor, and all three of the things the player could see
-- wrong with it came from that: the stats column stood against the last pixel
-- of the panel where a windowed client carries it off the edge, the name of a
-- helmet sat a third of a screen from the helmet, and there was no part of the
-- game left to click on with the sheet up. None of the three fails visibly, so
-- all three are numbers here.
do
	local zoom = ns.Zoom("characterZoom")
	local wide = (_G.GetPhysicalScreenSize())
	local across = frame:GetWidth() * zoom
	check(math.abs(across - wide / 2) <= zoom,
		("the sheet is %d of %d pixels across and it is meant to be half")
			:format(across, wide))
	check(math.abs(frame:GetWidth() / frame:GetHeight() - 4 / 3) < 0.02,
		("the sheet came out %d by %d, which is not four by three")
			:format(frame:GetWidth(), frame:GetHeight()))

	-- On the right, which is the half of the screen the player's own character
	-- is not standing in. The point itself rather than the four edges: the sheet
	-- ignores its parent's scale and UIParent does not, so the two are measured
	-- in different units and a difference between them says nothing.
	check(frame:GetNumPoints() == 1,
		("the sheet is held by %d points and it wants one")
			:format(frame:GetNumPoints()))
	local point, relative, relativePoint, x = frame:GetPoint(1)
	check(point == "RIGHT" and relativePoint == "RIGHT" and relative == _G.UIParent,
		("the sheet is anchored %s to the screen's %s"):format(tostring(point),
			tostring(relativePoint)))
	check(x < 0 and math.abs(x) < frame:GetWidth() / 4,
		("the sheet sits %d units off the right edge of a %d unit screen")
			:format(x, frame:GetWidth()))
end

for index = GEAR, LOADOUTS do
	check(Window.Pane(index) ~= nil, ("tab %d has no pane"):format(index))
end

----------------------------------------------------------------------
-- Missing, against the three published figures
----------------------------------------------------------------------

do
	local short = sheet.short
	sheet.short = 0

	check(math.abs(Stats.MeleeMiss(0) - 5.0) < 1e-6,
		("at the cap, a same level target reads %.2f%% and should read 5.00%%")
			:format(Stats.MeleeMiss(0)))
	check(math.abs(Stats.MeleeMiss(1) - 5.5) < 1e-6,
		("at the cap, one level up reads %.2f%% and should read 5.50%%")
			:format(Stats.MeleeMiss(1)))
	check(math.abs(Stats.MeleeMiss(2) - 6.0) < 1e-6,
		("at the cap, two levels up reads %.2f%% and should read 6.00%%")
			:format(Stats.MeleeMiss(2)))
	check(math.abs(Stats.MeleeMiss(3) - 9.0) < 1e-6,
		("at the cap, a boss reads %.2f%% and should read 9.00%%")
			:format(Stats.MeleeMiss(3)))

	-- And the shortfall, which is the branch a formula that stopped at the
	-- first ten points would get wrong. Ten points under the cap is six tenths
	-- of a percent each on top of the nine.
	sheet.short = 10
	check(math.abs(Stats.MeleeMiss(3) - 15.0) < 1e-6,
		("ten points of weapon skill short of the cap reads %.2f%% against a boss and should read 15.00%%")
			:format(Stats.MeleeMiss(3)))

	sheet.short = short
end

do
	local groups = Stats.Groups()
	local special = Find(groups, MISSING, "a special")
	check(special ~= nil, "the stats page has no row for missing a special")
	check(special.value == ("%.2f%%"):format(Stats.MeleeMiss(3) - sheet.hitMelee),
		("the special row reads %s and the hit off the gear was not taken off it")
			:format(tostring(special and special.value)))

	-- The second weapon costs nineteen points on a white swing and nothing on a
	-- special, which is the one thing on this page that is a fact about you
	-- rather than about the target.
	local was = H.swing.off
	H.swing.off = 1.8
	local swing = Find(Stats.Groups(), MISSING, "a white swing")
	check(swing.value == ("%.2f%%"):format(Stats.MeleeMiss(3) + 19 - sheet.hitMelee),
		("dual wielding, a white swing reads %s"):format(tostring(swing.value)))
	H.swing.off = was

	local skill = Find(Stats.Groups(), MISSING, "weapon skill")
	check(skill ~= nil and skill.note:find("Under the cap", 1, true) ~= nil,
		"a weapon skill under the cap does not say so on the stats page")

	-- A spell never goes below one percent however much hit is on the gear, so
	-- the row is floored rather than reaching nothing.
	local spell = Find(groups, MISSING, "a spell")
	check(spell ~= nil and tonumber(spell.value:match("^([%d.]+)")) >= 1,
		"the spell row went under the floor a spell always has")
end

-- The older client, which has no combat ratings at all. Taking the index away
-- is what makes it that client for a moment: the page has to say it cannot
-- subtract rather than subtracting zero and reporting a clean sheet.
do
	local melee, spell = _G.CR_HIT_MELEE, _G.CR_HIT_SPELL
	_G.CR_HIT_MELEE, _G.CR_HIT_SPELL = nil, nil

	local row = Find(Stats.Groups(), MISSING, "hit off your gear")
	check(row ~= nil and row.value:find("does not rate hit", 1, true) ~= nil,
		("with no ratings the hit row reads %s"):format(tostring(row and row.value)))
	local special = Find(Stats.Groups(), MISSING, "a special")
	check(special.value == ("%.2f%%"):format(Stats.MeleeMiss(3)),
		"with no ratings something was still taken off the miss chance")
	check(Stats.Describe():find("no ratings", 1, true) ~= nil,
		("the status line does not say the client has no ratings: %s"):format(Stats.Describe()))

	_G.CR_HIT_MELEE, _G.CR_HIT_SPELL = melee, spell
end

-- A group with nothing to say is not drawn at all. The client answers a spell
-- crit chance and a mana regen for a warrior in plate, both off intellect
-- nobody chose to have, so the spell group hangs on spell power rather than on
-- whether its calls answered: rows of nought are how a page teaches you to stop
-- reading it.
do
	local groups = Stats.Groups()
	local spell
	for _, group in ipairs(groups) do
		if group.title == "Spell" then
			spell = group
		end
	end
	check(spell == nil, "the spell group was drawn on a character with no spell power")
	sheet.spellPower = 640
	check(Find(Stats.Groups(), "Spell", "spell power") ~= nil,
		"spell power on the gear and the spell group is still not drawn")
	sheet.spellPower = 0
	check(Find(groups, "Attributes", "strength") ~= nil, "the attributes group is missing")
	check(Find(groups, "Defence", "dodge") ~= nil, "the defence group is missing")
end

----------------------------------------------------------------------
-- Skills
----------------------------------------------------------------------

do
	local groups = ns.CharSkills.Groups()
	check(#groups == 2, ("%d skill groups were drawn and the client listed two"):format(#groups))
	check(H.expandedSkills() == 1,
		("the skill headers were expanded %d times and once is the whole of it")
			:format(H.expandedSkills()))

	local axes = Find(groups, "Weapon Skills", "Axes")
	local swords = Find(groups, "Weapon Skills", "Swords")
	check(axes ~= nil and axes.note == nil,
		"a weapon skill at the cap for your level still carries a sentence")
	check(swords ~= nil and swords.note ~= nil and swords.note:find("10 points short", 1, true),
		("a weapon skill ten points short reads %s"):format(tostring(swords and swords.note)))
	check(axes.fraction ~= nil and math.abs(axes.fraction - 1) < 1e-6,
		"a skill at the cap did not draw a full bar")

	-- A profession is told from a weapon skill by what it caps at and whether
	-- it can be abandoned, not by the header it sits under, because every
	-- header on this page is a localised string.
	local craft = Find(groups, "Professions", "Blacksmithing")
	check(craft ~= nil and craft.note == nil,
		"a profession was treated as a weapon skill and told what it costs you")

	local behind, worst = ns.CharSkills.Behind()
	check(behind == 1 and worst == 10,
		("%d weapon skills behind by at most %d, and one by ten is the fixture")
			:format(behind, worst))
end

----------------------------------------------------------------------
-- Reputation
----------------------------------------------------------------------

do
	local groups = ns.CharRep.Groups()
	check(H.expandedFactions() == 1,
		"the collapsed faction header was not expanded, so nothing under it could be listed")
	check(#groups == 1 and #groups[1].rows == 2,
		("the reputation page drew %d groups"):format(#groups))

	local thrallmar = Find(groups, "Outland", "Thrallmar")
	check(thrallmar ~= nil and thrallmar.value:find("Honored", 1, true) ~= nil,
		("a standing the client names reads %s"):format(tostring(thrallmar and thrallmar.value)))
	check(thrallmar.fraction ~= nil and math.abs(thrallmar.fraction - 0.4) < 1e-6,
		("Thrallmar is 2400 of 6000 into Honored and the bar reads %.3f")
			:format(thrallmar.fraction or -1))
end

----------------------------------------------------------------------
-- Clicking a slot
--
-- Half of what a click on a worn item does is open to an addon and half is not.
-- The swap is an ordinary call. Using what is in the slot is protected, and so
-- is finishing a spell the client is holding until it is told which item it is
-- for, which is what a sharpening stone is: both of those got the dialog saying
-- the addon has been blocked from an action only available to the Blizzard UI.
-- So the use is a macro on a secure button, and every check below goes through
-- Click rather than the handlers, because the half that matters is the client's
-- own: the square that shipped had every attribute right and acted on an edge it
-- never registered for, which reads as a square that does nothing.
----------------------------------------------------------------------

do
	-- The tab, put up here rather than inherited. What the page draws moved to
	-- 52-gear-page.lua and took the Show with it, and a block that reads a square
	-- off a tab nobody raised reads it off a page that was never laid out.
	Window.Show(GEAR)
	local pane = Window.Pane(GEAR)
	local head
	for _, box in ipairs(pane.squares) do
		if box.entry.slot == 1 then
			head = box
		end
	end

	-- Nothing on these squares may hand the right button to the camera: the
	-- right button is the action.
	local passed = head.button:GetPassThroughButtons()
	check(passed == nil or not passed["RightButton"],
		"the square passes the right button through, so its right click turns the camera")

	-- And the row it sits on has to hand it back. The button is the icon and the
	-- rest of the row is an ordinary hover, because this page is the whole
	-- monitor: two columns of button the full width of a column is most of the
	-- left and right of the screen with no camera in it.
	--
	-- Read off the click flag and not off SetPassThroughButtons, which is what
	-- this block used to check. That call is 10.1.5 and the live client is 2.5.6,
	-- so the assertion passed against a stub of a call the game does not have
	-- while every row in the game ate the drag. The flag is the one the client
	-- carries: mouse on for the hover, clicks off so the buttons reach the world.
	check(head:IsMouseEnabled(), "the gear row does not answer the mouse, so it has no hover")
	check(not head:IsMouseClickEnabled(),
		"the gear row takes clicks, so a right drag on a row does not turn the camera")
	check(head.button:GetWidth() < head:GetWidth(),
		("the secure button is %s wide on a row of %s, so the action is the whole row again")
			:format(tostring(head.button:GetWidth()), tostring(head:GetWidth())))

	-- A right click takes the piece off, and it has to actually run: the line
	-- is read out of what the client was sent rather than off the attribute,
	-- because an attribute is what a dead square also has.
	local macros = #moved.macros
	head.button:Click("RightButton")
	check(#moved.macros == macros + 1 and moved.macros[#moved.macros] == "/use 1",
		("a right click on the helmet sent %s, and it has to send /use 1")
			:format(tostring(moved.macros[#moved.macros])))

	-- A plain left click is still the swap, and it is the client's own call.
	local picked, used = #moved.picked, #moved.used
	macros = #moved.macros
	head.button:Click("LeftButton")
	check(#moved.picked == picked + 1 and moved.picked[#moved.picked] == 1,
		"a left click on the helmet did not reach the client's own swap")
	check(#moved.used == used and #moved.macros == macros,
		"a left click used the helmet instead of swapping it")

	-- And in a fight, where the client refuses the swap silently. The page has
	-- to refuse first and say why, because a slot that does nothing when you
	-- click it is worse than one that will not let you.
	local real = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	picked = #moved.picked
	head.button:Click("LeftButton")
	check(#moved.picked == picked, "gear was moved in combat")
	local free, why = Worn.Free()
	check(free == false and why:find("fight", 1, true) ~= nil,
		("a slot in combat gave the reason %s"):format(tostring(why)))
	_G.InCombatLockdown = real
end

----------------------------------------------------------------------
-- Clicking a slot with a stone waiting
----------------------------------------------------------------------

do
	local pane = Window.Pane(GEAR)
	local main
	for _, box in ipairs(pane.squares) do
		if box.entry.slot == 16 then
			main = box
		end
	end

	moved.targeting = true
	local picked, used = #moved.picked, #moved.used

	-- The whole click, because the thing that was broken sat in the middle of
	-- one. The stone lands on the slot the square carries, and it lands from
	-- the client's own secure half rather than from anything this addon calls.
	main.button:Click("LeftButton")
	check(#moved.used == used + 1 and moved.used[#moved.used] == 16,
		"a stone waiting for an item did not land on the main hand")
	check(#moved.picked == picked,
		"a stone waiting for an item was answered with the swap, which is the forbidden one")

	-- And in a fight, where a stone is exactly the thing you want and nothing
	-- has to be written for it to work.
	local real = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	used, picked = #moved.used, #moved.picked
	main.button:Click("LeftButton")
	check(#moved.used == used + 1 and #moved.picked == picked,
		"a stone in a fight did not land on the main hand")
	_G.InCombatLockdown = real

	moved.targeting = false
	check(Worn.Targeting() == false,
		"nothing is waiting for an item and the page still thinks something is")

	-- With nothing waiting the same click is the swap again, which is the half
	-- of the arrangement that a square holding a macro on the left would lose.
	picked = #moved.picked
	main.button:Click("LeftButton")
	check(#moved.picked == picked + 1 and moved.picked[#moved.picked] == 16,
		"a left click with nothing waiting stopped being the swap")
end

----------------------------------------------------------------------
-- Dragging a piece out of a square
--
-- The half of the arrangement that a click test cannot reach. Dropping into a
-- square has been tested since the page was written and taking something out of
-- one was never a click, so the page shipped able to accept gear and unable to
-- give it back.
----------------------------------------------------------------------

do
	local pane = Window.Pane(GEAR)
	local main
	for _, box in ipairs(pane.squares) do
		if box.entry.slot == 16 then
			main = box
		end
	end

	check(main.button.dragButton == "LeftButton",
		"a gear square does not take a left drag, so nothing can be pulled out of it")

	-- Grabbed at a point on the square and let go of over nothing, which is what
	-- pulling a weapon out of a slot is. The square is one of nineteen on a page
	-- half the monitor wide, so which frame takes the press is a real question.
	local function pull(box)
		local took, dragging = H.mouse.Grab(H.mouse.Point(box.button))
		check(took == box.button, ("a drag on the %s square landed on %s")
			:format(tostring(box.entry.slot),
				took and (took:GetName() or took:GetObjectType()) or "nothing"))
		check(dragging, ("the %s square took no left drag"):format(tostring(box.entry.slot)))
		H.mouse.Drop(-5000, 5000)
	end

	local picked = #moved.picked
	pull(main)
	check(#moved.picked == picked + 1 and moved.picked[#moved.picked] == 16,
		"dragging out of the main hand did not pick the weapon up")

	-- And in a fight it asks the slot rather than the fight, which is the
	-- client's own rule: a weapon goes in your hand mid pull and armour does
	-- not. Both halves are checked here, because the whole of the change was
	-- that one rule became two.
	local chest
	for _, box in ipairs(pane.squares) do
		if box.entry.slot == 5 then
			chest = box
		end
	end

	local real = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end

	picked = #moved.picked
	pull(main)
	check(#moved.picked == picked + 1 and moved.picked[#moved.picked] == 16,
		"a weapon could not be pulled out of its square in a fight")

	picked = #moved.picked
	pull(chest)
	check(#moved.picked == picked, "a drag out of the chest square moved armour in combat")

	_G.InCombatLockdown = real
end

----------------------------------------------------------------------
-- The trace on a square
--
-- Turned on and clicked through, because what it costs to be wrong is a Lua
-- error inside PreClick, which takes the click down with it. The square has
-- now been broken three times and every symptom was the word nothing, so a
-- trace that breaks it a fourth is worse than no trace.
----------------------------------------------------------------------

do
	local pane = Window.Pane(GEAR)
	local main
	for _, box in ipairs(pane.squares) do
		if box.entry.slot == 16 then
			main = box
		end
	end

	local Trace = ns.CharTrace
	check(Trace.On() == false and Trace.Describe() == "off",
		"the gear trace is on before anybody asked for it")

	local said = _G.ChatFrame1.messages or {}
	local quiet = #said
	main.button:Click("LeftButton")
	check(#said == quiet, "the trace said something while it was off")

	Trace.Set(true)
	local describe = Trace.Describe()
	check(describe:find("19 squares", 1, true) ~= nil
		and describe:find("acts on up", 1, true) ~= nil,
		("the trace describes itself as %q, and it has to name the squares and the edge")
			:format(describe))

	local before = #said
	moved.targeting = true
	main.button:Click("LeftButton")
	moved.targeting = false
	local lines = ""
	for index = before + 1, #said do
		lines = lines .. said[index].text .. "\n"
	end
	check(lines:find("main hand (16)", 1, true) ~= nil,
		"a traced click did not name the slot it was on")
	check(lines:find("acts on up", 1, true) ~= nil,
		"a traced click did not say which edge the square acts on")
	check(lines:find("SpellCanTargetItem=true", 1, true) ~= nil,
		"a traced click did not say that a stone was waiting")
	check(lines:find("after:", 1, true) ~= nil,
		"a traced click said what it was about to do and never said what happened")

	Trace.Set(false)
	check(Trace.On() == false, "the trace would not turn off")
end

----------------------------------------------------------------------
-- The rows the readout draws
----------------------------------------------------------------------

do
	Window.Show(SKILLS)
	local pane = Window.Pane(SKILLS)
	check(pane:Lines() > 0, "the skills tab drew no lines at all")

	local tallest, fractional = 0, 0
	for index = 1, pane:Lines() do
		local line = pane.lines[index]
		if line:IsShown() then
			if not whole(line:GetHeight()) then
				fractional = fractional + 1
			end
			tallest = math.max(tallest, line:GetHeight())
		end
	end
	check(fractional == 0, ("%d rows are not a whole number of pixels tall"):format(fractional))
	check(tallest > ns.UI.Metric.row,
		"no row grew, so the sentence under a weapon skill is being drawn into one line's worth of room")
	H.carry.characterRows = pane:Lines()
end

----------------------------------------------------------------------
-- The loadout tab
----------------------------------------------------------------------

do
	Window.Show(LOADOUTS)
	local pane = Window.Pane(LOADOUTS)
	check(#pane.kit.widgets > 0, "the loadout page put no rows on the character window")
	check(pane.stack.height > 0, "the loadout page laid out to nothing")
	check(ns.LoadoutPage ~= nil, "the loadout page is not a file of its own")

	-- It is the same page, so it is still driving the same secure buttons. A
	-- tab that had quietly become a copy would pass every layout check above.
	local before = ns.Loadouts.Count()
	pane.host.Refresh()
	check(ns.Loadouts.Count() == before,
		"refreshing the loadout tab changed the list under it")
end

----------------------------------------------------------------------
-- Blizzard's own sheet
----------------------------------------------------------------------

do
	check(ns.db.hideBlizzCharacter, "the character sheet hide is off, so nothing below measures anything")
	local sheetFrame = _G.CharacterFrame
	check(sheetFrame:IsVisible() == false, "the client's character sheet is on the screen")
	check(ns.Attic.Held(sheetFrame), "the client's character sheet is hidden but not caged")
	check(ns.Attic.Held(_G.PaperDollFrame) and ns.Attic.Held(_G.SkillFrame),
		"the client's own pages were left out of the attic")

	-- The C key. The client's own function is gone and ours is in its place, and
	-- ours carries which page was asked for.
	Window.Hide()
	_G.ToggleCharacter("SkillFrame")
	check(Window.Shown() and Window.Tab() == SKILLS,
		("C on the skills page opened tab %d"):format(Window.Tab()))
	check(sheetFrame:IsVisible() == false, "the client's sheet came back on a key press")

	-- The two pages this window does not draw. Neither opens a tab and neither
	-- puts the client's window back: what happens is a sentence.
	Window.Hide()
	_G.ToggleCharacter("PetPaperDollFrame")
	check(not Window.Shown(), "the pet sheet opened a tab this window does not have")

	-- And off, all the way back to what was there before.
	ns.db.hideBlizzCharacter = false
	ns.BlizzHide.Apply()
	check(sheetFrame:IsVisible(), "turning the switch off left the client's sheet hidden")
	check(ns.Attic.Held(sheetFrame) == false,
		"the attic is still holding a sheet it handed back")
	local pages = #H.characterKey.pages
	_G.ToggleCharacter("PaperDollFrame")
	check(#H.characterKey.pages == pages + 1,
		"the switch went off and the client never got its own C key back")

	ns.db.hideBlizzCharacter = true
	ns.BlizzHide.Apply()
	check(ns.Attic.Held(sheetFrame), "the switch went back on and the sheet stayed out of the attic")
end

----------------------------------------------------------------------
-- The window in a fight
--
-- The gear page is nineteen secure buttons, and the client refuses an addon
-- every protected thing while it is in combat: showing this window, hiding it,
-- and taking the gear page down to put another tab up. That is what shut the
-- sheet mid pull, which is when the durability line is worth the most.
--
-- What answers it is a snippet on a bound button, so what is checked here is
-- the button, the binding under it, that a tab still moves in a fight without
-- the gear page going anywhere, and that the two Lua ways in now refuse out
-- loud rather than calling something the client will drop.
--
-- What this cannot prove: that the client runs the snippet. No stub does. The
-- shape is what is checkable here, and the shape is what has been wrong twice.
----------------------------------------------------------------------

do
	-- A key on the client's own character page. This fixture spends C and
	-- SHIFT-C on the cloned bars, so the page is bound to a key nothing else
	-- here holds, and the pass is told the binding set moved the way the client
	-- tells it.
	_G.WarriorKitBindings.TOGGLECHARACTER0 = { "ALT-C" }
	fire("UPDATE_BINDINGS")
	ns.BlizzHide.Apply()

	local key = Window.Key()
	check(key ~= nil, "there is no secure button behind the character key")
	check(key:GetRegisteredClicks()["AnyDown"] == true,
		"the character key button is not registered on the edge a binding fires")
	check(type(key:GetAttribute("_onclick")) == "string",
		"the character key button carries no snippet, so a fight is still a shut window")
	check(key:GetFrameRef("window") ~= nil, "the snippet was handed no window to show")
	check(GetBindingAction("ALT-C", true) == ("CLICK %s:LeftButton"):format(Window.KeyName()),
		"the character key never reached the secure button")
	-- And it can still say which key that was. The client stops answering a key
	-- for the command underneath once an override is on it, so a line that asked
	-- again here would tell the player to press the wrong letter.
	check(ns.CharBlizzard.KeyText() == "ALT-C",
		("the sheet calls its own key %s"):format(ns.CharBlizzard.KeyText()))

	-- And a drag, which is the other half of the same sentence. It is a secure
	-- drag, because moving a window that holds a protected frame is refused in
	-- combat exactly as showing it is, so the point is written into an attribute
	-- and a snippet is what places the frame.
	--
	-- The half worth gating is where the drag is delivered. The sheet has no
	-- title bar to grab, and the answer to that must not be the frame: a mouse
	-- enabled frame swallows every button that lands on it, and this one covers
	-- half the game, so a drag on the frame would take the left button and the
	-- camera's right drag out of that whole half. It is the strip across the top
	-- instead, and these three checks are the three ways that can go wrong.
	local frame = Window.Pane(GEAR).frame:GetParent():GetParent()
	local sheet
	for _, entry in ipairs(ns.UI.Windows) do
		if entry.frame == frame then
			sheet = entry
		end
	end
	check(sheet ~= nil and sheet.grip ~= nil, "the character sheet has no grip to drag it by")
	check(frame.dragButton == nil,
		"the whole sheet takes a drag, so half the screen is an invisible handle")
	check(sheet.grip.dragButton ~= nil, "the sheet's grip was never given the drag")
	check(frame:GetAttribute("_onattributechanged") ~= nil,
		"the sheet is dragged from a snippet and carries none")

	-- Over the page, and the tab row over the grip. This started out the other
	-- way round on the argument that a strip above the tabs is a tab you cannot
	-- press, and it shipped a sheet nobody could drag: the bottom of the stack is
	-- under the page, under the pages the sheet lifts to content plus ten, and
	-- under all nineteen gear squares, so the strip was never reached by anything.
	--
	-- Both halves are checked because either one alone is a bug. A grip under the
	-- page cannot be grabbed. A grip over the tabs eats every tab press.
	check(sheet.grip:GetFrameLevel() > sheet.content:GetFrameLevel(),
		("the grip sits at level %d and the page at %d, so the page is over the strip")
			:format(sheet.grip:GetFrameLevel(), sheet.content:GetFrameLevel()))
	-- Reached through the gear page, which is anchored to the bottom of the tab
	-- row, rather than through an export added for one check.
	local _, row = Window.Pane(GEAR).frame:GetPoint()
	check(row:GetFrameLevel() > sheet.grip:GetFrameLevel(),
		("the tab row sits at level %d and the grip at %d, so the strip eats the tabs")
			:format(row:GetFrameLevel(), sheet.grip:GetFrameLevel()))

	-- And where you drop it is where it stays. The sheet sizes and places itself
	-- off the monitor out of every resize, which is where a screen change and a
	-- drag of the zoom slider both land, so the corner it ships in has to be a
	-- default the drag overrides rather than a rule the drag loses to. A sheet
	-- that walked back to the right hand edge the next time the slider moved
	-- would look exactly like a drag that never took.
	local home = { frame:GetPoint() }
	local spot = ns.db.windowSpots["WarriorKitCharacter"]
	local was = sheet.place.placed
	local wasShown = frame:IsShown()

	-- Open, because it used to be dragged shut: a gesture nobody can make, and
	-- invisible while the drag was two handlers called by name.
	Window.Show(GEAR)

	-- Grabbed at the far end of the strip, away from the tabs over its left. The
	-- press goes to a point and the stub says which frame is really there, so a
	-- grip under the page fails here rather than passing. That is the
	-- arrangement that shipped, and this file asserted it as the requirement.
	local own = frame:GetEffectiveScale()
	local grabX, grabY = H.mouse.Point(sheet.grip,
		sheet.grip:GetWidth() - 20, -sheet.grip:GetHeight() / 2)
	local took, dragging = H.mouse.Grab(grabX, grabY, "LeftButton")
	check(took == sheet.grip, ("a drag on the sheet's strip landed on %s")
		:format(took and (took:GetName() or took:GetObjectType()) or "nothing"))
	check(dragging, "the strip under the pointer is not registered for a left drag")

	-- Straight down the screen first, and the direction is the point: x never
	-- changes on this leg, so a snippet hung off the offsets would sit still.
	-- What it hangs off is the count UI/Placeable.lua keeps.
	local top = frame:GetTop()
	local pointerX, pointerY = grabX, grabY - 40 * own
	H.mouse.Move(pointerX, pointerY)
	check(math.abs(frame:GetTop() - (top - 40)) < 1e-6,
		("a drag 40 down the screen moved the sheet from %.2f to %.2f")
			:format(top, frame:GetTop()))
	check(frame:GetNumPoints() == 1,
		("the snippet left the sheet on %d anchors, so it is pinned rather than placed")
			:format(frame:GetNumPoints()))

	H.mouse.Drop(pointerX + (60 - frame:GetLeft()) * own,
		pointerY + (-30 - frame:GetTop()) * own)
	check(ns.db.windowSpots["WarriorKitCharacter"] ~= nil,
		"the sheet was dropped somewhere and wrote down nothing")
	check(math.abs(frame:GetLeft() - 60) < 1e-6 and math.abs(frame:GetTop() + 30) < 1e-6,
		("the sheet was dropped at 60, -30 and landed at %.2f, %.2f")
			:format(frame:GetLeft(), frame:GetTop()))

	Window.Fit()
	check(math.abs(frame:GetLeft() - 60) < 1e-6 and math.abs(frame:GetTop() + 30) < 1e-6,
		("a refit put the sheet back to %.2f, %.2f after it was dropped at 60, -30")
			:format(frame:GetLeft(), frame:GetTop()))

	-- And the count is what places it. A new offset with no new count moves
	-- nothing, and the same count written twice is not a change at all, so the
	-- client drops the write and the snippet does not run again. Both halves are
	-- why that counter exists and nothing proved either.
	local count = frame:GetAttribute("wk-move")
	local function offset()
		return select(4, frame:GetPoint())
	end
	local before = offset()
	frame:SetAttribute("wk-x", 200)
	check(offset() == before,
		"a new offset placed the sheet without the count that the snippet reads")
	frame:SetAttribute("wk-move", count + 1)
	check(offset() == 200,
		("the count moved and the sheet is anchored at %s rather than 200")
			:format(tostring(offset())))
	frame:SetAttribute("wk-x", 300)
	frame:SetAttribute("wk-move", count + 1)
	check(offset() == 200,
		("the same count written twice ran the snippet again and the sheet is at %s")
			:format(tostring(offset())))
	sheet.place.moves = count + 1

	if not wasShown then
		frame:Hide()
	end
	frame:ClearAllPoints()
	frame:SetPoint(home[1], home[2] or _G.UIParent, home[3], home[4], home[5])
	ns.db.windowSpots["WarriorKitCharacter"] = spot
	-- And the flag, which the drop above set and nothing else clears. Left true,
	-- the sheet would decline to re-anchor for the rest of the run, and a later
	-- section asking where it sits off the monitor would be reading the corner
	-- this check dropped it in.
	sheet.place.placed = was

	-- Open before the fight, because that is the state the tabs are tested in.
	Window.Show(GEAR)
	check(Window.Shown(), "the window would not open out of combat")

	local real = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end

	local gear = Window.Pane(GEAR).frame
	Window.Show(SKILLS)
	check(Window.Tab() == SKILLS, "a tab would not move in a fight")
	check(gear:IsShown(), "switching tab in a fight hid the gear page and its secure buttons")

	check(Window.Hide() == false and Window.Shown(),
		"Lua closed a window holding a protected frame in a fight")

	_G.InCombatLockdown = real
	Window.Hide()
	_G.InCombatLockdown = function() return true end
	check(Window.Show(GEAR) == false and not Window.Shown(),
		"Lua opened a window holding a protected frame in a fight")
	_G.InCombatLockdown = real

	Window.Show(GEAR)
	check(Window.Shown(), "the window would not open again once the fight was over")
end

----------------------------------------------------------------------
-- The figure on the page
--
-- The squares are repainted on six events and the model was redressed on none
-- of them, so a weapon swapped with the sheet open changed the square and left
-- the figure holding the old one. It used to hide itself right by accident,
-- because switching tab took the page down and put it back; the page does not
-- go down any more, so the redress is deliberate and is checked here.
--
-- The other half is the cost. SetUnit reloads the model, UNIT_INVENTORY_CHANGED
-- fires on a bag moving as well, and a page that reloaded on every looted grey
-- would flicker all evening. So both directions are asserted: it reloads when
-- what you are wearing moved, and it does not when anything else did.
----------------------------------------------------------------------

do
	local pane = Window.Pane(GEAR)
	local model = pane.panel.model
	local real, dressed = model.SetUnit, 0
	model.SetUnit = function(self, unit)
		dressed = dressed + 1
		if real then
			return real(self, unit)
		end
	end

	pane:Paint()
	check(dressed == 0, "the model reloaded on a repaint that changed nothing")

	local held = H.swing.mainhand
	H.swing.mainhand = H.itemLink("Bloodspiller")
	pane:Paint()
	check(dressed == 1, "a weapon went into a hand and the figure kept the old one")

	pane:Paint()
	check(dressed == 1, "the model reloaded again on a repaint after the swap")

	H.swing.mainhand = held
	pane:Paint()
	check(dressed == 2, "a weapon came off and the figure kept holding it")

	model.SetUnit = real
end

Window.Hide()

-- The stats column used to be read out here and is 52-gear-page.lua's line now.
-- It moved with the block that measures it: a section cannot report a number a
-- later section is the one to take.
print(("character %d slots, %d skill rows; %s; %s")
	:format(#Window.Pane(GEAR).squares, H.carry.characterRows or 0,
		Worn.Describe(), Stats.Describe()))
