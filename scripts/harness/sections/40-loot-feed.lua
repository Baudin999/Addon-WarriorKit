-- The loot feed
--
-- 31-feeds.lua is what a feed is: a ring, an offset into it, rows that do not
-- move and a tooltip on the row under the cursor. Both feeds are that file and
-- neither of them is this one.
--
-- This is the half that is only ever true of loot. Seven questions, and none of
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
--
-- Does a repeat land on the row it is already on. Twelve bandages off one
-- corpse is one row and a number that climbs, and the arithmetic under it is
-- what a reading cannot check: the total, the pickups behind it, the looter it
-- may not fold across, and the minute after which it is a different afternoon.
-- Coin is the same question with no link to ask it with.
--
-- Is the column read against something the addon painted. The panel is gone and
-- each row carries a gradient that has to end where the text ends, because a
-- wash the width of the row is the panel again with a fade on one side.
--
-- And does the row say why you want it. The middle column and the ring are one
-- answer out of Need/Need.lua, and the half a reading cannot settle is that a
-- row which folded six of something reads the count as it stands now.

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
-- The ground a row is read on
--
-- The panel behind the column is gone and each row carries a gradient
-- instead, solid at the stripe and gone by the end of the text, with the
-- background slider saying how strongly it is painted. Every check here is
-- one that fails silently.
--
-- A wash the width of the row draws a rectangle, measures fine and is the
-- panel back with one soft edge. A wash made after the hover glow draws
-- perfectly and takes the light out of the row under the cursor. A wash
-- running the other way is solid where the number is and clear under the
-- name, which is worse than none. One that ignored the slider would leave
-- the loot feed's shipped 15 as a black bar under thirteen rows.
--
-- Built by UI/Feed.lua rather than by this stream, which is what makes it
-- every feed's: the combat feed takes the same rows through the same
-- resize and the same Feed:Wash off its own slider.
----------------------------------------------------------------------

do
	local C = ns.UI.Color
	local unit = ns.UI.Unit(_G.WarriorKitLootFeed)
	local row = feed:Row(1)

	check(lootStream.bg == nil,
		"the stream still paints a panel behind the column, so the wash is a second surface")
	check(row.wash ~= nil, "a row has no wash under its text")
	check(row.wash.layer == "BACKGROUND",
		("the wash is on %s, so it is drawn over the text it is meant to be under")
			:format(tostring(row.wash.layer)))
	check(row.stripe.layer == "ARTWORK" and row.icon.layer == "ARTWORK",
		"the stripe and the icon left ARTWORK, so the wash is no longer under them")

	-- Under the hover light rather than over it. Both are on BACKGROUND and
	-- the client draws that layer in the order the textures were made.
	do
		local wash, glow
		for index, region in ipairs(row.regions) do
			if region == row.wash then wash = index end
			if region == row.glow then glow = index end
		end
		check(wash and glow and wash < glow,
			"the wash was made after the glow, so it darkens the row the cursor is on")
	end

	-- It stops where the text stops. The number is held one inset off the
	-- row's right edge and the wash ends with it, so what is left over the
	-- world is the three pixels nothing is written in.
	check(math.abs(row.wash:GetRight() - row.amount:GetRight()) < 0.01,
		("the wash ends at %.1f and the number ends at %.1f")
			:format(row.wash:GetRight(), row.amount:GetRight()))
	check(row.wash:GetWidth() < row:GetWidth(),
		"the wash is as wide as the row, which is the panel again with one soft edge")
	check(row.wash:GetWidth() % 1 == 0,
		("the wash came out %.2f wide, which is not a whole number of pixels")
			:format(row.wash:GetWidth()))
	check(row.wash:GetHeight() == feed.row * unit,
		"the wash is not the height of the row it is under")

	-- Which end is solid. The client runs a horizontal gradient min at the
	-- left, and the left of a feed row is the stripe the text reads out from.
	do
		local ramp = row.wash:GetGradient()
		check(ramp ~= nil and ramp.orientation == "HORIZONTAL",
			"the wash under a row runs down the column rather than along the row")
		check(ramp.min[4] == C.shadow[4] and ramp.max[4] == 0,
			("the row washes from %s at the stripe to %s at the number")
				:format(tostring(ramp.min[4]), tostring(ramp.max[4])))
		check(ramp.max[1] == C.shadow[1] and ramp.max[2] == C.shadow[2]
			and ramp.max[3] == C.shadow[3],
			"the wash fades to a different colour rather than to nothing")
	end

	-- And how strongly, which is the slider that used to paint the panel.
	check(row.wash:GetAlpha() == ns.db.lootFeedAlpha / 100,
		("the wash is at %s and the slider says %d%%")
			:format(tostring(row.wash:GetAlpha()), ns.db.lootFeedAlpha))

	local kept = ns.db.lootFeedAlpha
	ns.db.lootFeedAlpha = 0
	lootStream:Apply()
	check(feed:Row(1).wash:GetAlpha() == 0,
		"at zero the rows still have a shadow painted under them")

	-- A row built after the slider moved takes the strength the feed is at.
	-- The number is held on the feed for this: a stepper that makes four more
	-- rows would otherwise leave them at full strength.
	local grew = ns.db.lootFeedRows + 2
	ns.db.lootFeedRows = grew
	lootStream:Apply()
	check(feed:Row(grew).wash:GetAlpha() == 0,
		"a row built after the slider moved was painted at full strength")

	ns.db.lootFeedAlpha, ns.db.lootFeedRows = kept, ns.DefaultFor("lootFeedRows")
	lootStream:Apply()
	check(feed:Row(1).wash:GetAlpha() == kept / 100,
		"putting the slider back did not put the wash back")
end

----------------------------------------------------------------------
-- What a row is written in
--
-- Shadowed, not rimmed. The rim was there because a feed had no ground it
-- could promise, the wash above is that ground, and a rim on a stroke costs
-- a pixel of every glyph to say the same thing worse.
--
-- 36-font-roles.lua holds the whole addon to "a string with nothing behind
-- it carries a rim or a shadow" and a feed row passes that either way, which
-- is why the claim that these four are shadowed has to be made here.
----------------------------------------------------------------------

do
	local row = feed:Row(1)
	for _, part in ipairs({ "name", "note", "amount", "caption" }) do
		local flags = select(3, row[part]:GetFont()) or ""
		check(flags:find("OUTLINE", 1, true) == nil,
			("the row's %s still carries a rim"):format(part))
		check(select(1, row[part]:GetShadowOffset()) ~= 0,
			("the row's %s has neither a rim nor a shadow"):format(part))
	end

	-- The floor that held the icon at 16 was the rim's, and the rim is gone.
	-- The number stands until somebody measures a shorter row with the wash
	-- under it, which is a separate commit and a ratchet of its own.
	check(ns.UI.FEED_ICON_LOW == 16,
		("the smallest row is %d and this commit was not the one to move it")
			:format(ns.UI.FEED_ICON_LOW))
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
-- One picture in both windows
--
-- Character/Paperdoll.lua rests the band round a worn item's icon at
-- UI.Metric.rest and the hover takes it to full. A feed shows more quality at
-- once than the sheet ever does, thirteen rows of it against nineteen squares
-- you look at one at a time, so it rests its stripe at the same number off the
-- same constant.
--
-- The ring is the exception and it is exempt by the entry's word rather than by
-- being a quest. A ring nobody claims rests with the stripe, which is the room
-- left for a ring that means something else.
----------------------------------------------------------------------

do
	local C, M = ns.UI.Color, ns.UI.Metric

	feed:Clear()
	drop("You receive loot: %s.", _G.WarriorKitItemLink("Linen Cloth"))
	local row = feed:Row(1)
	check(row.stripe:GetAlpha() == M.rest,
		("a resting stripe is at %s and the sheet rests a quality at %s")
			:format(tostring(row.stripe:GetAlpha()), tostring(M.rest)))

	feed:Enter(1)
	check(row.stripe:GetAlpha() == 1, "the row under the cursor did not go to full")
	feed:Leave()
	check(row.stripe:GetAlpha() == M.rest,
		"the stripe stayed lit after the cursor left the row")

	-- The quest ring, which is the one thing on the row telling you to look and
	-- is drawn at full whatever the cursor is on.
	drop("You receive loot: %s.", _G.WarriorKitItemLink("Hogger's Claw"))
	row = feed:Row(1)
	check(row.mark:IsShown() and row.mark:GetAlpha() == 1,
		("the quest ring is at %s rather than at full")
			:format(tostring(row.mark:GetAlpha())))
	check(row.stripe:GetAlpha() == M.rest,
		"the stripe on a quest row is lit as well as the ring")
	feed:Enter(1)
	check(row.mark:GetAlpha() == 1 and row.stripe:GetAlpha() == 1,
		"hovering the quest row left something short of full")
	feed:Leave()
	check(row.mark:GetAlpha() == 1, "the quest ring dimmed when the cursor left")

	-- And a ring the entry has not claimed. Nothing pushes one today; item 86
	-- turns the quest ring into a reason ring and this is the half of the
	-- mechanism it needs, so it is asserted rather than left to be discovered.
	local slot = feed:Entry()
	slot.name, slot.amount = "Unclaimed", ""
	slot.color, slot.stripe = C.text, C.text
	slot.ring = C.heading
	feed:Push()
	feed:Paint()
	check(feed:Row(1).mark:IsShown() and feed:Row(1).mark:GetAlpha() == M.rest,
		("a ring no entry claimed is at %s rather than resting with the stripe")
			:format(tostring(feed:Row(1).mark:GetAlpha())))

	feed:Clear()
end

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

----------------------------------------------------------------------
-- Three corpses on one coin row
--
-- Coin folds on being coin at all. There is no link to tell one copper from
-- another and the client reports nobody else's coin, so the window is the
-- whole of the match.
--
-- What it costs is the client's own sentence, and that is the point of this
-- scene. "12 Silver, 39 Copper" is the right text for the pickup it was
-- written about and the wrong text for a row three corpses have paid into, so
-- the row that folds is written from the running total instead. A coin row
-- still reading the first sentence while counting four pickups is the one
-- column in this addon that is arithmetic saying something untrue.
--
-- The total is a number rather than a phrase because a phrase cannot be added
-- up. Core/Loot.lua reads it back out of the client's own amount strings, so
-- 1 Gold, 8 Copper is 10008 here and is 10008 on a German client.
----------------------------------------------------------------------

local function coin(text)
	fire("CHAT_MSG_MONEY", text)
	local tick = feed.frame:GetScript("OnUpdate")
	if tick then
		tick(feed.frame, FRAME)
	end
end

feed:Clear()
coin("You loot 12 Silver, 39 Copper")
check(feed:Count() == 1 and newest().money, "coin did not reach the feed")
check(newest().copper == 1239,
	("the coin phrase came to %s copper"):format(tostring(newest().copper)))
-- One pickup keeps the client's sentence. It is the better text, and nothing
-- has been added to it for it to be wrong about.
check(newest().name == "12 Silver, 39 Copper",
	("a coin row that never folded reads %s"):format(tostring(newest().name)))

coin("You loot 1 Gold, 8 Copper")
check(feed:Count() == 1, "a second coin inside the window opened a second row")
check(newest().copper == 11247,
	("two pickups came to %s copper"):format(tostring(newest().copper)))
check(newest().name == ns.Coined(11247),
	("the folded coin row reads %s"):format(tostring(newest().name)))

-- An item in between does not end the run, and coin does not fold onto it.
drop("You receive loot: %s.", _G.WarriorKitItemLink("Arcanite Reaper"))
coin("You loot 3 Copper")
check(feed:Count() == 2, "coin landed on the item row above it or opened a row of its own")
check(feed:At(1).copper == 11250,
	("the coin row under the item holds %s copper"):format(tostring(feed:At(1).copper)))

-- Past the window it is a second trip, and that row is the client's sentence
-- again rather than the total of the one above it.
advance(61)
coin("You loot 7 Copper")
check(feed:Count() == 3, "a minute past the window and the coin row is still folding")
check(newest().copper == 7 and newest().name == "7 Copper",
	("the coin row past the window reads %s"):format(tostring(newest().name)))

-- What the row stopped being able to say. The total is on it; how many
-- corpses paid it is not.
feed:Clear()
coin("You loot 5 Silver")
hover()
check(said("Coin") == nil, "a coin row off one pickup counted its pickups")
coin("You loot 5 Silver")
hover()
check(said("Coin") == ("%s in 2 pickups"):format(ns.Coined(1000)),
	("a coin row off two pickups says %s"):format(tostring(said("Coin"))))
check(said("Looted") == ns.Stream.Clock(_G.GetTime()),
	("the hover dates the coin fold at %s and it landed at %s")
		:format(tostring(said("Looted")), ns.Stream.Clock(_G.GetTime())))
ns.UI.Tooltip.Close()

-- Why the row matters
--
-- The dim middle column is Core/Need.lua's phrase and the ring round the icon
-- is its colour, and the point of them being one answer is that they cannot
-- disagree: a row reading `4/8` in the green a reagent is drawn in is a row
-- saying two things about one item.
--
-- Only a quest count reaches the column, and the reason is a measurement:
-- "Leatherworking" is 104 units in the shipped face at a row's text size and
-- this column is 48 and is never handed more than 81. So a reagent is a green
-- ring and a word on the hover, and the row never draws part of a word.
--
-- 82-need.lua is where the answer itself is held to its order and its cache.
-- What is asserted here is the half only a row can be wrong about, which is the
-- fold. A row that folded six bandanas is showing a count that moved while it
-- was folding, and a note written once on the arrival that opened the row would
-- tell you to keep six more of something your log has stopped counting.
----------------------------------------------------------------------

-- Two items this part owns, at ids nothing else in the suite uses. The bandana
-- is the name quest 203 is already counting in the log fixture, so the quest
-- source answers with no fixture of its own; the ingot is a trade good and
-- nothing more until the list below says otherwise.
H.ITEMS["Red Silk Bandana"] = { id = 8401, classId = 15, subClassId = 0,
	quality = 1, price = 30, icon = "Interface\\Icons\\Bandana" }
H.ITEMS["Rough Ingot"] = { id = 8402, classId = 7, subClassId = 1,
	quality = 1, price = 15, icon = "Interface\\Icons\\Ingot" }

local BANDANA = _G.WarriorKitItemLink("Red Silk Bandana")
local OBJECTIVE = H.quests.text[203].objectives[1]
local COUNTING = OBJECTIVE[1]

feed:Clear()
fire("QUEST_LOG_UPDATE")
drop("You receive loot: %s.", BANDANA)
check(newest().note == COUNTING:match("(%d+/%d+)"),
	("a bandana the log is counting reads %s"):format(tostring(newest().note)))
check(newest().ring == ns.UI.Color.quest,
	"the ring round a quest objective is not the palette's quest colour")
check(feed:Row(1).note:GetText() == newest().note,
	("the row drew %s in its middle column"):format(tostring(feed:Row(1).note:GetText())))
check(feed:Row(1).note:IsShown(), "the loot feed asks for no middle column")

-- The sentence, which is the half a column three characters wide cannot say.
-- The row is the glance and the hover is the reading.
hover()
check(said("Red Silk Bandana, 0 of 6") == false,
	"the hover does not name the item and the two numbers")
ns.UI.Tooltip.Close()

-- Most items, which is the answer that has to stay quiet. Nothing counts a
-- stack of linen and no profession here has claimed it, so there is no phrase
-- and no ring, and a feed that ringed everything would be a feed with no marks
-- on it.
drop("You receive loot: %s.", _G.WarriorKitItemLink("Linen Cloth"))
check(newest().note == nil,
	("an item with no reason reads %s"):format(tostring(newest().note)))
check(newest().ring == nil, "an item with no reason got a ring round its icon")
check(not feed:Row(1).mark:IsShown(), "the ring is drawn on a row with no reason")

-- A reagent still worth a point: a green ring, an empty column and the
-- profession on the hover. The column is the check that carries the weight.
-- "Blacksmithing" is 93 units in the shipped face at a row's text size and the
-- widest this column is ever handed is 81, so a row that drew it would be
-- drawing part of a word, and part of a word is worse than none.
--
-- The list is written straight onto ns.dbc.lootReagents rather than walked out
-- of a profession window, because a window opened here would leave
-- 69-loot-filter.lua reading a list that section never asked for.
do
	local was = ns.dbc.lootReagents
	ns.dbc.lootReagents = { [8402] = { owner = "Blacksmithing", kind = "optimal" } }
	fire("SKILL_LINES_CHANGED")
	drop("You receive loot: %s.", _G.WarriorKitItemLink("Rough Ingot"))
	check(newest().note == nil,
		("a blacksmithing reagent put %s in the row's column"):format(tostring(newest().note)))
	check(feed:Row(1).note:GetText() == "",
		("the row drew %s beside a reagent"):format(tostring(feed:Row(1).note:GetText())))
	check(newest().ring == ns.UI.Color.skill,
		"the ring round a reagent is not the palette's skill colour")
	check(feed:Row(1).mark:IsShown(), "the ring round a reagent's icon is not drawn")
	hover()
	check(said("Rough Ingot, Blacksmithing") == false,
		"the hover does not name the profession the row had no room for")
	ns.UI.Tooltip.Close()
	ns.dbc.lootReagents = was
	fire("SKILL_LINES_CHANGED")
end

-- And the fold. Five more bandanas is one row and one count, and the note on it
-- is the objective as it stands now rather than as it stood when the row opened.
feed:Clear()
fire("QUEST_LOG_UPDATE")
drop("You receive loot: %s.", BANDANA)
check(newest().note == "0/6", "the row did not open on the count it arrived with")

OBJECTIVE[1] = "Red Silk Bandana: 5/6"
fire("QUEST_LOG_UPDATE")
advance(5)
drop("You receive loot: %sx5.", BANDANA)
check(feed:Count() == 1, "the second pickup of a bandana opened a second row")
check(newest().count == 6, ("the folded row counts %s"):format(tostring(newest().count)))
check(newest().note == "5/6",
	("the folded row still says %s"):format(tostring(newest().note)))
check(feed:Row(1).note:GetText() == "5/6",
	("the row drew %s after the fold"):format(tostring(feed:Row(1).note:GetText())))
hover()
check(said("Red Silk Bandana, 5 of 6") == false,
	"the hover after a fold is dating the note by the pickup that opened the row")
ns.UI.Tooltip.Close()

-- The fixture put back, because the objective is the log's and 47-quest-log.lua
-- reads the same line.
OBJECTIVE[1] = COUNTING
fire("QUEST_LOG_UPDATE")

print(("loot   no word and no line, %d chips over %d rows, icon %d px on a %d px row,"
	.. " vendor price per item and per stack, a stub scanner asked for the auction;"
	.. " a %d unit note column holding a quest count and nothing else, a green ring"
	.. " where the profession would not fit, and a fold that reread the count")
	:format(#feed.chips, ns.db.lootFeedRows, ns.db.lootFeedIcon, feed.row,
		lootStream.note))
