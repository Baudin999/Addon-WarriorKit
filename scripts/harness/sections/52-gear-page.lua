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
local Stats = ns.CharStats

-- What the line at the foot reports, filled in by the blocks that measure it.
-- Locals rather than H.carry: that table is for a number one section hands to a
-- later one, and every one of these is taken and read out in this file.
local column, stats, readout, dots, turned = 0, 0, 0, 0, 0

-- The heading the three miss rows sit under, named because the fold below reads
-- it twice and 52-character.lua reads it six times: the two files are looking at
-- the same group from either end.
local MISSING = "Missing a boss, three levels up"

local function Find(groups, title, label)
	for _, group in ipairs(groups) do
		if group.title == title then
			for _, row in ipairs(group.rows) do
				if row.label == label then
					return row
				end
			end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- The nineteen slots
----------------------------------------------------------------------

do
	Window.Show()
	local pane = Window.Pane()
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

	-- The rule is an underscore under the name, so it is measured against the
	-- letters and never against the row. A name is anchored at both ends so it
	-- can clip rather than wrap, which makes the frame's own width the width of
	-- the column: taken off that, a full piece drew a green line from its name
	-- across the row and out into the middle of the page, and nothing here said
	-- so, because a rule that is too long draws perfectly and measures fine.
	--
	-- The helmet is at forty percent, so the check is the arithmetic itself
	-- rather than a ceiling. It has to be: this stub does not model a region
	-- sized by two opposing anchors, so the name answers nothing for its own
	-- frame width and a ceiling taken off that would hold whichever width the
	-- code had used.
	local letters = head.name:GetStringWidth()
	check(math.abs(head.wear:GetWidth() - letters * 0.4) <= 1,
		("the wear line came out %d wide and 40%% of the name is %.1f")
			:format(head.wear:GetWidth(), letters * 0.4))
	check(head.wear:GetWidth() < head:GetWidth(),
		"the wear line is as wide as the whole row rather than as wide as the name")

	-- And it is between the name and the item level rather than through either.
	-- Both used to hang off the name's own bottom edge, so the line was drawn
	-- across the foot of the letters with the number sitting on top of it.
	check(head.wear:GetTop() <= head.name:GetBottom(),
		"the wear line is drawn through the name rather than under it")
	check(head.wear:GetBottom() >= head.note:GetTop(),
		"the wear line and the item level are drawn on top of each other")

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

	-- Compact means one line a row, and a bar under it where the row has a
	-- fraction. The sentence that used to wrap underneath is in the hover, so a
	-- plain row taller than one line is a row still drawing prose the column no
	-- longer has the height for.
	--
	-- Both kinds are on this column since the skills folded into it: a stat is a
	-- name and a number, a weapon skill is that with how far along it is under
	-- it. So the two are measured apart, because one ceiling over both would be
	-- the taller one and would stop saying anything about the plain rows.
	local plain, withBar = 0, 0
	for index = 1, pane.stats:Lines() do
		local line = pane.stats.lines[index]
		if line:IsShown() and line.label:IsShown() then
			if line.track:IsShown() then
				withBar = math.max(withBar, line:GetHeight())
			else
				plain = math.max(plain, line:GetHeight())
			end
		end
	end
	check(plain > 0 and plain <= ns.UI.Metric.row,
		("the tallest plain row in the stats column is %d px and a compact row is one line")
			:format(plain))
	check(withBar > plain and withBar <= ns.UI.Metric.row + 12,
		("a skill row came out %d px against a plain row's %d, and it is one line plus a bar")
			:format(withBar, plain))
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
	local pane = Window.Pane()
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
-- The wash a name is read on
--
-- The page has no ground, so a name is drawn over whatever the player is
-- standing on and a white name on snow is a name you lean in to read. Each
-- filled row carries a black gradient the size of its own two strings, solid at
-- the disc and gone by the far end of the text.
--
-- Every check here is one that fails silently. A wash sized off the wrong
-- string, one that never grew after the repaint set the text, one drawn under
-- the word "trinket" on an empty row and one running backwards along the right
-- hand column all draw a rectangle and all measure fine. The direction is the
-- worst of them: a right hand row washed the wrong way is solid where there is
-- no text and clear under every letter, which is worse than no wash at all.
----------------------------------------------------------------------

do
	local pane = Window.Pane()
	local M, C = ns.UI.Metric, ns.UI.Color
	local head, shirt, ring
	for _, box in ipairs(pane.squares) do
		if box.entry.slot == 1 then
			head = box
		elseif box.entry.slot == 4 then
			shirt = box
		elseif box.entry.slot == 11 then
			ring = box
		end
	end

	check(head.wash ~= nil, "a filled row has no wash under its name")
	check(head.wash:IsShown(), "the helmet's name is drawn on the grass")
	check(head.wash.layer == "BACKGROUND",
		("the wash is on %s, so it is drawn over the name it is meant to be under")
			:format(tostring(head.wash.layer)))

	-- As tall as the two strings plus eighteen. Not the row: the row is the disc,
	-- thirty-six pixels, and a wash cut to that is a name with its ascenders out
	-- in the open.
	local tall = ns.UI.TextHeight(head.name, M.font) + ns.UI.TextHeight(head.note, M.small)
	check(math.abs(head.wash:GetHeight() - (tall + 18)) <= 0.01,
		("the wash came out %.1f tall and the two strings are %.1f")
			:format(head.wash:GetHeight(), tall))

	-- And as wide as the wider of them plus forty-eight, off the letters rather
	-- than off the frame. A name is anchored at both ends so it can clip, which
	-- makes its frame the width of the column every time: taken off that, every
	-- wash on the page would be the same width and it would be the whole row.
	local letters = math.min(head.name:GetStringWidth(), head.name:GetWidth())
	local note = head.note:GetStringWidth()
	check(math.abs(head.wash:GetWidth() - (math.max(letters, note) + 48)) <= 0.01,
		("the wash came out %.1f wide and the longer string is %.1f")
			:format(head.wash:GetWidth(), math.max(letters, note)))
	check(head.wash:GetWidth() <= head:GetWidth() + 4,
		"the wash is wider than the row it is under, so it runs out over the figure")

	-- A different name is a different width. One wash the size of the longest
	-- name on the page would pass every arithmetic check above on the row that
	-- name is in.
	check(head.wash:GetWidth() ~= ring.wash:GetWidth(),
		"two rows with different names drew the same wash, so it is not measured per row")

	-- Re-measured by the repaint and not only at build. The strings take their
	-- text in the repaint, so a wash sized once at build is a wash sized against
	-- an empty string, and the row it is worst on is the one whose item changed
	-- while the page was open.
	head.wash:SetSize(7, 7)
	pane:Paint()
	check(math.abs(head.wash:GetWidth() - (math.max(letters, note) + 48)) <= 0.01,
		("a repaint left the wash %.1f wide, so it is sized at build and never again")
			:format(head.wash:GetWidth()))

	-- Nothing in the slot, nothing under it. The row still says what the slot is
	-- for, dimmed, and eight of the nineteen are empty on most characters.
	check(not shirt.wash:IsShown(),
		"an empty slot drew a shadow under the word it puts there instead of a name")

	-- Which end is solid. The client runs a horizontal gradient min at the left,
	-- so a left hand row is solid at min and a right hand row is solid at max,
	-- and the far end of both is the same colour at no alpha rather than black.
	local wash = head.wash:GetGradient()
	check(wash ~= nil and wash.orientation == "HORIZONTAL",
		"the wash under a row runs down the page rather than along the row")
	check(wash.min[4] == C.shadow[4] and wash.max[4] == 0,
		("a left hand row washes from %s to %s and the disc is on its left")
			:format(tostring(wash.min[4]), tostring(wash.max[4])))
	check(wash.max[1] == C.shadow[1] and wash.max[2] == C.shadow[2]
		and wash.max[3] == C.shadow[3],
		"the wash fades to a different colour rather than to nothing")

	check(ring.entry.side == "right",
		"the ring is not in the right hand column, so nothing below measures the other direction")
	local other = ring.wash:GetGradient()
	check(other.min[4] == 0 and other.max[4] == C.shadow[4],
		("a right hand row washes from %s to %s and its disc is on the right")
			:format(tostring(other.min[4]), tostring(other.max[4])))
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
	local pane = Window.Pane()
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
-- Skills
--
-- Here rather than in 52-character.lua because this is the page they are drawn
-- on. Character/Skills.lua answers on its own, without the column, and every
-- claim below is about the list it hands over rather than about the rows the
-- fold under it puts on the screen.
----------------------------------------------------------------------

do
	local groups = ns.CharSkills.Groups()
	check(#groups == 2, ("%d skill groups were drawn and the client listed two"):format(#groups))
	check(H.expandedSkills() == 1,
		("the skill headers were expanded %d times and once is the whole of it")
			:format(H.expandedSkills()))

	local axes = Find(groups, "Weapon Skills", "Axes")
	local swords = Find(groups, "Weapon Skills", "Swords")
	check(axes ~= nil and axes.note == nil,
		"a weapon skill at the cap for your level still carries a sentence")
	check(swords ~= nil and swords.note ~= nil and swords.note:find("10 points short", 1, true),
		("a weapon skill ten points short reads %s"):format(tostring(swords and swords.note)))
	check(axes.fraction ~= nil and math.abs(axes.fraction - 1) < 1e-6,
		"a skill at the cap did not draw a full bar")

	-- A profession is told from a weapon skill by what it caps at and whether
	-- it can be abandoned, not by the header it sits under, because every
	-- header on this page is a localised string.
	local craft = Find(groups, "Professions", "Blacksmithing")
	check(craft ~= nil and craft.note == nil,
		"a profession was treated as a weapon skill and told what it costs you")

	local behind, worst = ns.CharSkills.Behind()
	check(behind == 1 and worst == 10,
		("%d weapon skills behind by at most %d, and one by ten is the fixture")
			:format(behind, worst))
end

----------------------------------------------------------------------
-- The fold
--
-- Skills were a tab and are a group in the stats column. Two lists appended,
-- which is only a fold at all because both sides already hand back the same
-- shape, so what is worth asserting is the seam: that both are in the column,
-- that the stats come first, and that nothing was dropped in the join.
--
-- The order is the argument for the fold rather than a preference. The badge at
-- the head of this column says how often you miss, a weapon skill under the cap
-- is what that number is computed from, and the two were a tab press apart. Put
-- the skills above the miss rows and they are a list you scroll past to reach
-- the number they explain.
----------------------------------------------------------------------

do
	Window.Show()
	local groups = Window.Pane().stats.groups

	check(Find(groups, MISSING, "a special") ~= nil,
		"the stats are not in the column the sheet draws down its right")
	check(Find(groups, "Weapon Skills", "Swords") ~= nil,
		"the skills tab is gone and its rows did not land in the stats column")
	check(Find(groups, "Professions", "Blacksmithing") ~= nil,
		"only the weapon skills came across, so a profession is on no page at all")

	local missAt, skillAt
	for index = 1, #groups do
		if groups[index].title == MISSING then
			missAt = index
		elseif groups[index].title == "Weapon Skills" then
			skillAt = index
		end
	end
	check(missAt ~= nil and skillAt ~= nil and skillAt > missAt,
		("the miss rows are group %s and the weapon skills group %s, so the column opens on the skills")
			:format(tostring(missAt), tostring(skillAt)))
	check(#groups == #Stats.Groups() + #ns.CharSkills.Groups(),
		("the column holds %d groups and the two lists have %d between them")
			:format(#groups, #Stats.Groups() + #ns.CharSkills.Groups()))

	-- The sentence under a weapon skill went into the hover with it. A compact
	-- row draws one line and keeps the rest, which is the bargain the stats
	-- column already made, so a skill ten points short still says what that
	-- costs and says it by being pointed at.
	local swords
	local pane = Window.Pane().stats
	for index = 1, pane:Lines() do
		local line = pane.lines[index]
		if line.hint and line.hint.label == "Swords" then
			swords = line
		end
	end
	check(swords ~= nil, "no row in the stats column is the Swords skill")
	check(swords.hint.note ~= nil and swords.hint.note:find("10 points short", 1, true),
		"the skill row in the column carries nothing for its hover to say")
	check(swords.note:IsShown() == false,
		"a compact row drew the sentence on the page as well as in the hover")
end

----------------------------------------------------------------------
-- Sockets
--
-- The Burning Crusade put holes in gear and this addon has never read one. Two
-- calls answer half each: the link says what is in it, GetItemStats says how
-- many are open, and neither says which position an open one is. So the dots
-- draw filled first and open after, which is the only order the client supports.
--
-- A disc carries the gem now rather than standing in for it, so what the
-- helmet's first disc draws is the ruby's own icon cut to a circle, and its
-- ring is the gem's quality colour. The count came first and is still here,
-- because a disc that draws the right picture in the wrong number of places is
-- the same bug it always was.
--
-- What cannot be asserted is the socket's own colour, and that is the data
-- rather than a gap in this section: an item link carries the gem sitting in
-- each filled hole and nothing whatever about the empty ones. So an empty disc
-- is neutral on purpose, the assertion below says so, and the hover is where a
-- socket gets named.
----------------------------------------------------------------------

do
	local pane = Window.Pane()
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

	-- The gem itself. Filled first is what the block above measures, so the
	-- helmet's ruby is the first disc whichever socket it is actually sitting in.
	local gem = filled and filled[1]
	local _, art = ns.ItemInfo(gem or "")
	check(art and head.dots[1].gem:GetTexture() == art,
		"the filled socket drew no gem icon, so the disc is still a mark saying a gem is there")
	check(head.dots[1].gem.masks and #head.dots[1].gem.masks == 1,
		"the gem icon carries no mask, so a square picture is sitting in a round hole")
	check(head.dots[1].gem:GetWidth() < head.dots[1]:GetWidth(),
		"the gem icon is as wide as its own disc, so there is no ring left to carry a colour")

	local tone = ns.UI.Quality[ns.ItemValue(gem)]
	local r, g, b, a = head.dots[1]:GetVertexColor()
	check(tone and r == tone[1] and g == tone[2] and b == tone[3] and a == 1,
		"a filled socket's ring is not the gem's own quality colour at full strength")

	-- The hole is the same disc with nothing in it, and neutral because there is
	-- no call that says what colour an empty socket is. Half strength is the
	-- whole of what separates a place for a gem from a gem, so it is asserted
	-- against the filled disc's alpha rather than against a number written here.
	local edge = ns.UI.Color.edge
	local hr, hg, hb, ha = head.dots[2]:GetVertexColor()
	check(not head.dots[2].gem:IsShown(), "an empty socket drew a gem")
	check(hr == edge[1] and hg == edge[2] and hb == edge[3],
		"an empty socket is not the panel's edge colour, so the page invented a socket colour the link never carried")
	check(ha < a, "an empty socket is as strong as a filled one, so a hole reads as a gem")

	-- Where the socket is named, which is the row's hover and not a second one
	-- hung off the disc. Aimed at rather than called: a disc is a texture and
	-- takes no mouse, so the pointer over a disc is the pointer over the row, and
	-- the day somebody makes a disc a frame to put its own tooltip on, this is
	-- the line that says the row went quiet underneath it.
	local mouse = H.mouse
	local x, y = mouse.Point(head.dots[1])
	check(mouse.At(x, y) == head,
		"pointing at a socket disc does not reach the row, so the hover that names the socket never opens")

	-- And what that hover has to carry is the line the disc cannot draw, seeded
	-- here the way every other tooltip fixture is. The client writes it and the
	-- addon only reads it: "Yellow Socket" exists nowhere else, in this harness
	-- or in the game.
	H.tooltips.inventory[H.tooltipKey("player", 1)] = {
		{ "Lionheart Helm" }, { "Head, Plate" }, { "Yellow Socket" },
	}
	ns.UI.Tooltip.Close(true)
	mouse.Deliver(head, "OnEnter")
	check(ns.UI.Tooltip.IsShown(),
		"the pointer is on the sockets and the row said nothing, so a hole has no name anywhere")
	local named = false
	for index = 1, ns.UI.Tooltip.Lines() do
		named = named or (ns.UI.Tooltip.Text(index) or ""):find("Socket") ~= nil
	end
	check(named,
		"the row's hover carries no socket line, so the colour a disc cannot draw is nowhere on the page")
	mouse.Deliver(head, "OnLeave")
	ns.UI.Tooltip.Close(true)
	H.tooltips.inventory[H.tooltipKey("player", 1)] = nil
end

----------------------------------------------------------------------
-- The figure is yours to turn
--
-- Three gestures on one model, and none of them is visible in a rectangle. A
-- turn, a walk nearer and a pair of weapons are four numbers handed to the
-- client, so the client stub in client/13-character.lua keeps them and this
-- reads them back. Without that they are four calls into a no-op and a figure
-- that never moved would pass every assertion here.
--
-- What each block is for, and each one is a bug that has a name:
--
--   A right press arms nothing. The right button is the camera's and the sheet
--   is half the screen, so a figure that took the right drag would spin every
--   time the player tried to look around.
--
--   The wheel stops at both ends. There is no reset on this page and the sheet
--   fills half a monitor: a figure wound out of that half is only undone by
--   winding the wheel back, and a clamp that is off by a notch is invisible
--   until somebody scrolls.
--
--   The pose survives a redress. SetUnit builds the figure again from nothing,
--   so an angle applied once at login would be gone the first time you put a
--   ring on, and the page would still measure perfectly.
--
--   And every one of the three is written to this character's own saved
--   variables at the moment it moves, which is what "the sheet opens the way
--   you left it" is made of.
--
-- Every press here is aimed at a point and delivered by H.mouse, so the stub
-- decides who gets it. That matters more here than in most sections: the whole
-- claim is that a press on the figure reaches the figure, and a handler called
-- by name proves it about a frame that might be under the page.
----------------------------------------------------------------------

do
	local pane = Window.Pane()
	local model = pane.panel.model
	local mouse = H.mouse
	local x, y = mouse.Point(model)

	check(model:IsMouseEnabled(), "the figure answers no mouse, so no drag reaches him")
	check(mouse.At(x, y, "LeftButton") == model,
		"a press aimed at the middle of the figure lands on something else")
	check(ns.UI.Ticking("figure", model) == nil,
		"the figure is turning before anybody has touched him")

	-- A right press arms no turn, and it is delivered rather than aimed.
	--
	-- The figure is handed to ns.UI.PassCamera like every row on this page and
	-- the stub honours that call, so a right press aimed at him here goes past
	-- him entirely. That is the 10.1.5 answer and not this client's: on 2.5.6 the
	-- probe fails and the game hands the model the right button anyway. So the
	-- half worth asserting is the guard inside the handler, which is the one that
	-- runs in the game, and Deliver is how a press reaches a frame the call the
	-- game does not have would have spared it.
	mouse.Deliver(model, "OnMouseDown", "RightButton")
	check(ns.UI.Ticking("figure", model) == nil,
		"a right press armed the turn, so the drag that turns the camera spins the figure")

	-- A left drag turns him, and the angle is written down as it moves.
	local facing = model:GetRotation()
	check(mouse.Grab(x, y, "LeftButton") == model,
		"a left press aimed at the figure landed somewhere else")
	check(ns.UI.Ticking("figure", model) ~= nil,
		"a left press armed nothing, so a drag on the figure turns nothing")
	mouse.Move(x + 100, y)
	turned = model:GetRotation() or 0
	check(turned ~= facing, "a hundred pixels of drag turned the figure nowhere")
	check(ns.dbc.figureFacing == turned,
		"the figure turned and this character's saved pose did not follow him")
	mouse.Drop(x + 100, y)
	check(ns.UI.Ticking("figure", model) == nil,
		"the button came up and the figure is still turning")

	-- The wheel walks him nearer, and stops.
	check(select(1, mouse.Wheel(x, y, 1)) == model,
		"a wheel notch over the figure reaches something else")
	check(ns.dbc.figureNear > 0, "a notch of the wheel walked the figure nowhere")
	check(model.camScale < 1 and select(3, model:GetPosition()) < 0,
		"the wheel moved the camera or the figure but not both, so a close look is a look at his boots")

	for _ = 1, 40 do
		mouse.Wheel(x, y, 1)
	end
	check(ns.dbc.figureNear == 1 and model.camScale == 0.5,
		("forty notches in left the camera at %s, and the near end is half distance")
			:format(tostring(model.camScale)))

	for _ = 1, 80 do
		mouse.Wheel(x, y, -1)
	end
	check(ns.dbc.figureNear == 0 and model.camScale == 1
		and select(3, model:GetPosition()) == 0,
		("eighty notches out left the figure at %s, and the far end is where he starts")
			:format(tostring(ns.dbc.figureNear)))

	-- The weapons, on a mark in the corner of the figure rather than a row on a
	-- settings page. Pressed where it is drawn, which is the assertion that it is
	-- reachable at all: a mark on a model has to beat the model's own frame level
	-- or it is paint.
	local mark = pane.panel.mark
	local away = model:GetSheathed()
	mouse.On(mark, "LeftButton")
	check(model:GetSheathed() ~= away, "the mark was pressed and the weapons did not move")
	check(ns.dbc.figureSheathed == model:GetSheathed(),
		"the weapons moved and this character's saved pose did not follow them")

	-- And all of it survives the model being built again, which is every gear
	-- swap.
	mouse.Wheel(x, y, 3)
	local walked = model.camScale
	pane.panel.Dress()
	check(model:GetRotation() == turned and model.camScale == walked
		and model:GetSheathed() ~= away,
		"a redress put the figure back the way the client draws him and lost the pose")

	-- Left as it was found, because the pose is saved state and the sections
	-- after this one read a clean character file.
	ns.dbc.figureFacing = ns.DefaultCopy("figureFacing")
	ns.dbc.figureNear = ns.DefaultCopy("figureNear")
	ns.dbc.figureSheathed = ns.DefaultCopy("figureSheathed")
	pane.panel.Dress()
end

Window.Hide()

print(("gear   %d slots in two columns %d wide, the figure behind them turning to %.2f rad, %d px of stats beside; %d socket discs under the helmet, one of them the gem's own icon, %d px of readout")
	:format(#Window.Pane().squares, column, turned, stats, dots, readout))
