-- The buff nag's page
--
-- Where the drag is. The row is drawn again on the options page, as the two
-- lines it will draw, and the lines are sets: a spell off the spellbook lands
-- on the line it was dropped on and stays on any other it was on, a square
-- dragged onto the other line is on both, a square dragged off comes off that
-- line alone, and off its last line it turns up under the row where a right
-- click puts it back.
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
--
-- Five claims. A spell off the spellbook dropped on a line lands on that line.
-- The same spell dropped on the other line is on both, not moved. A square
-- dragged from one line onto the other is on both too, because nothing rides
-- the cursor out of a square here and the button coming up over a line is
-- what a drag means. Dragged off, it comes off the line it was lifted from and
-- no other, and off its last line it is under the row. Right clicked under the
-- row it goes back where it shipped.
----------------------------------------------------------------------

do
	local Page = ns.BuffPanel
	local BOOK = _G.WarriorKitSpellBookIds
	local baseline = Upkeep.Count()

	-- Open, and standing on the page. A square is in step only while the page it
	-- is on is showing, because a row on a page nobody is looking at is left
	-- alone, so the window has to be up before any of this means anything.
	ns.Options.Show()
	local window = ns.Options.Window()
	for index = 1, #window.groups do
		local group = window.groups[index]
		for section = 1, #group.sections do
			if group.sections[section].title == "Missing buffs" then
				window.rail:Select(index)
				ns.Options.SelectSection(section)
			end
		end
	end
	check(Page.Square(1) ~= nil, "the page built no squares to drag")

	local function drop(w, book)
		_G.WarriorKitCarrySpell(book, "spell")
		w.button.scripts.OnReceiveDrag(w.button)
	end

	-- The square holding one entry on one line.
	local function held(key, line)
		for index = 1, Upkeep.Ceiling() + 2 do
			local w = Page.Square(index)
			if w and w.entry and w.entry.key == key and w.line == line then
				return w
			end
		end
		return nil
	end

	-- A drag from one square to wherever the button comes up, answered under
	-- GetMouseFoci, the name this client may carry instead of GetMouseFocus.
	local function drag(w, onto)
		local foci = _G.GetMouseFoci
		_G.GetMouseFoci = function() return { onto and onto.button or nil } end
		w.button.scripts.OnDragStart(w.button)
		w.button.scripts.OnDragStop(w.button)
		_G.GetMouseFoci = foci
	end

	-- The empty square at the end of a line, which is one past that line's own.
	local function tail(line)
		local out, fight = Upkeep.Split()
		if line == Upkeep.OUT then
			return Page.Square(out + 1)
		end
		return Page.Square(out + 1 + fight + 1)
	end

	-- Rend, which no class puts on the row, onto the end of the in line.
	local REND = BOOK[1]
	drop(tail(Upkeep.IN), 1)
	tick()
	local rend = Upkeep.Owner(REND)
	check(rend ~= nil and Upkeep.Lines(rend) == Upkeep.IN,
		"a spell dragged out of the spellbook onto the in line is not on it alone")
	check(Upkeep.Count() == baseline + 1,
		("the drop left %d entries of %d"):format(Upkeep.Count(), baseline + 1))
	check(#Upkeep.Extra() == 1, "the drop did not put the spell on the list you keep")
	check(_G.GetCursorInfo() == nil, "the drop left the spell on the cursor")

	-- The same spell onto the out line: on both now, and still one entry.
	drop(tail(Upkeep.OUT), 1)
	tick()
	check(Upkeep.Lines(rend) == Upkeep.BOTH,
		"a spell dropped on the second line came off the first: " .. tostring(Upkeep.Lines(rend)))
	check(Upkeep.Count() == baseline + 1 and #Upkeep.Extra() == 1,
		"dragging a spell onto the second line added it a second time")
	check(held(rend.key, Upkeep.OUT) ~= nil and held(rend.key, Upkeep.IN) ~= nil,
		"an entry on both lines is not drawn on both")

	-- Dragged off the out line, onto nothing. Off that line and on the other.
	drag(held(rend.key, Upkeep.OUT), nil)
	tick()
	check(Upkeep.Lines(rend) == Upkeep.IN and Upkeep.Watched(rend.key),
		"dragging a square off one line took it off the other too")

	-- Dragged from the in line onto the out line: on both again, because a drag
	-- onto a line puts the square there and takes nothing away.
	drag(held(rend.key, Upkeep.IN), tail(Upkeep.OUT))
	tick()
	check(Upkeep.Lines(rend) == Upkeep.BOTH,
		"dragging a square onto the other line did not put it there as well")

	-- Right click takes it off that line only.
	local w = held(rend.key, Upkeep.IN)
	w.button.scripts.OnClick(w.button, "RightButton")
	tick()
	check(Upkeep.Lines(rend) == Upkeep.OUT, "right clicking a square took it off both lines")

	-- Off its last line, into the tray.
	drag(held(rend.key, Upkeep.OUT), Page.Shelved(1))
	tick()
	check(not Upkeep.Watched(rend.key), "a square dragged off its last line is still on the row")
	local under
	for index = 1, Upkeep.ShelfCount() do
		under = Upkeep.Shelved(index).key == rend.key and index or under
	end
	check(under ~= nil, "a square dragged off its last line is nowhere under the row")

	-- Right clicked under the row, it goes back where it shipped: yours ship on
	-- the out line.
	local back = Page.Shelved(under)
	back.button.scripts.OnClick(back.button, "RightButton")
	tick()
	check(Upkeep.Watched(rend.key) and Upkeep.Lines(rend) == Upkeep.OUT,
		"right clicking a square under the row did not put it back where it shipped")

	-- A square the page is not using takes no mouse. The button is parented to
	-- the square, so hiding one hides the mouse with it.
	local spare = Page.Square(Upkeep.Ceiling() + 2)
	check(spare ~= nil and not spare:IsShown() and spare.button:GetParent() == spare,
		"a square past the end of the row is drawn, or its button is parented past it")

	-- And a bare hand, which cannot ride the cursor at all, from the out line
	-- onto the racial's square on the in line: on both.
	drag(held("mainhand", Upkeep.OUT), held("racial", Upkeep.IN))
	tick()
	check(Upkeep.Lines(Upkeep.ByWord("weapon")) == Upkeep.BOTH,
		"a hand dragged onto the in line did not land on it")
	Upkeep.Place("mainhand", nil)

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
local window = ns.Options.Window()
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
