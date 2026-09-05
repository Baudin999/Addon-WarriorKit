-- The gear page
--
-- What the character window's first tab draws, which since the rows landed is
-- more than the rest of that window put together and is why it is a file.
--
-- It was the middle hundred lines of 52-character.lua and that file sat on its
-- own line ceiling, so every assertion the names, the sockets and the figure
-- behind them needed had nowhere to go. Raising the ceiling is the move
-- scripts/ratchet.lua exists to refuse. Splitting the subject out drops
-- 52-character under the limit everything else is held to and gives its
-- exemption back, which is the same trade the other four entries on that list
-- are still waiting to make.
--
-- The window is opened and shut here rather than inherited. This section runs
-- after 52-character has finished with the sheet and hidden it, so nothing
-- above is left standing to read.
--
-- What this cannot prove: that any of it looks like anything. A mask, a vertex
-- colour and a frame level are three calls the client answers nothing about,
-- and all three are load bearing for the page reading as one picture. What is
-- asserted is that each of them was made and landed on the right object.

local H = ...
local ns, check = H.ns, H.check

local Window, Worn = ns.CharWindow, ns.Worn
local GEAR = 1

-- What the line at the foot reports, filled in by the blocks that measure it.
-- Locals rather than H.carry: that table is for a number one section hands to a
-- later one, and every one of these is taken and read out in this file.
local column, stats, readout, dots = 0, 0, 0, 0

----------------------------------------------------------------------
-- The nineteen slots
----------------------------------------------------------------------

do
	Window.Show(GEAR)
	local pane = Window.Pane(GEAR)
	check(#pane.squares == 19,
		("%d slots were drawn and the client has nineteen"):format(#pane.squares))

	local head, neck
	for _, box in ipairs(pane.squares) do
		if box.entry.slot == 1 then
			head = box
		elseif box.entry.slot == 2 then
			neck = box
		end
	end

	check(head.icon:IsShown(), "the helmet slot is filled and drew no icon")
	check(head.wear:IsShown(), "the helmet is at 40% durability and drew no wear line")
	check(not neck.wear:IsShown(),
		"a necklace does not wear out and the slot drew a wear line anyway")

	-- Quality is the ring behind the icon now a square is a disc, read off tone
	-- because the stub swallows a vertex write; a mask answers nothing about itself.
	check(head.tone[1] == ns.UI.Quality[4][1], "the epic helmet is not ringed in the epic colour")
	check(head.icon.masks and #head.icon.masks == 1, "the helmet icon was not cut to the disc")

	local shirt
	for _, box in ipairs(pane.squares) do
		if box.entry.slot == 4 then
			shirt = box
		end
	end
	check(shirt.empty:IsShown() and not shirt.icon:IsShown(),
		"an empty slot did not draw the client's own silhouette")

	local wear, worst = Worn.Wear()
	check(math.abs(wear - (40 + 95 + 12) / 300) < 1e-6,
		("durability came to %.4f and the three worn pieces are 147 of 300"):format(wear))
	check(worst ~= nil and worst.slot == 16,
		"the worst piece is the main hand at twelve percent and something else was named")

	local level, empty = Worn.Level()
	check(level ~= nil and math.abs(level - 60) < 1e-6,
		("the average item level came to %s"):format(tostring(level)))
	check(empty > 0, "every slot came back full on a character wearing four pieces")

	-- The stats, which are on this page rather than on a tab. The check is that
	-- the column was given room and drew into it: a readout with no width paints
	-- nothing and returns quietly, which is what the move could break without
	-- anything else on the page noticing.
	check(pane.stats ~= nil, "the gear page has no stats column")
	check((pane.stats.width or 0) >= 204,
		("the stats column came out %s wide"):format(tostring(pane.stats.width)))
	check(pane.stats:Lines() > 0, "the stats column drew no lines beside the gear")

	-- Compact means one line a row. The sentence that used to wrap underneath is
	-- in the hover, so a row that grew past a single line is a row still drawing
	-- prose the column no longer has the height for.
	local tallest = 0
	for index = 1, pane.stats:Lines() do
		local line = pane.stats.lines[index]
		if line:IsShown() then
			tallest = math.max(tallest, line:GetHeight())
		end
	end
	check(tallest > 0 and tallest <= ns.UI.Metric.row,
		("the tallest row in the stats column is %d px and a compact row is one line")
			:format(tallest))
	readout = pane.stats.view.extent
	column = pane.left[1]:GetWidth()
	stats = pane.stats.frame:GetWidth()

	-- And what the row keeps back is what a hover hands over: the value the
	-- column may have clipped, then the sentence. A compact row with no hover is
	-- the whole bargain broken and nothing else on the page would show it.
	local row
	for index = 1, pane.stats:Lines() do
		local line = pane.stats.lines[index]
		if line:IsShown() and line.hint and line.hint.note then
			row = row or line
		end
	end
	check(row ~= nil, "no row in the stats column carries a sentence for its hover")
	ns.UI.Tooltip.Close(true)
	row:GetScript("OnEnter")(row)
	check(ns.UI.Tooltip.IsShown(), "hovering a stat said nothing")
	check(ns.UI.Tooltip.Lines() >= 3,
		("a stat's hover drew %d lines and it has a name, a value and a sentence")
			:format(ns.UI.Tooltip.Lines()))
	row:GetScript("OnLeave")(row)
	ns.UI.Tooltip.Close(true)

	-- And the row that carries the hover must not carry the click. This column is
	-- three hundred pixels wide and runs the height of the monitor: a row that
	-- took clicks the ordinary way was a band down the right of the sheet with no
	-- camera in it. Same flag on the four readings across the head, which are
	-- forty-four pixel discs in the middle of the same band.
	check(row:IsMouseEnabled() and not row:IsMouseClickEnabled(),
		"a stat row takes clicks, so a right drag begun on the stats column does not turn the camera")
	for index = 1, #pane.head.badges do
		local badge = pane.head.badges[index]
		check(badge:IsMouseEnabled() and not badge:IsMouseClickEnabled(),
			("reading %d takes clicks, so a right drag begun on it does not turn the camera")
				:format(index))
	end

	-- And it is beside the gear rather than over it. pane.width is the whole area
	-- the figure stands behind now rather than the portrait's own slice, so it
	-- and the stats column are the two numbers that have to add up to no more
	-- than the page was given. A column overlapping the rows would still draw,
	-- still measure and still pass every check above this one.
	local block = pane.width + pane.stats.frame:GetWidth()
	check(block <= pane.frame:GetWidth(),
		("the gear area and the stats column come to %d on a %d wide page")
			:format(block, pane.frame:GetWidth()))
end

----------------------------------------------------------------------
-- A row, and what is written along it
----------------------------------------------------------------------

do
	local pane = Window.Pane(GEAR)
	local head, shirt, hand
	for _, box in ipairs(pane.squares) do
		if box.entry.slot == 1 then
			head = box
		elseif box.entry.slot == 4 then
			shirt = box
		elseif box.entry.slot == 16 then
			hand = box
		end
	end

	-- The name is the whole point of the change and it is the item's own, in the
	-- item's own colour. An empty slot says what the slot is for instead: a blank
	-- line beside a silhouette is a row you have to work out.
	check(head.name ~= nil, "a worn slot drew no name beside it")
	check(head.name:GetText() ~= nil and head.name:GetText() ~= "",
		"the helmet slot drew an empty name")
	check(shirt.name:GetText() == shirt.entry.label,
		("an empty slot says %s rather than what the slot is for")
			:format(tostring(shirt.name:GetText())))

	-- The line under the name carries the item level, which the page has averaged
	-- for a while and never shown one of.
	check(head.note:GetText() == "60",
		("the helmet is item level 60 and its line reads %s")
			:format(tostring(head.note:GetText())))

	-- The weapons are rows in the left column now rather than three bare discs
	-- centred under the figure, so every one of the nineteen says what is in it.
	-- That was the last place on the page you could not read what you were
	-- holding, and it is the arrangement both of the sheets this page is drawn
	-- against have.
	check(hand.name ~= nil, "a weapon is still a nameless disc under the figure")
	check(hand.entry.side == "left",
		("the main hand is drawn in the %s group and the columns are the only two")
			:format(tostring(hand.entry.side)))

	-- Every row is over the figure. A model is drawn over every texture layer of
	-- the frame holding it, so a row left at the pane's own level is a row the
	-- client draws the character on top of, and nothing about that fails loudly.
	check(head:GetFrameLevel() > pane.panel:GetFrameLevel(),
		("a row sits at level %d and the figure's panel at %d")
			:format(head:GetFrameLevel(), pane.panel:GetFrameLevel()))
	check(head.button:GetFrameLevel() > head:GetFrameLevel(),
		"the secure button is under its own row, so a click on the name misses it")

	-- Two columns, and they are apart rather than adjacent: the gap between them
	-- is where the figure stands.
	local left, right = pane.left[1], pane.right[1]
	check(left:GetWidth() > 36 and right:GetWidth() > 36,
		"a column came out no wider than its disc, so no name would fit in it")
	check(left:GetWidth() + right:GetWidth() < pane.width,
		"the two columns fill the gear area and leave the figure nothing to stand in")
end

----------------------------------------------------------------------
-- The shape of the page, on a screen rather than in a window
--
-- The sheet is the size of the monitor now, and the three things that went
-- wrong the first time it was drawn on one all went wrong the same way: the
-- layout tracked the width it was handed rather than sizing itself. The figure
-- filled the page and was cropped at the crown and the knees, the two columns
-- were flung at the far edges of an ultrawide, and the stats fell off the side.
-- Every check here is one of those three, and none of them fails visibly: a
-- cropped model, a column against an edge and a column past the edge all draw
-- perfectly and measure fine.
----------------------------------------------------------------------

do
	local pane = Window.Pane(GEAR)
	local page = pane.frame:GetHeight()

	-- A portrait, not a landscape. The client scales a model to the width of its
	-- frame, so a panel wider than a person is a person taller than the panel.
	check(pane.panel:GetHeight() > pane.panel:GetWidth() * 1.9,
		("the figure stands in a %d by %d panel and a person is about one to two")
			:format(pane.panel:GetWidth(), pane.panel:GetHeight()))
	check(pane.panel:GetHeight() < page,
		"the figure fills the page top to bottom, so his head and his feet are off it")

	-- And the block is in the middle of the page rather than pinned to its
	-- edges. Measured off the row nearest each edge, because that is what a
	-- player sees: the name of a helmet a third of a screen from the helmet.
	local leftEdge = pane.left[1]:GetLeft() - pane.frame:GetLeft()
	check(leftEdge > 0,
		("the first column starts %d units from the page edge and the page is %d wide")
			:format(leftEdge, pane.frame:GetWidth()))

	-- The stats are still on the page. They came off it once, when the column
	-- was only drawn if the width left room for it after two columns and a
	-- stage, and nothing on the page said so.
	check(pane.stats.frame:IsShown() and pane.stats.frame:GetWidth() > 0,
		"the stats column is not drawn at all")
	check(pane.head:IsShown(), "your name and the four readings are not drawn at all")
	check(pane.stats.frame:GetRight() <= pane.frame:GetRight() + 1,
		"the stats column runs off the right of the page")
end

----------------------------------------------------------------------
-- Sockets
--
-- The Burning Crusade put holes in gear and this addon has never read one. Two
-- calls answer half each: the link says what is in it, GetItemStats says how
-- many are open, and neither says which position an open one is. So the dots
-- draw filled first and open after, which is the only order the client supports.
----------------------------------------------------------------------

do
	local pane = Window.Pane(GEAR)
	local head, neck
	for _, box in ipairs(pane.squares) do
		if box.entry.slot == 1 then
			head = box
		elseif box.entry.slot == 2 then
			neck = box
		end
	end

	local filled, open = ns.ItemSockets(Worn.Link(1))
	check((filled and #filled or 0) + open > 0,
		"the helmet fixture carries no sockets, so nothing below is being measured")

	local shown = 0
	for index = 1, #head.dots do
		if head.dots[index]:IsShown() then
			shown = shown + 1
		end
	end
	check(shown == (filled and #filled or 0) + open,
		("%d dots drew for %d gems and %d holes")
			:format(shown, filled and #filled or 0, open))
	dots = shown

	-- And a piece with no holes draws none, which is most of what anybody wears.
	for index = 1, #neck.dots do
		check(not neck.dots[index]:IsShown(),
			"a piece with no sockets drew a dot under its name")
	end
end

Window.Hide()

print(("gear   %d slots in two columns %d wide, the figure behind them, %d px of stats beside; %d dots under the helmet, %d px of readout")
	:format(#Window.Pane(GEAR).squares, column, stats, dots, readout))
