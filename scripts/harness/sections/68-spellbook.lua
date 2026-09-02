-- The spell book
--
-- One row per spell in place of the client's one entry per rank, and most of
-- this section is about the fold-out: that a rank picked there is what the
-- square is armed with, what a drag picks up, and what the window opens on
-- tomorrow.
--
-- **The grouping is asserted against the fixture's shape, not a count.**
-- 19-spellbook.lua puts Rend's three ranks at indices one, four and five with
-- two other spells between them, and a Battle Shout rank the trainer still
-- has. A reader that grouped by neighbour would draw Rend twice; one that
-- took every entry would draw a square nobody can cast. Both are checked by
-- what the first tab drew, not by how many rows it drew.
--
-- **The secure half is read back off the square.** What a press would cast
-- is the spell attribute, and the fixture's ids are what that attribute is
-- compared against, so the claim is that the pick reached the button the
-- client reads and not only the label beside it.
--
-- **A fight refuses the pick and the end of the fight lands it.** The square
-- is a protected frame and its attributes cannot be written in combat, so the
-- pick is held and the foot says so, and PLAYER_REGEN_ENABLED is what arms
-- it. Modelled with the lockdown stub swapped for a moment, the way section
-- 21 does.
--
-- What this cannot prove: that the client agrees a press on the square casts
-- the id in the attribute. 14-secure.lua models the macro half of a secure
-- click and nothing of the spell half, so the attribute is as far as the
-- harness can follow it.

local H = ...
local ns, check, state, fire = H.ns, H.check, H.state, H.fire
local fixture = H.spellbook

local Window, Blizz = ns.SpellWindow, ns.BookBlizzard
local M = ns.UI.Metric

local GENERAL, FURY = 1, 2

local function whole(value)
	return math.abs(value - math.floor(value + 0.5)) < 1e-6
end

local function Offsets(region)
	local _, _, _, x, y = region:GetPoint(1)
	return x, y
end

local function Spell(tab, name)
	local entry = Window.Book()[tab]
	for index = 1, #entry.spells do
		if entry.spells[index].name == name then
			return entry.spells[index], index
		end
	end
	return nil
end

-- The shared dropdown, asked for through the drawing layer the way the
-- options window is asked for through UI.Windows: which control it is open
-- under, and the lines it is showing.
local function Owner()
	local list = ns.UI.Dropdown()
	return list and list.owner or nil
end

local function DropdownRows()
	local list = ns.UI.Dropdown()
	local rows = {}
	if not list then
		return rows
	end
	for index = 1, #list.rows do
		if list.rows[index]:IsShown() then
			rows[#rows + 1] = list.rows[index]
		end
	end
	return rows
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

Window.Show()
local frame = _G.WarriorKitSpellbook
check(frame ~= nil, "the spell book was never built")
check(Window.Shown(), "the spell book would not open")
check(math.abs(ns.UI.Pixel(frame) * ns.Zoom("spellbookZoom") - 1) < 1e-9,
	("the spell book is not at its own zoom: one pixel is %.4f units at zoom %.2f")
		:format(ns.UI.Pixel(frame), ns.Zoom("spellbookZoom")))
check(whole(frame:GetWidth()) and whole(frame:GetHeight()),
	("the spell book is %.2f x %.2f, not a whole number of pixels")
		:format(frame:GetWidth(), frame:GetHeight()))
check(frame:GetHeight() * ns.Zoom("spellbookZoom") <= state.SCREEN_H,
	"the spell book is taller than the screen")

----------------------------------------------------------------------
-- The book, read and grouped
----------------------------------------------------------------------

do
	local book = Window.Book()
	check(#book == #fixture.tabs, ("the window read %d tabs of %d"):format(#book, #fixture.tabs))
	check(book[GENERAL] and book[GENERAL].name == "General",
		("the first tab is headed %s"):format(tostring(book[GENERAL] and book[GENERAL].name)))
	check(#book[GENERAL].spells == 3,
		("the first tab drew %d rows for seven entries, three of them spells"):format(#book[GENERAL].spells))

	local rend = Spell(GENERAL, "Rend")
	check(rend ~= nil and #rend.ranks == 3, "Rend's three ranks were not gathered into one row")
	if rend then
		check(rend.ranks[1].id == 772 and rend.ranks[2].id == 6546 and rend.ranks[3].id == 6547,
			"Rend's ranks are not in the book's own order")
		check(rend.ranks[3].label == "Rank 3", ("the top rank is labelled %s"):format(tostring(rend.ranks[3].label)))
	end

	local shout = Spell(GENERAL, "Battle Shout")
	check(shout ~= nil and #shout.ranks == 2, "the rank the trainer still has was drawn as one you know")

	local enrage = Spell(FURY, "Enrage")
	check(enrage ~= nil and enrage.passive, "Enrage was not read as passive")
	check(enrage ~= nil and enrage.ranks[1].label ~= "", "a passive with no rank line has no word under it")
end

----------------------------------------------------------------------
-- The rows and the squares
----------------------------------------------------------------------

do
	local rend, at = Spell(GENERAL, "Rend")
	local row = Window.Row(at)
	check(row ~= nil and row:IsShown(), "Rend has no row on the screen")
	check(row.square:GetAttribute("type") == "spell",
		("Rend's square is armed as %s"):format(tostring(row.square:GetAttribute("type"))))
	check(row.square:GetAttribute("spell") == rend.ranks[3].id,
		("Rend's square opens on %s and should open on the top rank"):format(tostring(row.square:GetAttribute("spell"))))
	check(row.fold:IsShown(), "Rend has three ranks and no fold-out")
	check(row.rank:GetText() == "Rank 3", ("the rank beside Rend reads %s"):format(tostring(row.rank:GetText())))
	check(row.square:GetRegisteredClicks()["AnyUp"] == true,
		"the square is not registered on the release, so a drag would cast on the press")
	check(row.square:GetAttribute("useOnKeyDown") == false,
		"the square does not name the edge it acts on")

	local _, clapAt = Spell(GENERAL, "Thunder Clap")
	local clap = Window.Row(clapAt)
	check(clap ~= nil and not clap.fold:IsShown(), "a spell with one rank has a fold-out")
	check(clap.square:GetAttribute("spell") == 6343,
		("Thunder Clap's square is armed with %s"):format(tostring(clap.square:GetAttribute("spell"))))

	-- Three rows over two columns: two down the first, one at the top of the
	-- second, at the pitch the file names.
	local x1, y1 = Offsets(Window.Row(1))
	local x2, y2 = Offsets(Window.Row(2))
	local x3, y3 = Offsets(Window.Row(3))
	check(x1 == 0 and y1 == 0, ("the first row sits at %s, %s"):format(tostring(x1), tostring(y1)))
	check(x2 == 0 and y2 < 0, ("the second row sits at %s, %s and should be under the first"):format(tostring(x2), tostring(y2)))
	check(x3 > 0 and y3 == 0, ("the third row sits at %s, %s and should head the second column"):format(tostring(x3), tostring(y3)))
	check(Window.Row(4) == nil or not Window.Row(4):IsShown(), "a fourth row is showing for a tab of three")
end

----------------------------------------------------------------------
-- The fold-out
----------------------------------------------------------------------

do
	local rend, at = Spell(GENERAL, "Rend")
	local row = Window.Row(at)

	check(Owner() == nil, "a fold-out is open before anything was pressed")
	row.fold:Click("LeftButton", false)
	check(Owner() == row.fold, "pressing the fold-out did not open the list under it")

	local rows = DropdownRows()
	check(#rows == 3, ("the fold-out lists %d ranks of 3"):format(#rows))
	check(rows[1] and rows[1].text:GetText() == "Rank 3, on the square",
		("the first line reads %s"):format(tostring(rows[1] and rows[1].text:GetText())))
	check(rows[3] and rows[3].text:GetText() == "Rank 1",
		("the last line reads %s"):format(tostring(rows[3] and rows[3].text:GetText())))

	-- Pressing the fold-out again folds it back.
	row.fold:Click("LeftButton", false)
	check(Owner() == nil, "pressing the fold-out again did not close the list")

	-- Pick rank one.
	row.fold:Click("LeftButton", false)
	rows = DropdownRows()
	rows[3]:Click("LeftButton", false)
	check(Owner() == nil, "picking a rank left the list open")
	check(row.square:GetAttribute("spell") == rend.ranks[1].id,
		("after the pick the square is armed with %s"):format(tostring(row.square:GetAttribute("spell"))))
	check(row.rank:GetText() == "Rank 1", ("after the pick the rank reads %s"):format(tostring(row.rank:GetText())))
	check(ns.dbc.spellRanks.Rend == 1, "the pick was not written down for this character")
	check(Window.Ranks():find("1 square set to a lower rank", 1, true) ~= nil,
		("the foot does not count the lowered square: %s"):format(Window.Ranks()))

	-- And the drag picks that rank up, by its book index.
	local before = #fixture.pickups
	row.square:GetScript("OnDragStart")(row.square)
	check(#fixture.pickups == before + 1, "a drag off the square picked nothing up")
	check(fixture.pickups[#fixture.pickups] == rend.ranks[1].index,
		("the drag picked up index %s and the square holds index %d")
			:format(tostring(fixture.pickups[#fixture.pickups]), rend.ranks[1].index))
	local kind, index, book = GetCursorInfo()
	check(kind == "spell" and index == rend.ranks[1].index and book == "spell",
		"the cursor is not holding the rank the square holds")
	ClearCursor()

	-- Back to the top: that is the default, so nothing is written down.
	row.fold:Click("LeftButton", false)
	rows = DropdownRows()
	rows[1]:Click("LeftButton", false)
	check(row.square:GetAttribute("spell") == rend.ranks[3].id, "picking the top rank did not arm the square with it")
	check(ns.dbc.spellRanks.Rend == nil, "the top rank was written down as a pick")

	-- A pick already on the character is what the window opens on.
	ns.dbc.spellRanks.Rend = 2
	Window.Paint()
	check(row.square:GetAttribute("spell") == rend.ranks[2].id,
		("a saved pick of rank two armed the square with %s"):format(tostring(row.square:GetAttribute("spell"))))
	ns.dbc.spellRanks.Rend = nil
	Window.Paint()
end

----------------------------------------------------------------------
-- The other tab, and a passive
----------------------------------------------------------------------

do
	check(Window.View(FURY), "the second tab would not come up")
	check(Window.Viewing() == FURY, "the window is not on the second tab")
	local enrage, at = Spell(FURY, "Enrage")
	local row = Window.Row(at)
	check(row ~= nil and row:IsShown(), "Enrage has no row")
	check(row.square:GetAttribute("type") == nil, "a passive's square is armed to cast")
	check(not row.fold:IsShown(), "a passive has a fold-out")
	check(row.rank:GetText() == enrage.ranks[1].label, ("the word under a passive reads %s"):format(tostring(row.rank:GetText())))

	local before = #fixture.pickups
	row.square:GetScript("OnDragStart")(row.square)
	check(#fixture.pickups == before, "a drag off a passive picked something up")

	check(not Window.View(3), "a tab the book does not have was drawn")
	Window.View(GENERAL)
end

----------------------------------------------------------------------
-- A fight
----------------------------------------------------------------------

do
	local rend, at = Spell(GENERAL, "Rend")
	local row = Window.Row(at)
	local realLockdown = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end

	row.fold:Click("LeftButton", false)
	local rows = DropdownRows()
	rows[3]:Click("LeftButton", false)
	check(row.square:GetAttribute("spell") == rend.ranks[3].id,
		"a rank picked in a fight reached the square before the fight ended")
	check(row.rank:GetText() == "Rank 1", "the label did not follow a pick made in a fight")
	check(Window.Ranks():find("lower rank", 1, true) ~= nil, "the count does not see a pick made in a fight")

	check(not Window.Hide(), "the window was hidden by Lua in a fight")
	check(Window.Shown(), "the window went down in a fight")

	_G.InCombatLockdown = realLockdown
	fire("PLAYER_REGEN_ENABLED")
	check(row.square:GetAttribute("spell") == rend.ranks[1].id,
		("after the fight the square is armed with %s"):format(tostring(row.square:GetAttribute("spell"))))

	row.fold:Click("LeftButton", false)
	DropdownRows()[1]:Click("LeftButton", false)
	check(ns.dbc.spellRanks.Rend == nil, "the pick was not put back")
end

----------------------------------------------------------------------
-- The key
----------------------------------------------------------------------

do
	_G.WarriorKitBindings.TOGGLESPELLBOOK = { "P" }
	fire("UPDATE_BINDINGS")
	ns.BlizzHide.Apply()

	local key = Window.Key()
	check(key ~= nil, "there is no secure button behind the spell book key")
	check(key:GetRegisteredClicks()["AnyDown"] == true,
		"the key button is not registered on the edge a binding fires")
	check(type(key:GetAttribute("_onclick")) == "string",
		"the key button carries no snippet, so a fight is still a shut window")
	check(key:GetFrameRef("window") == frame, "the snippet was handed the wrong window")
	check(GetBindingAction("P", true) == ("CLICK %s:LeftButton"):format(Window.KeyName()),
		"the P key never reached the secure button")
	check(Blizz.KeyText() == "P", ("the book calls its own key %s"):format(Blizz.KeyText()))
end

----------------------------------------------------------------------
-- Blizzard's own
----------------------------------------------------------------------

do
	check(Blizz.Caged(), "Blizzard's spell book was left on the screen with this one switched on")
	check(_G.SpellBookFrame:GetParent() == _G.WarriorKitAttic, "Blizzard's spell book is not in the attic")

	Window.Hide()
	local presses = #H.spellbookKey.books
	_G.ToggleSpellBook("spell")
	check(Window.Shown(), "the P key did not open this window")
	check(#H.spellbookKey.books == presses, "the P key reached Blizzard's own toggle as well as this window")
	_G.ToggleSpellBook("spell")
	check(not Window.Shown(), "the P key did not close this window again")

	-- The pet's book is the one page this window does not draw, and asking
	-- for it is answered with a sentence rather than with this window.
	_G.ToggleSpellBook("pet")
	check(not Window.Shown(), "asking for the pet's book opened the spell book")

	ns.db.hideBlizzSpellbook = false
	ns.BlizzHide.Apply()
	check(not Blizz.Caged(), "unticking the switch left the frame caged")
	check(_G.SpellBookFrame:GetParent() ~= _G.WarriorKitAttic, "unticking the switch left the frame in the attic")
	_G.ToggleSpellBook("spell")
	check(#H.spellbookKey.books == presses + 1, "with the switch off the P key did not reach Blizzard's toggle")
	check(GetBindingAction("P", true) == "TOGGLESPELLBOOK", "with the switch off the P key is still on the secure button")
	_G.SpellBookFrame:Hide()
	ns.db.hideBlizzSpellbook = true
	ns.BlizzHide.Apply()
	check(Blizz.Caged(), "ticking the switch again did not cage the frame")

	local feature
	for _, entry in ipairs(ns.features) do
		if entry.name == "spellbook" then
			feature = entry
		end
	end
	check(feature ~= nil, "no part called spellbook is registered")
	if feature then
		check(feature.switch and feature.switch.key == "spellbook" and feature.panel ~= nil,
			"the spell book has no switch for On and off to draw")
		feature.switch.apply(false)
		check(not Window.Shown(), "turning the part off left the window up")
		check(not Blizz.Caged(), "turning the part off left Blizzard's frame caged")
		feature.switch.apply(true)
		check(Blizz.Caged(), "turning the part back on did not cage Blizzard's frame")
	end
end

----------------------------------------------------------------------
-- The trainer
----------------------------------------------------------------------

-- The trainer sells the rank the book was greying out, and the client says
-- the book changed. The row gains a rank without anybody opening the window.
do
	Window.Show()
	local _, at = Spell(GENERAL, "Battle Shout")
	local row = Window.Row(at)
	fixture.entries[7].kind = "SPELL"
	fire("SPELLS_CHANGED")
	local shout = Spell(GENERAL, "Battle Shout")
	check(shout ~= nil and #shout.ranks == 3, "a rank sold by the trainer did not appear under its spell")
	check(row.square:GetAttribute("spell") == 6192,
		("after the trainer the square is armed with %s and the new rank is 6192"):format(tostring(row.square:GetAttribute("spell"))))
	check(row.rank:GetText() == "Rank 3", ("after the trainer the rank reads %s"):format(tostring(row.rank:GetText())))

	fixture.entries[7].kind = "FUTURESPELL"
	fire("SPELLS_CHANGED")
	check(#Spell(GENERAL, "Battle Shout").ranks == 2, "the fixture was not put back")
end

Window.Show()
print(("spell book %s; %s; Blizzard's %s"):format(Window.Describe(), Window.Ranks(), Blizz.Describe()))
Window.Hide()
