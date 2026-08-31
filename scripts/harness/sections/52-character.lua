-- The character window
--
-- Five tabs replacing a window of the client's, and most of this section is
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
local ns, check, state = H.ns, H.check, H.state
local sheet, moved = H.sheet, H.moved

local Window, Stats, Worn = ns.CharWindow, ns.CharStats, ns.Worn
-- The two tabs this section drives by number. The stats and reputation pages
-- are read through their own modules rather than through a tab, so neither
-- needs one.
local GEAR, SKILLS, LOADOUTS = 1, 3, 5

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
check(frame:GetHeight() * ns.UI.WindowZoom() <= state.SCREEN_H,
	"the character window is taller than the screen")

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
	local special = Find(groups, "Hit and miss", "a special, three levels up")
	check(special ~= nil, "the stats page has no row for missing a special")
	check(special.value == ("%.2f%%"):format(Stats.MeleeMiss(3) - sheet.hitMelee),
		("the special row reads %s and the hit off the gear was not taken off it")
			:format(tostring(special and special.value)))

	-- The second weapon costs nineteen points on a white swing and nothing on a
	-- special, which is the one thing on this page that is a fact about you
	-- rather than about the target.
	local was = H.swing.off
	H.swing.off = 1.8
	local swing = Find(Stats.Groups(), "Hit and miss", "a white swing, three levels up")
	check(swing.value == ("%.2f%%"):format(Stats.MeleeMiss(3) + 19 - sheet.hitMelee),
		("dual wielding, a white swing reads %s"):format(tostring(swing.value)))
	H.swing.off = was

	local skill = Find(Stats.Groups(), "Hit and miss", "weapon skill")
	check(skill ~= nil and skill.note:find("Under the cap", 1, true) ~= nil,
		"a weapon skill under the cap does not say so on the stats page")

	-- A spell never goes below one percent however much hit is on the gear, so
	-- the row is floored rather than reaching nothing.
	local spell = Find(groups, "Hit and miss", "a spell, three levels up")
	check(spell ~= nil and tonumber(spell.value:match("^([%d.]+)")) >= 1,
		"the spell row went under the floor a spell always has")
end

-- The older client, which has no combat ratings at all. Taking the index away
-- is what makes it that client for a moment: the page has to say it cannot
-- subtract rather than subtracting zero and reporting a clean sheet.
do
	local melee, spell = _G.CR_HIT_MELEE, _G.CR_HIT_SPELL
	_G.CR_HIT_MELEE, _G.CR_HIT_SPELL = nil, nil

	local row = Find(Stats.Groups(), "Hit and miss", "hit off your gear")
	check(row ~= nil and row.value:find("does not rate hit", 1, true) ~= nil,
		("with no ratings the hit row reads %s"):format(tostring(row and row.value)))
	local special = Find(Stats.Groups(), "Hit and miss", "a special, three levels up")
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
-- The gear page
----------------------------------------------------------------------

do
	Window.Show(GEAR)
	local pane = Window.Pane(GEAR)
	check(#pane.squares == 19,
		("%d slots were drawn and the client has nineteen"):format(#pane.squares))

	local head, neck
	for _, box in ipairs(pane.squares) do
		if box.entry.slot == 1 then
			head = box
		elseif box.entry.slot == 2 then
			neck = box
		end
	end

	check(head.icon:IsShown(), "the helmet slot is filled and drew no icon")
	check(head.wear:IsShown(), "the helmet is at 40% durability and drew no wear line")
	check(not neck.wear:IsShown(),
		"a necklace does not wear out and the slot drew a wear line anyway")

	-- Quality is read off the item rather than off the slot, so the edge round
	-- an epic is the epic colour and not the chrome.
	check(head.edges.r == ns.UI.Quality[4][1],
		"the epic helmet is not edged in the epic colour")

	local shirt
	for _, box in ipairs(pane.squares) do
		if box.entry.slot == 4 then
			shirt = box
		end
	end
	check(shirt.empty:IsShown() and not shirt.icon:IsShown(),
		"an empty slot did not draw the client's own silhouette")

	local wear, worst = Worn.Wear()
	check(math.abs(wear - (40 + 95 + 12) / 300) < 1e-6,
		("durability came to %.4f and the three worn pieces are 147 of 300"):format(wear))
	check(worst ~= nil and worst.slot == 16,
		"the worst piece is the main hand at twelve percent and something else was named")

	local level, empty = Worn.Level()
	check(level ~= nil and math.abs(level - 60) < 1e-6,
		("the average item level came to %s"):format(tostring(level)))
	check(empty > 0, "every slot came back full on a character wearing four pieces")
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

	local picked = #moved.picked
	main.button.scripts.OnDragStart(main.button)
	check(#moved.picked == picked + 1 and moved.picked[#moved.picked] == 16,
		"dragging out of the main hand did not pick the weapon up")

	-- And refused for the same reason a click is, rather than by a second rule
	-- written next to the first.
	local real = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	picked = #moved.picked
	main.button.scripts.OnDragStart(main.button)
	check(#moved.picked == picked, "a drag out of a square moved gear in combat")
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

Window.Hide()

print(("character %d slots, %d skill rows, %s; %s")
	:format(#Window.Pane(GEAR).squares, H.carry.characterRows or 0,
		Worn.Describe(), Stats.Describe()))
