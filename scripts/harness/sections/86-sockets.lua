-- The socketing window
--
-- Three claims, and the rest of the file is in service of them.
--
-- The window is opened by the session and not by whatever started it. Nothing
-- here calls Window.Show: it opens a session on the helmet the way the gear
-- page's shift click does, and what is asserted is that the window came up off
-- the client's own event. That is what lets a gesture this addon does not own,
-- a shift click on a bag square, land in the same window.
--
-- A gem you clicked is not a gem you socketed. The client keeps what is in the
-- hole apart from what you have put in front of it, the window has to draw the
-- second and hold the first, and only apply spends anything. So a click is
-- followed by reading the ruby that is still in the second hole, and the take
-- back is checked on the same hole.
--
-- And the bonus line is the client's answer rather than the addon's. The
-- ordering of the gem list comes off Core/Sockets.lua's colour table and the
-- sentence beside apply comes off the client's `matches`, and this file drives
-- a case where a table that had gone wrong would show up as one and not the
-- other: a purple gem, which fits a red hole and a blue one and is neither.
--
-- The client's own socketing frame is moved rather than hidden, which is the
-- merchant's argument on a different frame: hiding it is what ends the session,
-- and the window would then be drawing three empty holes.

local H = ...
local ns, check = H.ns, H.check
local CARRIED, sockets = H.CARRIED, H.sockets

local Window, Blizz = ns.SocketWindow, ns.SocketBlizzard
local CharWindow = ns.CharWindow

-- The slot the one piece with holes in it is worn in.
local HEAD = 1

----------------------------------------------------------------------
-- The scene
--
-- A fourth bag of gems, taken back at the foot of the file the way
-- 65-bag-piles.lua hands its fifth one back. Four gems and each is a different
-- answer for a red hole: a red one fits, a purple one fits, a yellow one does
-- not, and a meta fits nothing but a meta hole.
----------------------------------------------------------------------

CARRIED[3] = {
	"Rigid Dawnstone",
	"Bold Ornate Ruby",
	"Relentless Earthstorm Diamond",
	"Shifting Nightseye",
}

check(ns.Sockets.Available(), "this client has the socketing API and the addon says it has not")
check(not Window.Shown(), "the socketing window is up before anything opened a session")

-- Blizzard's own window arriving, which is what happens inside the client's own
-- handler for the event below.
sockets.arrive()

----------------------------------------------------------------------
-- The gesture
--
-- The complaint this part came out of: shift-clicking a piece with holes in it
-- did nothing, because this addon's gear page had replaced the one Blizzard
-- reads the modifier on. So the press is driven here rather than the call it
-- makes, and the same square is pressed without shift to prove the swap it used
-- to do is still what an ordinary click does.
----------------------------------------------------------------------

CharWindow.Show()
local helm
for _, box in ipairs(CharWindow.Pane().squares) do
	if box.entry.slot == HEAD then
		helm = box
	end
end
check(helm ~= nil, "no square on the gear page is the helmet")

_G.WarriorKitShift(false)
helm.button:Click("LeftButton")
check(not Window.Shown(),
	"an unmodified click on the helmet opened the socketing window instead of taking it off")

_G.WarriorKitShift(true)
helm.button:Click("LeftButton")
_G.WarriorKitShift(false)
CharWindow.Hide()

check(Window.Shown(), "a shift click on a piece with holes in it opened no window")
check(sockets.open(), "the window is up and the client has no session")

local window = Window.Frame()
check(window ~= nil, "the window is shown and there is no window")
check(_G.WarriorKitSockets ~= nil,
	"the window has no name, so escape cannot close it through UISpecialFrames")

----------------------------------------------------------------------
-- The holes
----------------------------------------------------------------------

check(ns.Sockets.Count() == 2, "the helmet has two holes and the session says otherwise")
check(window.holes[1]:IsShown() and window.holes[2]:IsShown(),
	"two holes and fewer than two squares drawn")
check(not window.holes[3]:IsShown(), "a third hole is drawn on a helmet with two")

check(ns.Sockets.Filled(2) == "Bold Living Ruby",
	"the second hole holds the ruby the gear fixture put there and the session says otherwise")
check(ns.Sockets.Filled(1) == nil, "the first hole is empty and the session says it is not")

-- The window opens pointing at the empty hole rather than at the filled one,
-- which is the whole of what you came here to do.
check(window.verdict.text:find("empty hole", 1, true) ~= nil,
	("an empty hole and the line says %q"):format(window.verdict.text))

----------------------------------------------------------------------
-- The gems
--
-- Every gem in the bags is drawn, and the ones that go in the hole you are
-- pointing at come first. The Tigerseye 04-hands.lua leaves in a bag is class 3
-- and fits nothing, and it is the one gem that must not be on the list at all.
----------------------------------------------------------------------

local carried = ns.Sockets.Gems()
check(#carried == 4, ("four gems in the bags and the walk found %d"):format(#carried))
for index = 1, #carried do
	check(carried[index].name ~= "Tigerseye",
		"a vanilla jewel that goes in no hole is on the list of gems you can socket")
end

check(window.squares[1].gem.name == "Bold Ornate Ruby"
	or window.squares[1].gem.name == "Shifting Nightseye",
	("the first square is %s, and a red hole should offer a red or a purple first")
		:format(tostring(window.squares[1].gem.name)))
check(window.squares[3].gem.name == "Rigid Dawnstone"
	or window.squares[3].gem.name == "Relentless Earthstorm Diamond",
	("the third square is %s, and the two that do not fit should be last")
		:format(tostring(window.squares[3].gem.name)))
check(window.squares[3].art:GetDesaturated(),
	"a gem that does not fit the hole is drawn as brightly as one that does")
check(not window.squares[1].art:GetDesaturated(),
	"a gem that fits the hole is drawn dimmed")

check(window.caption.text:find("fit the red hole", 1, true) ~= nil,
	("the caption reads %q"):format(window.caption.text))

----------------------------------------------------------------------
-- Putting one in
----------------------------------------------------------------------

local first = window.squares[1]
local chosenGem = first.gem.name
first:Click("LeftButton")

check(ns.Sockets.Waiting(1) == chosenGem,
	("clicking %s left %s waiting in the first hole")
		:format(chosenGem, tostring(ns.Sockets.Waiting(1))))
check(ns.Sockets.Filled(1) == nil,
	"a gem you have not paid for went into the item")
check(ns.Sockets.Filled(2) == "Bold Living Ruby",
	"putting a gem in the first hole moved what was in the second")
check(window.holes[1].wait:IsShown(),
	"a hole holding a gem you have not paid for says nothing about it")
check(window.apply:IsEnabled(),
	"a gem is waiting and apply is still off")

-- The bonus, off the client's own answer. A purple gem in a red hole matches
-- and so does a red one, so either of the two the sort could have put first
-- earns the bonus with the ruby already in the second hole.
check(window.verdict.text:find("socket bonus is yours", 1, true) ~= nil,
	("two matching gems and the line says %q"):format(window.verdict.text))

----------------------------------------------------------------------
-- Taking it back out
----------------------------------------------------------------------

window.holes[1]:Click("RightButton")
check(ns.Sockets.Waiting(1) == nil,
	"a right click on the hole left the gem waiting in it")
check(not window.holes[1].wait:IsShown(),
	"nothing is waiting and the hole still says something is")
check(not window.apply:IsEnabled(),
	"nothing is waiting and apply is still on")

----------------------------------------------------------------------
-- Paying for it
----------------------------------------------------------------------

first = window.squares[1]
chosenGem = first.gem.name
first:Click("LeftButton")
window.apply:Click("LeftButton")

check(not ns.UI.Asking(),
	"filling an empty hole asked a question, and there was nothing to destroy")
check(ns.Sockets.Filled(1) == chosenGem,
	("apply left %s in the first hole"):format(tostring(ns.Sockets.Filled(1))))
check(ns.Sockets.Waiting(1) == nil, "apply left the gem waiting as well as socketed")

----------------------------------------------------------------------
-- Replacing one, which is the press that cannot be taken back
----------------------------------------------------------------------

local replacement
for index = 1, 4 do
	local square = window.squares[index]
	if square and square:IsShown() and square.gem.name ~= chosenGem then
		replacement = square
		break
	end
end
check(replacement ~= nil, "every gem in the bags went into one hole")

if replacement then
	replacement:Click("LeftButton")
	check(window.verdict.text:find("destroys", 1, true) ~= nil,
		("a gem over a socketed one and the line says %q"):format(window.verdict.text))
	window.apply:Click("LeftButton")
	check(ns.UI.Asking() ~= nil,
		"destroying a gem you already paid for went through without a question")
	ns.UI.Answer(false)
	check(ns.Sockets.Filled(1) == chosenGem,
		"saying no to the question destroyed the gem anyway")
end

----------------------------------------------------------------------
-- The client's own window
----------------------------------------------------------------------

check(Blizz.Parked() and _G.ItemSocketingFrame:GetAlpha() == 0,
	"a session opened and the client's socketing window was on the screen")
check(_G.ItemSocketingFrame:IsShown(),
	"the client's window was hidden, which is what ends the session")

----------------------------------------------------------------------
-- Closing it
----------------------------------------------------------------------

Window.Hide()
check(not sockets.open(), "the window went down and the session is still open")
check(not Blizz.Parked(), "the session ended and the client's window is still parked")

print(("socket 2 holes, %d gems in the bags, %d squares drawn; %s")
	:format(#carried, #window.squares, Window.Describe()))
print(("socket the client's window %s"):format(Blizz.Describe()))

CARRIED[3] = nil
