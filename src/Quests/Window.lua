local ADDON, ns = ...

local Window = {}
ns.QuestWindow = Window

local UI = ns.UI
local C, M = UI.Color, UI.Metric
local Log, Where, Chart = ns.QuestLog, ns.QuestWhere, UI.Chart

--------------------------------------------------------------------------
-- The quest log
--
-- Three columns: what you are on, what this one says, and what it pays.
--
-- **The client's log is six lines and a scrollbar.** That is the whole reason
-- this exists. Twenty quests do not fit in six lines, so the log you are
-- carrying is something you scroll a strip to see one eighth of, and the text
-- of the quest you clicked appears in the same window by pushing the list off
-- it. Every question a player actually opens the log to answer is a question
-- about the whole log at once. What can I hand in. What is near here. What have
-- I outlevelled. None of them can be asked of six lines.
--
-- So the left column is the log, all of it, zone by zone, and it does not move
-- when you click something. Sixty rows fit where the client drew six.
--
-- **The middle column is the objectives first and the story second.** The
-- client puts the giver's four paragraphs at the top and the list of what to
-- kill underneath, which is the right order the first time you read it and the
-- wrong order the other forty. You have read the story. What you came back for
-- is three of eight, so three of eight is at the top.
--
-- **And behind a tab, it is a map instead.** Three of eight what, and where. A
-- quest log answers the first and has never answered the second on any client:
-- the text says Kobold Miners and the world does not label them, so the answer
-- has always been a second addon, or a second window, or a website. Questie
-- already knows every spawn of every one of them and spends that on icons
-- scattered over the world map, where you have to go and find the quest again
-- among the other nineteen. This draws the zone at the size of one column with
-- that one quest's places on it, which is the same data asked the other way
-- round: not "what is in this zone" but "where is this quest".
--
-- The tab is two words and it stays where you left it. A player who wants the
-- map wants it for the next quest too, so clicking down the left column keeps
-- whichever side you are on and redraws it.
--
-- **The right column is the payoff and the where.** Rewards alone would leave
-- it empty for the many quests that pay coin and nothing else, which is a third
-- of a window spent on white space. Under them goes the one thing the client
-- cannot answer and Questie can: who takes this back, and how far away the
-- nearest thing you still have to kill is. Quests/Where.lua reads that, and
-- both lines are simply absent when Questie is not installed.
--
-- **The two right-hand columns are one pool of rows.** A quest's text is
-- between three and thirty lines and its rewards are between none and six, so
-- the obvious way to draw them is to build the frames the quest needs and throw
-- them away on the next click. This client cannot destroy a frame. Thrown away
-- means leaked, and leaked once per quest you click all evening. So there is
-- one row frame per line of each column, built once, carrying every region
-- either kind of line can want, and a click repaints them rather than making
-- any. It is the same argument UI/Window.lua's list makes, one layer down.
--
-- **Nothing here is on a ticker.** The log changes when the server says it
-- changed, which is four events, and every one of them ends in Refresh.
-- Questie's own quest update is a fifth and is not a ticker either: it says a
-- quest was accepted, updated, turned in or abandoned, and it says it after
-- Questie has redone the answers the right column draws. The
-- distance in the right column is the one number that goes stale between
-- events, and it is redrawn when you click a quest rather than five times a
-- second, because a quest log open on the screen is not a compass.
--------------------------------------------------------------------------

local WIDTH, HEIGHT = 810, 520

-- The two fixed columns. The middle takes whatever is left, which is the way
-- round it has to be: a zone name and an item name have a length the font
-- decides, and prose does not.
--
-- The list is thirty pixels wider than it was and the window is thirty wider
-- with it, so the middle column comes out at the width it always had. That is
-- what the three things on the right of a row cost: the number of party members
-- on the quest, the share mark and the abandon mark. Taking it out of the
-- middle instead would have paid for them with the map.
local LIST, PAY = 250, 200

-- One reward's picture, and the mark down the left of an objective line. Both
-- are the width their column reserves before the words start, so the ticks line
-- up down one edge and the icons down the other.
local SLOT, MARK = 22, 10

-- The tick, in the one place both columns read it from. It is a `V` because
-- that is the letter Media/Glyphs.ttf cuts the Font Awesome check onto, and a
-- `V` is what a client that refuses the font draws instead. Nothing here has to
-- know either of those things beyond this line.
local TICK = "V"

local window, list
local page, pay
local tabs, atlas
local showing = nil

-- The two sides of the middle column, and which one is up.
--
-- Kept between quests on purpose. It is the one piece of state in this window
-- that is a preference rather than a fact about what is selected: a player who
-- opened the map for one quest is a player who wants the map for the next one.
local TEXT, MAP = 1, 2
local facing = TEXT

-- Which of the quest's zones the map is on. Reset with the quest, because zone
-- three of the last quest is nothing at all on this one.
local zoneAt = 1

-- The most zones one quest is offered as a choice between. Six is more than any
-- quest on these clients has anything in, and a strip that wrapped onto a third
-- line would take the map's own height to say where the map could be.
local ZONES = 6

-- Whether Paint is the thing that moved the selection.
--
-- The list calls back on every Select that changes the id, and the callback
-- repaints, and the repaint selects. Without this latch the first paint of a
-- window runs twice, which is two reads of the quest log and six borrows of the
-- shared cursor to draw one quest. It is the same latch the mail window keeps
-- between a field and the draft behind it.
local painting = false

--------------------------------------------------------------------------
-- One line of a column
--
-- Every row in the middle and the right column is this frame. It carries the
-- three regions between them they can want: a picture for a reward, a mark for
-- an objective's tick, and the words. A line that wants none of the first two
-- hides them and starts its text at the left edge.
--------------------------------------------------------------------------

local function Cell(column, index)
	local row = column.pool[index]
	if row then
		return row
	end

	row = CreateFrame("Frame", nil, column.stack.frame)

	row.icon = UI.Icon(row, "ARTWORK")
	row.icon:SetSize(SLOT, SLOT)
	row.icon:SetPoint("TOPLEFT")
	row.icon:Hide()

	-- The glyph face rather than the text face, because the mark against a
	-- finished objective is a tick and there is no tick in a text font. The
	-- letters both sides of that pass through unchanged: `-` is a minus in
	-- either face, and a client that will not take the font file draws a `V`
	-- where the tick was.
	row.mark = UI.Glyph(row, M.glyph, C.quiet, "LEFT")
	row.mark:SetPoint("TOPLEFT")
	row.mark:SetWidth(MARK)
	UI.Wrap(row.mark, false)
	row.mark:Hide()

	row.text = UI.Label(row, M.font, C.text, "LEFT", UI.FLAT)
	row.text:SetPoint("TOPLEFT")
	UI.Wrap(row.text, true)
	row.text:SetSpacing(2)

	-- The hover is hung once and reads whatever link the row is carrying now,
	-- rather than being re-hung per repaint. A row with no link answers nothing
	-- and the tooltip does not open, which is what stops the previous item's
	-- text staying on screen over a line that is now a coin amount.
	--
	-- The subject names a kind and nothing else, which is the whole of what this
	-- file has to know about tooltips. The item's own stats come off the client
	-- through UI/Scan.lua, and the vendor and auction prices arrive from
	-- Feeds/Worth.lua without this file asking: it registered against the item
	-- kind once, at load, so a quest reward answers with the same two lines a
	-- mail attachment and a linked item do.
	ns.Tip.Hang(row, function(self)
		if not self.link then
			return nil
		end
		return { kind = "item", link = self.link, title = self.name }
	end)

	column.pool[index] = row
	return row
end

-- opts.text     the words, which always wrap
-- opts.size     the font height, defaulting to the body size
-- opts.color    what the words are drawn in
-- opts.gap      air under this line
-- opts.icon     a texture in the left column, at SLOT wide
-- opts.mark     a character in the left column, at MARK wide
-- opts.markColor  what that character is drawn in
-- opts.link     an item link, which turns the line into a hover
-- opts.name     the title that hover carries
local function Line(column, opts)
	column.at = column.at + 1
	local row = Cell(column, column.at)
	local size = opts.size or M.font
	local left = 0

	row.icon:SetShown(opts.icon and true or false)
	if opts.icon then
		row.icon:SetTexture(opts.icon)
		left = SLOT + M.rowGap
	end

	row.mark:SetShown(opts.mark and true or false)
	if opts.mark then
		local color = opts.markColor or C.quiet
		row.mark:SetText(opts.mark)
		row.mark:SetTextColor(color[1], color[2], color[3])
		left = MARK + M.rowGap
	end

	row.text:ClearAllPoints()
	row.text:SetPoint("TOPLEFT", left, 0)
	row.text:SetFontObject(UI.Font(size, UI.FLAT))
	local color = opts.color or C.text
	row.text:SetTextColor(color[1], color[2], color[3])
	row.text:SetText(opts.text or "")

	row.link, row.name = opts.link, opts.name
	row:EnableMouse(opts.link and true or false)
	row:Show()

	local stack = column.stack
	column.stack:Add(row, {
		gap = opts.gap or M.rowGap,
		measure = function(cell)
			row.text:SetWidth(math.max(stack.width - cell.indent - left, 1))
			local height = UI.TextHeight(row.text, size)
			return opts.icon and math.max(SLOT, height) or height
		end,
	})
	return row
end

-- The caption over a run of lines: the small dim word that says what the next
-- four are. The same job the list's headers do in the left column.
local function Caption(column, label)
	return Line(column, { text = label, size = M.small, color = C.quiet })
end

-- One captioned run of lines, or nothing at all.
--
-- Every block in either scrolling column goes through this, which is what makes
-- the two of them read as one interface: a caption in the small quiet size, its
-- lines under it a row gap apart, and one gutter of air before whatever comes
-- next. A block with nothing in it draws neither the caption nor the air, so a
-- quest with no rewards leaves no heading standing over a blank.
local function Block(column, caption, lines)
	if #lines == 0 then
		return false
	end
	Caption(column, caption)
	for index = 1, #lines do
		Line(column, lines[index])
	end
	column.stack:Space(M.gutter)
	return true
end

-- A column ready to be filled in again. Every line past the ones this quest
-- needs is hidden rather than unmade, and the frames stay in the pool for the
-- next quest to land on.
local function Start(column)
	column.at = 0
	column.stack.cells = {}
end

local function Finish(column)
	for index = column.at + 1, #column.pool do
		column.pool[index]:Hide()
	end
	column.stack:SetWidth(column.view.width or 0)
	column.view:Update(column.stack:Reflow())
end

--------------------------------------------------------------------------
-- The left column
--------------------------------------------------------------------------

-- The character in front of a row, and the whole of what says a quest is
-- finished.
--
-- The colour said it first and the colour could not carry it. A quest ready to
-- hand in is drawn in C.tick, which is a green two shades off the green the
-- level ladder gives every quest a few levels under you, so a log of grey
-- quests you have outlevelled is a log where nothing stands out. And the row
-- you have selected drops its own tint for the heading colour, so the one quest
-- you were reading was the one quest that could not tell you at all.
--
-- The mark is the same tick the objective lines use and the same width on every
-- row, finished or not, so the levels stay in a column. It was a "+" until the
-- glyph face learned a tick, and a plus is the mark for adding a thing rather
-- than for having finished one.
local function Mark(quest)
	if quest.complete then
		return TICK
	end
	if quest.failed then
		return "!"
	end
	return ""
end

-- What that mark is drawn in, whatever colour the words beside it take.
--
-- The row's own colour is thrown away for the row you have selected, so a log
-- that said "finished" in the row colour alone said it least about the quest
-- you were reading. The mark keeps its colour through the selection, which is
-- the whole reason it is a region of its own rather than two characters on the
-- front of the label.
local function MarkTint(quest)
	if quest.complete then
		return C.tick
	end
	if quest.failed then
		return C.loss
	end
	return C.quiet
end

-- One row's words. The level first, because a column grouped by zone is still
-- read down the level: what you can do now and what you came back for later is
-- the first cut anybody makes over a quest log.
local function Label(quest)
	return ("[%d] %s"):format(quest.level, quest.title)
end

-- The colour a row is drawn in. Green for a quest you can hand in, red for one
-- that has failed, and the client's own XP ladder for everything else, which is
-- the same ladder the enemy bars colour a mob's level with. A quest log that
-- says "this one is finished" and "this one will kill you" in colour is a quest
-- log you can read without reading it.
local function Tint(quest)
	if quest.complete then
		return C.tick
	end
	if quest.failed then
		return C.loss
	end
	return ns.Unit.Level.WorthOf(quest.level)
end

-- What the left column holds, as the rows UI.List draws.
--
-- Public for the reason the aura rows and the meter are named: the harness has
-- to be able to measure what was drawn, and the alternative is this file handing
-- out a reference to the list widget itself. It is also the one place the two
-- facts a log is read at a glance for are decided, so a section can hold both
-- to a colour rather than to a screenshot.
function Window.Rows()
	local rows = {}
	for _, zone in ipairs(Log.Zones()) do
		if #zone.quests > 0 then
			rows[#rows + 1] = { header = zone.name }
			for _, quest in ipairs(zone.quests) do
				local company = #(quest.party or {})
				rows[#rows + 1] = {
					id = quest.key,
					label = Label(quest),
					color = Tint(quest),
					mark = Mark(quest),
					markColor = MarkTint(quest),
					-- How many of the people you are playing with are on this
					-- one. Absent rather than nought, because nobody having it
					-- and nothing being able to say are drawn the same and only
					-- one of them is a fact. Quests/Party.lua carries that.
					note = company > 0 and tostring(company) or nil,
				}
			end
		end
	end
	return rows
end

-- What one row's hover says, or nothing at all.
--
-- The number on the row is how many of the people you are playing with are on
-- this quest, and a number on its own is a fact you cannot act on. The names
-- are what you act on: you ask that person whether they want to do it now.
--
-- Nil where nobody has it, so no box opens rather than one opening empty. That
-- is also the answer on a client and an install that cannot tell, which is
-- correct: a hover that said "nobody" would be inventing the reading.
local function Company(row)
	local quest = Log.Quest(row.id)
	local names = quest and quest.party or nil
	if not names or #names == 0 then
		return nil
	end
	local lines = {}
	for at = 1, #names do
		lines[at] = { names[at] }
	end
	return { kind = "note", title = quest.title, lines = lines }
end

--------------------------------------------------------------------------
-- The middle column
--------------------------------------------------------------------------

-- The line under the title: where this quest belongs, what level it is, and
-- whether the client thinks you want help. One string because it is one
-- sentence, and the separator is the same dot the meter uses.
local function Tagline(detail)
	local quest = detail.quest
	local parts = { quest.zone, ("level %d"):format(quest.level) }
	if type(quest.tag) == "number" and quest.tag > 1 then
		parts[#parts + 1] = ("suggested group of %d"):format(quest.tag)
	elseif type(quest.tag) == "string" and quest.tag ~= "" then
		parts[#parts + 1] = quest.tag
	end
	if detail.seconds then
		parts[#parts + 1] = ("%d minutes left"):format(math.ceil(detail.seconds / 60))
	end
	-- Said in words as well as in the mark on the row, because a quest with no
	-- ticked list draws a summary sentence and nothing else, and that sentence
	-- reads the same whether you have done it or not. The deliveries and the
	-- talk-to-somebody ones are all of that kind.
	if quest.complete then
		parts[#parts + 1] = "ready to hand in"
	elseif quest.failed then
		parts[#parts + 1] = "failed"
	end
	return table.concat(parts, "  ·  ")
end

-- What is left to do, and the client's summary sentence where the quest has no
-- ticked list at all. One or the other, never both: the summary is the same
-- sentence the objectives spell out, so a quest with objectives that also drew
-- it would be saying the thing twice under one heading.
local function Ticks(detail)
	if #detail.objectives > 0 then
		local lines = {}
		for _, line in ipairs(detail.objectives) do
			lines[#lines + 1] = {
				text = line.text,
				color = line.done and C.dim or C.text,
				mark = line.done and TICK or "-",
				markColor = line.done and C.tick or C.quiet,
			}
		end
		return lines
	end
	if detail.summary ~= "" then
		return { { text = detail.summary } }
	end
	return {}
end

local function DrawPage(detail)
	Start(page)

	-- The title and the line under it are one unit and are the only two rows in
	-- either column outside a block. They carry a row gap between them and a
	-- gutter under, which is the same air a block leaves behind it, so the first
	-- caption sits the same distance below them as every later one sits below
	-- the block above it.
	Line(page, {
		text = detail.quest.title,
		size = M.heading,
		color = C.heading,
	})
	Line(page, {
		text = Tagline(detail),
		size = M.small,
		color = C.quiet,
		gap = M.gutter,
	})

	Block(page, "objectives", Ticks(detail))
	Block(page, "the quest",
		detail.description ~= "" and { { text = detail.description, color = C.dim } } or {})

	Finish(page)
end

--------------------------------------------------------------------------
-- The right column
--------------------------------------------------------------------------

-- Everything a block of the right column can hold, as line specs rather than as
-- drawn rows.
--
-- The two below answer lists and DrawPay decides the captions, which is the
-- whole reason they are shaped this way. A caption has to be added before the
-- rows it captions and a block only earns one if it has anything in it, so
-- something has to know the block is not empty before the first row is drawn.
-- The version that drew as it went could not, and the symptom was the one in
-- the screenshot: a quest paying coin and nothing else put two bare numbers at
-- the top of the column under no heading at all, beside a middle column where
-- every run of lines has one.

-- The items, whichever list they came off. Each carries the item's picture, its
-- name in its quality colour, the stack size where there is more than one, and
-- the item's own text in the hover.
--
-- That hover is why Quests/Client.lua reads the link at all. It is the only way
-- to answer "is this better than what I am wearing" without this addon carrying
-- an item database, and UI/Scan.lua is what reads the real text out of the
-- client to fill it.
local function Given(items)
	local lines = {}
	for _, item in ipairs(items) do
		lines[#lines + 1] = {
			text = item.count and ("%s x%d"):format(item.name, item.count) or item.name,
			size = M.small,
			color = UI.Quality[item.quality or 1] or C.text,
			icon = item.texture,
			link = item.link,
			name = item.name,
		}
	end
	return lines
end

-- The coin and the counts, in the order they matter to somebody handing a quest
-- in. Money first, because it is the one every quest has.
--
-- These go under the same caption as the items rather than one of their own. A
-- coin reward is a thing the quest gives you, and three headings over five lines
-- is a column of headings.
local function Paid(rewards, lines)
	if type(rewards.money) == "number" and rewards.money > 0 then
		lines[#lines + 1] = { text = ns.Coin(rewards.money), size = M.small }
	end
	if type(rewards.required) == "number" and rewards.required > 0 then
		lines[#lines + 1] = {
			text = ("costs %s"):format(ns.Coin(rewards.required)),
			size = M.small,
			color = C.loss,
		}
	end
	if type(rewards.xp) == "number" and rewards.xp > 0 then
		lines[#lines + 1] = {
			text = ("%d experience"):format(rewards.xp), size = M.small, color = C.dim,
		}
	end
	if type(rewards.honor) == "number" and rewards.honor > 0 then
		lines[#lines + 1] = {
			text = ("%d honor"):format(rewards.honor), size = M.small, color = C.dim,
		}
	end
	if type(rewards.title) == "string" and rewards.title ~= "" then
		lines[#lines + 1] = { text = rewards.title, size = M.small, color = C.heading }
	end
	-- The spell carries a picture the same way an item does, and it is drawn in
	-- the same column at the same size, because a reward you can see is a reward
	-- you can find again. It gets no hover: the client hands over a name and a
	-- texture and no spell id, so there is nothing for UI/Scan.lua to point at,
	-- and a tooltip that repeated the line under it would be worse than none.
	if rewards.spell then
		lines[#lines + 1] = {
			text = ("teaches %s"):format(rewards.spell.name),
			size = M.small,
			color = C.hint,
			icon = rewards.spell.texture,
		}
	end
	return lines
end

-- The two lines Questie pays for. Absent rather than empty when it is not
-- installed, because a caption over nothing is a window telling you it is
-- broken when it is doing exactly what it said it would.
local function Bearing(quest)
	local lines = {}
	local nearest, yards = Where.Nearest(quest.id)
	if nearest then
		lines[#lines + 1] = {
			text = yards and ("%s, %d yards"):format(nearest, yards) or nearest,
			size = M.small,
		}
	end
	local finisher = Where.Finisher(quest.id)
	if finisher then
		lines[#lines + 1] = {
			text = ("hand in to %s"):format(finisher),
			size = M.small,
			color = C.dim,
		}
	end
	return lines
end

local function DrawPay(detail)
	Start(pay)

	local rewards = detail.rewards
	local choices = rewards.choices or {}
	Block(pay, "choose one", Given(choices))
	-- The items you get regardless and the numbers under one caption, named for
	-- what is above it: after a list of choices these are the rest of the deal,
	-- and on their own they are the whole of it.
	Block(pay, #choices > 0 and "and also" or "reward",
		Paid(rewards, Given(rewards.items or {})))
	Block(pay, "where", Bearing(detail.quest))

	Finish(pay)
end

--------------------------------------------------------------------------
-- The map behind the tab
--------------------------------------------------------------------------

-- Everything under the map, as one sentence.
--
-- A line rather than a caption over an empty rectangle, because there are four
-- ways to have no map and a player deserves to know which one they have. Three
-- of them are somebody else's software not being there, and saying so is the
-- difference between "this addon is broken" and "Questie has not finished
-- compiling yet".
local function Note(quest, zones, drawn)
	if not Where.Ready() then
		return "Questie is not installed, so nothing here knows where a quest is."
	end
	if not Where.Compiled() then
		return "Questie is still compiling its database. This fills in when it is done."
	end
	if not quest then
		return ""
	end
	if #zones == 0 then
		return ("Questie has no row for %s. Type /wk quests where."):format(quest.title)
	end
	if drawn == 0 then
		return "This client has no map picture for that zone."
	end
	return "Blue is what is left to do, green is who takes it back, gold is you."
		.. " The wheel zooms in on whatever you are pointing at."
end

-- The strip of zones under the map, or nothing at all.
--
-- One quest in ten sends you to two places and the rest send you to one, so a
-- strip that was always drawn would be a row of one button under nine maps out
-- of ten. It is shown only where there is a choice, which is also the only time
-- a name on it tells you anything: with one zone the name is already the
-- heading over the map.
local function Choices(zones)
	local strip = atlas.zones
	for index = 1, ZONES do
		local zone = zones[index]
		strip:SetLabel(index, zone and (Chart.Name(zone.map) or "elsewhere") or "")
		strip:SetShown(index, zone ~= nil and index <= ZONES)
	end
	strip.frame:SetShown(#zones > 1)
	strip:Resize(atlas.width or 1)
	strip:Select(zoneAt)
	return #zones
end

-- What one dot says when you hover it: which zone, and how far across it.
--
-- The coordinates rather than the distance, and that is deliberate. A distance
-- is what the right column already gives for the one nearest thing, and it is
-- the number that goes stale the moment you walk; a coordinate is what you type
-- into the thing every player already has open, and it is true tomorrow.
local function Told(point)
	return ("%.1f, %.1f"):format(point.x, point.y)
end

local function DrawMap(quest)
	local zones = quest and Where.Places(quest.id) or {}
	if zoneAt > #zones or zoneAt < 1 then
		zoneAt = 1
	end
	local zone = zones[zoneAt]

	local points = {}
	if zone then
		for index = 1, #zone.points do
			local point = zone.points[index]
			point.note = Told(point)
			points[index] = point
		end
	end

	-- You, last, so the arrow is drawn over the blue dots rather than under
	-- them. There is nowhere on a quest map you are more likely to be standing
	-- than on top of the thing you are looking for.
	local here, x, y = Chart.Here()
	if zone and here == zone.map and x then
		-- The unit it is, as well as where it is. The board takes every point
		-- carrying one again on its own tick, which is how the arrow follows
		-- you across a zone with the window open, and a point that named no
		-- unit would be drawn once and then stand still while you walked.
		points[#points + 1] = { x = x, y = y, kind = Where.YOU, unit = "player",
			name = "you", note = Told({ x = x, y = y }) }
	end

	atlas.where:SetText(zone and (Chart.Name(zone.map) or "somewhere") or
		(quest and quest.title or ""))
	local drawn = atlas.board:Draw(zone and zone.map or nil, points)
	Choices(zones)
	atlas.note:SetText(Note(quest, zones, drawn))
	return #points
end

-- The map page: a heading, the board, the zones and the line under them, in
-- that order down one column. Built once, like everything else in this window.
local function Atlas(parent)
	local map = { width = 0 }
	map.frame = CreateFrame("Frame", "WarriorKitQuestMap", parent)

	map.where = UI.Label(map.frame, M.heading, C.heading, "LEFT", UI.FLAT)
	map.where:SetPoint("TOPLEFT")
	UI.Wrap(map.where, false)

	map.board = Chart.New(map.frame, "WarriorKitQuestChart")
	map.board.frame:SetPoint("TOPLEFT", map.frame, "TOPLEFT", 0, -(M.heading + M.rowGap))

	-- The strip is anchored under the board rather than measured, so a zone
	-- whose art is a different shape moves the two lines below it without
	-- anything here having to know the height. The board sets its own when it
	-- draws, and a board with nothing on it collapses to one pixel.
	map.zones = UI.TabStrip(map.frame, { onSelect = function(index)
		if painting then
			return
		end
		zoneAt = index
		Window.PaintMap()
	end })
	map.zones.frame:SetPoint("TOPLEFT", map.board.frame, "BOTTOMLEFT", 0, -M.gutter)
	for _ = 1, ZONES do
		map.zones:Add("")
	end

	map.note = UI.Label(map.frame, M.small, C.quiet, "LEFT", UI.FLAT)
	map.note:SetPoint("TOPLEFT", map.zones.frame, "BOTTOMLEFT", 0, -M.gutter)
	UI.Wrap(map.note, true)
	map.note:SetSpacing(2)

	return map
end

-- Which side of the tab is up. Both frames exist all the time and one of them
-- is hidden, rather than one being built when it is first asked for: a window
-- that made its map on the first click would take the cost of twelve textures
-- in the middle of a click instead of at login.
local function Face()
	page.frame:SetShown(facing == TEXT)
	atlas.frame:SetShown(facing == MAP)
end

--------------------------------------------------------------------------
-- The whole window
--------------------------------------------------------------------------

-- A column with its own scroll view, its own stack and its own pool of lines,
-- which is what both the middle and the right are.
local function Column(parent, name)
	local column = { pool = {}, at = 0 }
	-- Named for the reason the list beside it is, and the meter and the aura
	-- rows before that: a column that has laid itself out wrongly has to be
	-- measurable from a macro and from scripts/harness.lua, and the alternative
	-- is this file handing out a reference to its own frames.
	column.frame = CreateFrame("Frame", name, parent)
	column.view = UI.ScrollView(column.frame)
	column.view.frame:SetPoint("TOPLEFT")
	column.stack = UI.Stack(column.view.canvas)
	return column
end

local function Select(key, which, mods)
	if painting then
		return
	end
	-- Shift left click pins the quest as well as opening it, and UI.List's
	-- Press is what makes that reachable on the row you are already reading.
	--
	-- `which` is nil on every move the code makes, and it and `mods` arrive
	-- together, so this is the whole guard: a repaint cannot be mistaken for a
	-- press and a pin cannot be put on a quest nobody clicked.
	if which == "LeftButton" and mods.shift then
		Log.Pin(key, not Log.Pinned(key))
	end
	showing = key
	-- The zone, but not the tab. Zone three of the last quest is nothing at all
	-- on this one; the side of the tab you are on is a preference and survives.
	zoneAt = 1
	Window.Paint()
end

-- The two rules between the columns, and the three buttons in the footer.
local function Chrome()
	-- Down the middle of the gutter it divides rather than against one side of
	-- it, which is M.pad wide, so both halves of the air read as the same air.
	local HALF = M.pad / 2

	window.leftRule = UI.Rule(window.content, C.hairline, true)
	window.leftRule:SetPoint("TOPLEFT", list.frame, "TOPRIGHT", HALF, 0)
	window.leftRule:SetPoint("BOTTOMLEFT", list.frame, "BOTTOMRIGHT", HALF, 0)

	window.rightRule = UI.Rule(window.content, C.hairline, true)
	window.rightRule:SetPoint("TOPRIGHT", pay.frame, "TOPLEFT", -HALF, 0)
	window.rightRule:SetPoint("BOTTOMRIGHT", pay.frame, "BOTTOMLEFT", -HALF, 0)

	window.tally = UI.Label(window.footer, M.small, C.quiet, "LEFT", UI.FLAT)
	window.tally:SetPoint("LEFT", 0, 0)
	UI.Wrap(window.tally, false)

	window.abandon = UI.Button(window.footer, {
		label = "abandon",
		width = 76,
		onClick = function() Window.Abandon() end,
	})
	window.abandon:SetPoint("RIGHT", 0, 0)

	window.share = UI.Button(window.footer, {
		label = "share",
		width = 60,
		onClick = function() Window.Share() end,
	})
	window.share:SetPoint("RIGHT", window.abandon, "LEFT", -M.rowGap, 0)

	window.pin = UI.Button(window.footer, {
		label = "pin",
		width = 60,
		onClick = function() Window.Pin() end,
	})
	window.pin:SetPoint("RIGHT", window.share, "LEFT", -M.rowGap, 0)
end

-- Every column sized off the window, in one place rather than nine, because a
-- resolution change has to be able to call it again.
--
-- **The margin is the whole of what this got wrong the first time.** The three
-- columns were laid edge to edge inside the content frame, which spans the
-- window, so the list touched the left edge and the reward column ran under the
-- scrollbar and into the right one. The footer under them did not: UI/Window.lua
-- insets that by M.pad, and the result was a window whose buttons sat a
-- comfortable distance in from an edge its text was pressed against.
--
-- So the columns take the same M.pad on all four sides, and the two gutters
-- between them are the same number again. One measurement, five places, and
-- nothing in the window is a distance the eye has to accept as deliberate
-- because it is not repeated anywhere else.
function Window.Fit()
	if not window then
		return false
	end
	local body = window:Body() - M.pad * 2
	local middle = WIDTH - LIST - PAY - M.pad * 4

	list:Resize(LIST, body)

	-- The strip is measured rather than assumed, because a tab is as wide as
	-- its own title and two long ones would wrap onto a second line. What is
	-- left after it is what both sides of the tab get.
	local under = body - (tabs:Resize(middle) + M.gutter)
	page.frame:SetSize(middle, under)
	page.view:Resize(middle, under)

	atlas.frame:SetSize(middle, under)
	atlas.width = middle
	atlas.where:SetWidth(middle)
	atlas.note:SetWidth(middle)
	-- What the map is allowed to grow into when the wheel is turned. The column
	-- is taller than any zone's shape asks for at the width it gets, so at rest
	-- there is a block of nothing under the map and above the zone strip, and
	-- the wheel is what spends it.
	--
	-- Everything under the map is subtracted rather than measured, the strip
	-- included, and the strip is subtracted whether or not it is showing. One
	-- quest in ten has two zones, and a box that took the strip's height back on
	-- the other nine would be a map that changes size when you click a quest.
	-- The two lines reserved for the sentence at the bottom are the longest that
	-- sentence gets.
	atlas.board:Fit(middle, under - (M.heading + M.rowGap)
		- (M.gutter + atlas.zones:Resize(middle)) - (M.gutter + M.row * 2))

	pay.frame:SetSize(PAY, body)
	pay.view:Resize(PAY, body)
	return true
end

function Window.Build()
	if window then
		return window
	end

	window = UI.Window({
		name = "WarriorKitQuests",
		title = "Quest Log",
		width = WIDTH,
		height = HEIGHT,
		zoom = function() return ns.Zoom("questsZoom") end,
		-- The window takes itself back onto the grid and then this lays it out
		-- again, in that order, because every number Fit uses is in the window's
		-- own units and those units are what just changed.
		rescale = function(apply)
			apply()
			Window.Fit()
			Window.Refresh()
		end,
	})
	ns.Remember(window)

	-- The marks on a row are the two things you do to one quest without wanting
	-- to read it first. Handing it to the party is the whole of why a group
	-- quest is in your log at all, and throwing one away is the thing you do to
	-- the four grey ones you will never go back for, neither of which is worth
	-- selecting the quest and crossing the window to the footer.
	--
	-- The share mark is drawn only on the rows the client would take it on. The
	-- cross is drawn on every row, because every quest can be abandoned and the
	-- confirmation is what stands between the mark and the loss.
	list = UI.List(window.content, {
		name = "WarriorKitQuestList",
		onSelect = Select,
		marks = true,
		describe = Company,
		actions = {
			{
				glyph = "s",
				tip = "hand this quest to your party",
				shown = function(key)
					local quest = Log.Quest(key)
					return quest ~= nil and quest.shareable
				end,
				onClick = function(key) Window.Share(key) end,
			},
			{
				glyph = "x",
				tip = "abandon this quest",
				onClick = function(key) Window.Abandon(key) end,
			},
		},
	})
	list.frame:SetPoint("TOPLEFT", M.pad, -M.pad)

	-- The strip sits over the middle column only, and it is the whole of what
	-- says the two sides are the same column rather than two columns: it is as
	-- wide as what is under it and no wider.
	tabs = UI.TabStrip(window.content, { onSelect = function(index)
		facing = index
		Face()
		Window.PaintMap()
	end })
	tabs.frame:SetPoint("TOPLEFT", list.frame, "TOPRIGHT", M.pad, 0)
	tabs:Add("the quest")
	tabs:Add("the map")

	page = Column(window.content, "WarriorKitQuestText")
	page.frame:SetPoint("TOPLEFT", tabs.frame, "BOTTOMLEFT", 0, -M.gutter)

	atlas = Atlas(window.content)
	atlas.frame:SetPoint("TOPLEFT", tabs.frame, "BOTTOMLEFT", 0, -M.gutter)

	pay = Column(window.content, "WarriorKitQuestRewards")
	pay.frame:SetPoint("TOPRIGHT", -M.pad, -M.pad)

	Chrome()
	Window.Fit()
	tabs:Select(facing)
	return window
end

--------------------------------------------------------------------------

function Window.PaintFooter(detail)
	local total, done = Log.Tally()
	window.tally:SetText(("%d quests, %d ready to hand in"):format(total, done))

	local quest = detail and detail.quest
	local shareable = (detail and detail.shareable) and true or false

	window.pin.text:SetText(quest and quest.pinned and "unpin" or "pin")
	window.pin:EnableMouse(quest ~= nil)
	window.pin:SetAlpha(quest and 1 or 0.4)

	window.share:EnableMouse(shareable)
	window.share:SetAlpha(shareable and 1 or 0.4)

	window.abandon:EnableMouse(quest ~= nil)
	window.abandon:SetAlpha(quest and 1 or 0.4)
end

-- Everything the window draws, from the model rather than from the client. The
-- read is taken here, once, so the three columns cannot disagree about which
-- log they are drawing.
function Window.Paint()
	if not window or painting then
		return false
	end
	painting = true

	Log.Read()
	list:Set(Window.Rows())

	-- The quest that was showing may have been handed in, abandoned, or never
	-- picked. Falling back rather than blanking, because an empty middle column
	-- beside a full left one reads as a broken window.
	if not Log.Quest(showing) then
		showing = Log.First()
	end
	list:Select(showing)

	local detail = showing and Log.Detail(showing) or nil
	if detail then
		DrawPage(detail)
		DrawPay(detail)
	else
		Start(page)
		Line(page, { text = "Nothing in your log.", color = C.quiet })
		Finish(page)
		Start(pay)
		Finish(pay)
	end
	DrawMap(detail and detail.quest or nil)

	Window.PaintFooter(detail)
	painting = false
	return true
end

-- The map on its own, for the two things that move it without changing which
-- quest is selected: stepping to another of the quest's zones, and turning the
-- tab over.
--
-- Behind the same latch the whole paint is behind, because drawing the map
-- selects a zone in the strip and selecting one calls back here. Without it the
-- first click on a zone would draw the map twice and read Questie twice to do
-- it.
function Window.PaintMap()
	if not window or painting then
		return false
	end
	painting = true
	local detail = showing and Log.Detail(showing) or nil
	DrawMap(detail and detail.quest or nil)
	painting = false
	return true
end

--------------------------------------------------------------------------
-- The three buttons
--------------------------------------------------------------------------

-- The footer's half of the gesture, for the quest you have open. The other
-- half is the shift click on the row, and both go through Log.Pin so neither
-- can pin a quest the other would not.
function Window.Pin()
	local quest = Log.Quest(showing)
	if not quest then
		return false
	end
	Log.Pin(showing, not Log.Pinned(showing))
	Window.Paint()
	return true
end

-- Both of these take a quest and fall back to the one you are reading, because
-- there are two ways to ask for either: the mark on the row, which names the
-- quest it is on, and the button in the footer, which is about whatever is
-- open in the middle column.
function Window.Share(key)
	key = key or showing
	if not key then
		return false
	end
	local shared = Log.Share(key)
	if not shared then
		ns.Print("this client would not share that quest.")
	end
	return shared
end

-- Puts the question up, and answers whether there was one to ask rather than
-- whether the quest went.
--
-- The name in the question comes from the client's own armed state rather than
-- from the row this window thinks is selected, which is the whole point: if the
-- two ever disagree, the sentence in front of you is what says so before the
-- quest is gone rather than after.
--
-- This used to arm the footer button and abandon on the second press, with a
-- line in the chat window between the two. UI/Ask.lua's header carries why that
-- is not enough. The short of it is that the warning was in a window you may
-- not have been looking at, and the armed state was a button whose label had
-- changed by one word.
function Window.Abandon(key)
	key = key or showing
	local name = key and Log.Abandoning(key)
	if not name then
		ns.Print("this client would not offer that quest up.")
		return false
	end

	UI.Ask({
		title = "Abandon a quest",
		question = ("Abandon %s? Everything you have done towards it goes with it.")
			:format(name),
		accept = "abandon it",
		onAccept = function()
			Log.Abandon(key)
			if key == showing then
				showing = nil
			end
			Window.Paint()
		end,
	})
	return true
end

--------------------------------------------------------------------------

-- What the map drew, as the count of dots on it and the zone it is on. Public
-- for the reason Window.Rows is: a map that put the wrong number of places on
-- the wrong zone is a claim scripts/harness.lua has to be able to make, and the
-- alternative is this file handing out a reference to the board's own pool.
-- How far into the map the wheel has taken it, and a way to turn the wheel from
-- outside. Same argument as Window.Zone below: a zoom that will not move, or
-- one that keeps going past its own far end, is invisible from inside this file
-- and is exactly what a screenshot will not catch either.
function Window.Zoom(delta)
	if not atlas then
		return 1
	end
	if delta then
		atlas.board:Zoom(delta, 0.5, 0.5)
	end
	return atlas.board:Level()
end

function Window.Places()
	if not atlas then
		return 0, nil
	end
	local shown = atlas.board:Drawn()
	return shown, atlas.where:GetText()
end

-- Which quest the middle and right columns are drawing, and a way to ask for
-- another. Handed out for the reason the tab below is: driving the left column
-- by reaching into the list's own row pool is a test asserting the widget
-- library rather than this window.
function Window.Showing(key)
	if key and Log.Quest(key) then
		Select(key)
	end
	return showing
end

-- Which side of the tab is up, and a way to ask for the other one. The harness
-- drives the strip through this rather than through its own buttons, the way
-- the mail window's pages are driven: reaching into a widget's pool from
-- outside is a test asserting the widget library rather than this window.
function Window.Tab(index)
	if index and tabs then
		tabs:Select(index)
	end
	return facing
end

-- Press one of the marks on a quest's own row, and answer whether there was one
-- to press.
--
-- Same argument as the tab and the zone below: driving the column by reaching
-- into the list's own pool is a test asserting the widget library rather than
-- this window. There is a second reason here. The share mark is drawn only on
-- the rows the client would take it on, so "is it there" is half of what the
-- mark is, and a test that called this file's own closure would never ask.
function Window.Press(key, at)
	return list ~= nil and list:Act(key, at)
end

-- Click a quest's own row, with whatever the client says is held down.
--
-- The row's button rather than this file's Select, for the reason above and
-- for one of its own: the pin is a shift left click, and the modifier is read
-- off the client inside the widget's handler. A test that called Select with
-- the arguments it expected would assert the branch and never the wiring, and
-- the wiring is where a gesture goes missing.
function Window.Click(key, which)
	return list ~= nil and list:Click(key, which)
end

-- Which of the quest's zones the map is on, and a way to step to another. Same
-- argument as the tab above, and one more: the strip under the map is drawn
-- only where there is a choice, so a test that clicked it could not reach the
-- one-zone case at all.
function Window.Zone(index)
	if index and atlas then
		atlas.zones:Select(index)
	end
	return zoneAt
end

function Window.Built()
	return window ~= nil
end

function Window.Shown()
	return window ~= nil and window:IsShown()
end

function Window.Show()
	Window.Build()
	Window.Paint()
	window:Show()
	return true
end

function Window.Hide()
	if not window then
		return false
	end
	window:Hide()
	return true
end

function Window.Toggle()
	if Window.Shown() then
		return Window.Hide()
	end
	return Window.Show()
end

-- Redrawn only while it is up. Every event below fires whether or not anybody
-- is looking at the log, and reading sixty rows and three borrows of the quest
-- cursor to update a window nobody has open is the waste this addon has a gate
-- for.
function Window.Refresh()
	if Window.Shown() then
		return Window.Paint()
	end
	return false
end

-- Questie's quest updates, hung off the same paint as a second source.
--
-- The four events below are the client's and they are the wrong grain.
-- QUEST_LOG_UPDATE is not the log changing: it is the client saying it looked,
-- several times a second while you are killing things, and Quests/Where.lua's
-- one-second slot at the top of Soonest is what that already cost once.
-- Questie's fires four times a quest, on accept, update, turn-in and abandon.
--
-- What it buys is the order the right column is drawn in. Two of its three
-- lines are Questie's answers, and Questie works those out off the same client
-- events this file listens to, so the redraw the client asks for is a redraw
-- taken before the other addon has finished thinking. This one arrives after,
-- which is the only moment "who takes this back" and "how far to the nearest
-- one left" are the new answers rather than the previous quest's.
--
-- The client's four stay. Questie may not be installed, may be v6, and may be
-- twenty seconds from compiling its database at the moment you press L, and a
-- quest log that redraws only when another addon says so is a blank window on
-- all three. This sharpens the first source; it does not replace it.
--
-- The three arguments go unread. Questie hands over the quest id, an objective
-- index and one of Questie.API.Enums.QuestUpdateTriggerReason, and all four of
-- those reasons change what the left column says, so there is no reason to
-- refuse any of them and no partial repaint to spend one on.
--
-- Readiness is the one question this addon does not probe again for. The rule
-- at ns.Questie is that nothing about Questie is cached, because the database
-- compiles minutes after login and an answer taken before it is wrong for the
-- rest of the session; RegisterOnReady is that same argument answered from the
-- other end, by the database itself, once, at the moment it finishes.
function Window.Attach()
	local ready = ns.QuestieAPI("RegisterOnReady")
	if not ready then
		return false
	end
	ready.RegisterOnReady(function()
		local updates = ns.QuestieAPI("RegisterForQuestUpdates")
		if not updates then
			return
		end
		updates.RegisterForQuestUpdates(function()
			Window.Refresh()
		end)
	end)
	return true
end

function Window.Describe()
	if not ns.db.quests then
		return "off"
	end
	if not window then
		return "not built yet"
	end
	return Window.Shown() and "open" or "closed"
end

--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_WATCH_UPDATE")
events:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		if ns.db.quests then
			Window.Build()
		end
		-- The cage and the key go on at login rather than when this window
		-- first opens, and that is the difference between this part and the mail
		-- window. Blizzard's log has to be gone before anything can put it on
		-- the screen, and L has to open this one before the first press.
		--
		-- Questie's tracker goes on here for a third reason: the function it
		-- swaps belongs to another addon, and at load there is no promise that
		-- addon has loaded yet.
		ns.QuestBlizzard.Apply()
		ns.QuestTracker.Apply()
		-- And the quest updates for the reason the line above it is here.
		-- The list this puts a callback on is on that addon's own global,
		-- and login is the first moment anything promises the global is
		-- there.
		Window.Attach()
		return
	end
	Window.Refresh()
end)

