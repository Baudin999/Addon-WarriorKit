-- The loot feed
--
-- 31-feeds.lua is what a feed is: a ring, an offset into it, rows that do not
-- move and a tooltip on the row under the cursor. Both feeds are that file and
-- neither of them is this one.
--
-- This is the half that is only ever true of loot. Four questions, and none of
-- them can be answered by reading Feeds/Loot.lua.
--
-- Does the column give the screen back. The loot feed ships with no word over
-- it and no line round it, and the thing that goes wrong there is not the
-- setting: it is a strip that stops being drawn without the rows moving up,
-- which is a band of empty window that looks exactly like the bug it is.
--
-- Does one number move three things. The icon is a setting, the row is the icon
-- plus two, and the frame is the rows; write two of the three and you get a
-- column whose rows overlap or whose last row hangs out of the bottom.
--
-- Do the chips filter what is drawn rather than what is kept. There was a
-- quality floor here that worked at the door and could not be undone, and the
-- whole of the change is that an item a chip is refusing is still in the ring
-- and comes back when the chip does.
--
-- And is an item's hover worth opening. A vendor price the client will give you
-- per item and never per stack, a quest item that is the same white as a stack
-- of linen until something says otherwise, and a price out of somebody else's
-- addon with that addon named beside it.

local H = ...
local ns, fire, check, advance = H.ns, H.fire, H.check, H.advance

local Loot = ns.LootFeed
local lootStream = Loot.Stream()
local feed = lootStream:Feed()

-- One frame of the client, because a feed marks itself when a drop lands and
-- paints on its own tick. 31-feeds.lua is where that is asserted; here it is
-- only what has to happen before a row can be read.
local FRAME = 1 / 60
local function drop(format, ...)
	fire("CHAT_MSG_LOOT", (format):format(...))
	local tick = feed.frame:GetScript("OnUpdate")
	if tick then
		tick(feed.frame, FRAME)
	end
end

local function newest()
	return feed:At(0) or {}
end

----------------------------------------------------------------------
-- What the loot feed is dressed in
--
-- It ships bare: no word over the column and no line round the frame. Both
-- are settings and both are off, and the thing worth checking is not the
-- setting but the geometry, because a header that stopped being drawn
-- without the rows moving up is a strip of empty screen where a heading
-- used to be and looks exactly like the bug it is.
--
-- The combat feed keeps both, which is the same code answering differently
-- and is the reason the third argument to Stream.Defaults exists at all.
----------------------------------------------------------------------

check(not ns.db.lootFeedHeader, "the loot feed ships with a word over it")
check(not ns.db.lootFeedEdge, "the loot feed ships with a line round it")
check(ns.db.combatFeedHeader and ns.db.combatFeedEdge,
	"the combat feed lost the chrome the loot feed gave up")

do
	local rows, unit = ns.db.lootFeedRows, ns.UI.Unit(_G.WarriorKitLootFeed)
	-- The chips keep the strip even with the title off, so the loot feed's
	-- own top is the strip's. What the setting takes away is the word.
	local bare = feed:Row(1):GetTop()
	ns.db.lootFeedHeader = true
	lootStream:Apply()
	check(feed:Row(1):GetTop() == bare,
		"turning the word on moved the first row, so the chips were not already holding the strip")
	ns.db.lootFeedHeader = false
	lootStream:Apply()

	-- And with the chips off as well there is no strip at all, which is the
	-- only state in which the first row sits against the top of the frame.
	ns.db.lootFeedFilters = false
	lootStream:Apply()
	check(feed:Row(1):GetTop() == _G.WarriorKitLootFeed:GetTop(),
		"with no word and no chips the first row is still hanging off a strip")
	local height = feed.frame:GetHeight()
	check(math.abs(height - (rows * (feed.row + 1) - 1) * unit) < 0.01,
		("a headerless feed of %d rows is %.1f px and the rows are %.1f")
			:format(rows, height, (rows * (feed.row + 1) - 1) * unit))
	ns.db.lootFeedFilters = true
	lootStream:Apply()
end

----------------------------------------------------------------------
-- How big a row is
--
-- The icon is a setting and the row is the icon plus two, so one stepper
-- moves the picture, the line height and the height of the whole frame.
-- Three things off one number is three chances to write two of them, which
-- is a feed whose rows overlap or whose last row hangs out of the bottom.
----------------------------------------------------------------------

do
	local unit = ns.UI.Unit(_G.WarriorKitLootFeed)
	local tall = feed.frame:GetHeight()
	ns.db.lootFeedIcon = 16
	lootStream:Apply()
	check(feed.row == 18, ("a 16 pixel icon left a %d pixel row"):format(feed.row))
	check(feed:Row(1):GetHeight() == 18 * unit,
		"the row frame did not follow the icon down")
	check(feed:Row(1).icon:GetWidth() == 16 * unit,
		"the icon did not follow the setting down")
	check(feed.frame:GetHeight() < tall,
		"shrinking the icon did not shrink the feed")
	check(feed:Row(2):GetTop() < feed:Row(1):GetBottom() + 0.01,
		"the second row overlaps the first at the small icon size")

	-- And the panel's note about sharpness reads the setting rather than a
	-- constant, which is the whole reason UI.FeedIcons takes one.
	local _, sharp = ns.UI.FeedIcons(16, 1)
	local _, exact = ns.UI.FeedIcons(27, 1)
	check(not sharp and exact,
		"the sharpness note does not depend on the size it was given")

	ns.db.lootFeedIcon = ns.DefaultFor("lootFeedIcon")
	lootStream:Apply()
	check(feed.frame:GetHeight() == tall, "putting the icon back did not put the feed back")
end

----------------------------------------------------------------------
-- The picture on it
--
-- The size of the square is not the picture in it, and this is the half that
-- shipped broken. Every row drew the question mark, because ns.ItemInfo asked
-- _G.GetItemInfoInstant and the newer client keeps that lookup in C_Item and
-- has taken the global away. The two functions beside it in Core.lua already
-- asked C_Item first, so the quality colour and the quest ring went on
-- working and the feed looked like anything but a lookup asked in the wrong
-- place.
--
-- So the client loses both globals for the length of this block, which is the
-- newer client as far as the addon can tell, and the same drop has to come
-- back with the same icon it just had.
----------------------------------------------------------------------

do
	local link = _G.WarriorKitItemLink("Arcanite Reaper")
	feed:Clear()
	drop("You receive loot: %s.", link)
	local want = newest().icon
	check(want == "Interface\\Icons\\Axe",
		"the stub has no icon for an item, so nothing below this proves anything")

	local instant, cached = _G.GetItemInfoInstant, _G.GetItemInfo
	_G.GetItemInfoInstant, _G.GetItemInfo = nil, nil
	feed:Clear()
	drop("You receive loot: %s.", link)
	check(newest().icon == want,
		"with the item lookups only in C_Item the row drew " .. tostring(newest().icon))

	-- And the two that were already right, checked here rather than assumed,
	-- because the whole reason this went unnoticed is that they kept working.
	check(newest().quality == 4, "the quality went with the globals")
	check(newest().price == 9100, "the vendor price went with the globals")
	_G.GetItemInfoInstant, _G.GetItemInfo = instant, cached
end

----------------------------------------------------------------------
-- The chips
--
-- The quality floor that used to sit here worked at the door and this does
-- not, which is the whole of the change and is stated as three claims. An
-- item a chip is refusing is still in the ring. The column stops drawing it
-- the moment the chip goes off. And turning the chip back on brings it back
-- rather than starting an empty list, which is the thing a floor could
-- never do.
----------------------------------------------------------------------

feed:Clear()
drop("You receive loot: %s.", _G.WarriorKitItemLink("Chipped Boar Tusk"))
drop("You receive loot: %s.", _G.WarriorKitItemLink("Arcanite Reaper"))
check(feed:Count() == 2 and feed:Shown() == 2, "two drops did not both reach the column")

Loot.Light(0, false)
feed:Chipped()
check(feed:Count() == 2, "turning the grey chip off threw the grey out of the ring")
check(feed:Shown() == 1, ("the grey chip is off and the column still draws %d rows")
	:format(feed:Shown()))
check(feed:At(0).name == "Arcanite Reaper",
	"the top row is not the epic with the greys filtered out: " .. tostring(feed:At(0).name))
check(feed:Row(2).shownEntry == nil, "the second row is still drawing a filtered entry")

Loot.Light(0, true)
feed:Chipped()
check(feed:Shown() == 2, "turning the grey chip back on did not bring the grey back")

-- The chip in the strip and the arithmetic behind it are one switch. A click
-- on the first chip has to move the first quality and nothing else, because
-- the panel puts the same six switches on a page and the two disagreeing is
-- a control that fights the one beside it.
do
	local chip = feed:Chip(1)
	check(chip ~= nil, "the loot feed has no chips over it")
	H.mouse.On(chip)
	check(not Loot.Lit(0), "clicking the first chip did not turn the poor quality off")
	check(feed:Shown() == 1, "clicking the first chip did not take the grey off the column")
	H.mouse.On(chip)
	check(Loot.Lit(0), "clicking the first chip twice did not put it back")
	check(feed:Shown() == 2, "clicking the first chip twice did not bring the grey back")

	-- A chip draws a mark, and the mark has a font on it.
	--
	-- This is the one that shipped broken. UI.Glyph takes a pixel height and
	-- every measurement in UI/Feed.lua is a design pixel multiplied by the
	-- zoom, so the size went in multiplied: UI.GlyphFont was asked for 26.25,
	-- SetFont refused the fraction, GetFont came back nil and every chip drew
	-- an empty square. Nothing measured it, because the geometry was right and
	-- only the picture was missing.
	check(chip.mark:GetText() == "*",
		"the first chip carries no mark: " .. tostring(chip.mark:GetText()))
	local face, size = chip.mark:GetFont()
	check(face ~= nil and size ~= nil,
		"a chip's mark has no font on it, so it draws nothing at all")
	check(size == math.floor(size),
		("a chip's mark is set at %s, and a font size has to be a whole number of pixels")
			:format(tostring(size)))

	-- And the tooltip opens over it rather than beside it. The cursor's
	-- hotspot is the pointer's top left corner and the arrow hangs down and to
	-- the right, so a box pinned beside a sixteen pixel square opens under the
	-- arrow that opened it.
	--
	-- Undocked, because that is the setting the claim is about: a docked box is
	-- in the corner whatever it was opened on, and the chip's own answer to the
	-- cursor is still the one that has to be right for anybody who turns the
	-- dock off.
	local wasPlace = ns.UI.Tooltip.Place()
	ns.UI.Tooltip.SetPlace(ns.UI.Tooltip.BESIDE)
	ns.UI.Tooltip.Close(true)
	chip:GetScript("OnEnter")(chip)
	check(not ns.UI.Tooltip.IsShown(), "a chip opened its box before the hand had stopped")
	check(H.tipHold(), "hovering a chip said nothing")
	check(ns.Measure(ns.UI.Tooltip.Frame(), "GetBottom") >= ns.Measure(chip, "GetTop"),
		"a chip's tooltip opens beside it, which puts it under the cursor")
	chip:GetScript("OnLeave")(chip)
	ns.UI.Tooltip.SetPlace(wasPlace)

	-- With the mouse off the feed is a picture, and a picture does not have
	-- seven clickable squares on it. That setting is somebody getting the
	-- right button back for the camera, and a chip still swallowing it is the
	-- trade they turned it off to stop making.
	ns.db.lootFeedMouse = false
	lootStream:Apply()
	check(not chip:IsMouseEnabled(), "a chip still takes the mouse with the feed set to a picture")
	ns.db.lootFeedMouse = true
	lootStream:Apply()
	check(chip:IsMouseEnabled(), "a chip does not take the mouse with the setting back on")
end

-- With the strip hidden the filter goes with it, because a column refusing
-- rows with no control on screen saying so is one nobody can argue with.
Loot.Light(0, false)
ns.db.lootFeedFilters = false
lootStream:Apply()
check(feed:Shown() == 2, "the chips are hidden and the column is still filtering")
ns.db.lootFeedFilters = true
lootStream:Apply()
check(feed:Shown() == 1, "the chips came back and the filter did not")
Loot.Light(0, true)
feed:Chipped()

----------------------------------------------------------------------
-- A quest item
--
-- Class 12 and white, which is the whole problem: it is the same colour as a
-- stack of linen and the row that hands in your chain of five kills reads
-- exactly like the row that hands you a bandage. So it gets a ring, and a
-- chip that draws it whatever the white chip says.
----------------------------------------------------------------------

feed:Clear()
drop("You receive loot: %s.", _G.WarriorKitItemLink("Hogger's Claw"))
check(newest().quest, "a quest item did not read as one")
check(newest().ring ~= nil, "a quest item got no ring round its icon")
check(feed:Row(1).mark:IsShown(), "the ring round a quest item's icon is not drawn")

drop("You receive loot: %s.", _G.WarriorKitItemLink("Linen Cloth"))
check(not newest().quest, "an ordinary item read as a quest item")
check(not feed:Row(1).mark:IsShown(), "an ordinary row drew a ring round its icon")
check(newest().quality == 1, "the white item beside the quest item is not white")

-- White off and quest on is the combination the override exists for.
Loot.Light(1, false)
feed:Chipped()
check(feed:Shown() == 1, "turning the whites off left something other than the quest item")
check(feed:At(0).quest, "the row left standing is not the quest item")

ns.db.lootFeedQuest = false
feed:Chipped()
check(feed:Shown() == 0, "the quest chip is off and a white quest item is still drawn")
ns.db.lootFeedQuest = true
Loot.Light(1, true)
feed:Chipped()

----------------------------------------------------------------------
-- What an item is worth
--
-- Two numbers on the hover and they answer different questions. The vendor
-- price is the client's and is per item, which is why a stack gets a second
-- line: eleven silk cloth is the number you decide on, and no tooltip in
-- the game says it. The auction price is not the client's at all, and the
-- line naming the addon that supplied it is the whole of how a player can
-- check a number this addon did not work out.
----------------------------------------------------------------------

-- The right hand side of whichever line carries this label, or nil.
local function said(label)
	for index = 1, ns.UI.Tooltip.Lines() do
		local left, right = ns.UI.Tooltip.Text(index)
		if left == label then
			return right or false
		end
	end
	return nil
end

local function hover()
	feed:ToTop()
	local row = feed:Row(1)
	ns.UI.Tooltip.Close()
	row:GetScript("OnEnter")(row)
end

feed:Clear()
drop("You receive loot: %s.", _G.WarriorKitItemLink("Aegis"))
hover()
check(said("Vendor") == ns.Coin(3800),
	("the vendor line says %s and the item is worth %s")
		:format(tostring(said("Vendor")), ns.Coin(3800)))
check(said("Stack of 1") == nil, "a single item got a stack line")
check(said("Auctionator") == nil, "an auction price appeared with no auction addon installed")

drop("You receive loot: %sx8.", _G.WarriorKitItemLink("Tattered Cloth"))
hover()
check(said("Vendor") == ns.Coin(12), "the vendor line is not the price of one")
check(said("Stack of 8") == ns.Coin(96),
	("a stack of eight at 12c came to %s"):format(tostring(said("Stack of 8"))))

-- An item a vendor will not take says so in words rather than showing 0c,
-- because nought copper and "no price cached yet" are the same number and
-- different facts.
drop("You receive loot: %s.", _G.WarriorKitItemLink("Broken Twig"))
hover()
check(said("Vendor") == "will not take it",
	"an item worth nothing drew a price rather than a sentence")

-- The quest line, and the one thing a quality colour cannot say.
drop("You receive loot: %s.", _G.WarriorKitItemLink("Hogger's Claw"))
hover()
check(said("Quest item") == false, "a quest item's tooltip does not say so")

-- And the auction price, once something is there to ask. The scanner is
-- resolved on first use and remembered, so this has to come after the check
-- that there was none.
_G.Auctionator = {
	API = { v1 = { GetAuctionPriceByItemLink = function(caller, link)
		check(caller == "WarriorKit", "the auction scanner was not told who was asking")
		return link:find("Aegis", 1, true) and 47000 or nil
	end } },
}
check(ns.Auction.Describe():find("Auctionator", 1, true) ~= nil,
	"the panel does not report the auction addon that just appeared")

feed:Clear()
drop("You receive loot: %s.", _G.WarriorKitItemLink("Aegis"))
hover()
check(said("Auctionator") == ns.Coin(47000),
	("the auction line says %s and the scanner said %s")
		:format(tostring(said("Auctionator")), ns.Coin(47000)))

-- An item the scanner has no price for gets no line, rather than a zero.
drop("You receive loot: %s.", _G.WarriorKitItemLink("Tattered Cloth"))
hover()
check(said("Auctionator") == nil, "an item the scanner has never seen drew a price anyway")

-- Put away, because there is no unresolving a scanner: Feeds/Auction.lua
-- remembers the first one that answers, on the ground that an addon cannot
-- appear halfway through a session. What that means here is that the stub
-- stays found, and every hover after this asks a table that is gone and gets
-- a pcall failure, which is the same answer as no price.
_G.Auctionator = nil
ns.UI.Tooltip.Close()

----------------------------------------------------------------------
-- Twelve bandages on one row
--
-- A craft hands you one bandage a second and the client says so every time.
-- Twelve rows of the same sentence is a column that told you one thing and
-- spent eleven rows doing it, so the second one folds into the first: the
-- number on the row climbs, the row keeps the place it already had, and the
-- window inside which two of the same item are one pickup is sixty seconds.
--
-- The hover is the other half of the fold and the half that is easy to lose. A
-- row reading `x12` whose tooltip says `12` and nothing else has thrown the
-- fold away. What the row cannot hold is that twelve of them came off three
-- separate pickups, and which one of the three the clock on it is about.
----------------------------------------------------------------------

local LINEN = _G.WarriorKitItemLink("Linen Cloth")

feed:Clear()
local tally = Loot.Counts()
drop("You receive loot: %s.", LINEN)
drop("You receive loot: %s.", LINEN)
drop("You receive loot: %sx4.", LINEN)
check(feed:Count() == 1, ("three arrivals of one item made %d rows"):format(feed:Count()))
check(newest().count == 6 and newest().amount == "x6",
	("the folded row reads %s off a count of %s")
		:format(tostring(newest().amount), tostring(newest().count)))
-- A pickup that folded still reached the feed, which is what the panel's
-- number is a count of.
check(Loot.Counts() == tally + 3,
	("the feed's tally moved by %d over three arrivals"):format(Loot.Counts() - tally))

-- A different item between two of the same does not end the run, and the row
-- that folds does not climb over the one above it.
drop("You receive loot: %s.", _G.WarriorKitItemLink("Aegis"))
drop("You receive loot: %s.", LINEN)
check(feed:Count() == 2, "an item in between made the next one of them a new row")
check(feed:At(0).name == "Aegis" and feed:At(1).count == 7,
	"the folded row jumped to the top rather than climbing where it stood")

-- Half a minute on is the same pickup, and the clock on the row moves to the
-- one that just landed rather than staying on the one that started it.
local was = feed:At(1).at
advance(30)
drop("You receive loot: %s.", LINEN)
check(feed:Count() == 2 and feed:At(1).count == 8,
	"half a minute later was read as a different afternoon")
check(feed:At(1).at == _G.GetTime() and feed:At(1).at > was,
	"the folded row is still about the first one you picked up")

-- Past sixty seconds it is a second trip and gets a second row.
advance(61)
drop("You receive loot: %s.", LINEN)
check(feed:Count() == 3, "a minute past the window and the row is still folding")
check(newest().count == 1 and newest().amount == "x1",
	("the row past the window opened at %s"):format(tostring(newest().amount)))

-- What the row stopped being able to say.
feed:Clear()
drop("You receive loot: %sx8.", LINEN)
hover()
check(said("Stack") == "8",
	("a stack that arrived whole says %s"):format(tostring(said("Stack"))))
drop("You receive loot: %sx4.", LINEN)
hover()
check(said("Stack") == "12 in 2 pickups",
	("a row of twelve off two pickups says %s"):format(tostring(said("Stack"))))
check(said("Looted") == ns.Stream.Clock(_G.GetTime()),
	("the hover dates the fold at %s and it landed at %s")
		:format(tostring(said("Looted")), ns.Stream.Clock(_G.GetTime())))

advance(5)
drop("You receive loot: %s.", LINEN)
hover()
check(said("Stack") == "13 in 3 pickups",
	("a third pickup left the hover saying %s"):format(tostring(said("Stack"))))
-- Five seconds on, and the line is the arrival that just landed. The check
-- above says the hover reads now; this one says it is not the pickup before
-- last, which is what a clock left on the arrival that opened the row says and
-- which reads as a perfectly good time.
check(said("Looted") ~= ns.Stream.Clock(_G.GetTime() - 5),
	"the hover is dating the row by the pickup before last")

ns.UI.Tooltip.Close()

-- One item, two looters, two rows.
--
-- `who` is nil on your own pickup and a name on somebody else's, and the hover
-- draws it as "Went to". A fold that read the link and the clock alone would
-- put your linen and a party member's on one row, and that row would count
-- three of them and name one player. The group column is the one feature whose
-- whole job is answering who got it.
do
	local wasGroup = ns.db.lootFeedGroup
	ns.db.lootFeedGroup = true
	feed:Clear()
	drop("You receive loot: %s.", LINEN)
	drop("%s receives loot: %s.", "Bram", LINEN)
	check(feed:Count() == 2, "one item off two looters inside the window is one row")

	-- And each of them folds on its own.
	drop("You receive loot: %s.", LINEN)
	drop("%s receives loot: %sx2.", "Bram", LINEN)
	check(feed:Count() == 2, "a second pickup each opened a row rather than folding")
	check(feed:At(0).who == "Bram" and feed:At(0).count == 3,
		("the group row says %s of them went to %s")
			:format(tostring(feed:At(0).count), tostring(feed:At(0).who)))
	check(feed:At(1).who == nil and feed:At(1).count == 2,
		("your own row folded to %s and somebody else's pickup is in it")
			:format(tostring(feed:At(1).count)))
	ns.db.lootFeedGroup = wasGroup
end

print(("loot   no word and no line, %d chips over %d rows, icon %d px on a %d px row,"
	.. " vendor price per item and per stack, a stub scanner asked for the auction")
	:format(#feed.chips, ns.db.lootFeedRows, ns.db.lootFeedIcon, feed.row))
