-- The buff nag's page
--
-- Where the drag is. The row is drawn again on the options page, as the two
-- lines it will draw, and what you do to it is what Cooldowns/Panel.lua's
-- section already checks on the cooldown row: a spell off the spellbook lands
-- on the line it was dropped on, a square dragged off turns up under the row,
-- a right click under the row puts it back, and a bare hand, which cannot ride
-- the cursor, still lands on the square the button came up over.
--
-- And the click. A nag square is the one thing on screen you are certain to be
-- looking at when you decide a nag is wrong, so it opens the window on the
-- row's own page rather than on whatever page the window was last left on.
--
-- Its own chunk rather than the tail of 30-buff-nag.lua, because that file was
-- at the harness's own ceiling for names and lines, and the page is a subject
-- of its own. It reads what that section left behind: an orc warrior, both
-- hands bare, in a fight.

local H = ...
local frames, own, inCombat = H.frames, H.own, H.inCombat
local ns, check = H.ns, H.check

local Upkeep, Nag = ns.Upkeep, ns.BuffNag

local ticker
for _, f in ipairs(frames) do
	if f.scripts.OnUpdate and f.origin:match("Buffs/Nag") then
		ticker = f
	end
end

local function tick()
	ticker.scripts.OnUpdate(ticker, 0.2)
end

----------------------------------------------------------------------
-- The drag
----------------------------------------------------------------------

do
	local Page = ns.BuffPanel
	local BOOK = _G.WarriorKitSpellBookIds
	local baseline = Upkeep.Count()

	local window = ns.UI.Windows[1]
	for index = 1, #window.groups do
		local group = window.groups[index]
		for section = 1, #group.sections do
			if group.sections[section].title == "What it watches" then
				window.rail:Select(index)
				ns.Options.SelectSection(section)
			end
		end
	end
	ns.Options.Refresh()
	check(Page.Square(1) ~= nil, "the page built no squares to drag")

	local function drop(w, book)
		_G.WarriorKitCarrySpell(book, "spell")
		w.button.scripts.OnReceiveDrag(w.button)
	end

	local function held(key)
		for index = 1, Upkeep.Ceiling() + 2 do
			local w = Page.Square(index)
			if w and w.entry and w.entry.key == key then
				return w
			end
		end
		return nil
	end

	-- Rend, which no class puts on the row, onto the empty square at the end of
	-- the in line. The out line takes the first `out` squares and one empty one,
	-- so the in line's empty square is one past its own entries after that.
	local REND = BOOK[1]
	local out, fight = Upkeep.Split()
	drop(Page.Square(out + 1 + fight + 1), 1)
	tick()
	local rend = Upkeep.Owner(REND)
	check(rend ~= nil and Upkeep.LineOf(rend) == Upkeep.IN,
		"a spell dragged out of the spellbook onto the in line is not on it")
	check(Upkeep.Count() == baseline + 1,
		("the drop left %d entries of %d"):format(Upkeep.Count(), baseline + 1))
	check(#Upkeep.Extra() == 1, "the drop did not put the spell on the list you keep")
	check(_G.GetCursorInfo() == nil, "the drop left the spell on the cursor")

	-- The same spell onto the out line: it moves, nothing is added.
	drop(Page.Square(1), 1)
	tick()
	check(Upkeep.LineOf(rend) == Upkeep.OUT, "the square did not move to the line it was dropped on")
	check(Upkeep.Count() == baseline + 1 and #Upkeep.Extra() == 1,
		"dragging a square between the lines added it a second time")

	-- Dragged off. Nothing on this client puts a spell on the cursor, so the
	-- square is remembered, the button comes up over nothing, and the entry
	-- stays off the row and under it.
	local off = held(rend.key)
	check(off ~= nil, "the page is not holding the square the row is")
	off.button.scripts.OnDragStart(off.button)
	off.button.scripts.OnDragStop(off.button)
	tick()
	check(Upkeep.Count() == baseline, "a square dragged off the row is still on it")
	local under
	for index = 1, Upkeep.ShelfCount() do
		under = Upkeep.Shelved(index).key == rend.key and index or under
	end
	check(under ~= nil, "a square dragged off the row is nowhere under it either")

	-- Right clicked under the row, it goes back to the line it was on.
	local back = Page.Shelved(under)
	back.button.scripts.OnClick(back.button, "RightButton")
	tick()
	check(Upkeep.Count() == baseline + 1 and Upkeep.LineOf(rend) == Upkeep.OUT,
		"right clicking a square under the row did not put it back on its line")

	-- And a bare hand, which cannot ride the cursor at all, dragged onto the
	-- square under the mouse on the in line. Answered under GetMouseFoci, the
	-- name this client may carry instead of GetMouseFocus.
	local hand = held("mainhand")
	check(hand ~= nil, "the main hand is not on the page")
	local foci = _G.GetMouseFoci
	_G.GetMouseFoci = function() return { held("racial").button } end
	hand.button.scripts.OnDragStart(hand.button)
	hand.button.scripts.OnDragStop(hand.button)
	_G.GetMouseFoci = foci
	tick()
	check(Upkeep.LineOf(Upkeep.ByWord("weapon")) == Upkeep.IN,
		"a hand dragged onto the in line did not land on it")
	Upkeep.Place("mainhand", Upkeep.OUT)

	Upkeep.Remove(REND)
	Nag.Apply()
	tick()
	ns.Options.Refresh()
	check(Upkeep.Count() == baseline and #Upkeep.Extra() == 0,
		("forgetting the dragged spell left %d entries of %d"):format(Upkeep.Count(), baseline))
	ns.Options.Hide()
end

----------------------------------------------------------------------
-- A click on a square
--
-- The square is where you are looking when you decide a nag is wrong, and
-- the page it is switched off on is nine groups away. Left button, on the
-- way up, and the window opens on that page rather than on whatever it was
-- last left on.
----------------------------------------------------------------------

inCombat.player = nil
own.main = false
tick()
check(Nag.Shown() > 0, "nothing is drawn to click")
local window = ns.UI.Windows[1]
ns.Options.Hide()
local press = Nag.Icon(1):GetScript("OnMouseUp")
check(press ~= nil, "a nag square has no click")
if press then
	press(Nag.Icon(1), "LeftButton")
end
check(window.frame:IsShown(), "clicking a square did not open the options window")
check(window.header.text:GetText() == "Missing buffs",
	"the window opened on " .. tostring(window.header.text:GetText()) .. " rather than the row's page")
ns.Options.Hide()

-- Where the lists live: all three on the character, for the reason the
-- switch list already was. A shield one shaman drags on is not a fact about
-- the account's warrior.
check(ns.dbc.buffExtra ~= nil and ns.dbc.buffLine ~= nil,
	"the flask list and the lines are not in the character table")
check(ns.db.buffExtra == nil and ns.db.buffRacial == nil,
	"an account key the row no longer reads is still registered")

print(("page   %d entries on the page over two lines, %d under it, and a click that opens %q")
	:format(Upkeep.Count(), Upkeep.ShelfCount(), "Missing buffs"))
