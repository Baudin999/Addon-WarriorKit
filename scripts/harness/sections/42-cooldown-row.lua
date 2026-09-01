-- The cooldown row
--
-- Five questions, and the first two are the ones that make this a class part
-- rather than a warrior part.
--
-- Is the row built out of the registry. The list this character draws is
-- whatever Class/<yours>.lua wrote down, so every count below is measured
-- against that file rather than written out here, and the section runs
-- unchanged on all five class shapes. A warrior draws four, a mage up to eight,
-- a hunter none at all, and none of those numbers appears in this file.
--
-- Do the three filters each drop a square on their own. A spell the client
-- cannot name, a spell this character has not learned, and a switch you turned
-- off are three different reasons for an empty place on the row and each one is
-- asserted separately, because a row that dropped everything would pass any one
-- of them.
--
-- Does a trinket get on the row for the right reason. The client is what
-- decides: an item with a use effect answers GetItemSpell and one you merely
-- wear answers nothing, so both are worn here and exactly one of them takes a
-- square. That call is reached through the loose global rather than through
-- C_Item, which is the fallback half of ns.ItemSpell's probe.
--
-- Is the row on screen when it should be. It is up for the whole fight, up
-- after one while something is still recovering, and gone otherwise, which is
-- three states rather than the two the buff nag has.
--
-- And does the tick stay free. Nothing here allocates, and what a countdown
-- costs is measured rather than argued about: the timer string is only built on
-- the ticks where the number behind it moved.

local H = ...
local PLAYER_CLASS, CHURN, frames = H.PLAYER_CLASS, H.CHURN, H.frames
local own, worn, inCombat = H.own, H.worn, H.inCombat
local itemLink, advance = H.itemLink, H.advance
local ns, fire, check = H.ns, H.fire, H.check

local Cooldowns, Row = ns.Cooldowns, ns.CooldownRow

local ticker
for _, f in ipairs(frames) do
	if f.scripts.OnUpdate and f.origin:match("Cooldowns/Row") then
		ticker = f
	end
end
check(ticker ~= nil, "the cooldown row registered no ticker")

local function tick()
	ticker.scripts.OnUpdate(ticker, 0.2)
end

-- What this spec brought, which is what every count below is measured against.
--
-- Two lists now and one number. The row draws the rotation cooldowns as big
-- squares along the top and the long ones as smaller squares docked under them,
-- so a count of squares is a count of both, and the filters below are asserted
-- against the long list because that is the one every class file fills in.
local FAST = ns.Class.Of("rotation") or {}
local LISTED = ns.Class.Of("cooldowns") or {}
local BOTH = #FAST + #LISTED

local function rebuild()
	fire("SPELLS_CHANGED")
	tick()
end

----------------------------------------------------------------------
-- The list is the class file's
----------------------------------------------------------------------

ns.db.locked = true
ns.db.cooldowns = true
ns.db.cooldownIdle = false
inCombat.player = false
worn[13], worn[14] = nil, nil
rebuild()

check(Cooldowns.Count() == BOTH,
	("a %s was given %d squares and its class file lists %d over the two layers")
		:format(PLAYER_CLASS, Cooldowns.Count(), BOTH))

-- The rotation entries lead the list and every one of them is tagged, which is
-- what the row reads to decide which line a square goes on and how big it is.
-- Getting the order wrong would draw a long cooldown at rotation size on the
-- top line, which looks deliberate and is not.
for index = 1, Cooldowns.Count() do
	local rotation = Cooldowns.Layer(index) == Cooldowns.ROTATION
	check(rotation == (index <= #FAST),
		("square %d is on the %s line and the first %d squares are the rotation")
			:format(index, rotation and "rotation" or "docked", #FAST))
end

-- Every drawn entry carries a name this client answered for and an id it
-- resolved to, because a square with neither is a square with no picture and
-- nothing to ask the cooldown of.
for index = 1, Cooldowns.Count() do
	local entry = Cooldowns.Entry(index)
	check(entry.name ~= nil,
		("square %d is on the row with no name"):format(index))
	check(entry.id ~= nil or entry.slot ~= nil,
		("square %d resolved to no spell and is not a trinket"):format(index))
end

-- A class with nothing listed is a supported class and says why rather than
-- drawing an empty frame.
if BOTH == 0 then
	check(Cooldowns.Refusal() ~= nil,
		("a %s draws no row and gives no reason"):format(PLAYER_CLASS))
	check(Cooldowns.Refusal():find(ns.Class.Label(), 1, true) ~= nil,
		("the refusal on a %s does not name the class: %s")
			:format(PLAYER_CLASS, Cooldowns.Refusal()))
end

----------------------------------------------------------------------
-- The three filters
----------------------------------------------------------------------

if #LISTED > 0 then
	local first = LISTED[1]

	-- An entry with two ids is one button under two names, which is what
	-- Bloodlust and Heroism are and what an Ice Block filed under two numbers
	-- is. Losing one of them has to leave the square alone, and that is
	-- asserted before the square is taken away, because a row that dropped an
	-- entry on the first missing id would pass the test below on its own.
	if #first.spells > 1 then
		own.unknown[first.spells[1]] = true
		rebuild()
		check(Cooldowns.Count() == BOTH,
			("%s has %d ids and lost its square to one of them")
				:format(first.key, #first.spells))
	end

	-- Not learned. A talent nobody spent a point on, which is most of what
	-- separates one warrior from another at the same level.
	for index = 1, #first.spells do
		own.unknown[first.spells[index]] = true
	end
	rebuild()
	check(Cooldowns.Count() == BOTH - 1,
		("an unlearned %s left %d squares of %d")
			:format(first.key, Cooldowns.Count(), BOTH))
	for index = 1, #first.spells do
		own.unknown[first.spells[index]] = nil
	end
	rebuild()
	check(Cooldowns.Count() == BOTH, "learning it back did not put the square back")

	-- Switched off, which is per character and is the only one of the three you
	-- can reach from the panel.
	Cooldowns.SetWatched(first.key, false)
	tick()
	check(Cooldowns.Count() == BOTH - 1,
		("switching %s off left %d squares of %d")
			:format(first.key, Cooldowns.Count(), BOTH))
	local silent, names = Cooldowns.Silent()
	check(silent == 1 and names ~= "",
		("a switched off entry is not reported anywhere: %d, %q"):format(silent, names))
	Cooldowns.SetWatched(first.key, true)
	tick()
	check(Cooldowns.Count() == BOTH, "switching it back on did not put the square back")

	-- A word that belongs to another class is named as such rather than falling
	-- through to the bare on|off toggle, which would switch the whole row off
	-- and report that it had done something else.
	local other
	for token, def in pairs(ns.Class.All()) do
		if token ~= PLAYER_CLASS then
			for index = 1, #(def.cooldowns or {}) do
				other = other or def.cooldowns[index].key
			end
		end
	end
	if other and not Cooldowns.ByWord(other) then
		check(Cooldowns.Elsewhere(other) ~= nil,
			("%s belongs to no class this addon knows"):format(other))
	end
end

----------------------------------------------------------------------
-- The ones you add yourself, and where they sit
--
-- Three questions, and none of them is answerable off the class file, which is
-- what makes this block different from everything above it.
--
-- Does a spell you typed the id of get a square, and does it keep it. It is the
-- one entry on the row that is not filtered by IsSpellKnown, because that call
-- says no to a rank you have not trained and to anything an item casts, so a
-- square you asked for by number going away without a word is the failure this
-- asserts against.
--
-- Does moving one move it. Along its own line, never past the end of it, and
-- never into the other line by accident.
--
-- And does the row still lay out. The rotation entries lead the list whatever
-- you rearrange, because Row.lua counts along one line until the tag changes
-- and starts the other, so an entry out of place there is a long cooldown drawn
-- at rotation size on the top line.
--
-- Everything here is put back at the end, because this is the middle of the
-- section and every count below it is the class file's again.
----------------------------------------------------------------------

do
	local MINE = 500001
	local KEY = "spell" .. MINE
	local baseline = Cooldowns.Count()

	local added, said = Cooldowns.Add(MINE)
	tick()
	check(added, ("a spell of your own was refused: %s"):format(tostring(said)))
	check(Cooldowns.Count() == baseline + 1,
		("adding one of your own left %d squares of %d")
			:format(Cooldowns.Count(), baseline + 1))

	-- Where one of yours lands, which is the end of the docked line and stays
	-- that way until you move it: a square appearing in the middle of a row you
	-- already know the shape of is one you have to find before you can read it.
	--
	-- Measured against the whole list rather than against what is drawn, because
	-- that is the list the panel shows and the one the move buttons walk. An
	-- empty trinket slot is on it and is not on the row.
	local function Place()
		local list = Cooldowns.All()
		for index = 1, #list do
			if list[index].key == KEY then
				return index
			end
		end
		return nil
	end

	local whole = Cooldowns.All()
	check(Place() == #whole,
		("one of your own landed at place %s of %d rather than at the end")
			:format(tostring(Place()), #whole))
	check(whole[#whole].layer == Cooldowns.LONG,
		"one of your own landed on the rotation line")

	-- The three refusals, each said rather than swallowed.
	check(not Cooldowns.Add(MINE), "the same spell went on the row twice")
	check(not Cooldowns.Add(900001),
		"a spell this client cannot name went on the row")
	check(not Cooldowns.Add("brambleweed"),
		"a word that is not a number went on the row")

	-- The same three things through the slash words, because the dispatcher is
	-- where a word it does not know falls through to the bare on|off toggle,
	-- switches the whole row off and reports that it did something else.
	SlashCmdList.WARRIORKIT("cooldowns add 500002")
	check(Cooldowns.ByWord("spell500002") ~= nil,
		"/wk cooldowns add put nothing on the row")
	SlashCmdList.WARRIORKIT("cooldowns line spell500002")
	check(Cooldowns.ByWord("spell500002").layer == Cooldowns.ROTATION,
		"/wk cooldowns line left the square on the line it was already on")
	SlashCmdList.WARRIORKIT("cooldowns drop 500002")
	check(Cooldowns.ByWord("spell500002") == nil,
		"/wk cooldowns drop left it on the row")
	check(ns.db.cooldowns,
		"one of the new words fell through and switched the whole row off")

	-- Not learned, and kept anyway. The opposite answer from the class file's
	-- entries, which is asserted above, and the reason is that this one is not a
	-- guess about your character.
	own.unknown[MINE] = true
	rebuild()
	check(Cooldowns.Count() == baseline + 1,
		"a spell you added by id lost its square to IsSpellKnown")
	own.unknown[MINE] = nil
	rebuild()

	-- Along its own line, and not off the end of it.
	local at = Place()
	if at > 1 and whole[at - 1].layer == Cooldowns.LONG then
		check(Cooldowns.Move(KEY, -1), "a square with a neighbour refused to move")
		check(Place() == at - 1,
			("it was moved left and is at place %s"):format(tostring(Place())))
		check(Cooldowns.Move(KEY, 1), "it refused to move back")
		check(Place() == at, "moving it back did not put it back")
	end
	check(not Cooldowns.Move(KEY, 1),
		"the last square on a line moved off the end of it")

	-- The other line, which is the same act on one of yours and on a cooldown
	-- your class listed, and the invariant the row is laid out on.
	Cooldowns.SetLine(KEY, Cooldowns.ROTATION)
	tick()
	local moved
	for index = 1, Cooldowns.Count() do
		if Cooldowns.Entry(index).key == KEY then
			moved = index
		end
	end
	check(moved ~= nil and Cooldowns.Layer(moved) == Cooldowns.ROTATION,
		"a square sent to the top line is still on the docked one")
	local broken = 0
	for index = 2, Cooldowns.Count() do
		if Cooldowns.Layer(index) == Cooldowns.ROTATION
			and Cooldowns.Layer(index - 1) == Cooldowns.LONG then
			broken = broken + 1
		end
	end
	check(broken == 0,
		("%d rotation squares are drawn after a docked one, and the row lays both"
			.. " lines out in one walk"):format(broken))

	-- And it is drawn at the size of the line it moved to, which is the whole
	-- reading of the two lines and the only thing on screen that says which of
	-- them a square is on. Against a square that stayed on the docked line,
	-- where this character has one to compare against.
	local docked
	for index = 1, Cooldowns.Count() do
		if Cooldowns.Layer(index) == Cooldowns.LONG then
			docked = index
		end
	end
	inCombat.player = true
	tick()
	if docked then
		check(Row.Icon(moved):GetWidth() > Row.Icon(docked):GetWidth(),
			"a square on the top line is drawn no bigger than one on the docked line")
	end
	inCombat.player = false

	Cooldowns.ResetRow()
	tick()
	check(Cooldowns.Count() == baseline,
		("putting the row back left %d squares of %d")
			:format(Cooldowns.Count(), baseline))
	check(#Cooldowns.Mine() == 0, "putting the row back kept one of your own")
end

----------------------------------------------------------------------
-- Arranging it by hand
--
-- The page draws the row as it will look and you drag the squares around it,
-- which is four claims and not one of them can be settled by reading the code.
--
-- Does a spell dragged out of the spellbook land on the line and at the place
-- it was dropped at. This client answers a dragged spell with a spellbook index
-- and the book it came out of, and the row counts by id, so the id has to come
-- back off the book: a page that read the index as an id would put some other
-- spell on the row and look exactly like a page that worked.
--
-- Does a spell the row already knows about move rather than arrive twice, which
-- is the whole of the difference between dragging a square and adding one.
--
-- Does a square dragged off the row turn up under it, where it can be dragged
-- back. That is what replaced the tick box per entry.
--
-- And does the mouse follow the picture: a square the page is not using takes
-- no click, and every gesture works on the client that answers for the frame
-- under the cursor under the other of its two names.
--
-- Everything here is put back at the end, because every count below it is the
-- class file's again.
----------------------------------------------------------------------

do
	local Page = ns.CooldownPanel
	local BOOK = _G.WarriorKitSpellBookIds
	local baseline = Cooldowns.Count()

	-- Standing on the page, because the window lays out the section you are
	-- looking at and no other. That is the state a drag happens in and it is not
	-- an arrangement for the test: a square nobody can see is a square nobody
	-- can drop anything on.
	local window = ns.UI.Windows[1]
	for index = 1, #window.groups do
		local group = window.groups[index]
		for section = 1, #group.sections do
			if group.sections[section].title == "Which cooldowns" then
				window.rail:Select(index)
				ns.Options.SelectSection(section)
			end
		end
	end
	ns.Options.Refresh()
	check(Page.Square(1) ~= nil, "the page built no squares to drag")

	local square = Page.Square

	-- One gesture, in the two halves the client sends: what is on the cursor,
	-- and the drag landing on a square. The button carries the scripts, because
	-- that is the frame the widget layer enables the mouse on.
	local function drop(w, book)
		_G.WarriorKitCarrySpell(book, "spell")
		w.button.scripts.OnReceiveDrag(w.button)
	end

	-- Which square on the page is holding one entry. Walked rather than worked
	-- out, because the pool runs the top line first and then the docked one, and
	-- a test that recomputed that arithmetic would pass on its own copy of it.
	local function held(key)
		for index = 1, Cooldowns.Ceiling() + 2 do
			local w = Page.Square(index)
			if w and w.entry and w.entry.key == key then
				return w
			end
		end
		return nil
	end

	local function place(key)
		local fast = Cooldowns.Split()
		for index = 1, Cooldowns.Count() do
			if Cooldowns.Entry(index).key == key then
				return index, index <= fast and Cooldowns.ROTATION or Cooldowns.LONG
			end
		end
		return nil
	end

	-- A spell off the spellbook, onto the front of the top line.
	local REND = BOOK[1]
	drop(square(1), 1)
	tick()
	local at, line = place("spell" .. REND)
	check(at == 1 and line == Cooldowns.ROTATION,
		("a spell dragged out of the spellbook onto the front of the top line is"
			.. " at %s on the %s line"):format(tostring(at), tostring(line)))
	check(Cooldowns.Count() == baseline + 1,
		("the drop left %d squares of %d"):format(Cooldowns.Count(), baseline + 1))
	check(_G.GetCursorInfo() == nil, "the drop left the spell on the cursor")

	-- The same spell again, onto the docked line this time. One square moves;
	-- nothing is added.
	local fast = Cooldowns.Split()
	drop(square(fast + 2), 1)
	tick()
	at, line = place("spell" .. REND)
	check(line == Cooldowns.LONG, "the square did not move to the line it was dropped on")
	check(Cooldowns.Count() == baseline + 1,
		("dragging one square to the other line left %d squares of %d")
			:format(Cooldowns.Count(), baseline + 1))

	-- Dragged off. Nothing on this client puts a spell on the cursor, which is
	-- the trinket's case too: the square is remembered, the button comes up over
	-- nothing, and the entry stays off the row.
	local off = held("spell" .. REND)
	check(off ~= nil, "the page is not holding the square the row is")
	off.button.scripts.OnDragStart(off.button)
	off.button.scripts.OnDragStop(off.button)
	tick()
	check(place("spell" .. REND) == nil, "a square dragged off the row is still on it")
	check(Cooldowns.Count() == baseline,
		("dragging one off left %d squares of %d"):format(Cooldowns.Count(), baseline))

	local under
	for index = 1, Cooldowns.ShelfCount() do
		under = Cooldowns.Shelved(index).key == "spell" .. REND and index or under
	end
	check(under ~= nil, "a square dragged off the row is nowhere under it either")

	-- A square the page is not using takes no mouse. The button is anchored over
	-- the square and used to be parented past it, so hiding one left a live
	-- invisible button on the page, holding the rect the hidden square still
	-- had, over whatever square it came to rest on. That reads as one spell you
	-- cannot drag and the rest working, and nothing on screen can show it.
	--
	-- Asserted on the parent because the parent is the mechanism: the stub has
	-- no hit testing to catch the click that landed on nothing, and IsVisible is
	-- false for every frame on a page whose window is shut.
	local spare = Page.Square(Cooldowns.Count() + 3)
	check(spare ~= nil, "the pool is not built past the two lines and their ends")
	if spare then
		check(not spare:IsShown(), "a square past the end of the row is drawn")
		check(spare.button:GetParent() == spare,
			"the button on a square is parented past it, so hiding the square"
				.. " leaves the mouse behind on the page")
	end

	-- And back, onto the square the button came up over, which is the half of
	-- the gesture that can only be answered by the frame under the cursor. Asked
	-- under GetMouseFoci, the name this client may carry instead: read under one
	-- name only, a trinket could not be moved between the lines at all.
	local foci = _G.GetMouseFoci
	_G.GetMouseFoci = function() return { square(1).button } end
	local w = Page.Shelved(under)
	w.button.scripts.OnDragStart(w.button)
	w.button.scripts.OnDragStop(w.button)
	_G.GetMouseFoci = foci
	tick()
	at, line = place("spell" .. REND)
	check(at == 1 and line == Cooldowns.ROTATION,
		("dragged back onto the front of the top line it is at %s on the %s line")
			:format(tostring(at), tostring(line)))

	-- Right click, which is the same two acts in one press and the only pair
	-- that survives a client answering neither name for the frame under the
	-- cursor. Off from a square on the row, back on from one under it.
	local w2 = held("spell" .. REND)
	w2.button.scripts.OnClick(w2.button, "RightButton")
	tick()
	check(place("spell" .. REND) == nil, "right clicking a square left it on the row")
	local back = Page.Shelved(1)
	check(back and back.entry ~= nil, "nothing is under the row to put back")
	back.button.scripts.OnClick(back.button, "RightButton")
	tick()
	check(place("spell" .. REND) ~= nil,
		"right clicking a square under the row did not put it back on")

	Cooldowns.ResetRow()
	Cooldowns.SetWatched("spell" .. REND, true)
	tick()
	ns.Options.Refresh()
	check(Cooldowns.Count() == baseline,
		("putting the row back after the drags left %d squares of %d")
			:format(Cooldowns.Count(), baseline))
end

----------------------------------------------------------------------
-- What one square is doing
----------------------------------------------------------------------

if #LISTED > 0 then
	local entry = Cooldowns.Entry(1)

	local status = Cooldowns.State(1)
	check(status == "ready", ("a spell off cooldown reads as %s"):format(status))

	-- A global sweep is not a cooldown. Every square in the addon follows this
	-- rule and it is worth asserting on the one row where the whole point is the
	-- number: a row that counted the global would put 1.5 on every square every
	-- time you pressed anything.
	own.cooldowns[entry.id] = { _G.GetTime(), 1.5 }
	tick()
	status = Cooldowns.State(1)
	check(status == "ready", ("a global sweep read as %s"):format(status))

	own.cooldowns[entry.id] = { _G.GetTime(), 180 }
	tick()
	local start, duration
	status, start, duration = Cooldowns.State(1)
	check(status == "cooldown", ("a three minute wait reads as %s"):format(status))
	check(duration == 180, ("the swipe was handed %s seconds"):format(tostring(duration)))
	check(start == _G.GetTime(), "the swipe was handed the wrong start")

	-- Minutes, because a thirty minute cooldown on a 27 pixel square used to
	-- draw four digits of false precision. The whole ladder is walked here,
	-- because what a countdown has to get right is the seams: it rounds down, so
	-- 1m means a minute or more, and there is a label at every step from three
	-- minutes to the last tenth of a second.
	check(Row.Icon(1).timer:GetText() == "3m",
		("a three minute wait reads %q on the square"):format(Row.Icon(1).timer:GetText()))

	advance(61)
	tick()
	check(Row.Icon(1).timer:GetText() == "1m",
		("just under two minutes reads %q"):format(Row.Icon(1).timer:GetText()))

	advance(60)
	tick()
	check(Row.Icon(1).timer:GetText() == "59",
		("just under a minute reads %q"):format(Row.Icon(1).timer:GetText()))

	advance(55)
	tick()
	check(Row.Icon(1).timer:GetText() == "4.0",
		("four seconds left reads %q"):format(Row.Icon(1).timer:GetText()))

	own.cooldowns[entry.id] = nil
	tick()

	-- The window it opened, which the client will not answer for: a cooldown
	-- starts the moment you press the ability and says nothing about whether
	-- the fifteen seconds you pressed it for are still running. The aura is the
	-- only source, and it is read on an event rather than on the tick.
	own.auras[1] = { name = entry.name, icon = "Interface\\Icons\\A" }
	fire("UNIT_AURA", "player")
	tick()
	local _, _, _, active = Cooldowns.State(1)
	check(active == true, ("%s is running and the square does not say so"):format(entry.name))

	own.auras[1] = nil
	fire("UNIT_AURA", "player")
	tick()
	_, _, _, active = Cooldowns.State(1)
	check(active == false, "the window stayed open after the aura came off")
end

----------------------------------------------------------------------
-- The trinkets
--
-- Both slots are filled and exactly one of them takes a square, which is the
-- client answering rather than a list in the addon.
----------------------------------------------------------------------

local before = Cooldowns.Count()
worn[13] = itemLink("Bloodlust Brooch")
worn[14] = itemLink("Mark of Tyranny")
fire("PLAYER_EQUIPMENT_CHANGED")
tick()

check(Cooldowns.Count() == before + 1,
	("two trinkets, one of them passive, added %d squares")
		:format(Cooldowns.Count() - before))

local pressed = Cooldowns.Entry(Cooldowns.Count())
check(pressed.name == "Increased Strength",
	("the trinket square is named %q rather than after its use effect")
		:format(tostring(pressed.name)))
check(Cooldowns.Worn(13):find("Bloodlust Brooch", 1, true) ~= nil,
	("the panel reads trinket 1 as %q"):format(Cooldowns.Worn(13)))
check(Cooldowns.Worn(14):find("worn rather than pressed", 1, true) ~= nil,
	("the panel reads a passive trinket as %q"):format(Cooldowns.Worn(14)))

-- A worn item answers a different call from a spell, which is the one thing
-- about a trinket square that cannot be read off a spell id.
own.worn[13] = { _G.GetTime(), 120 }
tick()
local trinketStatus = Cooldowns.State(Cooldowns.Count())
check(trinketStatus == "cooldown",
	("a trinket on cooldown reads as %s"):format(trinketStatus))
own.worn[13] = nil
tick()

worn[14] = nil
fire("PLAYER_EQUIPMENT_CHANGED")
tick()
check(Cooldowns.Count() == before + 1,
	"taking a passive trinket off moved the row")

----------------------------------------------------------------------
-- When it is on the screen
----------------------------------------------------------------------

local DRAWS = Cooldowns.Count() > 0

inCombat.player = false
tick()
check((Row.Mode() == "quiet") or not DRAWS,
	("everything is ready out of combat and the row is %s"):format(tostring(Row.Mode())))

inCombat.player = true
tick()
check(Row.Mode() == (DRAWS and "fight" or "quiet"),
	("in combat the row is %s"):format(tostring(Row.Mode())))
check(Row.Shown() == Cooldowns.Count(),
	("%d squares drawn of %d on the list"):format(Row.Shown(), Cooldowns.Count()))

-- Out of a fight with something still recovering, which is the pull-or-wait
-- question and the only reason to look at the row between fights.
inCombat.player = false
own.worn[13] = { _G.GetTime(), 120 }
tick()
check(Row.Mode() == (DRAWS and "waiting" or "quiet"),
	("something is still recovering and the row is %s"):format(tostring(Row.Mode())))
own.worn[13] = nil
tick()

ns.db.cooldownIdle = true
Row.Apply()
tick()
check(Row.Mode() == (DRAWS and "waiting" or "quiet"),
	("idle on and the row is %s out of combat"):format(tostring(Row.Mode())))
ns.db.cooldownIdle = false
Row.Apply()

own.dead = true
inCombat.player = false
tick()
check(Row.Mode() == "quiet", "a corpse was drawn a cooldown row")
own.dead = false

ns.db.cooldowns = false
Row.Apply()
tick()
check(Row.Mode() == "quiet" and Row.Shown() == 0,
	"the row is switched off and still drawing")

-- A hidden row lays nothing out, which is a real bug rather than a hypothetical
-- one: the tick compares what it drew last against what it would draw now, and
-- comparing the list's length against the number of squares on the screen makes
-- those two disagree forever while the row is quiet. What that costs is a full
-- relayout of every square, ten times a second, for as long as you are out of a
-- fight. The row compares the list's rebuild count instead, which also catches
-- the rebuild that swaps one entry for another and leaves the length alone.
-- Counted rather than trusted, the way 04-ability-square.lua counts the writes
-- a redraw makes.
local laid = 0
if DRAWS then
	local square = Row.Icon(1)
	local wasPoint, wasHide = square.SetPoint, square.Hide
	square.SetPoint = function() laid = laid + 1 end
	-- Hide as well as SetPoint, and Hide is the one that catches it: a row that
	-- lays itself out while it is quiet takes the branch that hides every square
	-- rather than the one that places them, so a counter on SetPoint alone
	-- watches the half that is not running.
	square.Hide = function() laid = laid + 1 end
	for _ = 1, 20 do
		tick()
	end
	square.SetPoint, square.Hide = wasPoint, wasHide
end
check(laid == 0, ("a hidden row laid its squares out %d times over 20 ticks"):format(laid))

ns.db.cooldowns = true
Row.Apply()

----------------------------------------------------------------------
-- What a square says to the mouse
----------------------------------------------------------------------

inCombat.player = true
tick()

if DRAWS then
	local square = Row.Icon(1)
	local enter = square:GetScript("OnEnter")
	check(enter and square:GetScript("OnLeave"),
		"a cooldown square has no hover scripts, so it can never say what it means")
	ns.UI.Tooltip.Close()
	enter(square)
	check(ns.UI.Tooltip.IsShown(), "hovering a cooldown square opened nothing")
	local title = ns.UI.Tooltip.Text(1)
	check(tostring(title) == Cooldowns.Entry(1).name,
		("the tooltip is titled %q and the square is %q")
			:format(tostring(title), Cooldowns.Entry(1).name))
	ns.UI.Tooltip.Close()
end

----------------------------------------------------------------------
-- The grid, at every zoom
----------------------------------------------------------------------

local shipped = ns.db.cooldownZoom
local off = 0
for _, zoom in ipairs({ 1, 2, 3 }) do
	ns.db.cooldownZoom = zoom
	Row.Apply()
	tick()
	for slot = 1, Row.Shown() do
		local px = ns.UI.Pixel(Row.Icon(slot))
		for _, point in ipairs(Row.Icon(slot).points or {}) do
			local x, y = (point[4] or 0) / px, (point[5] or 0) / px
			if math.abs(x - math.floor(x + 0.5)) > 1e-6
				or math.abs(y - math.floor(y + 0.5)) > 1e-6 then
				off = off + 1
			end
		end
	end
end
check(off == 0, ("%d square anchors were off a whole pixel"):format(off))
ns.db.cooldownZoom = shipped
Row.Apply()
tick()

----------------------------------------------------------------------
-- What the tick costs
--
-- With the clock moving and something on cooldown, which is the row's only
-- moving state.
--
-- Five ticks are run before the count starts and they are the point of the
-- measurement rather than a way around it. The one allocation on this path is
-- the countdown's string, which UI/Ability.lua builds only on the ticks where
-- the number behind it moved; the tick that first drew this square is one of
-- those and every tick after it is the steady state. What the gate is for is
-- the steady state going non-zero, which is what a write nobody guarded looks
-- like.
----------------------------------------------------------------------

if DRAWS then
	own.worn[13] = { _G.GetTime(), 600 }
end
for _ = 1, 5 do
	advance(0.1)
	tick()
end
collectgarbage("collect")
collectgarbage("stop")
local start = collectgarbage("count")
for _ = 1, 50 do
	advance(0.1)
	tick()
end
local churned = collectgarbage("count") - start
collectgarbage("restart")
own.worn[13] = nil
check(churned < CHURN.cooldowns,
	("the cooldown row churned %.2f KB over 50 ticks, gate is %.2f")
		:format(churned, CHURN.cooldowns))

----------------------------------------------------------------------

-- The trinket comes off and the fight ends, because this is the last section
-- and what it leaves behind is what anybody reading a later scene would find.
-- The row itself is left drawn, which is what the print below describes.
inCombat.player = true
tick()

print(("cooldowns %d drawn for a %s, %d rotation and %d long off the class file and %d trinket, %s; %s; %.2f KB per 50 ticks, gate is %.2f")
	:format(Row.Shown(), ns.Class.Spec.Says(), #FAST, #LISTED,
		Cooldowns.Count() - BOTH, tostring(Row.Mode()), Cooldowns.Describe(),
		churned, CHURN.cooldowns))
