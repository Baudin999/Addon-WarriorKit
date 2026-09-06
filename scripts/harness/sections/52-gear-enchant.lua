-- The enchant on the line under the name, and the oil on the weapon
--
-- Two different facts about one piece, written on one line of the gear page,
-- and neither of them is anywhere else on that page. A slot you forgot to
-- enchant is invisible: the item level does not move, the figure looks the
-- same, and the only way to find it in the game is to hover all nineteen.
--
-- Its own file rather than a block in 52-gear-page.lua, which is a section at
-- its own line ceiling and is a subject that keeps growing. The two are not
-- quite the same subject either: that one is what the page draws about the
-- pieces, and this is what it reads out of the client to draw it, which is a
-- tooltip scan, a call whose shape nobody has settled and a tick.
--
-- The scene is this file's own. It opens the sheet, dresses the character in
-- three enchanted pieces, puts a stone on a hand, and puts every one of those
-- back before it hands over, because 53-shipped-defaults reads a character
-- wearing what client/13-character.lua put on it.
--
-- Five things here fail silently and every one is a check below.
--
--   A name read off the link. A link carries the enchant as a number and no
--   client call turns one into a word, so a reader that took the id would print
--   an id and look like it had worked.
--
--   A scan on every repaint. Nineteen tooltips filled and read back every time
--   anything you are wearing moves costs nothing anybody can see, which is why
--   it has to be asserted rather than noticed.
--
--   The order in the right hand column. Both sides draw the same three strings
--   and only one side reads them from the disc outward.
--
--   The wash under a line that grew. It is sized off the longer of the two
--   strings, the line was two digits when that was written, and a name half on
--   a shadow and half on the grass measures perfectly.
--
--   A tick that writes every second. The number on a hand changes once a
--   minute for an hour and the tick looks at it once a second, so the guard is
--   the difference between one write a minute and sixty.
--
-- What this cannot prove: that the client's own tooltip says what the stub says
-- it says. The enchant line is modelled from ENCHANTED_TOOLTIP_LINE, which is
-- the string 2.5.6 ships, and a model that is wrong is a test that passes and a
-- row that stays blank.

local H = ...
local ns, check = H.ns, H.check

local Window, Worn = ns.CharWindow, ns.Worn

-- What the line at the foot reports.
local minutes, scanned = 0, 0

do
	Window.Show()
	local pane = Window.Pane()
	local own, swing = H.own, H.swing
	local head, neck, ring, hand
	for _, box in ipairs(pane.squares) do
		if box.entry.slot == 1 then
			head = box
		elseif box.entry.slot == 2 then
			neck = box
		elseif box.entry.slot == 11 then
			ring = box
		elseif box.entry.slot == 16 then
			hand = box
		end
	end

	-- Three enchanted pieces, one in each column and one in a hand, and the neck
	-- left bare with an enchant line seeded against it anyway. That last one is
	-- the id gate: the client would answer this tooltip happily, and the only
	-- reason the row must not print it is that the link says the piece carries
	-- no enchant, which is the answer that costs nothing to ask for.
	local ENCHANT = "+26 Agility, +20 Critical Strike and +14 Hit"
	local helmLink = H.itemLink("Lionheart Helm", 2564)
	local ringLink = H.itemLink("Band of the Eternal", 2929)
	local axeLink = H.itemLink("Arcanite Reaper", 1900)
	H.tooltips.item[helmLink] = { { "Lionheart Helm" }, { "Head, Plate" },
		{ "Enchanted: " .. ENCHANT } }
	H.tooltips.item[ringLink] = { { "Band of the Eternal" },
		{ "Enchanted: +4 All Resistances" } }
	H.tooltips.item[axeLink] = { { "Arcanite Reaper" }, { "Enchanted: Crusader" } }
	H.tooltips.item[H.worn[2]] = { { "Onyxia Tooth Pendant" },
		{ "Enchanted: +8 Stamina" } }

	H.worn[1], H.worn[11] = helmLink, ringLink
	swing.mainhand = axeLink
	-- Half an hour of sharpening stone. Rebuilt rather than trusted: the stride
	-- GetWeaponEnchantInfo answers in is counted where the buff row is built, and
	-- which shape the stub is in is whatever the section that last flipped it
	-- left behind.
	own.main, own.mainLeft = true, 1830 * 1000
	ns.Upkeep.Rebuild()
	pane:Paint()

	check((head.note:GetText() or ""):find(ENCHANT, 1, true) ~= nil,
		("the helmet is enchanted and the line under it reads %s")
			:format(tostring(head.note:GetText())))
	check((head.note:GetText() or ""):sub(1, 2) == "60",
		"the left hand column does not open on its item level, so the number is away from the disc")
	check(neck.note:GetText() == "60",
		("a piece whose link carries no enchant read one out of a tooltip anyway: %s")
			:format(tostring(neck.note:GetText())))
	scanned = 3

	-- The right hand column reads inward, so its level is the last thing on the
	-- line and lands against its own disc. Drawn the same way round on both
	-- sides, half the page's item levels would be out in the middle of it.
	local mirrored = ring.note:GetText() or ""
	check(mirrored:sub(-2) == "60",
		("the right hand column ends on %s and its disc is on the right")
			:format(tostring(mirrored)))
	check(mirrored:find("+4 All Resistances", 1, true) ~= nil,
		"the right hand row lost its enchant, so the swap dropped a string rather than reordering two")

	-- Asked again only where the link moved. The seeded text is changed under a
	-- link that did not, which is a repaint the row must not scan: nineteen
	-- scans on every paint is what the flag on the row exists to stop, and a row
	-- that rescanned would pick these words up.
	H.tooltips.item[helmLink] = { { "Lionheart Helm" }, { "Enchanted: nothing at all" } }
	pane:Paint()
	check((head.note:GetText() or ""):find(ENCHANT, 1, true) ~= nil,
		"the helmet was scanned again on a repaint that found nothing had moved")

	-- And asked the moment it does move. The same item with a different enchant
	-- on it, which is what applying one looks like from here.
	local swapped = H.itemLink("Lionheart Helm", 2565)
	H.tooltips.item[swapped] = { { "Lionheart Helm" }, { "Enchanted: +12 Stamina" } }
	H.worn[1] = swapped
	pane:Paint()
	check((head.note:GetText() or ""):find("+12 Stamina", 1, true) ~= nil,
		("the helmet was enchanted with something else and its line still reads %s")
			:format(tostring(head.note:GetText())))

	----------------------------------------------------------------------
	-- The wash under a line that got longer
	--
	-- The shadow each row's two strings are read on is as wide as the longer of
	-- them, and until now the longer was always the name. A note anchored at
	-- both ends measures at its full length however much of it the client draws,
	-- so the wash taken off the raw measurement would run out past the edge the
	-- letters are cut off at and over the figure, which is the one thing the
	-- arithmetic at the head of Character/Paperdoll.lua rules out.
	----------------------------------------------------------------------

	H.worn[1] = helmLink
	H.tooltips.item[helmLink] = { { "Lionheart Helm" }, { "Head, Plate" },
		{ "Enchanted: " .. ENCHANT } }
	pane:Paint()

	local across = head.note:GetWidth()
	local raw = head.note:GetStringWidth()
	check(raw > across,
		("the enchant fixture measures %.1f in a row %.1f wide, so nothing here is measuring the clamp")
			:format(raw, across))
	check(math.abs(head.wash:GetWidth() - (across + 48)) <= 0.01,
		("the wash came out %.1f wide and the clamped line is %.1f")
			:format(head.wash:GetWidth(), across))
	check(head.wash:GetWidth() < raw + 48,
		"the wash was sized off the line's full length rather than the part of it that is drawn")
	check(head.wash:GetWidth() <= head:GetWidth() + 4,
		"a line longer than its row washed out past the edge its letters are cut off at")

	----------------------------------------------------------------------
	-- The stone on the hand
	--
	-- The half a warrior actually watches. It runs an hour and lapses in the
	-- middle of a raid, and the page is where the minutes left are, on the three
	-- weapon rows and nowhere else.
	----------------------------------------------------------------------

	check((hand.note:GetText() or ""):find("30m", 1, true) ~= nil,
		("half an hour of sharpening stone reads %s on the main hand")
			:format(tostring(hand.note:GetText())))
	check((hand.note:GetText() or ""):find("Crusader", 1, true) ~= nil,
		"a weapon carrying both lost its permanent enchant to its temporary one")
	check(Worn.Oil(18) == nil,
		"the ranged slot answered a temporary enchant, and nothing in this expansion goes on a bow")
	check(Worn.Oil(5) == nil,
		"a piece of armour answered a temporary enchant, so the reader is not asking about a hand")

	local tick = ns.UI.Ticking("oil")
	check(tick ~= nil,
		"nothing is counting the time left down, so the figure is written once and left to go stale")

	hand.note:SetText("untouched")
	own.mainLeft = 1825 * 1000
	tick:Beat(1)
	check(hand.note:GetText() == "untouched",
		"five seconds inside the same minute rewrote the line, so the guard is on the string rather than on the number")

	own.mainLeft = 1799 * 1000
	tick:Beat(1)
	check((hand.note:GetText() or ""):find("29m", 1, true) ~= nil,
		("the minute rolled over and the line reads %s")
			:format(tostring(hand.note:GetText())))
	minutes = 29

	-- The last minute is counted in seconds, because that is the part of it
	-- anybody is watching, and it is red for the same reason.
	own.mainLeft = 45 * 1000
	tick:Beat(1)
	local last = hand.note:GetText() or ""
	check(last:find("45s", 1, true) ~= nil,
		("under a minute left and the line reads %s"):format(tostring(last)))
	check(last:find("|cff", 1, true) ~= nil,
		"a lapsing enchant is drawn in the same colour as one with an hour left on it")

	-- Nothing at all while the sheet is shut. The gear page's own frame is shown
	-- from the moment it is built and never taken down again, because it holds
	-- nineteen secure buttons and hiding one of those in a fight is a protected
	-- act, so a tick reading that flag would run all session on a page nobody
	-- can see.
	Window.Hide()
	hand.note:SetText("shut")
	own.mainLeft = 10 * 1000
	tick:Beat(1)
	check(hand.note:GetText() == "shut",
		"the tick wrote on a row nobody can see, so it is reading the row's own flag rather than the window's")
	Window.Show()

	-- Left as it was found.
	H.tooltips.item[helmLink] = nil
	H.tooltips.item[ringLink] = nil
	H.tooltips.item[axeLink] = nil
	H.tooltips.item[swapped] = nil
	H.tooltips.item[H.worn[2]] = nil
	H.worn[1] = H.itemLink("Lionheart Helm")
	H.worn[11] = H.itemLink("Band of the Eternal")
	swing.mainhand = nil
	own.main, own.mainLeft = false, 0
	pane:Paint()
	check(head.note:GetText() == "60",
		("the scene was not put back and the helmet still reads %s")
			:format(tostring(head.note:GetText())))
	check(hand.note:GetText() == "",
		("the main hand was emptied and its line still reads %s")
			:format(tostring(hand.note:GetText())))
	Window.Hide()
end

print(("enchant %d pieces read off a tooltip, one hand counted down to %dm")
	:format(scanned, minutes))
