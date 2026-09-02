-- The talent window
--
-- Three trees side by side replacing a window of the client's, and most of
-- this section is about the one promise the window makes: nothing to scroll.
--
-- **The size is asserted against what was drawn, not against a constant.** The
-- window is sized to the tallest tree this character has, so the check is that
-- the lowest square of the deepest tree sits inside the content area and that
-- the whole window still fits the screen at its zoom. A window that grew to
-- fit and then overflowed the monitor would pass the first and fail the
-- second.
--
-- **The lines are measured, not counted.** Four routes are drawn in the
-- fixture, one of each kind: down a column across an empty tier, along a row,
-- a diagonal with a clear short route and a diagonal whose short route is
-- blocked. Each is asserted by where its segments start and how long they
-- are, in the grid's own units, because a count of four proves nothing about
-- which way any of them went.
--
-- **Everything else is what a square cannot say about itself.** Which rim it
-- wears and why, whether a press reached the client, whether the other spec
-- refuses a press, and whether the client's own window is in the attic with
-- its key redirected.
--
-- What this cannot prove: that the client agrees about any of the ten calls
-- behind it. The stub answers what client/18-talents.lua says it answers, and
-- the two clients this addon runs on disagree about three of them, which is
-- why the older shape is stood up here for a moment rather than assumed.

local H = ...
local ns, check, state, fire = H.ns, H.check, H.state, H.fire
local model, talentTrees = H.talentModel, H.talentTrees

local Window, Read, Cost, Blizz = ns.TalentWindow, ns.TalentRead, ns.TalentCost, ns.TalentBlizzard
local Board = ns.TalentBoard
local C = ns.UI.Color

local ARMS, FURY, PROT = 1, 2, 3

local function whole(value)
	return math.abs(value - math.floor(value + 0.5)) < 1e-6
end

local function same(color, r, g, b)
	return math.abs(color[1] - r) < 1e-6 and math.abs(color[2] - g) < 1e-6
		and math.abs(color[3] - b) < 1e-6
end

-- A square's rim, read back off the texture the outline is drawn with. Section
-- 52 reads the gear squares the same way.
local function Rim(square)
	return square.edges.r, square.edges.g, square.edges.b
end

-- Every line in the box, joined, so a sentence can be looked for wherever the
-- bands put it.
local function BoxText()
	local Tooltip = ns.UI.Tooltip
	local out = {}
	for index = 1, Tooltip.Lines() or 0 do
		out[#out + 1] = Tooltip.Text(index) or ""
	end
	return table.concat(out, "\n")
end

local function Offsets(region)
	local _, _, _, x, y = region:GetPoint(1)
	return x, y
end

-- The fixture's own points in each tree, whatever the run put there. A spec
-- run gives one tree every point and the others none, which is the right
-- shape for the resolver and the wrong one for a board: every assertion below
-- is written against thirty one in the first tree, twenty in the second and
-- none in the third, and the run's own numbers go back at the foot.
local given = {}
for tab = ARMS, PROT do
	given[tab] = talentTrees.player[tab].points
end
talentTrees.player[ARMS].points = 31
talentTrees.player[FURY].points = 20
talentTrees.player[PROT].points = 0
fire("PLAYER_TALENT_UPDATE")

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

Window.Show()
local frame = _G.WarriorKitTalents
check(frame ~= nil, "the talent window was never built")
check(Window.Shown(), "the talent window would not open")
-- At its own zoom, whatever that is by now: section 53 put every window back
-- on its shipped size, so the claim here is that this one followed, not that
-- the size is one.
check(math.abs(ns.UI.Pixel(frame) * ns.Zoom("talentsZoom") - 1) < 1e-9,
	("the talent window is not at its own zoom: one pixel is %.4f units at zoom %.2f")
		:format(ns.UI.Pixel(frame), ns.Zoom("talentsZoom")))
check(whole(frame:GetWidth()) and whole(frame:GetHeight()),
	("the talent window is %.2f x %.2f, not a whole number of pixels")
		:format(frame:GetWidth(), frame:GetHeight()))
check(frame:GetHeight() * ns.Zoom("talentsZoom") <= state.SCREEN_H,
	"the talent window is taller than the screen")

for tab = ARMS, PROT do
	check(Window.Board(tab) ~= nil, ("tree %d has no board"):format(tab))
end

-- Nothing to scroll: the deepest tree is nine tiers in the fixture, and the
-- lowest square of it has to sit above the footer.
do
	check(Window.Tiers() == 9,
		("the fixture's deepest tree is nine tiers and the window sized itself for %d"):format(Window.Tiers()))
	local prot = Window.Board(PROT)
	local low = prot:At(9, 2)
	check(low ~= nil and low:IsShown(), "the ninth tier talent was not drawn")
	local _, y = Offsets(low)
	local bottom = -y + Board.SQUARE
	local room = prot.grid:GetHeight()
	check(bottom <= room + 1e-6,
		("the ninth tier ends %.0f down a grid %.0f tall"):format(bottom, room))
	local body = frame:GetHeight() - ns.UI.Metric.title - ns.UI.Metric.footer
	local used = ns.UI.Metric.pad * 2 + prot.frame:GetHeight()
	check(used <= body + 1e-6,
		("the boards need %.0f of a body %.0f tall, so something scrolls or clips"):format(used, body))
end

----------------------------------------------------------------------
-- The three boards
----------------------------------------------------------------------

do
	local arms = Window.Board(ARMS)
	check(arms.name:GetText() == talentTrees.player[1].name,
		("the first board is headed %s"):format(tostring(arms.name:GetText())))
	check(arms.points:GetText() == ("%d points"):format(talentTrees.player[1].points),
		("the first board's points read %s"):format(tostring(arms.points:GetText())))
	check(Window.Board(PROT).points:GetText() == "no points",
		("an empty tree's points read %s"):format(tostring(Window.Board(PROT).points:GetText())))

	local drawn = 0
	for index = 1, #model.trees[1] do
		local square = arms:Square(index)
		if square and square:IsShown() then
			drawn = drawn + 1
		end
	end
	check(drawn == #model.trees[1],
		("the first tree drew %d of %d talents"):format(drawn, #model.trees[1]))

	-- Where a square lands: the fixture's tier and column, at the board's
	-- pitch, off the top left of the grid.
	local impale = arms:At(4, 3)
	local x, y = Offsets(impale)
	check(x == 2 * Board.PITCH and y == -3 * Board.PITCH,
		("Impale sits at %.0f, %.0f and the fourth tier third column is %d, %d")
			:format(x, y, 2 * Board.PITCH, -3 * Board.PITCH))
end

----------------------------------------------------------------------
-- The rims and the counts
----------------------------------------------------------------------

do
	local arms = Window.Board(ARMS)
	-- Full: every rank in.
	local full = arms:At(1, 1)
	check(same(C.heading, Rim(full)), "a talent with every rank in does not wear the gold rim")
	check(full.tally:GetText() == "3/3",
		("a full talent's count reads %s"):format(tostring(full.tally:GetText())))

	-- Reachable: Mortal Strike needs Sweeping Strikes, which is full, the tier
	-- is open at thirty one points and three points are waiting.
	local ms = arms:At(7, 2)
	check(ms.learnable == true, "Mortal Strike is not reachable with its requirement met and points waiting")
	check(same(C.tick, Rim(ms)), "a reachable talent does not wear the green rim")
	check(ms.tally:GetText() == "", ("an unlearned talent's count reads %s"):format(tostring(ms.tally:GetText())))
	check(not ms.dim, "a reachable talent was greyed")

	-- Locked: the protection tree has no points, so its second tier is shut.
	local prot = Window.Board(PROT)
	local shut = prot:At(2, 1)
	check(shut.unlocked == false, "a second tier talent in an empty tree reads as open")
	check(same(C.hairline, Rim(shut)), "a locked talent does not wear the hairline rim")
	check(shut.dim == true, "a locked talent was not greyed")
	-- And its first tier is open and reachable.
	local open = prot:At(1, 1)
	check(open.learnable == true, "the first tier of an empty tree is not reachable")
end

----------------------------------------------------------------------
-- The lines, by route
----------------------------------------------------------------------

do
	local S, P, L = Board.SQUARE, Board.PITCH, 2
	local mid = math.floor((S - L) / 2)

	-- Arms: Impale straight down one tier, Mortal Strike straight down across
	-- an empty tier, Improved Execute down then over because Mace
	-- Specialization blocks the short route. Four segments.
	local arms = Window.Board(ARMS)
	check(arms:Lines() == 4, ("the first tree drew %d line segments and the fixture asks four"):format(arms:Lines()))

	local found = {}
	for index = 1, arms:Lines() do
		local line = arms:Line(index)
		local x, y = Offsets(line)
		found[#found + 1] = { x = x, y = y, w = line:GetWidth(), h = line:GetHeight(),
			met = same(C.tick, line.r, line.g, line.b) }
	end
	local function has(x, y, w, h, met)
		for _, line in ipairs(found) do
			if line.x == x and line.y == y and line.w == w and line.h == h and line.met == met then
				return true
			end
		end
		return false
	end
	-- Impale, (3,3) to (4,3): a column line from under the third tier square.
	check(has(2 * P + mid, -2 * P - S, L, P - S, true),
		"Impale's line does not run straight down from Deep Wounds")
	-- Mortal Strike, (5,2) to (7,2): the same, two tiers long.
	check(has(P + mid, -4 * P - S, L, 2 * P - S, true),
		"Mortal Strike's line does not run down the column across the empty tier")
	-- Improved Execute, (5,2) to (6,3): down the second column to the sixth
	-- tier's centre line, then over to the square.
	check(has(P + mid, -4 * P - S, L, P - S + mid + L, true),
		"Improved Execute's line does not go down first with the short route blocked")
	check(has(P + mid, -5 * P - mid, 2 * P - (P + mid), L, true),
		"Improved Execute's line does not turn over along the sixth tier")

	-- Fury: two along a row, one from a full requirement and one from an empty
	-- one, Flurry over then down with a clear route, Bloodthirst down. Five
	-- segments, and every one whose requirement is not full is grey.
	local fury = Window.Board(FURY)
	check(fury:Lines() == 5, ("the second tree drew %d line segments and the fixture asks five"):format(fury:Lines()))
	found = {}
	for index = 1, fury:Lines() do
		local line = fury:Line(index)
		local x, y = Offsets(line)
		found[#found + 1] = { x = x, y = y, w = line:GetWidth(), h = line:GetHeight(),
			met = same(C.tick, line.r, line.g, line.b) }
	end
	-- Along tier two from Unbridled Wrath's right edge to Improved Berserker
	-- Rage, green because Unbridled Wrath is full.
	check(has(P + S, -P - mid, P - S, L, true),
		"a requirement along the row was not drawn between the two squares")
	-- Along tier three from Improved Cleave to Piercing Howl, grey because
	-- Improved Cleave is empty.
	check(has(S, -2 * P - mid, P - S, L, false),
		"a requirement along the row from an empty talent was not drawn grey")
	-- Flurry: over along tier four from Enrage to the third column's centre,
	-- then down to the sixth tier.
	check(has(P + S, -3 * P - mid, (2 * P + mid + L) - (P + S), L, false),
		"Flurry's line does not go over first with the short route clear")
	check(has(2 * P + mid, -3 * P - mid, L, 2 * P - mid, false),
		"Flurry's line does not turn down the third column")
end

----------------------------------------------------------------------
-- The hover
----------------------------------------------------------------------

do
	H.tooltips.talent[H.tooltipKey(1, 1)] = {
		{ "Improved Heroic Strike" },
		{ "Reduces the cost of your Heroic Strike ability by 3 rage points." },
	}
	local arms = Window.Board(ARMS)
	local square = arms:At(1, 1)
	square:GetScript("OnEnter")(square)
	check(ns.UI.Tooltip.IsShown(), "hovering a talent opened no tooltip")
	local text = BoxText()
	check(text:find("Reduces the cost", 1, true) ~= nil,
		"the client's own description of the talent is not in the box")
	check(text:find("Rank 3 of 3", 1, true) ~= nil, "the rank line is not in the box")
	check(text:find("Every rank learned", 1, true) ~= nil, "a full talent's box does not say so")
	square:GetScript("OnLeave")(square)
	check(not H.tipSettle(), "the tooltip stayed up after the pointer left the square")

	-- A locked talent says what it needs, and a talent with an unmet
	-- requirement names it.
	local prot = Window.Board(PROT)
	local shut = prot:At(2, 1)
	shut:GetScript("OnEnter")(shut)
	check(BoxText():find("Needs 5 points in", 1, true) ~= nil,
		"a locked talent's box does not say how many points open its tier")
	shut:GetScript("OnLeave")(shut)
	H.tipSettle()

	local fury = Window.Board(FURY)
	local howl = fury:At(3, 2)
	howl:GetScript("OnEnter")(howl)
	check(BoxText():find("Needs every rank of Improved Cleave", 1, true) ~= nil,
		"a talent whose requirement is empty does not name it")
	howl:GetScript("OnLeave")(howl)
	H.tipSettle()
end

----------------------------------------------------------------------
-- The press
----------------------------------------------------------------------

do
	local arms = Window.Board(ARMS)
	local before = #model.learned
	local ms = arms:At(7, 2)
	ms:GetScript("OnClick")(ms)
	check(#model.learned == before + 1, "pressing a reachable talent did not reach the client")
	local call = model.learned[#model.learned]
	check(call and call.tab == 1 and call.index == 17,
		("the press asked for tab %s index %s"):format(tostring(call and call.tab), tostring(call and call.index)))
	-- The client spent it and said so, and the square now reads as full.
	ms = arms:At(7, 2)
	check(ms.rank == 1 and ms.tally:GetText() == "1/1",
		("after the press Mortal Strike reads %s"):format(tostring(ms.tally:GetText())))
	check(same(C.heading, Rim(ms)), "a talent just filled does not wear the gold rim")
	check(model.unspent == 2, ("the client has %d points waiting after one press"):format(model.unspent))

	-- A locked one is refused without a call.
	local shut = Window.Board(PROT):At(2, 1)
	shut:GetScript("OnClick")(shut)
	check(#model.learned == before + 1, "pressing a locked talent reached the client")

	-- With nothing waiting, nothing is reachable and the whole tree greys.
	local had = model.unspent
	model.unspent = 0
	fire("CHARACTER_POINTS_CHANGED")
	local rend = arms:At(1, 3)
	check(rend.learnable == false and rend.dim == true,
		"with no points waiting an unlearned talent still reads as reachable")
	rend:GetScript("OnClick")(rend)
	check(#model.learned == before + 1, "pressing with no points waiting reached the client")
	model.unspent = had
	fire("CHARACTER_POINTS_CHANGED")
end

----------------------------------------------------------------------
-- The older client
--
-- No C_SpecializationInfo, and a GetTalentInfo that answers a run of values.
-- The same boards have to come out of it.
----------------------------------------------------------------------

do
	local modern, legacy = _G.C_SpecializationInfo, _G.GetTalentInfo
	_G.C_SpecializationInfo = nil
	_G.GetTalentInfo = model.Legacy
	Read.ForgetTipShape()
	check(Read.Describe():find("GetTalentInfo", 1, true) ~= nil,
		("on the older client the reader says it is %s"):format(Read.Describe()))

	Window.Paint()
	local arms = Window.Board(ARMS)
	local drawn = 0
	for index = 1, #model.trees[1] do
		local square = arms:Square(index)
		if square and square:IsShown() then
			drawn = drawn + 1
		end
	end
	check(drawn == #model.trees[1],
		("on the older client the first tree drew %d of %d talents"):format(drawn, #model.trees[1]))
	check(arms:At(7, 2) ~= nil and arms:At(7, 2).name == "Mortal Strike",
		"on the older client the talents are not where the newer one put them")
	check(arms:Lines() == 4,
		("on the older client the first tree drew %d line segments"):format(arms:Lines()))
	check(Window.Tiers() == 9, "on the older client the window lost a tier")

	_G.C_SpecializationInfo, _G.GetTalentInfo = modern, legacy
	Read.ForgetTipShape()
	Window.Paint()
end

----------------------------------------------------------------------
-- Two specs
----------------------------------------------------------------------

do
	local strip = Window.Build().content
	check(strip ~= nil, "the window has no content frame")

	-- One group: no strip, and the boards start under the title.
	local arms = Window.Board(ARMS)
	local _, y = Offsets(arms.frame)
	check(y == -ns.UI.Metric.pad,
		("with one spec the boards start %.0f down and the padding is %d"):format(-y, ns.UI.Metric.pad))
	local shortHeight = _G.WarriorKitTalents:GetHeight()

	model.groups = 2
	Window.Paint()
	_, y = Offsets(arms.frame)
	check(y < -ns.UI.Metric.pad, "with two specs the boards did not move down under the strip")
	check(_G.WarriorKitTalents:GetHeight() > shortHeight, "with two specs the window did not grow for the strip")
	check(Window.Viewing() == 1, ("the window opened on group %d rather than the live one"):format(Window.Viewing()))

	-- The other group: empty trees, nothing reachable, a press refused.
	check(Window.View(2), "the second spec could not be viewed")
	check(Window.Viewing() == 2, "viewing the second spec did not take")
	local full = arms:At(1, 1)
	check(full.rank == 0 and full.tally:GetText() == "",
		("in the second spec a talent full in the first reads %s"):format(tostring(full.tally:GetText())))
	check(full.learnable == false, "a talent in the spec you are not standing in reads as reachable")
	local before = #model.learned
	full:GetScript("OnClick")(full)
	check(#model.learned == before, "pressing a talent in the other spec reached the client")
	check(arms.points:GetText() == "no points",
		("the other spec's first tree reads %s"):format(tostring(arms.points:GetText())))

	-- Making it live goes through the client and comes back as an event.
	local frame = Window.Build()
	check(frame ~= nil, "no window to press activate on")
	local pressed = #model.activated
	-- The button is the one control on the window with that label.
	local button
	for _, child in ipairs({ strip:GetChildren() }) do
		if child.text and child.text:GetText() == "Make this spec live" then
			button = child
		end
	end
	check(button ~= nil and button:IsShown(), "the activate button is not up while viewing the other spec")
	if button then
		button:GetScript("OnClick")(button)
	end
	check(#model.activated == pressed + 1 and model.activated[#model.activated] == 2,
		"the activate button did not ask the client for the second group")
	check(model.active == 2 and Window.Viewing() == 2,
		("after activating, the client is on %d and the window on %d"):format(model.active, Window.Viewing()))
	check(button and not button:IsShown(), "the activate button stayed up on the live spec")

	-- And back, through the client rather than the window.
	_G.C_SpecializationInfo.SetActiveSpecGroup(1)
	check(Window.Viewing() == 1, "the window did not follow the client back to the first group")
	model.groups = 1
	Window.Paint()
	check(_G.WarriorKitTalents:GetHeight() == shortHeight, "with one spec again the window did not shrink back")
end

----------------------------------------------------------------------
-- What unlearning costs
----------------------------------------------------------------------

do
	check(ns.dbc.respecCount == 0, "a fresh character has paid to unlearn")
	check(Cost.Describe():find("1g", 1, true) ~= nil,
		("before any quote the schedule's first price is not 1g: %s"):format(Cost.Describe()))

	-- The trainer's dialog goes up with five gold in it, and is cancelled.
	fire("CONFIRM_TALENT_WIPE", 50000)
	local quote, when = Cost.Quote()
	check(quote == 50000 and type(when) == "number", "the trainer's quote was not written down")
	check(Cost.Describe():find("5g", 1, true) ~= nil,
		("the quote is not in the sentence: %s"):format(Cost.Describe()))
	check(Cost.Brief():find("5g", 1, true) ~= nil, ("the short form does not carry the quote: %s"):format(Cost.Brief()))
	fire("PLAYER_TALENT_UPDATE")
	check(Cost.Count() == 0, "a cancelled dialog was counted as a reset")

	-- Quoted again and taken: every tree empties.
	fire("CONFIRM_TALENT_WIPE", 50000)
	local kept = {}
	for tab = ARMS, PROT do
		kept[tab] = talentTrees.player[tab].points
		talentTrees.player[tab].points = 0
	end
	fire("PLAYER_TALENT_UPDATE")
	check(Cost.Count() == 1, ("a reset was counted %d times"):format(Cost.Count()))
	check(Cost.Next() == 50000, ("after one reset the schedule says %d copper next"):format(Cost.Next()))
	for tab = ARMS, PROT do
		talentTrees.player[tab].points = kept[tab]
	end
	fire("PLAYER_TALENT_UPDATE")

	local foot = Window.Build().footer
	check(foot ~= nil, "the window has no footer")
	ns.dbc.respecCount, ns.dbc.respecQuote, ns.dbc.respecQuoteAt = 0, false, false
end

----------------------------------------------------------------------
-- Blizzard's own
----------------------------------------------------------------------

do
	check(Blizz.Caged(), "Blizzard's talent frame was left on the screen with this one switched on")
	check(_G.PlayerTalentFrame:GetParent() == _G.WarriorKitAttic, "Blizzard's talent frame is not in the attic")

	Window.Hide()
	local presses = H.talentKey.presses
	_G.ToggleTalentFrame()
	check(Window.Shown(), "the N key did not open this window")
	check(H.talentKey.presses == presses, "the N key reached Blizzard's own toggle as well as this window")
	_G.ToggleTalentFrame()
	check(not Window.Shown(), "the N key did not close this window again")

	-- The switch off: the frame comes back and so does the key.
	ns.db.hideBlizzTalents = false
	ns.BlizzHide.Apply()
	check(not Blizz.Caged(), "unticking the switch left the frame caged")
	check(_G.PlayerTalentFrame:GetParent() ~= _G.WarriorKitAttic, "unticking the switch left the frame in the attic")
	_G.ToggleTalentFrame()
	check(H.talentKey.presses == presses + 1, "with the switch off the N key did not reach Blizzard's toggle")
	_G.PlayerTalentFrame:Hide()
	ns.db.hideBlizzTalents = true
	ns.BlizzHide.Apply()
	check(Blizz.Caged(), "ticking the switch again did not cage the frame")

	-- The part off: this window goes and Blizzard's is back, whatever the
	-- hide switch says.
	local feature
	for _, entry in ipairs(ns.features) do
		if entry.name == "talents" then
			feature = entry
		end
	end
	check(feature ~= nil, "no part called talents is registered")
	if feature then
		feature.switch.apply(false)
		check(not Window.Shown(), "turning the part off left the window up")
		check(not Blizz.Caged(), "turning the part off left Blizzard's frame caged")
		feature.switch.apply(true)
		check(Blizz.Caged(), "turning the part back on did not cage Blizzard's frame")
	end
end

Window.Show()
print(("talents %s; %s; %d tiers; Blizzard's %s"):format(
	Window.Describe(), Window.Trees(), Window.Tiers(), Blizz.Describe()))
Window.Hide()

for tab = ARMS, PROT do
	talentTrees.player[tab].points = given[tab]
end
fire("PLAYER_TALENT_UPDATE")
