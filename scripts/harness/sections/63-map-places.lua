-- The places on the map
--
-- One claim: the flight masters, innkeepers, vendors and trainers Questie can
-- draw are a checklist in this addon's panel, and a tick on it is a tick in
-- Questie's own menu, which is what puts the place on this map.
--
-- Its own section rather than part of 54-world-map.lua because that file is at
-- its line limit and the subject is not the same. That file asks whether a
-- frame Questie drew reaches the picture; this one asks whether this addon can
-- make Questie draw one, which is the other direction through the same seam.
--
-- **The flip is a toggle, and that is the whole of what can go wrong.** Questie
-- hands over one function per kind of place and it flips the state rather than
-- setting it, so a caller that calls it on a box already ticked unticks it.
-- Every set here is made twice, and the second is checked on Questie's own
-- profile rather than on this addon's reading of it, because the reading is
-- built from the same entries and would agree with itself.
--
-- **The map is painted on the click.** On the stub the frames are all there
-- at once, so the count after a switch is the count with the place on it. In
-- the game a kind of NPC arrives over a few ticks and lands on the next
-- repaint; Map/Feature.lua says why that is not a ticker.

local H = ...
local ns, check = H.ns, H.check
local worldmap, quests = H.worldmap, H.quests

local Places, Pins, Window = ns.MapPlaces, ns.MapPins, ns.MapWindow

local WESTFALL = 1436

local chat = _G.DEFAULT_CHAT_FRAME.AddMessage
local heard = {}
_G.DEFAULT_CHAT_FRAME.AddMessage = function(_, text)
	heard[#heard + 1] = tostring(text)
end

local function say(input)
	heard = {}
	_G.SlashCmdList.WARRIORKIT(input)
end

local function said(what)
	for index = 1, #heard do
		if heard[index]:find(what, 1, true) then
			return true
		end
	end
	return false
end

-- Whether a marker of that name is on the zone. Pins.Of is what the window
-- paints from, so this is the picture as far as anything above the chart can
-- see it.
local function drawn(name, map)
	local points = Pins.Of(map or WESTFALL)
	for _, point in ipairs(points) do
		if point.name == name then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- The list
----------------------------------------------------------------------

local rows = Places.List()
check(#rows == 6,
	("Questie offers six kinds of place and the list has %d"):format(#rows))

local labels = {}
for index, row in ipairs(rows) do
	labels[index] = row.label
end
check(table.concat(labels, ", ")
	== "Flight Master, Innkeeper, Mailbox, Food, Blacksmithing, Cooking",
	("the list came out as %q"):format(table.concat(labels, ", ")))
check(rows[4] and rows[4].group == "vendor" and rows[5] and rows[5].group == "trainer",
	"the rows do not say which of Questie's three lists they came out of")

check(Places.On("Flight Master") == true, "a kind Questie has on reads off")
check(Places.On("Innkeeper") == false, "a kind Questie has off reads on")
check(Places.On("Moonwell") == nil, "a kind Questie does not offer answered a state")

check(Places.Describe() == "6 kinds of place Questie can draw, 2 of them on",
	("the reading says %q"):format(Places.Describe()))

----------------------------------------------------------------------
-- The flip
----------------------------------------------------------------------

quests.standing.map = WESTFALL
Window.Show()
Window.Select(WESTFALL)
check(not drawn("Innkeeper Heather"), "the innkeeper was on the map before she was switched on")

check(Places.Set("Innkeeper", true) == true, "switching a kind on did not say it changed")
check(worldmap.townsfolk["Innkeeper"] == true, "the switch did not reach Questie's profile")
check(Places.On("Innkeeper") == true, "the reading did not follow the switch")
check(drawn("Innkeeper Heather"), "the innkeeper is not on the map after being switched on")

-- The same again, which is the trap. A set is not a flip, and the profile is
-- what says so.
check(Places.Set("Innkeeper", true) == false, "switching on a kind already on said it changed")
check(worldmap.townsfolk["Innkeeper"] == true, "switching on a kind already on switched it off")

check(Places.Set("Innkeeper", false) == true, "switching a kind off did not say it changed")
check(worldmap.townsfolk["Innkeeper"] == false, "switching off did not reach Questie's profile")
check(not drawn("Innkeeper Heather"), "the innkeeper stayed on the map after being switched off")

check(Places.Set("Moonwell", true) == nil, "a kind Questie does not offer was switched")

----------------------------------------------------------------------
-- The repaint
----------------------------------------------------------------------

-- Through the word rather than Places.Set, because the word is what goes
-- through Map/Feature.lua and the repaint is that file's, not Places'.
local before = Window.Drawn()
say("map places Innkeeper on")
check(Window.Drawn() == before + 1,
	("the map has %d markers after the switch where it had %d before the innkeeper")
		:format(Window.Drawn(), before))
say("map places Innkeeper off")
check(Window.Drawn() == before,
	"the map still has the innkeeper after she was switched off")

----------------------------------------------------------------------
-- The page
----------------------------------------------------------------------

-- One tick box per kind, filed under a section of their own, and reachable by
-- the finder under Questie's own label. Two labels rather than one because the
-- first is on Questie's townsfolk list and the second is a vendor, and the
-- hairline between them is the only thing that tells the two apart.
local page, boxes = nil, {}
for _, entry in ipairs(ns.Options.Indexed()) do
	if entry.section.title == "Places" then
		page = entry.section
		boxes[entry.label] = true
	end
end
check(page ~= nil, "the panel has no Places page")
check(page and page.group.name == "Chores",
	("the Places page is under %s rather than Chores"):format(page and page.group.name or "nothing"))
check(boxes["Flight Master"] and boxes["Food"],
	"the page is missing one of the two tick boxes looked for")
check(ns.Options.Find("Innkeeper") >= 1, "the finder cannot reach a place by Questie's label")

----------------------------------------------------------------------
-- The word
----------------------------------------------------------------------

say("map places")
check(said("Flight Master: on"), "the word did not list a kind that is on")
check(said("Innkeeper: off"), "the word did not list a kind that is off")

say("map places Flight Master off")
check(worldmap.townsfolk["Flight Master"] == false,
	"a two word kind followed by off did not reach Questie")
check(said("Flight Master is off"), "and the word did not say so")
say("map places Flight Master off")
check(said("already was"), "switching off a kind already off did not say it already was")
say("map places Flight Master on")
check(worldmap.townsfolk["Flight Master"] == true, "the kind was not switched back on")

say("map places Moonwell on")
check(said("no kind of place called"), "a kind Questie does not offer was not refused by name")
say("map places Innkeeper")
check(said("takes a kind of place and then on or off"),
	"a kind with no switch after it was not refused")

----------------------------------------------------------------------
-- A Questie with no menu
----------------------------------------------------------------------

worldmap.Menuless(true)
check(#Places.List() == 0, "a Questie without the builders offered places")
check(Places.On("Innkeeper") == nil, "a Questie without the builders answered a state")
check(Places.Describe() == "Questie is not answering, so there are no places to switch on",
	("without the builders the reading says %q"):format(Places.Describe()))
say("map places")
check(said("Questie is not answering"), "the word did not say Questie is not answering")
worldmap.Menuless(false)
check(#Places.List() == 6, "the builders did not come back")

_G.DEFAULT_CHAT_FRAME.AddMessage = chat
Window.Hide()

print(("places %s"):format(Places.Describe()))
